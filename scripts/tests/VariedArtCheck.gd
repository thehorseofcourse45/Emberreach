extends Node
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	var failures:=0
	var hashes:=[]
	for id in ["legendary_crownfin","nightveil_silk","ranch_plume","ranch_manure","enchant_catalyst"]:
		var texture: Texture2D=AssetRegistry.item_icon(id)
		var h: int=hash(texture.get_image().get_data())
		if texture.get_size()!=Vector2(32,32) or texture.resource_path!="res://assets/icons/items/%s.png" % id or hashes.has(h):
			print("FAIL varied ",id); failures+=1
		hashes.append(h)
	print("VARIED ART: ",5-failures,"/5 checks")
	get_tree().quit(1 if failures else 0)
