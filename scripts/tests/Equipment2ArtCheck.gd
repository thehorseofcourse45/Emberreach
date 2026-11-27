extends Node
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	var failures:=0
	for pair in [["embercrown_blade","herald_godsword"],["tempest_cloak","blighted_cloak"],["astral_pendant","heralds_sigil"]]:
		var texture: Texture2D=AssetRegistry.item_icon(pair[0])
		var original: Texture2D=AssetRegistry.item_icon(pair[1])
		if texture.get_size()!=Vector2(32,32) or texture.resource_path!="res://assets/icons/items/%s.png" % pair[0] or texture.get_image().get_data()==original.get_image().get_data():
			print("FAIL unique item ",pair[0]); failures+=1
	print("EQUIPMENT 2 ART: ",3-failures,"/3 checks")
	get_tree().quit(1 if failures else 0)
