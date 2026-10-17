extends Node
var checks := 0
var failures := 0
var hashes: Dictionary = {}
func ok(value: bool, name: String) -> void:
	checks+=1
	if not value:
		failures+=1
		print("FAIL: ",name)
func check_icon(texture: Texture2D, id: String, expected_size: int = 32) -> void:
	ok(texture.resource_path.ends_with(id+".png"), "real sprite: "+id)
	ok(texture.get_size()==Vector2(expected_size, expected_size), "%dx%d: %s" % [expected_size, expected_size, id])
	var im: Image=texture.get_image()
	ok(im.get_pixel(0,0).a==0 and im.get_pixel(expected_size-1,expected_size-1).a==0, "transparent padding: "+id)
	var hash: String=im.get_data().hex_encode().sha256_text()
	ok(not hashes.has(hash), "unique artwork: "+id)
	hashes[hash]=true
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	for id in DataLoader.dungeons:
		var d: Dictionary=DataLoader.get_dungeon(str(id))
		if not bool(d.get("stronghold",false)): continue
		check_icon(AssetRegistry.icon("dungeons",str(id)),str(id))
		for mid in d.monsters: check_icon(AssetRegistry.monster_sprite(str(mid)),str(mid),96)
		for gear in d.rewards_first_clear.items: check_icon(AssetRegistry.item_icon(str(gear)),str(gear))
	var panel=preload("res://scripts/ui/panels/CombatPanel.gd").new()
	panel.expeditions_only=true
	add_child(panel)
	panel.call("_show_strongholds",true)
	var picker: ItemList=panel.get("_place_list")
	var places: Array=panel.get("_places")
	for i in range(places.size()):
		ok(picker.get_item_icon(i)==AssetRegistry.icon("dungeons",str(places[i].id)),"selector displays stronghold art")
	ok(panel.get("_places_box").get_parent().get_index()==1,"stronghold selector is visible before preparation")
	panel.free()
	print("Stronghold icons: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
