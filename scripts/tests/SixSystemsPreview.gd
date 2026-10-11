extends Node
func find_script(root: Node, suffix: String) -> Node:
	var script = root.get_script()
	if script != null and str(script.resource_path).ends_with(suffix): return root
	for child in root.get_children():
		var found := find_script(child,suffix)
		if found!=null: return found
	return null
func scroll(root: Node, amount: int) -> void:
	for child in root.get_children():
		if child is ScrollContainer: child.scroll_vertical=amount
		scroll(child,amount)
func shot(name: String) -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/"+name+".png")
func _ready() -> void:
	GameManager.cli_mode=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	SaveManager._write_in_progress=true
	GameManager.start_new_game("standard")
	GameManager.is_paused=true
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid),120)
	Quests.deserialize({"claimed":{"expedition_charter":true}})
	for id in ["dream_essence","herald_bar"]: BankManager.add_item_guaranteed(id,10000)
	PlayerData.stats.dream_seconds={"cathedral":86400,"astral":50000,"crown":0}
	var main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	GameManager.cli_mode=true
	await get_tree().create_timer(0.6).timeout
	main.navigate({"screen":Screens.COLLECTION})
	var panel := find_script(main,"CollectionPanel.gd")
	panel.set("_tab","pursuits")
	panel.call("_rebuild")
	await shot("pursuits_preview")
	main.navigate({"screen":Screens.SKILLS,"skill_id":"dreamwalking"})
	await get_tree().create_timer(0.6).timeout
	scroll(main.get("_workspace"),550)
	await shot("dream_bosses_preview")
	main.navigate({"screen":Screens.EXPEDITIONS,"area_id":"endless_ashes"})
	CombatManager.start_combat({"type":"dungeon","id":"endless_ashes","monsters":DataLoader.get_dungeon("endless_ashes").monsters})
	await shot("endless_preview")
	CombatManager.stop_combat()
	main.navigate({"screen":Screens.SKILLS,"skill_id":"caravaneering"})
	await get_tree().create_timer(0.6).timeout
	var systems := find_script(main,"NewSkillSystems.gd")
	systems.set("_cv_route","glassstorm_crossing")
	main.navigate({"screen":Screens.SKILLS,"skill_id":"caravaneering"})
	await shot("dangerous_caravan_preview")
	print("Four native UI previews captured.")
	get_tree().quit()
