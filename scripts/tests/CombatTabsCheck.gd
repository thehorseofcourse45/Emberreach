extends Node
var checks := 0
var failures := 0
func ok(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)
func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	SaveManager._write_in_progress = true
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	var panel=preload("res://scripts/ui/panels/CombatPanel.gd").new()
	add_child(panel)
	for place in panel._places: ok(place.type == "area", "Regions contains only regions")
	var area_count=DataLoader.areas.values().filter(func(a): return a.get("type","area") != "slayer_area").size()
	ok(panel._places.size()==area_count, "all ordinary regions remain reachable")
	panel._show_dungeons(true)
	ok(panel._prep_box.find_children("*", "Button", true, false).any(func(b): return b.text.begins_with("Dungeon challenges")),"Dungeons shows challenge controls immediately")
	var dungeon_count=0
	for id in DataLoader.dungeons:
		if not CombatManager.is_expedition(str(id)): dungeon_count+=1
	ok(panel._places.size()==dungeon_count, "all ordinary dungeons remain reachable")
	for place in panel._places:
		ok(place.type=="dungeon" and not CombatManager.is_expedition(str(place.id)), "Dungeons excludes regions and expeditions")
	panel.focus_route({"area_id":"cinderkin_forge"})
	ok(panel._dungeons_only and panel._selected_area=="cinderkin_forge", "direct dungeon route selects Dungeons")
	panel.focus_route({"area_id":"farmlands"})
	ok(not panel._dungeons_only and panel._selected_area=="farmlands", "direct region route selects Regions")
	ok(panel._places_box.get_parent().get_index()==1,"combat selector precedes preparation")
	var tabs=panel._places_box.get_child(0)
	tabs.get_child(1).pressed.emit()
	ok(panel._dungeons_only,"Dungeons button switches tab")
	panel._places_box.get_child(0).get_child(0).pressed.emit()
	ok(not panel._dungeons_only,"Regions button switches tab")
	panel.free()
	var expedition=preload("res://scripts/ui/panels/CombatPanel.gd").new()
	expedition.expeditions_only=true
	add_child(expedition)
	for place in expedition._places: ok(CombatManager.is_expedition(str(place.id)),"Expeditions preserved")
	expedition._show_strongholds(true)
	ok(expedition._places.size()==5,"Strongholds preserved")
	expedition.free()
	print("Combat tabs: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
