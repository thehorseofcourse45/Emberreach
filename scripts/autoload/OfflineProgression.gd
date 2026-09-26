extends Node
## OfflineProgression — turns elapsed wall-clock time into simulated progress using the SAME
## authoritative simulation as online play (SkillManager.tick / CombatManager.tick).
##
## Guarantees:
##  1. EXACTLY ONCE. Progress is measured from PlayerData.last_offline_unix, which is advanced
##     and persisted immediately when catch-up finishes. Closing the game before an autosave
##     can no longer replay the same offline window.
##  2. BOUNDED. The catch-up runs across frames under a millisecond budget instead of one
##     blocking loop, so a 24-hour gap never freezes the interface.
##  3. HONEST. The summary reports time processed, time excluded by the cap, what stopped,
##     and the resulting deltas — all read from real state, never estimated for display.
##  4. ONE ACTIVITY SLOT. Skills and combat are mutually exclusive; offline processes whichever
##     is currently active, exactly like online play.
##  5. CONSISTENT CLOCKS. A negative delta (clock moved backwards) grants nothing and reports
##     the anomaly instead of inventing progress.

const MIN_ELAPSED_SECONDS: float = 5.0
const DEFAULT_CAP_HOURS: float = 24.0
const MIN_CAP_HOURS: float = 1.0
const MAX_CAP_HOURS: float = 168.0
## Simulated seconds processed per outer chunk, so the progress indicator moves.
# ponytail: 30s is the slice granularity, so a queued "gather until N" can overshoot by at most
# one slice. Thread a target predicate into simulate_elapsed if that ever matters.
const CHUNK_SECONDS: float = 30.0
## Wall-clock budget spent per frame on catch-up before yielding.
const FRAME_BUDGET_MSEC: float = 8.0
const MAX_TOTAL_CHUNKS: int = 5_000

var is_running: bool = false

var _job: Dictionary = {}
var _chunks_done: int = 0
var _last_summary: Dictionary = {}

## Every field the UI and tests may read. Kept stable across formats.
func empty_summary() -> Dictionary:
	return {
		"elapsed_seconds": 0.0,
		"capped_seconds": 0.0,
		"cap_hours": DEFAULT_CAP_HOURS,
		"processed_seconds": 0.0,
		"clock_anomaly": false,
		"activity": "none",           # "skill" | "combat" | "none"
		"skill": "", "action": "", "actions": 0,
		"xp_gained": {}, "levels_gained": {},
		"items_gained": {}, "items_consumed": {},
		"combat": {"kills": 0, "deaths": 0, "dungeons": 0, "kills_by_monster": {}},
		"rare_drops": {}, "pets": [],
		"farming_advanced": 0, "township_ticks": 0,
		"stopped_reason": "",
		"notes": [],
	}

func last_summary() -> Dictionary:
	return _last_summary

# =========================================================================
#  Entry point
# =========================================================================

## Called by GameManager after a successful load. Establishes the elapsed window and starts
## an asynchronous catch-up job. Returns immediately.
func run_on_load() -> Dictionary:
	if is_running:
		return empty_summary()
	var summary: Dictionary = empty_summary()
	var cap_hours: float = clampf(float(PlayerData.settings.get("offline_cap_hours", DEFAULT_CAP_HOURS)),
		MIN_CAP_HOURS, MAX_CAP_HOURS)
	summary["cap_hours"] = cap_hours
	var now: float = Time.get_unix_time_from_system()
	var marker: int = PlayerData.last_offline_unix
	if marker <= 0:
		# First load of an older save: fall back to the save timestamp.
		marker = int(SaveManager.get_last_timestamp(_read_save_root()))
	if marker <= 0:
		PlayerData.last_offline_unix = int(now)
		_last_summary = summary
		return summary
	var raw_delta: float = now - float(marker)
	if raw_delta < 0.0:
		# Clock moved backwards. Grant nothing and do NOT advance the marker, so the player
		# cannot farm progress by rolling the clock back and forth.
		summary["clock_anomaly"] = true
		summary["stopped_reason"] = "System clock moved backwards — no offline progress granted"
		summary["notes"].append("Clock anomaly detected; the offline marker was left untouched.")
		_last_summary = summary
		EventBus.offline_progress_summary.emit(summary)
		EventBus.state_refreshed.emit()
		return summary
	var cap_seconds: float = cap_hours * 3600.0
	var elapsed: float = minf(raw_delta, cap_seconds)
	summary["elapsed_seconds"] = elapsed
	summary["capped_seconds"] = maxf(0.0, raw_delta - elapsed)
	if elapsed < MIN_ELAPSED_SECONDS:
		_advance_marker(now)
		_last_summary = summary
		return summary
	_begin_job(summary, now)
	return summary

func _begin_job(summary: Dictionary, now: float) -> void:
	_job = {
		"summary": summary,
		"target_seconds": float(summary["elapsed_seconds"]),
		"processed": 0.0,
		"now": now,
		"xp_before": _snapshot_xp(),
		"levels_before": _snapshot_levels(),
		"pets_before": PlayerData.unlocked_pets.size(),
	}
	_chunks_done = 0
	is_running = true
	SimulationMode.begin()
	EventBus.offline_catchup_started.emit(float(summary["elapsed_seconds"]))
	EventBus.save_status.emit("saving", "Restoring offline progress…")

func _process(_delta: float) -> void:
	if not is_running:
		return
	var start_usec: int = Time.get_ticks_usec()
	var budget_usec: int = int(FRAME_BUDGET_MSEC * 1000.0)
	while is_running and Time.get_ticks_usec() - start_usec < budget_usec:
		if not _step_chunk():
			break
	if is_running:
		var target: float = maxf(1.0, float(_job["target_seconds"]))
		EventBus.offline_catchup_progress.emit(clampf(float(_job["processed"]) / target, 0.0, 1.0),
			_description_of_activity())

## Process one chunk. Returns false when the job is finished.
func _step_chunk() -> bool:
	if not is_running:
		return false
	var summary: Dictionary = _job["summary"]
	var target: float = float(_job["target_seconds"])
	var processed: float = float(_job["processed"])
	if processed >= target or _chunks_done >= MAX_TOTAL_CHUNKS:
		_finish()
		return false
	_chunks_done += 1
	var slice: float = minf(CHUNK_SECONDS, target - processed)
	# ONE activity slot: combat takes precedence when a fight is in progress, otherwise the
	# selected skill action runs. This mirrors online play exactly.
	if CombatManager.state != CombatManager.State.IDLE:
		if bool(PlayerData.settings.get("offline_combat_enabled", true)):
			var res: Dictionary = CombatManager.simulate_elapsed(slice)
			ActionQueueManager.after_simulation_slice()
			summary["activity"] = "combat"
			processed += float(res["seconds_processed"])
			if bool(res["stopped"]):
				summary["stopped_reason"] = str(res["reason"])
				_job["processed"] = processed
				_finish()
				return false
		else:
			summary["activity"] = "combat"
			summary["stopped_reason"] = "Offline combat is disabled in settings"
			_job["processed"] = processed
			_finish()
			return false
	elif SkillManager.running:
		var res2: Dictionary = SkillManager.simulate_elapsed(slice)
		ActionQueueManager.after_simulation_slice()
		summary["activity"] = "skill"
		summary["skill"] = SkillManager.active_skill
		summary["action"] = SkillManager.active_action_id
		processed += float(res2["seconds_processed"])
		summary["actions"] = int(summary.get("actions", 0)) + int(res2["actions"])
		if bool(res2["stopped"]):
			summary["stopped_reason"] = str(res2["stop_reason"])
			_job["processed"] = processed
			_finish()
			return false
	else:
		summary["activity"] = "none"
		summary["stopped_reason"] = "Nothing was running"
		processed = target
		_job["processed"] = processed
		_finish()
		return false
	_job["processed"] = processed
	return true

# =========================================================================
#  Finish
# =========================================================================

func _finish() -> void:
	if not is_running:
		return
	is_running = false
	var summary: Dictionary = _job["summary"]
	var processed: float = minf(float(_job["processed"]), float(_job["target_seconds"]))
	summary["processed_seconds"] = processed
	summary["capped_seconds"] = maxf(0.0, float(summary.get("capped_seconds", 0.0))
		+ (float(_job["target_seconds"]) - processed))
	if processed < float(_job["target_seconds"]) and str(summary.get("stopped_reason", "")) == "":
		summary["stopped_reason"] = "Simulation budget reached"
	# Farming and settlement advance on absolute time, so they need no stepping.
	summary["farming_advanced"] = FarmingManager.advance_offline(processed)
	summary["township_ticks"] = TownshipManager.advance_offline(processed)
	# Deltas read from real state — no estimated or invented numbers.
	summary["xp_gained"] = _diff_xp(_job["xp_before"])
	summary["levels_gained"] = _diff_levels(_job["levels_before"])
	var events: Dictionary = SimulationMode.take_events()
	summary["items_consumed"] = _int_table(events.get(SimulationMode.BUCKET_ITEMS_CONSUMED, {}))
	summary["items_gained"] = _int_table(events.get(SimulationMode.BUCKET_ITEMS_PRODUCED, {}))
	summary["rare_drops"] = _int_table(events.get(SimulationMode.BUCKET_RARE_DROPS, {}))
	summary["combat"] = {
		"kills": int(SimulationMode.get_total_from(events, SimulationMode.BUCKET_KILLS)),
		"kills_by_monster": _int_table(events.get(SimulationMode.BUCKET_KILLS, {})),
		"deaths": int(SimulationMode.get_total_from(events, SimulationMode.BUCKET_DEATHS)),
		"dungeons": int(SimulationMode.get_total_from(events, SimulationMode.BUCKET_DUNGEONS)),
	}
	var pets_after: int = PlayerData.unlocked_pets.size()
	if pets_after > int(_job["pets_before"]):
		var newly: Array = []
		for i in range(int(_job["pets_before"]), pets_after):
			newly.append(PlayerData.unlocked_pets[i])
		summary["pets"] = newly
	SimulationMode.end()
	PlayerData.bump_total("offline_seconds_processed", processed)
	_advance_marker(float(_job["now"]))
	# Persist immediately: this is the write that makes the catch-up exactly-once.
	BankManager.flush_notifications()
	SaveManager.save_game()
	EventBus.state_refreshed.emit()
	EventBus.offline_progress_summary.emit(summary)
	EventBus.offline_catchup_finished.emit(summary)
	_job = {}
	_last_summary = summary

func _description_of_activity() -> String:
	if CombatManager.state != CombatManager.State.IDLE:
		return "Fighting"
	if SkillManager.running:
		return str(DataLoader.get_skill(SkillManager.active_skill).get("name", SkillManager.active_skill))
	return "Idle"

## Advance the exactly-once marker and write it straight to disk.
func _advance_marker(now: float) -> void:
	PlayerData.last_offline_unix = int(now)
	SaveManager.save_game()

# =========================================================================
#  Deltas
# =========================================================================

func _snapshot_xp() -> Dictionary:
	var out: Dictionary = {}
	for skill_id in PlayerData.skills.keys():
		out[skill_id] = float(PlayerData.get_xp(skill_id))
	return out

func _snapshot_levels() -> Dictionary:
	var out: Dictionary = {}
	for skill_id in PlayerData.skills.keys():
		out[skill_id] = PlayerData.get_level(skill_id)
	return out

func _diff_xp(before: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for skill_id in before.keys():
		var delta: float = PlayerData.get_xp(skill_id) - float(before[skill_id])
		if delta > 0.0:
			out[skill_id] = delta
	return out

func _diff_levels(before: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for skill_id in before.keys():
		var delta: int = PlayerData.get_level(skill_id) - int(before[skill_id])
		if delta > 0:
			out[skill_id] = delta
	return out

func _int_table(source: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(source) != TYPE_DICTIONARY:
		return out
	for k in (source as Dictionary).keys():
		if str(k) == "_total":
			continue
		out[str(k)] = int((source as Dictionary)[k])
	return out

func _read_save_root() -> Dictionary:
	if not FileAccess.file_exists(SaveManager.SAVE_PATH):
		return {}
	var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

# =========================================================================
#  Deterministic simulation entry point (used by tests)
# =========================================================================

## Run a full catch-up synchronously. Used by the automated tests and the headless
## `--offline N` diagnostic. Not used during normal play (that uses the chunked job).
func simulate_synchronously(seconds: float) -> Dictionary:
	var summary: Dictionary = empty_summary()
	summary["elapsed_seconds"] = seconds
	_begin_job(summary, Time.get_unix_time_from_system())
	var guard: int = 0
	while is_running and guard < MAX_TOTAL_CHUNKS:
		guard += 1
		_step_chunk()
	return _last_summary
