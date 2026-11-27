extends Node
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("run")
func run() -> void:
	var ids := ["shale_watch", "quarry_of_echoes", "broken_sentry_keep", "frostbound_sinkhole", "brine_tunnels", "saltglass_crypt", "undercroft_annex", "sunken_armory", "wyrmwatch_gallery", "shrine_of_squalls", "drowned_archive", "stonebound_labyrinth", "ember_choir_catacombs", "duskward_foundry", "cinder_bastion_depths"]
	var failures := 0
	for i in ids.size():
		PlayerData.initialize_new_game()
		PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
		BankManager.deserialize({"purchased_slots": 200})
		EquipmentManager.deserialize({})
		var tier: String = "adamantite" if i < 4 else ("runite" if i < 8 else ("dragonite" if i < 12 else "herald"))
		var skill: int = 60 if i < 4 else (80 if i < 8 else (95 if i < 12 else 120))
		for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid), skill)
		var sword: String = "herald_godsword" if tier == "herald" else tier + "_sword"
		for item in [tier + "_helmet", tier + "_platebody", sword]:
			BankManager.add_item_guaranteed(item, 1)
			if not EquipmentManager.equip(item): print("FAIL equip ", item); failures += 1
		BankManager.add_item_guaranteed("shark", 10000)
		EquipmentManager.food_slots[0] = "shark"
		PlayerData.settings.auto_eat_tier = 3
		var snapshot: Dictionary = CombatSimulatorManager.build_snapshot("dungeon", ids[i], "melee", "slash", true)
		var report: Dictionary = CombatSimulator.simulate(snapshot, 1, 120)
		print(ids[i], ": ", report.wins, "/1 wins; deaths ", report.deaths, "; timeouts ", report.timeouts)
		if int(report.wins) != 1: failures += 1
	print("Bridge balance: ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
