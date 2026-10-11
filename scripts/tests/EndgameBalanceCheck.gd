extends Node
var failed := false
func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid), 120)
	for item in ["throneguard_helm", "throneguard_gauntlets", "throneguard_sabatons", "throneguard_platelegs", "throneguard_cuirass", "herald_godsword", "herald_bulwark", "heralds_sigil", "diamond_ring_of_warding"]:
		BankManager.add_item_guaranteed(item, 1)
		EquipmentManager.equip(item)
	BankManager.add_item_guaranteed("shark", 10000)
	EquipmentManager.food_slots[0] = "shark"
	PlayerData.settings.auto_eat_tier = 3
	for id in ["astral_sanctum", "storm_citadel", "crown_of_embers"]:
		var snapshot: Dictionary = CombatSimulatorManager.build_snapshot("dungeon", id, "melee", "slash")
		var report: Dictionary = CombatSimulator.simulate(snapshot, 10, 120)
		if int(report.wins) < 9 or int(report.deaths) > 0:
			failed = true
			push_error("Prepared level-120 loadout cannot reliably clear " + id)
		print(id, ": ", report.wins, "/10 wins; deaths ", report.deaths, "; timeouts ", report.timeouts, "; avg time ", report.elapsed_seconds / 10.0, "; player ", snapshot.player)
	get_tree().quit(1 if failed else 0)
