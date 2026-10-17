extends Node
func _ready() -> void:
	GameManager.cli_mode=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	SaveManager._write_in_progress=true
	var main=preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(.6).timeout
	GameManager.cli_mode=true
	GameManager.start_new_game("standard")
	GameManager.is_paused=true
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid),120)
	Quests.deserialize({"claimed":{"expedition_charter":true}})
	PlayerData.completion_log.dungeons["crown_of_embers"]=true
	for item in ["shark","potion_dr_3"]: BankManager.add_item_guaranteed(item,500)
	main.navigate({"screen":Screens.EXPEDITIONS,"area_id":"ironveil_bastion"})
	main.close_detail()
	await get_tree().create_timer(.8).timeout
	hide_windows(get_tree().root)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/strongholds_preview.png")
	print("Captured native Strongholds screen.")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()
func hide_windows(node: Node) -> void:
	for child in node.get_children():
		if child is Window: child.hide()
		hide_windows(child)

