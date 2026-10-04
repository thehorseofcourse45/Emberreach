extends Node
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("CROP/KILN FAIL: ", message)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	for sid in ["farming", "firemaking"]: PlayerData.skills[sid] = {"level": 120, "xp": 0.0}
	call_deferred("run")

func run() -> void:
	get_window().size = Vector2i(1200, 900)
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
	var seen: Dictionary = {}
	for sid in ["farming", "firemaking"]:
		layout.add_child(UIStyle.title("Husbandry crops" if sid == "farming" else "Kilncraft", 23))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 8)
		layout.add_child(grid)
		for action in DataLoader.get_skill_actions(sid):
			var row: Control = Widgets.activity_row(sid, action, false, func(_id): pass)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(row)
			var preview: TextureRect = row.get_child(0).get_child(0).get_child(0)
			var path := "res://assets/icons/%s/%s.png" % [sid, action.id]
			check(preview.texture.resource_path == path, "assigned " + path)
			check(preview.texture.get_size() == Vector2(32,32), "32x32")
			check(not seen.has(path), "unique path")
			seen[path] = true
	check(seen.size() == 21, "all 21 activities covered")
	var farm = preload("res://scripts/ui/panels/FarmPanel.gd").new()
	var crop_actions: Array = DataLoader.get_skill_actions("farming")
	for index in crop_actions.size():
		var seed := FarmingManager.seed_id_for_action(str(crop_actions[index].id))
		FarmingManager.plots[index].seed_id = seed
		FarmingManager.plots[index].alive = true
		FarmingManager.plots[index].planted_unix = Time.get_unix_time_from_system()
		FarmingManager.plots[index].grow_seconds = 10000.0
		var card: Control = farm._plot_card(index, "Plot")
		var preview: TextureRect = card.get_child(0).get_child(0).get_child(0)
		check(preview.texture.resource_path == "res://assets/icons/farming/%s.png" % crop_actions[index].id, "plot crop icon")
		card.free()
	var planter := MenuButton.new()
	farm._fill_planter(planter, 0)
	check(planter.get_popup().item_count == 10, "all ten crops in picker")
	for index in crop_actions.size():
		check(planter.get_popup().get_item_icon(index).resource_path == "res://assets/icons/farming/%s.png" % crop_actions[index].id, "picker crop icon")
	planter.free()
	farm.free()
	for frame in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/crop_kiln_game.png")
	print("CROP/KILN ICONS: %d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures else 0)
