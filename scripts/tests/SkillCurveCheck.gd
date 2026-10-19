extends Node
const Sim = preload("res://scripts/combat/CombatSimulator.gd")

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	for source in ModifierManager._sources.keys():
		ModifierManager.unregister(str(source))
	var t := TestRunner.new()
	# Reproduce the reported two-harvest scenario against real farming code.
	FarmingManager._build_plots()
	BankManager.add_item_guaranteed("garum_herb_seed", 2)
	PlayerData.set_level("farming", 1)
	for i in range(2):
		t._ok(FarmingManager.plant(i, "garum_herb_seed"), "starter Emberleaf plants")
		FarmingManager.plots[i].alive = true
		var at_time: float = float(FarmingManager.plots[i].planted_unix) + float(FarmingManager.plots[i].grow_seconds) + 1
		var result: Dictionary = FarmingManager.harvest(i, false, at_time)
		t._ok(float(result.xp) == 61.0, "Emberleaf harvest pays 61 XP")
		t._ok(FarmingManager.harvest(i, false, at_time).is_empty(), "same crop cannot pay twice")
	t._ok(PlayerData.get_level("farming") == 2, "two Emberleaf harvests reach level 2")
	t._ok(PlayerData.get_xp("farming") == 122.0, "two harvests give exactly 122 unmodified XP")
	TownshipManager.buildings = {"township_building_homes": 1, "township_building_school": 2}
	PlayerData.set_level("township", 1)
	PlayerData.set_level("woodcutting", 1)
	TownshipManager.set_study("woodcutting")
	t._ok(TownshipManager.xp_per_hour() <= 200.0, "fresh settlement cannot pay thousands of XP in one tick")
	t._approx(TownshipManager._trade_xp("township", 25000.0), 375.0, 0.001, "monument XP cannot bypass the starter curve")
	t._ok(TownshipManager.study_xp_per_hour() == 100.0, "level-two Schoolhouse pays 100 starter XP per hour")
	PlayerData.set_level("woodcutting", 90)
	t._ok(TownshipManager.study_xp_per_hour() > 4000, "study improves with the studied skill")
	t._ok(CaravaneeringManager.route("ferryman_run").xp <= 60, "first caravan trip has a small starter reward")
	t._ok(RanchingManager.species("hen").xp <= 30, "starter animal XP is bounded")
	t._ok(DreamwalkingManager.dream("meadow").xp_hour <= 150, "starter Dreamland XP is bounded")
	ModifierManager.register("curve_check", {"global_skill_xp_percent": 100.0, "attack_skill_xp_percent": 50.0}, "test")
	for skill in PlayerData.COMBAT_SKILLS:
		PlayerData.set_level(skill, 10)
	PlayerData.active_prayers = ["thick_skin"]
	for setup in [["melee", "stab", "attack"], ["melee", "slash", "strength"], ["melee", "block", "defence"], ["ranged", "stab", "ranged"], ["magic", "stab", "magic"]]:
		CombatManager.attack_style = setup[0]
		CombatManager.melee_style = setup[1]
		var before: float = PlayerData.get_xp(setup[2])
		var hp_before: float = PlayerData.get_xp("hitpoints")
		var prayer_before: float = PlayerData.get_xp("prayer")
		CombatManager._grant_combat_xp(100)
		t._approx(PlayerData.get_xp(setup[2]) - before, 100.0 if setup[2] == "attack" else 80.0, 0.001, "style XP honours bonuses: " + setup[2])
		t._approx(PlayerData.get_xp("hitpoints") - hp_before, 26.6, 0.001, "Vitality XP honours bonuses")
		t._approx(PlayerData.get_xp("prayer") - prayer_before, 20.0 / 3.0, 0.001, "Devotion XP honours bonuses")
	var slayer_before: float = PlayerData.get_xp("slayer")
	CombatManager._add_combat_skill_xp("slayer", 50)
	t._approx(PlayerData.get_xp("slayer") - slayer_before, 100.0, 0.001, "Huntsman XP honours bonuses")
	ModifierManager.unregister("curve_check")
	PlayerData.active_prayers = []
	var world: Dictionary = CombatSimulatorTests._strong_snapshot()
	world.player.on_slayer_task = true
	world.prayer_points = 1.0
	var raw: Dictionary = Sim.simulate(world, 10, 20261019)
	world.xp_multipliers = {"attack": 2.5, "hitpoints": 2.0, "prayer": 2.0, "slayer": 2.0}
	var boosted: Dictionary = Sim.simulate(world, 10, 20261019)
	for skill in raw.xp:
		t._approx(float(boosted.xp[skill]), float(raw.xp[skill]) * (2.5 if skill == "attack" else 2.0), 0.001, "simulator uses frozen XP bonus: " + skill)
	for sid in DataLoader.get_skill_ids():
		for action in DataLoader.get_skill_actions(sid):
			var xp: float = float(action.get("base_xp", 0))
			t._ok(is_finite(xp) and xp >= 0, "finite XP: " + sid + ":" + str(action.id))
			if sid == "farming":
				t._ok(xp == 0, "planting never grants harvest XP")
				continue
			if int(action.get("level_required", 1)) == 1:
				t._ok(xp < XPTable.xp_for_level(5), "starter action cannot skip the opening tier: " + str(action.id))
	t._test_xp_and_levels()
	t._test_action_xp_ladders()
	t._test_study_ramp_rises()
	t._test_late_skills_pace()
	t._test_farm_plot_types()
	t._test_township_has_no_dead_ends()
	t._test_dreamlands()
	t._test_caravaneering_data()
	t._test_caravaneering_core()
	var simulator_checks: Dictionary = await CombatSimulatorTests.run(self)
	t._passed += int(simulator_checks.passed)
	t._failed += int(simulator_checks.failed)
	print("SKILL CURVES: ", t._passed, " passed; ", t._failed, " failures")
	get_tree().quit(0 if t._failed == 0 else 1)
