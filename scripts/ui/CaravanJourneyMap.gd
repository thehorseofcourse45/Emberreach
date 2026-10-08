extends AcceptDialog
const Journey = preload("res://scripts/core/CaravanJourney.gd")
var route_id: String = ""
var trip_seed: int = 0
var snapshot: Dictionary = {}
var canvas: RouteCanvas
var selected_stop: int = 1
var detail: Label
var status: Label
var choices: HFlowContainer
var journal: Label
var _signature: String = ""

func _ready() -> void:
	title = str(CaravaneeringManager.route(route_id).get("name", route_id)) + " · Journey map"
	get_ok_button().text = "Close map"
	close_requested.connect(queue_free)
	confirmed.connect(queue_free)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := UIStyle.vbox(UITokens.SP_3)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var help := UIStyle.label("Click a stop to inspect it · Drag to pan · Scroll to zoom · Travel continues while this map is closed", true, UITokens.FONT_SMALL)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	canvas = RouteCanvas.new()
	canvas.custom_minimum_size = Vector2(680, 540)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.route_id = route_id
	canvas.selected.connect(func(index): selected_stop = index; _signature = ""; _refresh())
	box.add_child(canvas)
	var centre := UIStyle.mini_button("Centre map")
	centre.pressed.connect(func(): canvas.pan = Vector2.ZERO; canvas.zoom = 1.0; canvas.queue_redraw())
	box.add_child(centre)
	status = UIStyle.label("", true, UITokens.FONT_SMALL)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	detail = UIStyle.label("", false, UITokens.FONT_SMALL)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	choices = HFlowContainer.new()
	choices.add_theme_constant_override("h_separation", UITokens.SP_3)
	box.add_child(choices)
	for approach in Journey.APPROACHES:
		var button := UIStyle.mini_button(str(approach).capitalize())
		button.pressed.connect(func():
			if CaravaneeringManager.set_approach(trip_seed, selected_stop, str(approach)): _signature = ""; _refresh())
		choices.add_child(button)
	journal = UIStyle.label("", true, UITokens.FONT_SMALL)
	journal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(journal)
	_refresh()

func _process(_delta: float) -> void:
	if canvas != null: _refresh()

func _refresh() -> void:
	var c: Dictionary = CaravaneeringManager.trip(trip_seed) if trip_seed > 0 else {}
	var active: bool = not c.is_empty() and not bool(c.get("idle", false))
	if active: snapshot = c.duplicate(true)
	elif trip_seed > 0:
		for history in CaravaneeringManager.history:
			if int(history.get("journey", {}).get("seed", 0)) == trip_seed:
				snapshot = {"route": route_id, "journey": history.journey, "total": history.total, "remaining": 0.0}
				break
	if snapshot.is_empty(): snapshot = {"journey": Journey.create(route_id, 0), "total": 1.0, "remaining": 1.0}
	var j: Dictionary = snapshot.journey
	canvas.journey = j
	canvas.progress = clampf(1.0 - float(snapshot.remaining) / maxf(1.0, float(snapshot.total)), 0.0, 1.0)
	canvas.selection = selected_stop
	canvas.queue_redraw()
	status.text = "Route preview · Every departure makes a new path. Five reward stops, then destination trade." if trip_seed == 0 else "Returns in %s · %d / 5 stops reached · Stop rewards %s GP · Cargo value lost %.0f%%" % [UIStyle.fmt_duration(float(snapshot.remaining)), int(j.next_stop) - 1, UIStyle.fmt(float(j.bonus_gp)), float(j.loss) * 100.0]
	if trip_seed > 0 and not active: status.text = "Journey completed · %d stops reached · Stop rewards %s GP · Cargo value lost %.0f%%" % [int(j.next_stop) - 1, UIStyle.fmt(float(j.bonus_gp)), float(j.loss) * 100.0]
	var signature: String = str(selected_stop) + str(j.next_stop) + str(j.points[selected_stop].approach) + str(active)
	if signature == _signature: return
	_signature = signature
	var point: Dictionary = j.points[selected_stop]
	var passed: bool = selected_stop < int(j.next_stop)
	var text: String = "%s · %s" % [str(point.name), "Reached" if passed else "Upcoming"]
	if selected_stop in [0, 6]:
		text += "\nDeparture loads your cargo; destination pays the trade revenue, XP and specialty goods."
	else:
		text += "\n" + str(Journey.EVENTS[int(point.event)])
		var reward: int = maxi(1, floori(float(CaravaneeringManager.route(route_id).get("xp", 0)) * 0.001))
		if str(point.approach) == "cautious": reward = maxi(1, reward / 2)
		elif str(point.approach) == "bold": reward *= 2
		if int(point.event) in [4, 5]: reward *= 2
		text += " · Reward up to %s GP" % UIStyle.fmt(float(reward))
		text += " · Approach: " + str(point.approach).capitalize()
		text += "\nCautious: fewer rewards, 60% less danger. Balanced: normal rewards and risk. Bold: double rewards, 50% more danger. Guards protect cargo; storms and broken bridges still carry risk."
		for entry in j.log:
			if int(entry.stop) == selected_stop: text += "\nOutcome: %s · +%s GP" % [str(entry.text), UIStyle.fmt(float(entry.gp))]
	detail.text = text
	for button in choices.get_children(): button.disabled = not active or passed or selected_stop in [0, 6]
	var lines: Array[String] = []
	for entry in j.log:
		lines.append("%s: %s (+%s GP)" % [str(j.points[int(entry.stop)].name), str(entry.text), UIStyle.fmt(float(entry.gp))])
	journal.text = "Travel journal\n" + ("No stops reached yet. Balanced orders are used offline unless you change them." if lines.is_empty() else "\n".join(lines))

class RouteCanvas extends Control:
	signal selected(index: int)
	var route_id: String
	var journey: Dictionary = {}
	var progress: float = 0.0
	var selection: int = 1
	var pan := Vector2.ZERO
	var zoom := 1.0
	var dragging := false
	var drag_start := Vector2.ZERO
	var moved := false
	var picture: Texture2D
	func _ready() -> void:
		clip_contents = true
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		var path: String = "res://assets/caravans/maps/%s.png" % route_id
		if ResourceLoader.exists(path): picture = load(path)
	func map_rect() -> Rect2:
		var fit: float = minf(size.x / 1536.0, size.y / 1024.0)
		var width: float = 1536.0 * fit * zoom
		var height: float = 1024.0 * fit * zoom
		return Rect2((size - Vector2(width, height)) * 0.5 + pan, Vector2(width, height))
	func point_position(i: int) -> Vector2:
		var point: Dictionary = journey.points[i]
		var rect: Rect2 = map_rect()
		return rect.position + Vector2(float(point.x), float(point.y)) * rect.size
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UITokens.BG_DEEP)
		if picture != null: draw_texture_rect(picture, map_rect(), false)
		if journey.is_empty(): return
		var font: Font = ThemeDB.fallback_font
		for i in range(6):
			var a: Vector2 = point_position(i)
			var b: Vector2 = point_position(i + 1)
			var direction: Vector2 = (b - a).normalized()
			var distance: float = a.distance_to(b)
			var tint: Color = Color(0.35, 0.95, 0.66) if progress >= float(i + 1) / 6.0 else Color(1.0, 0.84, 0.42)
			for step in range(0, ceili(distance), 12):
				var centre: Vector2 = a + direction * float(step)
				draw_circle(centre, 3.5, Color(0.04, 0.03, 0.05, 0.85))
				draw_circle(centre, 1.7, tint)
		for i in range(7):
			var pos: Vector2 = point_position(i)
			var passed: bool = progress >= float(i) / 6.0
			var hazard: bool = int(journey.points[i].event) in [1, 2, 3]
			var tint: Color = Color(0.3, 0.95, 0.6) if passed else Color(1.0, 0.45, 0.3) if hazard else Color(1.0, 0.82, 0.33)
			draw_circle(pos, 17.0 if selection == i else 14.0, Color(0.04, 0.025, 0.08, 0.95))
			draw_arc(pos, 14.0, 0, TAU, 32, tint, 2.5, true)
			draw_string(font, pos + Vector2(-5, 5), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, tint)
			var label: String = "Start" if i == 0 else "Destination" if i == 6 else str(journey.points[i].name)
			var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			var text_pos: Vector2 = pos + Vector2(-text_size.x / 2.0, 29)
			draw_rect(Rect2(text_pos + Vector2(-4, -13), text_size + Vector2(8, 5)), Color(0.03, 0.02, 0.06, 0.88))
			draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		var leg: int = mini(5, floori(progress * 6.0))
		var marker: Vector2 = point_position(leg).lerp(point_position(leg + 1), clampf(progress * 6.0 - float(leg), 0.0, 1.0))
		draw_circle(marker + Vector2(0, -22), 8, Color.WHITE)
		draw_circle(marker + Vector2(0, -22), 5, Color(0.35, 0.16, 0.75))
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					dragging = true
					drag_start = event.position
					moved = false
				else:
					dragging = false
					if not moved and not journey.is_empty():
						for i in range(7):
							if event.position.distance_to(point_position(i)) <= 22:
								selected.emit(i)
				accept_event()
			elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var old: float = zoom
				zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 1.0, 3.5)
				pan = (pan - event.position + size * 0.5) * (zoom / old) + event.position - size * 0.5
				queue_redraw()
				accept_event()
		elif event is InputEventMouseMotion and dragging:
			if event.position.distance_to(drag_start) > 4: moved = true
			if moved:
				pan += event.relative
				queue_redraw()
			accept_event()
