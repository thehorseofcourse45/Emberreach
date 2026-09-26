extends VBoxContainer
## SettingsPanel — behaviour, accessibility and save management, in one honest place.
##
## Every switch here is wired to a real key in PlayerData.settings that the simulation reads, so
## toggling something either changes behaviour immediately or is stated as taking effect at a
## named moment. Nothing on this screen is decorative.
##
## Save management exposes the parts a player needs to trust the game: where the save lives,
## whether a backup exists, whether another window is active, and a one-click export copy.
## Resetting progress requires an explicit confirmation.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

const EXPORT_DIR: String = "user://exports/"

var _built: bool = false
var _import_menu: OptionButton
var _import_paths: Array[String] = []
var _save_health_box: VBoxContainer

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Settings", UITokens.FONT_DISPLAY))
	add_child(UIStyle.label(
		"These options change how the simulation behaves. Anything that changes a rule says so in its tooltip.",
		true, UITokens.FONT_SMALL))
	_build_offline()
	_build_automation()
	_build_presentation()
	_build_confirmations()
	_build_saves()
	EventBus.state_refreshed.connect(_refresh_save_health)

func focus_route(_route: Dictionary) -> void:
	pass

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Settings",
		"body": "Offline rules, automation thresholds, accessibility and save management. Changes apply immediately and are written with the next autosave."}

# =========================================================================
#  Sections
# =========================================================================

func _build_offline() -> void:
	var box := UIStyle.section("Offline", "what happens while the game is closed")
	add_child(box)
	box.add_child(_check("offline_combat_enabled", "Continue combat while away",
		"When enabled, an active fight keeps running during offline catch-up using the same simulation and the same consumables."))
	box.add_child(_check("offline_auto_repeat", "Keep repeating the current activity offline",
		"Skill actions repeat offline until materials run out, a target is reached, or storage is full."))
	box.add_child(UIStyle.colored_label(
		"Defeat always ends offline combat — that rule is fixed and cannot be disabled, so the game can never farm deaths in your absence.",
		UITokens.TEXT_MUTED, UITokens.FONT_MICRO))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_4)
	row.add_child(UIStyle.label("Offline cap", true, UITokens.FONT_SMALL))
	var caps: Array = [1, 4, 8, 12, 24, 48, 72, 168]
	var labels: Array[String] = []
	var current: float = float(PlayerData.settings.get("offline_cap_hours", 24.0))
	var selected: int = 4
	for i in range(caps.size()):
		labels.append("%d hours" % int(caps[i]))
		if absf(float(caps[i]) - current) < 0.5:
			selected = i
	var menu := Widgets.option_menu(labels, func(i):
		PlayerData.settings["offline_cap_hours"] = float(caps[clampi(i, 0, caps.size() - 1)])
		SaveManager.save_game()
		EventBus.notify("Offline cap set to %d hours." % int(caps[clampi(i, 0, caps.size() - 1)]), "info"), selected)
	menu.tooltip_text = "Time beyond this is excluded and reported in the offline summary rather than silently granted."
	row.add_child(menu)
	box.add_child(row)

func _build_automation() -> void:
	var box := UIStyle.section("Automation", "conveniences bought in the Provisioner")
	add_child(box)
	box.add_child(_check("auto_repeat", "Repeat the current activity",
		"When off, an activity stops after a single action. A quantity target still applies."))
	box.add_child(_check("auto_reuse_potion", "Renew potions automatically",
		"Consume a new potion from storage when the current one runs out of charges."))
	box.add_child(_check("auto_equip_upgrades", "Auto-equip strictly better equipment",
		"Only ever replaces an item when the new one is better in every relevant stat."))
	var tier: int = int(PlayerData.settings.get("auto_eat_tier", 0))
	var eat := UIStyle.label("Auto-eat: %s" % ("not purchased" if tier <= 0 else "tier %d" % tier),
		true, UITokens.FONT_SMALL)
	eat.tooltip_text = "Auto Eat is bought in the Provisioner; this row shows what is currently active."
	box.add_child(eat)

func _build_presentation() -> void:
	var box := UIStyle.section("Presentation", "accessibility and density")
	add_child(box)
	box.add_child(_check("reduced_motion", "Reduce motion",
		"Disables the toast fade-in and shortens interface transitions."))
	box.add_child(_check("compact_rows", "Compact rows",
		"Tightens list spacing so more of a screen fits at once."))
	box.add_child(_check("show_estimates_detail", "Show projection assumptions",
		"Appends the assumptions behind every estimated rate (XP/hour, output/hour)."))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_4)
	row.add_child(UIStyle.label("Interface scale", true, UITokens.FONT_SMALL))
	var scales: Array = [0.9, 1.0, 1.1, 1.25]
	var labels: Array[String] = ["90%", "100%", "110%", "125%"]
	var selected: int = 1
	for i in range(scales.size()):
		if absf(float(scales[i]) - float(PlayerData.settings.get("ui_scale", 1.0))) < 0.01:
			selected = i
	var menu := Widgets.option_menu(labels, func(i):
		var s: float = float(scales[clampi(i, 0, scales.size() - 1)])
		PlayerData.settings["ui_scale"] = s
		_apply_scale()
		SaveManager.save_game(), selected)
	menu.tooltip_text = "Scales the whole interface for readability."
	row.add_child(menu)
	box.add_child(row)

func _build_confirmations() -> void:
	var box := UIStyle.section("Confirmations", "where the game asks first")
	add_child(box)
	box.add_child(_check("confirm_sell_all", "Confirm selling everything",
		"Bulk sales of a whole stack ask before they happen. Single-unit sales never ask."))
	box.add_child(_check("confirm_reset", "Confirm resetting progress",
		"Resetting deletes the save and starts a new journey. Keep this on unless you are certain."))

func _build_saves() -> void:
	var box := UIStyle.section("Saves", "on disk, versioned and backed up")
	add_child(box)
	_save_health_box = UIStyle.vbox(UITokens.SP_2)
	box.add_child(_save_health_box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", UITokens.SP_3)
	var save_now := UIStyle.button("Save now", "Write your progress to disk immediately")
	save_now.pressed.connect(func():
		if SaveManager.save_game():
			EventBus.notify("Progress saved.", "success"))
	buttons.add_child(save_now)
	var export := UIStyle.button("Export a copy", "Write a timestamped JSON copy you can keep or move")
	export.pressed.connect(_on_export)
	buttons.add_child(export)
	box.add_child(buttons)

	var import_row := HBoxContainer.new()
	import_row.add_theme_constant_override("separation", UITokens.SP_4)
	_import_menu = Widgets.option_menu(["No exported copies found"], func(i): pass, 0)
	_import_menu.tooltip_text = "Choose an exported copy to load"
	import_row.add_child(_import_menu)
	var do_import := UIStyle.button("Import selected copy", "Validates the file, migrates it if needed, then loads it")
	do_import.pressed.connect(_on_import)
	import_row.add_child(do_import)
	box.add_child(import_row)
	box.add_child(UIStyle.colored_label(
		"Importing replaces your current progress. The replaced file is rotated into the backup slot, so the previous state is still recoverable.",
		UITokens.TEXT_MUTED, UITokens.FONT_MICRO))

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", UITokens.SP_4)
	mode_row.add_child(UIStyle.label("Mode for a new journey", true, UITokens.FONT_SMALL))
	var mode_ids: Array[String] = []
	var mode_labels: Array[String] = []
	for mode_id in DataLoader.game_modes.keys():
		if str(mode_id).begins_with("_"):
			continue
		mode_ids.append(str(mode_id))
		mode_labels.append("%s — %s" % [str(DataLoader.game_modes[mode_id].get("name", mode_id)),
			_mode_summary(str(mode_id))])
	var mode_selected: int = maxi(0, mode_ids.find(PlayerData.game_mode))
	var mode_menu := Widgets.option_menu(mode_labels, func(i):
		PlayerData.settings["new_game_mode"] = mode_ids[clampi(i, 0, mode_ids.size() - 1)],
		mode_selected)
	mode_menu.tooltip_text = "Applies the next time you start a new journey, not to your current character."
	mode_row.add_child(mode_menu)
	box.add_child(mode_row)

	var reset := UIStyle.danger_button("Reset progress and start over",
		"Deletes the save file and any backup, then begins a new journey")
	reset.pressed.connect(_on_reset)
	box.add_child(reset)
	box.add_child(UIStyle.colored_label(
		"Between sessions the game keeps one automatic backup of the last good save and quarantines any file that fails validation.",
		UITokens.TEXT_MUTED, UITokens.FONT_MICRO))
	_refresh_save_health()

func _mode_summary(mode_id: String) -> String:
	match mode_id:
		"hardcore": return "death is permanent"
		"adventure": return "skills unlocked with gold"
		"ancient_relics": return "low level cap, unlocks through play"
	return "the intended first experience"

# =========================================================================
#  Helpers
# =========================================================================

func _check(key: String, label: String, tooltip: String) -> Control:
	var box := CheckBox.new()
	box.text = label
	box.button_pressed = bool(PlayerData.settings.get(key, false))
	box.tooltip_text = tooltip
	box.add_theme_font_size_override("font_size", UITokens.FONT_SMALL)
	var k: String = key
	box.toggled.connect(func(on: bool):
		var before: Variant = PlayerData.settings.get(k, false)
		PlayerData.settings[k] = on
		if before != on:
			EventBus.notify("%s %s." % [label, "enabled" if on else "disabled"], "info")
			SaveManager.save_game())
	return box

func _apply_scale() -> void:
	var s: float = float(PlayerData.settings.get("ui_scale", 1.0))
	if is_inside_tree():
		get_window().content_scale_factor = clampf(s, 0.75, 2.0)

func _refresh_save_health() -> void:
	if not _built or _save_health_box == null:
		return
	for c in _save_health_box.get_children():
		_save_health_box.remove_child(c)
		c.queue_free()
	var health: Dictionary = SaveManager.save_health()
	_save_health_box.add_child(Widgets.key_value("Save file",
		"present" if bool(health["exists"]) else "not created yet",
		UITokens.GREEN if bool(health["exists"]) else UITokens.AMBER,
		ProjectSettings.globalize_path(SaveManager.SAVE_PATH)))
	_save_health_box.add_child(Widgets.key_value("Automatic backup",
		"present" if bool(health["backup"]) else "none yet",
		UITokens.GREEN if bool(health["backup"]) else UITokens.TEXT_MUTED,
		"Written every time a new save is committed, before the live file is replaced"))
	_save_health_box.add_child(Widgets.key_value("Save format version", str(int(health["version"])),
		UITokens.TEXT, "Older saves are migrated forward automatically; the original is preserved."))
	_save_health_box.add_child(Widgets.key_value("Last write",
		"never" if int(health["last_save_unix"]) <= 0 else UIStyle.fmt_duration(
			maxf(0.0, float(Time.get_unix_time_from_system() - int(health["last_save_unix"])))) + " ago",
		UITokens.GREEN if bool(health["last_save_ok"]) else UITokens.RED,
		"Green means the most recent write reached disk and re-read cleanly"))
	if bool(health.get("session_active_elsewhere", false)):
		_save_health_box.add_child(UIStyle.colored_label(
			"Another window appears to be running this save. Two windows will overwrite each other — keep only one open.",
			UITokens.AMBER, UITokens.FONT_SMALL))
	var note: String = SaveManager.get_migration_note()
	if note != "":
		_save_health_box.add_child(UIStyle.colored_label("Migration: %s" % note, UITokens.BLUE, UITokens.FONT_SMALL))

# =========================================================================
#  Export / import / reset
# =========================================================================

func _on_export() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXPORT_DIR))
	var name: String = "emberreach_%s.json" % Time.get_datetime_string_from_system(false, true).replace(":", "-").replace("T", "_")
	var result: Dictionary = SaveManager.export_save_to(EXPORT_DIR + name)
	if bool(result["ok"]):
		EventBus.notify("Exported a copy to %s" % (EXPORT_DIR + name), "success")
		_reload_import_list()
	else:
		EventBus.notify("Export failed: %s" % str(result["reason"]), "error")

func _reload_import_list() -> void:
	_import_paths.clear()
	if _import_menu == null:
		return
	_import_menu.clear()
	var dir := DirAccess.open(EXPORT_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				_import_paths.append(EXPORT_DIR + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	if _import_paths.is_empty():
		_import_menu.add_item("No exported copies found")
		_import_menu.disabled = true
		return
	_import_menu.disabled = false
	for p in _import_paths:
		_import_menu.add_item(str(p).get_file())

func _on_import() -> void:
	if _import_paths.is_empty():
		EventBus.notify("No exported copies to import.", "warn")
		return
	var index: int = clampi(_import_menu.selected, 0, _import_paths.size() - 1)
	var path: String = _import_paths[index]
	ConfirmDialog.ask(self, "Import this save?",
		"Loading %s replaces your current progress.\n\nYour current save is rotated into the backup slot first, so nothing is destroyed without a copy existing." % path.get_file(),
		"Import", func():
			var result: Dictionary = SaveManager.import_save_from(path)
			if bool(result["ok"]):
				EventBus.notify("Save imported.", "success")
				EventBus.state_refreshed.emit()
				if Screens.shell() != null:
					Screens.shell().call("rebuild_current")
			else:
				EventBus.notify("Import failed: %s" % str(result["reason"]), "error"), true)

func _on_reset() -> void:
	if not bool(PlayerData.settings.get("confirm_reset", true)):
		_do_reset()
		return
	var mode: String = str(PlayerData.settings.get("new_game_mode", PlayerData.game_mode))
	ConfirmDialog.ask(self, "Reset all progress?",
		"This deletes your save file and its automatic backup, then begins a new %s journey.\n\nThis cannot be undone." % mode,
		"Reset everything", _do_reset, true,
		"Exporting a copy first is free and reversible.")

func _do_reset() -> void:
	var mode: String = str(PlayerData.settings.get("new_game_mode", PlayerData.game_mode))
	SaveManager.delete_save()
	GameManager.start_new_game(mode)
	SaveManager.save_game()
	EventBus.notify("Progress reset. A new journey has begun.", "warn")
	Screens.go({"screen": Screens.OVERVIEW})
