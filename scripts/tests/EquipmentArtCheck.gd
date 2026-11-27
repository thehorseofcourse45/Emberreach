extends Node
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	var failures := 0
	for id in ["siegebound_platelegs", "dawnbloom_siege_bow", "attuned_dawn_wand", "siege_sigil"]:
		var texture: Texture2D = AssetRegistry.item_icon(id)
		if texture.resource_path != "res://assets/icons/items/%s.png" % id or texture.get_size() != Vector2(64,64):
			print("FAIL equipment icon ", id)
			failures += 1
	print("EQUIPMENT ART: ",4-failures,"/4 checks")
	get_tree().quit(1 if failures else 0)
