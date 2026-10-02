extends Control

var passed: int = 0
var failed: int = 0

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("POPUP FAIL: ", message)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	PlayerData.initialize_new_game()
	PlayerData.settings["reduced_motion"] = true
	PlayerData.settings["notify_success"] = false
	SimulationMode.end()
	theme = UIStyle.build_theme()
	var popup := ToastStack.new()
	add_child(popup)
	popup.set_process(false)
	for id in DataLoader.get_skill_ids():
		popup.clear()
		EventBus.skill_level_up.emit(id, 2)
		check(popup._entries.size() == 1, id + " raises a popup")
		if popup._entries.size() == 1:
			var entry: Dictionary = popup._entries[0]
			check(str(entry.text).contains("level 2"), id + " shows level")
			var icon: TextureRect = entry.node.get_node("body").get_child(0)
			check(icon.texture == AssetRegistry.skill_icon(id), id + " uses its icon")
	popup.clear()
	PlayerData.add_xp("woodcutting", float(XPTable.xp_for_level(5)))
	check(popup._entries.size() == 1 and str(popup._entries[0].text).contains("level 5"), "real XP grant shows final level")
	PlayerData.add_xp("woodcutting", 0.01)
	check(popup._entries.size() == 1, "XP without a level does not create a popup")
	popup.clear()
	SimulationMode.begin()
	EventBus.skill_level_up.emit("woodcutting", 6)
	check(popup._entries.is_empty(), "offline simulation leaves gains to summary")
	SimulationMode.end()
	EventBus.skill_level_up.emit("woodcutting", 6)
	Engine.time_scale = 16.0
	popup._process(16.0)
	check(popup._entries.size() == 1 and is_equal_approx(float(popup._entries[0].timer), 4.0), "lifetime uses real seconds at 16x")
	popup._process(64.0)
	check(popup._entries.is_empty(), "popup expires after five real seconds")
	Engine.time_scale = 1.0
	for i in range(10):
		EventBus.skill_level_up.emit("woodcutting", i + 10)
	check(popup._entries.size() == ToastStack.MAX_VISIBLE, "stack remains bounded")
	EventBus.game_loaded.emit()
	check(popup._entries.is_empty(), "load clears old character popups")
	for width in [420, 1440]:
		get_window().size = Vector2i(width, 900)
		EventBus.skill_level_up.emit("dreamwalking", 99)
		for frame in range(4):
			await get_tree().process_frame
		check(popup._column.get_combined_minimum_size().x <= width, "popup fits " + str(width))
		check(get_viewport_rect().encloses(popup._entries[0].node.get_global_rect()), "popup is visibly inside the viewport at " + str(width))
		if "--render-popup" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/level_popup_%d.png" % width)
		popup.clear()
	print("POPUP RESULT: %d checks, %d failed" % [passed + failed, failed])
	get_tree().quit(0 if failed == 0 else 1)
