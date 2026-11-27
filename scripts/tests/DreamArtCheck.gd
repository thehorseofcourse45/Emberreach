extends Node
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	var failures := 0
	for id in ["astral_orchard", "tide_of_names", "unwritten_horizon"]:
		var texture: Texture2D = AssetRegistry.icon("dream_realm", id)
		if texture.resource_path != "res://assets/icons/dream_realm/%s.png" % id or texture.get_size() != Vector2(64,64):
			print("FAIL region icon ", id)
			failures += 1
	for id in ["siegebound_platelegs", "orchard_memory_charm"]:
		var picture := UIStyle.icon_texture("items", id)
		if picture.texture != AssetRegistry.item_icon(id):
			print("FAIL item alias ", id)
			failures += 1
		picture.free()
	for id in ["orchard_memory_charm", "nameless_tide_band", "horizon_weavers_mantle"]:
		var texture: Texture2D = AssetRegistry.item_icon(id)
		if texture.resource_path != "res://assets/icons/items/%s.png" % id or texture.get_size() != Vector2(64,64):
			print("FAIL relic icon ", id)
			failures += 1
	print("DREAM ART: ", 8 - failures, "/8 checks")
	get_tree().quit(1 if failures else 0)
