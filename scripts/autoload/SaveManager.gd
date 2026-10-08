extends Node
## SaveManager — versioned, validated, atomically-written persistence for all player state.
##
## Design rules (Stage 1 hardening):
##  1. Saves are VERSIONED. Every load runs a migration chain up to SAVE_VERSION.
##  2. Saves are VALIDATED on load. A structurally broken save is never loaded silently.
##  3. Writes are ATOMIC: serialise -> write temp -> re-parse temp to prove it is readable
##     -> rotate the previous good save to the backup slot -> rename temp over the live save.
##     A crash mid-write therefore leaves the previous save intact.
##  4. A broken save is PRESERVED (quarantined to a timestamped file) and reported. The game
##     never silently replaces it with a fresh character.
##  5. Derived data (aggregated modifier cache, resolved stats) is NOT persisted. Every
##     subsystem re-derives it in deserialize()/_reapply(), which removes a whole class of
##     save/state desync bugs.
##
## Derived modifier state was stored by save format 1. Migration drops it; the owning
## managers re-register their sources when EventBus.game_loaded fires.

const SAVE_PATH: String = "user://save_game.json"
const BACKUP_PATH: String = "user://save_game.backup.json"
const TEMP_PATH: String = "user://save_game.json.tmp"
const QUARANTINE_TEMPLATE: String = "user://save_game.corrupt_%d.json"
## A save preserved immediately BEFORE a migration. Kept separate from the "corrupt" name
## because a migrated file was never broken — it was simply an older format.
const PREMIGRATION_TEMPLATE: String = "user://save_game.premigration_%d.json"
const LOCK_PATH: String = "user://save_session.lock"

## Project names this game shipped under before it became Emberreach. `user://` follows the
## project name, so a rename would otherwise hide the player's existing save entirely. These
## are checked once, and any save found there is COPIED in — never moved, never deleted.
const LEGACY_APP_NAMES: Array[String] = ["Melvor Idle Clone", "melvor-clone-godot"]

const SAVE_VERSION: int = 2
const AUTOSAVE_INTERVAL: float = 60.0
const MAX_AUTOSAVE_INTERVAL: float = 600.0
## The cadences Settings → Saves offers, in seconds. The list is deliberately short and
## ascending: a shorter interval protects progress more, a longer one writes to disk less.
const AUTOSAVE_CHOICES: Array[float] = [30.0, 60.0, 120.0, 300.0]

## Sections that must be Dictionaries for a save to be considered loadable.
const REQUIRED_SECTIONS: Array[String] = ["player", "bank", "equipment"]

enum LoadOutcome { NONE, LOADED, MIGRATED, RECOVERED, FAILED }

signal load_failed(reason: String, detail: String)

var last_save_unix: int = 0
var last_save_ok: bool = true
var save_on_major_event: bool = true
var autosave_enabled: bool = true
## The cadence in force. get_autosave_interval() re-derives it from the setting on every tick, so
## a load or a reset cannot leave the timer running on a value the player never chose.
var autosave_interval: float = AUTOSAVE_INTERVAL

## Populated when a load fails so the shell can offer recovery instead of a blank game.
var pending_recovery: Dictionary = {}   # {reason, detail, quarantine_path, backup_ok}
var last_outcome: int = LoadOutcome.NONE

## Set when the save was adopted from the old project directory, so the UI can say so.
var legacy_adopted_from: String = ""

var _autosave_timer: float = 0.0
var _write_in_progress: bool = false
var _session_id: String = ""

func _ready() -> void:
	_session_id = "%d-%d" % [OS.get_process_id(), int(Time.get_unix_time_from_system())]
	_adopt_legacy_save()
	EventBus.skill_level_up.connect(func(_s, _l): _save_on_event())
	EventBus.dungeon_completed.connect(func(_d): _save_on_event())
	EventBus.player_died.connect(func(_c): _save_on_event())
	EventBus.pet_unlocked.connect(func(_p): _save_on_event())
	EventBus.quest_completed.connect(func(_q): _save_on_event())
	EventBus.achievement_unlocked.connect(func(_a): _save_on_event())

func _process(delta: float) -> void:
	# While the recovery screen waits for a decision the save is not ours to touch: the live slot
	# holds the corrupt file and the backup is the only good copy.
	if not autosave_enabled or GameManager.boot_state == GameManager.BootState.LOAD_FAILED:
		return
	# Offline catch-up runs over several frames with the world only partially simulated. Writing
	# now — and advancing the marker to "now" — would persist a half-applied sim and discard the
	# unprocessed remainder of the offline window. Every passive manager already defers on this;
	# the autosave timer must too. The marker is advanced by the catch-up itself when it finishes.
	if OfflineProgression.is_running:
		return
	_autosave_timer += delta
	if _autosave_timer >= get_autosave_interval():
		_autosave_timer = 0.0
		# The offline marker must track the last persisted moment, or a save written now still
		# claims the whole session is unclaimed and the next launch pays it out a second time.
		# Only advance it once the write actually succeeded, so a failed/partial write cannot leave
		# the marker ahead of the last durable save and silently drop the window in between.
		var previous_marker: int = PlayerData.last_offline_unix
		PlayerData.last_offline_unix = int(Time.get_unix_time_from_system())
		if not save_game():
			PlayerData.last_offline_unix = previous_marker

func _save_on_event() -> void:
	if save_on_major_event and not _write_in_progress:
		save_game(true)

## Adopt the player's chosen cadence. The value is clamped here rather than at the UI because it
## arrives from a save file: an old or hand-edited save must not be able to stall the autosave
## or hammer the disk once per frame.
func set_autosave_interval(seconds: float) -> void:
	autosave_interval = clampf(seconds, AUTOSAVE_CHOICES[0], MAX_AUTOSAVE_INTERVAL)
	PlayerData.settings["autosave_interval"] = autosave_interval
	_autosave_timer = 0.0

## The cadence in force, re-read from the live settings so a save load or a reset cannot leave
## the timer running on a stale value.
func get_autosave_interval() -> float:
	var wanted: float = clampf(float(PlayerData.settings.get("autosave_interval", AUTOSAVE_INTERVAL)),
		AUTOSAVE_CHOICES[0], MAX_AUTOSAVE_INTERVAL)
	if not is_equal_approx(wanted, autosave_interval):
		autosave_interval = wanted
	return autosave_interval

# =========================================================================
#  Save
# =========================================================================

func build_save_data() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"timestamp": int(Time.get_unix_time_from_system()),
		"session": _session_id,
		"game_mode": PlayerData.game_mode,
		"player": PlayerData.serialize(),
		"settings": PlayerData.settings,
		"mastery": MasteryManager.serialize(),
		"bank": BankManager.serialize(),
		"loot_filters": LootFilterManager.serialize(),
		"equipment": EquipmentManager.serialize(),
		"active_action": SkillManager.serialize(),
		"action_queue": ActionQueueManager.serialize(),
		"combat_state": CombatManager.serialize(),
		"farming_plots": FarmingManager.serialize(),
		"township": TownshipManager.serialize(),
		"ranching": RanchingManager.serialize(),
		"inscription": InscriptionManager.serialize(),
		"engineering": EngineeringManager.serialize(),
		"caravaneering": CaravaneeringManager.serialize(),
		"enchanting": EnchantingManager.serialize(),
		"dreamwalking": DreamwalkingManager.serialize(),
		"slayer": SlayerManager.serialize(),
		"agility": AgilityManager.serialize(),
		"summoning": SummoningManager.serialize(),
		"astrology": AstrologyManager.serialize(),
		"cartography": CartographyManager.serialize(),
		"archaeology": ArchaeologyManager.serialize(),
		"raid": RaidManager.serialize(),
		"quests": Quests.serialize(),
		"achievements": Achievements.serialize(),
		"goals": Goals.serialize(),
		"prestige": PrestigeManager.serialize(),
		"tutorial": TutorialManager.serialize(),
	}

## Returns true when the save reached disk and re-read cleanly.
func save_game(_reason_is_major: bool = false) -> bool:
	if _write_in_progress:
		# Duplicate submission guard: a save already owns the write slot.
		return false
	# A half-applied catch-up must never reach disk with the old marker, or the next launch replays
	# the window. The catch-up saves itself once it finishes.
	if OfflineProgression.is_running:
		return false
	_write_in_progress = true
	EventBus.save_status.emit("saving", "Saving…")

	var data: Dictionary = build_save_data()
	var text: String = JSON.stringify(data, "\t")
	var ok: bool = _atomic_write(text)
	_write_in_progress = false

	last_save_ok = ok
	if ok:
		last_save_unix = int(Time.get_unix_time_from_system())
		EventBus.game_saved.emit()
		EventBus.save_status.emit("ok", "Saved %s" % _clock_string())
	else:
		EventBus.save_status.emit("error", "Save failed — progress is not on disk")
	return ok

func _atomic_write(text: String) -> bool:
	# 1) Write the new payload to a temp file and prove it parses back.
	var f := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot open temp save for writing")
		return false
	f.store_string(text)
	f.close()
	if not _file_parses(TEMP_PATH):
		push_error("SaveManager: temp save failed verification; live save left untouched")
		_remove_file(TEMP_PATH)
		return false

	# 2) Rotate the current good save into the backup slot.
	if FileAccess.file_exists(SAVE_PATH):
		_remove_file(BACKUP_PATH)
		DirAccess.copy_absolute(_abs(SAVE_PATH), _abs(BACKUP_PATH))

	# 3) Move temp over the live save.
	_remove_file(SAVE_PATH)
	var err: int = DirAccess.rename_absolute(_abs(TEMP_PATH), _abs(SAVE_PATH))
	if err != OK:
		push_error("SaveManager: rename failed with error %d" % err)
		return false
	return true

func _file_parses(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	if text.strip_edges() == "":
		return false
	return typeof(JSON.parse_string(text)) == TYPE_DICTIONARY

func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)

func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(_abs(path))

func _clock_string() -> String:
	var t: Dictionary = Time.get_time_dict_from_system()
	return "%02d:%02d:%02d" % [int(t.get("hour", 0)), int(t.get("minute", 0)), int(t.get("second", 0))]

# =========================================================================
#  Load
# =========================================================================

## One-time rescue of a save that lives under a previous project name.
func _adopt_legacy_save() -> void:
	if has_save():
		return
	var parent: String = OS.get_user_data_dir().get_base_dir()
	for legacy_name in LEGACY_APP_NAMES:
		var folder: String = parent.path_join(legacy_name)
		var candidate: String = folder.path_join("save_game.json")
		if not FileAccess.file_exists(candidate):
			continue
		DirAccess.copy_absolute(candidate, _abs(SAVE_PATH))
		var old_backup: String = folder.path_join("save_game.backup.json")
		if FileAccess.file_exists(old_backup) and not has_backup():
			DirAccess.copy_absolute(old_backup, _abs(BACKUP_PATH))
		legacy_adopted_from = candidate
		push_warning("SaveManager: adopted the save from the previous project folder: %s" % candidate)
		EventBus.save_status.emit("recovered", "Imported your save from the previous version")
		return

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func has_backup() -> bool:
	return FileAccess.file_exists(BACKUP_PATH)

func load_game() -> bool:
	last_outcome = LoadOutcome.NONE
	pending_recovery.clear()
	if not has_save():
		return false

	var raw: Variant = _read_json(SAVE_PATH)
	var problems: Array = validate_save(raw)
	if not problems.is_empty():
		return _attempt_recovery(problems)

	var data: Dictionary = raw
	var from_version: int = detect_version(data)
	var migrated: bool = from_version < SAVE_VERSION
	var keep: String = ""
	if migrated:
		# Preserve the exact original before touching it.
		keep = PREMIGRATION_TEMPLATE % int(Time.get_unix_time_from_system())
		DirAccess.copy_absolute(_abs(SAVE_PATH), _abs(keep))
		data = migrate_save(data, from_version)

	_apply(data)
	if migrated:
		_last_migration_note = "migrated v%d -> v%d (original preserved at %s)" % [from_version, SAVE_VERSION, keep]
	else:
		_last_migration_note = ""
	last_outcome = LoadOutcome.MIGRATED if migrated else LoadOutcome.LOADED
	_claim_session_lock()
	EventBus.game_loaded.emit()
	if migrated:
		EventBus.save_recovered.emit(_last_migration_note)
		save_game()   # persist the upgraded format immediately
	return true

var _last_migration_note: String = ""

func get_migration_note() -> String:
	return _last_migration_note

## Structural validation. Returns a list of human-readable problems (empty == loadable).
func validate_save(raw: Variant) -> Array:
	var problems: Array = []
	if typeof(raw) != TYPE_DICTIONARY:
		problems.append("save root is not a JSON object")
		return problems
	var data: Dictionary = raw
	if data.is_empty():
		problems.append("save root is empty")
		return problems
	for section in REQUIRED_SECTIONS:
		if not data.has(section):
			problems.append("missing required section '%s'" % section)
		elif typeof(data[section]) != TYPE_DICTIONARY:
			problems.append("section '%s' is not an object (found %s)" % [section, type_string(typeof(data[section]))])
	var version: int = detect_version(data)
	if version <= 0:
		problems.append("missing or unreadable save version")
	elif version > SAVE_VERSION:
		problems.append("save version %d is newer than this build (%d)" % [version, SAVE_VERSION])
	if problems.is_empty():
		var player: Dictionary = data.get("player", {})
		if not player.has("skills"):
			problems.append("player.skills missing")
		elif typeof(player["skills"]) != TYPE_DICTIONARY or (player["skills"] as Dictionary).is_empty():
			problems.append("player.skills is empty — all skill state would be lost")
	return problems

## 0 means "unidentifiable".
func detect_version(data: Dictionary) -> int:
	if data.has("save_version"):
		return int(data["save_version"])
	if data.has("version"):
		# Format 1 stored a semantic string.
		var v: String = str(data["version"])
		if v.begins_with("1."):
			return 1
		return 1
	# Format 1 is the only format that ever shipped without a version key.
	if data.has("player") and (data["player"] as Dictionary).has("skills"):
		return 1
	return 0

## Forward-only migration chain. Each step is a small, documented transform.
func migrate_save(data: Dictionary, from_version: int) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	var v: int = from_version
	if v < 2:
		out = _migrate_1_to_2(out)
		v = 2
	out["save_version"] = SAVE_VERSION
	out.erase("version")
	return out

## v1 -> v2
##  - drop the persisted modifier cache (derived state; managers re-derive on load)
##  - introduce player.last_offline_unix so offline gains are applied exactly once
##  - guarantee every settings key the gameplay code reads exists
func _migrate_1_to_2(data: Dictionary) -> Dictionary:
	data.erase("modifiers")
	var settings_note: Dictionary = data.get("settings", {})
	var player: Dictionary = data.get("player", {})
	var settings: Dictionary = player.get("settings", settings_note)
	for key in SettingsDefaults.DEFAULTS.keys():
		if not settings.has(key):
			settings[key] = SettingsDefaults.DEFAULTS[key]
	player["settings"] = settings
	data["settings"] = settings
	if not player.has("last_offline_unix"):
		player["last_offline_unix"] = int(data.get("timestamp", 0))
	player["save_format_history"] = _append_format_history(player.get("save_format_history", []), 1)
	data["player"] = player
	return data

func _append_format_history(history: Variant, version: int) -> Array:
	var out: Array = history if typeof(history) == TYPE_ARRAY else []
	if not out.has(version):
		out.append(version)
	if not out.has(SAVE_VERSION):
		out.append(SAVE_VERSION)
	return out

## A broken live save is quarantined and reported — never silently discarded.
func _attempt_recovery(problems: Array) -> bool:
	var detail: String = "; ".join(problems)
	push_error("SaveManager: save rejected — %s" % detail)
	var quarantine: String = QUARANTINE_TEMPLATE % int(Time.get_unix_time_from_system())
	DirAccess.copy_absolute(_abs(SAVE_PATH), _abs(quarantine))
	pending_recovery = {
		"reason": "Save file failed validation",
		"detail": detail,
		"quarantine_path": quarantine,
		"backup_ok": has_backup(),
	}
	# Try the backup automatically; the player is told which file was used.
	if has_backup():
		var backup_raw: Variant = _read_json(BACKUP_PATH)
		if validate_save(backup_raw).is_empty():
			var backup_data: Dictionary = backup_raw
			var bv: int = detect_version(backup_data)
			if bv < SAVE_VERSION:
				backup_data = migrate_save(backup_data, bv)
			_apply(backup_data)
			last_outcome = LoadOutcome.RECOVERED
			pending_recovery["recovered"] = true
			EventBus.save_status.emit("recovered", "Restored backup save (previous file kept at %s)" % quarantine)
			EventBus.game_loaded.emit()
			return true
		pending_recovery["backup_error"] = "; ".join(validate_save(backup_raw))
	load_failed.emit(pending_recovery["reason"], detail)
	EventBus.save_status.emit("blocked", "Save could not be loaded: %s" % detail)
	last_outcome = LoadOutcome.FAILED
	return false

## Stage a recovery that the shell can offer to the player explicitly.
func start_fresh_after_failure() -> void:
	pending_recovery.clear()

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	if text.strip_edges() == "":
		return null
	return JSON.parse_string(text)

func _apply(data: Dictionary) -> void:
	# Every subsystem tolerates a missing section; each re-derives its own modifiers.
	GameManager.clear_derived_modifiers()
	PlayerData.deserialize(data.get("player", {}))
	PlayerData.settings.merge(data.get("settings", {}), false)
	MasteryManager.deserialize(data.get("mastery", {}))
	# Restore derived equipment definitions before bank and equipment lookups.
	EnchantingManager.deserialize(data.get("enchanting", {}))
	RanchingManager.deserialize(data.get("ranching", {}))
	InscriptionManager.deserialize(data.get("inscription", {}))
	EngineeringManager.deserialize(data.get("engineering", {}))
	CaravaneeringManager.deserialize(data.get("caravaneering", {}))
	DreamwalkingManager.deserialize(data.get("dreamwalking", {}))
	BankManager.deserialize(data.get("bank", {}))
	EquipmentManager.deserialize(data.get("equipment", {}))
	SkillManager.deserialize(data.get("active_action", {}))
	ActionQueueManager.deserialize(data.get("action_queue", {}))
	# After the bank, so the rules exist before anything could act on them.
	LootFilterManager.deserialize(data.get("loot_filters", {}))
	CombatManager.deserialize(data.get("combat_state", {}))
	FarmingManager.deserialize(data.get("farming_plots", {}))
	TownshipManager.deserialize(data.get("township", {}))
	SlayerManager.deserialize(data.get("slayer", {}))
	AgilityManager.deserialize(data.get("agility", {}))
	SummoningManager.deserialize(data.get("summoning", {}))
	AstrologyManager.deserialize(data.get("astrology", {}))
	CartographyManager.deserialize(data.get("cartography", {}))
	ArchaeologyManager.deserialize(data.get("archaeology", {}))
	RaidManager.deserialize(data.get("raid", {}))
	Quests.deserialize(data.get("quests", {}))
	Achievements.deserialize(data.get("achievements", {}))
	Goals.deserialize(data.get("goals", {}))
	PrestigeManager.deserialize(data.get("prestige", {}))
	TutorialManager.deserialize(data.get("tutorial", {}))
	# One call, one place: every path that restores a save — load, migration, backup recovery and
	# import — funnels through _apply, so the persisted speed and save cadence cannot survive in
	# the file while a different value stays live in the autoloads.
	GameManager.apply_session_settings()

func delete_save() -> void:
	_remove_file(SAVE_PATH)
	_remove_file(BACKUP_PATH)
	_remove_file(TEMP_PATH)

# =========================================================================
#  Export / import
# =========================================================================

func export_save_to(path: String) -> Dictionary:
	var text: String = JSON.stringify(build_save_data(), "\t")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "reason": "cannot write to %s" % path}
	f.store_string(text)
	f.close()
	return {"ok": true, "reason": ""}

func import_save_from(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "file not found"}
	var raw: Variant = _read_json(path)
	var problems: Array = validate_save(raw)
	if not problems.is_empty():
		return {"ok": false, "reason": "; ".join(problems)}
	var data: Dictionary = raw
	var v: int = detect_version(data)
	if v < SAVE_VERSION:
		data = migrate_save(data, v)
	_apply(data)
	EventBus.game_loaded.emit()
	save_game()
	return {"ok": true, "reason": ""}

# =========================================================================
#  Concurrency guard (best effort — documented as advisory, not a security boundary)
# =========================================================================

func _claim_session_lock() -> void:
	var f := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"session": _session_id, "unix": int(Time.get_unix_time_from_system())}))
	f.close()

## True when another process wrote the lock within the last two minutes.
func other_session_active() -> bool:
	var raw: Variant = _read_json(LOCK_PATH)
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = raw
	if str(d.get("session", "")) == _session_id:
		return false
	return int(Time.get_unix_time_from_system()) - int(d.get("unix", 0)) < 120

func get_last_timestamp(data: Dictionary = {}) -> float:
	return float(data.get("timestamp", 0.0))

func save_health() -> Dictionary:
	return {
		"exists": has_save(),
		"backup": has_backup(),
		"last_save_unix": last_save_unix,
		"last_save_ok": last_save_ok,
		"version": SAVE_VERSION,
		"session_active_elsewhere": other_session_active(),
		"adopted_from": legacy_adopted_from,
	}
