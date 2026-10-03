extends Node
var checks := 0
var failures := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("STARREADING FAIL: ", description)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	PlayerData.skills.astrology = {"level": 120, "xp": 0.0}
	call_deferred("run")

func run() -> void:
	get_window().size = Vector2i(1200, 850)
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
	layout.add_child(UIStyle.title("Starreading · colored stardust", 23))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	layout.add_child(grid)
	var seen: Dictionary = {}
	var previews: Array = []
	for action in DataLoader.get_skill_actions("astrology"):
		var row: Control = Widgets.activity_row("astrology", action, false, func(_id): pass)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(row)
		var preview: TextureRect = row.get_child(0).get_child(0).get_child(0)
		check(preview.texture.resource_path == "res://assets/icons/items/stardust.png", "original sprite preserved")
		check(preview.texture.get_size() == Vector2(32, 32), "32x32 icon")
		check(preview.material.get_shader_parameter("dust_color") == Color(action.icon_tint), "assigned tint")
		check(not seen.has(action.icon_tint), "unique named color")
		seen[action.icon_tint] = true
		previews.append(preview)
		row.add_child(UIStyle.label(str(action.icon_color_name), true, 13))
	check(previews.size() == 18, "all eighteen activities covered")
	for frame in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image = get_viewport().get_texture().get_image()
	var signatures: Dictionary = {}
	for preview in previews:
		var rgb := Vector3.ZERO
		for y in range(int(preview.global_position.y), int(preview.global_position.y + preview.size.y)):
			for x in range(int(preview.global_position.x), int(preview.global_position.x + preview.size.x)):
				var pixel := rendered.get_pixel(x, y)
				rgb += Vector3(pixel.r, pixel.g, pixel.b)
		var signature := str(rgb.snapped(Vector3(0.1, 0.1, 0.1)))
		check(not signatures.has(signature), "rendered colors are visually distinct")
		signatures[signature] = true
	rendered.save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/starreading_colors.png")
	print("STARREADING ICONS: %d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures else 0)
