extends AcceptDialog
class_name OfflineSummaryDialog
## OfflineSummaryDialog — everything that happened while the game was closed, read from the
## summary the simulation actually produced. Nothing here is estimated for display.
##
## It also refuses to present progress that did not happen: a clock anomaly or a disabled
## activity is stated plainly instead of being dressed up as gains.

var _content: VBoxContainer

func _ready() -> void:
	title = "While you were away"
	ok_button_text = "Continue"
	min_size = Vector2i(520, 0)
	dialog_autowrap = true
	var scroll := UIStyle.scroll()
	scroll.custom_minimum_size = Vector2(500, 380)
	add_child(scroll)
	_content = UIStyle.vbox(UITokens.SP_4)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	EventBus.offline_progress_summary.connect(show_summary)

func show_summary(summary: Dictionary) -> void:
	if summary.is_empty():
		return
	if float(summary.get("processed_seconds", 0.0)) <= 0.0 and not bool(summary.get("clock_anomaly", false)):
		return
	for c in _content.get_children():
		c.queue_free()

	_content.add_child(UIStyle.title("While you were away", UITokens.FONT_DISPLAY))
	var processed: float = float(summary.get("processed_seconds", 0.0))
	_content.add_child(Widgets.key_value("Time processed", UIStyle.fmt_duration(processed),
		UITokens.TEXT_STRONG))
	var capped: float = float(summary.get("capped_seconds", 0.0))
	if capped > 1.0:
		_content.add_child(Widgets.key_value("Excluded by your cap", UIStyle.fmt_duration(capped),
			UITokens.AMBER, "Your offline cap is %.0f hours (Settings → Offline)" % float(summary.get("cap_hours", 24.0))))
	if bool(summary.get("clock_anomaly", false)):
		_content.add_child(UIStyle.colored_label(
			"The system clock moved backwards. No progress was granted and the offline marker was left untouched.",
			UITokens.AMBER, UITokens.FONT_SMALL))

	var stopped: String = str(summary.get("stopped_reason", ""))
	if stopped != "":
		_content.add_child(Widgets.key_value("Progress stopped because", stopped, UITokens.AMBER))

	var activity: String = str(summary.get("activity", "none"))
	if activity == "skill":
		_content.add_child(Widgets.key_value("Activity",
			"%s · %s" % [DataLoader.get_skill(str(summary.get("skill", ""))).get("name", "?"),
				str(summary.get("action", ""))], UITokens.TEAL))
		_content.add_child(Widgets.key_value("Actions completed", UIStyle.fmt_exact(float(summary.get("actions", 0)))))
	elif activity == "combat":
		var combat: Dictionary = summary.get("combat", {})
		_content.add_child(Widgets.key_value("Activity", "Expedition", UITokens.RED))
		_content.add_child(Widgets.key_value("Victories", UIStyle.fmt_exact(float(combat.get("kills", 0)))))
		_content.add_child(Widgets.key_value("Defeats", UIStyle.fmt_exact(float(combat.get("deaths", 0))),
			UITokens.RED if int(combat.get("deaths", 0)) > 0 else UITokens.TEXT))
		if int(combat.get("dungeons", 0)) > 0:
			_content.add_child(Widgets.key_value("Expeditions cleared", UIStyle.fmt_exact(float(combat["dungeons"])), UITokens.GOLD))
	elif activity == "none":
		_content.add_child(UIStyle.colored_label("Nothing was running, so no resources were produced.",
			UITokens.TEXT_MUTED, UITokens.FONT_SMALL))

	var dreaming: Dictionary = summary.get("dreamwalking", {})
	if float(dreaming.get("seconds", 0.0)) > 0:
		_content.add_child(Widgets.key_value("Dreamwalking", "%s · %d Essence" % [UIStyle.fmt_duration(float(dreaming.seconds)), int(dreaming.essence)], UITokens.TEAL))
		if int(dreaming.get("nightmare_loss", 0)) > 0:
			_content.add_child(UIStyle.label("A nightmare cost %d session Essence." % int(dreaming.nightmare_loss), true, UITokens.FONT_SMALL))
	preload("res://scripts/ui/panels/NewSkillSystems.gd").build_events(_content)
	var levels: Dictionary = summary.get("levels_gained", {})
	if not levels.is_empty():
		_content.add_child(UIStyle.section("Levels gained"))
		for skill_id in levels.keys():
			_content.add_child(Widgets.key_value(str(DataLoader.get_skill(str(skill_id)).get("name", skill_id)),
				"+%d levels" % int(levels[skill_id]), UITokens.GOLD_BRIGHT))

	var xp: Dictionary = summary.get("xp_gained", {})
	if not xp.is_empty():
		_content.add_child(UIStyle.section("Experience"))
		for skill_id in xp.keys():
			var before: int = PlayerData.get_level(str(skill_id))
			_content.add_child(Widgets.key_value(str(DataLoader.get_skill(str(skill_id)).get("name", skill_id)),
				"%s XP  ·  now level %d" % [UIStyle.fmt(float(xp[skill_id])), before]))

	_add_item_table("Items obtained", summary.get("items_gained", {}), UITokens.TEAL)
	_add_item_table("Materials consumed", summary.get("items_consumed", {}), UITokens.TEXT_MUTED)

	var rare: Dictionary = summary.get("rare_drops", {})
	if not rare.is_empty():
		_content.add_child(UIStyle.section("Rare finds"))
		for item_id in rare.keys():
			_content.add_child(Widgets.item_row(str(item_id), int(rare[item_id]),
				"Track", func(): Goals.pin("item", str(item_id))))

	var pets: Array = summary.get("pets", [])
	if not pets.is_empty():
		_content.add_child(UIStyle.section("New companions"))
		for pet_id in pets:
			_content.add_child(UIStyle.colored_label(str(DataLoader.pets.get(str(pet_id), {}).get("name", pet_id)),
				UITokens.GOLD_BRIGHT, UITokens.FONT_SMALL))

	if int(summary.get("farming_advanced", 0)) > 0:
		_content.add_child(Widgets.key_value("Crops ready", str(int(summary["farming_advanced"])), UITokens.TEAL))
	if int(summary.get("township_ticks", 0)) > 0:
		_content.add_child(Widgets.key_value("Settlement production ticks", str(int(summary["township_ticks"])), UITokens.TEAL))

	_content.add_child(UIStyle.colored_label(
		"Offline progress uses the same simulation, the same costs and the same stop conditions as playing.",
		UITokens.TEXT_DIM, UITokens.FONT_MICRO))
	popup_centered()
	get_ok_button().grab_focus()

func _add_item_table(heading: String, table: Dictionary, _color: Color) -> void:
	if table.is_empty():
		return
	_content.add_child(UIStyle.section(heading))
	var keys: Array = table.keys()
	keys.sort_custom(func(a, b): return float(table[a]) > float(table[b]))
	var shown: int = 0
	for item_id in keys:
		if shown >= 14:
			_content.add_child(UIStyle.label("…and %d more" % (keys.size() - shown), true, UITokens.FONT_MICRO))
			break
		_content.add_child(Widgets.item_row(str(item_id), int(table[item_id])))
		shown += 1
