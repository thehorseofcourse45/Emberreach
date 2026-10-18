extends Control

var checks := 0
var failures := 0
var panel: Control
var scroll: ScrollContainer
var routes: Array[Dictionary] = []
const OUT := "user://"

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", label)

func button_in(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node
	return null

func settle() -> void:
	for i in range(6):
		await get_tree().process_frame

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	SaveManager._write_in_progress = true
	call_deferred("run")

func run() -> void:
	PlayerData.initialize_new_game()
	BankManager.deserialize({"purchased_slots": 1000})
	Motion.force_reduced = true
	SimulationMode.begin()
	theme = UIStyle.build_theme()
	var backdrop := ColorRect.new()
	backdrop.color = UITokens.BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_"+side, 16)
	add_child(margin)
	scroll = UIStyle.scroll()
	margin.add_child(scroll)
	panel = load("res://scripts/ui/panels/OverviewPanel.gd").new()
	scroll.add_child(panel)
	panel.navigated.connect(func(route): routes.append(route))
	await settle()
	var summary: Control = panel.get("_summary_box")
	check(summary != null, "character summary exists")
	check(button_in(panel, "Equipment") != null, "equipment shortcut available")
	check(panel.get("_health_bar") != null, "readiness has a health meter")
	if summary == null:
		print("Overview dashboard: ", checks, " checks; ", failures, " failures")
		get_tree().quit(1)
		return
	var grid: GridContainer = panel.get("_summary_grid")
	check(grid.get_child_count()==4, "four readable headline metrics")
	for cell in grid.get_children():
		var icon: TextureRect = cell.get_child(0).get_child(0)
		check(icon.texture != null and icon.texture.resource_path != "", "headline icon uses authored artwork")
	var equipment_count := 0
	for button in panel.find_children("*", "Button", true, false):
		if button.has_meta("overview_equipment_slot"):
			equipment_count += 1
	check(equipment_count == EquipmentManager.SLOT_COUNT, "every equipment slot is visible")
	for pair in [["Equipment", Screens.EQUIPMENT], ["Storage", Screens.BANK], ["Task journal", Screens.QUESTS], ["Action queue", Screens.ACTION_QUEUE], ["Equip food", Screens.BANK], ["Prayers", Screens.PRAYERS]]:
		var button := button_in(panel, str(pair[0]))
		check(button != null, str(pair[0])+" shortcut exists")
		if button != null:
			button.pressed.emit()
			check(not routes.is_empty() and routes[-1].get("screen")==pair[1], str(pair[0])+" navigates correctly")
	check(panel.call("_activity_route", {"kind":"idle"}).get("screen")==Screens.SKILLS, "idle activity opens training, not combat")
	var more: Button = null
	for node in (panel.get("_unlocks_box") as Control).find_children("*", "Button", true, false):
		if node.text.begins_with("Show all"):
			more = node
	check(more != null and int(panel.get("_unlock_count")) > 6, "long unlock list has an expansion control")
	if more != null:
		more.pressed.emit()
		check(bool(panel.get("_show_all_unlocks")), "all opportunities can be expanded")
		button_in(panel.get("_unlocks_box"), "Show fewer").pressed.emit()
		check(not bool(panel.get("_show_all_unlocks")), "opportunities collapse again")
	PlayerData.set_level("woodcutting", 40)
	check(SkillManager.start_action("woodcutting", "normal_tree"), "sample activity starts")
	panel.refresh()
	SkillManager.progress = SkillManager.current_interval * 0.6
	panel.call("_update_live_dashboard")
	check(absf((panel.get("_activity_meter") as ProgressBar).value-0.6)<0.001, "activity meter follows live progress")
	var authored_activity := false
	for node in (panel.get("_activity_box") as Control).find_children("*", "TextureRect", true, false):
		if node.texture != null and node.texture.resource_path.ends_with("woodcutting/normal_tree.png"):
			authored_activity = true
	check(authored_activity, "current activity shows its own tree artwork")
	CombatManager.player_hp = 4.0
	panel.call("_update_live_dashboard")
	check(is_equal_approx((panel.get("_health_bar") as ProgressBar).value,4.0), "health meter follows current HP")
	PlayerData.set_level("hitpoints",40)
	panel.call("_update_live_dashboard")
	check(is_equal_approx((panel.get("_health_bar") as ProgressBar).max_value,CombatManager._compute_max_hp()), "health capacity follows character changes")
	BankManager.add_item_guaranteed("normal_log",1)
	panel.call("_update_live_dashboard")
	check((panel.get("_collection_value") as Label).text.begins_with(str((PlayerData.completion_log.get("items",{}) as Dictionary).size())+" /"), "collection count follows discoveries")
	SkillManager.stop_action()
	panel.call("_select_tab", "woodcutting")
	check((panel.get("_skill_box") as Control).visible and not (panel.get("_dashboard") as Control).visible, "skill summaries remain accessible")
	panel.call("_select_tab", "")
	for width in [420, 800, 1440]:
		get_window().size = Vector2i(width, 1000)
		await settle()
		panel.call("_update_dashboard_columns")
		await settle()
		check(panel.get_combined_minimum_size().x <= scroll.size.x+1, "dashboard fits %dpx (%s <= %s)" % [width,panel.get_combined_minimum_size().x,scroll.size.x])
		check((panel.get("_dashboard_grid") as GridContainer).columns==(2 if panel.size.x>=760 else 1), "columns respond at %dpx" % width)
	if "--render" in OS.get_cmdline_user_args():
		PlayerData.tutorial_step = TutorialManager.step_count()
		for sid in DataLoader.get_skill_ids():
			PlayerData.set_level(sid,45)
		for item in ["bronze_sword","bronze_helmet","bronze_platebody","bronze_platelegs","bronze_boots","bronze_shield","gold_amulet","charmed_gold_ring"]:
			if not DataLoader.get_item(item).is_empty():
				BankManager.add_item_guaranteed(item,1)
				EquipmentManager.equip(item)
		BankManager.add_item_guaranteed("normal_log",340)
		BankManager.add_item_guaranteed("shrimp",120)
		Goals.pin("skill","woodcutting",50)
		SkillManager.start_action("woodcutting","normal_tree")
		SkillManager.progress=SkillManager.current_interval*0.64
		panel.refresh()
		for width in [1440,420]:
			get_window().size=Vector2i(width,1100)
			scroll.scroll_vertical=0
			await settle()
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(OUT+"overview_"+str(width)+".png") == OK, "capture saves at %dpx" % width)
	SimulationMode.end()
	print("Overview dashboard: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
