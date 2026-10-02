class_name Widgets
extends RefCounted
## Widgets — the reusable component set the brief asks for, as pure static factories.
##
## Everything the game shows is composed from these: resource chips, icon + rarity treatments,
## progress rows, skill rows, activity/recipe rows, key-value rows, tabs, search bars, badges,
## empty states and requirement lines. Using factories rather than a scene per component keeps
## 700+ content records renderable without a scene-tree explosion, and guarantees an item looks
## identical everywhere it appears.

## The narrowest a control may demand before the row containing it becomes the layout problem.
const MIN_CONTROL_W: int = 148

# =========================================================================
#  Resource chip / status bar items
# =========================================================================

static func resource_chip(icon_kind: String, icon_id: String, text: String,
		tooltip := "", color: Color = UITokens.TEXT) -> Control:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", UITokens.SP_3)
	chip.tooltip_text = tooltip if tooltip != "" else text
	var icon := TextureRect.new()
	icon.texture = AssetRegistry.icon(icon_kind, icon_id)
	icon.custom_minimum_size = Vector2(UITokens.ICON_SM, UITokens.ICON_SM)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chip.add_child(icon)
	var l := UIStyle.label(text, false, UITokens.FONT_BODY)
	l.add_theme_color_override("font_color", color)
	l.name = "value"
	chip.add_child(l)
	return chip

## Key=value row used in tables and detail panes.
## A key longer than the column below is not a key any more: "Enchanting Catalyst Reduction
## Percent" is wider than the 260px detail pane, and a Label that cannot wrap sets the minimum
## width of every container it sits in, so the whole card overflows and its values are clipped.
const KEY_COLUMN: int = 132
const KEY_WRAP_CHARS: int = 22

static func key_value(key: String, value: String, value_color: Color = UITokens.TEXT,
		value_tooltip := "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_4)
	var k := UIStyle.label(key, true, UITokens.FONT_SMALL)
	if key.length() > KEY_WRAP_CHARS:
		k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		k.custom_minimum_size = Vector2(KEY_COLUMN, 0)
	row.add_child(k)
	var v := UIStyle.label(value, false, UITokens.FONT_SMALL)
	v.add_theme_color_override("font_color", value_color)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if value_tooltip != "":
		v.tooltip_text = value_tooltip
	row.add_child(v)
	return row

static func badge(text: String, color: Color, tooltip := "") -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITokens.FONT_MICRO)
	l.add_theme_color_override("font_color", color)
	l.add_theme_stylebox_override("normal", UIStyle.chip_box(Color(color.r, color.g, color.b, 0.16)))
	if tooltip != "":
		l.tooltip_text = tooltip
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

## A labelled bar. `color` communicates category; the numeric label carries the same
## information in text so nothing depends on colour alone.
static func progress_bar(value: float, maximum: float, color: Color, text := "",
		height := 14, tooltip := "") -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maxf(1.0, maximum)
	bar.value = clampf(value, 0.0, maxf(1.0, maximum))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, maxi(height, 18) if text != "" else height)
	bar.add_theme_stylebox_override("fill", UIStyle._solid(color, UITokens.R_SM))
	bar.tooltip_text = tooltip if tooltip != "" else text
	if text != "":
		var overlay := Label.new()
		overlay.text = text
		overlay.add_theme_font_size_override("font_size", UITokens.FONT_MICRO)
		overlay.add_theme_color_override("font_color", UITokens.TEXT_STRONG)
		overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(overlay)
	return bar

## Requirement line: current / required, satisfied marker, and an explanation hint.
static func requirement_row(label: String, current: float, required: float, satisfied: bool,
		hint := "", route: Dictionary = {}) -> Control:
	var box := UIStyle.vbox(UITokens.SP_1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_3)
	var color: Color = UITokens.GREEN if satisfied else UITokens.AMBER
	var mark := Label.new()
	mark.text = "✓" if satisfied else "✗"
	mark.add_theme_font_size_override("font_size", UITokens.FONT_SMALL)
	mark.add_theme_color_override("font_color", color)
	mark.custom_minimum_size = Vector2(14, 0)
	row.add_child(mark)
	var name_label := UIStyle.label(label, false, UITokens.FONT_SMALL)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_label)
	var numbers := UIStyle.label(UIStyle.fmt_requirement(current, required, satisfied), false, UITokens.FONT_SMALL)
	numbers.add_theme_color_override("font_color", color)
	numbers.name = "numbers"
	row.add_child(numbers)
	box.add_child(row)
	if hint != "":
		var h := UIStyle.label("    " + hint, true, UITokens.FONT_MICRO)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(h)
	if not satisfied and not route.is_empty():
		var go := UIStyle.mini_button("Go")
		go.tooltip_text = "Open the activity that resolves this requirement"
		var r: Dictionary = route
		go.pressed.connect(func(): Screens.go(r))
		var holder := HBoxContainer.new()
		holder.add_theme_constant_override("separation", UITokens.SP_3)
		holder.add_child(Control.new())
		holder.add_child(go)
		box.add_child(holder)
	return box

# =========================================================================
#  Items
# =========================================================================

## Item icon with the rarity treatment: a coloured border and a corner notch, so rarity is
## visible without colour alone (the tooltip states the rarity in words).
static func item_icon(item_id: String, size := UITokens.ICON_MD) -> Control:
	var rarity: Dictionary = UIStyle.item_rarity(item_id)
	var frame := PanelContainer.new()
	var sb := UIStyle.surface_box("sunken")
	sb.set_corner_radius_all(UITokens.R_SM)
	sb.border_color = rarity["color"]
	sb.set_border_width_all(2 if rarity["key"] != "common" else 1)
	sb.content_margin_left = 1
	sb.content_margin_right = 1
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	frame.add_theme_stylebox_override("panel", sb)
	frame.custom_minimum_size = Vector2(size, size)
	var tex_rect := TextureRect.new()
	tex_rect.texture = AssetRegistry.item_icon(item_id)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.add_child(tex_rect)
	frame.tooltip_text = item_tooltip(item_id)
	return frame

static func item_tooltip(item_id: String) -> String:
	var item: Dictionary = DataLoader.get_item(item_id)
	if item.is_empty():
		return item_id
	var rarity: Dictionary = UIStyle.item_rarity(item_id)
	var lines: Array[String] = [str(item.get("name", item_id))]
	lines.append("%s · %s" % [rarity["label"], str(item.get("item_type", "item")).capitalize()])
	if str(item.get("description", "")) != "":
		lines.append(str(item["description"]))
	var stats: Dictionary = item.get("equipment_stats", {})
	if not stats.is_empty():
		var parts: Array[String] = []
		for key in stats.keys():
			parts.append("%s %s" % [str(key).replace("_", " "), UIStyle.fmt_signed(float(stats[key]))])
		lines.append(" · ".join(parts))
	if not (item.get("passive_modifiers", {}) as Dictionary).is_empty():
		lines.append("Passive: " + UIStyle.describe_modifier_table(item["passive_modifiers"]))
	for skill_id in (item.get("level_requirements", {}) as Dictionary).keys():
		lines.append("Requires %s %d" % [DataLoader.get_skill(str(skill_id)).get("name", skill_id), int(item["level_requirements"][skill_id])])
	if int(item.get("sell_price", 0)) > 0:
		lines.append("Sells for %s GP" % UIStyle.fmt_exact(float(item["sell_price"])))
	return "\n".join(lines)

## One row describing an item and a quantity, with rarity colour and an optional action.
static func item_row(item_id: String, quantity: int, action_text := "",
		action: Callable = Callable(), selected := false, subtitle := "") -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIStyle.surface_box("raised" if selected else "row"))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UITokens.SP_4)
	row.add_child(h)
	var icon := item_icon(item_id)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var text_col := UIStyle.vbox(UITokens.SP_1)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := UIStyle.label(DataLoader.get_item(item_id).get("name", item_id), false, UITokens.FONT_BODY)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_child(name_label)
	var rarity: Dictionary = UIStyle.item_rarity(item_id)
	var metadata := HFlowContainer.new()
	metadata.add_theme_constant_override("h_separation", UITokens.SP_3)
	metadata.add_theme_constant_override("v_separation", UITokens.SP_1)
	metadata.add_child(badge(str(rarity["label"]), rarity["color"], "Presentation rarity derived from tier and value"))
	var sub: String = subtitle
	if sub == "":
		var item: Dictionary = DataLoader.get_item(item_id)
		sub = str(item.get("item_type", "")).capitalize()
		if int(item.get("sell_price", 0)) > 0:
			sub += " · %s GP each" % UIStyle.fmt(float(item["sell_price"]))
	var sub_label := UIStyle.label(sub, true, UITokens.FONT_MICRO)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(sub_label)
	h.add_child(text_col)
	metadata.add_child(UIStyle.colored_label("×%s" % UIStyle.fmt_exact(float(quantity)), UITokens.TEXT_STRONG, UITokens.FONT_BODY))
	if action_text != "" and action.is_valid():
		var b := UIStyle.mini_button(action_text)
		b.pressed.connect(action)
		metadata.add_child(b)
	text_col.add_child(metadata)
	return row

# =========================================================================
#  Skills & activities
# =========================================================================

static func skill_row(skill_id: String, selected: bool, on_press: Callable) -> Control:
	var skill: Dictionary = DataLoader.get_skill(skill_id)
	var level: int = PlayerData.get_level(skill_id)
	var xp: float = PlayerData.get_xp(skill_id)
	var row := Button.new()
	row.toggle_mode = false
	row.custom_minimum_size = Vector2(0, UITokens.H_ROW + 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("normal", UIStyle.surface_box("raised" if selected else "row"))
	row.add_theme_stylebox_override("hover", UIStyle.surface_box("raised"))
	row.add_theme_stylebox_override("pressed", UIStyle.surface_box("raised", true))
	row.add_theme_stylebox_override("focus", UIStyle.surface_box("raised", true))
	if selected:
		row.add_theme_stylebox_override("normal", UIStyle.surface_box("raised", true))
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", UITokens.SP_4)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = UITokens.SP_4
	content.offset_right = -UITokens.SP_4
	var icon := TextureRect.new()
	icon.texture = AssetRegistry.skill_icon(skill_id)
	icon.custom_minimum_size = Vector2(UITokens.ICON_SM, UITokens.ICON_SM)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	var col := UIStyle.vbox(UITokens.SP_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UIStyle.label(skill.get("name", skill_id), false, UITokens.FONT_SMALL)
	col.add_child(name_label)
	col.add_child(progress_bar(XPTable.level_progress(xp, level), 1.0,
		UITokens.GOLD if str(skill.get("category", "")) == "combat" else UITokens.TEAL, "", 5))
	content.add_child(col)
	var lvl := UIStyle.label(str(level), false, UITokens.FONT_BODY)
	lvl.add_theme_color_override("font_color", UITokens.TEXT_STRONG)
	lvl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(lvl)
	row.add_child(content)
	row.pressed.connect(on_press)
	row.tooltip_text = "%s — level %d\nXP %s / %s" % [
		skill.get("name", skill_id), level,
		UIStyle.fmt_exact(xp), UIStyle.fmt_exact(float(XPTable.xp_for_level(mini(level + 1, XPTable.MAX_LEVEL))))]
	return row

## An action/recipe row. Shows level requirement, mastery, and why it might be locked.
static func activity_row(skill_id: String, action: Dictionary, selected: bool,
		on_press: Callable) -> Control:
	var action_id: String = str(action.get("id", ""))
	var level: int = PlayerData.get_level(skill_id)
	var req: int = int(action.get("level_required", 1))
	var unlocked: bool = level >= req
	var mastery: int = MasteryManager.get_level(skill_id, action_id)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", UITokens.SP_1)
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 60)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.disabled = not unlocked
	row.add_theme_stylebox_override("normal", UIStyle.surface_box("raised" if selected else "row"))
	row.add_theme_stylebox_override("hover", UIStyle.surface_box("raised"))
	row.add_theme_stylebox_override("pressed", UIStyle.surface_box("raised", true))
	row.add_theme_stylebox_override("focus", UIStyle.surface_box("raised", true))
	row.add_theme_stylebox_override("disabled", UIStyle.surface_box("row"))
	if selected:
		row.add_theme_stylebox_override("normal", UIStyle.surface_box("raised", true))
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", UITokens.SP_4)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = UITokens.SP_4
	content.offset_right = -UITokens.SP_4
	var outputs: Dictionary = action.get("output_items", {})
	var preview := UIStyle.icon_texture("skills", skill_id)
	if skill_id == "inscription" and action.has("research_unlock"):
		preview.texture = AssetRegistry.item_icon("scribe_" + str(action.research_unlock) + "_inked")
	elif not outputs.is_empty():
		preview.texture = AssetRegistry.item_icon(str(outputs.keys()[0]))
	preview.custom_minimum_size = Vector2(40, 40)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.modulate.a = 1.0 if unlocked else 0.4
	content.add_child(preview)
	var name_label := UIStyle.label(str(action.get("name", action_id)), false, UITokens.FONT_SMALL)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		name_label.add_theme_color_override("font_color", UITokens.DISABLED)
	content.add_child(name_label)
	if mastery > 0:
		var m := badge("M%d" % mastery, UITokens.PURPLE, "Activity mastery %d — improves this activity only" % mastery)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(m)
	if not unlocked:
		var lock := badge("Lv %d" % req, UITokens.AMBER, "Requires %s %d — you are %d" % [
			DataLoader.get_skill(skill_id).get("name", skill_id), req, level])
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(lock)
	var estimate: Dictionary = ActionEstimates.for_action(skill_id, action_id)
	var interval: float = float(estimate.get("effective_interval", action.get("base_interval", 3.0)))
	var time_label := UIStyle.label("%.1fs\n≈ %s XP/h" % [interval, UIStyle.fmt(float(estimate.get("xp_per_hour", 0)))], true, UITokens.FONT_MICRO)
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(time_label)
	row.add_child(content)
	row.pressed.connect(func(): on_press.call(action_id))
	var tips: Array[String] = [str(action.get("name", action_id))]
	if str(action.get("description", "")) != "":
		tips.append(str(action["description"]))
	tips.append(ActionEstimates.summary_line(skill_id, action_id))
	tips.append("Expected respawn %.2fs + failure stun %.2fs per attempt" % [float(estimate.get("node_overhead", 0)), float(estimate.get("stun_overhead", 0))])
	if not estimate.get("next_unlock", {}).is_empty(): tips.append("Next unlock: %s · %s" % [str(estimate.next_unlock.name), UIStyle.fmt_duration(float(estimate.next_unlock.seconds))])
	if not (action.get("input_items", {}) as Dictionary).is_empty():
		tips.append("Consumes: " + _item_list(action["input_items"]))
	if not (action.get("output_items", {}) as Dictionary).is_empty():
		tips.append("Produces: " + _item_list(action["output_items"]))
	if not (action.get("secondary_outputs", []) as Array).is_empty():
		var sec_parts: Array[String] = []
		for sec in action["secondary_outputs"]:
			if typeof(sec) == TYPE_DICTIONARY:
				sec_parts.append("%s (%.2f%%)" % [
					DataLoader.get_item(str(sec.get("item_id", ""))).get("name", "?"),
					float(sec.get("chance", 0.0)) * 100.0])
		tips.append("Rare: " + ", ".join(sec_parts))
	if not unlocked:
		tips.append("LOCKED — requires %s %d" % [DataLoader.get_skill(skill_id).get("name", skill_id), req])
	row.tooltip_text = "\n".join(tips)
	card.add_child(row)
	return card

static func _item_list(items: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id in items.keys():
		parts.append("%s ×%s" % [DataLoader.get_item(str(item_id)).get("name", item_id), UIStyle.fmt_exact(float(items[item_id]))])
	return ", ".join(parts)

# =========================================================================
#  Tabs, search, empty states
# =========================================================================

## Segmented tab strip. Returns {root, buttons} so the caller can drive selection.
static func tab_strip(labels: Array, on_select: Callable, selected_index := 0) -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", UITokens.SP_2)
	var buttons: Array[Button] = []
	for i in range(labels.size()):
		var b := Button.new()
		b.text = str(labels[i])
		b.toggle_mode = true
		b.button_pressed = i == selected_index
		b.custom_minimum_size = Vector2(0, UITokens.H_CONTROL)
		b.add_theme_font_size_override("font_size", UITokens.FONT_SMALL)
		var idx: int = i
		b.pressed.connect(func(): on_select.call(idx))
		buttons.append(b)
		root.add_child(b)
	root.set_meta("buttons", buttons)
	return {"root": root, "buttons": buttons}

## Same contract as tab_strip, but the strip WRAPS. A fixed HBox is fine for four or five tabs and
## catastrophic for thirty: it sums every tab's minimum width into the panel's minimum, which is
## exactly how a narrow window ends up with a horizontal scrollbar.
static func tab_flow(labels: Array, on_select: Callable, selected_index := 0) -> Dictionary:
	var root := HFlowContainer.new()
	root.add_theme_constant_override("h_separation", UITokens.SP_2)
	root.add_theme_constant_override("v_separation", UITokens.SP_2)
	var buttons: Array[Button] = []
	for i in range(labels.size()):
		var b := Button.new()
		b.text = str(labels[i])
		b.toggle_mode = true
		b.button_pressed = i == selected_index
		b.custom_minimum_size = Vector2(0, UITokens.H_CONTROL)
		b.add_theme_font_size_override("font_size", UITokens.FONT_SMALL)
		var idx: int = i
		b.pressed.connect(func(): on_select.call(idx))
		buttons.append(b)
		root.add_child(b)
	root.set_meta("buttons", buttons)
	return {"root": root, "buttons": buttons}

## `width` is a preferred width, not a floor: a search field that cannot shrink is what forces a
## panel to overflow a narrow window.
static func search_bar(placeholder: String, on_change: Callable, width := 220) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.custom_minimum_size = Vector2(mini(width, MIN_CONTROL_W), UITokens.H_CONTROL)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(on_change)
	le.tooltip_text = placeholder
	return le

static func option_menu(options: Array, on_select: Callable, selected := 0) -> OptionButton:
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(MIN_CONTROL_W, UITokens.H_CONTROL)
	# Long option names must not dictate the width of the screen that contains them.
	ob.clip_text = true
	ob.fit_to_longest_item = false
	for o in options:
		ob.add_item(str(o))
	ob.selected = clampi(selected, 0, maxi(0, options.size() - 1))
	ob.item_selected.connect(on_select)
	return ob

## A MenuButton whose popup reports an id every time it is chosen — unlike an OptionButton,
## the same entry can be picked repeatedly ("Sell 1" five times in a row must work).
static func quantity_menu(entries: Array, on_id: Callable, tooltip := "") -> MenuButton:
	var mb := MenuButton.new()
	mb.text = str(entries[0].get("label", "Choose…")) if not entries.is_empty() else "Choose…"
	mb.flat = false
	mb.custom_minimum_size = Vector2(112, UITokens.H_CONTROL - 6)
	mb.add_theme_font_size_override("font_size", UITokens.FONT_SMALL)
	mb.tooltip_text = tooltip
	var popup := mb.get_popup()
	popup.clear()
	for i in range(entries.size()):
		popup.add_item(str(entries[i].get("label", "?")), i)
		if entries[i].has("tooltip"):
			popup.set_item_tooltip(i, str(entries[i]["tooltip"]))
	popup.id_pressed.connect(func(id: int): on_id.call(id))
	return mb

static func empty_state(title: String, body: String, action_text := "",
		action: Callable = Callable()) -> Control:
	var box := UIStyle.vbox(UITokens.SP_4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(UIStyle.spacer())
	var t := UIStyle.label(title, true, UITokens.FONT_SUBHEAD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	if body != "":
		var b := UIStyle.label(body, true, UITokens.FONT_SMALL)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(b)
	if action_text != "" and action.is_valid():
		var btn := UIStyle.primary_button(action_text)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(action)
		box.add_child(btn)
	box.add_child(UIStyle.spacer())
	return box

## Detach a cached widget from wherever it currently sits so it can be re-seated safely.
## A panel that keeps a widget in a member (the bounded event log) rebuilds its box with a clear
## that frees every child: without this, the clear destroys the cached widget, and a later
## add_child fails because the widget is still parented to the box that is being torn down.
static func detach(node: Node) -> void:
	if node != null and node.get_parent() != null:
		node.get_parent().remove_child(node)

## Bounded event log. The UI never keeps an unbounded list in memory.
static func event_log(max_lines := 60) -> Dictionary:
	var box := UIStyle.vbox(UITokens.SP_2)
	var lines: Array[String] = []
	var label := UIStyle.label("", true, UITokens.FONT_SMALL)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var api := {
		"root": box,
		"push": func(text: String):
			lines.insert(0, text)
			while lines.size() > max_lines:
				lines.pop_back()
			label.text = "\n".join(lines),
		"clear": func():
			lines.clear()
			label.text = "",
	}
	return api

## Compact number cards that wrap instead of forcing narrow screens wider.
static func stat_card(caption: String, value: String, color: Color = UITokens.GOLD) -> Control:
	var card := UIStyle.card()
	card.custom_minimum_size = Vector2(148, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var number := UIStyle.colored_label(value, color, UITokens.FONT_HEAD)
	number.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(number)
	col.add_child(UIStyle.label(caption, true, UITokens.FONT_MICRO))
	return card

static func item_rewards(items: Dictionary) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", UITokens.SP_4)
	flow.add_theme_constant_override("v_separation", UITokens.SP_3)
	for item_id in items:
		var chip := UIStyle.card()
		var row := UIStyle.hbox()
		chip.add_child(row)
		row.add_child(item_icon(str(item_id), 40))
		row.add_child(UIStyle.colored_label("×%s" % UIStyle.fmt_exact(float(items[item_id])), UITokens.GOLD_BRIGHT))
		chip.tooltip_text = item_tooltip(str(item_id))
		flow.add_child(chip)
	return flow
