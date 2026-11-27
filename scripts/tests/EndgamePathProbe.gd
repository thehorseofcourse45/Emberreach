extends Node
const ARMOR = ["throneguard_platelegs", "throneguard_gauntlets", "throneguard_sabatons", "heralds_sigil", "diamond_ring_of_warding"]
var problems := 0
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("run")
func setup(gear: Array) -> void:
	PlayerData.initialize_new_game()
	PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
	BankManager.deserialize({"purchased_slots": 200})
	EquipmentManager.deserialize({})
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid), 120)
	for item in gear:
		if DataLoader.get_item(str(item)).is_empty():
			print("FIXTURE MISSING ITEM ", item)
			problems += 1
			continue
		BankManager.add_item_guaranteed(str(item), 1)
		if not EquipmentManager.equip(str(item)):
			print("FIXTURE EQUIP FAILED ", item)
			problems += 1
	BankManager.add_item_guaranteed("shark", 5000)
	BankManager.add_item_guaranteed("herald_arrow", 20000)
	BankManager.add_item_guaranteed("umbral_rune", 20000)
	EquipmentManager.food_slots[0] = "shark"
	PlayerData.settings.auto_eat_tier = 3

func make_snapshot(id: String, style: String = "melee") -> Dictionary:
	var dungeon: Dictionary = DataLoader.get_dungeon(id)
	for material in dungeon.get("entry_items", {}): BankManager.add_item_guaranteed(str(material), int(dungeon.entry_items[material]))
	return CombatSimulatorManager.build_snapshot("dungeon", id, style, "slash", true)

func measure(label: String, snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		print("FIXTURE EMPTY ", label, " ", CombatSimulatorManager.last_error)
		problems += 1
		return
	var report: Dictionary = CombatSimulator.simulate(snapshot, 3, 20261103)
	print("PATH|", label, "|wins=", report.wins, "/3|deaths=", report.deaths, "|timeouts=", report.timeouts,
		"|minutes=", snappedf(float(report.elapsed_seconds) / 180.0, 0.1), "|food=", snappedf(float(report.food_eaten) / 3.0, 0.1),
		"|maxhit=", snapshot.player.max_hit)

func run() -> void:
	var cases := [
		["emberrift_cavern", ["herald_helmet", "herald_platebody", "herald_godsword"]],
		["tidewrought_temple", ["herald_helmet", "herald_platebody", "herald_godsword", "herald_bulwark"]],
		["moonbriar_mausoleum", ["herald_helmet", "herald_platebody", "herald_godsword", "herald_bulwark"]],
		["gilded_clockwork_vault", ["herald_helmet", "herald_platebody", "herald_godsword", "herald_bulwark"]],
		["stormglass_observatory", ["herald_helmet", "throneguard_cuirass", "herald_godsword", "herald_bulwark"]],
		["celestial_rift_gate", ["herald_helmet", "throneguard_cuirass", "herald_godsword", "herald_bulwark"]],
		["ironveil_bastion", ["herald_helmet", "throneguard_cuirass", "embercrown_blade", "herald_bulwark"]],
		["frostglass_citadel", ["herald_helmet", "throneguard_cuirass", "embercrown_blade", "ironveil_aegis"]],
		["eclipse_throne", ["herald_helmet", "blightroot_cuirass", "embercrown_blade", "ironveil_aegis"]],
		["worldheart_citadel", ["eclipse_diadem", "blightroot_cuirass", "embercrown_blade", "starfall_aegis"]],
		["emberglass_bastion", ["worldheart_crown", "blightroot_cuirass", "embercrown_blade", "starfall_aegis"]],
		["voidglass_monolith", ["worldheart_crown", "blightroot_cuirass", "embercrown_blade", "glassfire_aegis"]],
		["eternal_horizon_citadel", ["worldheart_crown", "voidglass_cuirass", "embercrown_blade", "glassfire_aegis"]],
		["infernal_crucible", ["worldheart_crown", "blightroot_cuirass", "embercrown_blade", "starfall_aegis"]],
		["leviathan_cathedral", ["worldheart_crown", "blightroot_cuirass", "crucible_blade", "starfall_aegis"]],
		["verdant_oblivion", ["worldheart_crown", "blightroot_cuirass", "crucible_blade", "starfall_aegis"]],
		["eclipse_citadel", ["worldheart_crown", "blightroot_cuirass", "crucible_blade", "starfall_aegis"]],
		["throne_beyond_stars", ["worldheart_crown", "blightroot_cuirass", "crucible_blade", "starfall_aegis"]],
		["solar_apex", ["worldheart_crown", "blightroot_cuirass", "star_throne_blade", "starfall_aegis"]],
	]
	for entry in cases:
		setup(ARMOR + entry[1])
		measure(str(entry[0]), make_snapshot(str(entry[0])))
	for i in [0, 4, 9]:
		setup(ARMOR + ["worldheart_crown", "blightroot_cuirass", "horizon_blade", "starfall_aegis"])
		var snap: Dictionary = make_snapshot("final_horizon")
		var enemies: Array = []
		for id in RaidManager.astral_sequence(i):
			var m: Dictionary = CombatSimulatorManager._monster_record(str(id))
			m.hitpoints = roundi(float(m.hitpoints) * (1.0 + float(i) * 0.025))
			enemies.append(m)
		snap.monsters = enemies
		measure("trial:" + str(RaidManager.ASTRAL_TRIALS[i].id), snap)
	print("PATH PROBE FIXTURE ERRORS ", problems)
	get_tree().quit(1 if problems else 0)
