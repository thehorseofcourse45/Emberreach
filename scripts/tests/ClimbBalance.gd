extends Node
func _ready() -> void:
    GameManager.cli_mode = true
    GameManager.is_paused = true
    SaveManager.autosave_enabled = false
    SaveManager.save_on_major_event = false
    PlayerData.initialize_new_game()
    PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
    BankManager.deserialize({"purchased_slots":200})
    EquipmentManager.deserialize({})
    for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid),120)
    for item in ["worldheart_crown","throneguard_gauntlets","throneguard_sabatons","throneguard_platelegs","throneguard_cuirass","star_throne_blade","starfall_aegis","heralds_sigil","diamond_ring_of_warding"]:
        BankManager.add_item_guaranteed(item,1)
        EquipmentManager.equip(item)
    BankManager.add_item_guaranteed("shark",50000)
    BankManager.add_item_guaranteed("potion_dr_3",1000)
    EquipmentManager.food_slots[0] = "shark"
    PlayerData.settings.auto_eat_tier = 3
    call_deferred("run")
func run() -> void:
    var ids := ["emberglass_bastion","tempest_zenith_keep","voidglass_monolith","astral_concord","eternal_horizon_citadel"]
    var failures := 0
    for id in ids:
        var snapshot: Dictionary = CombatSimulatorManager.build_snapshot("dungeon", id, "melee", "slash", true)
        if snapshot.is_empty():
            print("FAIL snapshot: ", id, " ", CombatSimulatorManager.last_error)
            failures += 1
            continue
        var result: Dictionary = CombatSimulator.simulate(snapshot, 2, 120)
        print(id, ": ", result.wins, "/2 wins; deaths ", result.deaths, "; timeouts ", result.timeouts, "; food ", result.food_eaten)
        if int(result.wins) < 1: failures += 1
    print("Stronghold climb balance: ", failures, " failures")
    get_tree().quit(0 if failures == 0 else 1)
