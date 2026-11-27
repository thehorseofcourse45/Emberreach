extends Node
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	PlayerData.initialize_new_game()
	PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
	BankManager.deserialize({"purchased_slots": 200})
	EquipmentManager.deserialize({})
	for skill in DataLoader.get_skill_ids(): PlayerData.set_level(str(skill), 120)
	for item in ["worldheart_crown", "throneguard_gauntlets", "throneguard_sabatons", "throneguard_platelegs", "throneguard_cuirass", "starfall_aegis", "heralds_sigil", "diamond_ring_of_warding"]:
		BankManager.add_item_guaranteed(item, 1)
		EquipmentManager.equip(item)
	BankManager.add_item_guaranteed("shark", 100000)
	BankManager.add_item_guaranteed("herald_arrow", 100000)
	BankManager.add_item_guaranteed("umbral_rune", 100000)
	for id in DataLoader.get_dungeon("solar_apex").get("entry_items", {}):
		BankManager.add_item_guaranteed(str(id), int(DataLoader.get_dungeon("solar_apex").entry_items[id]))
	EquipmentManager.food_slots[0] = "shark"
	PlayerData.settings.auto_eat_tier = 3
	call_deferred("run")
func run() -> void:
	var failures := 0
	for entry in [["melee", "star_throne_blade"], ["ranged", "eclipse_longbow"], ["magic", "dreamglass_staff"]]:
		BankManager.add_item_guaranteed(str(entry[1]), 1)
		if not EquipmentManager.equip(str(entry[1])):
			print("FAIL: equip ", entry[1]); failures += 1; continue
		var snapshot: Dictionary = CombatSimulatorManager.build_snapshot("dungeon", "solar_apex", str(entry[0]), "slash", true)
		if snapshot.is_empty():
			print("FAIL: snapshot ", CombatSimulatorManager.last_error); failures += 1; continue
		var report: Dictionary = CombatSimulator.simulate(snapshot, 3, 120)
		print(entry[0], ": ", report.wins, "/3 wins; deaths ", report.deaths, "; timeouts ", report.timeouts, "; max hit ", snapshot.player.max_hit)
		if int(report.wins) < 2 or int(report.deaths) > 0: failures += 1
	print("Combat styles: ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
