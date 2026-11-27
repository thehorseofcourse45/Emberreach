extends Node
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	var failures:=0
	var hashes:=[]
	for id in ["sapphire_ring_of_focus","emerald_ring_of_study","ruby_ring_of_fury","diamond_ring_of_warding","topaz_ring_of_the_hawk"]:
		var texture: Texture2D=AssetRegistry.item_icon(id)
		var h: int=hash(texture.get_image().get_data())
		if texture.get_size()!=Vector2(32,32) or texture.resource_path!="res://assets/icons/items/%s.png" % id or hashes.has(h):
			print("FAIL ring ",id); failures+=1
		hashes.append(h)
	print("RING ART: ",5-failures,"/5 checks")
	get_tree().quit(1 if failures else 0)
