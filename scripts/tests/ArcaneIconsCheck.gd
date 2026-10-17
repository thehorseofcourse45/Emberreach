extends Node

func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	var checks := 0
	var failures := 0
	var unique: Dictionary = {}
	for sid in ["riftkeeping", "spellweaving"]:
		var skill_tex: Texture2D = AssetRegistry.skill_icon(sid)
		checks += 1
		if skill_tex.resource_path == "" or skill_tex.get_size() != Vector2(32,32):
			failures += 1
		for action in DataLoader.get_skill_actions(sid):
			var texture: Texture2D = AssetRegistry.icon(sid, str(action.id))
			checks += 1
			if texture.resource_path == "" or texture.get_size() != Vector2(32,32):
				failures += 1
				print("FAIL missing icon: ", action.id)
			var row := Widgets.activity_row(sid, action, false, func(): pass)
			var preview: TextureRect = row.get_child(0).get_child(0).get_child(0)
			checks += 1
			if preview.texture != texture:
				failures += 1
			row.free()
			var bytes := texture.get_image().get_data()
			var digest := bytes.hex_encode().sha256_text()
			checks += 1
			if unique.has(digest):
				failures += 1
			unique[digest] = true
			for item in action.output_items:
				var item_tex: Texture2D = AssetRegistry.item_icon(str(item))
				checks += 1
				if item_tex.resource_path == "" or item_tex.get_image().get_data() != bytes:
					failures += 1
					print("FAIL item icon: ", item)
	print("Arcane icons: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
