extends Node
var failures := 0
var checks := 0
func check(v: bool, label: String):
 checks += 1
 if not v:
  failures += 1
  print("FAIL ", label)
func _ready():
 GameManager.cli_mode = true
 GameManager.is_paused = true
 SaveManager.autosave_enabled = false
 SaveManager.save_on_major_event = false
 PlayerData.initialize_new_game()
 PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
 BankManager.deserialize({"purchased_slots": 200})
 PlayerData.set_level("woodcutting", 120)
 call_deferred("run")
func run():
 var panel = load("res://scripts/ui/panels/SkillsPanel.gd").new()
 add_child(panel)
 panel.call("_select_skill", "woodcutting")
 var actions = DataLoader.get_skill_actions("woodcutting")
 var a: String = str(actions[0].id)
 var b: String = str(actions[1].id)
 var rows = panel.get("_activities")
 var first: Button = null
 var second: Button = null
 for row in rows.get_children():
  if str(row.get_meta("action_id", "")) == a: first = row.get_child(0)
  if str(row.get_meta("action_id", "")) == b: second = row.get_child(0)
 check(first != null and second != null, "activity buttons exist")
 var old_first_style = first.get_theme_stylebox("normal")
 var old_second_style = second.get_theme_stylebox("normal")
 var contexts = []
 panel.context_changed.connect(func(ctx): contexts.append(ctx))
 second.pressed.emit()
 check(panel.get("_selected_action") == b, "click selects activity")
 check(is_instance_valid(first) and is_instance_valid(second) and second.is_inside_tree(), "rows retained")
 check(str(panel.get("_highlighted_action")) == b, "highlight follows selection")
 check(contexts.size() == 1 and str(contexts[0].action_id) == b, "detail context updated")
 check(first.get_theme_stylebox("normal") != old_first_style and second.get_theme_stylebox("normal") != old_second_style, "both selection styles updated")
 PlayerData.set_level("woodcutting", 1)
 panel.call("_rebuild_activities")
 check(not first.is_inside_tree(), "level change rebuilds activity rows")
 var locked_found := false
 for row in rows.get_children():
  if row.has_meta("action_id") and (row.get_child(0) as Button).disabled: locked_found = true
 check(locked_found, "level requirement updates")
 panel.queue_free()
 await get_tree().process_frame
 print("SKILL SELECTION: ", checks, " checks; ", failures, " failures")
 get_tree().quit(1 if failures else 0)
