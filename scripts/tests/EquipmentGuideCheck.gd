extends Node
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)
func find_label(node: Node, needle: String) -> bool:
	if node is Label and str(node.text).contains(needle): return true
	for child in node.get_children():
		if find_label(child, needle): return true
	return false
func find_button(node: Node, label: String) -> Button:
	if node is Button and str(node.text) == label: return node
	for child in node.get_children():
		var found := find_button(child, label)
		if found != null: return found
	return null
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	PlayerData.initialize_new_game()
	PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
	BankManager.deserialize({"purchased_slots": 200})
	EquipmentManager.deserialize({})
	call_deferred("run")
func run() -> void:
	var panel = load("res://scripts/ui/panels/EquipmentGuidePanel.gd").new()
	add_child(panel)
	check(Screens.ORDER.has(Screens.EQUIPMENT_GUIDE), "guide is in navigation")
	for style in panel.STYLES:
		var choices: Array = panel._suggestions(style, ItemData.EquipmentSlot.WEAPON)
		check(not choices.is_empty(), str(style) + " has weapon suggestions")
		for choice in choices:
			var item: Dictionary = DataLoader.get_item(choice.id)
			check(int(item.equipment_slot) == ItemData.EquipmentSlot.WEAPON, "correct slot")
			check(panel._score(item, style, ItemData.EquipmentSlot.WEAPON) > 0, "matching style")
	BankManager.add_item_guaranteed("bronze_scimitar", 1)
	check(EquipmentManager.equip("bronze_scimitar"), "starter weapon equips")
	var selected: Array = panel._suggestions("Melee", ItemData.EquipmentSlot.WEAPON)
	for choice in selected:
		check(str(choice.id) != "bronze_scimitar", "equipped item omitted")
		check(float(choice.score) > panel._score(DataLoader.get_item("bronze_scimitar"), "Melee", ItemData.EquipmentSlot.WEAPON), "higher score than equipped")
	var started: int = Time.get_ticks_msec()
	panel.refresh()
	print("Equipment guide refresh: ", Time.get_ticks_msec() - started, " ms")
	check(find_label(panel, "Verdigris Scimitar"), "equipped item shown")
	check(find_label(panel, "Stat comparison"), "comparison visible")
	check(find_label(panel, "Where to get it") or find_label(panel, "No known acquisition"), "source state visible")
	check(find_label(panel, "Requirements"), "equipment requirements shown")
	var routes: Array = []
	panel.navigated.connect(func(route): routes.append(route))
	var source := find_button(panel, "Open source")
	check(source != null, "source link exists")
	if source != null:
		source.pressed.emit()
		check(not routes.is_empty() and str(routes[0].get("screen", "")) != "", "source link navigates")
	var later := find_button(panel, "Later upgrades")
	check(later != null and not later.disabled, "later upgrade page available")
	if later != null and not later.disabled:
		later.pressed.emit()
		check(panel._page == 1, "later upgrade page opens")
	panel._style.select(2)
	panel._slot.select(1)
	panel.refresh()
	check(panel._style.selected == 2 and panel._slot.selected == 1, "style and slot selection works")
	panel.queue_free()
	await get_tree().process_frame
	print("EQUIPMENT GUIDE: ", checks, " checks; ", failures, " failures")
	get_tree().quit(1 if failures else 0)
