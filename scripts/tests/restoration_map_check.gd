extends Node

func _ready() -> void:
	GameManager.start_new_game("standard")
	var panel := preload("res://scripts/ui/panels/QuestsPanel.gd").new()
	add_child(panel)
	panel._select_tab("restoration")
	var a := "hearthfall_restore_1"
	var b := "hearthfall_restore_2"
	assert(panel._restoration_stage_state(a) == "available")
	assert(panel._restoration_stage_state(b) == "locked")
	assert(Quests.accept(a))
	assert(panel._restoration_stage_state(a) == "in_progress")
	PlayerData.bump_stat("items_crafted", "bronze_bar", 10)
	PlayerData.bump_stat("monsters_killed", "golbin", 10)
	assert(panel._restoration_stage_state(a) == "ready")
	assert(Quests.claim(a))
	assert(panel._restoration_stage_state(a) == "completed")
	assert(panel._restoration_stage_state(b) == "available")
	panel._rebuild()
	var landscape = panel._list.find_child("RestorationLandscape", true, false)
	assert(landscape != null and landscape.states == ["completed", "available", "locked", "locked", "locked"])
	var selected: Array = []
	panel.context_changed.connect(func(ctx): selected.append(ctx))
	for i in range(1, 6):
		var stage: Control = panel._list.find_child("RestorationStage%d" % i, true, false)
		assert(stage != null)
		assert(stage.find_children("*", "TextureRect", true, false).size() >= 1)
		var labels: Array[Node] = stage.find_children("*", "Label", true, false)
		var reward_found := false
		for label in labels:
			if (label as Label).text.begins_with("Reward: "): reward_found = true
		assert(reward_found)
		if i == 2:
			for button in stage.find_children("*", "Button", true, false):
				if (button as Button).text == "Details": button.pressed.emit(); break
	assert(selected.size() == 1 and selected[0].goal.id == b)
	for i in range(panel.RESTORATION_CAMPAIGNS.size()):
		panel._restoration_index = i
		panel._rebuild()
		assert(panel._list.find_child("RestorationStage5", true, false) != null)
	print("RESTORATION MAP CHECK PASS")
	get_tree().quit()
