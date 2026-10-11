extends VBoxContainer
## Shared live mastery readout for recipes and system-managed activities.
var skill_id := ""
var action_id := ""
var _xp := -1.0
var _challenge_seconds := -1.0
var _caption: Label
var _bar: ProgressBar
func configure(skill: String, action: String) -> void:
	skill_id = skill
	action_id = action
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", UITokens.SP_1)
	_caption = UIStyle.label("", true, UITokens.FONT_MICRO)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	_bar = Widgets.meter(0.0, 1.0, "xp", "", 6, false)
	add_child(_bar)
	_refresh()
func _process(_delta: float) -> void:
	_refresh()
func _refresh() -> void:
	var xp: float = MasteryManager.get_xp(skill_id, action_id)
	var challenge: Dictionary = MasteryManager.challenge(skill_id, action_id)
	if xp == _xp and float(challenge.seconds) == _challenge_seconds:
		return
	_challenge_seconds = float(challenge.seconds)
	_xp = xp
	var level: int = MasteryManager.get_level(skill_id, action_id)
	_caption.text = "Mastery · %d / %d%s" % [level, XPTable.MAX_LEVEL, " · Complete" if level == XPTable.MAX_LEVEL else ""]
	_bar.value = XPTable.level_progress(xp, level)
	tooltip_text = "Mastery XP: %s\n%s\nActivity bonuses: %s" % [UIStyle.fmt_exact(xp), "Maximum mastery reached" if level == XPTable.MAX_LEVEL else "%s XP to level %d" % [UIStyle.fmt_exact(XPTable.xp_to_next_level(xp, level)), level + 1], UIStyle.describe_modifier_table(MasteryManager.item_effects(skill_id, action_id))]
	_caption.tooltip_text = tooltip_text
	_bar.tooltip_text = tooltip_text
	if bool(challenge.unlocked):
		_caption.text += " · Challenge claimed" if challenge.claimed else " · Challenge %s / 6h" % UIStyle.fmt_duration(float(challenge.seconds))
