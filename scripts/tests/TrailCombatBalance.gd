extends Node

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	BankManager.deserialize({"purchased_slots":200})
	EquipmentManager.deserialize({})
	for skill in ["attack", "strength", "defence", "hitpoints"]: PlayerData.set_level(skill, 40)
	for item in ["mithril_helmet", "mithril_platebody", "mithril_platelegs", "mithril_boots", "mithril_gloves", "mithril_scimitar", "mithril_shield"]:
		BankManager.add_item_guaranteed(item,1)
		if not EquipmentManager.equip(item):
			printerr("Could not equip ",item); get_tree().quit(1); return
	BankManager.add_item_guaranteed("shrimp", 2000)
	EquipmentManager.food_slots[0] = "shrimp"
	PlayerData.settings.auto_eat_tier = 3
	CombatManager.seed_rng(42)
	RaidManager._rng.seed = 42
	call_deferred("run")

func run() -> void:
	if not RaidManager.start_raid("normal"):
		printerr("Could not begin journey"); get_tree().quit(1); return
	var ticks := 0
	while RaidManager.active and ticks < 100000:
		if RaidManager.run_stage == "route":
			if not RaidManager.choose_route(0):
				printerr("Could not choose next patrol"); get_tree().quit(1); return
		else:
			CombatManager.tick(0.5)
		ticks += 1
	var success: bool = not RaidManager.active and int(RaidManager.trail_completions.get("normal", 0)) == 1
	print("Trail live combat: ", "PASS" if success else "FAIL", "; elapsed seconds ", ticks * 0.5, "; food used ", 2000 - BankManager.get_count("shrimp"))
	get_tree().quit(0 if success else 1)
