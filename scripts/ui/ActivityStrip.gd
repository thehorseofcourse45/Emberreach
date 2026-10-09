extends PanelContainer
class_name ActivityStrip
## ActivityStrip — the persistent "what am I doing right now" bar.
##
## Always visible on every screen, on desktop and mobile, and it never covers a control
## (the shell reserves a fixed row for it rather than floating it over content). It shows the
## activity, its progress, the projected yield, and a single always-available stop control.

var _icon: TextureRect
var _title: Label
var _bar: ProgressBar
var _hp_bar: ProgressBar
var _stop: Button
var _eat: Button
var _estimates: Label
## Eat-button cache: last HP it was built for, and a flag to rebuild when the bank changes.
var _eat_hp_seen: int = -1
var _eat_dirty: bool = true
# The activity layer's spawn offer (EventDirector): shown only while an offer is live, polled
# for its remaining charges because the count drops on engine completions, not on signals.
var _spawn_row: HBoxContainer
var _spawn_label: Label
var _spawn_switch: Button
# The open event card dialog, if any. Cards are opened here because the strip is the one piece
# of chrome present on every screen; closed on event_resolved (buttons, stored policy or
# watchdog all resolve through EventDirector.resolve, which always emits that signal).
var _card_dialog: ConfirmDialog = null

func _ready() -> void:
	custom_minimum_size = Vector2(0, UITokens.H_STRIP - 6)
	add_theme_stylebox_override("panel", UIStyle.surface_box("raised", true))
	# Flows rather than a plain HBox: the estimate text and the Stop button drop to a second line on
	# a narrow window instead of forcing it wider than the screen.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UITokens.SP_5)
	row.add_theme_constant_override("v_separation", UITokens.SP_2)
	add_child(row)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(32, 32)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_icon)

	var col := UIStyle.vbox(UITokens.SP_1)
	col.custom_minimum_size.x = 148
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_title = UIStyle.label("Idle", false, UITokens.FONT_SMALL)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_bar = Widgets.progress_bar(0.0, 1.0, UITokens.TEAL, "", 6)
	col.add_child(_bar)

	var health := UIStyle.hbox(UITokens.SP_3)
	health.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health.size_flags_stretch_ratio = 0.6
	health.custom_minimum_size.x = 148
	row.add_child(health)
	# Spawn offer: "Bonus: <target> (<n> left)" + a one-click switch of the activity slot.
	_spawn_row = HBoxContainer.new()
	_spawn_row.add_theme_constant_override("h_separation", UITokens.SP_3)
	_spawn_label = UIStyle.label("", false, UITokens.FONT_SMALL)
	_spawn_label.add_theme_color_override("font_color", UITokens.TEAL)
	_spawn_row.add_child(_spawn_label)
	_spawn_switch = UIStyle.mini_button("Switch", "Move the activity slot onto the bonus event's target action")
	_spawn_switch.pressed.connect(_on_switch)
	_spawn_row.add_child(_spawn_switch)
	_spawn_row.visible = false
	row.add_child(_spawn_row)

	_estimates = UIStyle.label("", true, UITokens.FONT_MICRO)
	_estimates.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# A hard 200px minimum here set the floor for the whole window; wrap instead so the strip can
	# narrow with the window.
	_estimates.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	health.add_child(_estimates)
	_hp_bar = Widgets.progress_bar(0.0, 1.0, UITokens.GREEN, "", 10, "Your health")
	_hp_bar.custom_minimum_size.x = 108
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.visible = false
	health.add_child(_hp_bar)

	_stop = UIStyle.danger_button("Stop", "Stop the current activity")
	_stop.custom_minimum_size.y = UITokens.H_CONTROL - 6
	_stop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stop.pressed.connect(_on_stop)
	row.add_child(_stop)

	_eat = UIStyle.button("Eat food", "Heal by eating the best food in Storage")
	_eat.custom_minimum_size.y = UITokens.H_CONTROL - 6
	_eat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_eat.pressed.connect(_on_eat)
	row.add_child(_eat)

	EventBus.activity_changed.connect(refresh)
	EventBus.state_refreshed.connect(refresh)
	EventBus.combat_ended.connect(func(_c): refresh())
	EventBus.bank_changed.connect(func(): _eat_dirty = true)
	EventBus.event_offered.connect(_on_event_offered)
	EventBus.event_resolved.connect(_on_event_resolved)
	EventBus.state_refreshed.connect(_close_card_dialog)
	refresh()

func _process(_delta: float) -> void:
	# Progress is polled from the authoritative simulation rather than animated independently,
	# so the bar can never disagree with the state that grants rewards.
	if CombatManager.state != CombatManager.State.IDLE:
		_refresh_combat_readout()
	elif SkillManager.running and not GameManager.is_paused:
		_bar.value = clampf(SkillManager.progress / maxf(SkillManager.current_interval, 0.001), 0.0, 1.0) * 100.0
	# The Eat button has to light up the moment you drop below full health, not on the next
	# panel refresh. Reading HP is free; the bank walk only runs when HP actually moved or the
	# bank changed, so this stays cheap per frame.
	var hp: int = int(CombatManager.player_hp)
	if hp != _eat_hp_seen or _eat_dirty:
		_eat_hp_seen = hp
		_eat_dirty = false
		_refresh_eat()
	# Same polling rule for the spawn countdown: the charge drops inside the engine's completion
	# path with no signal of its own, so the label follows the state instead of a cached string.
	if _spawn_row.visible:
		var spawn_text: String = _spawn_text()
		if spawn_text != "" and _spawn_label.text != spawn_text:
			_spawn_label.text = spawn_text

func refresh() -> void:
	var activity: Dictionary = GameManager.current_activity()
	var kind: String = str(activity.get("kind", "idle"))
	_hp_bar.visible = kind == "combat"
	_estimates.custom_minimum_size.x = 72 if kind == "combat" else 0
	_title.text = str(activity.get("label", "Idle"))
	# The detail shares the estimate line: title + bar + one status line keeps this strip a thin
	# band above the workspace instead of a three-line stack.
	var detail: String = str(activity.get("detail", ""))
	match kind:
		"skill":
			_bar.tooltip_text = "Progress to the next skill action"
			_icon.texture = AssetRegistry.skill_icon(str(activity.get("id", "")))
			_bar.max_value = 100.0
			_bar.value = float(activity.get("progress", 0.0)) * 100.0
			_bar.add_theme_stylebox_override("fill", UIStyle.glow_fill(UITokens.TEAL))
			_estimates.text = _join(detail, _skill_estimates(str(activity.get("id", "")), str(activity.get("action_id", ""))))
		"combat":
			_icon.texture = AssetRegistry.monster_sprite(CombatManager.current_monster_id)
			_bar.max_value = 100.0
			_bar.value = float(activity.get("progress", 0.0)) * 100.0
			_bar.add_theme_stylebox_override("fill", UIStyle.glow_fill(UITokens.RED))
			_refresh_combat_readout()
		"stopped":
			_icon.texture = AssetRegistry.icon("status", "warning")
			_bar.value = 0.0
			_estimates.text = detail
		_:
			_icon.texture = AssetRegistry.icon("status", "idle")
			_bar.value = 0.0
			_estimates.text = detail
	_stop.disabled = kind == "idle" or kind == "stopped"
	_stop.text = "Retreat" if kind == "combat" else "Stop"
	# The spawn offer rides the strip: hidden with no live offer, refreshed by activity_changed
	# (EventDirector emits it on offer, accept and expiry).
	_spawn_row.visible = not EventDirector.active_spawn.is_empty()
	if _spawn_row.visible:
		_spawn_label.text = _spawn_text()
	_refresh_eat()

func _refresh_combat_readout() -> void:
	var activity: Dictionary = GameManager.current_activity()
	_title.text = str(activity.get("label", ""))
	_bar.max_value = 100.0
	_bar.value = clampf(float(activity.get("progress", 0.0)), 0.0, 1.0) * 100.0
	_bar.tooltip_text = "Damage dealt to this enemy" if CombatManager.state == CombatManager.State.FIGHTING else "Waiting for the next enemy"
	var maxhp: float = maxf(1.0, CombatManager._compute_max_hp())
	_hp_bar.max_value = maxhp
	_hp_bar.value = clampf(CombatManager.player_hp, 0.0, maxhp)
	_estimates.text = "HP %s / %s" % [UIStyle.fmt(CombatManager.player_hp), UIStyle.fmt(maxhp)]
	_hp_bar.tooltip_text = "Your health: %s / %s" % [UIStyle.fmt(CombatManager.player_hp), UIStyle.fmt(maxhp)]

## Eating only matters while hurt, and only with food in the bank. Saying which of those is
## missing is the whole value of a disabled button.
func _refresh_eat() -> void:
	var food: Dictionary = _best_food_in_bank()
	var maxhp: float = CombatManager._compute_max_hp()
	if food.is_empty():
		_eat.disabled = true
		_eat.text = "Eat food"
		_eat.tooltip_text = "No food in Storage. Cook some to heal in a fight."
	elif CombatManager.player_hp >= maxhp:
		_eat.disabled = true
		_eat.text = "Full health"
		_eat.tooltip_text = "You are at full health."
	else:
		_eat.disabled = false
		_eat.text = "Eat %s" % str(food.get("name", ""))
		_eat.tooltip_text = "Eat %s for %d HP (you have %d / %d)" % [
			str(food.get("name", "")), int(food.get("heal_amount", 0)),
			int(CombatManager.player_hp), int(maxhp)]

## The food the Eat button would use: the same pick CombatManager.eat_best_food() makes.
func _best_food_in_bank() -> Dictionary:
	for item_id in BankManager.items.keys():
		if int(BankManager.items[item_id]) <= 0:
			continue
		var item: Dictionary = DataLoader.get_item(str(item_id))
		if str(item.get("item_type", "")) != "food":
			continue
		var heal: int = int(item.get("heal_amount", 0))
		if heal <= 0:
			continue
		# Same pick the Eat button previews, so the label and the meal can never disagree.
		if str(item.get("id", item_id)) == CombatManager.find_food():
			return item
	return {}

## Detail plus projections share one line, joined by the standard separator; either half may
## be empty (a respawn has nothing to say).
func _join(first: String, second: String) -> String:
	if first == "":
		return second
	if second == "":
		return first
	return "%s  ·  %s" % [first, second]

## Bounded, clearly-labelled projections. Estimated values are marked with "≈" and the tooltip
## states the assumption, so nothing here is presented as an exact rate.
func _skill_estimates(skill_id: String, action_id: String) -> String:
	if skill_id == "" or action_id == "":
		return ""
	var est: Dictionary = ActionEstimates.for_action(skill_id, action_id)
	if est.is_empty():
		return ""
	var parts: Array[String] = ["≈ %s XP/h" % UIStyle.fmt(float(est["xp_per_hour"]))]
	if float(est.get("output_per_hour", 0.0)) > 0.0:
		parts.append("%s %s/h" % [UIStyle.fmt(float(est["output_per_hour"])), str(est.get("output_name", ""))])
	if float(est.get("xp_to_next", 0.0)) > 0.0 and float(est["xp_per_hour"]) > 0.0:
		parts.append("next level in ≈ %s" % UIStyle.fmt_duration(float(est["xp_to_next"]) / maxf(1.0, float(est["xp_per_hour"])) * 3600.0))
	return "  ·  ".join(parts)

func _on_stop() -> void:
	if CombatManager.state != CombatManager.State.IDLE:
		CombatManager.stop_combat("retreat")
	else:
		SkillManager.stop_action(SkillManager.StopReason.PLAYER)
	refresh()

func _on_eat() -> void:
	if CombatManager.eat_best_food() != "":
		refresh()
func _spawn_text() -> String:
	if EventDirector.active_spawn.is_empty():
		return ""
	var skill_id: String = str(EventDirector.active_spawn.get("skill_id", ""))
	var target: String = str(EventDirector.active_spawn.get("target_action", ""))
	var action_name: String = str(DataLoader.get_action(skill_id, target).get("name", target))
	return "Bonus: %s (%d left)" % [action_name, int(EventDirector.active_spawn.get("actions_left", 0))]

func _on_switch() -> void:
	EventDirector.accept_spawn()
	refresh()

func _on_event_offered(event: Dictionary) -> void:
	# Only cards interrupt: a spawn offer is already announced by activity_changed -> refresh.
	if str(event.get("kind", "")) != "card":
		return
	if _card_dialog != null and is_instance_valid(_card_dialog):
		return   # the loop is paused while a card waits — there is never a second one
	_card_dialog = ConfirmDialog.ask_event(self, event)

func _on_event_resolved(_event_id: String, _policy: String) -> void:
	# Every resolution route — button, stored policy or watchdog — lands here and closes the card.
	_close_card_dialog()
	refresh()

func _close_card_dialog() -> void:
	if _card_dialog != null and is_instance_valid(_card_dialog):
		_card_dialog.queue_free()
	_card_dialog = null
