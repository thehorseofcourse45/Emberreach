extends Window
## Permanent upgrade map. GraphEdit owns pan/zoom; PrestigeManager owns all transactions.
var graph: GraphEdit
var _points: Label
var _cards: Dictionary = {}

func _ready() -> void:
	title = "Ascendancy upgrade tree"
	theme = UIStyle.build_theme()
	close_requested.connect(hide)
	var background := ColorRect.new()
	background.color = UITokens.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, UITokens.SP_5)
	add_child(margin)
	var layout := UIStyle.vbox(UITokens.SP_4)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	_points = UIStyle.title("", UITokens.FONT_HEAD)
	_points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_points)
	var reset := UIStyle.button("Reset view", "Restore the tree's starting view")
	reset.pressed.connect(reset_view)
	header.add_child(reset)
	var close := UIStyle.button("Close")
	close.pressed.connect(hide)
	header.add_child(close)
	layout.add_child(header)
	layout.add_child(UIStyle.label("Click and drag the background or a card to pan · Mouse wheel to zoom · Lines show required upgrades", true, UITokens.FONT_SMALL))
	graph = PannableGraph.new()
	focus_exited.connect(func(): graph._panning = false)
	visibility_changed.connect(func(): graph._panning = false)
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.minimap_size = Vector2(180, 140)
	graph.show_grid = false
	graph.show_grid_buttons = false
	graph.show_arrange_button = false
	graph.show_zoom_label = true
	graph.minimap_enabled = true
	graph.show_minimap_button = true
	graph.add_theme_stylebox_override("panel", UIStyle.surface_box("sunken"))
	layout.add_child(graph)
	var branches := OptionButton.new()
	branches.add_item("Jump to branch...")
	var branch_roots: Array[String] = []
	for id in DataLoader.ascendancy:
		if id == "_comment": continue
		var branch: String = str(DataLoader.ascendancy[id].get("branch", ""))
		if branch != "" and not branch_roots.any(func(root_id): return str(DataLoader.ascendancy[root_id].branch) == branch):
			branch_roots.append(str(id))
			branches.add_item(branch)
	branches.item_selected.connect(func(index):
		if index <= 0: return
		_focus_branch(str(DataLoader.ascendancy[branch_roots[index - 1]].branch)))
	header.add_child(branches)
	header.move_child(branches, 1)
	_build_tree()
	EventBus.state_refreshed.connect(refresh)
	refresh()
	reset_view()
	call_deferred("_compact_cards")

func _compact_cards() -> void:
	for ui in _cards.values():
		ui.card.reset_size()
	reset_view()

func open() -> void:
	popup_centered_clamped(Vector2i(1150, 800), 0.9)
	refresh()

func reset_view() -> void:
	_focus_branch("Wisdom")

func _focus_branch(branch: String) -> void:
	var bounds := Rect2()
	var found := false
	for id in _cards:
		if str(DataLoader.ascendancy[id].get("branch", "")) != branch: continue
		var card: GraphNode = _cards[id].card
		var rect := Rect2(card.position_offset, card.size)
		bounds = bounds.merge(rect) if found else rect
		found = true
	if not found: return
	graph.zoom = clampf(minf((graph.size.x - 80) / bounds.size.x,
		(graph.size.y - 110) / bounds.size.y), graph.zoom_min, 0.9)
	graph.scroll_offset = bounds.position * graph.zoom - Vector2(40, 65)

func _build_tree() -> void:
	# Prerequisite depth places parents to the left; insertion order keeps branches stable.
	var depths: Dictionary = {}
	var pending: Array = DataLoader.ascendancy.keys().filter(func(id): return id != "_comment")
	while not pending.is_empty():
		var progressed := false
		for id in pending.duplicate():
			var depth := 0
			var ready := true
			for req in DataLoader.ascendancy[id].get("requires", []):
				if not depths.has(req):
					ready = false
					break
				depth = maxi(depth, int(depths[req]) + 1)
			if ready:
				depths[id] = depth
				pending.erase(id)
				progressed = true
		if not progressed: break # ContentValidator reports malformed prerequisites.
	var rows: Dictionary = {}
	for id in depths:
		var depth: int = depths[id]
		var row: int = int(rows.get(depth, 0))
		rows[depth] = row + 1
		var data: Dictionary = DataLoader.ascendancy[id]
		var card := GraphNode.new()
		card.name = str(id)
		card.title = str(data.name)
		card.tooltip_text = str(data.get("branch", ""))
		card.draggable = false
		card.resizable = false
		card.custom_minimum_size = Vector2(270, 0)
		card.size = Vector2(270, 210)
		var position_data: Array = data.get("tree_position", [depth, row])
		card.position_offset = Vector2(float(position_data[0]) * 380, float(position_data[1]) * 350)
		var heading := UIStyle.surface_box("row")
		heading.set_content_margin_all(UITokens.SP_4)
		card.add_theme_stylebox_override("titlebar", heading)
		card.add_theme_color_override("title_color", UITokens.GOLD_BRIGHT)
		graph.add_child(card)
		var rank := UIStyle.label("", false, UITokens.FONT_SMALL)
		card.add_child(rank)
		card.set_slot(0, not data.get("requires", []).is_empty(), 0, UITokens.GOLD, true, 0, UITokens.GOLD)
		var description := UIStyle.label(str(data.description), true, UITokens.FONT_SMALL)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size.x = 240
		card.add_child(description)
		var effect := UIStyle.colored_label("Permanent bonus per rank", UITokens.TEAL, UITokens.FONT_SMALL)
		effect.tooltip_text = UIStyle.describe_modifier_table(data.modifiers)
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(effect)
		var status := UIStyle.label("", true, UITokens.FONT_MICRO)
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(status)
		var controls := HBoxContainer.new()
		var buy := UIStyle.button("Buy")
		buy.pressed.connect(_purchase.bind(str(id)))
		controls.add_child(buy)
		var refund := UIStyle.button("Refund rank")
		refund.pressed.connect(_refund.bind(str(id)))
		controls.add_child(refund)
		card.add_child(controls)
		_cards[id] = {"card": card, "rank": rank, "status": status, "buy": buy, "refund": refund}
	for id in depths:
		for req in DataLoader.ascendancy[id].get("requires", []):
			graph.connect_node(str(req), 0, str(id), 0)

func refresh() -> void:
	_points.text = "%d Ascendancy points available" % PrestigeManager.points()
	for id in _cards:
		var st: Dictionary = PrestigeManager.node_state(str(id))
		var ui: Dictionary = _cards[id]
		ui.rank.text = "Rank %d / %d · %d points per rank" % [st.rank, st.max_rank, st.cost]
		ui.buy.text = "Maxed" if st.maxed else ("Rank up" if st.rank > 0 else "Buy upgrade")
		ui.buy.disabled = not st.can_buy
		ui.buy.tooltip_text = str(st.blocker)
		ui.refund.disabled = st.rank <= 0
		var required: Array = []
		for req in DataLoader.ascendancy[id].get("requires", []):
			required.append(str(DataLoader.ascendancy[req].name))
		ui.status.text = "Maximum rank" if st.maxed else ("Ready to purchase" if st.can_buy else str(st.blocker))
		ui.card.tooltip_text = str(DataLoader.ascendancy[id].get("branch", "")) + "\n" + UIStyle.describe_modifier_table(DataLoader.ascendancy[id].modifiers) + " per rank\n"
		ui.card.tooltip_text += "Requires: " + ", ".join(required) if not required.is_empty() else "Starting upgrade · no prerequisites"
		var color: Color = UITokens.TEAL if st.rank > 0 else (UITokens.GOLD if st.can_buy else UITokens.BORDER_STRONG)
		var style := UIStyle.surface_box("raised" if st.rank > 0 else "row")
		style.border_color = color
		style.set_border_width_all(2)
		ui.card.add_theme_stylebox_override("panel", style)
		ui.card.set_slot_color_left(0, color)
		ui.card.set_slot_color_right(0, color)

func _purchase(id: String) -> void:
	var result: Dictionary = PrestigeManager.spend(id)
	if not result.ok: EventBus.notify(str(result.reason), "warn")
	refresh()

func _refund(id: String) -> void:
	var result: Dictionary = PrestigeManager.refund_node(id)
	if not result.ok: EventBus.notify(str(result.reason), "warn")
	refresh()

class PannableGraph extends GraphEdit:
	var _panning := false

	func _input(event: InputEvent) -> void:
		if not is_visible_in_tree(): return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed:
				if _panning:
					_panning = false
					get_viewport().set_input_as_handled()
				return
			var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			if not Rect2(Vector2.ZERO, size).has_point(local): return
			# Hit-test the event position so fast clicks do not depend on stale hover state.
			if _over_interactive(self, event.position): return
			_panning = true
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and _panning:
			scroll_offset -= event.relative
			get_viewport().set_input_as_handled()

	func _over_interactive(node: Node, position: Vector2) -> bool:
		for child in node.get_children(true):
			if child is Control and child.is_visible_in_tree():
				if child is BaseButton or child is Range or child.get_class() == "GraphEditMinimap":
					var local: Vector2 = child.get_global_transform_with_canvas().affine_inverse() * position
					if Rect2(Vector2.ZERO, child.size).has_point(local): return true
			if _over_interactive(child, position): return true
		return false
