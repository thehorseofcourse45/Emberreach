extends Node

func _ready() -> void:
	GameManager.start_new_game("standard")
	var panel := preload("res://scripts/ui/panels/CollectionPanel.gd").new()
	add_child(panel)
	var contexts: Array = []
	panel.context_changed.connect(func(ctx): contexts.append(ctx))
	for tab in ["monsters", "dungeons"]:
		panel._tab = tab
		var names: Dictionary = {}
		for key in panel._keys_for(tab):
			var item_name: String = panel._display_name(str(key), true).to_lower()
			assert(not names.has(item_name), "Duplicate data name: " + item_name)
			names[item_name] = true
		panel._rebuild_list(0)
		var initial: int = panel._keys_for(tab).size()
		var category: String = "enemies" if tab == "monsters" else "expeditions"
		assert(_has_text(panel._list, "%d undiscovered %s" % [initial, category]))
		assert(not _has_text(panel._list, "Unknown"))
		if tab == "monsters": PlayerData.discover_monster("chicken")
		else: PlayerData.discover_dungeon("chicken_coop")
		panel._rebuild_list(0)
		assert(_has_text(panel._list, "%d undiscovered %s" % [initial - 1, category]))
		var id: String = "chicken" if tab == "monsters" else "chicken_coop"
		var name: String = panel._display_name(id, true)
		assert(_has_text(panel._list, name))
		var details := _button(panel._list, "Details")
		assert(details != null)
		details.pressed.emit()
		assert(contexts[-1].kind == "region" and contexts[-1].area_id != "")
		panel._search.text = name
		panel._rebuild_list(0)
		assert(_has_text(panel._list, name))
		assert(not _has_text(panel._list, "%d undiscovered %s" % [initial - 1, category]))
		panel._search.text = ""
	assert(PlayerData.completion_log.monsters.has("chicken"))
	assert(PlayerData.completion_log.dungeons.has("chicken_coop"))
	print("COLLECTION DUPLICATES CHECK PASS")
	get_tree().quit()

func _has_text(box: Node, text: String) -> bool:
	for label in box.find_children("*", "Label", true, false):
		if (label as Label).text == text: return true
	return false

func _button(box: Node, text: String) -> Button:
	for node in box.find_children("*", "Button", true, false):
		if (node as Button).text == text: return node
	return null
