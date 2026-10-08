extends VBoxContainer
## QuestsPanel — the Tasks screen: difficulty sub-tabs, the six-hour rotation, and the task list.
##
## Tasks are organised the way players scan them: by difficulty tier (Easy → Nightmare), with a
## separate tab for the rotation whose featured tasks change every six hours. The Show filter
## narrows within the open tab; the state badges on every card still tell the whole story.
##
## Each objective states whether it counts something you HOLD (and can therefore un-satisfy) or
## something you have EVER DONE (a lifetime counter that cannot regress). That distinction is
## shown on every row, because it changes how the player should plan.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

const ROTATING_TAB: String = "rotating"
## Tier colours follow the house semantics: green/teal/blue read as progress, purple as rare
## mastery, red as danger — a readable ramp from Easy to Nightmare.
const DIFFICULTY_COLORS: Dictionary = {
	"easy": UITokens.GREEN,
	"normal": UITokens.TEAL,
	"hard": UITokens.BLUE,
	"expert": UITokens.PURPLE,
	"nightmare": UITokens.RED,
}

var _list: VBoxContainer
var _filter: OptionButton
var _filter_keys: Array[String] = ["available", "in_progress", "ready", "completed", "locked", "all"]
var _tabs_root: HFlowContainer
var _tab_buttons: Array[Button] = []
var _tab_ids: Array[String] = []
var _active_tab: String = ""
var _rotation_label: Label = null
var _rotation_timer: Timer
var _last_window: int = -1
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Frontier tasks", UITokens.FONT_DISPLAY))
	add_child(UIStyle.label(
		"Objectives are measured from your whole run: things you have already done count, so accepting a task never invalidates progress. Rewards are granted once, when you claim them.",
		true, UITokens.FONT_SMALL))
	# Difficulty sub-tabs (plus the rotating window) are the primary way tasks are scanned.
	_tab_ids = Quests.DIFFICULTIES.duplicate()
	_tab_ids.append(ROTATING_TAB)
	var labels: Array[String] = []
	for tab_id in _tab_ids:
		labels.append("Rotating" if tab_id == ROTATING_TAB else tab_id.capitalize())
	var strip: Dictionary = Widgets.tab_flow(labels, func(index): _select_tab(_tab_ids[index]))
	_tabs_root = strip["root"] as HFlowContainer
	_tab_buttons.assign(strip["buttons"])
	add_child(_tabs_root)
	_active_tab = _tab_ids[0]
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", UITokens.SP_4)
	bar.add_child(UIStyle.label("Show", true, UITokens.FONT_SMALL))
	_filter = Widgets.option_menu(["Available", "In progress", "Ready to claim", "Completed", "Locked", "All"],
		func(_i): _rebuild(), 0)
	bar.add_child(_filter)
	add_child(bar)
	_list = UIStyle.vbox(UITokens.SP_4)
	add_child(_list)
	# The rotation flips on wall-clock boundaries; a slow timer keeps the open tab honest between
	# them (and rebuilds the moment a new window begins) without touching a frame budget.
	_rotation_timer = Timer.new()
	_rotation_timer.wait_time = 30.0
	_rotation_timer.autostart = true
	_rotation_timer.timeout.connect(_on_rotation_tick)
	add_child(_rotation_timer)
	EventBus.quest_objective_progress.connect(func(_q, _i, _c, _r): _rebuild())
	EventBus.quest_reward_claimed.connect(func(_q): _rebuild())
	EventBus.bank_changed.connect(_rebuild)
	EventBus.state_refreshed.connect(_rebuild)
	_update_tab_buttons()
	_rebuild()

func focus_route(route: Dictionary) -> void:
	var quest_id: String = str(route.get("quest_id", ""))
	if quest_id != "":
		context_changed.emit({"kind": "goal", "goal": {"kind": "quest", "id": quest_id}})

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Tasks",
		"body": "Select a task to see its objectives, prerequisites, reward and the route to each objective."}

func _select_tab(tab_id: String) -> void:
	_active_tab = tab_id if _tab_ids.has(tab_id) else _tab_ids[0]
	_update_tab_buttons()
	_rebuild()

func _update_tab_buttons() -> void:
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].button_pressed = _tab_ids[i] == _active_tab

func _rebuild() -> void:
	if not _built:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rotation_label = null
	var filter: String = _filter_keys[clampi(_filter.selected, 0, _filter_keys.size() - 1)]
	_last_window = Quests.rotation_window()
	if _active_tab == ROTATING_TAB:
		_rebuild_rotating(filter)
	else:
		_rebuild_difficulty(filter)

func _rebuild_difficulty(filter: String) -> void:
	var shown: int = 0
	for quest_id in Quests.all_quest_ids():
		if Quests.is_rotating(quest_id):
			continue
		if str(Quests.get_quest(quest_id).get("difficulty", "")) != _active_tab:
			continue
		var card: Control = _matching_card(quest_id, filter)
		if card == null:
			continue
		shown += 1
		_list.add_child(card)
	if shown == 0:
		_list.add_child(Widgets.empty_state("Nothing in this tab",
			"No tasks match the current filter here. Switch the filter, or make progress on an active task.",
			"Show all", func():
				_filter.selected = 5
				_rebuild()))

func _rebuild_rotating(filter: String) -> void:
	_rotation_label = UIStyle.colored_label(_rotation_headline(), UITokens.GOLD_BRIGHT, UITokens.FONT_SMALL)
	_list.add_child(_rotation_label)
	_list.add_child(UIStyle.label(
		"Featured from the rotation pool. A claimed task reopens next rotation and needs fresh progress. Daily streak: %d day(s), rewards x%.1f. Claim one each day to keep it." % [Quests.current_streak(), Quests.streak_multiplier()],
		true, UITokens.FONT_MICRO))
	var shown: int = 0
	for quest_id in Quests.featured_rotating_ids():
		var card: Control = _matching_card(quest_id, filter, true)
		if card == null:
			continue
		shown += 1
		_list.add_child(card)
	if shown == 0:
		_list.add_child(Widgets.empty_state("Nothing to show in this rotation",
			"No featured tasks match the current filter. Switch the filter, or check back after the next rotation.",
			"Show all", func():
				_filter.selected = 5
				_rebuild()))

func _rotation_headline() -> String:
	return "Fresh selection in %s — the rotation changes every six hours." % UIStyle.fmt_duration(float(Quests.seconds_until_rotation()))

func _on_rotation_tick() -> void:
	if _active_tab != ROTATING_TAB:
		return
	if Quests.rotation_window() != _last_window:
		_rebuild()
	elif _rotation_label != null and is_instance_valid(_rotation_label):
		_rotation_label.text = _rotation_headline()

## Builds the card for a task only when it matches the state filter; null otherwise.
func _matching_card(quest_id: String, filter: String, show_difficulty := false) -> Control:
	var q: Dictionary = Quests.get_quest(quest_id)
	var p: Dictionary = Quests.progress(quest_id)
	var claimed: bool = Quests.is_claimed(quest_id)
	var complete: bool = p["all_satisfied"] and not claimed
	var locked: bool = not Quests.prerequisites_met(quest_id)
	var accepted: bool = Quests.is_accepted(quest_id)
	var state: String = "completed" if claimed else ("locked" if locked else ("ready" if complete else ("in_progress" if accepted else "available")))
	if filter != "all" and state != filter:
		return null
	return _quest_card(quest_id, q, p, state, show_difficulty)

func _quest_card(quest_id: String, q: Dictionary, p: Dictionary, state: String, show_difficulty := false) -> Control:
	var accent: bool = state == "ready"
	var card := UIStyle.card(accent)
	var col := UIStyle.vbox(UITokens.SP_3)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITokens.SP_4)
	head.add_child(UIStyle.icon_texture("currencies", "gp"))
	var title := UIStyle.title(str(q.get("name", quest_id)), UITokens.FONT_SUBHEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(title)
	if show_difficulty:
		var difficulty: String = str(q.get("difficulty", "normal"))
		head.add_child(Widgets.badge(difficulty.capitalize(), DIFFICULTY_COLORS.get(difficulty, UITokens.TEXT_MUTED),
			"Rotation difficulty"))
	match state:
		"completed":
			head.add_child(Widgets.badge("Completed", UITokens.GREEN))
		"ready":
			head.add_child(Widgets.badge("Ready to claim", UITokens.GOLD_BRIGHT, "Every objective is satisfied"))
		"locked":
			head.add_child(Widgets.badge("Locked", UITokens.TEXT_MUTED))
		"in_progress":
			head.add_child(Widgets.badge("In progress", UITokens.BLUE))
		_:
			if not show_difficulty:
				head.add_child(Widgets.badge("Chapter %d" % int(q.get("chapter", 1)), UITokens.BLUE))
	head.add_child(Widgets.badge("Objectives %d/%d" % [int(p["satisfied"]), int(p["total"])], UITokens.TEAL,
		"Objectives satisfied"))
	col.add_child(head)

	col.add_child(Widgets.progress_bar(float(p["satisfied"]), maxf(1.0, float(p["total"])),
		UITokens.GOLD_BRIGHT if state == "ready" else UITokens.TEAL,
		"%d / %d" % [int(p["satisfied"]), int(p["total"])], 12, "Objective progress"))

	if str(q.get("description", "")) != "":
		var d := UIStyle.label(str(q["description"]), true, UITokens.FONT_SMALL)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(d)
	if state == "locked":
		var reason := UIStyle.colored_label("Locked — %s" % Quests.lock_reason(quest_id), UITokens.AMBER, UITokens.FONT_SMALL)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(reason)

	for obj in p["objectives"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITokens.SP_4)
		var mark := Label.new()
		mark.text = "✓" if bool(obj["satisfied"]) else "✗"
		mark.add_theme_font_size_override("font_size", UITokens.FONT_SMALL)
		mark.add_theme_color_override("font_color", UITokens.GREEN if bool(obj["satisfied"]) else UITokens.AMBER)
		mark.custom_minimum_size = Vector2(14, 0)
		row.add_child(mark)
		var text := UIStyle.vbox(UITokens.SP_1)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Wrapped unconditionally: with a few hundred tasks, one long label must never set the
		# whole panel's minimum width at the narrowest supported window.
		var obj_label := UIStyle.label(str(obj["label"]), false, UITokens.FONT_SMALL)
		obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(obj_label)
		var detail: String = "%s / %s  ·  %s" % [UIStyle.fmt(float(obj["current"])), UIStyle.fmt(float(obj["required"])), str(obj["hint"])]
		var detail_label := UIStyle.label(detail, true, UITokens.FONT_MICRO)
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(detail_label)
		row.add_child(text)
		row.add_child(Widgets.badge("Lifetime" if bool(obj["lifetime"]) else "Held now",
			UITokens.PURPLE if bool(obj["lifetime"]) else UITokens.BLUE,
			"Lifetime counters never regress; held items can be spent." if bool(obj["lifetime"]) else "This objective checks what you are holding right now."))
		var route: Dictionary = obj.get("route", {})
		if not route.is_empty() and not bool(obj["satisfied"]):
			var go := UIStyle.mini_button("Go")
			var r: Dictionary = route
			go.pressed.connect(func(): navigated.emit(r))
			row.add_child(go)
		col.add_child(row)

	var reward_items: Dictionary = q.get("reward", {}).get("items", {})
	if not reward_items.is_empty():
		col.add_child(Widgets.item_rewards(reward_items))
	col.add_child(Widgets.key_value("Reward", Quests.describe_reward(q.get("reward", {})), UITokens.GOLD_BRIGHT))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", UITokens.SP_3)
	if state == "ready":
		var claim := UIStyle.primary_button("Claim reward")
		claim.pressed.connect(func():
			Quests.claim(quest_id)
			_rebuild())
		buttons.add_child(claim)
	elif state == "available":
		var accept := UIStyle.button("Accept")
		accept.pressed.connect(func():
			if Quests.accept(quest_id):
				_filter.select(2 if Quests.is_complete(quest_id) else 1)
				context_changed.emit({"kind": "goal", "goal": {"kind": "quest", "id": quest_id}})
			_rebuild())
		buttons.add_child(accept)
	var explain := UIStyle.mini_button("Track as goal")
	explain.pressed.connect(func():
		Goals.pin("quest", quest_id)
		context_changed.emit({"kind": "goal", "goal": {"kind": "quest", "id": quest_id}}))
	buttons.add_child(explain)
	col.add_child(buttons)
	return card
