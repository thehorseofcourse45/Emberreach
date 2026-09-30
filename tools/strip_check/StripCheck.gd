extends Node
const Support = preload("res://scripts/tests/TestSupport.gd")
var failed: int = 0
var checks: int = 0

func _ready() -> void:
	GameManager.cli_mode = true
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		print("STRIP FAIL: ", message)

func _run() -> void:
	var files: Dictionary = Support.backup_save_files()
	var snapshot: Dictionary = SaveManager.build_save_data()
	var paused: bool = GameManager.is_paused
	GameManager.is_paused = true
	var strip := ActivityStrip.new()
	strip.theme = UIStyle.build_theme()
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)
	layout.add_child(strip)
	strip.set_process(false)
	CombatManager.state = CombatManager.State.FIGHTING
	CombatManager.current_monster_id = "chicken"
	CombatManager.monster_max_hp = 20
	CombatManager.monster_hp = 20
	CombatManager.player_hp = CombatManager._compute_max_hp()
	strip.refresh()
	check(strip._hp_bar.visible, "player HP bar shown during combat")
	check(is_equal_approx(strip._bar.value, 0.0), "undamaged enemy starts at zero")
	CombatManager.monster_hp = 10
	CombatManager.player_hp = CombatManager._compute_max_hp() / 2.0
	strip._process(0.0)
	check(is_equal_approx(strip._bar.value, 50.0), "damage updates progress without a refresh signal")
	check(is_equal_approx(strip._hp_bar.value / strip._hp_bar.max_value, 0.5), "HP bar updates live")
	check(strip._estimates.text == "HP %s / %s" % [UIStyle.fmt(CombatManager.player_hp), UIStyle.fmt(CombatManager._compute_max_hp())], "HP number updates live")
	CombatManager.player_hp = CombatManager._compute_max_hp()
	strip._process(0.0)
	check(is_equal_approx(strip._hp_bar.value, strip._hp_bar.max_value), "healing updates HP bar")
	CombatManager.state = CombatManager.State.RESPAWNING
	strip._process(0.0)
	check(strip._bar.value == 0.0 and strip._title.text == "Waiting for the next enemy", "respawn clears stale enemy progress and label")
	CombatManager.state = CombatManager.State.IDLE
	strip.refresh()
	check(not strip._hp_bar.visible, "HP bar hidden outside combat")
	SkillManager.running = true
	SkillManager.active_skill = "woodcutting"
	SkillManager.active_action_id = str(DataLoader.get_skill_actions("woodcutting")[0].id)
	SkillManager.current_interval = 4.0
	SkillManager.progress = 2.0
	strip.refresh()
	GameManager.is_paused = false
	strip._process(0.0)
	check(is_equal_approx(strip._bar.value, 50.0), "skill progress still updates")
	GameManager.is_paused = true
	SkillManager.running = false
	for width in [420, 1440]:
		get_window().size = Vector2i(width, 240)
		for mode in ["idle", "combat", "skill"]:
			CombatManager.state = CombatManager.State.FIGHTING if mode == "combat" else CombatManager.State.IDLE
			SkillManager.running = mode == "skill"
			strip.refresh()
			for frame in range(4):
				await get_tree().process_frame
			check(strip._estimates.size.x >= 72, "%d %s: status text has readable width" % [width, mode])
			check(strip.size.y <= (150 if width == 420 else 80), "%d %s: strip stays compact" % [width, mode])
			check(strip.size.x <= width, "%d %s: strip fits the window" % [width, mode])
			if "--render-strip" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/strip_%d_%s.png" % [width, mode])
	strip.queue_free()
	Support.restore_snapshot(snapshot, files)
	GameManager.is_paused = paused
	check(Support.backup_save_files() == files, "save files restored")
	print("STRIP RESULT: %d checks, %d failures" % [checks, failed])
	get_tree().quit(failed)
