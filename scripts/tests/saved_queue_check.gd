extends Node

func button(box: Node, text: String) -> Button:
	for node in box.find_children("*", "Button", true, false):
		if (node as Button).text == text: return node
	return null

func _ready() -> void:
	GameManager.start_new_game("standard")
	ActionQueueManager.clear()
	assert(ActionQueueManager.saved_plans.is_empty())
	assert(not ActionQueueManager.add_skill_step("mining", "copper_ore", "copper_ore", 10).is_empty())
	var queue_before: Dictionary = ActionQueueManager.serialize()
	var panel := preload("res://scripts/ui/panels/ActionQueuePanel.gd").new()
	add_child(panel)
	panel._saved_name.text = "Ore run"
	button(panel._saved_box, "Save current queue").pressed.emit()
	assert(ActionQueueManager.saved_plans.size() == 1)
	var disk: Dictionary = SaveManager._read_json(SaveManager.SAVE_PATH)
	assert(disk.action_queue.saved_plans[0].name == "Ore run")
	assert(ActionQueueManager.steps == queue_before.steps)
	var saved: Dictionary = ActionQueueManager.serialize()
	ActionQueueManager.deserialize({})
	assert(ActionQueueManager.saved_plans.is_empty())
	ActionQueueManager.deserialize(saved)
	assert(ActionQueueManager.saved_plans.size() == 1)
	button(panel._saved_box, "Review / edit").pressed.emit()
	assert(panel._saved_edit.name == "Ore run")
	var spins: Array[Node] = panel._saved_box.find_children("*", "SpinBox", true, false)
	assert(spins.size() == 1)
	(spins[0] as SpinBox).value = 22
	assert(int(panel._saved_edit.steps[0].target_quantity) == 22)
	assert(int(ActionQueueManager.saved_plans[0].steps[0].target_quantity) == 10)
	button(panel._saved_box, "Save edits").pressed.emit()
	assert(int(ActionQueueManager.saved_plans[0].steps[0].target_quantity) == 22)
	button(panel._saved_box, "Add reviewed steps").pressed.emit()
	assert(ActionQueueManager.steps.size() == 2 and int(ActionQueueManager.steps[1].target_quantity) == 22)
	assert(ActionQueueManager.steps[0].id != ActionQueueManager.steps[1].id)
	assert(not ActionQueueManager.enabled)
	button(panel._saved_box, "Review / edit").pressed.emit()
	panel._saved_edit.steps[0].action_id = "missing_action"
	panel._render_saved()
	assert(button(panel._saved_box, "Add reviewed steps").disabled)
	var before: int = ActionQueueManager.steps.size()
	panel._append_saved(panel._saved_edit.steps)
	assert(ActionQueueManager.steps.size() == before)
	var area_id: String = str(DataLoader.areas.keys()[0])
	var monsters: Array = DataLoader.areas[area_id].get("monsters", [])
	assert(not monsters.is_empty())
	var fight: Dictionary = ActionQueueManager.add_combat_step({"type":"area", "id":area_id, "monsters":monsters})
	assert(not fight.is_empty())
	var combat_draft: Array = [fight.duplicate(true)]
	panel._append_saved(combat_draft)
	assert(ActionQueueManager.steps.size() == before + 2 and ActionQueueManager.steps[-1].kind == "combat")
	assert(ActionQueueManager.steps[-1].id != fight.id and not ActionQueueManager.enabled)
	ActionQueueManager.deserialize({})
	assert(panel._saved_index == -1 and ActionQueueManager.saved_plans.is_empty())
	print("SAVED QUEUE CHECK PASS")
	get_tree().quit()
