extends VBoxContainer
## CollectionPanel — the collection log: what you have discovered, and what remains.
##
## Undiscovered entries stay visible as silhouettes so the player knows content EXISTS without
## being told its identity, keeping some mystery without hiding progress-critical information.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _tabs_box: HBoxContainer
var _list: VBoxContainer
var _summary: VBoxContainer
var _tab: String = "items"
var _search: LineEdit
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Collection log", UITokens.FONT_DISPLAY))
	_search = Widgets.search_bar("Filter…", func(_t): _rebuild_list(0), 260)
	add_child(_search)
	_tabs_box = UIStyle.hbox(UITokens.SP_3)
	add_child(_tabs_box)
	for entry in [["items", "Items"], ["monsters", "Enemies"], ["dungeons", "Expeditions"], ["pets", "Companions"]]:
		var b := UIStyle.mini_button(str(entry[1]))
		var key: String = str(entry[0])
		b.pressed.connect(func():
			_tab = key
			_rebuild())
		_tabs_box.add_child(b)
	_summary = UIStyle.vbox(UITokens.SP_2)
	add_child(_summary)
	_list = UIStyle.vbox(UITokens.SP_2)
	add_child(_list)
	EventBus.item_discovered.connect(func(_i): _rebuild())
	EventBus.monster_discovered.connect(func(_i): _rebuild())
	EventBus.dungeon_discovered.connect(func(_i): _rebuild())
	EventBus.pet_unlocked.connect(func(_i): _rebuild())
	EventBus.state_refreshed.connect(_rebuild)
	_rebuild()

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Collection log",
		"body": "Recorded on first acquisition or first defeat. Undiscovered entries are listed as unknown so you can see how much content remains."}

func _rebuild() -> void:
	_rebuild_summary()
	_rebuild_list(0)

func _rebuild_summary() -> void:
	for c in _summary.get_children():
		_summary.remove_child(c)
		c.queue_free()
	var log: Dictionary = PlayerData.completion_log
	_summary.add_child(_summary_row("Items", (log.get("items", {}) as Dictionary).size(), DataLoader.items.size(), UITokens.TEAL))
	_summary.add_child(_summary_row("Enemies", (log.get("monsters", {}) as Dictionary).size(), DataLoader.monsters.size(), UITokens.RED))
	_summary.add_child(_summary_row("Expeditions", (log.get("dungeons", {}) as Dictionary).size(), DataLoader.dungeons.size(), UITokens.BLUE))
	_summary.add_child(_summary_row("Companions", (log.get("pets", {}) as Dictionary).size(), DataLoader.pets.size(), UITokens.PURPLE))

func _summary_row(label: String, got: int, total: int, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_4)
	var l := UIStyle.label(label, true, UITokens.FONT_SMALL)
	l.custom_minimum_size = Vector2(120, 0)
	row.add_child(l)
	var bar := Widgets.progress_bar(float(got), float(maxi(total, 1)), color,
		"%d / %d" % [got, total], 12)
	bar.custom_minimum_size = Vector2(220, 12)
	row.add_child(bar)
	return row

func _rebuild_list(_depth: int) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var query: String = _search.text.to_lower().strip_edges()
	var shown: int = 0
	# Undiscovered entries are shown first so the next goal is obvious.
	var entries: Array = []
	for key in _keys_for(_tab):
		var discovered: bool = PlayerData.completion_log.get(_tab, {}).has(str(key))
		entries.append({"id": str(key), "discovered": discovered})
	entries.sort_custom(func(a, b): return bool(a["discovered"]) == false and bool(b["discovered"]) == true)
	for e in entries:
		var item_id: String = str(e["id"])
		var discovered: bool = bool(e["discovered"])
		var label: String = _display_name(item_id, discovered)
		if query != "" and not label.to_lower().contains(query):
			continue
		if shown >= 60:
			_list.add_child(UIStyle.label("…%d more (use the filter)" % (entries.size() - shown), true, UITokens.FONT_MICRO))
			break
		shown += 1
		var card := UIStyle.card(false)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITokens.SP_4)
		card.add_child(row)
		var icon := TextureRect.new()
		icon.texture = _icon_for(item_id)
		icon.custom_minimum_size = Vector2(UITokens.ICON_MD, UITokens.ICON_MD)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if not discovered:
			icon.modulate = Color(1, 1, 1, 0.25)
		row.add_child(icon)
		var col := UIStyle.vbox(UITokens.SP_1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := UIStyle.label(label, not discovered, UITokens.FONT_SMALL)
		col.add_child(name_label)
		col.add_child(UIStyle.label(_subtitle_for(item_id, discovered), true, UITokens.FONT_MICRO))
		row.add_child(col)
		if discovered:
			var explain := UIStyle.mini_button("Details")
			explain.pressed.connect(_explain_entry.bind(item_id, label))
			row.add_child(explain)
			if _tab == "items":
				var track := UIStyle.mini_button("Track")
				var iid2: String = item_id
				track.pressed.connect(func(): Goals.pin("item", iid2))
				row.add_child(track)
		_list.add_child(card)

## Push this entry into the detail pane, in the shape that matches the current tab.
func _explain_entry(item_id: String, label: String) -> void:
	if _tab == "items":
		context_changed.emit({"kind": "item", "item_id": item_id})
		return
	if _tab == "monsters":
		context_changed.emit({"kind": "region", "area_id": _area_for_monster(item_id)})
		return
	if _tab == "dungeons":
		context_changed.emit({"kind": "region", "area_id": item_id})
		return
	context_changed.emit({"kind": "text", "title": label,
		"body": "Companion unlocked. Its passive effect is registered while it is active."})

func _keys_for(tab: String) -> Array:
	match tab:
		"items": return DataLoader.items.keys()
		"monsters": return DataLoader.monsters.keys()
		"dungeons": return DataLoader.dungeons.keys()
		"pets": return DataLoader.pets.keys()
	return []

func _display_name(id: String, discovered: bool) -> String:
	if not discovered:
		return "Unknown"
	match _tab:
		"items": return str(DataLoader.get_item(id).get("name", id))
		"monsters": return str(DataLoader.get_monster(id).get("name", id))
		"dungeons": return str(DataLoader.get_dungeon(id).get("name", id))
		"pets": return str(DataLoader.pets.get(id, {}).get("name", id))
	return id

func _subtitle_for(id: String, discovered: bool) -> String:
	if not discovered:
		return "Not yet recorded"
	match _tab:
		"items":
			var item: Dictionary = DataLoader.get_item(id)
			return "%s · sells for %s GP" % [str(item.get("item_type", "")).capitalize(), UIStyle.fmt(float(item.get("sell_price", 0)))]
		"monsters":
			var m: Dictionary = DataLoader.get_monster(id)
			return "Level %d · %d HP · %s" % [int(m.get("combat_level", 1)), int(m.get("hitpoints", 0)), str(m.get("attack_type", ""))]
		"dungeons":
			var d: Dictionary = DataLoader.get_dungeon(id)
			return "%d encounters" % (d.get("monsters", []) as Array).size()
		"pets":
			var eff: Dictionary = DataLoader.pets.get(id, {}).get("effect", {})
			return UIStyle.describe_modifier_table(eff) if not eff.is_empty() else "Passive companion"
	return ""

func _icon_for(id: String) -> Texture2D:
	match _tab:
		"items": return AssetRegistry.item_icon(id)
		"monsters": return AssetRegistry.monster_sprite(id)
		"dungeons": return AssetRegistry.icon("dungeons", id)
		"pets": return AssetRegistry.icon("pets", id)
	return AssetRegistry.icon("status", "idle")

func _area_for_monster(monster_id: String) -> String:
	for area_id in DataLoader.areas.keys():
		if (DataLoader.areas[area_id].get("monsters", []) as Array).has(monster_id):
			return str(area_id)
	return ""
