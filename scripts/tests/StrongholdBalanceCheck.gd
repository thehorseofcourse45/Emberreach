extends Node
var failures := 0
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	PlayerData.initialize_new_game()
	PlayerData.settings=SettingsDefaults.DEFAULTS.duplicate(true)
	BankManager.deserialize({"purchased_slots":200})
	EquipmentManager.deserialize({})
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid),120)
	for item in ["throneguard_helm","throneguard_gauntlets","throneguard_sabatons","throneguard_platelegs","throneguard_cuirass","embercrown_blade","herald_bulwark","heralds_sigil","diamond_ring_of_warding"]:
		BankManager.add_item_guaranteed(item,1)
		EquipmentManager.equip(item)
	BankManager.add_item_guaranteed("shark",5000)
	EquipmentManager.food_slots[0]="shark"
	PlayerData.settings.auto_eat_tier=3
	call_deferred("run")
func run() -> void:
	var ids: Array = ["ironveil_bastion","frostglass_citadel","blightroot_hold","sunken_dominion","eclipse_throne"]
	for id in ids:
		var d: Dictionary=DataLoader.get_dungeon(id)
		for item in d.entry_items: BankManager.add_item_guaranteed(str(item),int(d.entry_items[item]))
		var snapshot: Dictionary=CombatSimulatorManager.build_snapshot("dungeon",id,"melee","slash",true)
		var report: Dictionary=CombatSimulator.simulate(snapshot,5,120)
		print(id,": ",report.wins,"/5 wins; deaths ",report.deaths,"; timeouts ",report.timeouts,"; avg time ",float(report.elapsed_seconds)/5,"; food ",report.food_eaten)
		if int(report.wins)<4 or int(report.deaths)>0: failures+=1
		for gear in d.rewards_first_clear.items:
			BankManager.add_item_guaranteed(str(gear),1)
			EquipmentManager.equip(str(gear))
	# Bare equipment should not defeat an endgame siege merely by bringing food.
	EquipmentManager.deserialize({})
	EquipmentManager.food_slots[0]="shark"
	var poor: Dictionary=CombatSimulatorManager.build_snapshot("dungeon","ironveil_bastion","melee","slash",true)
	var weak: Dictionary=CombatSimulator.simulate(poor,1,120)
	if int(weak.wins)>0: failures+=1
	print("Stronghold balance: ",failures," failures; unequipped wins ",weak.wins)
	get_tree().quit(0 if failures==0 else 1)
