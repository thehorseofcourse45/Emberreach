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
    call_deferred("run")

func run() -> void:
    ok(RaidManager.ASTRAL_TRIALS.size() == 10, "five trials")
    ok(RaidManager.astral_lock_reason(0) != "", "Final Horizon gates the chamber")
    var locked_panel := preload("res://scripts/ui/panels/RaidPanel.gd").new()
    add_child(locked_panel)
    var locked_list: ItemList = locked_panel.find_child("AstralTrialList", true, false)
    if locked_list != null: locked_list.item_selected.emit(4)
    var locked_buttons := locked_panel.find_children("*", "Button", true, false).filter(func(b): return b.text == "Begin trial")
    ok(locked_buttons.size() == 1 and locked_buttons[0].disabled, "locked trial cannot start from selector")
    locked_panel.free()
    PlayerData.completion_log.dungeons["final_horizon"] = true
    PlayerData.raid_coins = 3000.0
    ok(RaidManager.buy("raid_wave_skip"), "old outfitter purchase remains available")
    ok(RaidManager.astral_lock_reason(0) == "" and RaidManager.astral_lock_reason(1) != "", "first trial opens")
    ok(RaidManager.start_astral(0), "old active trial fixture starts")
    CombatManager.context.monsters = ["astral_gatekeeper"]
    CombatManager.context.index = 0
    CombatManager._spawn_monster("astral_gatekeeper")
    var old_save: Dictionary = SaveManager.build_save_data().duplicate(true)
    SaveManager._apply(old_save)
    ok(CombatManager.context.monsters == ["astral_gatekeeper"] and CombatManager.current_monster_id == "astral_gatekeeper", "old single-boss save resumes unchanged")
    CombatManager.player_hp = 100000000.0
    CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
    CombatManager.tick(60)
    ok(not RaidManager.active and RaidManager.astral_completions.has("astral_vestibule"), "old single-boss save can complete")
    RaidManager.astral_completions.erase("astral_vestibule")
    for index in range(10):
        var trial: Dictionary = RaidManager.ASTRAL_TRIALS[index]
        var sequence: Array = RaidManager.astral_sequence(index)
        ok(sequence.size() == 25 and str(sequence.back()) == trial.enemy, "24 enemies followed by final boss")
        for mid in trial.wave_enemies:
            ok(DataLoader.get_monster(str(mid)).get("id") == mid and ResourceLoader.exists("res://assets/sprites/monsters/%s.png" % mid), "new enemy and art exist")
            ok(Goals._route_for_monster(str(mid)).get("trial_id") == trial.id, "collection source routes to its trial")
        ok(RaidManager.astral_lock_reason(index) == "", "trial unlocks in order")
        ok(DataLoader.get_monster(str(trial.enemy)).get("id") == trial.enemy, "unique enemy registered")
        ok(ResourceLoader.exists("res://assets/icons/dungeons/%s.png" % trial.id), "trial icon imported")
        ok(ResourceLoader.exists("res://assets/sprites/monsters/%s.png" % trial.enemy), "enemy sprite imported")
        var before: float = PlayerData.raid_coins
        ok(RaidManager.start_astral(index), "trial starts")
        ok(CombatManager.current_monster_id == sequence[0], "correct first enemy enters combat")
        for step in range(sequence.size()):
            ok(CombatManager.current_monster_id == sequence[step], "correct encounter order")
            if index == 0 and step == 4:
                var saved: Dictionary = SaveManager.build_save_data().duplicate(true)
                SaveManager._apply(saved)
                ok(RaidManager.astral_encounter == trial.id and CombatManager.current_monster_id == sequence[step] and int(CombatManager.context.index) == step, "mid-trial save resumes")
            if step < sequence.size() - 1: ok(not RaidManager.astral_completions.has(str(trial.id)), "no credit before the final boss")
            CombatManager.player_hp = 100000000.0
            CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
            CombatManager.tick(60)
        ok(not RaidManager.active and int(RaidManager.astral_completions.get(trial.id, 0)) == 1, "win records completion")
        ok(PlayerData.raid_coins >= before + float(trial.marks), "win banks marks")
    var persisted: Dictionary = SaveManager.build_save_data().duplicate(true)
    SaveManager._apply(persisted)
    ok(RaidManager.astral_completions.size() == 10 and int(RaidManager.purchased.get("raid_wave_skip", 0)) == 1, "progress and old purchases survive save/load")
    var legacy := {"active":true, "trail_mode":true, "difficulty":"normal", "wave":1, "coins_this_raid":120, "run_stage":"route", "pending_routes":[{"id":"trail_patrol"}], "purchased":{"raid_wave_skip":1}}
    RaidManager.deserialize(legacy)
    ok(RaidManager.active and RaidManager.trail_mode and RaidManager.astral_encounter == "", "old in-progress trail survives")
    var before: float = PlayerData.raid_coins
    RaidManager.end_raid()
    ok(PlayerData.raid_coins >= before + 120 and int(RaidManager.purchased.raid_wave_skip) == 1, "legacy currency and purchases retained")
    SaveManager._apply(persisted)
    var panel := preload("res://scripts/ui/panels/RaidPanel.gd").new()
    add_child(panel)
    var list: ItemList = panel.find_child("AstralTrialList", true, false)
    ok(list != null and list.item_count == 10, "five trials in combat-style selector")
    if list != null:
        list.item_selected.emit(2)
        ok(str(panel.detail_context().get("area_id", "")) == "eclipse_oratory", "selection updates details context")
    var buttons := panel.find_children("*", "Button", true, false).filter(func(b): return b.text == "Begin trial")
    ok(buttons.size() == 1 and not buttons[0].disabled, "selected unlocked trial has one start button")
    var detail := preload("res://scripts/ui/DetailPanel.gd").new()
    add_child(detail)
    detail.set_inline_context(panel.detail_context())
    ok(detail.has_content() and detail._title.text == "Eclipse Oratory" and detail._subtitle.text == "Astral trial", "sidebar renders selected trial")
    detail.free()
    if buttons.size() == 1:
        buttons[0].pressed.emit()
        ok(RaidManager.astral_encounter == "eclipse_oratory" and CombatManager.current_monster_id == "eclipse_umbrawisp", "selected trial button starts the correct fight")
        RaidManager.end_raid()
    panel.free()
    print("Astral Chamber: ", checks, " checks; ", failures, " failures")
    get_tree().quit(0 if failures == 0 else 1)
