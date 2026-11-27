extends Node
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("run")
func run() -> void:
	GameManager.start_new_game("standard")
	BankManager.deserialize({"purchased_slots":500})
	EquipmentManager.deserialize({})
	var crafted: Dictionary = {}
	for spec in [["smithing","temper_siegebound_platelegs","throneguard_platelegs","siegebound_platelegs"], ["fletching","reinforce_dawnbloom_bow","dawnbloom_longbow","dawnbloom_siege_bow"], ["runecrafting","attune_dawn_wand","dawn_wand","attuned_dawn_wand"], ["crafting","set_siege_sigil","heralds_sigil","siege_sigil"]]:
		var skill: String = spec[0]
		var action: Dictionary = {}
		for candidate in DataLoader.get_skill_actions(skill):
			if str(candidate.id) == str(spec[1]): action = candidate
		check(not action.is_empty(), spec[1] + " exists")
		PlayerData.set_level(skill, int(action.level_required))
		check(not SkillManager.can_perform(skill, str(spec[1])), spec[1] + " needs materials")
		for id in action.input_items:
			var input_id: String = str(id)
			if str(spec[1]) == "temper_siegebound_platelegs" and input_id == str(spec[2]): input_id += "__quality_fine"
			BankManager.add_item_guaranteed(input_id, int(action.input_items[id]))
		PlayerData.set_level(skill, int(action.level_required) - 1)
		check(not SkillManager.can_perform(skill, str(spec[1])), spec[1] + " respects level")
		PlayerData.set_level(skill, int(action.level_required))
		check(SkillManager.start_action(skill, str(spec[1])), spec[1] + " starts")
		var result: Dictionary = SkillManager.perform_action()
		SkillManager.stop_action()
		var outputs: Dictionary = result.get("items", {})
		var output_id: String = str(outputs.keys()[0]) if not outputs.is_empty() else ""
		crafted[str(spec[3])] = output_id
		check(bool(result.get("success",false)) and output_id.begins_with(str(spec[3])) and BankManager.has_item(output_id, 1), spec[1] + " crafts upgrade")
		check(BankManager.count_with_variants(str(spec[2])) == 0, spec[1] + " consumes original, including quality variants")
		check(not Goals.sources_for_item(str(spec[3])).is_empty(), spec[3] + " source discoverable")
	PlayerData.set_level("enchanting",120)
	PlayerData.set_level("defence",120)
	var base: String = str(crafted.get("siegebound_platelegs", ""))
	check(EnchantingManager.can_enchant(base,"steadfast").contains("Clear"), "armor enchant requires its dungeon")
	PlayerData.stats["dungeons_cleared"]["emberrift_cavern"] = 1
	check(EnchantingManager.can_enchant(base,"steadfast") == "", "dungeon clear unlocks armor enchant")
	var cost: Dictionary = EnchantingManager.enchant_cost(base,"steadfast")
	for id in cost:
		if str(id) != base: BankManager.add_item_guaranteed(str(id),int(cost[id]))
	check(EnchantingManager.begin_enchant(base,"steadfast"), "begin enchanting")
	var pending: Dictionary = EnchantingManager.pending.duplicate(true)
	var variant_id: String = str(pending.output.keys()[0])
	var enchant_result: Dictionary = SkillManager.perform_action()
	SkillManager.stop_action()
	if not (enchant_result.get("items", {}) as Dictionary).is_empty(): variant_id = str(enchant_result.items.keys()[0])
	check(BankManager.has_item(variant_id,1) and not BankManager.has_item(base,1), "enchant consumes base and creates variant")
	check(EquipmentManager.equip(variant_id), "enchanted armor equips")
	check(ModifierManager.get_modifier("food_healing_percent") >= 12.0, "crafted and enchanted bonuses apply")
	var save: Dictionary = SaveManager.build_save_data()
	SaveManager._apply(save)
	EventBus.game_loaded.emit()
	check(EquipmentManager.get_equipped(2) == variant_id and ModifierManager.get_modifier("food_healing_percent") >= 12.0, "equipped enchant survives save and load")
	var bow: String = str(crafted.get("dawnbloom_siege_bow", ""))
	check(EnchantingManager.can_enchant(bow,"siegebreaker").contains("Clear"), "weapon enchant requires its dungeon")
	PlayerData.stats["dungeons_cleared"]["crown_of_embers"] = 1
	check(EnchantingManager.can_enchant(bow,"siegebreaker") == "", "weapon enchant unlocks after clear")
	check(not EnchantingManager.recipe("spellward").is_empty(), "spellward enchant available")
	print("Combat crafting expansion: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
