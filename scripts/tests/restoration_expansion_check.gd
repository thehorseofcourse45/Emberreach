extends Node

func _ready() -> void:
	var prefixes := ["hearthfall", "barrows", "reedwrack", "ashwood", "dunecross", "ashenkeep", "sunderhold", "frostbound", "tidebreak", "greyharrow", "cinderforge", "rookwood"]
	for prefix in prefixes:
		for n in range(1, 6):
			var id: String = prefix + "_restore_" + str(n)
			if not Quests.has_quest(id):
				printerr("RESTORATION EXPANSION FAIL: missing ", id)
				get_tree().quit(1)
				return
	Quests.deserialize({"claimed": {"hearthfall_restore_1": true, "hearthfall_restore_2": true, "hearthfall_restore_3": true}})
	assert(Quests.is_claimed("hearthfall_restore_3"))
	assert(Quests.prerequisites_met("hearthfall_restore_4"))
	assert(not Quests.prerequisites_met("hearthfall_restore_5"))
	assert(not Quests.is_claimed("barrows_restore_1"))
	Quests.deserialize({})
	for prefix in prefixes:
		for n in range(2, 6): assert(not Quests.prerequisites_met(prefix + "_restore_" + str(n)))
		for n in range(1, 6):
			var id: String = prefix + "_restore_" + str(n)
			assert(Quests.prerequisites_met(id))
			for obj in Quests.get_quest(id).objectives:
				var amount: float = float(obj.required)
				match str(obj.kind):
					"kill_monster": PlayerData.bump_stat("monsters_killed", str(obj.monster_id), amount)
					"complete_dungeon": PlayerData.bump_stat("dungeons_cleared", str(obj.dungeon_id), amount)
					"craft_item": PlayerData.bump_stat("items_crafted", str(obj.item_id), amount)
					"caravan_delivery": PlayerData.bump_stat("caravan_deliveries", str(obj.item_id), amount)
					"do_actions": PlayerData.bump_stat("actions", str(obj.skill_id) + ":" + str(obj.action_id), amount)
					_: assert(false, "Unexpected objective kind")
			assert(Quests.claim(id))
			assert(not Quests.claim(id))
	var saved := Quests.serialize()
	Quests.deserialize({})
	Quests.deserialize(saved)
	for prefix in prefixes:
		for n in range(1, 6): assert(Quests.is_claimed(prefix + "_restore_" + str(n)))
	var panel := preload("res://scripts/ui/panels/QuestsPanel.gd").new()
	add_child(panel)
	panel._select_tab("restoration")
	assert(panel._restoration_choice.item_count == prefixes.size())
	var maps: Dictionary = {}
	for i in range(prefixes.size()):
		panel._restoration_choice.item_selected.emit(i)
		assert(panel._restoration_index == i and panel._list.get_child_count() == 9)
		assert(panel._list.find_child("RestorationStage5", true, false) != null)
		var campaign: Dictionary = panel.RESTORATION_CAMPAIGNS[i]
		assert(campaign.labels.size() == 5 and campaign.scenes.size() == 6)
		assert(ResourceLoader.exists("res://assets/caravans/maps/%s.png" % campaign.map))
		assert(not maps.has(campaign.map))
		maps[campaign.map] = true
	var sources := []
	for kind in ["gather", "craft", "drop", "shop", "passive", "dungeon", "quest"]:
		sources.append({"kind": kind})
	var diverse: Array = Goals._diversify(sources, 6)
	assert(diverse.size() == 6 and diverse[0].kind == "gather" and diverse[5].kind == "quest")
	var ore_task_found := false
	for source in Goals.sources_for_item("iron_ore"):
		if source.get("kind", "") == "quest": ore_task_found = true
	assert(ore_task_found)
	print("RESTORATION EXPANSION PASS: 12 campaigns, 60 stages")
	get_tree().quit()
