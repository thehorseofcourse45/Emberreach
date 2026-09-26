class_name CombatSimulatorTests
extends RefCounted
const CombatSimulator = preload("res://scripts/combat/CombatSimulator.gd")
## Dedicated tests for the built-in combat simulator.
##
## The model is pure, so most checks run it directly on a hand-built snapshot: that is the only way
## to assert "the same inputs give the same answer" without a worker thread in the way. The
## production 10,000-fight path is then exercised through the manager, including the promise that
## the player's own save data is untouched by it.

## A deliberately lopsided snapshot: the player wins almost every fight, so the assertions about
## rates are about arithmetic rather than about balance.
static func _strong_snapshot(monster_hp: int = 10, monster_max_hit: int = 1) -> Dictionary:
	return {
		"player": {
			"mode": "standard", "style": "melee", "melee_style": "stab",
			"max_hp": 100.0, "accuracy": 1000, "max_hit": 50, "min_hit_percent": 0.0,
			"min_hit_flat": 0.0, "attack_interval": 1.0, "damage_reduction": 0.0,
			"evasion": {"melee": 100, "ranged": 100, "magic": 100},
			"crit_chance": 0.0, "crit_multiplier": 50.0, "life_steal": 0.0, "hybrid": false,
		},
		"monsters": [{
			"id": "dummy", "name": "Dummy", "hitpoints": monster_hp, "max_hit": monster_max_hit,
			"min_hit_percent": 0.0, "min_hit_flat": 0.0, "accuracy_rating": 1,
			"attack_speed": 3.0, "attack_type": "melee", "damage_type": "normal",
			"damage_reduction": 0.0, "melee_evasion": 1, "ranged_evasion": 1, "magic_evasion": 1,
		}],
		"food": {},
		"auto_eat_tier": 0,
		"auto_eat_threshold_percent": 0.0,
		"prayer_points": 0.0,
		"mode_config": {"advantage_accuracy": 10.0, "advantage_damage": 10.0,
			"disadvantage_accuracy": -10.0, "disadvantage_damage": -10.0},
		"in_slayer_area": false,
		"on_slayer_task": false,
	}

static func run(host: Node) -> Dictionary:
	var state: Dictionary = {"passed": 0, "failed": 0, "failures": []}
	var snap: Dictionary = _strong_snapshot()

	# ---------------------------------------------------------------------------
	# Determinism
	# ---------------------------------------------------------------------------
	var a: Dictionary = CombatSimulator.simulate(snap, 200, 12345)
	var b: Dictionary = CombatSimulator.simulate(snap, 200, 12345)
	_assert(a["kills"] == b["kills"] and is_equal_approx(float(a["kills_per_hour"]), float(b["kills_per_hour"])),
		"the same snapshot, seed and trial count produce an identical report", state)
	var c: Dictionary = CombatSimulator.simulate(snap, 200, 999)
	_assert(int(c["wins"]) >= 0 and int(c["deaths"]) >= 0,
		"a different seed still produces a valid report", state)

	# ---------------------------------------------------------------------------
	# The four headline figures
	# ---------------------------------------------------------------------------
	_assert(a.has("death_chance"), "the report names a death chance", state)
	_assert(a.has("kills_per_hour"), "the report names a kills/hour figure", state)
	_assert(a.has("food_per_hour"), "the report names a food/hour figure", state)
	_assert(a.has("xp_per_hour_total"), "the report names an XP/hour figure", state)
	for key in ["death_chance", "kills_per_hour", "food_per_hour", "xp_per_hour_total"]:
		var v: float = float(a[key])
		_assert(is_finite(v) and v >= 0.0, "%s is finite and non-negative" % key, state)
	_assert(float(a["death_chance"]) <= 1.0, "a death chance above 100% is impossible", state)
	_assert(int(a["wins"]) + int(a["deaths"]) + int(a["timeouts"]) == int(a["trials"]),
		"every trial is accounted for as a win, a death or a timeout", state)

	# A player who cannot be hit dies, and that must show as a death chance, not a crash.
	var doomed: Dictionary = _strong_snapshot(100000, 100)
	doomed["player"]["accuracy"] = 1
	var death_report: Dictionary = CombatSimulator.simulate(doomed, 20, 4242)
	_assert(float(death_report["death_chance"]) > 0.0,
		"an unwinnable fight reports a death chance instead of pretending to win", state)

	# A stalemate is a loss, not a hang.
	var stuck: Dictionary = _strong_snapshot(1000000, 1)
	stuck["player"]["accuracy"] = 1
	stuck["monsters"][0]["accuracy_rating"] = 1
	var stuck_report: Dictionary = CombatSimulator.simulate(stuck, 5, 7)
	_assert(int(stuck_report["timeouts"]) > 0 or int(stuck_report["deaths"]) > 0,
		"a fight that can never resolve ends as a loss rather than running forever", state)

	# ---------------------------------------------------------------------------
	# Food projection
	# ---------------------------------------------------------------------------
	# The monster has to actually connect: a 0.5%-to-hit dummy never pushes the player below the
	# Auto Eat threshold, so food would never be consumed and the test would prove nothing.
	var fed: Dictionary = _strong_snapshot(1000, 30)
	(fed["monsters"][0] as Dictionary)["accuracy_rating"] = 500
	fed["food"] = {"shrimp": 20}
	fed["auto_eat_tier"] = 1
	fed["player"]["damage_reduction"] = 0.0
	var fed_report: Dictionary = CombatSimulator.simulate(fed, 200, 31337)
	_assert(int(fed_report["food_eaten"]) > 0, "Auto Eat consumes food when the threshold is crossed", state)
	_assert(float(fed_report["food_per_hour"]) > 0.0, "food/hour reflects that consumption", state)
	# The same fight with no food type owned eats nothing: consumption follows what you own.
	var unfed: Dictionary = fed.duplicate(true)
	unfed["food"] = {}
	var unfed_report: Dictionary = CombatSimulator.simulate(unfed, 200, 31337)
	_assert(int(unfed_report["food_eaten"]) == 0, "with no food type owned, nothing is consumed", state)
	_assert(int(fed_report["deaths"]) < int(unfed_report["deaths"]),
		"having food available strictly reduces deaths", state)

	# ---------------------------------------------------------------------------
	# Dungeon trials
	# ---------------------------------------------------------------------------
	var dungeon: Dictionary = _strong_snapshot(10, 1)
	dungeon["monsters"] = [
		(dungeon["monsters"][0] as Dictionary).duplicate(true),
		(dungeon["monsters"][0] as Dictionary).duplicate(true),
		(dungeon["monsters"][0] as Dictionary).duplicate(true),
	]
	var dungeon_report: Dictionary = CombatSimulator.simulate(dungeon, 50, 555)
	_assert(int(dungeon_report["fights"]) == 150,
		"a three-monster dungeon trial spends three fights", state)
	_assert(int(dungeon_report["kills"]) == 150,
		"a won dungeon trial counts every monster in its sequence as a kill", state)

	# ---------------------------------------------------------------------------
	# XP is attributed per skill
	# ---------------------------------------------------------------------------
	var xp: Dictionary = a["xp"]
	_assert(xp.has("hitpoints") and float(xp["hitpoints"]) > 0.0,
		"damage dealt produces hitpoints XP", state)
	_assert(xp.has("melee") and float(xp["melee"]) > 0.0,
		"damage dealt produces attack-style XP", state)
	_assert(not xp.has("slayer"),
		"no slayer XP is granted outside a slayer area", state)
	var slayer_snap: Dictionary = _strong_snapshot(10, 1)
	slayer_snap["in_slayer_area"] = true
	var slayer_report: Dictionary = CombatSimulator.simulate(slayer_snap, 50, 77)
	_assert(float((slayer_report["xp"] as Dictionary).get("slayer", 0.0)) > 0.0,
		"a defeat in a slayer area grants slayer XP", state)

	# Assumptions travel with the report, because they are the reason real results differ.
	_assert((a["assumptions"] as Array).size() >= 3,
		"the report states its assumptions alongside the numbers", state)

	# ---------------------------------------------------------------------------
	# The production path, through the manager
	# ---------------------------------------------------------------------------
	var saved_game: Dictionary = SaveManager.build_save_data()
	var area: Dictionary = _first_area()
	if area.is_empty():
		_assert(false, "found a region with monsters to simulate", state)
		return state
	_assert(not area.is_empty(), "found a region with monsters to simulate", state)

	await host.get_tree().process_frame
	ProgressTracker.mark_dirty(true)
	ProgressTracker.evaluate_now()
	await host.get_tree().process_frame
	var before: String = _save_fingerprint()
	_assert(CombatSimulatorManager.start("area", str(area["id"]), "melee", "stab",
		CombatSimulatorManager.PRODUCTION_TRIALS, 987654), "a 10,000-fight run starts", state)
	_assert(CombatSimulatorManager.is_running(), "the manager reports the run as active", state)
	_assert(not CombatSimulatorManager.start("area", str(area["id"]), "melee", "stab", 100, 1),
		"a second run is refused while one is active", state)

	# Control first: wait the same number of frames with nothing running at all, so any drift
	# below is the live game's own doing and not the simulator's.
	var control_wait: int = 40
	for _i in range(control_wait):
		await host.get_tree().process_frame
	var settled: String = _save_fingerprint()
	# Wait for the worker. A generous cap: if the model ever regressed into a hang, this fails the
	# test rather than the run.
	var frames: int = 0
	while CombatSimulatorManager.is_running() and frames < 3000:
		frames += 1
		await host.get_tree().process_frame
	_assert(not CombatSimulatorManager.is_running(), "the background run finishes", state)
	var report: Dictionary = CombatSimulatorManager.last_report
	_assert(bool(report.get("valid", false)), "the finished run published a valid report", state)
	_assert(int(report.get("trials", 0)) == CombatSimulatorManager.PRODUCTION_TRIALS,
		"the production run really did 10,000 fights", state)
	for key in ["death_chance", "kills_per_hour", "food_per_hour", "xp_per_hour_total"]:
		var v: float = float(report.get(key, -1.0))
		_assert(is_finite(v) and v >= 0.0, "the production report's %s is finite and non-negative" % key, state)
	var formatted: Array[String] = CombatSimulatorManager.format_report(report)
	_assert(_mentions(formatted, "Death chance"), "the formatted report states the death chance", state)
	_assert(_mentions(formatted, "Kills/hour"), "the formatted report states kills/hour", state)
	_assert(_mentions(formatted, "Food/hour"), "the formatted report states food/hour", state)
	_assert(_mentions(formatted, "XP/hour"), "the formatted report states XP/hour", state)

	# The promise that matters most: simulating must not have touched the character.
	# ProgressTracker evaluates quests/achievements on a debounce during any wait, so settle that
	# first: otherwise the measurement window catches its own timer rather than anything the
	# simulator did.
	ProgressTracker.mark_dirty(true)
	ProgressTracker.evaluate_now()
	await host.get_tree().process_frame
	var after: String = _save_fingerprint()
	# Ambient drift is the live game doing its own thing (playtime, township) over the same frames
	# a control run would take. Only a section the control also changed is genuinely the clock.
	var control_before: String = _save_fingerprint()
	var control_frames: int = maxi(2, frames)
	for _i in range(control_frames):
		await host.get_tree().process_frame
	var ambient: Array = _diff_keys(control_before, _save_fingerprint())
	var drift: Array = []
	for key in _diff_keys(before, after):
		if not ambient.has(key):
			drift.append(key)
	_assert(drift.is_empty(),
		"the simulator writes no save data of its own (live drift in the same window: %s)" % str(ambient), state)

	# A reset invalidates results, so stale output cannot appear under a new character.
	CombatSimulatorManager.invalidate()
	_assert(CombatSimulatorManager.last_report.is_empty(),
		"invalidating after a reset discards the previous report", state)
	_assert(not CombatSimulatorManager.start("area", "", "melee", "stab", 10, 1),
		"a target with no monsters is refused before any thread starts", state)
	SaveManager._apply(saved_game)
	return state

## Save data with the wall-clock stamp removed. The timestamp is expected to differ between two
## reads; what must not differ is a single thing about the character.
static func _save_fingerprint() -> String:
	var data: Dictionary = SaveManager.build_save_data()
	data.erase("timestamp")
	data.erase("playtime_seconds")
	return JSON.stringify(data)

## Names the top-level sections that changed, so a failure says what drifted rather than just
## that something did.
static func _diff_keys(before: String, after: String) -> Array:
	var out: Array = []
	var b: Dictionary = JSON.parse_string(before) if before != "" else {}
	var a: Dictionary = JSON.parse_string(after) if after != "" else {}
	if typeof(b) != TYPE_DICTIONARY or typeof(a) != TYPE_DICTIONARY:
		return ["<unparseable>"]
	for key in a.keys():
		if JSON.stringify(b.get(key, null)) != JSON.stringify(a[key]):
			out.append(str(key))
	return out

static func _mentions(lines: Array, needle: String) -> bool:
	for line in lines:
		if str(line).findn(needle) >= 0:
			return true
	return false

static func _first_area() -> Dictionary:
	var ids: Array = DataLoader.areas.keys()
	ids.sort()
	for area_id in ids:
		var row: Dictionary = DataLoader.areas[area_id]
		if str(row.get("type", "area")) == "slayer_area":
			continue
		if (row.get("monsters", []) as Array).is_empty():
			continue
		return {"id": str(area_id)}
	return {}

static func _assert(condition: bool, label: String, state: Dictionary) -> void:
	if condition:
		state["passed"] = int(state["passed"]) + 1
	else:
		state["failed"] = int(state["failed"]) + 1
		var list: Array = state["failures"]
		list.append(label)
