extends Node
var checks := 0
var failures := 0
func check(v: bool, message: String) -> void:
	checks += 1
	if not v:
		failures += 1
		print("FAIL: ", message)
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	PlayerData.initialize_new_game()
	PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
	BankManager.deserialize({"purchased_slots": 200})
	call_deferred("run")
func run() -> void:
	var panel = load("res://scripts/ui/panels/CombatRoadmapPanel.gd").new()
	add_child(panel)
	check(Screens.ORDER.has(Screens.COMBAT_ROADMAP), "roadmap is registered")
	for kind in panel.TYPES:
		var records: Array = panel._records(kind)
		check(not records.is_empty(), kind + " has entries")
		for row in records:
			check(int(row.max_level) >= int(row.min_level), str(row.name) + " has ordered levels")
		var picks: Array = panel._suggestions(kind)
		check(not picks.is_empty(), kind + " has a suggestion")
		for row in picks:
			check(not row.done, str(row.name) + " is unfinished")
			if kind != "Regions":
				var expected: String = CombatManager.expedition_unlock_reason() if CombatManager.is_expedition(row.id) else ""
				if expected == "": expected = CombatManager.dungeon_lock_reason(row.id)
				check(row.reason == expected, str(row.name) + " uses combat gate")
	var first: Dictionary = panel._suggestions("Dungeons")[0]
	PlayerData.completion_log["dungeons"][first.id] = true
	var next: Array = panel._suggestions("Dungeons")
	check(next.is_empty() or str(next[0].id) != str(first.id), "cleared dungeon no longer recommended")
	var sections: int = panel._body.get_child_count()
	panel._filter.select(1)
	panel.refresh()
	check(panel._body.get_child_count() < sections, "path filter reduces displayed sections")
	panel.queue_free()
	await get_tree().process_frame
	print("COMBAT ROADMAP: ", checks, " checks; ", failures, " failures")
	get_tree().quit(1 if failures else 0)
