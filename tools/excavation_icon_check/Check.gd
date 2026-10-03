extends Node
var checks := 0
var failures := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("EXCAVATION FAIL: ", description)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	PlayerData.skills.archaeology = {"level": 120, "xp": 0.0}
	call_deferred("run")

func run() -> void:
	get_window().size = Vector2i(1200, 800)
	var background := ColorRect.new()
	background.color = UITokens.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.theme = UIStyle.build_theme()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	layout.add_child(UIStyle.title("Excavation · unique dig sites", 23))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	layout.add_child(grid)
	var seen: Dictionary = {}
	for action in DataLoader.get_skill_actions("archaeology"):
		var row: Control = Widgets.activity_row("archaeology", action, false, func(_id): pass)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(row)
		var preview: TextureRect = row.get_child(0).get_child(0).get_child(0)
		var path := "res://assets/icons/archaeology/%s.png" % action.id
		check(preview.texture.resource_path == path, "target sprite assigned: " + action.id)
		check(preview.texture.get_size() == Vector2(32, 32), "32x32 icon")
		check(not seen.has(path), "unique asset per target")
		seen[path] = true
	check(seen.size() == 11, "all eleven activities covered")
	for frame in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/excavation_game.png")
	print("EXCAVATION ICONS: %d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures else 0)
