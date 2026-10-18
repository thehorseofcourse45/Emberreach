extends Node

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	SaveManager._write_in_progress = true
	call_deferred("run")

func run() -> void:
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	BankManager.deserialize({"purchased_slots":1000})
	PlayerData.add_gp(10000000)
	var specs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/SurveyExpansion.json"))
	check(DataLoader.cartography_hexes.size()==475,"475 total world hexes")
	var coordinates := {}
	for id in DataLoader.cartography_hexes:
		coordinates[CartographyManager.coord_of(id)] = id
	check(coordinates.size()==475,"all world coordinates are unique")
	check((specs.added as Array).all(func(id):return DataLoader.cartography_hexes.has(id)),"250 added hexes resolve")
	if DataLoader.cartography_hexes.size()!=475:
		finish()
		return
	var origin: String = CartographyManager.hex_at(Vector2i.ZERO)
	CartographyManager.deserialize({"discovered":{origin:true},"surveyed":{},"ships_owned":["river_skiff"],"ship":"river_skiff"})
	var reached := {origin:true}
	var pending: Array = [origin]
	var order: Array = []
	while not pending.is_empty():
		var id: String = pending.pop_front()
		for offset in CartographyManager.NEIGHBOURS:
			var neighbour: String = CartographyManager.hex_at(CartographyManager.coord_of(id)+offset)
			if neighbour!="" and not reached.has(neighbour):
				reached[neighbour]=true
				pending.append(neighbour)
				order.append(neighbour)
	check(reached.size()==475,"entire expanded map connected to home")
	CartographyManager.ship="frontier_galleon"
	CartographyManager.ships_owned.append("frontier_galleon")
	var travelled := true
	for id in order:
		travelled = CartographyManager.travel(id) and travelled
	check(travelled and CartographyManager.discovered.size()==475,"every hex reachable through real travel")
	for terrain in specs.terrains:
		var rule: Dictionary = DataLoader.cartography_terrain.get(terrain,{})
		check(not rule.is_empty() and float(rule.get("cost_mult",0))>0 and int(rule.get("reveals",0))>0,str(terrain)+" has travel and survey rules")
		check(CartographyManager.terrain_progress(terrain)==Vector2i(0,3),str(terrain)+" has three unclaimed landmarks")
		if not "--without-art" in OS.get_cmdline_user_args():
			var texture: Texture2D = load("res://assets/survey/terrain/%s.png" % terrain)
			check(texture!=null and texture.get_size()==Vector2(256,256),str(terrain)+" authored terrain loads")
	for id in specs.landmarks:
		var reward: Dictionary = CartographyManager.get_hex(id).poi.reward
		var before_gp: float = PlayerData.gp
		check(not CartographyManager.survey(id).is_empty() and PlayerData.gp==before_gp+float(reward.gp),str(id)+" survey grants reward")
		var paid_gp: float = PlayerData.gp
		check(CartographyManager.survey(id).is_empty() and PlayerData.gp==paid_gp,str(id)+" reward cannot repeat")
	for terrain in specs.terrains:
		check(CartographyManager.terrain_progress(terrain)==Vector2i(3,3),str(terrain)+" region set completes")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(CartographyManager.serialize()))
	CartographyManager.deserialize(saved)
	check(CartographyManager.discovered.size()==475 and CartographyManager.surveyed.size()==18,"expanded discoveries survive save round trip")
	if not "--without-art" in OS.get_cmdline_user_args():
		var map = preload("res://scripts/ui/SurveyMap.gd").new()
		add_child(map)
		map.canvas.size=Vector2(1000,460)
		map.canvas.zoom=6.0
		var far: String = specs.added.back()
		map.canvas.selected_id=far
		map.canvas.pan-=map.canvas.centre_for(far)-map.canvas.size/2.0
		map.refresh()
		check(map.canvas.centres.size()==475,"map canvas includes every expanded hex")
		check(map.canvas.hex_at(map.canvas.centre_for(far))==far,"distant hex remains selectable after panning and zooming")
		check(map.canvas.textures.values().all(func(t):return t!=null),"every world hex has terrain artwork")
		map.free()
	finish()

func finish() -> void:
	print("Survey expansion: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
