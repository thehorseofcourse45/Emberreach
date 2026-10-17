extends Node

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	var checks := 0
	var failures := 0
	for action in DataLoader.get_skill_actions("enchanting"):
		var path := "res://assets/icons/enchanting/%s.png" % action.id
		var card := Widgets.activity_row("enchanting", action, false, func(): pass)
		var preview: TextureRect = card.get_child(0).get_child(0).get_child(0)
		checks += 1
		if preview.texture == null or preview.texture.resource_path != path or preview.texture.get_size() != Vector2(32,32):
			failures += 1
			print("FAIL activity: ", action.id)
		card.free()
	for enchant in DataLoader.new_skill_systems.get("enchants", []):
		var texture: Texture2D = AssetRegistry.icon("enchants",str(enchant.id))
		checks += 1
		if texture == null or texture.resource_path != "res://assets/icons/enchants/%s.png" % enchant.id or texture.get_size() != Vector2(32,32):
			failures += 1
			print("FAIL enchant: ", enchant.id)
	print("Attunement icons: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
