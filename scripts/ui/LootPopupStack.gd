extends Control
class_name LootPopupStack
## Small, click-through item notifications at the bottom-right of the game.
## BankManager.item_obtained is the authoritative source for new items from
## skills, pickpocketing, combat, quests, shops and overflow. Transfers are quiet.

const MAX_VISIBLE: int = 4
const LIFETIME: float = 4.0
const MAX_WAITING: int = 32

var _column: VBoxContainer
var _entries: Array = []
var _waiting: Array = []
var _unshown_types: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -340
	offset_right = -12
	offset_top = -390
	offset_bottom = -64
	_column = UIStyle.vbox(UITokens.SP_2)
	_column.alignment = BoxContainer.ALIGNMENT_END
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	EventBus.item_obtained.connect(_on_item_obtained)
	EventBus.game_loaded.connect(clear)

func _on_item_obtained(item_id: String, quantity: int) -> void:
	if quantity <= 0 or item_id == "" or SimulationMode.is_silent():
		return
	if not bool(PlayerData.settings.get("show_item_popups", true)):
		return
	var context: String = "PICKPOCKETED" if SkillManager.running and SkillManager.active_skill == "thieving" else "ITEM RECEIVED"
	var in_overflow: bool = not BankManager.items.has(item_id) and BankManager.overflow.has(item_id)
	if in_overflow:
		context = "SENT TO OVERFLOW"
	# Merge repeated drops instead of spawning a new popup for every skill tick.
	for entry in _entries:
		if entry["id"] == item_id and entry["context"] == context:
			entry["quantity"] = int(entry["quantity"]) + quantity
			entry["timer"] = LIFETIME
			_update_entry(entry)
			return
	for entry in _waiting:
		if entry["id"] == item_id and entry["context"] == context:
			entry["quantity"] = int(entry["quantity"]) + quantity
			return
	if _waiting.size() >= MAX_WAITING:
		# An active ultra-fast action can outpace the four-slot feed. Keep the
		# popup bounded; the item itself is already safely in Storage.
		_unshown_types += 1
		return
	_waiting.append({"id": item_id, "quantity": quantity, "context": context})
	_pump()

func _pump() -> void:
	while _entries.size() < MAX_VISIBLE and not _waiting.is_empty():
		var entry: Dictionary = _waiting.pop_front()
		var built: Dictionary = _build(entry)
		entry["node"] = built["node"]
		entry["value"] = built["value"]
		entry["timer"] = LIFETIME
		_entries.append(entry)
		_column.add_child(entry["node"])
		_update_entry(entry)
		Motion.fade_rise(entry["node"])
	if _entries.size() < MAX_VISIBLE and _waiting.is_empty() and _unshown_types > 0:
		var n: int = _unshown_types
		_unshown_types = 0
		var more := {"id": "", "quantity": n, "context": "MORE ITEMS"}
		var built: Dictionary = _build(more)
		more["node"] = built["node"]
		more["value"] = built["value"]
		more["timer"] = LIFETIME
		_entries.append(more)
		_column.add_child(more["node"])
		_update_entry(more)

func _build(entry: Dictionary) -> Dictionary:
	var item_id: String = str(entry["id"])
	var rarity: Dictionary = UIStyle.item_rarity(item_id) if item_id != "" else {"color": UITokens.AMBER, "label": ""}
	var accent: Color = rarity["color"]
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 304
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = UIStyle.flat_box("overlay")
	style.border_color = accent
	style.set_border_width_all(2 if str(rarity["label"]) in ["Epic", "Legendary", "Relic"] else 1)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = AssetRegistry.item_icon(item_id) if item_id != "" else AssetRegistry.icon("status", "ok")
	icon.custom_minimum_size = Vector2(38, 38)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var labels := UIStyle.vbox(0)
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(labels)
	var headline := UIStyle.label(str(entry["context"]), true, UITokens.FONT_MICRO)
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	headline.add_theme_color_override("font_color", accent)
	labels.add_child(headline)
	var name: String = str(DataLoader.get_item(item_id).get("name", item_id)) if item_id != "" else "Open Storage to see the rest"
	var title := UIStyle.label(name, false, UITokens.FONT_SMALL)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(title)
	var value := UIStyle.label("", false, UITokens.FONT_BODY)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.add_theme_color_override("font_color", accent)
	row.add_child(value)
	return {"node": panel, "value": value}

func _update_entry(entry: Dictionary) -> void:
	if is_instance_valid(entry.get("value")):
		entry["value"].text = "×%d" % int(entry["quantity"])

func _process(delta: float) -> void:
	if not bool(PlayerData.settings.get("show_item_popups", true)):
		if not _entries.is_empty() or not _waiting.is_empty():
			clear()
		return
	var elapsed: float = delta / maxf(Engine.time_scale, 0.01)
	for entry in _entries.duplicate():
		entry["timer"] = float(entry["timer"]) - elapsed
		if float(entry["timer"]) <= 0.0:
			_entries.erase(entry)
			if is_instance_valid(entry["node"]):
				entry["node"].queue_free()
	_pump()

func clear() -> void:
	for entry in _entries:
		if is_instance_valid(entry["node"]):
			entry["node"].queue_free()
	_entries.clear()
	_waiting.clear()
	_unshown_types = 0
