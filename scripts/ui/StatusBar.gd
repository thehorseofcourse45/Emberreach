extends PanelContainer
class_name StatusBar
## StatusBar — essential resources, save health and time controls, always visible.
##
## The save indicator is deliberately textual ("Saved 12:04:31" / "Unsaved changes" /
## "Save failed") as well as coloured, because a player must be able to trust that their
## progress is on disk without interpreting a colour.

var _chips: Dictionary = {}
var _save_label: Label
var _playtime: Label
var _combat_level: Label
var _pause_button: Button
var _speed: OptionButton
var _save_timer: float = 0.0

## The one speed ladder, shared with Settings → Simulation. Both controls read and write
## PlayerData.settings["game_speed"] through GameManager.set_speed, so they cannot disagree.
const GAME_SPEEDS: Array[float] = [1.0, 2.0, 4.0]
const GAME_SPEEDS_LABELS: Array[String] = ["1×", "2×", "4×"]

## The list entry whose speed is closest to a value the engine may already hold (a save can carry
## any speed in the 0.25–16 clamp range, not just the three offered here).
static func _nearest_speed(speed: float) -> float:
	var best: float = GAME_SPEEDS[0]
	for s in GAME_SPEEDS:
		if absf(s - speed) < absf(best - speed):
			best = s
	return best

func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.surface_box("panel"))
	custom_minimum_size = Vector2(0, UITokens.H_HEADER + 8)
	# Flows rather than a plain HBox so the chips and time controls wrap instead of forcing the
	# whole window wider than it is: the minimum width of a single HBox here is ~600px, and the
	# window is allowed to be 420.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UITokens.SP_5)
	row.add_theme_constant_override("v_separation", UITokens.SP_2)
	add_child(row)

	_add_chip(row, "gp", "gp", "Gold pieces — earned by selling and by expeditions")
	_add_chip(row, "slayer_coins", "slayer_coins", "Huntsman coins from contracts and bounties")
	_add_chip(row, "abyssal_coins", "abyssal_coins", "Abyssal coins from late encounters, spent at the Provisioner")
	_add_chip(row, "prayer_points", "prayer_points", "Devotion points — spent per attack while a rite is active")
	_add_chip(row, "stardust", "stardust", "Stardust spent in Starreading")

	_combat_level = UIStyle.label("", true, UITokens.FONT_SMALL)
	row.add_child(_combat_level)

	row.add_child(UIStyle.spacer())

	_save_label = UIStyle.label("Not saved yet", true, UITokens.FONT_SMALL)
	row.add_child(_save_label)

	_playtime = UIStyle.label("", true, UITokens.FONT_SMALL)
	_playtime.tooltip_text = "Total time played"
	row.add_child(_playtime)

	_speed = Widgets.option_menu(GAME_SPEEDS_LABELS, _on_speed,
		maxi(0, GAME_SPEEDS.find(_nearest_speed(GameManager.game_speed))))
	_speed.tooltip_text = "Simulation speed. Slower speeds are useful while learning a system."
	EventBus.game_speed_changed.connect(_on_game_speed_changed)
	row.add_child(_speed)

	_pause_button = UIStyle.button("Pause", "Pause the simulation")
	_pause_button.pressed.connect(_on_pause)
	row.add_child(_pause_button)

	var save_button := UIStyle.button("Save", "Write your progress to disk now")
	save_button.pressed.connect(func():
		if SaveManager.save_game():
			EventBus.notify("Progress saved.", "success"))
	row.add_child(save_button)

	var clear_button := UIStyle.button("Clear", "Delete your save and start over")
	clear_button.pressed.connect(_on_clear)
	row.add_child(clear_button)

	EventBus.gp_changed.connect(func(_a, _t): refresh())
	EventBus.slayer_coins_changed.connect(func(_a, _t): refresh())
	EventBus.abyssal_coins_changed.connect(func(_a, _t): refresh())
	EventBus.prayer_points_changed.connect(func(_t): refresh())
	EventBus.skill_level_up.connect(func(_s, _l): refresh())
	EventBus.state_refreshed.connect(refresh)
	EventBus.bank_changed.connect(refresh)
	refresh()

func _add_chip(parent: Control, icon_id: String, key: String, tooltip: String) -> void:
	var chip := Widgets.resource_chip("currencies", icon_id, "0", tooltip)
	parent.add_child(chip)
	_chips[key] = chip.get_node("value")

func refresh() -> void:
	_set_chip("gp", PlayerData.gp, "currencies", "gp")
	_set_chip("slayer_coins", PlayerData.slayer_coins, "currencies", "slayer_coins")
	_set_chip("abyssal_coins", PlayerData.abyssal_coins, "currencies", "abyssal_coins")
	_set_chip("prayer_points", PlayerData.prayer_points, "currencies", "prayer_points")
	_set_chip("stardust", BankManager.get_count("stardust"), "items", "stardust")
	_combat_level.text = "Combat %d" % PlayerData.get_combat_level()
	_playtime.text = UIStyle.fmt_duration(maxf(0.0, GameManager.playtime_seconds))
	if BankManager.has_overflow():
		_playtime.text += "  ·  overflow %d" % BankManager.overflow_count()

func _set_chip(key: String, value: float, _kind: String, _icon_id: String) -> void:
	if not _chips.has(key):
		return
	var label: Label = _chips[key]
	label.text = UIStyle.fmt(float(value))
	label.tooltip_text = "%s exact: %s" % [label.text, UIStyle.fmt_exact(float(value))]

## Save state, stated in words as well as colour.
func set_save_state(kind: String, message: String) -> void:
	if _save_label == null:
		return
	var color: Color = UITokens.TEXT_MUTED
	match kind:
		"ok":
			color = UITokens.GREEN
		"saving":
			color = UITokens.BLUE
		"error":
			color = UITokens.RED
		"blocked":
			color = UITokens.RED
		"recovered":
			color = UITokens.AMBER
	_save_label.text = message
	_save_label.add_theme_color_override("font_color", color)
	_save_label.tooltip_text = message
	_save_timer = 8.0

func _on_clear() -> void:
	var mode: String = str(PlayerData.settings.get("new_game_mode", PlayerData.game_mode))
	ConfirmDialog.ask(self, "Clear save?",
		"This deletes your save file and its automatic backup, then begins a new %s journey.\n\nThis cannot be undone." % mode,
		"Clear save", _do_clear, true,
		"Exporting a copy first is free and reversible.")

func _do_clear() -> void:
	var mode: String = str(PlayerData.settings.get("new_game_mode", PlayerData.game_mode))
	SaveManager.delete_save()
	GameManager.reset_everything(mode)
	SaveManager.save_game()
	EventBus.notify("Progress cleared. A new journey has begun.", "warn")
	Screens.go({"screen": Screens.OVERVIEW})

func _on_pause() -> void:
	GameManager.set_paused(not GameManager.is_paused)
	_pause_button.text = "Resume" if GameManager.is_paused else "Pause"

func _on_speed(index: int) -> void:
	GameManager.set_speed(GAME_SPEEDS[clampi(index, 0, GAME_SPEEDS.size() - 1)])

## The speed changed somewhere else (the Settings screen, or a save that carried one), so the
## top bar has to show what is actually running rather than a stale selection of its own.
func _on_game_speed_changed(speed: float) -> void:
	if _speed == null:
		return
	_speed.select(maxi(0, GAME_SPEEDS.find(_nearest_speed(speed))))

func _process(delta: float) -> void:
	_playtime.text = UIStyle.fmt_duration(maxf(0.0, GameManager.playtime_seconds))
	if _save_timer > 0.0:
		_save_timer -= delta
		if _save_timer <= 0.0 and SaveManager.last_save_unix > 0:
			var age: float = float(Time.get_unix_time_from_system() - SaveManager.last_save_unix)
			_save_label.text = "Saved %s ago" % UIStyle.fmt_duration(age) if age > 5.0 else "Saved"
			_save_label.add_theme_color_override("font_color", UITokens.GREEN if SaveManager.last_save_ok else UITokens.RED)
