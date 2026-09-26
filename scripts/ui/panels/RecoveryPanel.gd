extends VBoxContainer
## RecoveryPanel — shown when a save exists but could not be loaded.
##
## The game never silently replaces a broken save with a new character. This screen states exactly
## what went wrong, where the original file was preserved, and then hands the player the decision:
## retry, restore a quarantined copy, import an exported copy, or start fresh.
##
## Every action here is explicit and every destructive option is confirmed.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _body: VBoxContainer
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Your save could not be loaded", UITokens.FONT_DISPLAY))
	add_child(UIStyle.colored_label(
		"Nothing has been overwritten. The original file is preserved exactly as it was found, and the game is waiting for you to decide what happens next.",
		UITokens.AMBER, UITokens.FONT_SMALL))
	_body = UIStyle.vbox(UITokens.SP_4)
	add_child(_body)
	EventBus.save_status.connect(func(_k, _m): _rebuild())
	_rebuild()

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Recovery",
		"body": "A save that fails validation is quarantined rather than deleted. Choose how to proceed: restore a copy, import an export, or start a new journey deliberately."}

func refresh() -> void:
	_rebuild()

func _rebuild() -> void:
	if not _built:
		return
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()

	var recovery: Dictionary = SaveManager.pending_recovery
	var problems := UIStyle.section("What happened")
	problems.add_child(UIStyle.label(
		str(recovery.get("reason", "The save file could not be read or failed validation.")),
		false, UITokens.FONT_SMALL))
	var detail: String = str(recovery.get("detail", ""))
	if detail != "":
		var d := UIStyle.label(detail, true, UITokens.FONT_SMALL)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		problems.add_child(d)
	if str(recovery.get("quarantine_path", "")) != "":
		problems.add_child(Widgets.key_value("Preserved copy",
			ProjectSettings.globalize_path(str(recovery["quarantine_path"])), UITokens.GREEN,
			"A byte-for-byte copy of the file that failed, kept so nothing is lost"))
	if recovery.has("backup_error"):
		problems.add_child(Widgets.key_value("Backup also rejected",
			str(recovery["backup_error"]), UITokens.AMBER,
			"The automatic backup had its own problem, so it was not loaded silently"))
	if bool(recovery.get("recovered", false)):
		problems.add_child(UIStyle.colored_label(
			"The automatic backup was loaded instead. Your progress was restored from it.",
			UITokens.GREEN, UITokens.FONT_SMALL))
	_body.add_child(problems)

	var choices := UIStyle.section("Choose how to proceed")
	choices.add_child(_choice("Try loading again",
		"Re-reads the save file in case it changed on disk (for example, after a completed sync).",
		"Retry", _on_retry, false))
	var quarantined: Array = _quarantine_files()
	if not quarantined.is_empty():
		choices.add_child(_choice("Restore a preserved copy",
			"Found %d preserved file(s). Restoring one copies it over the live save so it can be loaded normally."
				% quarantined.size(),
			"Restore newest", _on_restore_newest, false))
	choices.add_child(_choice("Import an exported copy",
		"Exported copies live in the Saves section of Settings, where importing them is confirmed.",
		"Open Settings", func(): navigated.emit({"screen": Screens.SETTINGS}), false))
	choices.add_child(_choice("Start a new journey",
		"Begins a fresh character. The preserved copy above stays on disk and is not deleted.",
		"Start new journey", _on_start_new, true))
	choices.add_child(_choice("Quit without saving",
		"Closes the game and leaves every file untouched so you can inspect or back up the save yourself.",
		"Quit", func(): get_tree().quit(), false))
	_body.add_child(choices)

func _choice(title: String, body: String, button_text: String, action: Callable, destructive: bool) -> Control:
	var card := UIStyle.card(destructive)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_4)
	card.add_child(row)
	var col := UIStyle.vbox(UITokens.SP_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIStyle.label(title, false, UITokens.FONT_BODY))
	var b := UIStyle.label(body, true, UITokens.FONT_MICRO)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(b)
	row.add_child(col)
	var button := UIStyle.danger_button(button_text) if destructive else UIStyle.primary_button(button_text)
	button.pressed.connect(action)
	row.add_child(button)
	return card

func _quarantine_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open("user://")
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with("save_game.corrupt_") and file_name.ends_with(".json"):
			out.append("user://" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	out.reverse()   # newest timestamp first
	return out

func _on_retry() -> void:
	if SaveManager.load_game():
		EventBus.notify("Save loaded successfully.", "success")
		EventBus.state_refreshed.emit()
		navigated.emit({"screen": Screens.OVERVIEW})
	else:
		EventBus.notify("The save still could not be loaded.", "warn")
		_rebuild()

func _on_restore_newest() -> void:
	var files: Array = _quarantine_files()
	if files.is_empty():
		EventBus.notify("No preserved copies were found.", "warn")
		return
	var newest: String = str(files[0])
	ConfirmDialog.ask(self, "Restore this copy?",
		"This copies the preserved file back over the live save:\n%s\n\nThe file currently in the live slot is preserved first, so both versions remain on disk." % newest,
		"Restore", func():
			# Preserve whatever is in the live slot before overwriting it.
			if FileAccess.file_exists(SaveManager.SAVE_PATH):
				var keep: String = "user://save_game.corrupt_%d.json" % int(Time.get_unix_time_from_system())
				DirAccess.copy_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH),
					ProjectSettings.globalize_path(keep))
			DirAccess.copy_absolute(ProjectSettings.globalize_path(newest),
				ProjectSettings.globalize_path(SaveManager.SAVE_PATH))
			SaveManager.pending_recovery.clear()
			if SaveManager.load_game():
				EventBus.notify("Preserved copy restored and loaded.", "success")
				EventBus.state_refreshed.emit()
				navigated.emit({"screen": Screens.OVERVIEW})
			else:
				EventBus.notify("That copy could not be loaded either — it is still preserved.", "error")
				_rebuild(), true)

func _on_start_new() -> void:
	ConfirmDialog.ask(self, "Start a new journey?",
		"A new character is created. The preserved copy of your old save stays on disk — you can restore it later from this screen as long as the game stays closed until then.",
		"Start new journey", func():
			GameManager.recover_with_new_game()
			navigated.emit({"screen": Screens.OVERVIEW}), true)
