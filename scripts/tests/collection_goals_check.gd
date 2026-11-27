extends Node

func button(box: Node, text: String) -> Button:
	for node in box.find_children("*", "Button", true, false):
		if (node as Button).text == text: return node
	return null

func _ready() -> void:
	GameManager.start_new_game("standard")
	Goals.clear()
	var id := "bronze_scimitar"
	assert(not PlayerData.completion_log.items.has(id))
	var panel := preload("res://scripts/ui/panels/CollectionPanel.gd").new()
	add_child(panel)
	panel._tab = "missing"
	panel._search.text = "bronze_scimitar"
	panel._rebuild_list(0)
	assert(button(panel._list, "Track discovery") != null)
	button(panel._list, "Track discovery").pressed.emit()
	assert(Goals.is_pinned("collection_item", id))
	assert(not Goals.is_pinned("item", id))
	assert(button(panel._list, "Untrack discovery") != null)
	var result: Dictionary = Goals.resolve({"kind":"collection_item", "id":id})
	assert(result.ok and not result.complete and not result.sources.is_empty())
	var contexts: Array = []
	panel.context_changed.connect(func(ctx): contexts.append(ctx))
	button(panel._list, "Find sources").pressed.emit()
	assert(contexts.size() == 1 and contexts[0].goal.id == id)
	var detail := preload("res://scripts/ui/DetailPanel.gd").new()
	add_child(detail)
	detail.show_goal(contexts[0].goal)
	var routes: Array = []
	detail.navigated.connect(func(route): routes.append(route))
	var go := button(detail, "Go to this")
	assert(go != null)
	go.pressed.emit()
	assert(routes.size() == 1 and routes[0].has("screen"))
	var snapshot: Dictionary = Goals.serialize().duplicate(true)
	assert(SaveManager.save_game())
	var disk: Dictionary = SaveManager._read_json(SaveManager.SAVE_PATH)
	assert(disk.goals.pinned.any(func(g): return g.kind == "collection_item" and g.id == id))
	Goals.clear()
	Goals.deserialize(snapshot)
	assert(Goals.is_pinned("collection_item", id))
	BankManager.add_item_guaranteed(id, 1)
	assert(BankManager.remove_item(id, 1))
	assert(Goals.resolve({"kind":"collection_item", "id":id}).complete)
	assert(not Goals.resolve({"kind":"item", "id":id}).complete)
	assert(Goals.is_pinned("collection_item", id))
	assert(button(panel._list, "Track discovery") == null)
	var old_stack := "iron_ore"
	BankManager.items[old_stack] = 1
	PlayerData.completion_log.items.erase(old_stack)
	assert(not Goals.resolve({"kind":"collection_item", "id":old_stack}).complete)
	BankManager.add_item_guaranteed(old_stack, 1)
	assert(Goals.resolve({"kind":"collection_item", "id":old_stack}).complete)
	assert(Goals.unpin("collection_item", id))
	panel._tab = "pursuits"
	panel._search.text = "gemkeeper"
	panel._rebuild_list(0)
	var pursuit_id: String = str(Quests.get_quest("collection_gemkeeper").objectives[0].item_ids[0])
	assert(button(panel._list, "Track") != null)
	button(panel._list, "Track").pressed.emit()
	assert(Goals.is_pinned("collection_item", pursuit_id))
	button(panel._list, "Sources").pressed.emit()
	assert(contexts[-1].goal.id == pursuit_id)
	Goals.unpin("collection_item", pursuit_id)
	var drop_id := ""
	for monster in DataLoader.monsters.values():
		for drop in monster.get("loot_table", []):
			var candidate: String = str(drop.get("item_id", ""))
			if candidate == "" or PlayerData.completion_log.items.has(candidate): continue
			for source in Goals.sources_for_item(candidate):
				if str(source.get("kind", "")) == "drop" and not (source.get("route", {}) as Dictionary).is_empty():
					drop_id = candidate; break
			if drop_id != "": break
		if drop_id != "": break
	assert(drop_id != "")
	var drop_goal: Dictionary = Goals.resolve({"kind":"collection_item", "id":drop_id})
	assert(drop_goal.sources.any(func(s): return s.get("kind", "") == "drop" and not (s.get("route", {}) as Dictionary).is_empty()))
	print("COLLECTION GOALS CHECK PASS")
	get_tree().quit()
