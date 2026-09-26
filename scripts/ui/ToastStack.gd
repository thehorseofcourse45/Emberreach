extends Control
class_name ToastStack
## ToastStack — non-blocking feedback.
##
## Guard rails the brief asks for: notifications are useful rather than constant (identical
## messages collapse into a counter instead of stacking), the list is bounded, and the whole
## stack respects reduced-motion and never steals focus or blocks a control.

const MAX_VISIBLE: int = 4
const LIFETIME: float = 5.0
const LIFETIME_ERROR: float = 9.0

var _column: VBoxContainer
var _entries: Array = []   # [{node, timer, text, count, label}]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	custom_minimum_size = Vector2(320, 0)
	offset_left = -336
	offset_top = 56
	offset_right = -12
	_column = UIStyle.vbox(UITokens.SP_2)
	_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	_column.custom_minimum_size = Vector2(320, 0)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	EventBus.notification.connect(push)

func push(text: String, kind: String = "info") -> void:
	if text.strip_edges() == "":
		return
	if SimulationMode.is_silent():
		return   # offline catch-up reports through the summary, not through toasts
	# Collapse a repeated message into a counter instead of adding another toast.
	for entry in _entries:
		if entry["text"] == text:
			entry["count"] = int(entry["count"]) + 1
			entry["timer"] = _lifetime_for(kind)
			_refresh_entry(entry)
			return
	while _entries.size() >= MAX_VISIBLE:
		_remove_entry(_entries[0])
	var node := _build(text, kind)
	_column.add_child(node)
	var entry: Dictionary = {"node": node, "timer": _lifetime_for(kind), "text": text,
		"count": 1, "label": node.get_node("body/label"), "kind": kind}
	_entries.append(entry)
	_refresh_entry(entry)
	if not UITokens_motion_reduced():
		node.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(node, "modulate:a", 1.0, UITokens.DUR_NORMAL)

func _lifetime_for(kind: String) -> float:
	return LIFETIME_ERROR if kind == "error" or kind == "warn" else LIFETIME

func _build(text: String, kind: String) -> Control:
	var panel := PanelContainer.new()
	var accent: Color = UITokens.TEAL
	var icon_id: String = "ok"
	match kind:
		"warn":
			accent = UITokens.AMBER
			icon_id = "warning"
		"error", "danger":
			accent = UITokens.RED
			icon_id = "danger"
		"success":
			accent = UITokens.GREEN
			icon_id = "ok"
	panel.add_theme_stylebox_override("panel", UIStyle.surface_box("raised", true))
	var sb: StyleBoxFlat = panel.get_theme_stylebox("panel")
	sb.border_color = accent
	var row := HBoxContainer.new()
	row.name = "body"
	row.add_theme_constant_override("separation", UITokens.SP_4)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = AssetRegistry.icon("status", icon_id)
	icon.custom_minimum_size = Vector2(UITokens.ICON_SM, UITokens.ICON_SM)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var l := UIStyle.label(text, false, UITokens.FONT_SMALL)
	l.name = "label"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", accent if kind == "error" else UITokens.TEXT)
	row.add_child(l)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel

func _refresh_entry(entry: Dictionary) -> void:
	var suffix: String = "" if int(entry["count"]) <= 1 else "  (×%d)" % int(entry["count"])
	entry["label"].text = str(entry["text"]) + suffix

func _remove_entry(entry: Dictionary) -> void:
	_entries.erase(entry)
	if is_instance_valid(entry["node"]):
		entry["node"].queue_free()

func _process(delta: float) -> void:
	var expired: Array = []
	for entry in _entries:
		entry["timer"] = float(entry["timer"]) - delta
		if float(entry["timer"]) <= 0.0:
			expired.append(entry)
	for entry in expired:
		_remove_entry(entry)

func clear() -> void:
	for entry in _entries.duplicate():
		_remove_entry(entry)

func UITokens_motion_reduced() -> bool:
	return bool(PlayerData.settings.get("reduced_motion", false))
