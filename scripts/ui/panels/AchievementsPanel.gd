extends VBoxContainer
## AchievementsPanel — milestones grouped by category, with live progress on each condition.
##
## Rewards are deliberately modest so nothing here becomes mandatory. Conditions are re-evaluated
## against persisted state, so a milestone earned before this screen existed (or while offline)
## is collected automatically on the next evaluation.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _list: VBoxContainer
var _summary: Label
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Milestones", UITokens.FONT_DISPLAY))
	_summary = UIStyle.label("", true, UITokens.FONT_SMALL)
	add_child(_summary)
	add_child(UIStyle.label(
		"Rewards are intentionally small — these are recognition, not a grind. Progress is measured from your lifetime record.",
		true, UITokens.FONT_SMALL))
	_list = UIStyle.vbox(UITokens.SP_4)
	add_child(_list)
	EventBus.achievement_unlocked.connect(func(_a): _rebuild())
	EventBus.state_refreshed.connect(_rebuild)
	EventBus.bank_changed.connect(_rebuild)
	_rebuild()

func focus_route(_route: Dictionary) -> void:
	pass

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Milestones",
		"body": "Categories cover progression, gathering, crafting, combat, discovery, collection and a few optional challenges."}

func _rebuild() -> void:
	if not _built:
		return
	_summary.text = "%d of %d unlocked" % [Achievements.unlocked_count(), Achievements.count()]
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var used_categories: Array[String] = ["optional"]
	var categories: Array[String] = Achievements.categories()
	categories.sort_custom(func(a, b): return a < b)
	for category in categories:
		var header := UIStyle.section(str(category).capitalize(), _category_hint(str(category)))
		var any: bool = false
		for id in Achievements.all_ids():
			var rec: Dictionary = Achievements.get_record(id)
			if str(rec.get("category", "general")) != category:
				continue
			any = true
			header.add_child(_row(id, rec))
		if any:
			_list.add_child(header)

func _category_hint(category: String) -> String:
	match category:
		"progression": return "levels and settlement growth"
		"gathering": return "resources brought home"
		"crafting": return "work completed at a station"
		"combat": return "enemies and expeditions"
		"discovery": return "companions and the collection log"
		"collection": return "holding and earning"
		"optional": return "optional challenges — deliberately modest"
	return ""

func _row(id: String, rec: Dictionary) -> Control:
	var progress: Dictionary = Achievements.progress(id)
	var unlocked: bool = bool(progress.get("unlocked", false))
	var card := UIStyle.card(unlocked)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_4)
	card.add_child(row)
	var mark := Label.new()
	mark.text = "★" if unlocked else "☆"
	mark.add_theme_font_size_override("font_size", UITokens.FONT_HEAD)
	mark.add_theme_color_override("font_color", UITokens.GOLD_BRIGHT if unlocked else UITokens.TEXT_DIM)
	mark.custom_minimum_size = Vector2(22, 0)
	row.add_child(mark)
	var col := UIStyle.vbox(UITokens.SP_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := UIStyle.label(str(rec.get("name", id)), false, UITokens.FONT_BODY)
	if not unlocked:
		name_label.add_theme_color_override("font_color", UITokens.TEXT_MUTED)
	col.add_child(name_label)
	var desc := UIStyle.label(str(rec.get("description", "")), true, UITokens.FONT_MICRO)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	col.add_child(Widgets.progress_bar(float(progress.get("current", 0)), maxf(1.0, float(progress.get("required", 1))),
		UITokens.GOLD_BRIGHT if unlocked else UITokens.BLUE,
		"%s / %s" % [UIStyle.fmt(float(progress.get("current", 0))), UIStyle.fmt(float(progress.get("required", 1)))], 10,
		str(progress.get("description", ""))))
	row.add_child(col)
	row.add_child(UIStyle.colored_label(Achievements.describe_reward(id),
		UITokens.TEXT_MUTED if not unlocked else UITokens.GOLD_BRIGHT, UITokens.FONT_MICRO))
	if unlocked:
		row.add_child(Widgets.badge("Unlocked", UITokens.GREEN,
			"Unlocked at %s" % Time.get_datetime_string_from_unix_time(Achievements.unlocked_at(id)) if Achievements.unlocked_at(id) > 0 else "Unlocked"))
	return card
