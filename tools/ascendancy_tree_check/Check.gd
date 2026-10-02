extends Node
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("TREE FAIL: ", message)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	SaveManager._write_in_progress = true # Transactions exercise UI without writing the player's save.
	call_deferred("run")

func run() -> void:
	PlayerData.prestige = {"points": 0, "nodes": {}}
	var panel = load("res://scripts/ui/panels/PrestigePanel.gd").new()
	add_child(panel)
	panel._open_tree()
	var tree = panel._tree_window
	for i in 10: await get_tree().process_frame
	check(tree._cards.size() == 48, "all 48 upgrades visible before first ascension")
	var validator := ContentValidator.new()
	validator._check_ascendancy()
	check(validator.issues.is_empty(), "expanded tree content validates")
	var edge_count := 0
	var branches: Dictionary = {}
	for id in tree._cards:
		edge_count += DataLoader.ascendancy[id].get("requires", []).size()
		branches[DataLoader.ascendancy[id].branch] = true
	check(branches.size() == 8, "eight distinct branches")
	check(tree.graph.get_connection_list().size() == edge_count, "all prerequisites connected")
	for id in tree._cards:
		check(tree._cards[id].buy.disabled, "zero points cannot purchase " + str(id))
		for req in DataLoader.ascendancy[id].get("requires", []):
			check(tree.graph.is_node_connected(req, 0, id, 0), "prerequisite line " + str(id))
		for other in tree._cards:
			if other == id: continue
			check(not Rect2(tree._cards[id].card.position_offset, tree._cards[id].card.size).intersects(Rect2(tree._cards[other].card.position_offset, tree._cards[other].card.size)), "cards do not overlap")
	PlayerData.prestige.points = 20
	EventBus.state_refreshed.emit()
	check(not tree._cards.ascendant_insight.buy.disabled, "root becomes purchasable")
	check(tree._cards.ascendant_bounty.buy.disabled, "child stays locked")
	tree._cards.ascendant_insight.buy.pressed.emit()
	check(PrestigeManager.node_rank("ascendant_insight") == 1, "buy button spends point")
	check(not tree._cards.ascendant_bounty.buy.disabled, "buy unlocks child")
	tree._cards.ascendant_bounty.buy.pressed.emit()
	tree._cards.ascendant_insight.refund.pressed.emit()
	check(PrestigeManager.node_rank("ascendant_insight") == 1, "dependent parent cannot be refunded")
	tree._cards.ascendant_bounty.refund.pressed.emit()
	check(PrestigeManager.node_rank("ascendant_bounty") == 0, "refund works")
	check(PrestigeManager.points() == 19, "refund returns exact cost")
	var offset: Vector2 = tree.graph.scroll_offset
	var at: Vector2 = tree.graph.position + Vector2(100, tree.graph.size.y - 80)
	var press := InputEventMouseButton.new()
	press.position = at
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	tree.push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = at + Vector2(80, 30)
	motion.relative = Vector2(80, 30)
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	tree.push_input(motion, true)
	press.position = motion.position
	press.pressed = false
	tree.push_input(press, true)
	await get_tree().process_frame
	check(tree.graph.scroll_offset != offset, "middle drag pans the tree")
	var zoom: float = tree.graph.zoom
	press.button_index = MOUSE_BUTTON_WHEEL_UP
	press.pressed = true
	tree.push_input(press, true)
	await get_tree().process_frame
	check(tree.graph.zoom > zoom, "wheel zooms the tree")
	var pan: Vector2 = tree.graph.scroll_offset
	EventBus.state_refreshed.emit()
	check(tree.graph.scroll_offset == pan, "refresh preserves view")
	# Left drag pans from blank canvas and card text, but buttons retain normal clicks.
	tree.reset_view()
	for frame in 3: await get_tree().process_frame
	var blank: Vector2 = tree.graph.global_position + Vector2(100, tree.graph.size.y - 70)
	var old_pan: Vector2 = tree.graph.scroll_offset
	await left_drag(tree, blank, Vector2(55, 25))
	check(tree.graph.scroll_offset.is_equal_approx(old_pan - Vector2(55, 25)), "left drag pans blank canvas")
	check(not tree.graph._panning, "release ends panning")
	tree.reset_view()
	for frame in 3: await get_tree().process_frame
	var drag_card: GraphNode = tree._cards.ascendant_insight.card
	var on_card: Vector2 = drag_card.global_position + Vector2(30, 55) * tree.graph.zoom
	old_pan = tree.graph.scroll_offset
	await left_drag(tree, on_card, Vector2(-40, 35))
	check(tree.graph.scroll_offset.is_equal_approx(old_pan - Vector2(-40, 35)), "left drag pans card text")
	tree.reset_view()
	for frame in 3: await get_tree().process_frame
	var buy: Button = tree._cards.ascendant_insight.buy
	var on_button: Vector2 = buy.global_position + buy.size * tree.graph.zoom * 0.5
	old_pan = tree.graph.scroll_offset
	var old_rank: int = PrestigeManager.node_rank("ascendant_insight")
	await left_drag(tree, on_button, Vector2.ZERO)
	check(tree.graph._over_interactive(tree.graph, on_button), "purchase button is excluded from drag handling")
	buy.pressed.emit()
	check(PrestigeManager.node_rank("ascendant_insight") == old_rank + 1, "excluded button still purchases upgrade")
	check(tree.graph.scroll_offset == old_pan and not tree.graph._panning, "button click does not pan")
	var map_point: Vector2 = tree.graph.global_position + tree.graph.size - Vector2(90, 70)
	check(tree.graph._over_interactive(tree.graph, map_point), "minimap is excluded from panning")
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.position = Vector2(5, 5)
	outside.pressed = true
	tree.push_input(outside, true)
	check(not tree.graph._panning, "outside canvas cannot start panning")
	# Buy and refund every rank through the real UI without disk writes.
	PlayerData.prestige = {"points": 1000, "nodes": {}}
	PrestigeManager._reapply()
	var remaining: Array = tree._cards.keys()
	var expected: Dictionary = {}
	var total_cost := 0
	while not remaining.is_empty():
		var progressed := false
		for id in remaining.duplicate():
			if not PrestigeManager.node_state(id).can_buy: continue
			var data: Dictionary = DataLoader.ascendancy[id]
			for rank in int(data.max_rank):
				tree._cards[id].buy.pressed.emit()
				total_cost += int(data.cost)
			check(tree._cards[id].buy.disabled, "maximum rank disables buy: " + str(id))
			check(not PrestigeManager.spend(id).ok, "cannot overspend maximum: " + str(id))
			for key in data.modifiers:
				expected[key] = float(expected.get(key, 0)) + float(data.modifiers[key]) * int(data.max_rank)
			remaining.erase(id)
			progressed = true
		if not progressed:
			check(false, "unreachable upgrades")
			break
	check(PrestigeManager.points() == 1000 - total_cost, "all costs accounted for")
	var source: Dictionary = ModifierManager.serialize().get("prestige", {}).get("modifiers", {})
	for key in expected:
		check(is_equal_approx(float(source.get(key, 0)), expected[key]), "stacking effect: " + str(key))
	var saved: Dictionary = PrestigeManager.serialize().duplicate(true)
	PlayerData.prestige = {}
	PrestigeManager.deserialize(saved)
	check(PrestigeManager.points_spent() == total_cost, "all purchased upgrades survive save round-trip")
	PrestigeManager.respec()
	check(PrestigeManager.points() == 1000 and not ModifierManager.has_source("prestige"), "respec refunds expanded tree and clears modifiers")
	# Ascend beyond the old cap and earn enough points to max the entire expanded tree.
	for count in [100, 194, 1000]:
		PlayerData.prestige = {"ascensions": count, "total": count, "points": count - 1, "points_earned": count, "nodes": {"ascendant_insight": 1}}
		PlayerData.skills["woodcutting"] = {"xp": 0.0, "level": 1}
		check(not PrestigeManager.can_ascend(), "XP gate still applies beyond old cap")
		check(not PrestigeManager.ascend().ok, "below-gate ascension refused")
		PlayerData.skills["woodcutting"] = {"xp": PrestigeManager.GATE_XP, "level": 1}
		check(PrestigeManager.can_ascend(), "ascension available beyond old cap")
		check(int(PrestigeManager.next_reward().ascension) == count + 1, "next reward has no ceiling")
		check(PrestigeManager.ascend().ok, "actual ascension succeeds beyond old cap")
		check(PrestigeManager.ascensions() == count + 1 and PrestigeManager.points_earned() == count + 1, "count and earned points increment")
		check(PrestigeManager.points() == count and PrestigeManager.node_rank("ascendant_insight") == 1, "points and purchases survive ascension")
		if count == 194:
			check(PrestigeManager.points_earned() >= total_cost, "entire tree can eventually be maxed")
	PlayerData.prestige = {"points": 20, "nodes": {"ascendant_insight": 1}}
	PrestigeManager._reapply()
	EventBus.state_refreshed.emit()
	var navigation: OptionButton = tree.find_children("*", "OptionButton", true, false)[0]
	check(navigation.item_count == 9, "navigation includes all branches")
	for index in range(1, navigation.item_count):
		navigation.select(index)
		navigation.item_selected.emit(index)
		for frame in 3: await get_tree().process_frame
		check(tree.graph.zoom > 0 and tree.graph.scroll_offset.y >= -120, "branch navigation works")
		for id in tree._cards:
			if DataLoader.ascendancy[id].branch != navigation.get_item_text(index): continue
			var card: GraphNode = tree._cards[id].card
			var shown := Rect2(card.position_offset * tree.graph.zoom - tree.graph.scroll_offset, card.size * tree.graph.zoom)
			check(shown.position.x >= 0 and shown.position.y >= 40 and shown.end.x <= tree.graph.size.x and shown.end.y <= tree.graph.size.y, "branch fits viewport: " + str(id))
		if "--render" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			tree.get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/ascendancy_" + navigation.get_item_text(index) + ".png")
	tree.reset_view()
	for i in 6: await get_tree().process_frame
	if "--render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		tree.get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/ascendancy_tree.png")
	tree.close_requested.emit()
	check(not tree.visible, "close hides window")
	panel._open_tree()
	check(panel._tree_window == tree and tree.visible, "reopen reuses window")
	panel.queue_free()
	await get_tree().process_frame
	print("ASCENDANCY TREE: %d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func left_drag(tree: Window, start: Vector2, delta: Vector2) -> void:
	var hover := InputEventMouseMotion.new()
	hover.window_id = tree.get_window_id()
	hover.position = start
	hover.global_position = start
	tree.push_input(hover, true)
	var button := InputEventMouseButton.new()
	button.window_id = tree.get_window_id()
	button.position = start
	button.global_position = start
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = true
	tree.push_input(button, true)
	var motion := InputEventMouseMotion.new()
	motion.window_id = tree.get_window_id()
	motion.position = start + delta
	motion.global_position = start + delta
	motion.relative = delta
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	tree.push_input(motion, true)
	button.position = start + delta
	button.global_position = start + delta
	button.pressed = false
	tree.push_input(button, true)
	await get_tree().process_frame
