extends Node
## GameManager — boot orchestration, playtime, pause/speed, and the single-activity rule.
##
## BOOT STATES (this is the part Stage 1 hardened):
##   "new"         — no save exists; a fresh character starts immediately.
##   "loaded"      — the save loaded; offline catch-up is scheduled.
##   "load_failed" — a save exists but could not be loaded or recovered. The game does NOT
##                   silently start a new character over the top of it. The shell shows the
##                   recovery panel and waits for an explicit decision.
##
## ACTIVITY CAPACITY (explicit, single slot):
##   Exactly one activity occupies the main slot at a time: either a skill action or a fight.
##   Combat refuses to begin while an action is running only if the player has not been asked;
##   instead the activity is stopped with a stated reason and the event log records it. A skill
##   action cannot start during a fight and says so, so nothing is cancelled behind the
##   player's back and a queue can never act as a second worker.

enum BootState { NEW, LOADED, LOAD_FAILED }

var is_paused: bool = false
var game_speed: float = 1.0
var playtime_seconds: float = 0.0
var boot_state: int = BootState.NEW
## Set by the headless CLI entry points (--tests, --smoke, --offline, …) before anything awaits.
## Those modes drive the singletons deliberately and restore them afterwards, so the normal
## deferred boot must not fire in the middle of a run and load a real save over the test state.
var cli_mode: bool = false

func _ready() -> void:
	process_priority = -10
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	if cli_mode:
		return
	if SaveManager.has_save():
		if SaveManager.load_game():
			boot_state = BootState.LOADED
			_validate_content_quietly()
			OfflineProgression.run_on_load()
			return
		# Recovery already attempted (backup). Hand the decision to the player.
		boot_state = BootState.LOAD_FAILED
		EventBus.notification.emit("Save could not be loaded — see the recovery panel.", "error")
		return
	boot_state = BootState.NEW
	start_new_game(str(PlayerData.game_mode))

func _validate_content_quietly() -> void:
	if not OS.is_debug_build():
		return
	var report: Array = ContentValidator.new().validate_all()
	var errors: int = 0
	for i in report:
		if i["severity"] == "error":
			errors += 1
			push_error("content: %s" % i["message"])
	if errors > 0:
		EventBus.content_validation_report.emit(report)

# =========================================================================
#  New game / recovery
# =========================================================================

## Reset EVERY subsystem to its starting state. Both a brand-new game and a confirmed progress
## reset go through here, so a reset can never leave a stale modifier, quest flag or settlement
## structure behind. Preferences in PlayerData.settings are preserved.
func start_new_game(mode: String) -> void:
	if not DataLoader.game_modes.has(mode):
		mode = "standard"
	PlayerData.game_mode = mode
	PlayerData.initialize_new_game()
	PlayerData.settings = SettingsDefaults.with_defaults(PlayerData.settings)
	BankManager.deserialize({})
	LootFilterManager.deserialize({})
	EquipmentManager.deserialize({})
	MasteryManager.deserialize({})
	CombatManager.deserialize({})
	SkillManager.deserialize({})
	ActionQueueManager.deserialize({})
	CombatSimulatorManager.invalidate()
	FarmingManager.deserialize({})
	TownshipManager.deserialize({})
	RanchingManager.deserialize({})
	InscriptionManager.deserialize({})
	EngineeringManager.deserialize({})
	CaravaneeringManager.deserialize({})
	EnchantingManager.deserialize({})
	DreamwalkingManager.deserialize({})
	SlayerManager.deserialize({})
	AgilityManager.deserialize({})
	SummoningManager.deserialize({})
	AstrologyManager.deserialize({})
	CartographyManager.deserialize({})
	ArchaeologyManager.deserialize({})
	RaidManager.deserialize({})
	PetManager.deserialize({})
	Quests.deserialize({})
	Achievements.deserialize({})
	Goals.deserialize({})
	SkillManager.stop_action(SkillManager.StopReason.PLAYER)
	CombatManager.stop_combat("new game")
	# Clear every derived modifier category; each owning manager re-registers its own sources.
	# "prestige" is deliberately absent: an ascension's bonus must survive the reset it bought,
	# and PrestigeManager re-registers it from PlayerData.prestige.
	clear_derived_modifiers()
	ProgressTracker.mark_dirty(true)
	boot_state = BootState.NEW
	# A reset keeps the player's preferences (including their chosen speed and save cadence), so
	# the session clocks have to be re-read from them rather than left on stale values.
	apply_session_settings()
	EventBus.state_refreshed.emit()
	EventBus.notification.emit("New journey started (%s)" % mode, "success")

## Drop every derived modifier source; each owning manager re-registers its own on deserialize.
## Also used before restoring a save, so an import cannot inherit the previous character's bonuses.
func clear_derived_modifiers() -> void:
	for category in ["prayer", "potion", "shop", "agility", "astrology", "summoning",
			"pet", "poi", "raid", "township", "mastery_item", "equipment", "goals"]:
		ModifierManager.clear_category(category)

## A confirmed "reset all progress": a new game that also drops the Ascendancy, which
## start_new_game keeps because an ascension must survive the reset it buys.
func reset_everything(mode: String) -> void:
	start_new_game(mode)
	PlayerData.prestige = {}
	PrestigeManager._reapply()

## Player-confirmed fresh start after a failed load. The broken file stays quarantined.
func recover_with_new_game() -> void:
	var mode: String = PlayerData.game_mode
	SaveManager.start_fresh_after_failure()
	start_new_game(mode)
	SaveManager.save_game()

# =========================================================================
#  Loop
# =========================================================================

func _process(delta: float) -> void:
	if is_paused or boot_state == BootState.LOAD_FAILED:
		return
	var scaled: float = delta / maxf(0.001, Engine.time_scale)
	playtime_seconds += scaled
	PlayerData.playtime_seconds = playtime_seconds

func set_paused(p: bool) -> void:
	is_paused = p
	EventBus.activity_changed.emit()

func set_speed(s: float) -> void:
	game_speed = clampf(s, 0.25, 16.0)
	# Every simulation reads delta from _process, so the engine's own scale is the one place
	# that moves every consumer. Scaling playtime alone left the speed control inert.
	Engine.time_scale = game_speed
	# The setting is the single source of truth, so the top bar and the Settings screen are
	# two views of one value rather than two independent controls that can disagree.
	PlayerData.settings["game_speed"] = game_speed
	EventBus.game_speed_changed.emit(game_speed)

## Re-apply the persisted speed and save cadence after a load, an import or a reset. Called by
## the systems that change those settings wholesale, not by the UI, which writes them directly.
func apply_session_settings() -> void:
	set_speed(float(PlayerData.settings.get("game_speed", 1.0)))
	SaveManager.set_autosave_interval(float(PlayerData.settings.get("autosave_interval", SaveManager.AUTOSAVE_INTERVAL)))

## Called on app quit / menu exit.
func save_and_quit() -> void:
	SaveManager.save_game()

func boot_state_name() -> String:
	match boot_state:
		BootState.LOADED: return "loaded"
		BootState.LOAD_FAILED: return "load_failed"
	return "new"

# =========================================================================
#  Activity slot (single activity rule)
# =========================================================================

## True when a fight is in progress and would block a skill action.
func activity_blocked_by_combat() -> bool:
	return CombatManager.state != CombatManager.State.IDLE

## The player's explicit "stop what you are doing and start this" action.
func request_skill_action(skill_id: String, action_id: String, target: int = 0, manual: bool = true) -> bool:
	if manual:
		ActionQueueManager.pause("Manual activity started")
	if activity_blocked_by_combat():
		CombatManager.stop_combat("retreat")
		if not SimulationMode.is_silent():
			EventBus.notification.emit("Retreated from combat.", "info")
	return SkillManager.start_action(skill_id, action_id, target)

func request_combat(ctx: Dictionary, manual: bool = true) -> bool:
	if str(ctx.get("type", "")) == "dungeon" and CombatManager.is_expedition(str(ctx.get("id", ""))):
		var reason: String = CombatManager.expedition_unlock_reason()
		if reason != "":
			EventBus.notify("Expedition locked: %s" % reason, "warn")
			return false
	if manual:
		ActionQueueManager.pause("Manual activity started")
	if SkillManager.running:
		SkillManager.stop_action(SkillManager.StopReason.PLAYER, "Combat began")
	return CombatManager.start_combat(ctx)

## One-line description of what the character is currently doing, for the activity strip.
func current_activity() -> Dictionary:
	if CombatManager.state == CombatManager.State.FIGHTING:
		var m: Dictionary = DataLoader.get_monster(CombatManager.current_monster_id)
		return {
			"kind": "combat",
			"label": "Fighting %s" % str(m.get("name", "an enemy")),
			"detail": "HP %d / %d" % [int(CombatManager.player_hp), int(CombatManager._compute_max_hp())],
			"screen": "expeditions" if CombatManager.is_expedition(str(CombatManager.context.get("id", ""))) else "combat",
			"id": str(CombatManager.context.get("id", "")),
			"progress": 1.0 - float(CombatManager.monster_hp) / maxf(1.0, float(CombatManager.monster_max_hp)),
		}
	if CombatManager.state == CombatManager.State.RESPAWNING:
		return {"kind": "combat", "label": "Waiting for the next enemy", "detail": "",
			"screen": "expeditions" if CombatManager.is_expedition(str(CombatManager.context.get("id", ""))) else "combat", "id": str(CombatManager.context.get("id", "")), "progress": 0.0}
	if SkillManager.running:
		var data: Dictionary = SkillManager.get_action_data()
		var skill: Dictionary = DataLoader.get_skill(SkillManager.active_skill)
		return {
			"kind": "skill",
			"label": "%s · %s" % [str(skill.get("name", SkillManager.active_skill)), str(data.get("name", SkillManager.active_action_id))],
			"detail": "%s · %.1fs" % [("×%d" % SkillManager.repeat_target) if SkillManager.repeat_target > 0 else "repeating",
				SkillManager.current_interval],
			"screen": "skill",
			"id": SkillManager.active_skill,
			"action_id": SkillManager.active_action_id,
			"progress": clampf(SkillManager.progress / maxf(SkillManager.current_interval, 0.001), 0.0, 1.0),
		}
	if SkillManager.stop_reason != SkillManager.StopReason.NONE and SkillManager.stop_reason_text() != "":
		return {"kind": "stopped", "label": "Idle", "detail": SkillManager.stop_reason_text(),
			"screen": "overview", "id": "", "progress": 0.0}
	return {"kind": "idle", "label": "Idle", "detail": "Choose an activity", "screen": "overview", "id": "", "progress": 0.0}
