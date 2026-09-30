extends VBoxContainer
## AchievementsPanel — milestones grouped by category, with live progress and manual claiming.
##
## Rewards are deliberately modest so nothing here becomes mandatory. Conditions are re-evaluated
## against persisted state, so a milestone earned before this screen existed (or while offline)
## shows up as complete and waits here to be claimed — nothing is paid out automatically.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _list: VBoxContainer
var _summary: Label
var _claim_row: HBoxContainer
var _claim_all_button: Button
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Milestones", UITokens.FONT_DISPLAY))
	_summary = UIStyle.label("", true, UITokens.FONT_SMALL)
	add_child(_summary)
	add_child(UIStyle.label(
		"Rewards are intentionally small — a little gold, some XP, and a bundle of supplies. Once a condition is met, claim the reward here. Progress is measured from your lifetime record.",
		true, UITokens.FONT_SMALL))
	_claim_row = HBoxContainer.new()
	_claim_row.add_theme_constant_override("separation", UITokens.SP_4)
	_claim_all_button = UIStyle.primary_button("Claim all ready")
	_claim_all_button.tooltip_text = "Collect every completed milestone reward in one go"
	_claim_all_button.pressed.connect(func(): _claim_all())
	_claim_row.add_child(_claim_all_button)
	_claim_row.visible = false
	add_child(_claim_row)
	_list = UIStyle.vbox(UITokens.SP_4)
	add_child(_list)
	EventBus.achievement_unlocked.connect(func(_a): _rebuild())
	EventBus.achievement_reward_claimed.connect(func(_a): _rebuild())
	EventBus.state_refreshed.connect(_rebuild)
	EventBus.bank_changed.connect(_rebuild)
	_rebuild()

func _claim_all() -> void:
	Achievements.claim_all()
	_rebuild()

func focus_route(_route: Dictionary) -> void:
	pass

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Milestones",
		"body": "Categories cover progression, gathering, crafting, combat, discovery, collection and a few optional challenges."}

func _rebuild() -> void:
	if not _built:
		return
	var claimed: int = Achievements.claimed_count()
	var ready: int = Achievements.ready_count()
	_summary.text = "%d of %d claimed" % [claimed, Achievements.count()]
	if ready > 0:
		_summary.text += "  —  %d ready to claim" % ready
	_claim_row.visible = ready > 0
	_claim_all_button.text = "Claim all ready (%d)" % ready
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
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
	var completed: bool = bool(progress.get("completed", false))
	var claimed: bool = bool(progress.get("claimed", false))
	var ready: bool = completed and not claimed
	var card := UIStyle.card(ready)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_4)
	card.add_child(row)
	var mark := Label.new()
	mark.text = "★" if completed else "☆"
	mark.add_theme_font_size_override("font_size", UITokens.FONT_HEAD)
	mark.add_theme_color_override("font_color", UITokens.GOLD_BRIGHT if completed else UITokens.TEXT_DIM)
	mark.custom_minimum_size = Vector2(22, 0)
	row.add_child(mark)
	var col := UIStyle.vbox(UITokens.SP_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := UIStyle.label(str(rec.get("name", id)), false, UITokens.FONT_BODY)
	if not completed:
		name_label.add_theme_color_override("font_color", UITokens.TEXT_MUTED)
	col.add_child(name_label)
	var desc := UIStyle.label(str(rec.get("description", "")), true, UITokens.FONT_MICRO)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	col.add_child(Widgets.progress_bar(float(progress.get("current", 0)), maxf(1.0, float(progress.get("required", 1))),
		UITokens.GREEN if claimed else (UITokens.GOLD_BRIGHT if ready else UITokens.BLUE),
		"%s / %s" % [UIStyle.fmt(float(progress.get("current", 0))), UIStyle.fmt(float(progress.get("required", 1)))], 10,
		str(progress.get("description", ""))))
	row.add_child(col)
	# The reward line wraps: with item supplies in every reward it can get long, and it must
	# never set the panel's minimum width at the narrowest supported window.
	var reward := UIStyle.colored_label(Achievements.describe_reward(id),
		UITokens.GOLD_BRIGHT if ready else UITokens.TEXT_MUTED, UITokens.FONT_MICRO)
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(reward)
	if ready:
		var claim := UIStyle.primary_button("Claim reward")
		claim.tooltip_text = "Collect this milestone's reward"
		claim.pressed.connect(func():
			Achievements.claim(id)
			_rebuild())
		row.add_child(claim)
	elif claimed:
		row.add_child(Widgets.badge("Claimed", UITokens.GREEN,
			"Claimed at %s" % Time.get_datetime_string_from_unix_time(Achievements.claimed_at(id)) if Achievements.claimed_at(id) > 0 else "Claimed"))
	return card
