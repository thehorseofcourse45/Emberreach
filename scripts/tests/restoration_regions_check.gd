extends Node

func _ready() -> void:
	for prefix in ["barrows_restore_", "reedwrack_restore_"]:
		for n in range(1, 4):
			if not Quests.has_quest(prefix + str(n)):
				printerr("RESTORATION REGIONS FAIL: missing ", prefix, n)
				get_tree().quit(1)
				return
	for prefix in ["barrows_restore_", "reedwrack_restore_"]:
		assert(not Quests.prerequisites_met(prefix + "2"))
	PlayerData.bump_stat("items_crafted", "iron_bar", 10)
	PlayerData.bump_stat("monsters_killed", "skeleton", 15)
	PlayerData.bump_stat("actions", "woodcutting:oak_tree", 30)
	PlayerData.bump_stat("monsters_killed", "spider", 15)
	PlayerData.bump_stat("caravan_deliveries", "oak_log", 20)
	PlayerData.bump_stat("caravan_deliveries", "trout", 20)
	PlayerData.bump_stat("dungeons_cleared", "undead_graveyard", 1)
	PlayerData.bump_stat("dungeons_cleared", "spider_forest", 1)
	for prefix in ["barrows_restore_", "reedwrack_restore_"]:
		for n in range(1, 4):
			var id: String = prefix + str(n)
			assert(Quests.claim(id))
			assert(not Quests.claim(id))
	var saved := Quests.serialize()
	Quests.deserialize({})
	Quests.deserialize(saved)
	for prefix in ["barrows_restore_", "reedwrack_restore_"]:
		for n in range(1, 4): assert(Quests.is_claimed(prefix + str(n)))
	var panel := preload("res://scripts/ui/panels/QuestsPanel.gd").new()
	add_child(panel)
	panel._select_tab("restoration")
	assert(panel._restoration_choice.item_count == 12)
	for i in range(3):
		panel._restoration_choice.item_selected.emit(i)
		assert(panel._restoration_index == i)
		assert(panel._restoration_choice.selected == i)
		assert(panel._list.get_child_count() == 9)
		assert(panel._list.find_child("RestorationStage5", true, false) != null)
	print("RESTORATION REGIONS PASS")
	get_tree().quit()
