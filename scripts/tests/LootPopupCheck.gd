extends Node
## Isolated UI/event regression checks for the global item-received popup feed.
var checks: int = 0
var failures: int = 0
const PopupScript = preload("res://scripts/ui/LootPopupStack.gd")

func verify(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", label)

func contains_text(node: Node, needle: String) -> bool:
	if node is Label and (node as Label).text.contains(needle):
		return true
	for child in node.get_children():
		if contains_text(child, needle):
			return true
	return false

func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("_run")

func _run() -> void:
	GameManager.start_new_game("standard")
	var host := Control.new()
	host.size = Vector2(1200, 800)
	add_child(host)
	var popup: Control = PopupScript.new()
	host.add_child(popup)
	verify(popup.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Loot popups never intercept gameplay input")
	verify((popup.get("_entries") as Array).is_empty(), "No fabricated loot on open")
	BankManager.add_item("raw_shrimp", 2)
	var entries: Array = popup.get("_entries")
	verify(entries.size() == 1 and int(entries[0]["quantity"]) == 2, "Storage gain creates item-and-quantity popup")
	verify(contains_text(entries[0]["node"], "Raw Marsh Shrimp") and contains_text(entries[0]["node"], "×2"),
		"Popup displays the real item name and received quantity")
	BankManager.add_item("raw_shrimp", 3)
	entries = popup.get("_entries")
	verify(entries.size() == 1 and int(entries[0]["quantity"]) == 5 and
		BankManager.get_count("raw_shrimp") == 5,
		"Repeated loot combines into a single count without changing actual bank gains")
	verify(SkillManager.start_action("thieving", "man"), "Larceny activity starts for context test")
	BankManager.add_item("gold_ring", 1)
	entries = popup.get("_entries")
	verify(entries.size() == 2 and str(entries[1]["context"]) == "PICKPOCKETED", "Larceny gets recognizable pickpocket reward wording")
	var successful_steal: bool = false
	for _attempt in range(20):
		var reward: Dictionary = SkillManager.perform_action()
		if bool(reward.get("success", false)):
			successful_steal = not (reward.get("items", {}) as Dictionary).is_empty()
			break
	verify(successful_steal and (popup.get("_entries") as Array).any(
		func(entry): return str(entry.get("context", "")) == "PICKPOCKETED"),
		"Successful real Larceny steals display item notifications")
	SkillManager.stop_action()
	popup.clear()
	BankManager.add_item("raw_shrimp", 1)
	BankManager.add_item("ruby", 1)
	BankManager.add_item("diamond", 1)
	BankManager.add_item("sapphire", 1)
	BankManager.add_item("topaz", 1)
	verify((popup.get("_entries") as Array).size() == PopupScript.MAX_VISIBLE and
		(popup.get("_waiting") as Array).size() == 1,
		"Bursts queue excess loot without obscuring all the screen")
	popup._process(PopupScript.LIFETIME + 0.1)
	verify((popup.get("_waiting") as Array).is_empty() and contains_text(popup, "Topaz"),
		"Queued item appears once room opens")
	popup.clear()
	verify((popup.get("_entries") as Array).is_empty() and (popup.get("_waiting") as Array).is_empty(),
		"Clearing gameplay state resets visible and pending popups")
	SimulationMode.begin()
	EventBus.item_obtained.emit("diamond", 4)
	SimulationMode.end()
	verify((popup.get("_entries") as Array).is_empty(), "Offline or silent simulation creates no item popup")
	PlayerData.settings["show_item_popups"] = false
	BankManager.add_item("emerald", 1)
	verify((popup.get("_entries") as Array).is_empty() and BankManager.get_count("emerald") == 1,
		"Player can disable the popup without disabling rewards")
	PlayerData.settings["show_item_popups"] = true
	BankManager.items.clear()
	for i in range(BankManager.get_slot_limit()):
		BankManager.items["test_storage_%d" % i] = 1
	BankManager.add_item("topaz", 1)
	entries = popup.get("_entries")
	verify(entries.size() == 1 and str(entries[0]["context"]) == "SENT TO OVERFLOW" and
		BankManager.overflow.get("topaz", 0) == 1,
		"Items sent to overflow get an accurate notification")
	popup.queue_free()
	host.queue_free()
	print("Loot popup checks: ", checks, " passed/failed: ", checks - failures, "/", failures)
	get_tree().quit(0 if failures == 0 else 1)
