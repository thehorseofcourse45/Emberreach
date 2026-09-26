extends PanelContainer
class_name ActivityStrip
## ActivityStrip — the persistent "what am I doing right now" bar.
##
## Always visible on every screen, on desktop and mobile, and it never covers a control
## (the shell reserves a fixed row for it rather than floating it over content). It shows the
## activity, its progress, the projected yield, and a single always-available stop control.

var _icon: TextureRect
var _title: Label
var _detail: Label
var _bar: ProgressBar
var _stop: Button
var _estimates: Label

func _ready() -> void:
	custom_minimum_size = Vector2(0, UITokens.H_STRIP + 8)
	add_theme_stylebox_override("panel", UIStyle.surface_box("raised", true))
	# Flows rather than a plain HBox: the estimate text and the Stop button drop to a second line on
	# a narrow window instead of forcing it wider than the screen.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UITokens.SP_5)
	row.add_theme_constant_override("v_separation", UITokens.SP_2)
	add_child(row)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(UITokens.ICON_MD, UITokens.ICON_MD)
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_icon)

	var col := UIStyle.vbox(UITokens.SP_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_title = UIStyle.label("Idle", false, UITokens.FONT_BODY)
	col.add_child(_title)
	_bar = Widgets.progress_bar(0.0, 1.0, UITokens.TEAL, "", 8)
	col.add_child(_bar)
	_detail = UIStyle.label("Choose an activity to begin.", true, UITokens.FONT_MICRO)
	col.add_child(_detail)

	_estimates = UIStyle.label("", true, UITokens.FONT_MICRO)
	_estimates.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# A hard 200px minimum here set the floor for the whole window; wrap instead so the strip can
	# narrow with the window.
	_estimates.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_estimates)

	_stop = UIStyle.danger_button("Stop", "Stop the current activity")
	_stop.pressed.connect(_on_stop)
	row.add_child(_stop)

	EventBus.activity_changed.connect(refresh)
	EventBus.state_refreshed.connect(refresh)
	refresh()

func _process(_delta: float) -> void:
	# Progress is polled from the authoritative simulation rather than animated independently,
	# so the bar can never disagree with the state that grants rewards.
	if SkillManager.running and not GameManager.is_paused:
		_bar.value = clampf(SkillManager.progress / maxf(SkillManager.current_interval, 0.001), 0.0, 1.0) * 100.0

func refresh() -> void:
	var activity: Dictionary = GameManager.current_activity()
	var kind: String = str(activity.get("kind", "idle"))
	_title.text = str(activity.get("label", "Idle"))
	_detail.text = str(activity.get("detail", ""))
	match kind:
		"skill":
			_icon.texture = AssetRegistry.skill_icon(str(activity.get("id", "")))
			_bar.max_value = 100.0
			_bar.value = float(activity.get("progress", 0.0)) * 100.0
			_bar.add_theme_stylebox_override("fill", UIStyle._solid(UITokens.TEAL, UITokens.R_SM))
			_estimates.text = _skill_estimates(str(activity.get("id", "")), str(activity.get("action_id", "")))
		"combat":
			_icon.texture = AssetRegistry.monster_sprite(CombatManager.current_monster_id)
			_bar.max_value = 100.0
			_bar.value = float(activity.get("progress", 0.0)) * 100.0
			_bar.add_theme_stylebox_override("fill", UIStyle._solid(UITokens.RED, UITokens.R_SM))
			_estimates.text = "HP %s / %s" % [UIStyle.fmt(CombatManager.player_hp),
				UIStyle.fmt(CombatManager._compute_max_hp())]
		"stopped":
			_icon.texture = AssetRegistry.icon("status", "warning")
			_bar.value = 0.0
			_estimates.text = ""
		_:
			_icon.texture = AssetRegistry.icon("status", "idle")
			_bar.value = 0.0
			_estimates.text = ""
	_stop.disabled = kind == "idle" or kind == "stopped"
	_stop.text = "Retreat" if kind == "combat" else "Stop"

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
