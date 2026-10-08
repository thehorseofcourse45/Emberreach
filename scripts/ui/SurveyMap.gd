extends VBoxContainer
## Spatial frontier view; managers retain ownership of travel and POI rewards.
const Survey = preload("res://scripts/ui/SurveyMinigame.gd")
signal navigated(route: Dictionary)
var canvas: HexCanvas
var sites_box: VBoxContainer
var heading: Label
var help: Label
var detail: Label
var action: Button

func _ready() -> void:
	var toolbar := UIStyle.hbox(UITokens.SP_4)
	help = UIStyle.label("%d hexes · Click to select · Drag to pan · Scroll to zoom" % DataLoader.cartography_hexes.size(), true, UITokens.FONT_SMALL)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(help)
	var reset := UIStyle.mini_button("Centre map")
	toolbar.add_child(reset)
	add_child(toolbar)
	canvas = HexCanvas.new()
	canvas.custom_minimum_size = Vector2(0, 460)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(canvas)
	reset.pressed.connect(func(): canvas.pan = Vector2.ZERO; canvas.zoom = 1.0; canvas.queue_redraw())
	canvas.selected.connect(func(_id): refresh())
	canvas.activated.connect(_act)
	var panel := UIStyle.panel()
	var box := UIStyle.vbox(UITokens.SP_4)
	panel.add_child(box)
	heading = UIStyle.title("", UITokens.FONT_SUBHEAD)
	box.add_child(heading)
	detail = UIStyle.label("", true, UITokens.FONT_SMALL)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	sites_box = UIStyle.vbox(UITokens.SP_2)
	box.add_child(sites_box)
	action = UIStyle.button("Travel")
	action.pressed.connect(_act)
	box.add_child(action)
	add_child(panel)
	EventBus.gp_changed.connect(func(_amount, _total): refresh())
	refresh()

func view_state() -> Dictionary:
	return {"selected": canvas.selected_id, "pan": canvas.pan, "zoom": canvas.zoom}

func restore_view(state: Dictionary) -> void:
	canvas.selected_id = str(state.get("selected", "hex_0_0"))
	canvas.pan = state.get("pan", Vector2.ZERO)
	canvas.zoom = float(state.get("zoom", 1.0))
	refresh()

func refresh() -> void:
	var id: String = canvas.selected_id
	var hex: Dictionary = CartographyManager.get_hex(id)
	var visited: bool = CartographyManager.is_discovered(id)
	var claimed: bool = CartographyManager.surveyed.has(id)
	var poi: Dictionary = hex.get("poi", {})
	var cost: float = CartographyManager.travel_cost(id)
	heading.text = "%s · (%s, %s)" % [str(poi.get("name", "Frontier")) if claimed else str(hex.get("terrain", "Frontier")).capitalize(), hex.get("q",0), hex.get("r",0)]
	action.disabled = false
	action.tooltip_text = ""
	if claimed:
		detail.text = "Surveyed · " + UIStyle.describe_modifier_table(poi.get("effect", {}))
		action.text = "Discovery claimed"
		action.disabled = true
	elif visited and not poi.is_empty():
		detail.text = "Visited · Find the hidden landmark to claim its reward and permanent bonus."
		action.text = "Survey this region"
		action.disabled = false
	elif visited:
		detail.text = "Explored terrain · No landmark here. Continue across the landscape to reach another discovery."
		action.text = "Terrain explored"
		action.disabled = true
	else:
		detail.text = "Unexplored · Travel reveals this region. Most hexes are open terrain; discoveries are scattered across the frontier."
		var block: String = CartographyManager.travel_block(id)
		action.text = "Travel · %s GP" % UIStyle.fmt(cost)
		action.disabled = block != "" or PlayerData.gp < cost
		action.tooltip_text = block if block != "" else ("Need %s GP" % UIStyle.fmt(cost) if action.disabled else "Reveal this region")
		if block != "":
			detail.text += " " + block + "."
	var terrain: String = str(hex.get("terrain", ""))
	var prog: Vector2i = CartographyManager.terrain_progress(terrain)
	var bonus: Dictionary = DataLoader.cartography_terrain.get(terrain, {}).get("modifiers", {})
	if prog.y > 0 and not bonus.is_empty():
		detail.text += "\n%s set: %d / %d landmarks claimed%s · %s" % [terrain.capitalize(), prog.x, prog.y, " ✓" if prog.x >= prog.y else "", UIStyle.describe_modifier_table(bonus)]
	help.text = "%d / %d charted · Click to select · Drag to pan · Scroll to zoom" % [CartographyManager.discovered.size(), DataLoader.cartography_hexes.size()]
	_rebuild_sites(id)
	canvas.queue_redraw()

## Combat areas, expeditions and dig sites placed on this region (their "hex" field), each with
## a button that opens it where it is played.
func _rebuild_sites(id: String) -> void:
	for c in sites_box.get_children():
		sites_box.remove_child(c)
		c.queue_free()
	var rows: Array = []
	for area_id in DataLoader.areas.keys():
		if str(DataLoader.areas[area_id].get("hex", "")) == id:
			rows.append([str(DataLoader.areas[area_id].get("name", area_id)), "Combat", {"screen": Screens.COMBAT, "area_id": str(area_id)}])
	for dungeon_id in DataLoader.dungeons.keys():
		if str(DataLoader.dungeons[dungeon_id].get("hex", "")) == id:
			var screen: String = Screens.EXPEDITIONS if CombatManager.is_expedition(str(dungeon_id)) else Screens.COMBAT
			rows.append([str(DataLoader.dungeons[dungeon_id].get("name", dungeon_id)), "Dungeon", {"screen": screen, "area_id": str(dungeon_id)}])
	for site_id in DataLoader.archaeology_sites.keys():
		if str(DataLoader.archaeology_sites[site_id].get("hex", "")) == id:
			rows.append([str(DataLoader.archaeology_sites[site_id].get("name", site_id)), "Dig site", {"screen": "skill", "skill_id": "archaeology", "action_id": str(site_id)}])
	for r in rows:
		var row := UIStyle.hbox(UITokens.SP_3)
		var l := UIStyle.label("%s · %s" % [r[0], r[1]], false, UITokens.FONT_SMALL)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var go := UIStyle.mini_button("Go")
		var route: Dictionary = r[2]
		go.tooltip_text = "Open %s" % r[0]
		go.pressed.connect(func(): navigated.emit(route))
		row.add_child(go)
		sites_box.add_child(row)

func _act() -> void:
	if action.disabled: return
	var id: String = canvas.selected_id
	if not CartographyManager.is_discovered(id):
		if CartographyManager.travel(id): refresh()
	else:
		var game := Survey.new()
		game.hex_id = id
		game.finished.connect(func(_found): refresh())
		get_tree().root.add_child(game)
		game.popup_centered()

class HexCanvas extends Control:
	signal selected(id: String)
	signal activated
	const RADIUS := 56.0
	var selected_id := "hex_0_0"
	var pan := Vector2.ZERO
	var zoom := 1.0
	var hovered := ""
	var dragging := false
	var dragged := false
	var press_position := Vector2.ZERO
	var textures: Dictionary = {}
	var landmarks: Dictionary = {}
	var centres: Dictionary = {}
	var bounds := Rect2()

	func _ready() -> void:
		clip_contents = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for id in DataLoader.cartography_hexes:
			var hex: Dictionary = DataLoader.cartography_hexes[id]
			var centre := Vector2(sqrt(3.0) * RADIUS * (float(hex.q) + float(hex.r) / 2.0), 1.5 * RADIUS * float(hex.r))
			centres[id] = centre
			var rect := Rect2(centre - Vector2.ONE * RADIUS, Vector2.ONE * RADIUS * 2.0)
			bounds = rect if centres.size() == 1 else bounds.merge(rect)
			var tpath: String = "res://assets/survey/terrain/%s.png" % hex.get("terrain", "plains")
			textures[id] = load(tpath) if ResourceLoader.exists(tpath) else null
			var lpath: String = "res://assets/survey/landmarks/%s.png" % hex.get("landmark", "relic")
			landmarks[id] = load(lpath) if ResourceLoader.exists(lpath) else null
		resized.connect(queue_redraw)
		focus_exited.connect(func(): dragging = false)
		mouse_exited.connect(func(): hovered = ""; queue_redraw())

	func scale_factor() -> float:
		return minf((size.x - 24.0) / bounds.size.x, (size.y - 24.0) / bounds.size.y) * zoom

	func centre_for(id: String) -> Vector2:
		return size / 2.0 + pan + (Vector2(centres[id]) - bounds.get_center()) * scale_factor()

	func polygon_for(id: String) -> PackedVector2Array:
		var polygon := PackedVector2Array()
		var centre := centre_for(id)
		for i in 6:
			var angle := deg_to_rad(60.0 * i - 30.0)
			polygon.append(centre + Vector2(cos(angle),sin(angle)) * RADIUS * scale_factor())
		return polygon

	func hex_at(point: Vector2) -> String:
		for id in centres:
			if Geometry2D.is_point_in_polygon(point, polygon_for(str(id))): return str(id)
		return ""

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),UITokens.BG_DEEP)
		var font: Font = ThemeDB.fallback_font
		for id in centres:
			var polygon := polygon_for(str(id))
			var centre := centre_for(str(id))
			var radius := RADIUS * scale_factor()
			var uv := PackedVector2Array()
			for point in polygon: uv.append((point - centre) / (radius * 2.0) + Vector2.ONE / 2.0)
			var visited: bool = CartographyManager.is_discovered(str(id))
			var claimed: bool = CartographyManager.surveyed.has(id)
			draw_polygon(polygon,PackedColorArray([Color.WHITE if visited else Color(0.38,0.38,0.46,1)]),uv,textures[id])
			if not visited: draw_colored_polygon(polygon,Color(UITokens.BG_DEEP,0.28))
			if claimed and landmarks[id] != null:
				var extent := radius * 0.82
				draw_texture_rect(landmarks[id],Rect2(centre-Vector2.ONE*extent/2.0,Vector2.ONE*extent),false)
			elif visited and not DataLoader.cartography_hexes[id].get("poi", {}).is_empty():
				if landmarks[id] != null:
					var dim := radius * 0.7
					draw_texture_rect(landmarks[id],Rect2(centre-Vector2.ONE*dim/2.0,Vector2.ONE*dim),false,Color(0.1,0.1,0.14,0.55))
				draw_circle(centre,minf(10.0,radius*0.3),UITokens.BG_DEEP)
				draw_string(font,centre+Vector2(-4,5),"?",HORIZONTAL_ALIGNMENT_LEFT,-1,clampi(int(radius*0.55),10,16),UITokens.AMBER)
			var edge: Color = UITokens.BORDER_GOLD if id == selected_id else UITokens.GREEN if claimed else UITokens.TEAL if visited else UITokens.BORDER_STRONG
			if id == hovered and id != selected_id: edge = UITokens.TEXT_STRONG
			polygon.append(polygon[0])
			draw_polyline(polygon,edge,3.0 if id == selected_id else 1.5,true)
			if radius > 30.0:
				var hex: Dictionary = DataLoader.cartography_hexes[id]
				var text := "%s, %s" % [hex.q,hex.r]
				var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
				draw_string(font,centre+Vector2(-width/2.0,radius*0.68),text,HORIZONTAL_ALIGNMENT_LEFT,-1,11,UITokens.TEXT_STRONG)
		# Active caravans run from the origin to their route's destination.
		var origin: String = CartographyManager.hex_at(Vector2i.ZERO)
		if centres.has(origin):
			for c in CaravaneeringManager.caravans:
				if bool(c.get("idle", false)):
					continue
				var dest: String = str(CaravaneeringManager.route(str(c.get("route", ""))).get("hex", ""))
				if centres.has(dest) and dest != origin:
					draw_dashed_line(centre_for(origin), centre_for(dest), UITokens.AMBER, 2.0, 8.0)
					draw_circle(centre_for(dest), 4.0, UITokens.AMBER)
		# The ship token sits on the last region travelled to.
		var here: String = CartographyManager.current_hex
		if centres.has(here):
			var tip := centre_for(here) + Vector2(0, -RADIUS * scale_factor() * 0.35)
			var s := clampf(RADIUS * scale_factor() * 0.18, 5.0, 12.0)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-s, 0), tip + Vector2(s, 0), tip + Vector2(s * 0.6, s * 0.6), tip + Vector2(-s * 0.6, s * 0.6)]), UITokens.GOLD_BRIGHT)
			draw_line(tip, tip + Vector2(0, -s * 1.4), UITokens.GOLD_BRIGHT, 2.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
				var previous := zoom
				zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.15),0.55,6.0)
				pan = event.position-size/2.0-(event.position-size/2.0-pan)*(zoom/previous)
				queue_redraw()
				accept_event()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					grab_focus()
					dragging = true
					dragged = false
					press_position = event.position
				else:
					if dragging and not dragged:
						var id := hex_at(event.position)
						if id != "":
							selected_id = id
							selected.emit(id)
							queue_redraw()
					dragging = false
				accept_event()
		elif event is InputEventMouseMotion:
			if dragging:
				if event.position.distance_to(press_position) > 5.0: dragged = true
				if dragged: pan += event.relative
				queue_redraw()
			else:
				hovered = hex_at(event.position)
				tooltip_text = "Click to select region" if hovered != "" else "Drag to pan"
				queue_redraw()
			accept_event()
		elif event is InputEventKey and event.pressed:
			var direction := Vector2i.ZERO
			if event.is_action_pressed("ui_left"): direction = Vector2i(-1,0)
			elif event.is_action_pressed("ui_right"): direction = Vector2i(1,0)
			elif event.is_action_pressed("ui_up"): direction = Vector2i(0,-1)
			elif event.is_action_pressed("ui_down"): direction = Vector2i(0,1)
			elif event.is_action_pressed("ui_accept"): activated.emit()
			if direction != Vector2i.ZERO:
				var hex: Dictionary = DataLoader.cartography_hexes[selected_id]
				var coordinate := Vector2i(int(hex.q),int(hex.r)) + direction
				for id in centres:
					var candidate: Dictionary = DataLoader.cartography_hexes[id]
					if Vector2i(int(candidate.q),int(candidate.r)) == coordinate:
						selected_id = str(id)
						selected.emit(selected_id)
						queue_redraw()
						break
			accept_event()
