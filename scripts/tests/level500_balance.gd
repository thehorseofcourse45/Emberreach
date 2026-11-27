extends Node

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid),120)
	for item in ["throneguard_helm","throneguard_gauntlets","throneguard_sabatons","throneguard_platelegs","throneguard_cuirass","embercrown_blade","herald_bulwark","heralds_sigil","diamond_ring_of_warding"]:
		BankManager.add_item_guaranteed(item,1)
		EquipmentManager.equip(item)
	BankManager.add_item_guaranteed("shark",5000)
	EquipmentManager.food_slots[0] = "shark"
	PlayerData.settings.auto_eat_tier = 3
	for id in ["riftbound_spire","final_horizon"]:
		var d: Dictionary = DataLoader.get_dungeon(id)
		for item in d.entry_items: BankManager.add_item_guaranteed(str(item),int(d.entry_items[item]))
		var snapshot: Dictionary = CombatSimulatorManager.build_snapshot("dungeon",id,"melee","slash",true)
		var result: Dictionary = CombatSimulator.simulate(snapshot,5,120)
		print(id, ": ", result.wins, "/5 wins; deaths ", result.deaths, "; timeouts ", result.timeouts, "; average seconds ", float(result.elapsed_seconds)/5.0)
		assert(int(result.wins)>=4 and int(result.deaths)==0)
		for item in d.rewards_first_clear.items:
			BankManager.add_item_guaranteed(str(item),1)
			EquipmentManager.equip(str(item))
	print("LEVEL 500 EXPEDITION BALANCE PASS")
	get_tree().quit()
