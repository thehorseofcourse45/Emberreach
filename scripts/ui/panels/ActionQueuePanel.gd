extends VBoxContainer
## ActionQueuePanel — the "set it and forget it" surface for the FIFO planner.
##
## This is a thin adapter: it builds controls and renders ActionQueueManager's state. Every rule
## (ordering, target conditions, the combat gate) lives in the manager, so the planner behaves the
## same whether it is driven from here, from a save load, or from an offline slice.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _header: VBoxContainer
var _steps_box: VBoxContainer
var _status_box: VBoxContainer
var _add_box: VBoxContainer
var _queue: VBoxContainer

var _skill_picker: OptionButton
var _action_picker: OptionButton
var _item_picker: OptionButton
var _quantity: LineEdit
var _place_picker: OptionButton
var _kind_toggle: Button
var _skill_row: HFlowContainer
var _target_row: HFlowContainer
var _place_row: HFlowContainer
var _showing_combat: bool = false

const QUANTITY_PRESETS: Array[int] = [1, 100, 1000, 5000]
## `var`, not `const`: the place list is rebuilt every time the picker is filled, and a const
## array is read-only in Godot 4.
var _places: Array[Dictionary] = []

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	EventBus.state_refreshed.connect(refresh)
	ActionQueueManager.queue_changed.connect(refresh)
	ActionQueueManager.queue_paused.connect(func(reason: String): _on_paused(reason))
	refresh()

func focus_route(route: Dictionary) -> void:
	if str(route.get("screen", "")) == Screens.ACTION_QUEUE:
		refresh()

func detail_context() -> Dictionary:
	var step: Dictionary = ActionQueueManager.current_step()
	if step.is_empty():
		return {"kind": "text", "title": "Action queue",
			"body": "Nothing is running. Add a step, then press Start to hand the activity slot to the queue."}
	return {"kind": "text", "title": "Current step",
		"body": "%s — %s" % [ActionQueueManager.step_label(step), _status_sentence()]}

# =========================================================================
#  Build
# =========================================================================

func _build() -> void:
	var intro := UIStyle.card()
	add_child(intro)
	var intro_col := UIStyle.vbox(UITokens.SP_2)
	intro.add_child(intro_col)
	intro_col.add_child(UIStyle.title("ACTION QUEUE", UITokens.FONT_SUBHEAD))
	var blurb := UIStyle.label(
		"Queue a sequence — \"chop Yew until 1,000 logs, burn all of them, then fight\" — and the game switches by itself as each condition is met.",
		true, UITokens.FONT_SMALL)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_col.add_child(blurb)

	_add_box = UIStyle.vbox(UITokens.SP_4)
	add_child(_add_box)
	_build_add_controls()

	_header = UIStyle.vbox(UITokens.SP_4)
	add_child(_header)
	_status_box = UIStyle.vbox(UITokens.SP_3)
	_header.add_child(_status_box)
	_steps_box = UIStyle.vbox(UITokens.SP_3)
	_header.add_child(_steps_box)
	_build_control_row()

	_queue = UIStyle.vbox(UITokens.SP_6)
	add_child(_queue)

func _build_add_controls() -> void:
	UIPanelClear(_add_box)
	var card := UIStyle.card(true)
	_add_box.add_child(card)
	var col := UIStyle.vbox(UITokens.SP_3)
	card.add_child(col)
	col.add_child(UIStyle.section("Add a step"))

	_kind_toggle = UIStyle.mini_button("Step type: Skill", "Switch between a skill step and a combat step")
	_kind_toggle.pressed.connect(_on_kind_toggled)
	col.add_child(_kind_toggle)

	# Skill controls.
	# Flow containers, not fixed rows: on a 420px window the controls wrap onto a second line
	# instead of forcing the panel wider than the window.
	_skill_row = _flow_row()
	col.add_child(_skill_row)
	var skill_row: HFlowContainer = _skill_row
	_skill_picker = OptionButton.new()
	_skill_picker.custom_minimum_size = Vector2(0, UITokens.H_HEADER + 8)
	_skill_picker.clip_text = true
	_skill_picker.fit_to_longest_item = false
	_skill_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_picker.item_selected.connect(func(_i): _fill_actions())
	skill_row.add_child(_skill_picker)
	_action_picker = OptionButton.new()
	_action_picker.custom_minimum_size = Vector2(0, UITokens.H_HEADER + 8)
	_action_picker.clip_text = true
	_action_picker.fit_to_longest_item = false
	_action_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_picker.item_selected.connect(func(_i): _fill_items())
	skill_row.add_child(_action_picker)
	var add_skill := UIStyle.primary_button("Add skill step", "Append this step to the end of the queue")
	add_skill.pressed.connect(_on_add_skill)
	skill_row.add_child(add_skill)

	var target_row := _flow_row()
	col.add_child(target_row)
	_target_row = target_row
	target_row.add_child(UIStyle.label("Stop when", true, UITokens.FONT_SMALL))
	_item_picker = OptionButton.new()
	_item_picker.custom_minimum_size = Vector2(0, UITokens.H_HEADER + 8)
	_item_picker.clip_text = true
	_item_picker.fit_to_longest_item = false
	_item_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_picker.item_selected.connect(func(_i): pass)
	target_row.add_child(_item_picker)
	_quantity = LineEdit.new()
	_quantity.placeholder_text = "0 = all"
	_quantity.custom_minimum_size = Vector2(84, UITokens.H_HEADER + 8)
	_quantity.tooltip_text = "Stop once you own this many. 0 means burn the whole stack."
	target_row.add_child(_quantity)
	for preset in QUANTITY_PRESETS:
		var chip := UIStyle.mini_button(UIStyle.fmt_exact(float(preset)))
		chip.pressed.connect(func(): _quantity.text = str(preset))
		target_row.add_child(chip)
	var hint := UIStyle.label("0 means \"all\" — the step ends when the bank runs out.", true, UITokens.FONT_MICRO)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target_row.add_child(hint)

	# Combat controls.
	var place_row := _flow_row()
	col.add_child(place_row)
	_place_row = place_row
	place_row.add_child(UIStyle.label("Fight in", true, UITokens.FONT_SMALL))
	_place_picker = OptionButton.new()
	_place_picker.custom_minimum_size = Vector2(0, UITokens.H_HEADER + 8)
	_place_picker.clip_text = true
	_place_picker.fit_to_longest_item = false
	_place_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place_row.add_child(_place_picker)
	var add_combat := UIStyle.button("Add combat step", "Append a fight step to the end of the queue")
	add_combat.pressed.connect(_on_add_combat)
	place_row.add_child(add_combat)

	_fill_skills()
	_fill_places()
	_showing_combat = false
	_apply_kind_visibility()

func _apply_kind_visibility() -> void:
	if _kind_toggle == null:
		return
	_kind_toggle.text = "Step type: Combat" if _showing_combat else "Step type: Skill"
	_skill_row.visible = not _showing_combat
	_target_row.visible = not _showing_combat
	_place_row.visible = _showing_combat

func _build_control_row() -> void:
	var card := UIStyle.card()
	_header.add_child(card)
	var row := _flow_row()
	card.add_child(row)
	var start := UIStyle.primary_button("Start", "Hand the activity slot to the queue")
	start.pressed.connect(_on_start)
	row.add_child(start)
	var cont := UIStyle.button("Continue", "Resolve the current combat gate and move to the next step")
	cont.pressed.connect(func(): _on_continue())
	row.add_child(cont)
	var skip := UIStyle.button("Skip step", "Abandon the current step and move to the next one")
	skip.pressed.connect(_on_skip)
	row.add_child(skip)
	var pause := UIStyle.button("Pause", "Stop queue automation and keep the remaining steps")
	pause.pressed.connect(func():
		ActionQueueManager.pause("Paused by player")
		refresh())
	row.add_child(pause)
	var clear := UIStyle.button("Clear queue", "Remove every step and stop queue-owned activity")
	clear.pressed.connect(func():
		ActionQueueManager.clear()
		refresh())
	row.add_child(clear)

# =========================================================================
#  Refresh
# =========================================================================

func refresh() -> void:
	if not is_inside_tree():
		return
	_refresh_status()
	_refresh_steps()

func _refresh_status() -> void:
	UIPanelClear(_status_box)
	var status: String = ActionQueueManager.status
	var color: Color = UITokens.GOLD_BRIGHT
	match status:
		ActionQueueManager.STATUS_RUNNING: color = UITokens.GREEN
		ActionQueueManager.STATUS_COMBAT_WAITING: color = UITokens.AMBER
		ActionQueueManager.STATUS_PAUSED: color = UITokens.RED
		ActionQueueManager.STATUS_IDLE: color = UITokens.TEXT_MUTED
	var row := UIStyle.hbox(UITokens.SP_4)
	_status_box.add_child(row)
	var badge := Widgets.badge(status.replace("_", " ").capitalize(), color,
		"Queue state: idle, ready, running, paused or waiting on a combat decision")
	row.add_child(badge)
	row.add_child(UIStyle.label(_status_sentence(), false, UITokens.FONT_SMALL))
	if ActionQueueManager.last_error != "":
		# A deliberate pause is a note, not a failure — only true errors get the red.
		var is_error: bool = ActionQueueManager.status != ActionQueueManager.STATUS_PAUSED
		var tone: Color = UITokens.RED if is_error else UITokens.TEXT_MUTED
		var err := UIStyle.colored_label(ActionQueueManager.last_error, tone, UITokens.FONT_MICRO)
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_status_box.add_child(err)

func _status_sentence() -> String:
	if ActionQueueManager.waiting_for_combat():
		return "This step is fighting. Expeditions have no automatic end yet, so the queue waits for Continue or Skip."
	match ActionQueueManager.status:
		ActionQueueManager.STATUS_RUNNING:
			return "Running step %d of %d." % [ActionQueueManager.current_index + 1, ActionQueueManager.size()]
		ActionQueueManager.STATUS_READY:
			return "Ready — press Start to hand over the activity slot."
		ActionQueueManager.STATUS_PAUSED:
			return "Paused. Remaining steps are kept; Continue or Start resumes."
		ActionQueueManager.STATUS_COMBAT_WAITING:
			return "Waiting on a combat decision."
	if ActionQueueManager.is_empty():
		return "No steps queued."
	if not ActionQueueManager.has_pending_work():
		return "Every step is done. The activity slot is free."
	return "%d step(s) waiting." % (ActionQueueManager.size() - ActionQueueManager.current_index)

func _refresh_steps() -> void:
	UIPanelClear(_steps_box)
	var steps: Array = ActionQueueManager.steps
	if steps.is_empty():
		_steps_box.add_child(Widgets.empty_state("Nothing queued yet",
			"Add a skill step above, then press Start. The queue runs one step at a time and switches for you."))
		return
	for i in range(steps.size()):
		_steps_box.add_child(_step_row(i, steps[i]))

func _step_row(index: int, step: Dictionary) -> Control:
	var is_current: bool = index == ActionQueueManager.current_index and ActionQueueManager.enabled
	var is_next: bool = index == ActionQueueManager.current_index
	var card := UIStyle.card(is_current)
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var row := _flow_row()
	col.add_child(row)
	row.add_child(UIStyle.colored_label(str(index + 1), UITokens.GOLD, UITokens.FONT_SUBHEAD))
	var text := UIStyle.vbox(UITokens.SP_1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(UIStyle.label(ActionQueueManager.step_label(step), is_next, UITokens.FONT_BODY))
	var kind: String = str(step.get("kind", ""))
	var detail: String = ""
	if kind == "skill":
		var item_name: String = str(DataLoader.get_item(str(step.get("target_item_id", ""))).get("name", "?"))
		detail = "%s · stop at %s %s (you have %s)" % [str(step.get("skill_id", "")).capitalize(),
			item_name,
			"all" if int(step.get("target_quantity", 0)) == 0 else UIStyle.fmt_exact(float(step.get("target_quantity", 0))),
			UIStyle.fmt_exact(float(BankManager.get_total_owned(str(step.get("target_item_id", "")))))]
	else:
		var ctx: Dictionary = step.get("context", {})
		detail = "%s · %s" % [str(ctx.get("type", "area")).capitalize(), str(ctx.get("id", "?"))]
	text.add_child(UIStyle.label(detail, true, UITokens.FONT_MICRO))
	if kind == "skill":
		var sid: String = str(step.get("skill_id", ""))
		var aid: String = str(step.get("action_id", ""))
		var action: Dictionary = DataLoader.get_action(sid, aid)
		text.add_child(UIStyle.label("Inputs: " + Goals._input_summary(action.get("input_items", {})) + " · output: " + str(action.get("output_items", {})), true, UITokens.FONT_MICRO))
		var check: Dictionary = SkillManager.check_action(sid, aid)
		if not bool(check.ok): text.add_child(UIStyle.colored_label("Current blocker: " + str(check.detail), UITokens.AMBER, UITokens.FONT_MICRO))
		text.add_child(UIStyle.label("Stop condition uses owned stock; offline quantity targets can overshoot by up to one 30-second slice. Material exhaustion and one-shot research still stop immediately.", true, UITokens.FONT_MICRO))
	if is_current:
		row.add_child(Widgets.badge("Current", UITokens.GOLD_BRIGHT))
	var step_id: String = str(step.get("id", ""))
	var actions := _flow_row()
	col.add_child(actions)
	var up := UIStyle.mini_button("Move up", "Move this step earlier in the queue")
	up.disabled = index == 0
	up.pressed.connect(func():
		ActionQueueManager.move_step(step_id, -1)
		refresh())
	actions.add_child(up)
	var down := UIStyle.mini_button("Move down", "Move this step later in the queue")
	down.disabled = index == steps_size() - 1
	down.pressed.connect(func():
		ActionQueueManager.move_step(step_id, 1)
		refresh())
	actions.add_child(down)
	var remove := UIStyle.mini_button("Remove", "Remove this step from the queue")
	remove.pressed.connect(func():
		ActionQueueManager.remove_step(step_id)
		refresh())
	actions.add_child(remove)
	return card

## Indirection so the panel never touches another screen's node tree.
func steps_size() -> int:
	return ActionQueueManager.steps.size()

# =========================================================================
#  Populating the pickers
# =========================================================================

func _fill_skills() -> void:
	_skill_picker.clear()
	for skill_id in DataLoader.get_skill_ids():
		_skill_picker.add_item(str(DataLoader.get_skill(str(skill_id)).get("name", skill_id)))
		_skill_picker.set_item_metadata(_skill_picker.item_count - 1, str(skill_id))
	_fill_actions()

func _fill_actions() -> void:
	_action_picker.clear()
	var skill_id: String = _selected_skill()
	for action_id in _action_ids(skill_id):
		_action_picker.add_item(str(DataLoader.get_action(skill_id, action_id).get("name", action_id)))
		_action_picker.set_item_metadata(_action_picker.item_count - 1, action_id)
	_fill_items()

## The target list is the action's inputs and outputs, which covers gather, craft and burn
## flows without a searchable item browser.
func _fill_items() -> void:
	_item_picker.clear()
	var skill_id: String = _selected_skill()
	var action_id: String = _selected_action()
	var action: Dictionary = DataLoader.get_action(skill_id, action_id)
	if action.is_empty():
		return
	var seen: Dictionary = {}
	for source in [action.get("output_items", {}), action.get("input_items", {})]:
		for item_id in (source as Dictionary).keys():
			var id_str: String = str(item_id)
			if seen.has(id_str):
				continue
			seen[id_str] = true
			_item_picker.add_item(str(DataLoader.get_item(id_str).get("name", id_str)))
			_item_picker.set_item_metadata(_item_picker.item_count - 1, id_str)
	if _item_picker.item_count > 0:
		_item_picker.select(0)

func _fill_places() -> void:
	_places.clear()
	_place_picker.clear()
	var area_ids: Array = DataLoader.areas.keys()
	area_ids.sort_custom(func(a, b):
		return int((DataLoader.areas[a].get("level_range", [0]) as Array)[0]) < int((DataLoader.areas[b].get("level_range", [0]) as Array)[0]))
	for area_id in area_ids:
		if str(DataLoader.areas[area_id].get("type", "area")) == "slayer_area":
			continue
		_places.append({"type": "area", "id": str(area_id)})
		_place_picker.add_item("Region · %s" % str(DataLoader.areas[area_id].get("name", area_id)))
	var dungeon_ids: Array = DataLoader.dungeons.keys()
	dungeon_ids.sort()
	for dungeon_id in dungeon_ids:
		_places.append({"type": "dungeon", "id": str(dungeon_id)})
		_place_picker.add_item("Expedition · %s" % str(DataLoader.dungeons[dungeon_id].get("name", dungeon_id)))
	if _place_picker.item_count > 0:
		_place_picker.select(0)

func _selected_skill() -> String:
	if _skill_picker == null or _skill_picker.selected < 0:
		return ""
	return str(_skill_picker.get_item_metadata(_skill_picker.selected))

func _selected_action() -> String:
	if _action_picker == null or _action_picker.selected < 0:
		return ""
	return str(_action_picker.get_item_metadata(_action_picker.selected))

func _selected_item() -> String:
	if _item_picker == null or _item_picker.selected < 0:
		return ""
	return str(_item_picker.get_item_metadata(_item_picker.selected))

## get_skill_actions() returns an Array of action records, so read the id off each entry.
func _action_ids(skill_id: String) -> Array:
	var out: Array = []
	if skill_id == "":
		return out
	for action in DataLoader.get_skill_actions(skill_id):
		if typeof(action) == TYPE_DICTIONARY:
			out.append(str(action.get("id", "")))
	return out

# =========================================================================
#  Commands
# =========================================================================

func _on_kind_toggled() -> void:
	_showing_combat = not _showing_combat
	_apply_kind_visibility()

func _on_add_skill() -> void:
	var step: Dictionary = ActionQueueManager.add_skill_step(_selected_skill(), _selected_action(),
		_selected_item(), _quantity_value())
	if step.is_empty():
		EventBus.notify("That step is not valid — pick a real skill, action and item.", "warn")
		return
	_quantity.text = ""
	refresh()

func _on_add_combat() -> void:
	if _place_picker.selected < 0 or _place_picker.selected >= _places.size():
		EventBus.notify("Pick a region or expedition first.", "warn")
		return
	var place: Dictionary = _places[_place_picker.selected]
	var place_id: String = str(place["id"])
	var is_dungeon: bool = str(place["type"]) == "dungeon"
	var source: Dictionary = DataLoader.get_dungeon(place_id) if is_dungeon else DataLoader.areas.get(place_id, {})
	var step: Dictionary = ActionQueueManager.add_combat_step({
		"type": "dungeon" if is_dungeon else "area",
		"id": place_id,
		"monsters": source.get("monsters", []),
		"endless": not is_dungeon,
		"attack_style": CombatManager.attack_style,
		"melee_style": CombatManager.melee_style,
	})
	if step.is_empty():
		EventBus.notify("That expedition is not valid.", "warn")
		return
	refresh()

func _on_start() -> void:
	if ActionQueueManager.is_empty():
		EventBus.notify("Add at least one step first.", "warn")
		return
	if not ActionQueueManager.start():
		EventBus.notify(ActionQueueManager.last_error, "warn")
		return
	refresh()

func _on_continue() -> void:
	if ActionQueueManager.continue_queue():
		refresh()
	else:
		EventBus.notify("There is nothing to continue.", "warn")

func _on_skip() -> void:
	if ActionQueueManager.skip_current():
		refresh()
	else:
		EventBus.notify("There is nothing to skip.", "warn")

func _on_paused(reason: String) -> void:
	EventBus.notify("Action queue paused: %s" % reason, "info")
	refresh()

func _quantity_value() -> int:
	if _quantity == null:
		return 0
	return maxi(0, int(_quantity.text.strip_edges()))

## A wrapping row. Narrow controls must wrap, not widen the panel past the window.
func _flow_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UITokens.SP_3)
	row.add_theme_constant_override("v_separation", UITokens.SP_2)
	return row

## Local clear: a panel only ever clears its own containers.
func UIPanelClear(box: Node) -> void:
	if box == null:
		return
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
