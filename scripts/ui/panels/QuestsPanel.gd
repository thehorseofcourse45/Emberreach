extends VBoxContainer
## QuestsPanel — authored tasks, their live objective state, and exactly-once reward claiming.
##
## Each objective states whether it counts something you HOLD (and can therefore un-satisfy) or
## something you have EVER DONE (a lifetime counter that cannot regress). That distinction is
## shown on every row, because it changes how the player should plan.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _list: VBoxContainer
var _filter: OptionButton
var _filter_keys: Array[String] = ["available", "in_progress", "ready", "completed", "locked", "all"]
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Frontier tasks", UITokens.FONT_DISPLAY))
	add_child(UIStyle.label(
		"Objectives are measured from your whole run: things you have already done count, so accepting a task never invalidates progress. Rewards are granted once, when you claim them.",
		true, UITokens.FONT_SMALL))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", UITokens.SP_4)
	bar.add_child(UIStyle.label("Show", true, UITokens.FONT_SMALL))
	_filter = Widgets.option_menu(["Available", "In progress", "Ready to claim", "Completed", "Locked", "All"],
		func(_i): _rebuild(), 0)
	bar.add_child(_filter)
	add_child(bar)
	_list = UIStyle.vbox(UITokens.SP_4)
	add_child(_list)
	EventBus.quest_objective_progress.connect(func(_q, _i, _c, _r): _rebuild())
	EventBus.quest_reward_claimed.connect(func(_q): _rebuild())
	EventBus.bank_changed.connect(_rebuild)
	EventBus.state_refreshed.connect(_rebuild)
	_rebuild()

func focus_route(route: Dictionary) -> void:
	var quest_id: String = str(route.get("quest_id", ""))
	if quest_id != "":
		context_changed.emit({"kind": "goal", "goal": {"kind": "quest", "id": quest_id}})

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Tasks",
		"body": "Select a task to see its objectives, prerequisites, reward and the route to each objective."}

func _rebuild() -> void:
	if not _built:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var filter: String = _filter_keys[clampi(_filter.selected, 0, _filter_keys.size() - 1)]
	var shown: int = 0
	for quest_id in Quests.all_quest_ids():
		var q: Dictionary = Quests.get_quest(quest_id)
		var p: Dictionary = Quests.progress(quest_id)
		var claimed: bool = Quests.is_claimed(quest_id)
		var complete: bool = p["all_satisfied"] and not claimed
		var locked: bool = not Quests.prerequisites_met(quest_id)
		var accepted: bool = Quests.is_accepted(quest_id)
		var state: String = "completed" if claimed else ("locked" if locked else ("ready" if complete else ("in_progress" if accepted else "available")))
		if filter != "all" and state != filter:
			continue
		shown += 1
		_list.add_child(_quest_card(quest_id, q, p, state))
	if shown == 0:
		_list.add_child(Widgets.empty_state("Nothing in this filter",
			"Switch the filter, or make progress on an active task.",
			"Show all", func():
				_filter.selected = 5
				_rebuild()))

func _quest_card(quest_id: String, q: Dictionary, p: Dictionary, state: String) -> Control:
	var accent: bool = state == "ready"
	var card := UIStyle.card(accent)
	var col := UIStyle.vbox(UITokens.SP_3)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITokens.SP_4)
	var title := UIStyle.title(str(q.get("name", quest_id)), UITokens.FONT_SUBHEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
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
		text.add_child(UIStyle.label(str(obj["label"]), false, UITokens.FONT_SMALL))
		var detail: String = "%s / %s  ·  %s" % [UIStyle.fmt(float(obj["current"])), UIStyle.fmt(float(obj["required"])), str(obj["hint"])]
		text.add_child(UIStyle.label(detail, true, UITokens.FONT_MICRO))
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
