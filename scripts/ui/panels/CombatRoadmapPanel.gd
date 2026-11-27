extends VBoxContainer
## Recommendations use completion and the actual entry gates, not enemy/player level comparisons.
signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

const TYPES: Array[String] = ["Regions", "Dungeons", "Expeditions", "Strongholds", "Raids"]
var _body: VBoxContainer
var _filter: OptionButton

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_4)
	add_child(UIStyle.title("Combat progression roadmap", UITokens.FONT_DISPLAY))
	_paragraph(self, "Explore the next encounters in each path. Recommendations follow your recorded completions and entry requirements; they are not a guarantee of survival.")
	_filter = Widgets.option_menu(["All paths"] + TYPES, func(_i): refresh(), 0)
	add_child(_filter)
	_body = UIStyle.vbox(UITokens.SP_4)
	add_child(_body)
	EventBus.state_refreshed.connect(refresh)
	refresh()

func focus_route(_route: Dictionary) -> void:
	refresh()

func detail_context() -> Dictionary:
	return {"kind":"text", "title":"Combat roadmap", "body":"Suggestions use recorded completions and actual entry requirements. Inspect enemies and test your equipment before a run."}

func _paragraph(parent: Node, text: String) -> void:
	var label := UIStyle.label(text, true, UITokens.FONT_SMALL)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func _button(parent: Node, text: String, action: Callable) -> void:
	var button := UIStyle.mini_button(text)
	button.pressed.connect(action)
	parent.add_child(button)

func _path_for(id: String) -> String:
	var d: Dictionary = DataLoader.get_dungeon(id)
	if bool(d.get("raid", false)): return "Raids"
	if bool(d.get("stronghold", false)): return "Strongholds"
	return "Expeditions" if CombatManager.is_expedition(id) else "Dungeons"

func _records(kind: String) -> Array:
	var out: Array = []
	if kind == "Regions":
		for key in DataLoader.areas:
			var area: Dictionary = DataLoader.areas[key]
			if str(area.get("type", "area")) == "slayer_area": continue
			var monsters: Array = area.get("monsters", [])
			var defeated: int = 0
			for monster in monsters:
				if PlayerData.completion_log.get("monsters", {}).has(str(monster)): defeated += 1
			out.append(_record(str(key), area, kind, not monsters.is_empty() and defeated == monsters.size(), "", defeated, monsters.size()))
	else:
		for key in DataLoader.dungeons:
			var id: String = str(key)
			if _path_for(id) != kind: continue
			var d: Dictionary = DataLoader.get_dungeon(id)
			var reason: String = CombatManager.expedition_unlock_reason() if CombatManager.is_expedition(id) else ""
			if reason == "": reason = CombatManager.dungeon_lock_reason(id)
			var cleared: bool = PlayerData.completion_log.get("dungeons", {}).has(id)
			out.append(_record(id, d, kind, cleared, reason, 0, 0))
	out.sort_custom(func(a, b):
		if int(a.min_level) == int(b.min_level): return str(a.name) < str(b.name)
		return int(a.min_level) < int(b.min_level))
	return out

func _record(id: String, data: Dictionary, kind: String, done: bool, reason: String, defeated: int, total: int) -> Dictionary:
	var levels: Array = data.get("level_range", [0, 0])
	return {"id": id, "name": str(data.get("name", id)), "kind": kind, "data": data,
		"done": done, "reason": reason, "min_level": int(levels[0]) if levels.size() > 0 else 0,
		"max_level": int(levels[-1]) if levels.size() > 0 else 0, "defeated": defeated, "total": total}

## The first available incomplete encounter and the first locked incomplete encounter are
## deliberately separate: an unmet prerequisite is not presented as something you can enter.
func _suggestions(kind: String) -> Array:
	var available: Array = []
	var locked: Array = []
	for record in _records(kind):
		if record.done: continue
		if str(record.reason) == "": available.append(record)
		else: locked.append(record)
	var result: Array = []
	if not available.is_empty(): result.append(available[0])
	if not locked.is_empty(): result.append(locked[0])
	return result

func refresh() -> void:
	if _body == null or Widgets.defer_offscreen_rebuild(self, refresh): return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var prep := UIStyle.section("Before you fight", "Use your current equipment and supplies to judge readiness.")
	_body.add_child(prep)
	var weapon_id: String = EquipmentManager.get_equipped(8)
	var weapon: String = str(DataLoader.get_item(weapon_id).get("name", weapon_id)) if weapon_id != "" else "none equipped"
	_paragraph(prep, "Current weapon: %s. Bring food, check enemy attack styles and maximum hits, and review run restrictions. Enemy levels use a separate scale from player skills." % weapon)
	var buttons := HFlowContainer.new()
	prep.add_child(buttons)
	_button(buttons, "Equipment", func(): navigated.emit({"screen": Screens.EQUIPMENT}))
	_button(buttons, "Equipment guide", func(): navigated.emit({"screen": Screens.EQUIPMENT_GUIDE}))
	_button(buttons, "Combat simulator", func(): navigated.emit({"screen": Screens.COMBAT_SIMULATOR}))
	var chosen: Array = TYPES if _filter.selected == 0 else [TYPES[_filter.selected - 1]]
	for kind in chosen: _show_path(str(kind))

func _show_path(kind: String) -> void:
	var records := _records(kind)
	var completed := 0
	for record in records:
		if record.done: completed += 1
	var section := UIStyle.section(kind, ("Enemy checklists" if kind == "Regions" else "First clears") + ": %d / %d" % [completed, records.size()])
	_body.add_child(section)
	if kind == "Regions": _paragraph(section, "A checklist counts enemies defeated anywhere, including shared enemies; it is not proof of a region clear.")
	var picks := _suggestions(kind)
	if picks.is_empty():
		_paragraph(section, "No unfinished encounters found in this path.")
		return
	for record in picks: _show_encounter(section, record)

func _show_encounter(parent: Node, record: Dictionary) -> void:
	var card := UIStyle.card()
	parent.add_child(card)
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var icon := UIStyle.icon_texture("areas" if record.kind == "Regions" else "dungeons", str(record.id))
	icon.custom_minimum_size = Vector2(48, 48)
	head.add_child(icon)
	var title := UIStyle.title(str(record.name), UITokens.FONT_SUBHEAD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(title)
	var reason: String = str(record.reason)
	_paragraph(col, ("Available to enter" if reason == "" else "Locked: " + reason) + " · Enemy levels %s–%s" % [UIStyle.fmt_exact(float(record.min_level)), UIStyle.fmt_exact(float(record.max_level))])
	if record.kind == "Regions": _paragraph(col, "Known enemy defeats: %d / %d" % [record.defeated, record.total])
	var data: Dictionary = record.data
	var types: Array[String] = []
	for mid in data.get("monsters", []):
		var attack: String = str(DataLoader.get_monster(str(mid)).get("attack_type", ""))
		if attack != "" and not types.has(attack): types.append(attack)
	if not types.is_empty(): _paragraph(col, "Enemy attack styles: " + ", ".join(types) + ". Check defences and food for these encounters.")
	if bool(data.get("equipment_locked", false)): _paragraph(col, "Equipment is locked during this run. Prepare your loadout before entering.")
	var prerequisite: String = str(data.get("requires_dungeon", ""))
	if prerequisite != "" and PlayerData.completion_log.get("dungeons", {}).has(prerequisite):
		var previous: Dictionary = DataLoader.get_dungeon(prerequisite)
		var previous_items: Dictionary = previous.get("rewards_first_clear", {}).get("items", {})
		var previous_gear: Array[String] = []
		for item_id in previous_items:
			var item: Dictionary = DataLoader.get_item(str(item_id))
			if str(item.get("item_type", "")) == "equipment": previous_gear.append(str(item.get("name", item_id)))
		if not previous_gear.is_empty(): _paragraph(col, "Gear from the required previous clear to consider: " + ", ".join(previous_gear) + ". Compare its bonuses and requirements with your loadout.")
	var rewards: Dictionary = data.get("rewards_first_clear", {}).get("items", {})
	var gear: Array[String] = []
	for item_id in rewards:
		var item: Dictionary = DataLoader.get_item(str(item_id))
		if str(item.get("item_type", "")) == "equipment": gear.append(str(item.get("name", item_id)))
	if not gear.is_empty(): _paragraph(col, "First-clear equipment to work toward: " + ", ".join(gear) + ".")
	var route := {"screen": Screens.COMBAT, "area_id": str(record.id)}
	_button(col, "View encounter and requirements", func(): navigated.emit(route))
