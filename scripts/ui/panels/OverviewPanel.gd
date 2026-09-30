extends VBoxContainer
## OverviewPanel — the dashboard that answers "what should I do now?".
##
## Sections, in the order the brief lists them: current activity, tracked goals, skill
## highlights, loadout readiness, newly available unlocks, recent events, and suggested next
## steps. Every suggestion is derived from live state (Goals.suggestions), never from a
## rotating tip list, and every card links to the screen that resolves it.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _activity_box: VBoxContainer
## First-run guidance sits directly above the suggestions: on a genuinely new character this is
## the first thing on the screen that says what to do, and it retires itself into one friendly line
## once the steps are done. It is a section, not a modal, so the first action is never blocked.
var _tutorial_box: VBoxContainer
var _goals_box: VBoxContainer
var _suggest_box: VBoxContainer
var _unlocks_box: VBoxContainer
var _skills_box: VBoxContainer
var _loadout_box: VBoxContainer
var _events_box: VBoxContainer
## Overview is a hub: a wrapping strip of sub-tabs (the dashboard, then every skill) sits above two
## exclusive content areas. Skill tabs deliberately show a COMPACT card rather than a second copy of
## the full skills screen, so the two cannot drift apart.
var _tabs_root: HFlowContainer
var _tab_buttons: Array[Button] = []
var _tab_ids: Array[String] = []
var _skill_menu: OptionButton
var _active_tab: String = ""
var _dashboard_grid: GridContainer
var _dashboard: VBoxContainer
var _skill_box: VBoxContainer
var _stats_box: VBoxContainer
## Live XP readout for the open skill sub-tab. Cached on rebuild, polled per frame for the same
## reason as SkillsPanel: the header must not wait for a level-up or a screen change to move.
var _xp_bar: ProgressBar = null
var _xp_bar_text: Label = null
var _xp_remaining: Label = null
var _xp_skill_id: String = ""
var _xp_level_shown: int = -1
var _log: Dictionary = Widgets.event_log(80)
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	EventBus.notification.connect(_on_notification)
	EventBus.skill_level_up.connect(_on_level_up)
	EventBus.mastery_level_up.connect(_on_mastery)
	EventBus.goal_changed.connect(refresh)
	EventBus.state_refreshed.connect(refresh)
	EventBus.quest_reward_claimed.connect(func(_q): refresh())
	EventBus.activity_changed.connect(refresh)
	EventBus.bank_changed.connect(_refresh_unlocks_light)
	refresh()

func _build() -> void:
	_built = true
	_build_tabs()
	_dashboard = UIStyle.vbox(UITokens.SP_4)
	add_child(_dashboard)
	_skill_box = UIStyle.vbox(UITokens.SP_3)
	add_child(_skill_box)
	_skill_box.visible = false
	# Getting started goes first, above "Current activity": on a brand-new character the activity
	# card is an Idle 0.0% placeholder, and guidance under it would be one scroll too low.
	_tutorial_box = _section("Getting started", "one step at a time — it moves on by itself")
	_activity_box = _section("Current activity")
	_goals_box = _section("Tracked goals", "pin anything with the Track button")
	_suggest_box = _section("Suggested next steps", "derived from your actual progress")
	_unlocks_box = _section("Newly available")
	_skills_box = _section("Closest levels", "smallest gaps first")
	_loadout_box = _section("Combat readiness")
	_events_box = _section("Recent events")
	_stats_box = _section("Journey")
	resized.connect(_update_dashboard_columns)
	_update_dashboard_columns()

func _build_tabs() -> void:
	_tab_ids = [""]
	_tabs_root = HFlowContainer.new()
	_tabs_root.add_theme_constant_override("h_separation", UITokens.SP_4)
	_tabs_root.add_theme_constant_override("v_separation", UITokens.SP_3)
	add_child(_tabs_root)
	var dashboard_button := UIStyle.primary_button("Dashboard")
	dashboard_button.toggle_mode = true
	dashboard_button.button_pressed = true
	dashboard_button.pressed.connect(func(): _select_tab(""))
	_tabs_root.add_child(dashboard_button)
	_tab_buttons = [dashboard_button]
	_skill_menu = OptionButton.new()
	_skill_menu.custom_minimum_size = Vector2(220, UITokens.H_HEADER)
	_skill_menu.clip_text = true
	_skill_menu.fit_to_longest_item = false
	_skill_menu.add_item("Browse a skill")
	for category in ["combat", "non_combat"]:
		_skill_menu.add_separator("Combat" if category == "combat" else "Non-combat")
		_tab_ids.append("")
		for skill_id in DataLoader.get_skill_ids():
			var skill: Dictionary = DataLoader.get_skill(skill_id)
			if str(skill.get("category", "")) != category:
				continue
			_skill_menu.add_item("%s · Lv %d" % [skill.get("name", skill_id), PlayerData.get_level(skill_id)])
			_tab_ids.append(skill_id)
	_skill_menu.item_selected.connect(func(i): _select_tab(_tab_ids[i]))
	_tabs_root.add_child(_skill_menu)

## Skill names carry their level so the strip is a progress readout, not just navigation.
func _tab_labels() -> Array[String]:
	var out: Array[String] = ["Dashboard"]
	for skill_id in DataLoader.get_skill_ids():
		out.append("%s %d" % [str(DataLoader.get_skill(skill_id).get("name", skill_id)),
			PlayerData.get_level(skill_id)])
	return out

func _update_tab_labels() -> void:
	for i in range(1, _tab_ids.size()):
		var skill_id: String = _tab_ids[i]
		if skill_id == "":
			continue
		_skill_menu.set_item_text(i, "%s · Lv %d" % [DataLoader.get_skill(skill_id).get("name", skill_id), PlayerData.get_level(skill_id)])

func _select_tab(skill_id: String) -> void:
	_active_tab = skill_id
	_dashboard.visible = skill_id == ""
	_skill_box.visible = skill_id != ""
	_tab_buttons[0].button_pressed = skill_id == ""
	_skill_menu.select(maxi(0, _tab_ids.find(skill_id)))
	refresh()

const RECENT_EVENT_LIMIT: int = 40

func _section(title: String, hint := "") -> VBoxContainer:
	var s := UIStyle.vbox(UITokens.SP_3)
	s.set_meta("section_title", title)
	s.set_meta("section_hint", hint)
	if title in ["Getting started", "Current activity"]:
		_dashboard.add_child(s)
	else:
		if _dashboard_grid == null:
			_dashboard_grid = GridContainer.new()
			_dashboard_grid.add_theme_constant_override("h_separation", UITokens.SP_5)
			_dashboard_grid.add_theme_constant_override("v_separation", UITokens.SP_5)
			_dashboard.add_child(_dashboard_grid)
		var card := UIStyle.panel()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(s)
		_dashboard_grid.add_child(card)
	return s

func _update_dashboard_columns() -> void:
	if _dashboard_grid != null:
		_dashboard_grid.columns = 2 if size.x >= 760 else 1

# =========================================================================
#  Refresh
# =========================================================================

func refresh() -> void:
	if not _built:
		return
	_update_tab_labels()
	# A skill sub-tab owns the screen while it is open: rebuilding the eight dashboard sections
	# underneath it would be work nobody can see.
	if _active_tab != "":
		_rebuild_skill_card(_active_tab)
		return
	# Highlighted quest guidance first when something is ready to claim.
	TutorialManager.next_step()
	_rebuild_tutorial()
	_rebuild_activity()
	_rebuild_goals()
	_rebuild_suggestions()
	_rebuild_unlocks()
	_rebuild_skills()
	_rebuild_loadout()
	_rebuild_events()
	_rebuild_stats()

## key_value() returns an HBox of [key Label, value Label]; the value is the one we rewrite.
func _value_label_of(row: Control) -> Label:
	if row == null or row.get_child_count() < 2:
		return null
	return row.get_child(1) as Label

## Live XP for the open skill sub-tab. Polled from the authoritative PlayerData state, so the
## number on screen is the number the simulation awarded rather than a snapshot from page load.
func _process(_delta: float) -> void:
	# is_instance_valid, not != null: _clear() uses queue_free(), so a node freed by the last
	# rebuild is still a non-null reference for the rest of that frame.
	if not is_instance_valid(_xp_bar) or not is_instance_valid(_xp_bar_text) or _xp_skill_id == "":
		return
	var xp: float = PlayerData.get_xp(_xp_skill_id)
	var level: int = PlayerData.get_level(_xp_skill_id)
	# A level change re-derives the maximum, the label and the cap notice: let the rebuild do it.
	if level != _xp_level_shown:
		return
	_xp_bar.value = clampf(XPTable.level_progress(xp, level), 0.0, 1.0)
	var next_level: int = mini(level + 1, XPTable.MAX_LEVEL)
	if _xp_bar_text != null:
		_xp_bar_text.text = "%s / %s" % [UIStyle.fmt_exact(xp),
			UIStyle.fmt_exact(float(XPTable.xp_for_level(next_level)))]
	if _xp_remaining != null:
		_xp_remaining.text = UIStyle.fmt_exact(float(XPTable.xp_to_next_level(xp, level)))

func _clear(box: VBoxContainer) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	if box.has_meta("section_title"):
		box.add_child(UIStyle.section(str(box.get_meta("section_title")), str(box.get_meta("section_hint"))))

## The compact per-skill summary a sub-tab shows. It answers "where am I with this, what can I do
## next, and what would it earn me", then hands off to the full screen for the recipe detail.
func _rebuild_skill_card(skill_id: String) -> void:
	_clear(_skill_box)
	var skill: Dictionary = DataLoader.get_skill(skill_id)
	var skill_name: String = str(skill.get("name", skill_id))
	var level: int = PlayerData.get_level(skill_id)
	var xp: float = PlayerData.get_xp(skill_id)
	var next_level: int = mini(level + 1, XPTable.MAX_LEVEL)
	var at_cap: bool = level >= PlayerData.get_level_cap(skill_id)

	_skill_box.add_child(UIStyle.section(skill_name, "%s — level %d of %d" % [
		str(skill.get("category", "skill")).capitalize(), level,
		PlayerData.get_level_cap(skill_id)]))
	_skill_box.add_child(UIStyle.title("%s — level %d" % [skill_name, level], UITokens.FONT_HEAD))
	_skill_box.add_child(UIStyle.label(str(skill.get("description", "")), true, UITokens.FONT_MICRO))
	var bar := Widgets.progress_bar(XPTable.level_progress(xp, level), 1.0, UITokens.GOLD,
		"%s / %s" % [UIStyle.fmt_exact(xp), UIStyle.fmt_exact(float(XPTable.xp_for_level(next_level)))], 16,
		"Level %d progress" % level)
	_skill_box.add_child(bar)
	_xp_bar = bar
	_xp_bar_text = bar.get_child(0) as Label if bar.get_child_count() > 0 else null
	_xp_skill_id = skill_id
	_xp_level_shown = level
	if at_cap:
		_skill_box.add_child(UIStyle.colored_label(
			"This skill is at its level cap. Activity mastery and gear are still worth raising.",
			UITokens.GOLD, UITokens.FONT_SMALL))
	else:
		var to_next_row := Widgets.key_value("XP to level %d" % next_level,
			UIStyle.fmt_exact(float(XPTable.xp_to_next_level(xp, level))), UITokens.GOLD,
			"Level cap in your game mode: %d" % PlayerData.get_level_cap(skill_id))
		_skill_box.add_child(to_next_row)
		_xp_remaining = _value_label_of(to_next_row)
	_skill_box.add_child(Widgets.key_value("Activities", "%d total · %d unlocked at level %d" % [
		DataLoader.get_action_count(skill_id),
		DataLoader.get_unlocked_action_count(skill_id, level), level],
		UITokens.TEXT, "Unlocks are driven by skill level, not by mastery"))
	_skill_box.add_child(Widgets.key_value("Mastery pool", "%.1f%%" % MasteryManager.get_pool_percent(skill_id),
		UITokens.PURPLE, "Pool XP can be spent to raise any activity's mastery on this skill"))
	_skill_box.add_child(Widgets.key_value("Total mastery levels",
		UIStyle.fmt_exact(MasteryManager.get_skill_total_mastery_levels(skill_id)), UITokens.PURPLE,
		"Summed across every activity on this skill"))

	_skill_box.add_child(UIStyle.section("Best activity you can run now"))
	var best: Dictionary = _best_unlocked_action(skill_id, level)
	if best.is_empty():
		_skill_box.add_child(UIStyle.label(
			"Nothing is unlocked yet. Raise this skill to open its first activities.",
			true, UITokens.FONT_SMALL))
	else:
		var action_id: String = str(best.get("id", ""))
		_skill_box.add_child(UIStyle.label("%s  ·  needs level %d" % [
			str(best.get("name", action_id)), int(best.get("level_required", 1))],
			false, UITokens.FONT_BODY))
		var est: Dictionary = ActionEstimates.for_action(skill_id, action_id)
		_skill_box.add_child(UIStyle.label(ActionEstimates.summary_line(skill_id, action_id),
			true, UITokens.FONT_SMALL))
		if float(est.get("supply_hours", -1.0)) >= 0.0:
			_skill_box.add_child(UIStyle.colored_label(
				"Your current stock lasts about %s at this rate." % UIStyle.fmt_duration(
					float(est["supply_hours"]) * 3600.0),
				UITokens.AMBER, UITokens.FONT_MICRO))

	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", UITokens.SP_3)
	actions.add_theme_constant_override("v_separation", UITokens.SP_2)
	var open := UIStyle.primary_button("Open full skill",
		"Open the Skills screen on %s for every recipe, material and modifier" % skill_name)
	var target: String = skill_id
	open.pressed.connect(func(): navigated.emit({"screen": Screens.SKILLS, "skill_id": target}))
	actions.add_child(open)
	var pin := UIStyle.mini_button("Track level goal", "Pin 'reach level X in %s' as a goal" % skill_name)
	pin.pressed.connect(func():
		Goals.pin("skill", target, next_level)
		EventBus.notify("Tracking level %d in %s." % [next_level, skill_name], "success"))
	actions.add_child(pin)
	_skill_box.add_child(actions)

## The highest-level action the player has actually unlocked: the most relevant thing to point at,
## rather than whatever happens to be first in the table.
func _best_unlocked_action(skill_id: String, level: int) -> Dictionary:
	var best: Dictionary = {}
	var best_level: int = -1
	for action in DataLoader.get_skill_actions(skill_id):
		if typeof(action) != TYPE_DICTIONARY:
			continue
		var needed: int = int(action.get("level_required", 1))
		if needed > level or needed < best_level:
			continue
		best = action
		best_level = needed
	return best

## First-run guidance. One card, the step the player is actually on, and a button that goes
## where the step says. When every step is done the whole section collapses to a single line
## rather than disappearing: "you finished this" is worth saying once, and the player is on a
## screen that rebuilds, so an empty gap reads as a bug.
func _rebuild_tutorial() -> void:
	_clear(_tutorial_box)
	if TutorialManager.step_count() <= 0:
		_tutorial_box.set_meta("section_hint", "no guidance authored")
		_tutorial_box.add_child(UIStyle.label("No onboarding content is loaded.", true, UITokens.FONT_SMALL))
		return
	if TutorialManager.is_finished():
		_tutorial_box.set_meta("section_hint", "all done")
		_tutorial_box.add_child(UIStyle.colored_label(
			"You have been through the beginning. The sections below will keep working out what to do next.",
			UITokens.GREEN, UITokens.FONT_SMALL))
		return
	var step: Dictionary = TutorialManager.describe(TutorialManager.current_index())
	if step.is_empty():
		return
	_tutorial_box.set_meta("section_hint", "step %d of %d" % [int(step["index"]) + 1, TutorialManager.step_count()])
	var card := UIStyle.card(true)
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", UITokens.SP_3)
	head.add_theme_constant_override("v_separation", UITokens.SP_2)
	head.add_child(UIStyle.label(str(step["title"]), false, UITokens.FONT_SUBHEAD))
	head.add_child(Widgets.badge("Step %d of %d" % [int(step["index"]) + 1, TutorialManager.step_count()], UITokens.GOLD))
	col.add_child(head)
	var body := UIStyle.label(str(step["body"]), true, UITokens.FONT_SMALL)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	var cond: Dictionary = step.get("condition", {})
	if not cond.is_empty():
		col.add_child(Widgets.progress_bar(float(cond["current"]), float(cond["required"]),
			UITokens.TEAL,
			"%s / %s" % [UIStyle.fmt(float(cond["current"])), UIStyle.fmt(float(cond["required"]))], 10,
			str(cond["label"])))
	var route: Dictionary = step.get("route", {})
	if not route.is_empty():
		var go := UIStyle.primary_button("Take me there",
			"Open the screen this step points at: %s" % str(cond.get("label", "next objective")))
		var r: Dictionary = route
		go.pressed.connect(func(): navigated.emit(r))
		col.add_child(go)
	_tutorial_box.add_child(card)

func _rebuild_activity() -> void:
	_clear(_activity_box)
	var activity: Dictionary = GameManager.current_activity()
	var card := UIStyle.card(true)
	var col := UIStyle.vbox(UITokens.SP_3)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITokens.SP_4)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(UITokens.ICON_LG, UITokens.ICON_LG)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	match str(activity.get("kind", "idle")):
		"skill":
			icon.texture = AssetRegistry.skill_icon(str(activity.get("id", "")))
		"combat":
			icon.texture = AssetRegistry.monster_sprite(CombatManager.current_monster_id)
		_:
			icon.texture = AssetRegistry.icon("skills", "mining")
	head.add_child(icon)
	var text := UIStyle.vbox(UITokens.SP_1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UIStyle.label(str(activity.get("label", "Idle")), false, UITokens.FONT_SUBHEAD))
	text.add_child(UIStyle.label(str(activity.get("detail", "")), true, UITokens.FONT_SMALL))
	head.add_child(text)
	col.add_child(head)
	var progress: float = float(activity.get("progress", 0.0))
	col.add_child(Widgets.progress_bar(progress, 1.0,
		UITokens.RED if str(activity.get("kind", "")) == "combat" else UITokens.TEAL,
		UIStyle.fmt_percent(progress), 14))
	var kind: String = str(activity.get("kind", "idle"))
	if kind == "skill":
		var est: Dictionary = ActionEstimates.for_action(str(activity.get("id", "")), str(activity.get("action_id", "")))
		if not est.is_empty():
			col.add_child(Widgets.key_value("Projection",
				"≈ %s XP/h · ≈ %s %s/h" % [UIStyle.fmt(float(est["xp_per_hour"])),
					UIStyle.fmt(float(est.get("output_per_hour", 0.0))), str(est.get("output_name", ""))],
				UITokens.TEAL, "Assumptions: %s" % str(est["assumptions"])))
			if float(est.get("supply_hours", -1.0)) >= 0.0:
				col.add_child(Widgets.key_value("Stock lasts about",
					UIStyle.fmt_duration(float(est["supply_hours"])), UITokens.AMBER,
					"At the current rate with no interruptions"))
			col.add_child(Widgets.key_value("Time to next level (≈)",
				UIStyle.fmt_duration(float(est["hours_to_next_level"]) * 3600.0), UITokens.GOLD))
	elif kind == "combat":
		var cmp: Dictionary = CombatManager.target_comparison()
		if not cmp.is_empty():
			col.add_child(Widgets.key_value("Target", "%s (Lv %d · %s, max hit %d)" % [
				str(cmp["monster_name"]), int(cmp["monster_level"]), str(cmp["monster_damage_type"]),
				int(cmp["monster_max_hit"])]))
			col.add_child(Widgets.key_value("Your hit chance", UIStyle.fmt_percent(float(cmp["your_hit_chance_percent"]) / 100.0), UITokens.TEAL))
			col.add_child(Widgets.key_value("Their hit chance", UIStyle.fmt_percent(float(cmp["their_hit_chance_percent"]) / 100.0), UITokens.RED))
	elif kind == "stopped":
		var reason := UIStyle.label(str(activity.get("detail", "")), true, UITokens.FONT_SMALL)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(reason)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UITokens.SP_3)
	if kind != "idle" and kind != "stopped":
		var stop := UIStyle.danger_button("Retreat" if kind == "combat" else "Stop")
		stop.pressed.connect(func():
			if CombatManager.state != CombatManager.State.IDLE:
				CombatManager.stop_combat("retreat")
			else:
				SkillManager.stop_action(SkillManager.StopReason.PLAYER)
			refresh())
		actions.add_child(stop)
	var open := UIStyle.primary_button("Open this activity")
	open.pressed.connect(func(): navigated.emit({
		"screen": Screens.SKILLS if kind == "skill" else (Screens.EXPEDITIONS if CombatManager.is_expedition(str(activity.get("id", ""))) else Screens.COMBAT),
		"skill_id": str(activity.get("id", "")),
		"action_id": str(activity.get("action_id", "")),
		"area_id": str(activity.get("id", "")) if kind == "combat" else "",
	}))
	actions.add_child(open)
	col.add_child(actions)
	_activity_box.add_child(card)

func _rebuild_goals() -> void:
	_clear(_goals_box)
	if Goals.pinned.is_empty():
		var hint := UIStyle.label("Nothing tracked. Track an item, recipe, skill level, task or structure and this panel will work out exactly what it needs.",
			true, UITokens.FONT_SMALL)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_goals_box.add_child(hint)
		return
	for goal in Goals.pinned:
		var resolved: Dictionary = Goals.resolve(goal)
		var card := UIStyle.card(bool(resolved.get("complete", false)))
		var col := UIStyle.vbox(UITokens.SP_2)
		card.add_child(col)
		var head := HFlowContainer.new()
		head.add_theme_constant_override("h_separation", UITokens.SP_3)
		head.add_theme_constant_override("v_separation", UITokens.SP_2)
		var g: Dictionary = goal
		var title := UIStyle.label(str(resolved.get("label", g.get("id", ""))), false, UITokens.FONT_BODY)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not bool(resolved.get("ok", true)):
			title.add_theme_color_override("font_color", UITokens.AMBER)
		head.add_child(title)
		head.add_child(Widgets.badge(str(g.get("kind", "")), UITokens.BLUE))
		var open := UIStyle.mini_button("Explain")
		open.pressed.connect(func(): context_changed.emit({"kind": "goal", "goal": g}))
		head.add_child(open)
		var untrack := UIStyle.mini_button("Untrack")
		untrack.pressed.connect(func():
			Goals.unpin(str(g.get("kind", "")), str(g.get("id", "")))
			refresh())
		head.add_child(untrack)
		col.add_child(head)
		if bool(resolved.get("ok", false)):
			col.add_child(Widgets.progress_bar(float(resolved.get("progress_current", 0)),
				maxf(1.0, float(resolved.get("progress_required", 1))),
				UITokens.GOLD if bool(resolved.get("complete", false)) else UITokens.TEAL,
				"%s / %s" % [UIStyle.fmt(float(resolved.get("progress_current", 0))),
					UIStyle.fmt(float(resolved.get("progress_required", 1)))], 12))
			var problem: String = str(resolved.get("problem", ""))
			if problem != "":
				col.add_child(UIStyle.colored_label(problem, UITokens.RED, UITokens.FONT_MICRO))
			# The one-blocking-requirement summary is what makes a pinned goal useful at a glance.
			var blocking: Array = []
			for req in resolved.get("requirements", []):
				if not bool(req.get("satisfied", false)):
					blocking.append(str(req.get("label", "")))
			if blocking.is_empty():
				col.add_child(UIStyle.colored_label("All requirements met.", UITokens.GREEN, UITokens.FONT_MICRO))
			else:
				var l := UIStyle.label("Missing: " + "; ".join(blocking.slice(0, 3)), true, UITokens.FONT_MICRO)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				col.add_child(l)
		else:
			col.add_child(UIStyle.colored_label(str(resolved.get("problem", "Unresolvable goal")), UITokens.AMBER, UITokens.FONT_MICRO))
		_goals_box.add_child(card)

func _rebuild_suggestions() -> void:
	_clear(_suggest_box)
	var suggestions: Array = Goals.suggestions(6)
	if suggestions.is_empty():
		_suggest_box.add_child(UIStyle.label("No obvious next step — pick a skill and explore.", true, UITokens.FONT_SMALL))
		return
	for s in suggestions:
		var card := UIStyle.card()
		# Flows rather than a plain HBox: on a narrow window the action buttons drop to the next
		# line instead of forcing the panel wider than the window.
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", UITokens.SP_4)
		row.add_theme_constant_override("v_separation", UITokens.SP_2)
		card.add_child(row)
		if str(s.get("icon_id", "")) != "":
			var icon := TextureRect.new()
			icon.texture = AssetRegistry.icon(str(s["icon_kind"]), str(s["icon_id"]))
			icon.custom_minimum_size = Vector2(48, 48)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(icon)
		var col := UIStyle.vbox(UITokens.SP_1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UIStyle.label(str(s.get("label", "")), false, UITokens.FONT_BODY))
		var why := UIStyle.label(str(s.get("reason", "")), true, UITokens.FONT_MICRO)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(why)
		row.add_child(col)
		var go := UIStyle.primary_button("Go")
		var route: Dictionary = s.get("route", {})
		go.pressed.connect(func(): navigated.emit(route))
		row.add_child(go)
		if s.has("goal"):
			var goal: Dictionary = s["goal"]
			var track := UIStyle.mini_button("Track")
			track.pressed.connect(func():
				Goals.pin(str(goal.get("kind", "")), str(goal.get("id", "")), int(goal.get("level", 0)))
				refresh())
			row.add_child(track)
		_suggest_box.add_child(card)

func _rebuild_unlocks() -> void:
	_clear(_unlocks_box)
	var found: bool = false
	# Unclaimed completed tasks.
	for quest_id in Quests.all_quest_ids():
		if Quests.is_complete(quest_id) and not Quests.is_claimed(quest_id):
			found = true
			_unlocks_box.add_child(_unlock_row("Task reward ready",
				str(Quests.get_quest(quest_id).get("name", quest_id)),
				"Claim %s" % Quests.describe_reward(Quests.get_quest(quest_id).get("reward", {})),
				{"screen": Screens.QUESTS, "quest_id": quest_id}, UITokens.GOLD))
	# Newly unlocked activities at exactly the current level.
	for skill_id in DataLoader.get_skill_ids():
		var level: int = PlayerData.get_level(skill_id)
		for a in DataLoader.get_skill_actions(skill_id):
			if int(a.get("level_required", 1)) != level:
				continue
			found = true
			_unlocks_box.add_child(_unlock_row("New activity",
				"%s · %s" % [DataLoader.get_skill(skill_id).get("name", skill_id), str(a.get("name", ""))],
				"Unlocked at level %d" % level,
				{"screen": Screens.SKILLS, "skill_id": skill_id, "action_id": str(a.get("id", ""))}, UITokens.TEAL))
	# Affordable upgrades.
	for upgrade_id in DataLoader.shop.keys():
		if not bool(ShopManager.can_buy(upgrade_id)["ok"]):
			continue
		found = true
		var u: Dictionary = DataLoader.shop[upgrade_id]
		_unlocks_box.add_child(_unlock_row("Affordable upgrade",
			str(u.get("name", upgrade_id)),
			"%s GP · %s" % [UIStyle.fmt(float(u.get("cost", 0))), str(u.get("description", ""))],
			{"screen": Screens.PROVISIONER}, UITokens.BLUE))
	# Affordable structures.
	for building_id in DataLoader.township_buildings.keys():
		var b: Dictionary = DataLoader.township_buildings[building_id]
		var afford: bool = true
		for res_id in (b.get("cost", {}) as Dictionary).keys():
			if float(TownshipManager.resources.get(res_id, 0.0)) < float(b["cost"][res_id]):
				afford = false
				break
		if not afford:
			continue
		found = true
		_unlocks_box.add_child(_unlock_row("Structure affordable",
			str(b.get("name", building_id)),
			"Ready to build in Emberreach", {"screen": Screens.SETTLEMENT}, UITokens.TEAL))
	# Overflow items waiting.
	if BankManager.has_overflow():
		found = true
		_unlocks_box.add_child(_unlock_row("Storage full",
			"%d items waiting in overflow" % BankManager.overflow_count(),
			"Expand storage or clear space to withdraw them", {"screen": Screens.BANK}, UITokens.AMBER))
	if not found:
		_unlocks_box.add_child(UIStyle.label("Nothing new right now. Keep training — unlocks appear here the moment they land.",
			true, UITokens.FONT_SMALL))

func _unlock_row(kind: String, title: String, detail: String, route: Dictionary, color: Color) -> Control:
	var card := UIStyle.card(color == UITokens.GOLD)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UITokens.SP_4)
	row.add_theme_constant_override("v_separation", UITokens.SP_2)
	card.add_child(row)
	var icon := UIStyle.icon_texture("skills", str(route.get("skill_id", "woodcutting")))
	if not route.has("skill_id"):
		icon.texture = AssetRegistry.icon("currencies", "gp")
	icon.custom_minimum_size = Vector2(40, 40)
	row.add_child(icon)
	row.add_child(Widgets.badge(kind, color))
	var col := UIStyle.vbox(UITokens.SP_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIStyle.label(title, false, UITokens.FONT_SMALL))
	var d := UIStyle.label(detail, true, UITokens.FONT_MICRO)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(d)
	row.add_child(col)
	var go := UIStyle.mini_button("Go")
	var r: Dictionary = route
	go.pressed.connect(func(): navigated.emit(r))
	row.add_child(go)
	return card

func _rebuild_skills() -> void:
	_clear(_skills_box)
	var entries: Array = []
	for skill_id in DataLoader.get_skill_ids():
		var level: int = PlayerData.get_level(skill_id)
		if level >= XPTable.MAX_LEVEL:
			continue
		var xp: float = PlayerData.get_xp(skill_id)
		var needed: float = float(XPTable.xp_to_next_level(xp, level))
		entries.append({"skill_id": skill_id, "level": level, "needed": needed,
			"progress": XPTable.level_progress(xp, level)})
	entries.sort_custom(func(a, b): return float(a["progress"]) > float(b["progress"]))
	for e in entries.slice(0, 5):
		var skill_id: String = str(e["skill_id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITokens.SP_4)
		var icon := TextureRect.new()
		icon.texture = AssetRegistry.skill_icon(skill_id)
		icon.custom_minimum_size = Vector2(UITokens.ICON_SM, UITokens.ICON_SM)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var col := UIStyle.vbox(UITokens.SP_1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UIStyle.label("%s  ·  level %d" % [DataLoader.get_skill(skill_id).get("name", skill_id), int(e["level"])],
			false, UITokens.FONT_SMALL))
		col.add_child(Widgets.progress_bar(float(e["progress"]), 1.0, UITokens.GOLD, "", 8,
			"%s XP to level %d" % [UIStyle.fmt(float(e["needed"])), int(e["level"]) + 1]))
		row.add_child(col)
		row.add_child(UIStyle.colored_label("%s XP" % UIStyle.fmt(float(e["needed"])), UITokens.TEXT_MUTED, UITokens.FONT_MICRO))
		var track := UIStyle.mini_button("Track")
		var sid: String = skill_id
		var next_level: int = int(e["level"]) + 1
		track.pressed.connect(func(): Goals.pin("skill", sid, next_level))
		row.add_child(track)
		_skills_box.add_child(row)

func _rebuild_loadout() -> void:
	_clear(_loadout_box)
	var summary: Dictionary = CombatManager.player_combat_summary()
	var filled: int = 0
	for slot in EquipmentManager.slots.keys():
		if str(EquipmentManager.slots[slot]) != "":
			filled += 1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_5)
	var col := UIStyle.vbox(UITokens.SP_2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Widgets.key_value("Slots filled", "%d of %d" % [filled, EquipmentManager.SLOT_COUNT],
		UITokens.GREEN if filled >= 5 else UITokens.AMBER))
	col.add_child(Widgets.key_value("Max hit", UIStyle.fmt(float(summary["max_hit"])), UITokens.RED))
	col.add_child(Widgets.key_value("Accuracy rating", UIStyle.fmt(float(summary["accuracy"]))))
	col.add_child(Widgets.key_value("Attack interval", "%.2fs" % float(summary["attack_interval"])))
	col.add_child(Widgets.key_value("Damage reduction", UIStyle.fmt_percent(float(summary["damage_reduction"]) / 100.0), UITokens.TEAL))
	var evasion: Dictionary = summary["evasion"]
	col.add_child(Widgets.key_value("Evasion (melee / ranged / magic)",
		"%s / %s / %s" % [UIStyle.fmt(float(evasion["melee"])), UIStyle.fmt(float(evasion["ranged"])), UIStyle.fmt(float(evasion["magic"]))]))
	col.add_child(Widgets.key_value("Active rites", str(PlayerData.active_prayers.size())))
	col.add_child(Widgets.key_value("Active potion", str(DataLoader.get_item(PlayerData.active_potion).get("name", "none")),
		UITokens.TEXT if PlayerData.active_potion != "" else UITokens.TEXT_MUTED,
		"%d charges remaining" % PlayerData.potion_charges))
	var food: int = _food_count()
	col.add_child(Widgets.key_value("Food in store", UIStyle.fmt_exact(float(food)),
		UITokens.GREEN if food > 0 else UITokens.AMBER,
		"Auto-eat tier %d" % int(PlayerData.settings.get("auto_eat_tier", 0))))
	col.add_child(Widgets.key_value("Storage", "%d / %d stacks" % [BankManager.get_used_slots(), BankManager.get_slot_limit()],
		UITokens.AMBER if BankManager.is_full() else UITokens.TEXT))
	row.add_child(col)
	_loadout_box.add_child(row)
	_loadout_box.add_child(UIStyle.label(
		"Readiness is preparation, not reflexes: the fight runs itself once you commit.",
		true, UITokens.FONT_MICRO))

func _food_count() -> int:
	var n: int = 0
	for item_id in BankManager.items.keys():
		if str(DataLoader.get_item(item_id).get("item_type", "")) == "food":
			n += int(BankManager.items[item_id])
	return n

func _rebuild_events() -> void:
	# The log is cached across rebuilds, so lift it out before the clear frees the box's children.
	Widgets.detach(_log["root"])
	_clear(_events_box)
	_events_box.add_child(_log["root"])

func _rebuild_stats() -> void:
	_clear(_stats_box)
	var total_level: int = 0
	for skill_id in DataLoader.get_skill_ids():
		total_level += PlayerData.get_level(skill_id)
	var ready_ach: int = Achievements.ready_count()
	var claimed_ach: int = Achievements.claimed_count()
	var claimed: int = Quests.claimed_count()
	_stats_box.add_child(Widgets.key_value("Playtime", UIStyle.fmt_duration(GameManager.playtime_seconds)))
	_stats_box.add_child(Widgets.key_value("Total skill levels", UIStyle.fmt_exact(float(total_level))))
	_stats_box.add_child(Widgets.key_value("Combat level", str(PlayerData.get_combat_level())))
	_stats_box.add_child(Widgets.key_value("Tasks completed", "%d of %d" % [claimed, Quests.count()]))
	_stats_box.add_child(Widgets.key_value("Milestones", "%d of %d" % [claimed_ach, Achievements.count()],
		UITokens.GOLD_BRIGHT if ready_ach > 0 else UITokens.TEXT,
		"%d ready to claim" % ready_ach if ready_ach > 0 else ""))
	_stats_box.add_child(Widgets.key_value("Items discovered",
		"%d of %d" % [(PlayerData.completion_log.get("items", {}) as Dictionary).size(), DataLoader.items.size()]))
	_stats_box.add_child(Widgets.key_value("Enemies defeated (distinct)",
		"%d of %d" % [(PlayerData.completion_log.get("monsters", {}) as Dictionary).size(), DataLoader.monsters.size()]))
	_stats_box.add_child(Widgets.key_value("Expeditions cleared (distinct)",
		"%d of %d" % [(PlayerData.completion_log.get("dungeons", {}) as Dictionary).size(), DataLoader.dungeons.size()]))
	_stats_box.add_child(Widgets.key_value("Offline time processed",
		UIStyle.fmt_duration(PlayerData.get_stat("offline_seconds_processed")), UITokens.TEXT_MUTED,
		"Total time the simulation has caught up on your behalf"))
	_stats_box.add_child(Widgets.key_value("Defeats", UIStyle.fmt_exact(PlayerData.get_stat("deaths")),
		UITokens.TEXT_MUTED))

# =========================================================================
#  Event log
# =========================================================================

func _on_notification(text: String, kind: String) -> void:
	# The log records the same events the toasts show, so "recent meaningful events" survives
	# after a toast fades.
	var prefix: String = ""
	match kind:
		"success": prefix = "✓ "
		"warn": prefix = "! "
		"error": prefix = "× "
	_log["push"].call(prefix + text)
	if _built and is_inside_tree():
		_rebuild_events()

func _on_level_up(skill_id: String, level: int) -> void:
	_log["push"].call("▲ %s reached level %d" % [DataLoader.get_skill(skill_id).get("name", skill_id), level])
	if _built and is_inside_tree():
		_rebuild_events()

func _on_mastery(skill_id: String, action_id: String, level: int) -> void:
	_log["push"].call("◆ Mastery %d: %s" % [level, DataLoader.get_action(skill_id, action_id).get("name", action_id)])
	if _built and is_inside_tree():
		_rebuild_events()

func _refresh_unlocks_light() -> void:
	if _built and is_inside_tree():
		_rebuild_unlocks()
