extends Node
const Sidebar = preload("res://scripts/ui/SidebarNav.gd")
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	var host = load("res://scripts/ui/MainUI.gd").new()
	add_child(host)
	GameManager.cli_mode = true
	await get_tree().process_frame
	var runner := TestRunner.new()
	runner._test_combat_screen_split(host)
	var button: Button = host._nav_buttons[Screens.SETTLEMENT]
	runner._ok(button.text == "Settlement · Lv 1", "Settlement management entry shows its level")
	button.pressed.emit()
	runner._ok(host._screen == Screens.SETTLEMENT, "Settlement button opens management")
	PlayerData.add_xp("township", float(XPTable.xp_for_level(2)))
	runner._ok(button.text == "Settlement · Lv 2", "Settlement label updates immediately after leveling")
	host._refresh_nav()
	runner._ok(button.text == "Settlement · Lv 2", "navigation refresh keeps Settlement level")
	for screen in [Screens.SKILLS, "skill"]:
		host.navigate({"screen": screen, "skill_id": "township"})
		runner._ok(host._screen == Screens.SETTLEMENT, "old Settlement skill route opens management")
	Sidebar.populate_drawer(host, host._drawer)
	var buttons: Array = host._drawer.find_children("*", "Button", true, false)
	var settlement_buttons: Array = buttons.filter(func(b): return b.text.begins_with("Settlement"))
	runner._ok(settlement_buttons.size() == 1 and settlement_buttons[0].text == "Settlement · Lv 2", "drawer has one Settlement entry with level")
	PlayerData.add_xp("township", float(XPTable.xp_for_level(3) - XPTable.xp_for_level(2)))
	runner._ok(settlement_buttons[0].text == "Settlement · Lv 3", "drawer Settlement level updates live")
	host.queue_free()
	await get_tree().process_frame
	print("SETTLEMENT NAV: ", runner._passed, " passed; ", runner._failed, " failures")
	get_tree().quit(0 if runner._failed == 0 else 1)
