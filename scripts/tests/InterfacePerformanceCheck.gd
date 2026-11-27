extends Node
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	var stock := {}
	for id in DataLoader.items:
		stock[id] = 10
		if stock.size() == 93: break
	BankManager.deserialize({"purchased_slots":200,"items":stock})
	call_deferred("run")
func run() -> void:
	var bank = load("res://scripts/ui/panels/BankPanel.gd").new()
	add_child(bank)
	var list: VBoxContainer = bank.get("_list")
	var seen := {}
	for page in range(3):
		check(list.get_child_count() == (40 if page < 2 else 13), "correct page size")
		for row in list.get_children(): seen[str(row.get_meta("item_id"))] = true
		if page < 2:
			var next: Button
			for button in bank.get("_page_bar").find_children("*", "Button", true, false):
				if button.text == "Next": next = button
			check(next != null and not next.disabled, "next page available")
			if next: next.pressed.emit()
	check(seen.size() == 93, "all item stacks appear exactly once across pages")
	var row := list.get_child(0)
	var id := str(row.get_meta("item_id"))
	var details: Button
	for button in row.find_children("*", "Button", true, false):
		if button.text == "Details": details = button
	var contexts := []
	bank.context_changed.connect(func(context): contexts.append(context))
	if details: details.pressed.emit()
	check(is_instance_valid(row) and row.is_inside_tree(), "selection retains list row")
	check(str(bank.get("_selected")) == id and contexts.size() == 1 and str(contexts[0].item_id) == id, "selection updates details")
	var search: LineEdit = bank.get("_search")
	search.text = "zzzz_no_matching_item"
	search.text_changed.emit(search.text)
	check(int(bank.get("_page")) == 0 and list.get_child_count() == 1, "search resets page and shows empty state")
	search.text = ""
	search.text_changed.emit("")
	check(list.get_child_count() == 40, "clearing search restores first page")
	bank.free()
	print("Interface performance behavior: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures == 0 else 1)
