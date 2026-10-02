extends Node
const Support = preload("res://scripts/tests/TestSupport.gd")
const Skills = preload("res://scripts/ui/panels/SkillsPanel.gd")
var failures: int = 0
var checks: int = 0
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("_run")

func _run() -> void:
	SimulationMode.begin()
	PlayerData.initialize_new_game()
	PlayerData.gp = 1000000000
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid), 120)
	BankManager.purchased_slots = 2000
	for id in DataLoader.items: BankManager.add_item_guaranteed(str(id), 1000)
	ArchaeologyManager.tokens = 10000
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.theme = UIStyle.build_theme()
	add_child(layout)
	for sid in DataLoader.get_skill_ids():
		var panel := Skills.new()
		layout.add_child(panel)
		var actions: Array = DataLoader.get_skill_actions(str(sid))
		panel.focus_route({"skill_id": sid, "action_id": str(actions[0].id) if not actions.is_empty() else ""})
		await _measure(panel, str(sid))
		layout.remove_child(panel)
		panel.queue_free()
	for file in ["PrayerPanel", "RaidPanel", "EquipmentPanel", "SettlementPanel", "CombatSimulatorPanel", "CollectionPanel"]:
		var panel: Control = load("res://scripts/ui/panels/" + file + ".gd").new()
		layout.add_child(panel)
		await _measure(panel, file)
		layout.remove_child(panel)
		panel.queue_free()
	layout.queue_free()
	print("RECOMMENDATIONS UI: ", checks, " checks, ", failures, " failed")
	get_tree().quit(1 if failures else 0)

func _measure(panel: Control, id: String) -> void:
	for width in [420, 1440]:
		get_window().size = Vector2i(width, 1000)
		for frame in range(4): await get_tree().process_frame
		checks += 1
		if panel.get_combined_minimum_size().x > width:
			failures += 1
			print("UI FAIL ", id, " @", width, ": ", Support.widest_descendant(panel))
		if "--render-recommendations" in OS.get_cmdline_user_args() and id in ["woodcutting", "astrology", "RaidPanel", "PrayerPanel", "EquipmentPanel"]:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/recommendations_%s_%d.png" % [id, width])
