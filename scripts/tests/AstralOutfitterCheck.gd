extends Node
var checks := 0
var failures := 0

func ok(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        print("FAIL: ", message)

func _ready() -> void:
    GameManager.cli_mode = true
    GameManager.is_paused = true
    SaveManager.autosave_enabled = false
    SaveManager.save_on_major_event = false
    GameManager.start_new_game("standard")
    BankManager.deserialize({"purchased_slots":200})
    call_deferred("run")

func run() -> void:
    var ids := ["astral_vanguard_blade", "cometfall_longbow", "eclipse_oracle_staff", "starward_aegis", "constellation_signet", "horizon_mantle", "observatory_blade", "observatory_helm", "nebula_bow", "nebula_cuirass", "aurora_staff", "aurora_gauntlets", "voidstar_aegis", "voidstar_greaves", "eternity_greatblade", "eternity_crown_helm"]
    ok(DataLoader.raid_shop.alt_items.slice(0, ids.size()) == ids, "six astral items replace scavenged catalog")
    ok(DataLoader.raid_shop.legacy_alt_items.has("raid_alt_weapon_1"), "legacy rewards remain recognized")
    BankManager.add_item_guaranteed("raid_alt_weapon_1", 1)
    PlayerData.raid_coins = 1000000
    ok(RaidManager.buy("raid_wave_skip"), "legacy upgrade can be purchased")
    var saved: Dictionary = SaveManager.build_save_data().duplicate(true)
    SaveManager._apply(saved)
    ok(BankManager.get_total_owned("raid_alt_weapon_1") >= 1 and int(RaidManager.purchased.get("raid_wave_skip", 0)) == 1, "old items and upgrades survive save")
    ok(RaidManager.choice_info("raid_alt_weapon_1").get("id") == "raid_alt_weapon_1", "legacy pending choice remains available")
    for id in ids:
        var item: Dictionary = DataLoader.get_item(id)
        ok(not item.is_empty() and not str(item.get("unlock_trial", "")).is_empty(), "item and unlock exist: " + id)
        RaidManager.astral_completions.erase(str(item.unlock_trial))
        ok(RaidManager.shop_lock_reason(id) != "" and not RaidManager.buy(id), "cannot buy locked item: " + id)
        RaidManager.astral_completions[str(item.unlock_trial)] = 1
        var before: float = PlayerData.raid_coins
        ok(RaidManager.shop_lock_reason(id) == "" and RaidManager.buy(id), "buy unlocked item: " + id)
        ok(PlayerData.raid_coins == before - int(item.raid_cost) and BankManager.get_total_owned(id) == 1, "correct cost and item: " + id)
        ok(ResourceLoader.exists("res://assets/icons/items/%s.png" % id), "authored icon exists: " + id)
    ok(ResourceLoader.exists("res://assets/icons/navigation/raids.png"), "navigation icon exists")
    for skill in PlayerData.COMBAT_SKILLS: PlayerData.set_level(str(skill), 120)
    for id in ids:
        ok(EquipmentManager.equip(id), "can equip " + id)
        for modifier in DataLoader.get_item(id).get("passive_modifiers", {}):
            ok(ModifierManager.get_modifier(str(modifier)) >= float(DataLoader.get_item(id).passive_modifiers[modifier]), "equipment bonus applies: " + id + " " + str(modifier))
    saved = SaveManager.build_save_data().duplicate(true)
    SaveManager._apply(saved)
    ok(RaidManager.astral_completions.size() == 10 and int(RaidManager.purchased.raid_wave_skip) == 1, "unlock and rank persist")
    var panel := preload("res://scripts/ui/panels/RaidPanel.gd").new()
    add_child(panel)
    ok(panel.find_children("*", "Button", true, false).filter(func(b): return b.text == "Buy").size() == 19, "sixteen items and three blessings displayed")
    var pictures := panel.find_children("*", "TextureRect", true, false)
    for id in ["raid_wave_skip", "raid_food", "raid_pet"]:
        var expected := "res://assets/icons/navigation/%s.png" % id
        ok(pictures.any(func(p): return p.texture != null and p.texture.resource_path == expected and p.texture.get_size() == Vector2(64, 64)), "blessing has its own icon: " + id)
    panel.free()
    print("Astral outfitter: ", checks, " checks; ", failures, " failures")
    get_tree().quit(0 if failures == 0 else 1)
