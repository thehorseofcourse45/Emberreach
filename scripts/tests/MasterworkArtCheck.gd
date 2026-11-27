extends Node
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	var failures:=0
	for pair in [["aurora_gauntlets","caldera_gauntlets"],["sunforged_weapon","herald_godsword"],["sunforged_aegis","throneguard_cuirass"],["nightweaver_weapon","echobound_bow"],["starbound_weapon","dawn_wand"],["starbound_vestments","archmage_robe"],["nightweaver_mantle","blighted_cloak"]]:
		var texture: Texture2D=AssetRegistry.item_icon(pair[0])
		var original: Texture2D=AssetRegistry.item_icon(pair[1])
		if texture.get_size()!=Vector2(64,64) or texture.resource_path!="res://assets/icons/items/%s.png" % pair[0] or texture.get_image().get_data()==original.get_image().get_data():
			print("FAIL unique item ",pair[0]); failures+=1
	print("MASTERWORK ART: ",7-failures,"/7 checks")
	get_tree().quit(1 if failures else 0)
