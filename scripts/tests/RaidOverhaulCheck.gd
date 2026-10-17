extends Node
## Headless raid progression checks. Run with isolated APPDATA / LOCALAPPDATA.
var checked: int = 0
var failed: int = 0

func verify(ok: bool, label: String) -> void:
	checked += 1
	if not ok:
		failed += 1
		print("FAIL: ", label)

func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("_test")

func _test() -> void:
	GameManager.start_new_game("standard")
	verify(RaidManager.start_raid("normal"), "start raid")
	verify(RaidManager.run_stage == "combat" and RaidManager.wave == 1, "wave starts in combat")
	verify(not RaidManager.current_encounter.is_empty(), "encounter description exists")
	var panel := preload("res://scripts/ui/panels/RaidPanel.gd").new()
	add_child(panel)
	verify(panel.get("_body") is VBoxContainer, "raid panel builds during combat")
	CombatManager.stop_combat("test")
	# Restore state for the wave completion callback, as the stop above deliberately retreated.
	RaidManager.active = true
	RaidManager.run_stage = "combat"
	RaidManager._on_combat_ended({"type": "raid", "reason": "complete"})
	verify(RaidManager.run_stage == "reward" and RaidManager.pending_choices.size() == 3, "reward options available")
	panel.call("_rebuild")
	verify((panel.get("_body") as VBoxContainer).get_child_count() > 0, "raid panel builds reward choices")
	verify(RaidManager.pending_choices.size() == 3 and RaidManager.pending_choices[0] != RaidManager.pending_choices[1], "reward picks are distinct")
	var serialized: Dictionary = RaidManager.serialize()
	RaidManager.deserialize(serialized)
	verify(RaidManager.pending_choices.size() == 3 and RaidManager.run_stage == "reward", "reward phase survives serialization")
	verify(RaidManager.choose(0), "reward can be claimed")
	verify(RaidManager.run_stage == "route" and RaidManager.pending_routes.size() == 3, "route choices appear")
	panel.call("_rebuild")
	verify((panel.get("_body") as VBoxContainer).get_child_count() > 0, "raid panel builds route choices")
	var route_save: Dictionary = RaidManager.serialize()
	RaidManager.deserialize(route_save)
	verify(RaidManager.run_stage == "route" and RaidManager.pending_routes.size() == 3, "route phase survives serialization")
	verify(RaidManager.choose_route(1), "swarm route starts")
	verify(RaidManager.wave == 2 and RaidManager.run_stage == "combat", "route advances wave")
	verify(str(RaidManager.current_encounter.get("id", "")) == "horde", "selected route changes encounter")
	verify(RaidManager.best_wave.get("normal", 0) == 1, "best wave recorded")
	RaidManager.end_raid()
	verify(not RaidManager.active and RaidManager.run_relics.is_empty(), "end clears run-only relics")
	verify(not RaidManager.buy("invalid_shop_item"), "unknown purchases rejected")
	panel.queue_free()
	print("Raid overhaul: ", checked, " checks, ", failed, " failures")
	get_tree().quit(0 if failed == 0 else 1)
