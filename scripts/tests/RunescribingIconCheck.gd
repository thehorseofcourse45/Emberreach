extends Node

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	var checks := 0
	var failures := 0
	for action in DataLoader.get_skill_actions("alt_magic"):
		var expected: Texture2D
		if action.get("icon_activity",false):
			expected = AssetRegistry.icon("alt_magic",str(action.id))
		elif action.has("icon_item"):
			expected = AssetRegistry.item_icon(str(action.icon_item))
		else:
			expected = AssetRegistry.item_icon(str(action.output_items.keys()[0]))
		var card := Widgets.activity_row("alt_magic",action,false,func(): pass)
		var preview: TextureRect = card.get_child(0).get_child(0).get_child(0)
		checks += 1
		if expected == null or expected.resource_path == "" or preview.texture != expected or preview.texture.get_size() != Vector2(32,32):
			failures += 1
			print("FAIL: ",action.id)
		card.free()
	print("Runescribing icons: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures == 0 else 1)
