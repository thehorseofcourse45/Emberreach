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
	BankManager.deserialize({"purchased_slots": 500})
	SkillManager.seed_rng(20261104)
	var cases := [
		["cooking", "cook_siege_supplies", "siege_supper"],
		["herblore", "brew_wardens_draught", "wardens_draught"],
		["inscription", "inscribe_hunters_sigil", "hunters_sigil"],
		["engineering", "assemble_siege_charge", "siege_charge"]]
	for test_case in cases:
		var skill_id: String = test_case[0]
		var action_id: String = test_case[1]
		var item_id: String = test_case[2]
		var action: Dictionary = {}
		for candidate in DataLoader.get_skill_actions(skill_id):
			if str(candidate.id) == action_id: action = candidate
		check(not action.is_empty(), action_id + " exists")
		PlayerData.set_level(skill_id, int(action.level_required))
		check(not SkillManager.can_perform(skill_id, action_id), action_id + " needs ingredients")
		for ingredient in action.input_items: BankManager.add_item_guaranteed(str(ingredient), int(action.input_items[ingredient]) * 10)
		PlayerData.set_level(skill_id, int(action.level_required) - 1)
		check(not SkillManager.can_perform(skill_id, action_id), action_id + " respects skill level")
		PlayerData.set_level(skill_id, int(action.level_required))
		check(SkillManager.start_action(skill_id, action_id), action_id + " starts")
		for attempt in range(5):
			if BankManager.has_item(item_id, 1): break
			SkillManager.perform_action()
		SkillManager.stop_action()
		check(BankManager.has_item(item_id, 1), action_id + " produces item")
		check(not Goals.sources_for_item(item_id).is_empty(), item_id + " has a discoverable source")
		if item_id == "siege_supper":
			check(int(DataLoader.get_item(item_id).get("heal_amount", 0)) == 800, "supper heals 800")
			continue
		PotionManager.clear()
		check(PotionManager.use_potion(item_id), item_id + " activates")
		var item: Dictionary = DataLoader.get_item(item_id)
		for modifier in item.potion_effect:
			check(ModifierManager.get_modifier(str(modifier)) >= float(item.potion_effect[modifier]), item_id + " applies " + str(modifier))
		check(PlayerData.potion_charges == 300, item_id + " starts with 300 charges")
		PotionManager.consume_charge("woodcutting")
		check(PlayerData.potion_charges == 300, item_id + " ignores skill actions")
		PotionManager.consume_charge("combat")
		check(PlayerData.potion_charges == 299, item_id + " consumes combat charge")
		PlayerData.potion_charges = 1
		PotionManager.consume_charge("combat")
		check(not PotionManager.is_active(), item_id + " expires")
	BankManager.add_item_guaranteed("siege_charge", 1)
	check(PotionManager.use_potion("siege_charge"), "preparation activates before save")
	PotionManager.consume_charge("combat")
	var save: Dictionary = SaveManager.build_save_data()
	PotionManager.clear()
	SaveManager._apply(save)
	EventBus.game_loaded.emit()
	check(PlayerData.active_potion == "siege_charge" and PlayerData.potion_charges == 299, "active preparation and charges survive save")
	check(ModifierManager.get_modifier("combat_max_hit_percent") >= 12.0, "preparation modifier restored after load")
	print("Combat preparations: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
