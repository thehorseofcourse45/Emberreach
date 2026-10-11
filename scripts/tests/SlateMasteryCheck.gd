extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)
func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	var suite = preload("res://scripts/tests/TestRunner.gd").new()
	suite.test_grimoire_palette()
	suite.test_grimoire_buttons()
	suite.test_surface_textures()
	suite.call("_test_mastery_metadata")
	check(int(suite.get("_failed")) == 0, "shared styles, contrast, fallback and metadata")
	for sid in DataLoader.get_skill_ids():
		var activities: Array = MasteryManager.activities(sid)
		if activities.is_empty(): continue
		PlayerData.set_level(sid, 120)
		check(MasteryManager.get_pool_cap(sid) == activities.size() * 500000.0, sid+" pool includes every activity")
		for action in activities:
			var before: float = MasteryManager.get_xp(sid, str(action.id))
			MasteryManager.add_mastery_xp(sid, str(action.id), 3.0)
			check(MasteryManager.get_xp(sid, str(action.id)) > before, sid+":"+str(action.id)+" earns mastery")
		check(DataLoader.get_skill(sid).mastery_unlocks.has("120"), sid+" has capstone bonuses")
	for sid in ["ranching", "dreamwalking", "caravaneering"]:
		check(not MasteryManager.activities(sid).is_empty(), sid+" system activities registered")
	# Preserve existing XP, including old over-cap XP; spending must stop at level 120.
	var first: String = str(MasteryManager.activities("woodcutting")[0].id)
	var second: String = str(MasteryManager.activities("woodcutting")[1].id)
	var cap: float = XPTable.xp_for_level(120)
	MasteryManager.deserialize({"mastery_xp": {"woodcutting": {first: cap - 50.0, second: 123.0}}, "pools": {"woodcutting": 100.0}})
	check(MasteryManager.spend_pool_xp("woodcutting", first, 1000.0), "pool spend is capped to required XP")
	check(MasteryManager.get_level("woodcutting", first) == 120 and MasteryManager.get_pool_xp("woodcutting") == 50.0, "cap reaches 120 without wasting pool")
	check(not MasteryManager.spend_pool_xp("woodcutting", first, 1.0), "maxed activity cannot spend pool")
	check(not MasteryManager.spend_pool_xp("woodcutting", second, -10.0) and not MasteryManager.spend_pool_xp("woodcutting", second, NAN), "invalid spends rejected")
	check(not MasteryManager.spend_pool_xp("woodcutting", "missing", 1.0), "unknown activity cannot consume pool")
	var saved: Dictionary = MasteryManager.serialize().duplicate(true)
	MasteryManager.deserialize(saved)
	check(MasteryManager.get_xp("woodcutting", first) == cap and MasteryManager.get_xp("woodcutting", second) == 123.0, "mastery save roundtrip preserves progress")
	var readout = Widgets.mastery_progress("woodcutting", second)
	add_child(readout)
	MasteryManager.add_pool_xp("woodcutting", 1000.0)
	MasteryManager.spend_pool_xp_for_levels("woodcutting", second, 2)
	readout.call("_refresh")
	check((readout.get_child(0) as Label).text.contains("/ 120"), "live mastery level readout")
	check((readout.get_child(1) as ProgressBar).value == XPTable.level_progress(MasteryManager.get_xp("woodcutting", second), MasteryManager.get_level("woodcutting", second)), "mastery bar follows pool XP immediately")
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	check((readout.get_child(1) as ProgressBar).value == XPTable.level_progress(MasteryManager.get_xp("woodcutting", second), MasteryManager.get_level("woodcutting", second)), "opening animation cannot reset mastery progress")
	readout.free()
	SkillManager.start_action("woodcutting", first)
	var interval_bonus: float = ModifierManager.get_modifier("woodcutting_interval_percent")
	MasteryManager.spend_pool_xp_for_levels("woodcutting", second, 1)
	check(ModifierManager.get_modifier("woodcutting_interval_percent") == interval_bonus, "inactive mastery cannot replace active activity bonuses")
	SkillManager.stop_action()
	var animal: String = str(DataLoader.new_skill_systems.species[0].id)
	var ranch_before: float = MasteryManager.get_xp("ranching", "raise_" + animal)
	RanchingManager.pens = [{"species": animal, "cycles": 1, "pending": {}, "pending_xp": 10.0}]
	check(RanchingManager.collect(0) and MasteryManager.get_xp("ranching", "raise_" + animal) > ranch_before, "ranch collection awards mastery")
	RanchingManager.pens.clear()
	DreamwalkingManager.select("meadow", 0.5)
	var dream_before: float = MasteryManager.get_xp("dreamwalking", "meadow")
	DreamwalkingManager.advance_offline(60.0)
	check(MasteryManager.get_xp("dreamwalking", "meadow") > dream_before, "offline dream awards mastery")
	var route: String = str(CaravaneeringManager.routes()[0].id)
	var wagon: String = str(CaravaneeringManager.wagons()[0].id)
	var guard: String = str(CaravaneeringManager.guards()[0].id)
	var cargo: String = str(DataLoader.new_skill_systems.caravan_goods[0].item_id)
	BankManager.add_item_guaranteed(cargo, 10)
	PlayerData.gp = 100000.0
	CaravaneeringManager.owned_wagons = [wagon]
	var caravan_before: float = MasteryManager.get_xp("caravaneering", route)
	check(CaravaneeringManager.dispatch(route, wagon, guard, {cargo: 1}), "test caravan dispatched")
	CaravaneeringManager.advance(CaravaneeringManager.trip_seconds(route) + 1.0)
	check(MasteryManager.get_xp("caravaneering", route) > caravan_before, "finished journey awards mastery")
	print("Slate and mastery: ", checks, " checks, ", failures, " failures; shared suite ", suite.get("_passed"), " passed")
	if "--capture" in OS.get_cmdline_user_args():
		var main = preload("res://scenes/main.tscn").instantiate()
		add_child(main)
		GameManager.cli_mode = true
		await get_tree().create_timer(0.5).timeout
		main.navigate({"screen": Screens.SKILLS, "skill_id": "woodcutting", "action_id": first})
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/slate_mastery_preview.png")
		main.queue_free()
		await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
