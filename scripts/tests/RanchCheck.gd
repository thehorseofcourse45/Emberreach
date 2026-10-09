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
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	var rm = RanchingManager
	PlayerData.add_gp(100000)
	verify(rm.build_pen(), "initial pen")
	verify(not rm.upgrade_pen(0), "upgrade level gate")
	verify(not rm.set_management(0, "production"), "production level gate")
	verify(rm.set_management(0, "pasture"), "level one pasture")
	verify(not rm.set_management(-1, "balanced") and not rm.set_management(0, "wrong"), "invalid management")
	BankManager.add_item("ranch_hen", 5)
	verify(rm.stock(0, "hen") and rm.stock(0, "hen"), "pair stocked")
	verify(not rm.stock(0, "hen"), "basic capacity")
	verify(not rm.stock(0, "cow") and not rm.stock(0, "hen", true), "matching species and variant")
	rm.set_management(0, "balanced")
	var base: Dictionary = rm.pen_rates(0)
	rm.set_management(0, "pasture")
	var pasture: Dictionary = rm.pen_rates(0)
	verify(is_equal_approx(float(pasture.feed_hour), float(base.feed_hour) * 0.75) and is_equal_approx(float(pasture.speed), float(base.speed) * 0.9), "pasture tradeoff")
	PlayerData.set_level("ranching", 70)
	for tier in range(3):
		var gp: float = PlayerData.gp
		verify(rm.upgrade_pen(0), "upgrade %d" % tier)
		verify(PlayerData.gp == gp - float(rm.PEN_UPGRADES[tier].cost), "exact upgrade payment")
	verify(not rm.upgrade_pen(0) and not rm.upgrade_pen(99), "upgrade cap and invalid index")
	verify(rm.capacity(0) == 4 and rm.stock(0, "hen") and rm.stock(0, "hen"), "expanded four animal enclosure")
	verify(not rm.stock(0, "hen"), "expanded capacity enforced")
	rm.set_management(0, "production")
	verify(float(rm.pen_rates(0).speed) > float(base.speed), "production increases speed")
	rm.set_management(0, "breeding")
	verify(float(rm.pen_rates(0).breed) == 1.875 and float(rm.pen_rates(0).rare) == 0.06, "breeding and sanctuary effects")
	BankManager.add_item("ranch_feed", 1000)
	verify(rm.feed_pen(0, 1000), "feed stocked")
	var baseline: Dictionary = rm.serialize()
	rm._rng.seed = 12
	rm.advance(28800)
	var offline: Dictionary = rm.serialize()
	rm.deserialize(baseline)
	rm._rng.seed = 12
	for i in range(480): rm.advance(60)
	var live: Dictionary = rm.serialize()
	verify(offline.pens[0].pending == live.pens[0].pending, "online offline produce parity")
	for key in ["feed", "progress", "pending_xp", "happiness", "breed_seconds"]:
		verify(is_equal_approx(float(offline.pens[0][key]), float(live.pens[0][key])), "online offline " + key)
	verify(int(rm.pens[0].animals) == 4 and int(rm.pens[0].upgrade) == 3 and str(rm.pens[0].management) == "breeding", "save preserves upgraded ranch")
	verify(rm.breed(0), "four animals can breed")
	verify(not rm.breed(0), "breeding cannot pay twice")
	var pending: Dictionary = rm.pens[0].pending.duplicate()
	var xp: float = PlayerData.get_xp("ranching")
	verify(rm.collect(0), "produce collected")
	verify(PlayerData.get_xp("ranching") > xp and BankManager.get_count("ranch_egg") >= int(pending.get("ranch_egg", 0)), "produce and XP paid")
	verify(not rm.collect(0), "collection cannot pay twice")
	rm.pens[0].happiness = 100.0
	rm.pens[0].feed = 0.0
	rm.advance(100000)
	verify(float(rm.pens[0].happiness) >= 50.0, "sanctuary mood floor")
	var legacy: Dictionary = baseline.duplicate(true)
	legacy.pens[0].animals = 2
	legacy.pens[0].erase("upgrade")
	legacy.pens[0].erase("management")
	rm.deserialize(legacy)
	verify(rm.capacity(0) == 2 and str(rm.pens[0].management) == "balanced", "legacy save defaults")
	verify(float(rm.pens[0].feed) == float(legacy.pens[0].feed), "legacy feed retained")
	var saved: Dictionary = rm.serialize()
	saved.pens[0].upgrade = 99
	saved.pens[0].management = "wrong"
	rm.deserialize(saved)
	verify(int(rm.pens[0].upgrade) == 3 and str(rm.pens[0].management) == "balanced", "invalid saved management normalized")
	rm.deserialize({})
	PlayerData.set_level("ranching", 1)
	PlayerData.gp = 0
	var frame := Control.new()
	frame.theme = UIStyle.build_theme()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	var scroll := ScrollContainer.new()
	frame.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var view = load("res://scripts/ui/panels/NewSkillSystems.gd").new()
	scroll.add_child(view)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.set_skill("ranching")
	await get_tree().process_frame
	var labels: Array = view.find_children("*", "Label", true, false)
	verify(labels.any(func(label): return label.text == "Livestock catalogue"), "catalogue visible without pens")
	verify(labels.any(func(label): return label.text == "Celestial Dragon"), "late game livestock visible")
	var livestock_previews: Array = view.find_children("*", "TextureRect", true, false).filter(func(icon): return icon.custom_minimum_size == Vector2(64, 64))
	verify(livestock_previews.size() == 9 and livestock_previews.all(func(icon): return icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST), "all livestock previews use crisp pixel scaling")
	verify(view.find_children("*", "Button", true, false).filter(func(button): return button.text.begins_with("Buy stock · owned")).size() == 9, "nine species cards")
	if "--capture" in OS.get_cmdline_user_args():
		for layout_frame in range(5): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/ranch_empty_runtime.png")
	frame.queue_free()
	await get_tree().process_frame
	PlayerData.add_gp(100000)
	PlayerData.set_level("ranching", 70)
	rm.build_pen()
	rm.stock(0, "hen")
	rm.stock(0, "hen")
	rm.upgrade_pen(0)
	rm.upgrade_pen(0)
	rm.set_management(0, "production")
	rm.pens[0].feed = 100.0
	rm.advance(3600)
	var populated = load("res://scripts/ui/panels/NewSkillSystems.gd").new()
	add_child(populated)
	populated.set_skill("ranching")
	await get_tree().process_frame
	verify(populated.find_children("*", "TextureRect", true, false).filter(func(icon): return icon.custom_minimum_size == Vector2(64, 64)).all(func(icon): return icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST), "pen portraits use crisp pixel scaling")
	verify(populated._live_pens.size() == 1, "live pen bars built")
	verify(populated.find_children("*", "OptionButton", true, false).size() >= 1, "management selector built")
	populated._process(0.5)
	verify(populated._live_pens[0].reserve.text.contains("lasts"), "live feed reserve")
	rm.pens[0].breed_seconds = 21600.0
	populated._process(0.5)
	verify(not populated._live_pens[0].breed_button.disabled, "breeding button unlocks live")
	rm.pens[0].happiness = 25.0
	populated._process(0.5)
	verify(populated._live_pens[0].breed_button.disabled, "unhappy animals cannot breed")
	rm.pens[0].happiness = 100.0
	populated.queue_free()
	await get_tree().process_frame
	if "--capture" in OS.get_cmdline_user_args():
		var host = load("res://scripts/ui/MainUI.gd").new()
		add_child(host)
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await get_tree().process_frame
		host.navigate({"screen": Screens.SKILLS, "skill_id": "ranching"})
		await get_tree().process_frame
		for layout_frame in range(5): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/ranch_game_populated.png")
		rm.deserialize({})
		PlayerData.set_level("ranching", 1)
		PlayerData.spend_gp(PlayerData.gp)
		host.navigate({"screen": Screens.SKILLS, "skill_id": "ranching"})
		await get_tree().process_frame
		for layout_frame in range(5): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/ranch_game_empty.png")
		for scroll_view in host._workspace.find_children("*", "ScrollContainer", true, false): scroll_view.scroll_vertical = 690
		for layout_frame in range(3): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/livestock_sharp_runtime.png")
		host.queue_free()
		await get_tree().process_frame
	print("RANCH: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
