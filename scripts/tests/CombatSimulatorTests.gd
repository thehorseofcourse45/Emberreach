class_name CombatSimulatorTests
extends RefCounted
const CombatSimulator = preload("res://scripts/combat/CombatSimulator.gd")

## Backstop for the production run's completion signal, in real time rather than frames. The
## in-test run measures ~1.3s, and a deliberately slow one (a 500-HP dummy taking ~10 hits per
## fight) measures ~8s, so 120s leaves over 15x headroom even for the slow case. The budget it
## replaces was worth 26s of wall clock here and an unpredictable amount on other hardware, because
## its size was set by the machine's frame rate rather than by the work. A genuine hang still fails
## the suite rather than blocking forever.
const RUN_TIMEOUT_MS: int = 120000

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

## One-monster worlds for the passive and ability checks, patched rather than derived from
## _strong_snapshot so every number an assertion depends on is visible on the call.
## `passives` goes on the monster and `loadout` on the player: that pair is the ONLY difference
## between a world and its control, so any difference in the two reports is the feature under test
## and nothing else. min_hit_percent 100.0 on both sides makes every hit a fixed number, which
## turns "deals more damage" into an exact figure instead of a direction a wrong constant could
## still satisfy.
static func _passive_world(passives: Array, loadout: Array = [], player_patch: Dictionary = {},
		monster_patch: Dictionary = {}) -> Dictionary:
	var world: Dictionary = {
		"player": {
			"mode": "standard", "style": "melee", "melee_style": "stab",
			"max_hp": 1000.0, "accuracy": 1000, "max_hit": 50, "min_hit_percent": 100.0,
			"min_hit_flat": 0.0, "attack_interval": 1.0, "damage_reduction": 0.0,
			"evasion": {"melee": 0, "ranged": 0, "magic": 0},
			"crit_chance": 0.0, "crit_multiplier": 50.0, "life_steal": 0.0, "hybrid": false,
		},
		"monsters": [{
			"id": "fixture", "name": "Fixture", "hitpoints": 2000, "max_hit": 4,
			"min_hit_percent": 100.0, "min_hit_flat": 0.0, "accuracy_rating": 1000000,
			"attack_speed": 3.0, "attack_type": "melee", "damage_type": "normal",
			"damage_reduction": 0.0, "melee_evasion": 0, "ranged_evasion": 0, "magic_evasion": 0,
			"passives": passives,
		}],
		"food": {},
		"auto_eat_tier": 0,
		"auto_eat_threshold_percent": 0.0,
		"prayer_points": 0.0,
		"mode_config": {},
		"in_slayer_area": false,
		"on_slayer_task": false,
		"loadout": loadout,
		"strategy": {"name": "Fixture", "ability_loadout": loadout, "food_threshold": 0.0,
			"special_bias": "normal", "protection_prayer_auto": ""},
		"weapon_special": {},
	}
	for key in player_patch.keys():
		(world["player"] as Dictionary)[key] = player_patch[key]
	for key in monster_patch.keys():
		((world["monsters"][0] as Dictionary))[key] = monster_patch[key]
	return world

## An ability that fires on every landed hit: a 100% trigger chance cannot lose a roll, because
## randf() is always below 1.0. Built here rather than taken from data/abilities.json so the
## "always-firing" claim cannot quietly become a data-dependent one.
static func _always_firing_ability() -> Array:
	return [{"id": "test_always", "name": "Always", "style": "melee", "req_levels": {},
		"effect": {"max_hit_percent": 10.0}, "trigger_chance": 100.0, "cooldown_attacks": 0}]

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
	# Regeneration and hazards
	# ---------------------------------------------------------------------------
	# A regenerating monster must take strictly longer to kill than the same
	# monster without the passive: same seed, high-HP dummy the player cannot
	# one-shot, monster accurate enough to land its own attacks (regen triggers
	# per monster attack).
	var plain: Dictionary = _strong_snapshot(2000, 1)
	(plain["monsters"][0] as Dictionary)["accuracy_rating"] = 10000
	var plain_report: Dictionary = CombatSimulator.simulate(plain, 20, 31337)
	var regen: Dictionary = _strong_snapshot(2000, 1)
	(regen["monsters"][0] as Dictionary)["accuracy_rating"] = 10000
	(regen["monsters"][0] as Dictionary)["passives"] = ["regeneration"]
	var regen_report: Dictionary = CombatSimulator.simulate(regen, 20, 31337)
	_assert(float(regen_report["kills_per_hour"]) < float(plain_report["kills_per_hour"]),
		"a regenerating monster yields strictly fewer kills per hour", state)
	# A −100 accuracy hazard means the player never lands a hit: every trial
	# must time out rather than report phantom wins.
	var dark: Dictionary = _strong_snapshot(100, 1)
	dark["hazard"] = {"enemy_damage_percent": 0.0, "player_accuracy_percent": -100.0}
	var dark_report: Dictionary = CombatSimulator.simulate(dark, 5, 77)
	_assert(int(dark_report["wins"]) == 0 and int(dark_report["timeouts"]) == 5,
		"a blinding hazard converts every trial into a timeout, never a win", state)

	# ---------------------------------------------------------------------------
	# The mirrored draw order, the loadout, and the three new passives
	# ---------------------------------------------------------------------------
	# WHAT THESE CHECKS ARE NOT: none of them drives the live engine, so none of them proves the
	# model and the live loop agree. Running one snapshot twice from one seed proves the model is
	# REPRODUCIBLE — that it walks its own draw order the same way every time, which is what makes
	# a mirroring mistake visible as a wrong number rather than a random one. Cross-engine parity
	# rests on the draw order and constants being transcribed faithfully, and is not proven here.
	var armed: Dictionary = _passive_world([], _always_firing_ability())
	var armed_once: Dictionary = CombatSimulator.simulate(armed, 20, 4242)
	var armed_again: Dictionary = CombatSimulator.simulate(armed, 20, 4242)
	_assert(JSON.stringify(armed_once) == JSON.stringify(armed_again),
		"the same snapshot, seed and trial count reproduce the mirrored report byte for byte "
		+ "(determinism, not cross-engine parity)", state)

	# The loadout reaches the fight: without this the ability code below could be a no-op and every
	# later assertion would still pass, because an empty loadout behaves exactly like a broken one.
	_assert(armed_once.has("ability_fires"), "the report names how many abilities fired", state)
	var armed_fires: int = int(armed_once["ability_fires"])
	_assert(armed_fires > 0,
		"an always-firing loadout fires abilities (%d fires over 20 trials)" % armed_fires, state)
	var disarmed: Dictionary = CombatSimulator.simulate(_passive_world([]), 20, 4242)
	_assert(int(disarmed["ability_fires"]) == 0,
		"an empty loadout fires nothing, so the counter is counting something real", state)

	# rage: the monster's own damage climbs as its health falls, so the arithmetic is pinned on its
	# own (a fight can only show that rage bites) and the behaviour against a control that differs
	# in nothing else. Exact numbers: the player always lands 10, the monster always hits for 4,
	# and the fight is long enough that the monster enrages across it.
	_eq_float(CombatSimulator._rage_multiplier(400.0, 400.0), 1.0, "rage is inert at full health", state)
	_eq_float(CombatSimulator._rage_multiplier(200.0, 400.0), 1.25, "half health is half the bonus", state)
	_eq_float(CombatSimulator._rage_multiplier(0.0, 400.0), 1.5, "a monster on its last HP hits hardest", state)
	var calm: Dictionary = _passive_world([], [], {"max_hit": 10, "max_hp": 220.0}, {"hitpoints": 1500})
	var raging: Dictionary = _passive_world(["rage"], [], {"max_hit": 10, "max_hp": 220.0}, {"hitpoints": 1500})
	var calm_report: Dictionary = CombatSimulator.simulate(calm, 20, 8675309)
	var rage_report: Dictionary = CombatSimulator.simulate(raging, 20, 8675309)
	_assert(int(calm_report["deaths"]) == 0,
		"the same monster without rage never kills a player standing at 220 HP", state)
	_assert(int(rage_report["deaths"]) == 20,
		"the raging monster kills every one of those players (%d of 20)" % int(rage_report["deaths"]), state)

	# veil: a flat evasion bonus, so the player's hit rate falls and the same fight takes longer.
	var veiled_world: Dictionary = _passive_world(["veil"])
	var plain_world: Dictionary = _passive_world([])
	var veiled_record: Dictionary = veiled_world["monsters"][0]
	var plain_record: Dictionary = plain_world["monsters"][0]
	_eq_int(CombatSimulator._evasion_for(veiled_record, "melee"), 15,
		"veil adds its flat bonus to the evasion the model uses", state)
	_eq_int(CombatSimulator._evasion_for(plain_record, "melee"), 0,
		"the control's evasion is untouched", state)
	var seen: Dictionary = _passive_world([], [], {"accuracy": 30}, {"melee_evasion": 10})
	var unseen: Dictionary = _passive_world(["veil"], [], {"accuracy": 30}, {"melee_evasion": 10})
	var seen_report: Dictionary = CombatSimulator.simulate(seen, 20, 555)
	var unseen_report: Dictionary = CombatSimulator.simulate(unseen, 20, 555)
	_assert(float(unseen_report["average_fight_seconds"]) > float(seen_report["average_fight_seconds"]),
		"a veiled monster lowers the player's hit rate, so the same kill takes longer "
		+ "(%.1fs against %.1fs)" % [float(unseen_report["average_fight_seconds"]),
			float(seen_report["average_fight_seconds"])], state)

	# leech: a fraction of what the monster dealt, so it has to be beaten twice as often, and never
	# past its own maximum.
	_eq_float(CombatSimulator._leech_heal(100.0, 400.0, 1000.0), 350.0, "leech heals a quarter of the damage", state)
	_eq_float(CombatSimulator._leech_heal(390.0, 400.0, 1000.0), 400.0, "a leech heal is capped at max HP", state)
	_eq_float(CombatSimulator._leech_heal(200.0, 400.0, 0.0), 201.0,
		"a swing that dealt nothing still leeches the one HP the live engine's maxi(1, ...) floor gives it", state)
	# The monster hits for half the player's damage, so the quarter it leeches back is a tenth of
	# a hit rather than a rounding error: a thin margin here would be a pin that only holds today.
	var leech_report: Dictionary = CombatSimulator.simulate(
		_passive_world(["leech"], [], {}, {"max_hit": 50}), 20, 31337)
	var leechless: Dictionary = CombatSimulator.simulate(
		_passive_world([], [], {}, {"max_hit": 50}), 20, 31337)
	_assert(float(leech_report["damage_dealt"]) > float(leechless["damage_dealt"]),
		"a leeching monster has to be hit harder to kill (%.0f against %.0f)"
		% [float(leech_report["damage_dealt"]), float(leechless["damage_dealt"])], state)
	_assert(float(leech_report["average_fight_seconds"]) > float(leechless["average_fight_seconds"]),
		"...which takes longer, since the healed damage is dealt again", state)

	# regeneration keeps its old behaviour with the new code around it: the ability roll now draws
	# between the player's swings, so the monster's rolls land elsewhere. Structural, not exact —
	# its per-swing heal is pinned exactly in the live suite.
	var regen_world: Dictionary = _passive_world(["regeneration"])
	var regen_world_report: Dictionary = CombatSimulator.simulate(regen_world, 20, 31337)
	_assert(float(regen_world_report["average_fight_seconds"]) > float(leechless["average_fight_seconds"]),
		"a regenerating monster still takes longer to kill than the control", state)

	# The strategy knobs are threshold changes, and a threshold the model ignored would show up
	# only as a different number, so each is asserted as a DIRECTION against its own control.
	_eq_float(CombatSimulator._biased_special_chance(80.0, "eager"), 100.0, "eager doubles a chance and caps at 100", state)
	_eq_float(CombatSimulator._biased_special_chance(30.0, "eager"), 60.0, "eager doubles a chance below the cap", state)
	_eq_float(CombatSimulator._biased_special_chance(30.0, "normal"), 30.0, "normal is the identity", state)
	_eq_float(CombatSimulator._biased_special_chance(30.0, "hold"), 0.0, "hold is a hard zero", state)
	_eq_float(CombatSimulator._biased_special_chance(30.0, "reckless"), 30.0,
		"an unrecognised bias falls back to the identity", state)
	_eq_float(CombatSimulator._food_threshold_percent(20.0, {"food_threshold": 0.0}), 20.0,
		"food_threshold 0.0 defers to the auto-eat tier", state)
	_eq_float(CombatSimulator._food_threshold_percent(20.0, {"food_threshold": 0.5}), 50.0,
		"a 0.5 food_threshold replaces the tier's percent", state)
	var armed_special: Dictionary = _passive_world([])
	(armed_special["weapon_special"] as Dictionary)["id"] = "test_special"
	(armed_special["weapon_special"] as Dictionary)["trigger_chance"] = 100.0
	(armed_special["weapon_special"] as Dictionary)["damage_multiplier"] = 2.0
	var eager_special: Dictionary = armed_special.duplicate(true)
	(eager_special["strategy"] as Dictionary)["special_bias"] = "eager"
	var held_special: Dictionary = armed_special.duplicate(true)
	(held_special["strategy"] as Dictionary)["special_bias"] = "hold"
	var eager_report: Dictionary = CombatSimulator.simulate(eager_special, 20, 99)
	var held_report: Dictionary = CombatSimulator.simulate(held_special, 20, 99)
	_assert(float(eager_report["average_fight_seconds"]) < float(held_report["average_fight_seconds"]),
		"an eager bias lands the weapon special and a held one never does, even at a 100%% chance "
		+ "(%.1fs against %.1fs)" % [float(eager_report["average_fight_seconds"]),
			float(held_report["average_fight_seconds"])], state)

	# food_threshold, on the model's own auto-eat: the same fight, the same food, one threshold
	# moved. The monster has to actually connect, or the player never crosses either threshold.
	var fed_default: Dictionary = _passive_world([], [], {"max_hp": 100.0},
		{"hitpoints": 1000, "max_hit": 30, "min_hit_percent": 0.0})
	(fed_default["food"] as Dictionary)["shrimp"] = 20
	fed_default["auto_eat_tier"] = 1
	var finicky: Dictionary = fed_default.duplicate(true)
	(finicky["strategy"] as Dictionary)["food_threshold"] = 0.5
	var tier_report: Dictionary = CombatSimulator.simulate(fed_default, 50, 8080)
	var finicky_report: Dictionary = CombatSimulator.simulate(finicky, 50, 8080)
	_assert(int(tier_report["food_eaten"]) > 0, "the control's auto-eat threshold is reached at all", state)
	_assert(int(finicky_report["food_eaten"]) > int(tier_report["food_eaten"]),
		"a 0.5 food_threshold eats where the tier-1 20%% would not (%d against %d portions)"
		% [int(finicky_report["food_eaten"]), int(tier_report["food_eaten"])], state)

	# ---------------------------------------------------------------------------
	# The snapshot the model is handed
	# ---------------------------------------------------------------------------
	# Nothing carried a monster's passives into the model before this: the record the manager
	# builds listed thirteen keys and passives was not one of them, so the regeneration the older
	# check exercised — on a hand-built record — could never fire in a real run. Pinned here
	# because a snapshot missing the key fails silently: the model reads an absent key as "no
	# passives", which looks exactly like a monster that has none.
	var snapshot: Dictionary = CombatSimulatorManager.build_snapshot_for_test(
		"moss_giant", ["power_strike"], "eager")
	var snapshot_monsters: Array = snapshot.get("monsters", [])
	_assert(not snapshot_monsters.is_empty(), "a snapshot can be built for a shipped monster", state)
	var snapshot_record: Dictionary = snapshot_monsters[0] as Dictionary
	_assert(snapshot_record.has("passives"), "the snapshot's monster record carries a passives key", state)
	_assert((snapshot_record["passives"] as Array).has("regeneration"),
		"a regenerating monster's passive reaches the snapshot the model runs on", state)
	_assert(snapshot.has("loadout") and snapshot.has("strategy"),
		"the snapshot carries the loadout and the strategy", state)
	_eq_str(str((snapshot["strategy"] as Dictionary).get("special_bias", "")), "eager",
		"the requested special bias reaches the snapshot", state)
	# The loadout travels as whole ability RECORDS: the worker thread that runs a 10,000-fight job
	# is given a plain dictionary and no autoload, so an id list would leave it nothing to roll.
	var loadout: Array = snapshot.get("loadout", [])
	_assert(loadout.size() == 1 and (loadout[0] as Dictionary).has("trigger_chance"),
		"the loadout reaches the snapshot as whole ability records", state)
	_eq_float(float((loadout[0] as Dictionary).get("trigger_chance", -1.0)),
		float(DataLoader.get_ability("power_strike").get("trigger_chance", 0.0)),
		"...carrying the data's own trigger chance rather than a default", state)
	_assert(CombatSimulatorManager.build_snapshot_for_test("no_such_monster", [], "normal").is_empty(),
		"an unknown monster yields no snapshot rather than a fight against nothing", state)

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
	var _settled: String = _save_fingerprint()
	# Wait for the worker's real completion signal, not a frame count. The manager publishes from
	# _process on the main thread, so the signal lands on a frame boundary and the loop below only
	# has to keep the tree ticking and enforce the timeout.
	var waiter: RunWaiter = RunWaiter.new()
	CombatSimulatorManager.run_finished.connect(waiter.on_finished)
	CombatSimulatorManager.run_failed.connect(waiter.on_failed)
	var started_ms: int = Time.get_ticks_msec()
	while not waiter.done and Time.get_ticks_msec() - started_ms < RUN_TIMEOUT_MS:
		await host.get_tree().process_frame
	var run_ms: int = Time.get_ticks_msec() - started_ms
	CombatSimulatorManager.run_finished.disconnect(waiter.on_finished)
	CombatSimulatorManager.run_failed.disconnect(waiter.on_failed)
	_assert(waiter.done and waiter.outcome == "finished",
		"the background run finishes (%s)" % _outcome_note(waiter, run_ms), state)
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
	# Ambient drift is the live game doing its own thing over the same span of time the run took, so
	# the control window is sized in real milliseconds rather than in frames.
	var control_before: String = _save_fingerprint()
	var control_deadline: int = Time.get_ticks_msec() + maxi(200, run_ms)
	while Time.get_ticks_msec() < control_deadline:
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

## Carries the run's completion signal back to the test. It has to be an object with mutated
## fields: a GDScript lambda captures its enclosing locals by value, so a lambda handler can signal
## that it fired but can never record it in the caller's scope.
class RunWaiter extends RefCounted:
	var done: bool = false
	var outcome: String = ""
	var detail: String = ""

	func on_finished(_report: Dictionary) -> void:
		done = true
		outcome = "finished"

	func on_failed(reason: String) -> void:
		done = true
		outcome = "failed"
		detail = reason

## Says how the run ended, so a failure names the cause (a refused or discarded run, or a real hang
## that blew the timeout) instead of just reporting that something did not finish.
static func _outcome_note(waiter: RunWaiter, run_ms: int) -> String:
	if waiter.done and waiter.outcome == "finished":
		return "finished in %d ms" % run_ms
	if waiter.done:
		return "%s: %s" % [waiter.outcome, waiter.detail]
	return "no completion signal after %d ms (timeout %d ms)" % [run_ms, RUN_TIMEOUT_MS]

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

## The equality half of _assert, so a wrong number says WHICH number was wrong instead of only
## that something was. The house suite spells these out for the same reason.
static func _eq_int(actual: int, expected: int, label: String, state: Dictionary) -> void:
	_assert(actual == expected, "%s (expected %d, got %d)" % [label, expected, actual], state)

static func _eq_float(actual: float, expected: float, label: String, state: Dictionary) -> void:
	_assert(absf(actual - expected) < 0.0001, "%s (expected %.4f, got %.4f)" % [label, expected, actual],
		state)

static func _eq_str(actual: String, expected: String, label: String, state: Dictionary) -> void:
	_assert(actual == expected, "%s (expected '%s', got '%s')" % [label, expected, actual], state)
