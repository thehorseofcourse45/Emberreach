extends Node
## Headless save-slot acceptance checks. Run with APPDATA redirected to a temporary directory.
## The checks write real slot files and must never be run using a player's normal user data.

var checks: int = 0
var failures: int = 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", description)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("_run_checks")

func _run_checks() -> void:
	GameManager.start_new_game("standard")
	check(SaveManager.SLOT_COUNT == 5, "Five slots available")
	check(SaveManager.active_slot == 1, "First slot selected in fresh test data")
	check(SaveManager.validate_save(SaveManager.build_save_data()).is_empty(), "Save fixture valid")
	PlayerData.gp = 1101.0
	check(bool(SaveManager.save_to_slot(1).get("ok", false)), "Save initial slot")
	check(bool(SaveManager.get_slot_info(1).get("exists", false)), "First slot exists")
	check(not bool(SaveManager.get_slot_info(2).get("exists", false)), "Other slot starts empty")
	check(bool(SaveManager.rename_slot(1, "Before Update").get("ok", false)), "Rename first slot")
	check(str(SaveManager.get_slot_info(1).get("name", "")) == "Before Update", "Slot name persisted")
	check(bool(SaveManager.save_to_slot(2, true).get("ok", false)), "Create and activate second slot")
	check(SaveManager.active_slot == 2 and bool(SaveManager.get_slot_info(2).get("active", false)), "Active slot switched")
	SaveManager._load_slot_index()
	check(SaveManager.active_slot == 2 and str(SaveManager.get_slot_info(1).get("name", "")) == "Before Update",
		"Active slot and custom name persist when the slot index is reloaded")
	PlayerData.gp = 2202.0
	check(bool(SaveManager.save_to_slot(2).get("ok", false)), "Save unique progress in second slot")
	GameManager.cli_mode = false
	var autosaved: bool = SaveManager.save_game()
	GameManager.cli_mode = true
	check(autosaved and FileAccess.file_exists(SaveManager.SAVE_PATH),
		"Ordinary save writes the live file and the active slot")
	check(is_equal_approx(float((SaveManager._read_json(SaveManager._slot_path(2)) as Dictionary).get("player", {}).get("gp", 0.0)), 2202.0),
		"Automatic save wrote the second slot's actual character progress")
	var code_result: Dictionary = SaveManager.export_slot_code(2)
	check(bool(code_result.get("ok", false)), "Export code")
	var code: String = str(code_result.get("code", ""))
	check(code.begins_with(SaveManager.PORTABLE_PREFIX), "Portable code has version prefix")
	var imported: Dictionary = SaveManager.import_slot_code(3, code, false)
	if not bool(imported.get("ok", false)):
		print("Import code reason: ", imported.get("reason", ""))
	check(bool(imported.get("ok", false)), "Import code without activating another slot")
	check(SaveManager.active_slot == 2 and bool(SaveManager.get_slot_info(3).get("exists", false)), "Code import leaves active slot untouched")
	var export_path: String = "user://slot_roundtrip_test.json"
	check(bool(SaveManager.export_slot_file(2, export_path).get("ok", false)), "Export portable JSON")
	var imported_file: Dictionary = SaveManager.import_slot_file(4, export_path, false)
	if not bool(imported_file.get("ok", false)):
		print("Import file reason: ", imported_file.get("reason", ""))
	check(bool(imported_file.get("ok", false)), "Import portable JSON")
	check(bool(SaveManager.get_slot_info(4).get("exists", false)), "File import persisted to target slot")
	var before: String = JSON.stringify(SaveManager._read_json(SaveManager._slot_path(4)))
	var malformed: String = "INVALID:" + code.substr(0, 18)
	check(not bool(SaveManager.import_slot_code(4, malformed, false).get("ok", false)), "Damaged compressed code rejected")
	check(JSON.stringify(SaveManager._read_json(SaveManager._slot_path(4))) == before, "Bad code does not mutate slot")
	var packed: PackedByteArray = Marshalls.base64_to_raw(code.substr(SaveManager.PORTABLE_PREFIX.length()))
	var envelope: Dictionary = JSON.parse_string(packed.decompress_dynamic(SaveManager.MAX_IMPORT_BYTES, FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	var payload: Dictionary = JSON.parse_string(str(envelope.get("payload", "")))
	var player: Dictionary = payload.get("player", {})
	player["gp"] = 99999999.0
	payload["player"] = player
	envelope["payload"] = JSON.stringify(payload)
	var altered_code: String = SaveManager.PORTABLE_PREFIX + Marshalls.raw_to_base64(
		JSON.stringify(envelope).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))
	check(not bool(SaveManager.import_slot_code(4, altered_code, false).get("ok", false)), "Tampered content fails checksum")
	check(JSON.stringify(SaveManager._read_json(SaveManager._slot_path(4))) == before, "Tampered code leaves slot unchanged")
	var damaged_path: String = "user://slot_roundtrip_tampered.json"
	var file := FileAccess.open(damaged_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope))
	file.close()
	check(not bool(SaveManager.import_slot_file(4, damaged_path, false).get("ok", false)), "Tampered file rejected")
	check(JSON.stringify(SaveManager._read_json(SaveManager._slot_path(4))) == before, "Tampered file leaves slot unchanged")
	var future_data: Dictionary = SaveManager.build_save_data()
	future_data["save_version"] = SaveManager.SAVE_VERSION + 1
	var future_envelope: Dictionary = SaveManager._portable_envelope(future_data)
	var future_code: String = SaveManager.PORTABLE_PREFIX + Marshalls.raw_to_base64(
		JSON.stringify(future_envelope).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))
	check(not bool(SaveManager.import_slot_code(4, future_code, false).get("ok", false)),
		"A correctly checksummed save from a newer format is rejected")
	check(JSON.stringify(SaveManager._read_json(SaveManager._slot_path(4))) == before,
		"Future-version save cannot overwrite current progress")
	check(not bool(SaveManager.import_slot_code(2, code, false).get("ok", false)), "Active slot cannot be overwritten without loading")
	var load_3: Dictionary = SaveManager.load_slot(3)
	check(bool(load_3.get("ok", false)) and SaveManager.active_slot == 3, "Load third slot and activate")
	check(is_equal_approx(PlayerData.gp, 2202.0), "Code roundtrip restores earned gold")
	check(bool(SaveManager.load_slot(1).get("ok", false)), "Load original slot")
	check(is_equal_approx(PlayerData.gp, 1101.0), "Original slot retained independent progress")
	check(not bool(SaveManager.delete_slot(1).get("ok", false)), "Active slot cannot be deleted")
	check(bool(SaveManager.delete_slot(4).get("ok", false)) and not bool(SaveManager.get_slot_info(4).get("exists", false)), "Delete inactive slot")
	check(not bool(SaveManager.load_slot(4).get("ok", false)), "Loading deleted slot fails")
	var raw_legacy_path: String = "user://save_slot_legacy.json"
	var legacy_data: Dictionary = SaveManager.build_save_data()
	legacy_data["save_version"] = 2
	var legacy_file := FileAccess.open(raw_legacy_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy_data))
	legacy_file.close()
	check(bool(SaveManager.import_slot_file(5, raw_legacy_path, false).get("ok", false)),
		"Previous-version raw JSON exports remain importable")
	check(bool(SaveManager.get_slot_info(5).get("exists", false))
		and SaveManager.detect_version(SaveManager._read_json(SaveManager._slot_path(5))) == SaveManager.SAVE_VERSION,
		"Legacy import migrates the save into the current format")
	check(SaveManager.validate_save(SaveManager._read_json(SaveManager._slot_backup(2))).is_empty(),
		"Second slot has a valid automatically rotated backup")
	var backup_gp: float = float((SaveManager._read_json(SaveManager._slot_backup(2)) as Dictionary).get("player", {}).get("gp", 0.0))
	var corrupted_slot := FileAccess.open(SaveManager._slot_path(2), FileAccess.WRITE)
	corrupted_slot.store_string("{ \"unreadable\": true }")
	corrupted_slot.close()
	check(bool(SaveManager.get_slot_info(2).get("exists", false)),
		"Corrupted primary remains available through slot backup")
	check(bool(SaveManager.load_slot(2).get("ok", false)),
		"Loading damaged primary restores its valid backup")
	check(is_equal_approx(PlayerData.gp, backup_gp),
		"Recovered backup restores the previous successfully written progress")
	# Switching to a slot catches up its time away, exactly like loading it at boot.
	var away_data: Dictionary = SaveManager._read_json(SaveManager._slot_path(3))
	away_data["player"]["last_offline_unix"] = int(Time.get_unix_time_from_system()) - 3600
	check(SaveManager._write_slot_snapshot(3, JSON.stringify(away_data)), "Slot with an hour away written")
	check(bool(SaveManager.load_slot(3).get("ok", false)) and OfflineProgression.is_running,
		"Switching to a slot starts its offline catch-up")
	var steps: int = 0
	while OfflineProgression.is_running and steps < 10000:
		steps += 1
		OfflineProgression._step_chunk()
	check(float(OfflineProgression.last_summary().get("elapsed_seconds", 0.0)) >= 3500.0,
		"The switched-in slot is credited its hour away")
	check(PlayerData.last_offline_unix > int(Time.get_unix_time_from_system()) - 10,
		"Catch-up advances the switched-in slot's offline marker")
	OfflineProgression.is_running = true
	check(not bool(SaveManager.load_slot(1).get("ok", false)),
		"Slot switching is blocked during offline progression")
	OfflineProgression.is_running = false
	# Simulate a crash between moving the previous primary away and installing
	# the new snapshot. Startup should recover the staged previous file.
	var staged_path: String = SaveManager._slot_path(4)
	var previous_path: String = staged_path + ".previous"
	var staged_data: Dictionary = SaveManager.build_save_data()
	var staged_file := FileAccess.open(previous_path, FileAccess.WRITE)
	staged_file.store_string(JSON.stringify(staged_data))
	staged_file.close()
	check(not FileAccess.file_exists(staged_path), "Interrupted slot fixture has no primary")
	SaveManager._restore_previous(staged_path)
	check(SaveManager.validate_save(SaveManager._read_json(staged_path)).is_empty(),
		"Interrupted slot replacement restores the previous good primary")
	if SaveManager.validate_save(SaveManager._read_json(SaveManager.BACKUP_PATH)).is_empty():
		var corrupt_live := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		corrupt_live.store_string("{bad data")
		corrupt_live.close()
		check(SaveManager.load_game(), "Corrupt live file recovers from valid backup")
		check(SaveManager.validate_save(SaveManager._read_json(SaveManager.SAVE_PATH)).is_empty(),
			"Recovered primary is restored to disk")
		check(SaveManager.save_game(), "Save succeeds after backup recovery")
		check(JSON.stringify(SaveManager._read_json(SaveManager.BACKUP_PATH)) != "null" and
			SaveManager.validate_save(SaveManager._read_json(SaveManager.BACKUP_PATH)).is_empty(),
			"Post-recovery save preserves a valid backup")
	var panel := preload("res://scripts/ui/panels/SettingsPanel.gd").new()
	add_child(panel)
	check(panel.get("_slot_picker") != null and (panel.get("_slot_picker") as OptionButton).item_count == 5,
		"Settings panel exposes five slots")
	check(panel.get("_slot_code") is TextEdit and panel.get("_slot_file_dialog") is FileDialog,
		"Settings panel exposes code and file import/export")
	panel.queue_free()
	print("Save slots: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
