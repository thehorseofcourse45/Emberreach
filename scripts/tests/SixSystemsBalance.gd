extends Node
func _ready() -> void:
	GameManager.cli_mode=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	SaveManager._write_in_progress=true
	GameManager.start_new_game("standard")
	GameManager.is_paused=true
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid),120)
	for item in ["throneguard_helm","throneguard_gauntlets","throneguard_sabatons","throneguard_platelegs","throneguard_cuirass","herald_godsword","herald_bulwark","heralds_sigil","diamond_ring_of_warding"]:
		BankManager.add_item_guaranteed(item,1)
		EquipmentManager.equip(item)
	BankManager.add_item_guaranteed("shark",10000)
	EquipmentManager.food_slots[0]="shark"
	PlayerData.settings.auto_eat_tier=3
	var failed := false
	for id in ["threat_sundered_reaches","threat_drowned_reach","threat_heralds_march","dream_choir","dream_tide","dream_sovereign","endless_ashes","endless_tides","endless_stars"]:
		var snap: Dictionary = CombatSimulatorManager.build_snapshot("dungeon",id,"melee","slash")
		var report: Dictionary = CombatSimulator.simulate(snap,10,120)
		print(id,": ",report.wins,"/10 wins, deaths ",report.deaths,", timeouts ",report.timeouts,", avg minutes ",snappedf(float(report.elapsed_seconds)/600.0,0.1))
		if int(report.wins)<9 or int(report.deaths)>0: failed=true
		if id.begins_with("endless_"):
			for monster in snap.monsters:
				monster.hitpoints=roundi(float(monster.hitpoints)*(1.0+0.12*49))
				monster.max_hit=roundi(float(monster.max_hit)*(1.0+0.04*49))
			var deep: Dictionary = CombatSimulator.simulate(snap,3,120)
			print(id," floor 50: ",deep.wins,"/3 wins, deaths ",deep.deaths,", timeouts ",deep.timeouts)
	get_tree().quit(1 if failed else 0)
