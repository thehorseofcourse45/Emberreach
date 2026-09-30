extends VBoxContainer
## PrayerPanel — activate and deactivate prayers.
##
## PrayerManager.toggle() was fully implemented (level gate, 2-prayer cap, modifier registration,
## point cost) with no caller anywhere in the UI, so a 120-level skill's entire unlock tree was
## unreachable. This panel is the missing entry point; the logic all lives in PrayerManager.
##
## Points come from burying bones in Storage and from settlement buildings, and are spent per
## player attack, so the cost line is the number that matters when choosing what to keep lit.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _list: VBoxContainer
var _summary: Label
var _filter: OptionButton
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Prayers", UITokens.FONT_DISPLAY))
	_summary = UIStyle.label("", true, UITokens.FONT_SMALL)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	add_child(UIStyle.label(
		"Up to %d prayers run at once. Each one costs prayer points on every attack you make; "
		% PrayerManager.MAX_ACTIVE + "bury bones in Storage or raise them in your settlement to earn more.",
		true, UITokens.FONT_SMALL))
	_filter = OptionButton.new()
	for label in ["All prayers", "Unlocked", "Active"]:
		_filter.add_item(label)
	_filter.item_selected.connect(func(_index): _rebuild())
	add_child(_filter)
	_list = UIStyle.vbox(UITokens.SP_4)
	add_child(_list)
	EventBus.prayer_activated.connect(func(_p): _rebuild())
	EventBus.prayer_deactivated.connect(func(_p): _rebuild())
	EventBus.skill_level_up.connect(func(_s, _l): _rebuild())
	EventBus.state_refreshed.connect(_rebuild)
	EventBus.prayer_points_changed.connect(func(_points): _update_summary())
	_rebuild()

func focus_route(_route: Dictionary) -> void:
	pass

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Prayers",
		"body": "Active prayers grant combat bonuses and drain points as you fight. Turn one off "
			+ "before you run out of points, or the manager deactivates all of them for you."}

func _update_summary() -> void:
	var level: int = PlayerData.get_level("prayer")
	var active: int = PlayerData.active_prayers.size()
	var cost: float = PrayerManager.cost_per_attack()
	_summary.text = "Prayer Lv %d · %d/%d active · %.1f points · %.2f per attack" % [
		level, active, PrayerManager.MAX_ACTIVE, PlayerData.prayer_points, cost]

func _rebuild() -> void:
	if not _built:
		return
	_update_summary()
	var level: int = PlayerData.get_level("prayer")
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var ids: Array = DataLoader.prayers.keys()
	ids.sort_custom(func(a, b):
		return int(DataLoader.prayers[a].get("level", 0)) < int(DataLoader.prayers[b].get("level", 0)))
	var any_shown: bool = false
	for id in ids:
		var p: Dictionary = DataLoader.prayers[id]
		if p.is_empty() or p.has("_comment"):
			continue
		var need: int = int(p.get("level", 1))
		if _filter.selected == 1 and need > level:
			continue
		if _filter.selected == 2 and not PrayerManager.is_active(str(id)):
			continue
		any_shown = true
		_list.add_child(_row(str(id), p, level))
	if not any_shown:
		_list.add_child(Widgets.empty_state("No prayers in this filter",
			"Choose All prayers to see every unlock, or activate an unlocked prayer."))

func _row(id: String, p: Dictionary, level: int) -> Control:
	var is_active: bool = PrayerManager.is_active(id)
	var card: PanelContainer = UIStyle.card(is_active)
	var row := UIStyle.hbox(UITokens.SP_4)
	card.add_child(row)
	row.add_child(UIStyle.icon_texture("prayers", id))
	var text := UIStyle.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_label := UIStyle.label(str(p.get("name", id)), false, UITokens.FONT_BODY)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(name_label)
	var effects := UIStyle.label(_benefit_text(p), true, UITokens.FONT_SMALL)
	effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(effects)
	var requirement := UIStyle.label("Lv %d · %.1f points per attack" % [
		int(p.get("level", 1)), float(p.get("prayer_point_cost", 0.0))], true, UITokens.FONT_SMALL)
	requirement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(requirement)
	var btn: Button = UIStyle.mini_button("Deactivate" if is_active else "Activate")
	if is_active:
		btn.pressed.connect(func(): PrayerManager.toggle(id))
	elif level < int(p.get("level", 1)):
		btn.text = "Locked"
		btn.disabled = true
		btn.tooltip_text = "Requires Prayer level %d" % int(p.get("level", 1))
	elif active_full():
		btn.disabled = true
		btn.tooltip_text = "Only %d prayers may be active" % PrayerManager.MAX_ACTIVE
	else:
		btn.pressed.connect(func(): PrayerManager.toggle(id))
	row.add_child(btn)
	return card

func active_full() -> bool:
	return PlayerData.active_prayers.size() >= PrayerManager.MAX_ACTIVE

func _benefit_text(prayer: Dictionary) -> String:
	if prayer.get("type", "") == "protect":
		return "Reduces incoming %s damage" % str(prayer.get("style", ""))
	if prayer.get("type", "") == "protect_item":
		return "Protects equipment on defeat"
	return _effect_text(prayer.get("effect", {}))

## Modifier effect dict -> one readable line, so the panel needs no per-prayer special-casing.
func _effect_text(effect: Dictionary) -> String:
	if effect.is_empty():
		return "no modifier"
	var parts: Array[String] = []
	for k in effect.keys():
		var v: float = float(effect[k])
		if k == "attack_interval_percent":
			parts.append("Attack interval -%.0f%%" % v)
			continue
		if k == "min_hit_percent_of_max":
			parts.append("Minimum hit %.0f%% of max" % v)
			continue
		parts.append("%s %s%.0f%%" % [str(k).replace("_percent", "").replace("_", " "),
			"+" if v >= 0.0 else "", v])
	return ", ".join(parts)
