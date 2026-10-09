extends Node
var checks := 0
var failures := 0
func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	var runner := TestRunner.new()
	runner._deterministic(true)
	var host = load("res://scripts/ui/MainUI.gd").new()
	add_child(host)
	await get_tree().process_frame
	await runner._test_husbandry(host)
	host.queue_free()
	await get_tree().process_frame
	runner._test_farm_plot_types()
	var skill_panel = load("res://scripts/ui/panels/SkillsPanel.gd").new()
	add_child(skill_panel)
	skill_panel.focus_route({"skill_id": "farming"})
	verify(skill_panel.find_children("*", "Button", true, false).any(func(button): return button.text.begins_with("Manage farm")), "Husbandry skill links to farm management")
	skill_panel.queue_free()
	await get_tree().process_frame
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	var fm = FarmingManager
	var seed := "garum_herb_seed"
	var plain: Dictionary = fm.planting_preview(0, seed)
	verify(not fm.upgrade_plot(-1) and not fm.upgrade_plot(99), "invalid upgrade indices")
	PlayerData.add_gp(200000)
	var gp: float = PlayerData.gp
	verify(not fm.upgrade_plot(0) and PlayerData.gp == gp, "upgrade level gate spends nothing")
	for tier in range(3):
		PlayerData.set_level("farming", int(fm.UPGRADES[tier].level))
		verify(fm.upgrade_plot(0), "upgrade tier %d" % tier)
		verify(PlayerData.gp == gp - float(fm.UPGRADES[tier].cost), "exact upgrade cost")
		gp = PlayerData.gp
	verify(not fm.upgrade_plot(0), "maximum upgrade refused")
	var upgraded: Dictionary = fm.planting_preview(0, seed)
	verify(is_equal_approx(float(upgraded.seconds), float(plain.seconds) * 0.85) and int(upgraded.yield_bonus) == 30, "upgrade effects")
	verify(fm.set_method(0, "careful"), "careful selectable")
	var careful: Dictionary = fm.planting_preview(0, seed)
	verify(float(careful.survival) >= float(upgraded.survival) and is_equal_approx(float(careful.seconds), float(upgraded.seconds) * 1.15), "careful tradeoff")
	verify(fm.set_method(0, "intensive"), "intensive selectable")
	var intensive: Dictionary = fm.planting_preview(0, seed)
	verify(int(intensive.yield_bonus) == 65 and float(intensive.survival) < float(careful.survival), "intensive tradeoff")
	verify(not fm.set_method(0, "bogus") and not fm.set_method(-1, "careful"), "invalid methods rejected")
	BankManager.add_item(seed, 4)
	verify(fm.plant(0, seed), "managed crop planted")
	verify(not fm.set_method(0, "careful") and not fm.upgrade_plot(0), "growing management locked")
	verify(int(fm.plots[0].crop_yield_bonus) == 65 and float(fm.plots[0].grow_seconds) == float(intensive.seconds), "planting snapshots preview")
	fm.plots[0].alive = true
	fm.plots[0].planted_unix = Time.get_unix_time_from_system() - 999999
	var saved: Dictionary = fm.serialize().duplicate(true)
	fm.deserialize(saved.duplicate(true))
	verify(fm.is_ready(0) and int(fm.plots[0].upgrade) == 3 and str(fm.plots[0].method) == "intensive", "save restores growing crop and management")
	var result: Dictionary = fm.harvest(0, false)
	verify(not result.is_empty() and float(result.xp) == float(DataLoader.get_item(seed).harvest_xp), "XP per harvest unchanged")
	verify(str(fm.plots[0].last_seed) == seed, "successful harvest records rotation")
	var same: Dictionary = fm.planting_preview(0, seed)
	verify(not bool(same.rotated), "same crop earns no rotation")
	fm.plots[0].last_seed = "sourleaf_seed"
	var rotated: Dictionary = fm.planting_preview(0, seed)
	verify(bool(rotated.rotated) and int(rotated.yield_bonus) == int(same.yield_bonus) + 15, "different crop earns rotation")
	verify(is_equal_approx(float(rotated.survival), minf(1.0, float(same.survival) + 0.1)), "rotation survival")
	BankManager.add_item("compost", 8)
	for i in range(5): verify(fm.apply_compost(0), "compost dose")
	var stock: int = BankManager.get_count("compost")
	verify(not fm.apply_compost(0) and BankManager.get_count("compost") == stock, "compost cap without waste")
	verify(fm.plant(0, seed), "rotated planting")
	fm.plots[0].alive = false
	verify(fm.clear_plot(0) and str(fm.plots[0].last_seed) == "sourleaf_seed", "failure preserves prior successful harvest")
	var legacy: Dictionary = saved.duplicate(true)
	for p in legacy.plots:
		for key in ["method", "upgrade", "last_seed", "crop_yield_bonus", "crop_survival"]: p.erase(key)
	fm.deserialize(legacy)
	verify(fm.plots.size() == 15 and str(fm.plots[0].seed_id) == seed, "legacy save preserves crops")
	verify(int(fm.planting_preview(0, seed).yield_bonus) == 0, "legacy default management")
	fm.deserialize({})
	PlayerData.set_level("farming", 90)
	PlayerData.gp = 0
	verify(not fm.upgrade_plot(0) and int(fm.plots[0].get("upgrade", 0)) == 0, "unaffordable upgrade refused")
	PlayerData.add_gp(100000)
	BankManager.add_item(seed, 2)
	fm.plant(0, seed)
	fm.plots[0].alive = true
	fm.plots[0].planted_unix = Time.get_unix_time_from_system() - 999999
	fm.plots[0].crop_yield_bonus = 0
	var base_save: Dictionary = fm.serialize().duplicate(true)
	fm._rng.seed = 8765
	var base_yield: int = int(fm.harvest(0, false).quantity)
	fm.deserialize(base_save)
	fm.plots[0].crop_yield_bonus = 100
	fm._rng.seed = 8765
	verify(int(fm.harvest(0, false).quantity) == base_yield * 2, "saved yield bonus changes actual harvest")
	fm.deserialize({})
	for def in EngineeringManager.devices():
		if str(def.skill) != "farming": continue
		EngineeringManager.installed = [{"id": str(def.id), "action": "plant_garum_herb", "progress": 0.0, "fuel_seconds": 0.0, "status": "Ready"}]
		var before: float = float(EngineeringManager.worker_preview(0).outputs.get("garum_herb", 0))
		fm.upgrade_plot(0)
		var after: float = float(EngineeringManager.worker_preview(0).outputs.get("garum_herb", 0))
		verify(after > before, "Farmhand forecast includes plot upgrades")
		EngineeringManager.installed.clear()
	fm.deserialize({})
	var frame := Control.new()
	frame.theme = UIStyle.build_theme()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	var panel = load("res://scripts/ui/panels/FarmPanel.gd").new()
	scroll.add_child(panel)
	await get_tree().process_frame
	verify(panel._plot_count() == 15, "all farm cards rendered")
	verify(panel.find_children("*", "OptionButton", true, false).size() == 15, "each empty plot exposes growing method")
	if "--capture" in OS.get_cmdline_user_args():
		BankManager.add_item("ranch_manure", 3)
		fm.apply_manure(0)
		fm.set_method(0, "careful")
		fm.plant(0, seed)
		fm.plots[0].alive = true
		fm.plots[0].planted_unix = Time.get_unix_time_from_system() - float(fm.plots[0].grow_seconds) * 0.5
		panel._rebuild()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/husbandry_runtime.png")
	frame.queue_free()
	await get_tree().process_frame
	checks += runner._passed + runner._failed
	failures += runner._failed
	print("HUSBANDRY: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
