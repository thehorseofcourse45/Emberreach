extends Node
var checks := 0
var failures := 0
var content: Dictionary

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("COOKERY MEALS FAIL: ", message)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	PlayerData.settings["sfx_volume"] = 0.0
	PlayerData.settings["music_volume"] = 0.0
	content = JSON.parse_string(FileAccess.get_file_as_string("res://tools/cookery_meals_check/new_content.json"))
	PlayerData.game_mode = "standard"
	BankManager.purchased_slots = 100
	SkillManager._rng.seed = 24681
	call_deferred("run")

func run() -> void:
	for sid in ["fishing", "cooking"]:
		for aid in content[sid]:
			var action: Dictionary = DataLoader.get_action(sid, str(aid))
			var item_id: String = str(action.output_items.keys()[0])
			check(not action.is_empty(), "action loaded: " + str(aid))
			var row: Control = Widgets.activity_row(sid, action, false, func(_id): pass)
			var preview: TextureRect = row.get_child(0).get_child(0).get_child(0)
			check(preview.texture.resource_path == "res://assets/icons/items/%s.png" % item_id, "activity uses item artwork")
			row.free()
			PlayerData.set_level(sid, 1)
			check(str(SkillManager.check_action(sid, str(aid)).reason) == "level", "level gate")
			PlayerData.set_level(sid, int(action.level_required))
			BankManager.items.clear()
			if sid == "cooking": check(str(SkillManager.check_action(sid, str(aid)).reason) == "materials", "ingredient gate")
			for ingredient in action.get("input_items", {}): BankManager.add_item(str(ingredient), int(action.input_items[ingredient]) * 40)
			check(SkillManager.start_action(sid, str(aid)), "start action")
			var xp_before: float = PlayerData.get_xp(sid)
			var result: Dictionary = {}
			for attempt in 40:
				result = SkillManager.perform_action()
				if bool(result.get("success", false)): break
			check(bool(result.get("success", false)), "successful production")
			check(BankManager.get_count(item_id) > 0, "output reaches storage")
			check(PlayerData.get_xp(sid) > xp_before if int(action.level_required) < 120 else PlayerData.get_xp(sid) == xp_before, "XP awarded or correctly capped")
			SkillManager.stop_action()
			if sid == "cooking":
				EquipmentManager.food_slots.fill("")
				check(EquipmentManager.equip_food(0, item_id), "food can be equipped")
				var count_before: int = BankManager.get_count(item_id)
				CombatManager.player_hp = 1.0
				check(EquipmentManager.eat_food_slot(0) == item_id, "food can be eaten")
				check(CombatManager.player_hp > 1.0, "food heals")
				check(BankManager.get_count(item_id) == count_before - 1, "one food consumed")
	for item_id in content.items:
		var tex: Texture2D = AssetRegistry.item_icon(str(item_id))
		check(tex.resource_path == "res://assets/icons/items/%s.png" % item_id, "authored item icon")
		check(tex.get_size() == Vector2(32,32), "32x32 icon")
	check(DataLoader.get_skill_actions("fishing").size() >= 27, "Angling expanded")
	check(DataLoader.get_skill_actions("cooking").size() >= 36, "Cookery expanded")
	for frame in 3: await get_tree().process_frame
	print("COOKERY MEALS: %d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures else 0)
