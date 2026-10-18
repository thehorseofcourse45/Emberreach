extends Node
## Run through Godot headless with APPDATA and LOCALAPPDATA redirected.
var checks: int = 0
var failures: int = 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", description)

func contains_label(node: Node, needle: String) -> bool:
	if node is Label and (node as Label).text.contains(needle):
		return true
	for child in node.get_children():
		if contains_label(child, needle):
			return true
	return false

func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("_run")

func _run() -> void:
	GameManager.start_new_game("standard")
	var actions: Array = DataLoader.get_skill_actions("thieving")
	check(actions.size() == 36, "Every Larceny target is present")
	var valid: bool = true
	var has_rare: bool = true
	for action in actions:
		var table: Array = action.get("pickpocket_loot", [])
		valid = valid and preload("res://scripts/core/PickpocketLoot.gd").valid_table(table, DataLoader.items)
		has_rare = has_rare and table.any(func(e): return float(e.get("chance", 0.0)) <= 0.01)
	check(valid, "All targets have six valid existing-item chance entries totaling 100 percent")
	check(has_rare, "Every target has a rare one-percent-or-less loot result")
	var man: Dictionary = DataLoader.get_action("thieving", "man")
	var loot: Array = man.get("pickpocket_loot", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = 50120
	var counts: Dictionary = {}
	for _attempt in range(20000):
		var item: Dictionary = preload("res://scripts/core/PickpocketLoot.gd").roll(loot, rng)
		var item_id: String = str(item.get("item_id", ""))
		counts[item_id] = int(counts.get(item_id, 0)) + 1
		if int(item.get("quantity", 0)) < 1:
			valid = false
	check(valid and counts.keys().size() == 6, "Every loot entry can actually roll")
	check(absf(float(counts.get("raw_shrimp", 0)) / 20000.0 - 0.34) < 0.025,
		"Common rewards follow the authored 34 percent rate")
	check(absf(float(counts.get("gold_ring", 0)) / 20000.0 - 0.01) < 0.005,
		"Rare rewards follow the authored 1 percent rate")
	var projection: Dictionary = ActionEstimates.for_action("thieving", "man")
	check(float(projection.get("outputs_per_hour", {}).get("raw_shrimp", 0.0)) > 0.0,
		"Planning estimates include the pickpocket loot pool")
	var source: Array = Goals._producer_recipes("raw_shrimp")
	check(source.any(func(x): return str(x.get("skill_id", "")) == "thieving" and str(x.get("action_id", "")) == "man"),
		"Where-to-find shows Larceny item sources")
	var shared_source: Array = Goals._producer_recipes("sourweed_seed").filter(
		func(x): return str(x.get("skill_id", "")) == "thieving" and str(x.get("action_id", "")) == "farmer")
	check(shared_source.size() == 1 and absf(float(shared_source[0].get("chance", 0.0)) - 0.37) < 0.0001,
		"Overlapping primary and bonus items show one source with combined odds")
	check(SkillManager.start_action("thieving", "man"), "The real Larceny activity starts")
	var successes: int = 0
	var awarded: int = 0
	var failures_awarded_nothing: bool = true
	for _attempt in range(100):
		var result: Dictionary = SkillManager.perform_action()
		if not bool(result.get("success", false)):
			failures_awarded_nothing = failures_awarded_nothing and (result.get("items", {}) as Dictionary).is_empty()
			continue
		successes += 1
		var table_items: int = 0
		for entry in loot:
			table_items += int(result.get("items", {}).get(str(entry.get("item_id", "")), 0))
		if table_items > 0:
			awarded += 1
	check(successes > 20 and awarded == successes,
		"Each successful actual pickpocket yields a real banked loot item")
	check(failures_awarded_nothing, "Failed pickpockets cannot grant the new rewards")
	SkillManager.stop_action()
	check(BankManager.get_count("raw_shrimp") > 0, "Stolen goods land in storage")
	check(not (DataLoader.get_action("thieving", "king").get("secondary_outputs", []) as Array).is_empty(),
		"Independent seed and rare drops remain in older Larceny rewards")
	var panel := preload("res://scripts/ui/panels/SkillsPanel.gd").new()
	add_child(panel)
	panel.focus_route({"skill_id": "thieving", "action_id": "man"})
	check(contains_label(panel, "Pickpocket loot"), "Larceny activity presents its loot table")
	check(contains_label(panel, "34.0%") and contains_label(panel, "Gold Ring"),
		"Activity details display each item's named percentage chance")
	check(contains_label(panel, "Independent bonus drops"),
		"Existing bonus seed chances are shown separately")
	panel.queue_free()
	print("Larceny loot: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
