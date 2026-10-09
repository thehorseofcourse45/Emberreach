extends Node

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	var checks := 0
	var failures := 0
	for action in DataLoader.get_skill_actions("crafting"):
		if not action.get("icon_activity", false):
			continue
		var path := "res://assets/icons/crafting/%s.png" % action.id
		var card := Widgets.activity_row("crafting", action, false, func(): pass)
		var preview: TextureRect = card.get_child(0).get_child(0).get_child(0)
		checks += 1
		if preview.texture == null or preview.texture.resource_path != path or preview.texture.get_size() != Vector2(32, 32):
			failures += 1
			print("FAIL: ", action.id)
		card.free()
	checks += 1
	var ring: Texture2D = AssetRegistry.item_icon("topaz_ring")
	if ring == null or ring.get_size() != Vector2(32, 32):
		failures += 1
	print("Artifice icon checks: ", checks, " passed: ", checks - failures, " failures: ", failures)
	get_tree().quit(0 if failures == 0 else 1)
