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
	var new_ids: Array[String] = ["mireheart_staff", "frostcrown_staff", "stormcaller_staff", "sunheart_staff"]
	var staff_count := 0
	for action in DataLoader.get_skill_actions("runecrafting"):
		var outputs: Dictionary = action.get("output_items", {})
		if outputs.size() != 1:
			continue
		var ident: String = str(outputs.keys()[0])
		if not ident.ends_with("_staff"):
			continue
		staff_count += 1
		var item: Dictionary = DataLoader.get_item(ident)
		verify(str(action.name) == str(item.name), ident + " consistent display name")
		var path: String = "res://assets/icons/items/%s.png" % ident
		verify(ResourceLoader.exists(path), ident + " imported sprite exists")
		var card := Widgets.activity_row("runecrafting", action, false, func(): pass)
		var icon: TextureRect = card.get_child(0).get_child(0).get_child(0)
		verify(icon.texture != null and icon.texture.resource_path == path, ident + " activity preview loads authored sprite")
		card.free()
		if not new_ids.has(ident) and ident != "blood_staff":
			continue
		PlayerData.set_level("runecrafting", int(action.level_required)-1)
		verify(not SkillManager.start_action("runecrafting", str(action.id)), ident + " craft level gate")
		PlayerData.set_level("runecrafting", int(action.level_required))
		for material in action.input_items:
			BankManager.add_item(str(material), int(action.input_items[material])*2)
		var before: int = BankManager.get_count(ident)
		var xp: float = PlayerData.get_xp("runecrafting")
		verify(SkillManager.start_action("runecrafting", str(action.id), 1), ident + " recipe starts")
		SkillManager.tick(SkillManager.current_interval + 0.01)
		verify(BankManager.get_count(ident) > before, ident + " recipe produces staff")
		verify(PlayerData.get_xp("runecrafting") > xp, ident + " recipe grants XP")
		SkillManager.stop_action()
		PlayerData.set_level("magic", int(item.level_requirements.magic)-1)
		verify(not EquipmentManager.equip(ident), ident + " magic level gate")
		PlayerData.set_level("magic", int(item.level_requirements.magic))
		verify(EquipmentManager.equip(ident), ident + " equip succeeds")
		verify(float(CombatManager.call("_spell_max_hit")) == float(item.spell_max_hit), ident + " combat reads staff spell")
		verify(EquipmentManager.get_attack_cost() == item.attack_cost_items, ident + " combat reads rune cost")
		EquipmentManager.unequip(8)
	verify(staff_count == 17, "17 craftable staffs including Bloodtithe")
	print("Glyphcraft staff checks: ", checks, " passed: ", checks-failures, " failures: ", failures)
	get_tree().quit(0 if failures == 0 else 1)
