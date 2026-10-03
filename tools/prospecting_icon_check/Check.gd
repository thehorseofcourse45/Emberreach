extends Node

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	var failures := 0
	var checks := 0
	var seen: Dictionary = {}
	for action in DataLoader.get_skill_actions("harvesting"):
		var row: Control = Widgets.activity_row("harvesting", action, false, func(): pass)
		var preview: TextureRect = row.get_child(0).get_child(0).get_child(0)
		var path: String = "res://assets/icons/items/%s.png" % action.icon_item
		checks += 3
		if preview.texture.resource_path != path: failures += 1
		if preview.texture.get_size() != Vector2(32, 32): failures += 1
		if seen.has(path): failures += 1
		seen[path] = true
		row.free()
	print("PROSPECTING ICONS: %d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures else 0)
