extends Node

func shot(name: String) -> void:
	await get_tree().create_timer(.8).timeout
	hide_windows(get_tree().root)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/" + name + ".png")

func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	SaveManager._write_in_progress = true
	var main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(.6).timeout
	GameManager.cli_mode = true
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	for skill in ["riftkeeping", "spellweaving", "magic"]:
		PlayerData.set_level(skill, 120)
	for action in DataLoader.get_skill_actions("spellweaving"):
		PlayerData.stats.actions["spellweaving:" + str(action.id)] = 1
		for item in action.input_items:
			BankManager.add_item_guaranteed(str(item), 1000)
	EquipmentManager.slots[8] = "fire_staff"
	Quests.deserialize({"claimed": {"riftkeeping_foundation": true, "spellweaving_foundation": true}})
	PlayerData.settings.spellweaving_pattern = "rime_snare"
	main.navigate({"screen": Screens.SKILLS, "skill_id": "riftkeeping", "action_id": "candle_fracture"})
	await shot("riftkeeping_preview")
	main.navigate({"screen": Screens.SKILLS, "skill_id": "spellweaving", "action_id": "rime_snare"})
	await shot("spellweaving_preview")
	print("Captured two native arcane skill screens.")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()

func hide_windows(node: Node) -> void:
	for child in node.get_children():
		if child is Window: child.hide()
		hide_windows(child)
