extends Node
var checks := 0
var failures := 0
func ok(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures += 1
        print("FAIL: ", message)
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
    Quests.deserialize({"claimed":{"expedition_charter":true}})
    call_deferred("run")
func run() -> void:
    var ids := ["stormbreak_redoubt", "obsidian_crown", "moonfall_bastion", "thornstar_citadel", "dawnspire_fortress", "furnace_of_fallen_stars", "maw_of_abyssal_tide", "archive_of_the_last_moon", "the_voidborne_nexus", "sanctum_of_eternal_dawn"]
    var unique_enemies := {}
    var unique_rewards := {}
    for n in range(ids.size()):
        var id: String = ids[n]
        var d: Dictionary = DataLoader.get_dungeon(id)
        var siege := n < 5
        ok(not d.is_empty() and bool(d.get("stronghold" if siege else "raid", false)), id + " is listed in the right category")
        ok(ResourceLoader.exists("res://assets/icons/dungeons/%s.png" % id), id + " has its own icon")
        ok(d.get("monsters", []).size() == 3 if siege else d.get("monsters", []).size() >= 25, id + " has full encounter sequence")
        ok(int(d.level_range.back()) <= 5000000, id + " respects combat level cap")
        var authored: Array = []
        for mid in d.monsters:
            if not authored.has(str(mid)): authored.append(str(mid))
        ok(authored.size() == 3, id + " has three exclusive enemy types")
        for mid in authored:
            var enemy: Dictionary = DataLoader.get_monster(str(mid))
            ok(not enemy.is_empty() and not unique_enemies.has(str(mid)), id + " has unique enemy " + str(mid))
            unique_enemies[str(mid)] = true
            ok(ResourceLoader.exists("res://assets/sprites/monsters/%s.png" % mid), str(mid) + " has unique art")
            ok(ContentValidator.validate_monster_mechanics(str(mid), enemy).is_empty(), str(mid) + " mechanics are valid")
        var final_boss: Dictionary = DataLoader.get_monster(str(d.monsters.back()))
        var signature := "signature_" + str(d.monsters.back())
        ok(final_boss.get("special_attacks", []).has(signature) and not DataLoader.get_special_attack(signature).is_empty(), id + " boss has its own signature attack")
        var reward_id: String = str(d.rewards_first_clear.items.keys()[0])
        ok(not unique_rewards.has(reward_id) and DataLoader.items.has(reward_id), id + " has unique first-clear reward")
        unique_rewards[reward_id] = true
        ok(ResourceLoader.exists("res://assets/icons/items/%s.png" % reward_id), reward_id + " has unique icon")
        if not siege:
            var options := PlayerData.raid_exchange_items(id)
            ok(options.size() == 3, id + " offers three exchangeable drops")
            for option in options:
                var drop_id: String = str(option.item_id)
                ok(not unique_rewards.has(drop_id) and ResourceLoader.exists("res://assets/icons/items/%s.png" % drop_id), drop_id + " has unique reward and art")
                unique_rewards[drop_id] = true
        for ingredient in d.entry_items: BankManager.add_item_guaranteed(str(ingredient), int(d.entry_items[ingredient]))
        PlayerData.completion_log.dungeons.erase(str(d.requires_dungeon))
        ok(CombatManager.dungeon_lock_reason(id).begins_with("Clear"), id + " requires its prior clear")
        PlayerData.completion_log.dungeons[str(d.requires_dungeon)] = true
        var ctx := {"type":"dungeon", "id":id, "monsters":d.monsters, "endless":false}
        ok(not CombatManager.start_combat({"type":"dungeon", "id":id, "monsters":[d.monsters[-1]], "endless":false}), id + " cannot skip encounters")
        ok(CombatManager.start_combat(ctx), id + " starts")
        for step in range(d.monsters.size()):
            var mid: String = str(d.monsters[step])
            if n == 5 and step == 5:
                var saved: Dictionary = SaveManager.build_save_data().duplicate(true)
                SaveManager._apply(saved)
                ok(CombatManager.current_monster_id == mid and int(CombatManager.context.index) == step, "new raid resumes at the saved encounter")
            ok(CombatManager.current_monster_id == mid, id + " ordered encounter " + str(mid))
            CombatManager.player_hp = 100000000.0
            CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
            CombatManager.tick(6)
        ok(CombatManager.state == CombatManager.State.IDLE and PlayerData.completion_log.dungeons.has(id), id + " completes")
        ok(BankManager.get_total_owned(reward_id) > 0, id + " awards first-clear item")
        var gear_ids: Array = [reward_id]
        if not siege:
            for option in PlayerData.raid_exchange_items(id):
                var gear_id := str(option.item_id)
                BankManager.add_item_guaranteed(gear_id, 1)
                gear_ids.append(gear_id)
        for gear_id in gear_ids:
            var gear: Dictionary = DataLoader.get_item(str(gear_id))
            ok(EquipmentManager.equip(str(gear_id)), str(gear_id) + " can be equipped")
            for modifier in gear.get("passive_modifiers", {}):
                ok(ModifierManager.get_modifier(str(modifier)) >= float(gear.passive_modifiers[modifier]), str(gear_id) + " activates " + str(modifier))
            ok(EquipmentManager.unequip(int(gear.equipment_slot)), str(gear_id) + " can be unequipped")
    ok(unique_enemies.size() == 30 and unique_rewards.size() == 25, "30 unique enemies and 25 rewards")
    var panel := preload("res://scripts/ui/panels/CombatPanel.gd").new()
    panel.expeditions_only = true
    add_child(panel)
    panel.focus_route({"area_id":"stormbreak_redoubt"})
    ok(panel.find_children("*", "Label", true, false).any(func(label): return str(label.text).contains("Squall Gate")), "stronghold stage names appear in the encounter panel")
    panel.free()
    var state := SaveManager.build_save_data().duplicate(true)
    PlayerData.initialize_new_game()
    SaveManager._apply(state)
    ok(PlayerData.completion_log.dungeons.has(ids[0]) and PlayerData.completion_log.dungeons.has(ids[-1]), "new clears survive save/load")
    print("Endgame ten: ", checks, " checks; ", failures, " failures")
    get_tree().quit(0 if failures == 0 else 1)
