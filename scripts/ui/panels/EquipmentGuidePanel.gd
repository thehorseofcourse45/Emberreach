extends VBoxContainer
## A shortlist based on explicit stats; exact differences and other effects stay visible.
signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

const STYLES: Array[String] = ["Melee", "Ranged", "Magic"]
const SLOTS: Array[int] = [8, 0, 1, 2, 3, 4, 9, 5, 6, 7]
const MELEE_KEYS: Array[String] = ["stab", "slash", "block", "melee_strength"]
const RANGED_KEYS: Array[String] = ["ranged_attack", "ranged_strength"]
const MAGIC_KEYS: Array[String] = ["magic_attack", "magic_damage_percent"]
const PAGE_SIZE := 4
var _style: OptionButton
var _slot: OptionButton
var _body: VBoxContainer
var _page := 0

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_4)
	add_child(UIStyle.title("Equipment progression guide", UITokens.FONT_DISPLAY))
	_paragraph(self, "Choose a combat style and slot. The shortlist uses a weighted score for style bonuses, defences and damage reduction. Compare the individual stats, speed, requirements and effects before deciding.")
	var controls := HFlowContainer.new()
	controls.add_theme_constant_override("h_separation", UITokens.SP_3)
	controls.add_theme_constant_override("v_separation", UITokens.SP_2)
	add_child(controls)
	_style = Widgets.option_menu(STYLES, func(_i): _page = 0; refresh(), 0)
	_style.tooltip_text = "Combat style"
	controls.add_child(_style)
	var names: Array[String] = []
	for slot in SLOTS: names.append(ItemData.slot_name(slot))
	_slot = Widgets.option_menu(names, func(_i): _page = 0; refresh(), 0)
	_slot.tooltip_text = "Equipment slot"
	controls.add_child(_slot)
	_body = UIStyle.vbox(UITokens.SP_4)
	add_child(_body)
	EventBus.state_refreshed.connect(refresh)
	EventBus.item_equipped.connect(func(_s, _i): Widgets.rebuild_once_per_frame(refresh))
	EventBus.item_unequipped.connect(func(_s, _i): Widgets.rebuild_once_per_frame(refresh))
	refresh()

func focus_route(_route: Dictionary) -> void:
	refresh()

func detail_context() -> Dictionary:
	return {"kind":"text", "title":"Equipment guide", "body":"Compare a shortlist of equipment, then inspect sources and requirements. Item effects and combat situations may change which item is best."}

func _paragraph(parent: Node, text: String) -> void:
	var label := UIStyle.label(text, true, UITokens.FONT_SMALL)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func _button(parent: Node, text: String, action: Callable) -> void:
	var button := UIStyle.mini_button(text)
	button.pressed.connect(action)
	parent.add_child(button)

func _style_keys(style: String) -> Array[String]:
	match style:
		"Ranged": return RANGED_KEYS
		"Magic": return MAGIC_KEYS
	return MELEE_KEYS

func _score(item: Dictionary, style: String, slot: int) -> float:
	var stats: Dictionary = item.get("equipment_stats", {})
	var offensive: float = 0.0
	if style == "Melee":
		offensive = maxf(float(stats.get("stab", 0.0)), maxf(float(stats.get("slash", 0.0)), float(stats.get("block", 0.0)))) + float(stats.get("melee_strength", 0.0))
	else:
		for key in _style_keys(style): offensive += float(stats.get(key, 0.0))
	# Exclude weapons that offer no bonuses for the chosen style.
	if slot == ItemData.EquipmentSlot.WEAPON and offensive <= 0.0: return -1.0
	var defence: float = 0.0
	for key in ["melee_defence", "ranged_defence", "magic_defence"]: defence += float(stats.get(key, 0.0))
	return offensive + defence + 10.0 * float(stats.get("damage_reduction", 0.0))

func _suggestions(style: String, slot: int) -> Array:
	var current_id: String = EquipmentManager.get_equipped(slot)
	var current_score: float = maxf(0.0, _score(DataLoader.get_item(current_id), style, slot))
	var out: Array = []
	for id in DataLoader.items:
		var item: Dictionary = DataLoader.items[id]
		if str(item.get("item_type", "")) != "equipment" or int(item.get("equipment_slot", -1)) != slot: continue
		if str(id) == current_id or item.has("crafted_quality") or str(id).begins_with("enchanted__"): continue
		var score: float = _score(item, style, slot)
		if score <= current_score: continue
		out.append({"id": str(id), "score": score})
	out.sort_custom(func(a, b):
		if is_equal_approx(float(a.score), float(b.score)): return str(a.id) < str(b.id)
		return float(a.score) < float(b.score))
	return out

func refresh() -> void:
	if _body == null or Widgets.defer_offscreen_rebuild(self, refresh): return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var style: String = STYLES[_style.selected]
	var slot: int = SLOTS[_slot.selected]
	var current_id: String = EquipmentManager.get_equipped(slot)
	var current: Dictionary = DataLoader.get_item(current_id)
	var heading := UIStyle.section("Currently equipped", ItemData.slot_name(slot))
	_body.add_child(heading)
	_paragraph(heading, str(current.get("name", "Empty slot")))
	var candidates := _suggestions(style, slot)
	if candidates.is_empty():
		_paragraph(_body, "No higher-scoring standard items found for this style and slot. Items with unusual effects may still be useful; inspect the Equipment and Reference screens.")
		return
	var pages: int = maxi(1, ceili(float(candidates.size()) / PAGE_SIZE))
	_page = clampi(_page, 0, pages - 1)
	_paragraph(_body, "%d candidates · page %d of %d" % [candidates.size(), _page + 1, pages])
	var paging := HFlowContainer.new()
	_body.add_child(paging)
	var previous := UIStyle.mini_button("Previous upgrades")
	previous.disabled = _page == 0
	previous.pressed.connect(func(): _page -= 1; refresh())
	paging.add_child(previous)
	var next := UIStyle.mini_button("Later upgrades")
	next.disabled = _page + 1 >= pages
	next.pressed.connect(func(): _page += 1; refresh())
	paging.add_child(next)
	for candidate in candidates.slice(_page * PAGE_SIZE, mini(candidates.size(), (_page + 1) * PAGE_SIZE)):
		_add_candidate(str(candidate.id), current_id)

func _add_candidate(id: String, current_id: String) -> void:
	var item: Dictionary = DataLoader.get_item(id)
	var current: Dictionary = DataLoader.get_item(current_id)
	var card := UIStyle.card()
	_body.add_child(card)
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var icon := UIStyle.icon_texture("items", id)
	icon.custom_minimum_size = Vector2(40, 40)
	head.add_child(icon)
	var title := UIStyle.title(str(item.get("name", id)), UITokens.FONT_SUBHEAD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(title)
	_paragraph(col, "In Storage: %d · %s" % [BankManager.get_count(id), "Requirements met" if EquipmentManager._meets_requirements(item) else "Requirements not met"])
	var reqs: Dictionary = item.get("level_requirements", {}).duplicate()
	var extra: Dictionary = item.get("requires_level", {})
	if not extra.is_empty(): reqs[str(extra.get("skill", ""))] = int(extra.get("level", 0))
	for skill in reqs:
		_paragraph(col, "%s: %d / %d" % [str(DataLoader.get_skill(str(skill)).get("name", skill)), PlayerData.get_level(str(skill)), int(reqs[skill])])
	var before: Dictionary = current.get("equipment_stats", {})
	var after: Dictionary = item.get("equipment_stats", {})
	var keys: Array = before.keys()
	for key in after:
		if not keys.has(key): keys.append(key)
	keys.sort()
	_paragraph(col, "Stat comparison: equipped → this item (change)")
	for key in keys:
		var old: float = float(before.get(key, 0))
		var next: float = float(after.get(key, 0))
		_paragraph(col, "%s: %s → %s (%+.1f)" % [str(key).replace("_", " ").capitalize(), str(old), str(next), next - old])
	if item.has("attack_speed") or current.has("attack_speed"):
		_paragraph(col, "Attack interval: %s → %s seconds (lower is faster)" % [str(current.get("attack_speed", "—")), str(item.get("attack_speed", "—"))])
	if bool(item.get("is_two_handed", false)): _paragraph(col, "Two-handed: equipping this returns your shield to Storage.")
	if slot_is_shield(item) and bool(DataLoader.get_item(EquipmentManager.get_equipped(ItemData.EquipmentSlot.WEAPON)).get("is_two_handed", false)):
		_paragraph(col, "Equipping this shield returns your two-handed weapon to Storage.")
	if not (current.get("passive_modifiers", {}) as Dictionary).is_empty(): _paragraph(col, "Equipped passive: " + UIStyle.describe_modifier_table(current.passive_modifiers))
	if not (item.get("passive_modifiers", {}) as Dictionary).is_empty(): _paragraph(col, "This item's passive: " + UIStyle.describe_modifier_table(item.passive_modifiers))
	if str(current.get("special_attack", "")) != "": _paragraph(col, "Equipped special: " + str(DataLoader.get_special_attack(str(current.special_attack)).get("name", current.special_attack)))
	if str(item.get("special_attack", "")) != "": _paragraph(col, "This item's special: " + str(DataLoader.get_special_attack(str(item.special_attack)).get("name", item.special_attack)))
	if item.has("spell_max_hit") or current.has("spell_max_hit"): _paragraph(col, "Spell maximum hit: %s → %s" % [str(current.get("spell_max_hit", "—")), str(item.get("spell_max_hit", "—"))])
	if not (item.get("attack_cost_items", {}) as Dictionary).is_empty(): _paragraph(col, "Attack supplies: " + Goals._input_summary(item.attack_cost_items))
	var sources: Array = Goals.sources_for_item(id)
	if sources.is_empty():
		_paragraph(col, "No known acquisition source is listed. Inspect the item for details.")
	else:
		_paragraph(col, "Where to get it")
		for source in sources.slice(0, 3):
			var label: String = str(source.get("label", "Source"))
			var detail: String = str(source.get("detail", ""))
			_paragraph(col, label + (" — " + detail if detail != "" else ""))
			var route: Dictionary = source.get("route", {})
			var skill_id: String = str(route.get("skill_id", ""))
			var action_id: String = str(route.get("action_id", ""))
			if skill_id != "" and action_id != "":
				var action: Dictionary = DataLoader.get_action(skill_id, action_id)
				if not action.is_empty():
					var level: int = int(action.get("level_required", 1))
					_paragraph(col, "Requires %s %d (you: %d)" % [str(DataLoader.get_skill(skill_id).get("name", skill_id)), level, PlayerData.get_level(skill_id)])
					for material in action.get("input_items", {}):
						_paragraph(col, "%s: %d / %d" % [str(DataLoader.get_item(str(material)).get("name", material)), BankManager.get_count(str(material)), int(action.input_items[material])])
			if not route.is_empty(): _button(col, "Open source", func(): navigated.emit(route))
		if sources.size() > 3: _paragraph(col, "More sources are available in item details.")
	_button(col, "Inspect item and all sources", func(): context_changed.emit({"kind":"item", "item_id":id}))

func slot_is_shield(item: Dictionary) -> bool:
	return int(item.get("equipment_slot", -1)) == ItemData.EquipmentSlot.SHIELD
