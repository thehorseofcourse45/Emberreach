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
var _tree_box: VBoxContainer
var _history_box: VBoxContainer
var _built: bool = false
var _tree_window: Window

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
	_tree_box = UIStyle.section("Ascendancy tree", "spend points on permanent, stacking nodes")
	add_child(_tree_box)
	_history_box = UIStyle.section("Record", "past ascensions and the run behind them")
	add_child(_history_box)
	EventBus.state_refreshed.connect(refresh)
	EventBus.skill_level_up.connect(func(_s, _l): refresh())
	refresh()

func detail_context() -> Dictionary:
	var body: String = "Ascendancy needs %s this run’s XP. Every ascension adds a permanent bonus " % UIStyle.fmt(PrestigeManager.GATE_XP)
	body += "to skill XP and gold that no reset takes away."
	return {"kind": "text", "title": "Ascendancy", "body": body}

func refresh() -> void:
	if not _built:
		return
	_rebuild_status()
	_rebuild_reward()
	_rebuild_tree()
	_rebuild_history()

func _clear(box: VBoxContainer) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _rebuild_status() -> void:
	_clear(_status_box)
	var n: int = PrestigeManager.ascensions()
	_status_box.add_child(Widgets.key_value("Ascensions taken", "%d" % n))
	_status_box.add_child(Widgets.key_value("Ascendancy Points", "%d available · %d earned" % [PrestigeManager.points(), PrestigeManager.points_earned()]))
	_status_box.add_child(Widgets.key_value("Active bonus", PrestigeManager.bonus_summary()))
	_status_box.add_child(Widgets.key_value("This run’s XP", UIStyle.fmt(PrestigeManager.lifetime_xp())))
	_status_box.add_child(Widgets.key_value("Gate", "%s this run’s XP" % UIStyle.fmt(PrestigeManager.GATE_XP)))
	var progress: float = clampf(PrestigeManager.lifetime_xp() / PrestigeManager.GATE_XP, 0.0, 1.0)
	_status_box.add_child(Widgets.progress_bar(PrestigeManager.lifetime_xp(),
		PrestigeManager.GATE_XP, UITokens.TEAL,
		"%s / %s" % [UIStyle.fmt(PrestigeManager.lifetime_xp()), UIStyle.fmt(PrestigeManager.GATE_XP)],
		14, "This run’s XP toward the ascension gate"))
	if n <= 0:
		_status_box.add_child(UIStyle.label(
			"You have not ascended yet. The first ascension is the hardest — everything after it " +
			"starts with a bonus already in place.", true, UITokens.FONT_SMALL))

func _rebuild_reward() -> void:
	_clear(_reward_box)
	var reward: Dictionary = PrestigeManager.next_reward()
	_reward_box.add_child(Widgets.key_value("Ascension %d grants" % int(reward["ascension"]),
		"+%d Ascendancy Point" % int(reward["points"])))
	_reward_box.add_child(UIStyle.label(
		"Each ascension gives a point to spend in the Ascendancy tree below. Points and bought " +
		"nodes are permanent and survive every future reset. There is no ascension limit; every upgrade can eventually be maxed.", true, UITokens.FONT_SMALL))
	_reward_box.add_child(UIStyle.label("Resets: skills, mastery, Storage, equipment, farms, pens, workers, research, enchants, dreams, course, stars, quests and combat. Keeps: collection log, accumulated lifetime counters, Ascendancy points and nodes, game mode and settings.", true, UITokens.FONT_SMALL))
	var blocker: String = PrestigeManager.blocker()
	var button := UIStyle.button("Ascend", "Reset this run and take the permanent bonus")
	button.disabled = not PrestigeManager.can_ascend()
	if button.disabled:
		button.tooltip_text = blocker
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
	body += "KEPT: your collection log, your lifetime record, your Ascendancy points and nodes, and +%d Ascendancy Point to spend." % PrestigeManager.POINTS_PER_ASCENSION
	ConfirmDialog.ask(self, "Ascend?", body, "Ascend", func():
		var result: Dictionary = PrestigeManager.ascend()
		if not bool(result.get("ok", false)):
			EventBus.notify(str(result.get("reason", "Could not ascend")), "warn")
		refresh(), true)

func _rebuild_tree() -> void:
	_clear(_tree_box)
	var available: int = PrestigeManager.points()
	_tree_box.add_child(Widgets.key_value("Points to spend", "%d" % available,
		UITokens.GREEN if available > 0 else UITokens.TEXT_MUTED))
	_tree_box.add_child(UIStyle.label("Explore permanent upgrades and their prerequisite paths. Bought ranks survive every ascension.", true, UITokens.FONT_SMALL))
	var open_tree := UIStyle.button("Open upgrade tree", "Explore, pan and zoom the connected upgrade tree")
	open_tree.pressed.connect(_open_tree)
	_tree_box.add_child(open_tree)
	if PrestigeManager.points_spent() > 0:
		var respec := UIStyle.button("Respec all", "Return every spent point and clear all nodes")
		respec.pressed.connect(func():
			ConfirmDialog.ask(self, "Respec Ascendancy?",
				"Return all %d spent point(s) and clear every node? Your point total is unchanged; you simply re-choose." % PrestigeManager.points_spent(),
				"Respec", func():
					PrestigeManager.respec()
					refresh(), false))
		_tree_box.add_child(respec)

func _open_tree() -> void:
	if not is_instance_valid(_tree_window):
		_tree_window = load("res://scripts/ui/AscendancyTree.gd").new()
		add_child(_tree_window)
	_tree_window.open()

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
