extends Node
var failures := 0
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	SaveManager._write_in_progress=true
	call_deferred("run")
func run() -> void:
	var builds=[
		["scarecrow_cellar",15,"iron"],
		["ashwood_nest",35,"steel"],
		["barrow_chapel",45,"mithril"],
		["rookwatch_tower",65,"adamantite"],
		["shaleheart_vault",70,"adamantite"],
		["saltglass_catacombs",85,"runite"]]
	for build in builds:
		PlayerData.initialize_new_game()
		PlayerData.settings=SettingsDefaults.DEFAULTS.duplicate(true)
		BankManager.deserialize({"purchased_slots":200})
		EquipmentManager.deserialize({})
		DungeonModifierManager.selected_ids.clear()
		for skill in ["attack","strength","defence","hitpoints","ranged","magic","slayer"]: PlayerData.set_level(skill,int(build[1]))
		for piece in ["helmet","platebody","platelegs","boots","shield","scimitar"]:
			var id: String=str(build[2])+"_"+piece
			if DataLoader.get_item(id).is_empty(): continue
			BankManager.add_item_guaranteed(id,1)
			if not EquipmentManager.equip(id): failures+=1; print("FAIL equip: ",id)
		BankManager.add_item_guaranteed("shark",500)
		EquipmentManager.food_slots[0]="shark"
		PlayerData.settings.auto_eat_tier=2
		var snapshot: Dictionary=CombatSimulatorManager.build_snapshot("dungeon",str(build[0]),"melee","slash",true)
		var report: Dictionary=CombatSimulator.simulate(snapshot,3,17)
		print(build[0]," level ",build[1]," ",build[2],": ",report.wins,"/3 wins; deaths ",report.deaths,"; timeouts ",report.timeouts,"; avg seconds ",float(report.elapsed_seconds)/3.0,"; food ",report.food_eaten)
		if int(report.wins)!=3 or int(report.deaths)>0 or int(report.timeouts)>0: failures+=1
	print("Early monster balance: ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
