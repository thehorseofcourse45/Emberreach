extends VBoxContainer
## SkillsPanel — one skill at a time: its level, its activities, and the selected activity's
## full explanation, quantities and controls.
##
## Owns the "craft one / craft N / craft maximum / repeat until stopped" controls. Those all
## occupy the same single activity slot: a target quantity is not a second worker.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

const QUANTITY_PRESETS: Array[int] = [1, 5, 10, 25, 50]
## Skills whose activity list is rendered inside their system section instead of the generic
## Activities card. Surveying's charts are what the Frontier map shows progress across, so they
## live on the map; here, that card only promised rewards those actions never produce.
const INTEGRATED_ACTIVITIES: Array[String] = ["cartography"]
## Preloaded by path: the global class cache is not guaranteed to know a freshly added
## file when the headless test suite runs.
const SkillSystemsView = preload("res://scripts/ui/panels/SkillSystems.gd")

var _skill_id: String = ""
var _selected_action: String = ""
var _header: VBoxContainer
var _main_grid: GridContainer
var _activities_card: PanelContainer
var _selected_card: PanelContainer
var _advanced_body: VBoxContainer
var _activities: VBoxContainer
var _selected_box: VBoxContainer
var _mods_box: VBoxContainer
var _mastery_box: VBoxContainer
var _quantity_index: int = 0
var _built: bool = false
var _systems: SkillSystemsView
## Live XP readout. The bar is rebuilt on every refresh(), so these are re-cached each rebuild and
## then polled per frame: the simulation grants XP per action, not per stop, and a bar that only
## moves when you leave the screen makes you guess what you earned.
var _xp_bar: ProgressBar = null
var _xp_bar_text: Label = null
var _xp_remaining: Label = null
## Level the cached bar was built for. While this differs from the live level the header is
## mid-rebuild, so _process() must not write stale values over the new widgets.
var _xp_level_shown: int = -1

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_7)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	resized.connect(_update_columns)
	EventBus.skill_level_up.connect(func(s, _l): if s == _skill_id: refresh())
	EventBus.mastery_level_up.connect(func(s, _a, _l): if s == _skill_id: refresh())
	EventBus.mastery_pool_changed.connect(func(s, _v): if s == _skill_id: _refresh_mastery())
	EventBus.action_started.connect(func(_s, _a): refresh())
	EventBus.action_stopped.connect(func(_s, _a): refresh())
	EventBus.action_completed.connect(func(s, _a, _r): if s == _skill_id: _refresh_selected())
	EventBus.state_refreshed.connect(refresh)
	EventBus.bank_changed.connect(_refresh_selected)
	if _skill_id == "":
		_select_skill(SkillManager.active_skill if SkillManager.running else "woodcutting")
	else:
		refresh()

func focus_route(route: Dictionary) -> void:
	var skill_id: String = str(route.get("skill_id", ""))
	if skill_id != "":
		_select_skill(skill_id)
	elif SkillManager.running:
		_select_skill(SkillManager.active_skill)
	var action_id: String = str(route.get("action_id", ""))
	if action_id != "":
		_selected_action = action_id
		_refresh_selected()
		_sync_system_selection()
	if str(route.get("start", "")) == "1":
		_on_start()

func detail_context() -> Dictionary:
	if _selected_action == "":
		return {"kind": "text", "title": DataLoader.get_skill(_skill_id).get("name", _skill_id),
			"body": "Select an activity to see its materials, projections and modifiers."}
	return {"kind": "recipe", "skill_id": _skill_id, "action_id": _selected_action}

func _build() -> void:
	_built = true
	# No skill dropdown here on purpose: the left sidebar lists every skill with its level and
	# switches to it, so a picker on this tab only duplicated navigation and crowded the top.
	_header = UIStyle.vbox(UITokens.SP_4)
	add_child(_header)
	_main_grid = GridContainer.new()
	_main_grid.columns = 2
	_main_grid.add_theme_constant_override("h_separation", UITokens.SP_5)
	_main_grid.add_theme_constant_override("v_separation", UITokens.SP_5)
	add_child(_main_grid)
	_systems = SkillSystemsView.new()
	_systems.visible = false
	add_child(_systems)
	_systems.navigated.connect(func(route): navigated.emit(route))
	_systems.action_selected.connect(func(_sid, action_id): _select_action(str(action_id)))
	_activities_card = UIStyle.panel()
	_activities_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_grid.add_child(_activities_card)
	_activities = UIStyle.vbox(UITokens.SP_3)
	_activities_card.add_child(_activities)
	_selected_card = UIStyle.panel(true)
	_selected_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_grid.add_child(_selected_card)
	_selected_box = UIStyle.vbox(UITokens.SP_4)
	_selected_card.add_child(_selected_box)
	var advanced := UIStyle.button("Mastery & bonuses  ▾")
	advanced.alignment = HORIZONTAL_ALIGNMENT_LEFT
	advanced.pressed.connect(func():
		_advanced_body.visible = not _advanced_body.visible
		advanced.text = "Mastery & bonuses  %s" % ("▾" if _advanced_body.visible else "▸"))
	add_child(advanced)
	_advanced_body = UIStyle.vbox(UITokens.SP_5)
	_advanced_body.visible = false
	add_child(_advanced_body)
	_mastery_box = UIStyle.section("Mastery pool")
	_advanced_body.add_child(_mastery_box)
	_mods_box = UIStyle.section("Modifiers applying to this skill")
	_advanced_body.add_child(_mods_box)
	_update_columns()

func _update_columns() -> void:
	if _main_grid == null:
		return
	var wide: bool = size.x >= 760
	# Two columns only make sense when both cells hold content: a hidden Activities card would
	# leave the details card sitting beside an empty half of the grid.
	var paired: bool = wide and _activities_card != null and _activities_card.visible
	_main_grid.columns = 2 if paired else 1
	if _selected_card != null:
		_main_grid.move_child(_selected_card, 1 if paired else 0)

## Child order is the page's reading order. When a skill's activities are rendered inside its
## system section, that section moves above the details card, so a tap on a chart row updates the
## card directly beneath it instead of one that scrolled past off the top of the screen.
func _arrange_layout() -> void:
	if _header == null or _main_grid == null or _systems == null:
		return
	var integrated: bool = _skill_id in INTEGRATED_ACTIVITIES
	move_child(_systems, 1 if integrated else 2)
	move_child(_main_grid, 2 if integrated else 1)

# =========================================================================
#  Refresh
# =========================================================================

func _select_skill(skill_id: String) -> void:
	_skill_id = skill_id if DataLoader.skills.has(skill_id) else "woodcutting"
	_systems.set_skill(_skill_id)
	_selected_action = SkillManager.active_action_id if SkillManager.running and SkillManager.active_skill == _skill_id else ""
	if _selected_action == "":
		for action in DataLoader.get_skill_actions(_skill_id):
			if typeof(action) == TYPE_DICTIONARY and PlayerData.get_level(_skill_id) >= int(action.get("level_required", 1)):
				_selected_action = str(action.get("id", ""))
				break
	refresh()

func refresh() -> void:
	if not _built or _skill_id == "":
		return
	_rebuild_header()
	_rebuild_activities()
	_refresh_selected()
	_refresh_mastery()
	_rebuild_modifiers()
	_systems.set_selected_action(_selected_action)
	_systems.rebuild()

func _rebuild_header() -> void:
	_clear(_header)
	var skill: Dictionary = DataLoader.get_skill(_skill_id)
	var level: int = PlayerData.get_level(_skill_id)
	var xp: float = PlayerData.get_xp(_skill_id)
	var hero := UIStyle.panel()
	var head := HBoxContainer.new()
	hero.add_child(head)
	head.add_theme_constant_override("separation", UITokens.SP_5)
	var icon := TextureRect.new()
	icon.texture = AssetRegistry.skill_icon(_skill_id)
	icon.custom_minimum_size = Vector2(UITokens.ICON_XL, UITokens.ICON_XL)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var col := UIStyle.vbox(UITokens.SP_2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var running_here: bool = SkillManager.running and SkillManager.active_skill == _skill_id
	col.add_child(UIStyle.colored_label("ACTIVE SKILL" if running_here else "SKILL PROGRESS",
		UITokens.TEAL if running_here else UITokens.TEXT_MUTED, UITokens.FONT_MICRO))
	col.add_child(UIStyle.title("%s  ·  Level %d" % [str(skill.get("name", _skill_id)), level], UITokens.FONT_DISPLAY))
	col.add_child(UIStyle.label(str(skill.get("description", "")), true, UITokens.FONT_MICRO))
	var next_level: int = mini(level + 1, XPTable.MAX_LEVEL)
	var to_next: int = XPTable.xp_to_next_level(xp, level)
	var bar := Widgets.progress_bar(XPTable.level_progress(xp, level), 1.0, UITokens.GOLD,
		"%s / %s" % [UIStyle.fmt_exact(xp), UIStyle.fmt_exact(float(XPTable.xp_for_level(next_level)))], 16,
		"Level %d progress" % level)
	col.add_child(bar)
	# Cache for the per-frame update in _process(). progress_bar() puts the text in a child Label.
	_xp_bar = bar
	_xp_bar_text = bar.get_child(0) as Label if bar.get_child_count() > 0 else null
	var to_next_row := Widgets.key_value("XP to level %d" % next_level, UIStyle.fmt_exact(float(to_next)),
		UITokens.GOLD, "Level cap for this skill in your game mode: %d" % PlayerData.get_level_cap(_skill_id))
	col.add_child(to_next_row)
	_xp_remaining = _value_label_of(to_next_row)
	_xp_level_shown = level
	var highlights := HFlowContainer.new()
	highlights.add_theme_constant_override("h_separation", UITokens.SP_4)
	highlights.add_theme_constant_override("v_separation", UITokens.SP_4)
	highlights.add_child(Widgets.stat_card("Mastery pool", "%.1f%%" % MasteryManager.get_pool_percent(_skill_id), UITokens.PURPLE))
	highlights.add_child(Widgets.stat_card("Activities unlocked", "%d / %d" % [DataLoader.get_unlocked_action_count(_skill_id, level), DataLoader.get_action_count(_skill_id)], UITokens.TEAL))
	col.add_child(highlights)
	if _skill_id == "farming":
		var farm := UIStyle.primary_button("Manage farm · upgrades, rotation & growing methods")
		farm.pressed.connect(func(): navigated.emit({"screen": Screens.FARM}))
		col.add_child(farm)
	head.add_child(col)
	_header.add_child(hero)

## key_value() returns an HBox of [key Label, value Label]; the value is the one we rewrite.
func _value_label_of(row: Control) -> Label:
	if row == null or row.get_child_count() < 2:
		return null
	return row.get_child(1) as Label

## Poll the authoritative XP state rather than rebuilding. PlayerData mutates xp in place, so this
## is one float read per frame; the level-up signal still forces a full refresh because a level
## change re-derives the bar maximum, the next-level label and the cap notice.
func _process(_delta: float) -> void:
	# is_instance_valid, not != null: _clear() uses queue_free(), so a node freed by the last
	# rebuild is still a non-null reference for the rest of that frame.
	if not is_instance_valid(_xp_bar) or not is_instance_valid(_xp_bar_text) or _skill_id == "":
		return
	var xp: float = PlayerData.get_xp(_skill_id)
	var level: int = PlayerData.get_level(_skill_id)
	if level != _xp_level_shown:
		return
	# The bar was built with max_value 1.0, so write the 0..1 fraction, not a 0..100 percent.
	_xp_bar.value = clampf(XPTable.level_progress(xp, level), 0.0, 1.0)
	var next_level: int = mini(level + 1, XPTable.MAX_LEVEL)
	if _xp_bar_text != null:
		_xp_bar_text.text = "%s / %s" % [UIStyle.fmt_exact(xp),
			UIStyle.fmt_exact(float(XPTable.xp_for_level(next_level)))]
	if _xp_remaining != null:
		_xp_remaining.text = UIStyle.fmt_exact(float(XPTable.xp_to_next_level(xp, level)))

func _rebuild_activities() -> void:
	_main_grid.visible = _skill_id not in ["ranching", "dreamwalking", "caravaneering"]
	var integrated: bool = _skill_id in INTEGRATED_ACTIVITIES
	_activities_card.visible = not integrated
	_arrange_layout()
	_update_columns()
	_clear(_activities)
	if integrated:
		# The rows are drawn by the system section that owns them (the Frontier map).
		return
	_activities.add_child(UIStyle.title("Activities", UITokens.FONT_SUBHEAD))
	_activities.add_child(UIStyle.label("Choose a reward to train toward.", true, UITokens.FONT_SMALL))
	var actions: Array = DataLoader.get_skill_actions(_skill_id)
	if actions.is_empty():
		_activities.add_child(UIStyle.label("This skill has no trainable actions yet (%s)." % _skill_id, true, UITokens.FONT_SMALL))
		return
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action_id: String = str(a.get("id", ""))
		var row := Widgets.activity_row(_skill_id, a, action_id == _selected_action,
			func(id): _select_action(str(id)))
		(row.get_child(0) as Button).custom_minimum_size.y = 60
		_activities.add_child(row)

func _select_action(action_id: String) -> void:
	_selected_action = action_id
	_quantity_index = 0
	_rebuild_activities()
	_refresh_selected()
	_sync_system_selection()
	context_changed.emit({"kind": "recipe", "skill_id": _skill_id, "action_id": action_id})

## The integrated activity list draws its own highlight, so it needs the current selection back
## before it redraws — and redrawing it here is what makes a tap on the map's list light up.
func _sync_system_selection() -> void:
	_systems.set_selected_action(_selected_action)
	if _skill_id in INTEGRATED_ACTIVITIES:
		_systems.rebuild()

func _refresh_selected() -> void:
	_clear(_selected_box)
	_selected_box.add_child(UIStyle.title("Activity details", UITokens.FONT_SUBHEAD))
	if _selected_action == "":
		_selected_box.add_child(UIStyle.label("Choose an activity to see its materials, rewards and start controls.",
			true, UITokens.FONT_SMALL))
		return
	var action: Dictionary = DataLoader.get_action(_skill_id, _selected_action)
	if action.is_empty():
		return
	var running: bool = SkillManager.running and SkillManager.active_skill == _skill_id \
		and SkillManager.active_action_id == _selected_action

	_selected_box.add_child(UIStyle.title("%s%s" % [str(action.get("name", _selected_action)),
		"  ·  running" if running else ""], UITokens.FONT_SUBHEAD))
	var rewards: Dictionary = action.get("output_items", {})
	if not rewards.is_empty():
		_selected_box.add_child(Widgets.item_rewards(rewards))
	var check: Dictionary = SkillManager.check_action(_skill_id, _selected_action)
	if not bool(check["ok"]):
		_selected_box.add_child(UIStyle.colored_label("Cannot start: %s" % str(check["detail"]), UITokens.AMBER, UITokens.FONT_SMALL))
	if SkillManager.running and not running and SkillManager.stop_reason != SkillManager.StopReason.NONE:
		_selected_box.add_child(UIStyle.colored_label("Last activity ended: %s" % SkillManager.stop_reason_text(),
			UITokens.TEXT_MUTED, UITokens.FONT_MICRO))

	# Materials with current-vs-required quantities and a route to each source.
	var inputs: Dictionary = action.get("input_items", {})
	if not inputs.is_empty():
		_selected_box.add_child(UIStyle.section("Materials"))
		for item_id in inputs.keys():
			var need: int = int(inputs[item_id])
			var have: int = BankManager.get_count(str(item_id))
			var route: Dictionary = {}
			var sources: Array = Goals.sources_for_item(str(item_id))
			if not sources.is_empty():
				route = sources[0].get("route", {})
			_selected_box.add_child(Widgets.requirement_row(
				str(DataLoader.get_item(str(item_id)).get("name", item_id)), float(have), float(need),
				have >= need, "%s available now" % UIStyle.fmt_exact(float(have)), route))

	var est: Dictionary = ActionEstimates.for_action(_skill_id, _selected_action)
	if not est.is_empty():
		var gains := UIStyle.section("What you gain")
		gains.tooltip_text = str(est["assumptions"])
		_selected_box.add_child(gains)
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", UITokens.SP_6)
		grid.add_theme_constant_override("v_separation", UITokens.SP_2)
		_add_stat(grid, "Action time", "%.2fs" % float(est["interval"]))
		_add_stat(grid, "XP per action", UIStyle.fmt(float(est["xp_per_action"])))
		_add_stat(grid, "XP per hour (≈)", UIStyle.fmt(float(est["xp_per_hour"])))
		_add_stat(grid, "Success chance", UIStyle.fmt_percent(float(est["success_chance"])))
		if float(est.get("output_per_hour", 0.0)) > 0.0:
			_add_stat(grid, "Output per hour (≈)", "%s %s" % [UIStyle.fmt(float(est["output_per_hour"])), str(est["output_name"])])
		if float(est["xp_to_next"]) > 0.0:
			_add_stat(grid, "Time to next level (≈)",
				UIStyle.fmt_duration(float(est["hours_to_next_level"]) * 3600.0) if float(est["hours_to_next_level"]) > 0.0 else "—")
		if float(est.get("supply_hours", -1.0)) >= 0.0:
			_add_stat(grid, "Current stock lasts (≈)", UIStyle.fmt_duration(float(est["supply_hours"])))
		_selected_box.add_child(grid)

	if not est.is_empty():
		_add_forecast_details(est, action)
	# Quantity controls.
	var qty_row := HBoxContainer.new()
	qty_row.add_theme_constant_override("separation", UITokens.SP_3)
	qty_row.add_child(UIStyle.label("Quantity", true, UITokens.FONT_SMALL))
	var qty_menu := Widgets.option_menu(["Just run", "1", "5", "10", "25", "50", "Maximum now"], func(i):
		_quantity_index = i
		_refresh_selected(), _quantity_index)
	qty_menu.tooltip_text = "A quantity stops the activity when it is reached. It still uses the one activity slot."
	qty_row.add_child(qty_menu)
	var	max_now: int = _max_craftable(action)
	qty_row.add_child(UIStyle.colored_label("maximum now: %s" % (UIStyle.fmt_exact(float(max_now)) if max_now > 0 else "none"),
		UITokens.TEAL if max_now > 0 else UITokens.AMBER, UITokens.FONT_MICRO))
	_selected_box.add_child(qty_row)

	# Event policy row (activity plan Task 6): one menu per category THIS skill's pool uses,
	# writing the same PlayerData.event_policies key EventDirector reads at decision time.
	# Skills with no event pool show nothing — a dead control would imply a feature that isn't
	# there for them.
	var event_categories: Array[String] = []
	for ev in DataLoader.get_skill_events(_skill_id):
		if typeof(ev) == TYPE_DICTIONARY:
			var category: String = str((ev as Dictionary).get("category", ""))
			if category != "" and not event_categories.has(category):
				event_categories.append(category)
	if not event_categories.is_empty():
		const POLICY_VALUES: Array[String] = ["manual", "safe", "greedy"]
		# A FLOW, not a plain HBox: with a menu per category an HBox's minimum (~450px) breaks the
		# hard "every screen fits a 420px window" pin. Flowing keeps the plan's one-row shape at
		# desktop widths and wraps the categories to a second line instead of overflowing.
		var events_row := HFlowContainer.new()
		events_row.add_theme_constant_override("h_separation", UITokens.SP_3)
		events_row.add_theme_constant_override("v_separation", UITokens.SP_2)
		var events_label := UIStyle.label("Events", true, UITokens.FONT_SMALL)
		events_label.tooltip_text = "How each event type decides when you are slow or away: ask each time, always play safe, or always push your luck."
		events_row.add_child(events_label)
		for category in event_categories:
			events_row.add_child(UIStyle.label("%s:" % category.capitalize(), true, UITokens.FONT_MICRO))
			var current_index: int = maxi(0, POLICY_VALUES.find(
				str(PlayerData.event_policies.get(category, "manual"))))
			var menu := Widgets.option_menu(["Ask me", "Auto safe", "Auto greedy"],
				func(i): PlayerData.event_policies[category] = POLICY_VALUES[int(i)], current_index)
			menu.tooltip_text = "What '%s' events do when you do not answer in time." % category
			events_row.add_child(menu)
		_selected_box.add_child(events_row)


	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", UITokens.SP_3)
	var start := UIStyle.primary_button("Stop" if running else "Start")
	start.disabled = not bool(check["ok"]) and not running
	start.tooltip_text = "Begin this activity" if bool(check["ok"]) else str(check["detail"])
	start.pressed.connect(_on_start)
	buttons.add_child(start)
	var pin := UIStyle.mini_button("Untrack" if Goals.is_pinned("recipe", "%s:%s" % [_skill_id, _selected_action]) else "Track goal")
	pin.pressed.connect(func():
		Goals.toggle("recipe", "%s:%s" % [_skill_id, _selected_action])
		_refresh_selected())
	buttons.add_child(pin)
	var explain := UIStyle.mini_button("Explain")
	explain.pressed.connect(func(): context_changed.emit({"kind": "recipe", "skill_id": _skill_id, "action_id": _selected_action}))
	buttons.add_child(explain)
	if CombatManager.state != CombatManager.State.IDLE:
		var retreat := UIStyle.danger_button("Retreat & start", "Combat is running — retreat and start this activity")
		retreat.pressed.connect(func():
			GameManager.request_skill_action(_skill_id, _selected_action, _target_for_index())
			refresh())
		buttons.add_child(retreat)
	_selected_box.add_child(buttons)

	if running:
		_selected_box.add_child(Widgets.progress_bar(SkillManager.progress,
			maxf(0.01, SkillManager.current_interval), UITokens.TEAL,
			"%d of %s completed" % [SkillManager.total_action_count,
				str(SkillManager.repeat_target) if SkillManager.repeat_target > 0 else "∞"], 14))
		if SkillManager.total_action_count > 0:
			_selected_box.add_child(UIStyle.label("Completed %d action(s) this session." % SkillManager.total_action_count,
				true, UITokens.FONT_MICRO))

func _add_stat(grid: HFlowContainer, key: String, value: String) -> void:
	grid.add_child(Widgets.stat_card(key, value, UITokens.TEAL if key.contains("XP") else UITokens.GOLD_BRIGHT))

func _target_for_index() -> int:
	match _quantity_index:
		0: return 0
		6: return _max_craftable(DataLoader.get_action(_skill_id, _selected_action))
		_: return QUANTITY_PRESETS[_quantity_index - 1]

## How many times the current stock can run this recipe, respecting preservation-free worst case.
func _max_craftable(action: Dictionary) -> int:
	var inputs: Dictionary = action.get("input_items", {})
	if inputs.is_empty():
		return 0
	var limit: int = 1 << 30
	for item_id in inputs.keys():
		var need: int = maxi(1, int(inputs[item_id]))
		limit = mini(limit, BankManager.get_count(str(item_id)) / need)
	if limit == 1 << 30:
		return 0
	return limit

func _on_start() -> void:
	if _selected_action == "":
		return
	var running: bool = SkillManager.running and SkillManager.active_skill == _skill_id \
		and SkillManager.active_action_id == _selected_action
	if running:
		SkillManager.stop_action(SkillManager.StopReason.PLAYER)
	else:
		GameManager.request_skill_action(_skill_id, _selected_action, _target_for_index())
	refresh()

func _refresh_mastery() -> void:
	_clear(_mastery_box)
	if _selected_action == "":
		_mastery_box.add_child(UIStyle.label("Select an activity to raise its mastery.", true, UITokens.FONT_SMALL))
		return
	var level: int = MasteryManager.get_level(_skill_id, _selected_action)
	var xp: float = MasteryManager.get_xp(_skill_id, _selected_action)
	var pool_pct: float = MasteryManager.get_pool_percent(_skill_id)
	_mastery_box.add_child(Widgets.key_value("Activity mastery", "level %d" % level, UITokens.PURPLE,
		"Mastery affects this activity only: shorter actions, better yield, better rare-drop odds"))
	_mastery_box.add_child(Widgets.key_value("Mastery XP", UIStyle.fmt_exact(xp), UITokens.PURPLE))
	_mastery_box.add_child(Widgets.progress_bar(pool_pct, 100.0, UITokens.PURPLE, "%.1f%%" % pool_pct, 14,
		"Mastery pool: 25% of mastery XP earned goes here (50% at level 99+). Spend it to level any activity on this skill."))
	_mastery_box.add_child(UIStyle.label(MasteryManager.next_checkpoint(_skill_id), true, UITokens.FONT_SMALL))
	var unlocks: Dictionary = DataLoader.get_skill(_skill_id).get("mastery_unlocks", {})
	if not unlocks.is_empty():
		var lines: Array[String] = []
		var ordered: Array = unlocks.keys()
		ordered.sort_custom(func(a, b): return int(a) < int(b))
		for threshold in ordered:
			if int(threshold) > level:
				_mastery_box.add_child(UIStyle.label("Next activity mastery %s: %s XP remaining · %s" % [str(threshold), UIStyle.fmt(float(XPTable.xp_for_level(int(threshold))) - xp), UIStyle.describe_modifier_table(unlocks[threshold])], true, UITokens.FONT_SMALL))
				break
		for threshold in ordered:
			var reached: bool = level >= int(threshold)
			lines.append("%s %s: %s" % ["✓" if reached else "·", str(threshold),
				UIStyle.describe_modifier_table(unlocks[threshold])])
		var l := UIStyle.label("\n".join(lines), true, UITokens.FONT_MICRO)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_mastery_box.add_child(l)
	var spend := HBoxContainer.new()
	spend.add_theme_constant_override("separation", UITokens.SP_3)
	for n in [1, 5, 25]:
		var b := UIStyle.mini_button("+%d mastery" % n, "Spend pool XP to raise this activity by %d levels" % n)
		var count: int = n
		var preview: Dictionary = MasteryManager.spend_preview(_skill_id, _selected_action, n)
		b.tooltip_text = "Cost %s pool XP; pool %.1f%% → %.1f%%. Lost bonuses: %s" % [UIStyle.fmt(float(preview.cost)), float(preview.before), float(preview.after), UIStyle.describe_modifier_table(preview.lost)]
		b.disabled = float(preview.cost) <= 0 or MasteryManager.get_pool_xp(_skill_id) < float(preview.cost)
		b.pressed.connect(func():
			var spent: float = MasteryManager.spend_pool_xp_for_levels(_skill_id, _selected_action, count)
			if spent <= 0.0:
				EventBus.notify("Not enough pool XP.", "warn")
			else:
				EventBus.notify("Spent %s pool XP on %s." % [UIStyle.fmt(spent),
					str(DataLoader.get_action(_skill_id, _selected_action).get("name", ""))], "success")
			refresh())
		spend.add_child(b)
	_mastery_box.add_child(spend)

func _rebuild_modifiers() -> void:
	_clear(_mods_box)
	var keys: Array[String] = [
		ModifierKeys.skill_key(_skill_id, ModifierKeys.SUFFIX_SKILL_XP_PERCENT),
		ModifierKeys.skill_key(_skill_id, ModifierKeys.SUFFIX_INTERVAL_PERCENT),
		ModifierKeys.skill_key(_skill_id, ModifierKeys.SUFFIX_INTERVAL_FLAT),
		ModifierKeys.skill_key(_skill_id, ModifierKeys.SUFFIX_DOUBLING_PERCENT),
		ModifierKeys.skill_key(_skill_id, ModifierKeys.SUFFIX_PRESERVATION_PERCENT),
		ModifierKeys.skill_key(_skill_id, ModifierKeys.SUFFIX_RESOURCE_FLAT),
		ModifierKeys.GLOBAL_SKILL_XP_PERCENT,
		ModifierKeys.BANK_SPACE_FLAT,
	]
	var any: bool = false
	for key in keys:
		var v: float = ModifierManager.get_modifier(key)
		if absf(v) < 0.0001:
			continue
		any = true
		_mods_box.add_child(Widgets.key_value(key.replace("_", " ").capitalize(),
			UIStyle.describe_modifier(key, v), UITokens.PURPLE,
			"Combined from all active sources"))
	if not any:
		_mods_box.add_child(UIStyle.label("No bonuses are currently modifying this skill. Equipment, rites, potions, companions and Starreading all register here.",
			true, UITokens.FONT_SMALL))
	_mods_box.add_child(UIStyle.label("Bonuses are bounded and always explained: the action time floor is 0.25s and preservation cannot exceed 100%%.",
		true, UITokens.FONT_MICRO))

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _add_forecast_details(est: Dictionary, action: Dictionary) -> void:
	var box := UIStyle.section("Planning")
	_selected_box.add_child(box)
	if float(est.node_overhead) > 0: box.add_child(Widgets.key_value("Expected node downtime / action", "%.2fs" % float(est.node_overhead)))
	if float(est.stun_overhead) > 0: box.add_child(Widgets.key_value("Expected stun / attempt", "%.2fs" % float(est.stun_overhead)))
	if float(est.gp_per_hour) > 0: box.add_child(Widgets.key_value("Sustainable GP / hour", UIStyle.fmt(float(est.gp_per_hour)), UITokens.GOLD))
	if not est.next_unlock.is_empty(): box.add_child(UIStyle.label("Next unlock: %s · Lv %d · ≈ %s at this rate" % [est.next_unlock.name, int(est.next_unlock.level), UIStyle.fmt_duration(float(est.next_unlock.seconds))], true, UITokens.FONT_SMALL))
	var quantity: int = _target_for_index()
	if quantity <= 0: quantity = 1
	var batch: Dictionary = ActionEstimates.batch(_skill_id, _selected_action, quantity)
	box.add_child(UIStyle.label("%d successful actions · ≈ %s · preservation %.1f%% · doubling %.1f%%" % [quantity, UIStyle.fmt_duration(float(batch.seconds)), float(est.preservation_chance) * 100, float(est.doubling_chance) * 100], true, UITokens.FONT_SMALL))
	for id in batch.inputs: box.add_child(Widgets.key_value(str(DataLoader.get_item(str(id)).get("name", id)), "≈ %.1f used / %d owned" % [float(batch.inputs[id]), BankManager.get_count(str(id))]))
	if str(batch.bottleneck) != "": box.add_child(UIStyle.label("Material bottleneck: " + str(batch.bottleneck) + ". Estimates include failed attempts; quantity counts successful actions.", true, UITokens.FONT_MICRO))
	if _skill_id == "inscription":
		box.add_child(UIStyle.label("Research prerequisite: " + str(action.get("requires_research", "none")), true, UITokens.FONT_SMALL))
		if action.has("quality_product"):
			var odds: Dictionary = InscriptionManager.quality_odds(_selected_action)
			box.add_child(UIStyle.label("Faded %.1f%% · Inked %.1f%% · Illuminated %.1f%%" % [float(odds.faded) * 100, float(odds.inked) * 100, float(odds.illuminated) * 100], true, UITokens.FONT_SMALL))
	if _skill_id == "corruption": box.add_child(UIStyle.label("Produces Abyssal Essence; consumes no materials and deals no self-damage. Mastery 25/99 grants damage reduction while this action is active. Spending time here replaces combat training.", true, UITokens.FONT_SMALL))
	var identities: Dictionary = {"echo_keeping": "Choose the support echo you need; follow its input sources before committing.", "wayfolding": "Choose a route supply chain: produce maps first, then turn them into travel support.", "fermentation": "Choose a useful fermentation product, then collect its required cultures and ingredients.", "customcraft": "Compare commission rewards with failure losses. Higher rewards can consume more supplies.", "lostfinding": "Choose a case's final reward and work backwards through its search inputs."}
	if identities.has(_skill_id):
		box.add_child(UIStyle.label(str(identities[_skill_id]), true, UITokens.FONT_SMALL))
		for id in action.get("output_items", {}):
			var reward_id: String = str(id)
			var target_reward := UIStyle.mini_button("Target " + str(DataLoader.get_item(reward_id).get("name", reward_id)), "Pin this reward and its supply chain")
			target_reward.clip_text = true
			target_reward.pressed.connect(func(): Goals.pin("item", reward_id, 1))
			box.add_child(target_reward)
			for input_id in action.get("input_items", {}):
				var supply_id: String = str(input_id)
				var source_button := UIStyle.mini_button("Find " + str(DataLoader.get_item(supply_id).get("name", supply_id)), "Track the required ingredient and its production routes")
				source_button.clip_text = true
				source_button.pressed.connect(func(): Goals.pin("item", supply_id, int(action.input_items[supply_id])))
				box.add_child(source_button)
			var consumers: Array = []
			for sid in DataLoader.get_skill_ids():
				for recipe in DataLoader.get_skill_actions(str(sid)):
					if recipe.get("input_items", {}).has(id): consumers.append(str(recipe.get("name", "")))
			box.add_child(UIStyle.label("Used for: " + (", ".join(consumers.slice(0, 5)) if not consumers.is_empty() else str(DataLoader.get_item(str(id)).get("description", "Final reward; sell or keep in Storage."))), true, UITokens.FONT_MICRO))
	box.add_child(UIStyle.label(str(est.assumptions), true, UITokens.FONT_MICRO))
