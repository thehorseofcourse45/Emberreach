extends VBoxContainer
## OverviewPanel — the dashboard that answers "what should I do now?".
##
## Character progress, current activity and preparation share one dashboard.
## Suggestions and navigation resolve against live game state.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

const EquipmentView = preload("res://scripts/ui/panels/EquipmentPanel.gd")
const UNLOCK_PREVIEW_LIMIT: int = 6

var _summary_box: VBoxContainer
var _summary_grid: GridContainer
var _collection_value: Label
var _activity_meter: ProgressBar
var _activity_progress_text: Label
var _health_bar: ProgressBar
var _health_text: Label
var _activity_detail: Label
var _live_elapsed := 0.0
var _unlock_count := 0
var _show_all_unlocks := false
var _activity_box: VBoxContainer
## First-run guidance shares the grid and hides after onboarding is complete.
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
	EventBus.activity_changed.connect(func(): Widgets.rebuild_once_per_frame(refresh))
	EventBus.bank_changed.connect(func(): Widgets.rebuild_once_per_frame(_refresh_unlocks_light))
	EventBus.item_equipped.connect(func(_slot, _item): Widgets.rebuild_once_per_frame(refresh))
	EventBus.item_unequipped.connect(func(_slot, _item): Widgets.rebuild_once_per_frame(refresh))
	refresh()

func _build() -> void:
	_built = true
	_build_tabs()
	_dashboard = UIStyle.vbox(UITokens.SP_4)
	add_child(_dashboard)
	_skill_box = UIStyle.vbox(UITokens.SP_3)
	add_child(_skill_box)
	_skill_box.visible = false
	var summary_card := UIStyle.panel()
	_summary_box = UIStyle.vbox(UITokens.SP_3)
	summary_card.add_child(_summary_box)
	_dashboard.add_child(summary_card)
	_activity_box = _section("Current activity")
	_tutorial_box = _section("Getting started", "your next first step")
	_loadout_box = _section("Combat readiness", "equipment, health and supplies")
	_goals_box = _section("Tracked goals", "your next milestones")
	_suggest_box = _section("Suggested next steps", "based on your progress")
	_skills_box = _section("Closest levels", "keep your momentum")
	_unlocks_box = _section("Newly available", "rewards, activities and upgrades")
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
	if title == "Current activity":
		_dashboard.add_child(s)
	else:
		if _dashboard_grid == null:
			_dashboard_grid = GridContainer.new()
			_dashboard_grid.add_theme_constant_override("h_separation", UITokens.SP_5)
			_dashboard_grid.add_theme_constant_override("v_separation", UITokens.SP_5)
			_dashboard.add_child(_dashboard_grid)
		var card := UIStyle.panel()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		card.add_child(s)
		_dashboard_grid.add_child(card)
	return s

func _update_dashboard_columns() -> void:
	if _dashboard_grid != null:
		_dashboard_grid.columns = 2 if size.x >= 760 else 1
	if is_instance_valid(_summary_grid):
		_summary_grid.columns = 4 if size.x >= 760 else (2 if size.x >= 360 else 1)

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
	if Widgets.defer_offscreen_rebuild(self, refresh):
		return
	_rebuild_summary()
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
	_live_elapsed += _delta
	if _live_elapsed >= 0.05 and is_visible_in_tree() and _active_tab == "":
		_live_elapsed = 0.0
		_update_live_dashboard()
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

## Onboarding stays available until all steps are complete.
func _rebuild_tutorial() -> void:
	_clear(_tutorial_box)
	_tutorial_box.get_parent().visible = not TutorialManager.is_finished()
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

func _shortcut(text: String, route: Dictionary) -> Button:
	var button := UIStyle.button(text)
	button.pressed.connect(func(): navigated.emit(route))
	return button

func _rebuild_summary() -> void:
	_clear(_summary_box)
	var head := UIStyle.hbox(UITokens.SP_4)
	var emblem := UIStyle.icon_texture("skills", "defence")
	emblem.custom_minimum_size = Vector2(48, 48)
	emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head.add_child(emblem)
	var title := UIStyle.vbox(UITokens.SP_1)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(UIStyle.title("Character overview", UITokens.FONT_HEAD))
	title.add_child(UIStyle.label("Progress, preparation, and what to do next.", true, UITokens.FONT_SMALL))
	head.add_child(title)
	_summary_box.add_child(head)
	_summary_grid = GridContainer.new()
	_summary_grid.add_theme_constant_override("h_separation", UITokens.SP_4)
	_summary_grid.add_theme_constant_override("v_separation", UITokens.SP_3)
	_summary_box.add_child(_summary_grid)
	var total := 0
	for sid in DataLoader.get_skill_ids():
		total += PlayerData.get_level(sid)
	var discovered: int = (PlayerData.completion_log.get("items", {}) as Dictionary).size()
	var metrics: Array = [
		["Combat level", str(PlayerData.get_combat_level()), "skills", "attack", UITokens.RED],
		["Total level", UIStyle.fmt_exact(total), "items", "gold_bar", UITokens.GOLD_BRIGHT],
		["Tasks completed", "%d / %d" % [Quests.claimed_count(), Quests.count()], "currencies", "gp", UITokens.TEAL],
		["Items discovered", "%d / %d" % [discovered, DataLoader.items.size()], "items", "bones", UITokens.BLUE],
	]
	for metric in metrics:
		var cell := UIStyle.card()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := UIStyle.hbox(UITokens.SP_3)
		cell.add_child(row)
		var icon := UIStyle.icon_texture(str(metric[2]), str(metric[3]))
		icon.custom_minimum_size = Vector2(28, 28)
		row.add_child(icon)
		var body := UIStyle.vbox(UITokens.SP_1)
		var value := UIStyle.colored_label(str(metric[1]), metric[4], UITokens.FONT_SUBHEAD)
		body.add_child(value)
		if metric[0] == "Items discovered":
			_collection_value = value
		body.add_child(UIStyle.label(str(metric[0]), true, UITokens.FONT_MICRO))
		row.add_child(body)
		_summary_grid.add_child(cell)
	var links := HFlowContainer.new()
	links.add_theme_constant_override("h_separation", UITokens.SP_2)
	links.add_theme_constant_override("v_separation", UITokens.SP_2)
	links.add_child(_shortcut("Equipment", {"screen": Screens.EQUIPMENT}))
	links.add_child(_shortcut("Storage", {"screen": Screens.BANK}))
	links.add_child(_shortcut("Task journal", {"screen": Screens.QUESTS}))
	var ready := Achievements.ready_count()
	links.add_child(_shortcut("Milestones" + (" · %d ready" % ready if ready>0 else ""), {"screen": Screens.ACHIEVEMENTS}))
	_summary_box.add_child(links)
	_update_dashboard_columns()

func _activity_route(activity: Dictionary) -> Dictionary:
	if str(activity.get("kind", "")) == "skill":
		return {"screen": Screens.SKILLS, "skill_id": str(activity.get("id", "")), "action_id": str(activity.get("action_id", ""))}
	if str(activity.get("kind", "")) == "combat":
		return {"screen": str(activity.get("screen", Screens.COMBAT)), "area_id": str(activity.get("id", ""))}
	return {"screen": Screens.SKILLS, "skill_id": SkillManager.active_skill if SkillManager.active_skill != "" else "woodcutting"}

func _update_live_dashboard() -> void:
	if is_instance_valid(_activity_meter):
		var activity: Dictionary = GameManager.current_activity()
		var progress := clampf(float(activity.get("progress", 0)), 0.0, 1.0)
		_activity_meter.value = progress
		if is_instance_valid(_activity_progress_text):
			_activity_progress_text.text = ("Encounter" if activity.get("kind")=="combat" else "Action")+" · "+UIStyle.fmt_percent(progress)
		if is_instance_valid(_activity_detail):
			_activity_detail.text = str(activity.get("detail", ""))
	if is_instance_valid(_collection_value):
		_collection_value.text = "%d / %d" % [(PlayerData.completion_log.get("items", {}) as Dictionary).size(), DataLoader.items.size()]
	if is_instance_valid(_health_bar):
		_health_bar.max_value = CombatManager._compute_max_hp()
		_health_bar.value = CombatManager.player_hp
		_health_text.text = "Health · %s / %s" % [UIStyle.fmt_exact(CombatManager.player_hp), UIStyle.fmt_exact(_health_bar.max_value)]

func _rebuild_activity() -> void:
	_clear(_activity_box)
	var activity: Dictionary = GameManager.current_activity()
	var card := UIStyle.card(true)
	var col := UIStyle.vbox(UITokens.SP_3)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITokens.SP_4)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(64, 64)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	match str(activity.get("kind", "idle")):
		"skill":
			var skill_id: String = str(activity.get("id", ""))
			var action: Dictionary = DataLoader.get_action(skill_id, str(activity.get("action_id", "")))
			icon.texture = AssetRegistry.icon(skill_id, str(action.get("id", ""))) if action.get("icon_activity", false) else AssetRegistry.skill_icon(skill_id)
		"combat":
			icon.texture = AssetRegistry.monster_sprite(CombatManager.current_monster_id)
		_:
			icon.texture = AssetRegistry.skill_icon("woodcutting")
	head.add_child(icon)
	var text := UIStyle.vbox(UITokens.SP_1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var active_kind: String = str(activity.get("kind", "idle"))
	var state_badge := Widgets.badge("Paused" if GameManager.is_paused else ("In progress" if active_kind in ["skill", "combat"] else "Ready to begin"), UITokens.TEAL)
	state_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	text.add_child(state_badge)
	var heading := UIStyle.label(str(activity.get("label", "Idle")) if active_kind in ["skill", "combat"] else "Choose your next activity", false, UITokens.FONT_SUBHEAD)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(heading)
	_activity_detail = UIStyle.label(str(activity.get("detail", "")), true, UITokens.FONT_SMALL)
	_activity_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_activity_detail)
	head.add_child(text)
	col.add_child(head)
	var progress: float = float(activity.get("progress", 0.0))
	_activity_progress_text = UIStyle.label("", true, UITokens.FONT_MICRO)
	col.add_child(_activity_progress_text)
	_activity_meter = Widgets.meter(progress, 1.0, "enemy_hp" if activity.get("kind")=="combat" else "ember", "", 12, false)
	col.add_child(_activity_meter)
	_activity_progress_text.visible = str(activity.get("kind", "")) in ["skill", "combat"]
	_activity_meter.visible = _activity_progress_text.visible
	var world_event: Dictionary = RegionalEventsManager.active_event()
	if not world_event.is_empty():
		var condition := UIStyle.label("World condition · %s · %s left" % [str(world_event.get("name", "")), UIStyle.fmt_duration(RegionalEventsManager.remaining_seconds())], true, UITokens.FONT_MICRO)
		condition.tooltip_text = str(world_event.get("description", ""))
		condition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(condition)
	var kind: String = str(activity.get("kind", "idle"))
	if kind == "skill":
		var est: Dictionary = ActionEstimates.for_action(str(activity.get("id", "")), str(activity.get("action_id", "")))
		if not est.is_empty():
			var skill_id: String = str(activity.get("id", ""))
			var chips: Array = [
				Widgets.stat_chip("skills", skill_id, "≈ %s XP/h" % UIStyle.fmt(float(est["xp_per_hour"])),
					"Projected XP per hour. Assumptions: %s" % str(est["assumptions"]), UITokens.TEAL),
				Widgets.stat_chip("navigation", Screens.BANK, "≈ %s %s/h" % [UIStyle.fmt(float(est.get("output_per_hour", 0.0))), str(est.get("output_name", ""))],
					"Projected output per hour", UITokens.TEXT),
				Widgets.stat_chip("status", "action_time", UIStyle.fmt_duration(float(est["hours_to_next_level"]) * 3600.0),
					"Time to the next level at this rate", UITokens.GOLD_BRIGHT),
			]
			if float(est.get("supply_hours", -1.0)) >= 0.0:
				chips.append(Widgets.stat_chip("status", "warning", UIStyle.fmt_duration(float(est["supply_hours"])),
					"Your stock lasts about this long at the current rate", UITokens.AMBER))
			col.add_child(Widgets.chip_row(chips))
	elif kind == "combat":
		var cmp: Dictionary = CombatManager.target_comparison()
		if not cmp.is_empty():
			col.add_child(Widgets.chip_row([
				Widgets.stat_chip("navigation", Screens.COMBAT, "%s · Lv %d" % [str(cmp["monster_name"]), int(cmp["monster_level"])],
					"Target: %s, %s damage, max hit %d" % [str(cmp["monster_name"]), str(cmp["monster_damage_type"]), int(cmp["monster_max_hit"])]),
				Widgets.stat_chip("skills", "attack", UIStyle.fmt_percent(float(cmp["your_hit_chance_percent"]) / 100.0),
					"Your hit chance against it", UITokens.TEAL),
				Widgets.stat_chip("skills", "defence", UIStyle.fmt_percent(float(cmp["their_hit_chance_percent"]) / 100.0),
					"Its hit chance against you", UITokens.RED),
			]))
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", UITokens.SP_3)
	actions.add_theme_constant_override("v_separation", UITokens.SP_2)
	if kind != "idle" and kind != "stopped":
		var stop := UIStyle.danger_button("Retreat" if kind == "combat" else "Stop")
		stop.pressed.connect(func():
			if CombatManager.state != CombatManager.State.IDLE:
				CombatManager.stop_combat("retreat")
			else:
				SkillManager.stop_action(SkillManager.StopReason.PLAYER)
			refresh())
		actions.add_child(stop)
	var open := UIStyle.primary_button("Open this activity" if kind in ["skill", "combat"] else "Choose a skill")
	open.pressed.connect(func(): navigated.emit(_activity_route(GameManager.current_activity())))
	actions.add_child(open)
	actions.move_child(open, 0)
	actions.add_child(_shortcut("Action queue", {"screen": Screens.ACTION_QUEUE}))
	col.add_child(actions)
	_activity_box.add_child(card)
	_update_live_dashboard()

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
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		var heading := UIStyle.label(str(s.get("label", "")), false, UITokens.FONT_BODY)
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(heading)
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
	_unlock_count = 0
	var found: bool = false
	# Unclaimed completed tasks.
	for quest_id in Quests.all_quest_ids():
		if Quests.is_complete(quest_id) and not Quests.is_claimed(quest_id):
			found = true
			_add_unlock("Task reward ready",
				str(Quests.get_quest(quest_id).get("name", quest_id)),
				"Claim %s" % Quests.describe_reward(Quests.get_quest(quest_id).get("reward", {})),
				{"screen": Screens.QUESTS, "quest_id": quest_id}, UITokens.GOLD)
	# Newly unlocked activities at exactly the current level.
	for skill_id in DataLoader.get_skill_ids():
		var level: int = PlayerData.get_level(skill_id)
		for a in DataLoader.get_skill_actions(skill_id):
			if int(a.get("level_required", 1)) != level:
				continue
			found = true
			_add_unlock("New activity",
				"%s · %s" % [DataLoader.get_skill(skill_id).get("name", skill_id), str(a.get("name", ""))],
				"Unlocked at level %d" % level,
				{"screen": Screens.SKILLS, "skill_id": skill_id, "action_id": str(a.get("id", ""))}, UITokens.TEAL)
	# Affordable upgrades.
	for upgrade_id in DataLoader.shop.keys():
		if not bool(ShopManager.can_buy(upgrade_id)["ok"]):
			continue
		found = true
		var u: Dictionary = DataLoader.shop[upgrade_id]
		_add_unlock("Affordable upgrade",
			str(u.get("name", upgrade_id)),
			"%s GP · %s" % [UIStyle.fmt(float(u.get("cost", 0))), str(u.get("description", ""))],
			{"screen": Screens.PROVISIONER}, UITokens.BLUE)
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
		_add_unlock("Structure affordable",
			str(b.get("name", building_id)),
			"Ready to build in Emberreach", {"screen": Screens.SETTLEMENT}, UITokens.TEAL)
	# Overflow items waiting.
	if BankManager.has_overflow():
		found = true
		_add_unlock("Storage full",
			"%d items waiting in overflow" % BankManager.overflow_count(),
			"Expand storage or clear space to withdraw them", {"screen": Screens.BANK}, UITokens.AMBER)
	if not found:
		_unlocks_box.add_child(UIStyle.label("Nothing new right now. Keep training — unlocks appear here the moment they land.",
			true, UITokens.FONT_SMALL))
	if _unlock_count > UNLOCK_PREVIEW_LIMIT:
		var more := UIStyle.button("Show fewer" if _show_all_unlocks else "Show all %d opportunities" % _unlock_count)
		more.pressed.connect(func():
			_show_all_unlocks = not _show_all_unlocks
			_rebuild_unlocks())
		_unlocks_box.add_child(more)

func _add_unlock(kind: String, title: String, detail: String, route: Dictionary, color: Color) -> void:
	_unlock_count += 1
	if _show_all_unlocks or _unlock_count <= UNLOCK_PREVIEW_LIMIT:
		_unlocks_box.add_child(_unlock_row(kind, title, detail, route, color))

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
	var heading := UIStyle.label(title, false, UITokens.FONT_SMALL)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(heading)
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
		var skill_label := UIStyle.label("%s · level %d" % [DataLoader.get_skill(skill_id).get("name", skill_id), int(e["level"])], false, UITokens.FONT_SMALL)
		skill_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(skill_label)
		col.add_child(Widgets.progress_bar(float(e["progress"]), 1.0, UITokens.GOLD, "", 8,
			"%s XP to level %d" % [UIStyle.fmt(float(e["needed"])), int(e["level"]) + 1]))
		row.add_child(col)
		col.add_child(UIStyle.colored_label("%s XP to next level" % UIStyle.fmt(float(e["needed"])), UITokens.TEXT_MUTED, UITokens.FONT_MICRO))
		var track := UIStyle.mini_button("Track")
		var sid: String = skill_id
		var next_level: int = int(e["level"]) + 1
		track.pressed.connect(func(): Goals.pin("skill", sid, next_level))
		row.add_child(track)
		var train := UIStyle.mini_button("Train")
		train.pressed.connect(func(): navigated.emit({"screen": Screens.SKILLS, "skill_id": sid}))
		row.add_child(train)
		_skills_box.add_child(row)

func _rebuild_loadout() -> void:
	_clear(_loadout_box)
	var summary: Dictionary = CombatManager.player_combat_summary()
	var filled: int = 0
	for slot in EquipmentManager.slots.keys():
		if str(EquipmentManager.slots[slot]) != "":
			filled += 1
	_health_text = UIStyle.label("", false, UITokens.FONT_SMALL)
	_loadout_box.add_child(_health_text)
	_health_bar = Widgets.meter(float(summary["hp"]), float(summary["max_hp"]), "hp", "", 12, false)
	_loadout_box.add_child(_health_bar)
	var equipment := HFlowContainer.new()
	equipment.add_theme_constant_override("h_separation", UITokens.SP_2)
	equipment.add_theme_constant_override("v_separation", UITokens.SP_2)
	for slot in range(EquipmentManager.SLOT_COUNT):
		var item_id: String = EquipmentManager.get_equipped(slot)
		var item: Dictionary = DataLoader.get_item(item_id)
		var button := UIStyle.mini_button("")
		button.custom_minimum_size = Vector2(44, 44)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 32)
		button.icon = AssetRegistry.item_icon(item_id) if item_id != "" else AssetRegistry.icon("slots", str(EquipmentView.SLOT_ICONS[slot]))
		button.tooltip_text = "%s · %s\nOpen equipment" % [EquipmentView.SLOT_NAMES[slot], item.get("name", "Empty")]
		button.set_meta("overview_equipment_slot", slot)
		button.pressed.connect(func(): navigated.emit({"screen": Screens.EQUIPMENT}))
		equipment.add_child(button)
	_loadout_box.add_child(equipment)
	var evasion: Dictionary = summary["evasion"]
	var food: int = _food_count()
	_loadout_box.add_child(Widgets.chip_row([
		Widgets.stat_chip("slots", "platebody", "%d / %d" % [filled, EquipmentManager.SLOT_COUNT], "Equipment slots filled",
			UITokens.GREEN if filled >= 5 else UITokens.AMBER),
		Widgets.stat_chip("skills", "strength", "Hit "+UIStyle.fmt(float(summary["max_hit"])), "Max hit", UITokens.RED),
		Widgets.stat_chip("skills", "attack", "Acc "+UIStyle.fmt(float(summary["accuracy"])), "Accuracy rating"),
		Widgets.stat_chip("status", "slow", "%.2fs" % float(summary["attack_interval"]), "Attack interval"),
		Widgets.stat_chip("skills", "defence", "DR "+UIStyle.fmt_percent(float(summary["damage_reduction"]) / 100.0), "Damage reduction", UITokens.TEAL),
		Widgets.stat_chip("slots", "shield", "%s / %s / %s" % [UIStyle.fmt(float(evasion["melee"])), UIStyle.fmt(float(evasion["ranged"])), UIStyle.fmt(float(evasion["magic"]))],
			"Evasion against melee / ranged / magic"),
		Widgets.stat_chip("navigation", Screens.PRAYERS, str(PlayerData.active_prayers.size()), "Active rites"),
		Widgets.stat_chip("slots", "consumable", str(DataLoader.get_item(PlayerData.active_potion).get("name", "none")),
			"Active potion · %d charges remaining" % PlayerData.potion_charges,
			UITokens.TEXT if PlayerData.active_potion != "" else UITokens.TEXT_MUTED),
		Widgets.stat_chip("skills", "cooking", UIStyle.fmt_exact(float(food)),
			"Food in storage · auto-eat tier %d" % int(PlayerData.settings.get("auto_eat_tier", 0)),
			UITokens.GREEN if food > 0 else UITokens.AMBER),
		Widgets.stat_chip("navigation", Screens.BANK, "%d / %d" % [BankManager.get_used_slots(), BankManager.get_slot_limit()],
			"Storage stacks used", UITokens.AMBER if BankManager.is_full() else UITokens.TEXT),
	]))
	var links := HFlowContainer.new()
	links.add_theme_constant_override("h_separation", UITokens.SP_2)
	links.add_theme_constant_override("v_separation", UITokens.SP_2)
	links.add_child(_shortcut("Manage equipment", {"screen": Screens.EQUIPMENT}))
	links.add_child(_shortcut("Equip food", {"screen": Screens.BANK}))
	links.add_child(_shortcut("Prayers", {"screen": Screens.PRAYERS}))
	_loadout_box.add_child(links)
	_update_live_dashboard()

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
	_stats_box.add_child(Widgets.chip_row([
		Widgets.stat_chip("status", "playtime", UIStyle.fmt_duration(GameManager.playtime_seconds), "Playtime"),
		Widgets.stat_chip("navigation", Screens.STATS, UIStyle.fmt_exact(float(total_level)), "Total skill levels", UITokens.GOLD_BRIGHT),
		Widgets.stat_chip("navigation", Screens.COMBAT, str(PlayerData.get_combat_level()), "Combat level"),
		Widgets.stat_chip("navigation", Screens.QUESTS, "%d / %d" % [claimed, Quests.count()], "Tasks completed"),
		Widgets.stat_chip("navigation", Screens.ACHIEVEMENTS, "%d / %d" % [claimed_ach, Achievements.count()],
			"Milestones claimed" + (" · %d ready to claim" % ready_ach if ready_ach > 0 else ""),
			UITokens.GOLD_BRIGHT if ready_ach > 0 else UITokens.TEXT),
		Widgets.stat_chip("navigation", Screens.COLLECTION, "%d / %d" % [(PlayerData.completion_log.get("items", {}) as Dictionary).size(), DataLoader.items.size()], "Items discovered"),
		Widgets.stat_chip("navigation", Screens.EXPEDITIONS, "%d / %d" % [(PlayerData.completion_log.get("dungeons", {}) as Dictionary).size(), DataLoader.dungeons.size()], "Expeditions cleared (distinct)"),
		Widgets.stat_chip("skills", "slayer", "%d / %d" % [(PlayerData.completion_log.get("monsters", {}) as Dictionary).size(), DataLoader.monsters.size()], "Enemies defeated (distinct)"),
		Widgets.stat_chip("status", "ok", UIStyle.fmt_duration(PlayerData.get_stat("offline_seconds_processed")),
			"Offline time the simulation has caught up on your behalf", UITokens.TEXT_MUTED),
		Widgets.stat_chip("status", "danger", UIStyle.fmt_exact(PlayerData.get_stat("deaths")), "Defeats", UITokens.TEXT_MUTED),
	]))

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
	Widgets.rebuild_once_per_frame(refresh)
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
