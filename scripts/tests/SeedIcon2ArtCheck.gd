extends Node
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	var failures:=0
	var hashes:=[]
	for id in ["blood_ginger_seed","moon_lotus_seed","storm_lavender_seed","night_pepper_seed","astral_fennel_seed","dawn_orchid_seed"]:
		var texture: Texture2D=AssetRegistry.item_icon(id)
		var h: int=hash(texture.get_image().get_data())
		if texture.get_size()!=Vector2(32,32) or texture.resource_path!="res://assets/icons/items/%s.png" % id or hashes.has(h):
			print("FAIL seed ",id); failures+=1
		hashes.append(h)
	print("SEED ART: ",6-failures,"/6 checks")
	get_tree().quit(1 if failures else 0)
