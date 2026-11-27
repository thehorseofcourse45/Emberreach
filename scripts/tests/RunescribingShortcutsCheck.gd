extends Node

const IDS := ["scribe_bronze_volley", "scribe_leather_kit", "scribe_ghoststeel_yield", "scribe_fen_rations", "scribe_catalyst", "scribe_runic_cache"]
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: ", label)

func _ready() -> void:
    GameManager.cli_mode = true
    GameManager.is_paused = true
    SaveManager.autosave_enabled = false
    SaveManager.save_on_major_event = false
    GameManager.start_new_game("standard")
    GameManager.is_paused = true
    for id in IDS:
        var action: Dictionary = DataLoader.get_action("alt_magic", id)
        check(not action.is_empty(), id + " exists")
        if action.is_empty():
            continue
        PlayerData.set_level("alt_magic", int(action.level_required) - 1)
        check(not SkillManager.start_action("alt_magic", id), id + " level gate")
        PlayerData.set_level("alt_magic", int(action.level_required))
        for ingredient in action.input_items:
            BankManager.add_item_guaranteed(ingredient, int(action.input_items[ingredient]) * 10)
        var before := {}
        for output in action.output_items:
            before[output] = BankManager.get_count(output)
        check(SkillManager.start_action("alt_magic", id, 1), id + " starts")
        SkillManager.tick(SkillManager.current_interval + 0.01)
        for output in action.output_items:
            check(BankManager.get_count(output) >= int(before[output]) + int(action.output_items[output]), id + " produces " + output)
        SkillManager.stop_action()
        var first: String = str(action.output_items.keys()[0])
        var previous := BankManager.get_count(first)
        check(SkillManager.start_action("alt_magic", id, 2), id + " starts offline")
        SkillManager.simulate_elapsed(SkillManager.current_interval * 2 + 0.1)
        check(BankManager.get_count(first) > previous, id + " produces offline")
        SkillManager.stop_action()
        var icon: Texture2D = AssetRegistry.icon("alt_magic", id)
        check(icon != null and icon.resource_path == "res://assets/icons/alt_magic/%s.png" % id and icon.get_size() == Vector2(32, 32), id + " icon")
    print("RUNESCRIBING SHORTCUTS: ", checks, " checks; ", failures, " failures")
    get_tree().quit(1 if failures else 0)
