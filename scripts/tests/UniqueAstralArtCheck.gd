extends Node
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	var failures:=0
	for pair in [["observatory_blade","astral_vanguard_blade"],["nebula_bow","cometfall_longbow"],["aurora_staff","eclipse_oracle_staff"],["voidstar_aegis","starward_aegis"],["nebula_cuirass","thornstar_cuirass"],["observatory_helm","last_moon_relic"],["eternity_greatblade","eternal_dawn_blade"],["eternity_crown_helm","eternal_dawn_relic"]]:
		var texture: Texture2D=AssetRegistry.item_icon(pair[0])
		var original: Texture2D=AssetRegistry.item_icon(pair[1])
		if texture.get_size()!=Vector2(64,64) or texture.resource_path!="res://assets/icons/items/%s.png" % pair[0] or texture.get_image().get_data()==original.get_image().get_data():
			print("FAIL unique astral item ",pair[0]); failures+=1
	print("UNIQUE ASTRAL ART: ",8-failures,"/8 checks")
	get_tree().quit(1 if failures else 0)
