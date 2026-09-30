extends Node
const Support = preload("res://scripts/tests/TestSupport.gd")
var checks := 0
var failures := 0

func _ready() -> void:
	GameManager.cli_mode = true
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FOOD FAIL: ", message)

func _run() -> void:
	var files: Dictionary = Support.backup_save_files()
	var snapshot: Dictionary = SaveManager.build_save_data()
	var paused: bool = GameManager.is_paused
	GameManager.is_paused = true
	EquipmentManager.deserialize({})
	var foods: Array[String] = []
	for id in DataLoader.items:
		var item: Dictionary = DataLoader.get_item(str(id))
		if item.get("item_type", "") == "food" and int(item.get("heal_amount", 0)) > 0:
			foods.append(str(id))
			if foods.size() == 3:
				break
	check(EquipmentManager.food_slots == ["", "", ""], "old saves start with three empty food slots")
	check(not EquipmentManager.equip_food(-1, foods[0]), "negative slot rejected")
	check(not EquipmentManager.equip_food(3, foods[0]), "fourth slot rejected")
	check(not EquipmentManager.equip_food(0, "missing"), "non-food rejected")
	BankManager.items.erase(foods[0])
	check(not EquipmentManager.equip_food(0, foods[0]), "food must be in Storage")
	for slot in range(3):
		BankManager.add_item_guaranteed(foods[slot], 3)
		var quantity: int = BankManager.get_count(foods[slot])
		check(EquipmentManager.equip_food(slot, foods[slot]), "three distinct foods can be assigned")
		check(BankManager.get_count(foods[slot]) == quantity, "assignment does not duplicate or consume food")
	check(not EquipmentManager.equip_food(1, foods[0]), "same food cannot occupy two slots")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(EquipmentManager.serialize()))
	EquipmentManager.deserialize(saved)
	check(EquipmentManager.food_slots == foods, "food assignments survive JSON save round trip")
	CombatManager.player_hp = CombatManager._compute_max_hp()
	var before: int = BankManager.get_count(foods[0])
	check(EquipmentManager.eat_food_slot(0) == "" and BankManager.get_count(foods[0]) == before, "full health never wastes food")
	CombatManager.player_hp = 1.0
	check(EquipmentManager.eat_food_slot(0) == foods[0], "Eat consumes the chosen slot's food")
	check(BankManager.get_count(foods[0]) == before - 1 and CombatManager.player_hp > 1.0, "Eat consumes exactly one and heals")
	BankManager.items.erase(foods[0])
	CombatManager.player_hp = 1.0
	check(EquipmentManager.eat_food_slot(0) == "" and CombatManager.player_hp == 1.0, "empty stack cannot heal for free")
	check(EquipmentManager.equip_food(0, "") and EquipmentManager.food_slots[0] == "", "Clear removes the assignment")
	BankManager.add_item_guaranteed(foods[0], 3)
	EquipmentManager.equip_food(0, foods[0])
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.theme = UIStyle.build_theme()
	add_child(layout)
	var panel = load("res://scripts/ui/panels/CombatPanel.gd").new()
	layout.add_child(panel)
	check(panel._food_controls.size() == 3, "Combat shows three assigned food controls")
	panel._update_food_controls()
	check(not panel._food_controls[0].eat.disabled, "Eat enabled while hurt")
	CombatManager.player_hp = CombatManager._compute_max_hp()
	panel._process(0.0)
	check(panel._food_controls[0].eat.disabled, "Eat disables immediately at full health")
	for width in [420, 1440]:
		get_window().size = Vector2i(width, 900)
		for frame in range(4):
			await get_tree().process_frame
		check(panel._food_box.get_combined_minimum_size().x <= width - 28, "food slots fit %dpx" % width)
		if "--render-food" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/food_%d.png" % width)
	layout.queue_free()
	Support.restore_snapshot(snapshot, files)
	GameManager.is_paused = paused
	check(Support.backup_save_files() == files, "save files restored")
	print("FOOD RESULT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(failures)
