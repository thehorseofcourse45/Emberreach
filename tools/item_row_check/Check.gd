extends Node
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ITEM ROW FAIL: ", message)

func _labels(node: Node) -> Array:
	var result: Array = []
	if node is Label: result.append(node)
	for child in node.get_children(): result.append_array(_labels(child))
	return result

func _run() -> void:
	var action: Dictionary = DataLoader.get_skill_actions("cooking")[0]
	var item_id: String = str(action.output_items.keys()[0])
	var name_text: String = str(DataLoader.get_item(item_id).name)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.theme = UIStyle.build_theme()
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 12)
	add_child(margin)
	for width in [220, 260, 420, 1440]:
		get_window().size = Vector2i(width, 850)
		var layout := VBoxContainer.new()
		margin.add_child(layout)
		for with_action in [false, true]:
			var clicked: Array = [false]
			var row: Control = Widgets.item_row(item_id, 1000 if with_action else 1, "Use" if with_action else "", func(): clicked[0] = true)
			layout.add_child(row)
			for frame in range(4): await get_tree().process_frame
			check(row.get_combined_minimum_size().x <= width - 24, "row fits %dpx" % width)
			for label in _labels(row):
				if label.text == name_text: check(label.get_line_count() <= 2, "item name avoids letter-by-letter wrapping at %dpx (%d lines, %.0fpx wide)" % [width, label.get_line_count(), label.size.x])
			var icon: Control = row.get_child(0).get_child(0)
			check(is_equal_approx(icon.size.x, icon.size.y), "icon frame stays square at %dpx (%s)" % [width, icon.size])
			if with_action:
				var buttons: Array = row.find_children("*", "Button", true, false)
				check(buttons.size() == 1, "action remains available")
				if not buttons.is_empty(): buttons[0].pressed.emit()
				check(bool(clicked[0]), "action callback preserved")
			layout.remove_child(row)
			row.queue_free()
		margin.remove_child(layout)
		layout.queue_free()
	get_window().size = Vector2i(260, 850)
	var detail := DetailPanel.new()
	margin.add_child(detail)
	detail.show_recipe("cooking", str(action.id))
	for frame in range(5): await get_tree().process_frame
	for label in _labels(detail):
		if label.text == name_text: check(label.get_line_count() <= 2, "actual recipe-detail output name wraps in words")
	check(detail.get_combined_minimum_size().x <= 236, "actual recipe details fit the sidebar")
	if "--render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var suffix: String = "before" if "--before" in OS.get_cmdline_user_args() else "after"
		get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/item_row_" + suffix + ".png")
	print("ITEM ROW RESULT: ", checks, " checks, ", failures, " failed")
	margin.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
