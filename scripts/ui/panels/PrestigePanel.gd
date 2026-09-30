extends VBoxContainer
## PrestigePanel — Ascendancy: the reset layer, and the only screen that can wipe a run.
##
## This screen is deliberately the most cautious in the game. Ascending throws away every
## level, every item and every unlock, so the button is disabled until the gate is met, the
## cost is spelled out in full before anything is lost, and the action routes through the
## existing ConfirmDialog rather than firing on a single click.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _status_box: VBoxContainer
var _reward_box: VBoxContainer
var _history_box: VBoxContainer
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Ascendancy", UITokens.FONT_DISPLAY))
	add_child(UIStyle.label(
		"End a journey and begin again with a permanent bonus. Everything you have trained is " +
		"lost; what you keep is the bonus, your collection log and your lifetime record.",
		true, UITokens.FONT_SMALL))
	_status_box = UIStyle.section("Where you stand", "progress toward the gate")
	add_child(_status_box)
	_reward_box = UIStyle.section("What the next ascension pays", "")
	add_child(_reward_box)
	_history_box = UIStyle.section("Record", "past ascensions and the run behind them")
	add_child(_history_box)
	EventBus.state_refreshed.connect(refresh)
	EventBus.skill_level_up.connect(func(_s, _l): refresh())
	refresh()

func detail_context() -> Dictionary:
	var body: String = "Ascendancy needs %s lifetime XP. Every ascension adds a permanent bonus " % UIStyle.fmt(PrestigeManager.GATE_XP)
	body += "to skill XP and gold that no reset takes away."
	return {"kind": "text", "title": "Ascendancy", "body": body}

func refresh() -> void:
	if not _built:
		return
	_rebuild_status()
	_rebuild_reward()
	_rebuild_history()

func _clear(box: VBoxContainer) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _rebuild_status() -> void:
	_clear(_status_box)
	var n: int = PrestigeManager.ascensions()
	_status_box.add_child(Widgets.key_value("Ascensions taken", "%d" % n))
	_status_box.add_child(Widgets.key_value("Permanent bonus", PrestigeManager.bonus_summary()))
	_status_box.add_child(Widgets.key_value("Lifetime XP this run", UIStyle.fmt(PrestigeManager.lifetime_xp())))
	_status_box.add_child(Widgets.key_value("Gate", "%s lifetime XP" % UIStyle.fmt(PrestigeManager.GATE_XP)))
	var progress: float = clampf(PrestigeManager.lifetime_xp() / PrestigeManager.GATE_XP, 0.0, 1.0)
	_status_box.add_child(Widgets.progress_bar(PrestigeManager.lifetime_xp(),
		PrestigeManager.GATE_XP, UITokens.TEAL,
		"%s / %s" % [UIStyle.fmt(PrestigeManager.lifetime_xp()), UIStyle.fmt(PrestigeManager.GATE_XP)],
		14, "Lifetime XP toward the ascension gate"))
	if n <= 0:
		_status_box.add_child(UIStyle.label(
			"You have not ascended yet. The first ascension is the hardest — everything after it " +
			"starts with a bonus already in place.", true, UITokens.FONT_SMALL))

func _rebuild_reward() -> void:
	_clear(_reward_box)
	var reward: Dictionary = PrestigeManager.next_reward()
	if bool(reward.get("capped", false)):
		_reward_box.add_child(UIStyle.colored_label("Ascendancy is at its cap.", UITokens.AMBER, UITokens.FONT_SMALL))
		return
	_reward_box.add_child(Widgets.key_value("Ascension %d pays" % int(reward["ascension"]),
		"+%d%% skill XP, +%d%% gold" % [int(reward["xp_percent"]), int(reward["gp_percent"])]))
	_reward_box.add_child(UIStyle.label(
		"The bonus applies to everything, immediately and permanently, and stacks with every " +
		"ascension you take.", true, UITokens.FONT_SMALL))
	var blocker: String = PrestigeManager.blocker()
	var button := UIStyle.button("Ascend", "Reset this run and take the permanent bonus")
	button.disabled = not PrestigeManager.can_ascend()
	if button.disabled:
		button.tooltip_text = blocker if blocker != "" else "Ascendancy is at its cap"
	button.pressed.connect(_confirm_ascend)
	_reward_box.add_child(button)
	if not blocker.is_empty():
		_reward_box.add_child(UIStyle.colored_label(blocker, UITokens.AMBER, UITokens.FONT_SMALL))

## Spell out exactly what is lost before anything is lost. The gate is the only guard on a
## button that deletes a character, so the confirmation has to be the real second one.
func _confirm_ascend() -> void:
	var n: int = PrestigeManager.ascensions() + 1
	var body: String = "Ascend to level %d?\n\n" % n
	body += "LOST: every skill level, your gold, items, equipment, unlocks, quest and milestone " \
		+ "progress, the settlement, and everything bought in this run.\n\n"
	body += "KEPT: your collection log, your lifetime record, and a permanent +%d%% skill XP / +%d%% gold bonus." % [
		int(PrestigeManager.XP_PER_ASCENSION * float(n)),
		int(PrestigeManager.GP_PER_ASCENSION * float(n))]
	ConfirmDialog.ask(self, "Ascend?", body, "Ascend", func():
		var result: Dictionary = PrestigeManager.ascend()
		if not bool(result.get("ok", false)):
			EventBus.notify(str(result.get("reason", "Could not ascend")), "warn")
		refresh(), true)

func _rebuild_history() -> void:
	_clear(_history_box)
	var total: int = PrestigeManager.total_ascendancies()
	var kept: Dictionary = PlayerData.prestige.get("lifetime_stats", {}) as Dictionary
	if total <= 0 and kept.is_empty():
		_history_box.add_child(UIStyle.label("No record yet. Ascend to start one.", true, UITokens.FONT_SMALL))
		return
	_history_box.add_child(Widgets.key_value("Ascensions taken", "%d" % total))
	_history_box.add_child(Widgets.key_value("Items discovered all-time", "%d" % int((kept.get("items_gained", {}) as Dictionary).size())))
	_history_box.add_child(Widgets.key_value("Enemies felled all-time", "%d" % int((kept.get("monsters_killed", {}) as Dictionary).size())))
	_history_box.add_child(Widgets.key_value("Deaths all-time", UIStyle.fmt(float(kept.get("deaths", 0)))))
	_history_box.add_child(Widgets.key_value("Gold earned all-time", UIStyle.fmt(float(kept.get("gp_earned", 0)))))
	var log: Dictionary = PlayerData.prestige.get("history", {}) as Dictionary
	_history_box.add_child(Widgets.key_value("Collection entries kept",
		"%d" % ((log.get("items", {}) as Dictionary).size() + (log.get("monsters", {}) as Dictionary).size())))
