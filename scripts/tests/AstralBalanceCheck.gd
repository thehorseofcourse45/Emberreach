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
    for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid), 120)
    for item in ["worldheart_crown", "throneguard_gauntlets", "throneguard_sabatons", "throneguard_platelegs", "throneguard_cuirass", "star_throne_blade", "starfall_aegis", "heralds_sigil", "diamond_ring_of_warding"]:
        BankManager.add_item_guaranteed(item, 1)
        EquipmentManager.equip(item)
    BankManager.add_item_guaranteed("shark", 50000)
    BankManager.add_item_guaranteed("potion_dr_3", 6)
    EquipmentManager.food_slots[0] = "shark"
    PlayerData.settings.auto_eat_tier = 3
    call_deferred("run")

func run() -> void:
    var failures := 0
    for i in range(RaidManager.ASTRAL_TRIALS.size()):
        var trial: Dictionary = RaidManager.ASTRAL_TRIALS[i]
        var snapshot: Dictionary = CombatSimulatorManager.build_snapshot("dungeon", "final_horizon", "melee", "slash", true)
        var monsters: Array = []
        for id in RaidManager.astral_sequence(i):
            var monster: Dictionary = CombatSimulatorManager._monster_record(str(id))
            monster.hitpoints = roundi(float(monster.hitpoints) * (1.0 + float(i) * 0.025))
            monsters.append(monster)
        snapshot.monsters = monsters
        var result: Dictionary = CombatSimulator.simulate(snapshot, 2, 120)
        print(trial.name, ": ", result.wins, "/2 wins; deaths ", result.deaths, "; timeouts ", result.timeouts, "; food ", result.food_eaten)
        if int(result.wins) < 1: failures += 1
    print("Astral balance: ", failures, " failures")
    get_tree().quit(0 if failures == 0 else 1)
