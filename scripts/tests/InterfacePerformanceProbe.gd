extends Node
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	var stocked := {}
	var count := 0
	for id in DataLoader.items:
		if DataLoader.get_item(str(id)).get("item_type", "") != "":
			stocked[id] = 10
			count += 1
			if count >= 500: break
	BankManager.deserialize({"purchased_slots":1000, "items":stocked})
	call_deferred("run")
func measure(label: String, action: Callable, repeats := 3) -> void:
	var samples: Array[float] = []
	for i in range(repeats):
		await get_tree().process_frame
		var start := Time.get_ticks_usec()
		action.call()
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	print("TIMING|", label, "|median_ms=", snappedf(samples[int(samples.size()/2)],0.01), "|samples=", samples)
func run() -> void:
	var bank = load("res://scripts/ui/panels/BankPanel.gd").new()
	var start := Time.get_ticks_usec()
	add_child(bank)
	print("TIMING|storage_open|ms=", float(Time.get_ticks_usec()-start)/1000.0)
	var rows = bank.get("_list")
	var details: Button
	for button in rows.find_children("*", "Button", true, false):
		if button.text == "Details": details = button; break
	await measure("storage_details_500", func():
		var button: Button
		for b in rows.find_children("*", "Button", true, false):
			if b.text == "Details": button = b; break
		if button: button.pressed.emit())
	bank.free()
	await get_tree().process_frame
	var collection = load("res://scripts/ui/panels/CollectionPanel.gd").new()
	start = Time.get_ticks_usec()
	add_child(collection)
	print("TIMING|collection_open|ms=", float(Time.get_ticks_usec()-start)/1000.0)
	collection.set("_tab", "missing")
	await measure("collection_missing", func(): collection.call("_rebuild_list",0))
	collection.free()
	await get_tree().process_frame
	var wiki = load("res://scripts/ui/panels/EncyclopediaPanel.gd").new()
	start = Time.get_ticks_usec()
	add_child(wiki)
	print("TIMING|encyclopedia_open|ms=", float(Time.get_ticks_usec()-start)/1000.0)
	wiki.call("_set_mode", "reference")
	wiki.get("_category").select(1)
	await measure("encyclopedia_activities", func(): wiki.call("_rebuild"))
	wiki.get("_category").select(2)
	await measure("encyclopedia_items", func(): wiki.call("_rebuild"))
	wiki.free()
	await get_tree().process_frame
	var combat = load("res://scripts/ui/panels/CombatPanel.gd").new()
	start = Time.get_ticks_usec()
	add_child(combat)
	print("TIMING|combat_open|ms=", float(Time.get_ticks_usec()-start)/1000.0)
	combat.call("_show_dungeons",true)
	var index := 0
	await measure("combat_dungeon_select", func():
		var list: ItemList = combat.get("_place_list")
		if list.item_count > 1:
			index = 1 - index
			list.item_selected.emit(index))
	combat.free()
	await get_tree().process_frame
	print("INTERFACE PERFORMANCE PROBE DONE")
	get_tree().quit()
