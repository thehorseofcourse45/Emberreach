extends Node
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	var failures:=0
	for pair in [["masterwork_gyro","herald_bar"],["masterwork_codex","enchant_catalyst"],["march_sigil","herald_essence"],["tidal_sigil","dream_essence"]]:
		var texture: Texture2D=AssetRegistry.item_icon(pair[0])
		var original: Texture2D=AssetRegistry.item_icon(pair[1])
		if texture.get_size()!=Vector2(32,32) or texture.resource_path!="res://assets/icons/items/%s.png" % pair[0] or texture.get_image().get_data()==original.get_image().get_data():
			print("FAIL artifact ",pair[0]); failures+=1
	print("ARTIFACT ART: ",4-failures,"/4 checks")
	get_tree().quit(1 if failures else 0)
