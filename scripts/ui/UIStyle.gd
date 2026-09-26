class_name UIStyle
extends RefCounted
## UIStyle — builds the Godot Theme from UITokens and provides the shared widget factories.
##
## Two responsibilities:
##   1. build_theme(): every control class gets consistent styling, including focus rings so the
##      whole game is keyboard-navigable and no information is conveyed by colour alone.
##   2. formatting helpers used across panels (numbers, durations, percentages, requirements)
##      so the same value never renders two different ways in two places.

# Backwards-compatible token aliases used by remaining panels.
const BG := UITokens.BG
const PANEL := UITokens.SURFACE
const PANEL2 := UITokens.SURFACE_2
const INK := UITokens.TEXT
const MUTED := UITokens.TEXT_MUTED
const ACCENT := UITokens.GOLD
const OK := UITokens.TEAL
const WARN := UITokens.AMBER
const DANGER := UITokens.RED

# =========================================================================
#  Style boxes
# =========================================================================

static func surface_box(kind: String = "panel", accent: bool = false) -> StyleBox:
	var path: String = "res://assets/ui/%s_9slice.png" % kind
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		var m: int = UITokens.NINE_SLICE_MARGINS.get(kind, 12)
		sb.content_margin_left = m; sb.content_margin_right = m
		sb.content_margin_top = m; sb.content_margin_bottom = m
		sb.expand_margin_left = m; sb.expand_margin_right = m
		sb.expand_margin_top = m; sb.expand_margin_bottom = m
		return sb
	return _flat_fallback(kind, accent)  # today's StyleBoxFlat body, moved verbatim

static func _flat_fallback(kind: String, accent: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	match kind:
		"sunken":
			sb.bg_color = UITokens.SURFACE_SUNKEN
		"row":
			sb.bg_color = UITokens.SURFACE_2
		"raised":
			sb.bg_color = UITokens.SURFACE_3
		_:
			sb.bg_color = UITokens.SURFACE
	if accent:
		sb.border_color = UITokens.GOLD
		sb.set_border_width_all(1)
	else:
		sb.border_color = UITokens.BORDER
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(UITokens.R_LG)
	_inset(sb, UITokens.SP_5, UITokens.SP_5, UITokens.SP_4, UITokens.SP_4)
	if kind == "panel":
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(0, 1)
	return sb

static func _inset(sb: StyleBoxFlat, left: int, right: int, top: int, bottom: int) -> void:
	sb.content_margin_left = left
	sb.content_margin_right = right
	sb.content_margin_top = top
	sb.content_margin_bottom = bottom

static func panel_style(accent := false) -> StyleBox:
	return surface_box("panel", accent)

static func chip_box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(UITokens.R_SM)
	sb.border_color = Color(1, 1, 1, 0.10)
	sb.set_border_width_all(1)
	_inset(sb, UITokens.SP_3, UITokens.SP_3, UITokens.SP_1, UITokens.SP_1)
	return sb

# =========================================================================
#  Theme
# =========================================================================

static func build_theme() -> Theme:
	var th := Theme.new()

	# --- fonts ------------------------------------------------------------
	# Missing files keep the default font, never crash (pinned by test_identity_theme_builds).
	if ResourceLoader.exists("res://assets/fonts/ember_display.ttf"):
		th.set_font("display", "", load("res://assets/fonts/ember_display.ttf"))
	if ResourceLoader.exists("res://assets/fonts/ember_text.ttf"):
		th.set_font("text", "", load("res://assets/fonts/ember_text.ttf"))

	# --- containers -------------------------------------------------------
	th.set_stylebox("panel", "PanelContainer", surface_box("panel"))
	th.set_stylebox("panel", "Panel", surface_box("panel"))
	th.set_stylebox("panel", "ItemList", surface_box("sunken"))
	th.set_stylebox("panel", "PopupMenu", surface_box("raised"))
	th.set_stylebox("panel", "PopupPanel", surface_box("raised"))
	th.set_stylebox("panel", "TooltipPanel", surface_box("raised"))
	th.set_stylebox("panel", "AcceptDialog", surface_box("panel"))
	th.set_stylebox("panel", "TabContainer", surface_box("panel"))
	th.set_stylebox("panel_info", "AcceptDialog", surface_box("panel"))
	th.set_stylebox("panel", "Window", surface_box("panel"))

	# --- buttons ----------------------------------------------------------
	var b_normal := _button_box(UITokens.SURFACE_2, UITokens.BORDER)
	var b_hover := _button_box(UITokens.SURFACE_3, UITokens.BORDER_STRONG)
	var b_pressed := _button_box(UITokens.SURFACE_3, UITokens.GOLD)
	# A visible focus ring is mandatory: keyboard navigation must be legible, and the ring uses
	# a border *and* a bright colour so it does not rely on hue alone.
	var b_focus := _button_box(UITokens.SURFACE_3, UITokens.GOLD_BRIGHT)
	b_focus.set_border_width_all(2)
	var b_disabled := _button_box(UITokens.SURFACE, UITokens.BORDER)
	b_disabled.bg_color = Color(UITokens.SURFACE.r, UITokens.SURFACE.g, UITokens.SURFACE.b, 0.55)

	th.set_stylebox("normal", "Button", b_normal)
	th.set_stylebox("hover", "Button", b_hover)
	th.set_stylebox("pressed", "Button", b_pressed)
	th.set_stylebox("focus", "Button", b_focus)
	th.set_stylebox("disabled", "Button", b_disabled)
	th.set_color("font_color", "Button", UITokens.TEXT)
	th.set_color("font_hover_color", "Button", UITokens.TEXT_STRONG)
	th.set_color("font_pressed_color", "Button", UITokens.GOLD_BRIGHT)
	th.set_color("font_focus_color", "Button", UITokens.TEXT_STRONG)
	th.set_color("font_disabled_color", "Button", UITokens.DISABLED)
	th.set_font_size("font_size", "Button", UITokens.FONT_BODY)
	th.set_constant("h_separation", "Button", UITokens.SP_3)

	for cls in ["OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		th.set_stylebox("normal", cls, b_normal)
		th.set_stylebox("hover", cls, b_hover)
		th.set_stylebox("pressed", cls, b_pressed)
		th.set_stylebox("focus", cls, b_focus)
		th.set_stylebox("disabled", cls, b_disabled)
		th.set_color("font_color", cls, UITokens.TEXT)
		th.set_color("font_hover_color", cls, UITokens.TEXT_STRONG)
		th.set_color("font_disabled_color", cls, UITokens.DISABLED)
		th.set_font_size("font_size", cls, UITokens.FONT_BODY)

	for cls2 in ["HScrollBar", "VScrollBar"]:
		var grab := StyleBoxFlat.new()
		grab.bg_color = UITokens.BORDER_STRONG
		grab.set_corner_radius_all(UITokens.R_SM)
		_inset(grab, 0, 0, 0, 0)
		th.set_stylebox("grabber", cls2, grab)
		th.set_stylebox("grabber_highlight", cls2, _solid(UITokens.GOLD, UITokens.R_SM))
		th.set_stylebox("grabber_pressed", cls2, _solid(UITokens.GOLD_BRIGHT, UITokens.R_SM))
		th.set_stylebox("scroll", cls2, _solid(UITokens.SURFACE_SUNKEN, UITokens.R_SM))

	# --- text inputs ------------------------------------------------------
	var le_normal: StyleBoxFlat = surface_box("sunken")
	le_normal.set_corner_radius_all(UITokens.R_MD)
	var le_focus: StyleBoxFlat = surface_box("sunken")
	le_focus.set_corner_radius_all(UITokens.R_MD)
	le_focus.border_color = UITokens.GOLD
	le_focus.set_border_width_all(2)
	th.set_stylebox("normal", "LineEdit", le_normal)
	th.set_stylebox("focus", "LineEdit", le_focus)
	th.set_stylebox("read_only", "LineEdit", le_normal)
	th.set_color("font_color", "LineEdit", UITokens.TEXT)
	th.set_color("font_placeholder_color", "LineEdit", UITokens.TEXT_DIM)
	th.set_color("caret_color", "LineEdit", UITokens.GOLD)
	th.set_color("selection_color", "LineEdit", Color(UITokens.GOLD.r, UITokens.GOLD.g, UITokens.GOLD.b, 0.35))
	th.set_font_size("font_size", "LineEdit", UITokens.FONT_BODY)
	th.set_stylebox("normal", "TextEdit", le_normal)
	th.set_stylebox("focus", "TextEdit", le_focus)

	# --- labels -----------------------------------------------------------
	for cls3 in ["Label", "RichTextLabel", "LinkButton"]:
		th.set_color("font_color", cls3, UITokens.TEXT)
		th.set_font_size("font_size", cls3, UITokens.FONT_BODY)
	th.set_color("default_color", "RichTextLabel", UITokens.TEXT)
	th.set_font_size("normal_font_size", "RichTextLabel", UITokens.FONT_BODY)
	th.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	th.set_color("font_color", "TooltipLabel", UITokens.TEXT)
	th.set_font_size("font_size", "TooltipLabel", UITokens.FONT_SMALL)

	# --- progress ---------------------------------------------------------
	th.set_stylebox("background", "ProgressBar", _solid(UITokens.SURFACE_SUNKEN, UITokens.R_SM))
	th.set_stylebox("fill", "ProgressBar", _solid(UITokens.TEAL, UITokens.R_SM))
	th.set_color("font_color", "ProgressBar", UITokens.TEXT)
	th.set_font_size("font_size", "ProgressBar", UITokens.FONT_MICRO)

	# --- lists & trees ----------------------------------------------------
	th.set_stylebox("panel", "Tree", surface_box("sunken"))
	th.set_color("font_color", "Tree", UITokens.TEXT)
	th.set_color("font_selected_color", "Tree", UITokens.GOLD_BRIGHT)
	th.set_stylebox("selected", "Tree", _solid(UITokens.SURFACE_3, UITokens.R_SM))
	th.set_stylebox("selected_focus", "Tree", _solid(UITokens.SURFACE_3, UITokens.R_SM))
	th.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	th.set_color("font_color", "ItemList", UITokens.TEXT)
	th.set_color("font_selected_color", "ItemList", UITokens.GOLD_BRIGHT)
	th.set_stylebox("selected", "ItemList", _solid(UITokens.SURFACE_3, UITokens.R_SM))
	th.set_stylebox("selected_focus", "ItemList", _solid(UITokens.SURFACE_3, UITokens.R_SM))
	th.set_stylebox("cursor", "ItemList", _solid(UITokens.BORDER_STRONG, UITokens.R_SM))
	th.set_stylebox("cursor_unfocused", "ItemList", _solid(UITokens.BORDER, UITokens.R_SM))
	th.set_constant("v_separation", "ItemList", UITokens.SP_2)

	# --- tabs -------------------------------------------------------------
	th.set_stylebox("tab_selected", "TabContainer", _solid(UITokens.SURFACE_3, UITokens.R_MD))
	th.set_stylebox("tab_unselected", "TabContainer", _solid(UITokens.SURFACE, UITokens.R_MD))
	th.set_stylebox("tab_hovered", "TabContainer", _solid(UITokens.SURFACE_2, UITokens.R_MD))
	th.set_color("font_selected_color", "TabContainer", UITokens.GOLD_BRIGHT)
	th.set_color("font_unselected_color", "TabContainer", UITokens.TEXT_MUTED)
	th.set_stylebox("panel", "TabContainer", surface_box("panel"))

	# --- separators -------------------------------------------------------
	th.set_stylebox("separator", "HSeparator", _solid(UITokens.BORDER, UITokens.R_SM))
	th.set_stylebox("separator", "VSeparator", _solid(UITokens.BORDER, UITokens.R_SM))
	th.set_constant("separation", "HSeparator", UITokens.SP_4)
	th.set_constant("separation", "VSeparator", UITokens.SP_4)

	th.set_font_size("font_size", "HeaderSmall", UITokens.FONT_SUBHEAD)
	return th

static func _solid(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	_inset(sb, UITokens.SP_2, UITokens.SP_2, UITokens.SP_1, UITokens.SP_1)
	return sb

static func _button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UITokens.R_MD)
	_inset(sb, UITokens.SP_5, UITokens.SP_5, UITokens.SP_3, UITokens.SP_3)
	return sb

# =========================================================================
#  Label & container factories
# =========================================================================

## A sentence in a Label reports its full width as its minimum, which is what makes a panel
## refuse to fit a narrow window. Prose therefore wraps by default and short labels stay compact,
## so no call site has to remember which of the two it is writing.
const WRAP_THRESHOLD: int = 48

static func label(text: String, muted := false, size := UITokens.FONT_BODY) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", UITokens.TEXT_MUTED if muted else UITokens.TEXT)
	# Always fill, never shrink. An autowrapping Label whose minimum width is ~1px collapses to a
	# single character per line unless it is allowed to fill; and callers enable autowrap on their
	# own all over the UI, so the flag cannot be tied to a length check here. Filling is also
	# harmless for short left-aligned text: it reads identically, it just claims the row.
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Only long text is wrapped here. An empty label is usually filled in later with short text
	# ("Combat level 3"), and enabling autowrap on it would make its minimum width ~1px, collapsing
	# it to one character per line. Callers that fill long text set autowrap explicitly.
	if text.length() > WRAP_THRESHOLD:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func title(text: String, size := UITokens.FONT_HEAD) -> Label:
	var l := label(text, false, size)
	l.add_theme_color_override("font_color", UITokens.GOLD_BRIGHT)
	return l

static func colored_label(text: String, color: Color, size := UITokens.FONT_BODY) -> Label:
	var l := label(text, false, size)
	l.add_theme_color_override("font_color", color)
	return l

## A section heading with a horizontal rule, used instead of "every element is a card".
static func section(title_text: String, hint := "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITokens.SP_3)
	var head := label(title_text.to_upper(), false, UITokens.FONT_SMALL)
	head.add_theme_color_override("font_color", UITokens.GOLD_BRIGHT)
	box.add_child(head)
	if hint != "":
		var h := label(hint, true, UITokens.FONT_MICRO)
		box.add_child(h)
	return box

static func button(text: String, tooltip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
	b.custom_minimum_size = Vector2(0, UITokens.H_CONTROL)
	if tooltip != "":
		b.tooltip_text = tooltip
	return b

## A compact, low-emphasis control (used inside dense rows).
static func mini_button(text: String, tooltip := "") -> Button:
	var b := button(text, tooltip)
	b.add_theme_font_size_override("font_size", UITokens.FONT_SMALL)
	b.custom_minimum_size = Vector2(0, UITokens.H_CONTROL - 6)
	return b

## Primary action: the one gold control on a screen that the player is meant to press.
static func primary_button(text: String, tooltip := "") -> Button:
	var b := button(text, tooltip)
	b.add_theme_color_override("font_color", UITokens.GOLD_BRIGHT)
	var box := _button_box(UITokens.SURFACE_2, UITokens.GOLD)
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("hover", _button_box(UITokens.SURFACE_3, UITokens.GOLD_BRIGHT))
	return b

static func danger_button(text: String, tooltip := "") -> Button:
	var b := button(text, tooltip)
	b.add_theme_color_override("font_color", UITokens.RED)
	b.add_theme_stylebox_override("normal", _button_box(UITokens.SURFACE_2, UITokens.RED))
	return b

static func panel(accent := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", surface_box("panel", accent))
	return p

static func card(accent := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", surface_box("row", accent))
	return p

static func scroll(vertical := true) -> ScrollContainer:
	var s := ScrollContainer.new()
	if vertical:
		s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

static func vbox(separation := UITokens.SP_4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v

static func hbox(separation := UITokens.SP_4) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

static func icon_texture(kind: String, id: String) -> TextureRect:
	var tex_rect := TextureRect.new()
	tex_rect.texture = AssetRegistry.icon(kind, id)
	tex_rect.custom_minimum_size = Vector2(UITokens.ICON_MD, UITokens.ICON_MD)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tex_rect

# =========================================================================
#  Formatting — one value, one rendering
# =========================================================================

static func fmt(v: float) -> String:
	var neg: bool = v < 0.0
	var a: float = absf(v)
	var out: String
	if a >= 1_000_000_000_000.0:
		out = "%.2fT" % (a / 1_000_000_000_000.0)
	elif a >= 1_000_000_000.0:
		out = "%.2fB" % (a / 1_000_000_000.0)
	elif a >= 1_000_000.0:
		out = "%.2fM" % (a / 1_000_000.0)
	elif a >= 100_000.0:
		out = "%.1fK" % (a / 1_000.0)
	elif a >= 10_000.0:
		out = "%.2fK" % (a / 1_000.0)
	elif a == floor(a):
		out = str(int(a))
	else:
		out = "%.2f" % a
	return ("-" + out) if neg else out

## Exact, grouped form for tooltips where the abbreviated value would hide information.
static func fmt_exact(v: float) -> String:
	var s: String = str(int(round(v)))
	var neg: bool = s.begins_with("-")
	if neg:
		s = s.substr(1)
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if neg else out

static func fmt_duration(seconds: float) -> String:
	if seconds < 0.0 or not is_finite(seconds):
		return "—"
	var s: int = int(round(seconds))
	if s < 60:
		return "%ds" % s
	var m: int = floori(s / 60.0)
	if m < 60:
		return "%dm %02ds" % [m, s % 60]
	var h: int = floori(m / 60.0)
	if h < 24:
		return "%dh %02dm" % [h, m % 60]
	return "%dd %02dh" % [floori(h / 24.0), h % 24]

static func fmt_percent(fraction: float) -> String:
	return "%.1f%%" % (fraction * 100.0)

static func fmt_signed(v: float, suffix := "") -> String:
	var sign_str: String = "+" if v >= 0.0 else ""
	return "%s%s%s" % [sign_str, fmt(v), suffix]

## "3 / 12" with a satisfied marker — never rely on colour alone to say "requirement met".
static func fmt_requirement(current: float, required: float, satisfied: bool) -> String:
	var mark: String = "✓" if satisfied else "✗"
	return "%s %s / %s" % [mark, fmt(current), fmt(required)]

## Rarity colour + label for an item id (presentation only).
static func item_rarity(item_id: String) -> Dictionary:
	var item: Dictionary = DataLoader.get_item(item_id)
	var key: String = UITokens.rarity_for_item(item)
	var r: Dictionary = UITokens.rarity(key)
	return {"key": key, "label": str(r["label"]), "color": r["color"]}

## Human-readable modifier description, used in tooltips so bonuses are never unexplained.
const MODIFIER_LABELS: Dictionary = {
	"global_skill_xp_percent": "all skill XP",
	"global_mastery_xp_percent": "mastery XP",
	"global_gp_percent": "GP earned",
	"global_slayer_coins_percent": "Huntsman coins",
	"global_double_loot_percent": "double loot chance",
	"global_accuracy_percent": "accuracy (all styles)",
	"bank_space_flat": "storage stacks",
	"damage_reduction_percent": "damage reduction",
	"attack_interval_percent": "attack speed",
	"attack_interval_flat": "attack interval",
	"crit_chance_percent": "critical chance",
	"crit_multiplier_percent": "critical damage",
	"life_steal_percent": "life steal",
	"prayer_cost_reduction_percent": "Devotion point cost",
	"ammo_preservation_percent": "ammunition preservation",
	"rune_preservation_percent": "rune preservation",
	"food_healing_percent": "food healing",
	"auto_eat_threshold_percent": "auto-eat threshold",
	"auto_eat_efficiency_percent": "auto-eat efficiency",
	"respawn_time_percent": "enemy respawn time",
	"blessed_bone_offering_flat": "prayer points per bone",
	"hidden_levels": "effective levels",
	"doubling_percent": "double output chance",
	"preservation_percent": "material preservation",
	"interval_percent": "action speed",
	"interval_flat": "action interval",
	"resource_flat": "flat output",
	"node_preservation_percent": "node preservation",
	"skill_xp_percent": "skill XP",
	"mastery_xp_percent": "mastery XP",
	"max_hit_percent": "max hit",
	"max_hit_flat": "max hit (flat)",
	"accuracy_percent": "accuracy",
	"evasion_percent": "evasion",
}

static func describe_modifier(key: String, value: float) -> String:
	var desc: String = str(MODIFIER_LABELS.get(key, key.replace("_", " ")))
	if key.ends_with("_percent"):
		return "%s %s" % [fmt_signed(value, "%"), desc]
	return "%s %s" % [fmt_signed(value), desc]

static func describe_modifier_table(mods: Dictionary) -> String:
	if mods.is_empty():
		return ""
	var parts: Array[String] = []
	for key in mods.keys():
		parts.append(describe_modifier(str(key), float(mods[key])))
	return " · ".join(parts)
