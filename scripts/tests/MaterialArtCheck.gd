extends Node
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	var failures:=0
	for pair in [["worldheart_ore","herald_ore"],["masterwork_ingot","herald_bar"],["ash_depth_shard","summoning_shard_gold"],["tide_depth_shard","summoning_shard_gold"],["star_depth_shard","summoning_shard_gold"]]:
		var texture: Texture2D=AssetRegistry.item_icon(pair[0])
		var original: Texture2D=AssetRegistry.item_icon(pair[1])
		if texture.get_size()!=Vector2(32,32) or texture.resource_path!="res://assets/icons/items/%s.png" % pair[0] or texture.get_image().get_data()==original.get_image().get_data():
			print("FAIL unique material ",pair[0]); failures+=1
	print("MATERIAL ART: ",5-failures,"/5 checks")
	get_tree().quit(1 if failures else 0)
