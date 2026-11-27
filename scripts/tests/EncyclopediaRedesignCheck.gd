extends Node
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)

func find_button(node: Node, label: String) -> Button:
	if node is Button and node.text == label: return node
	for child in node.get_children():
		var found := find_button(child, label)
		if found != null: return found
	return null

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	PlayerData.initialize_new_game()
	PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
	BankManager.deserialize({"purchased_slots": 200})
	call_deferred("run")

func run() -> void:
	var panel = load("res://scripts/ui/panels/EncyclopediaPanel.gd").new()
	add_child(panel)
	check(panel._mode == "home", "opens at guide home")
	check(panel._articles.size() >= 15, "substantial guides loaded")
	var ids := {}
	for article in panel._articles:
		var id: String = str(article.get("id", ""))
		check(id != "" and not ids.has(id), "unique guide id " + id)
		ids[id] = true
		check(not article.get("sections", []).is_empty(), id + " has sections")
		var route: Dictionary = article.get("route", {})
		check(route.is_empty() or Screens.ORDER.has(str(route.get("screen", ""))), id + " route is a screen")
	check(panel._all_guides().size() == panel._articles.size() + DataLoader.get_skill_ids().size(), "guide for every skill")
	for skill_id in DataLoader.get_skill_ids():
		check(str(panel._skill_tips.get(skill_id, "")) != "", "practical guidance for " + str(skill_id))
	panel.focus_route({"section": "tutorial"})
	check(panel._mode == "tutorial", "tutorial route opens first steps")
	check(PlayerData.tutorial_step == 0, "viewing tutorial preserves progress")
	PlayerData.tutorial_step = 3
	panel._rebuild()
	check(PlayerData.tutorial_step == 3, "reviewing old steps preserves progress")
	var saved: Dictionary = TutorialManager.serialize()
	PlayerData.tutorial_step = 0
	TutorialManager.deserialize(saved)
	check(PlayerData.tutorial_step == 3, "tutorial progress survives serialization")
	panel._set_mode("guides")
	panel._search.text = "clarity"
	panel._rebuild()
	check(panel._list.get_child_count() > 2, "guide search includes article text")
	panel._open_article("dream")
	check(panel._article_id == "dream", "open guide")
	panel._open_article("skill:woodcutting")
	check(panel._article_id == "skill:woodcutting", "open skill guide")
	var routes: Array = []
	panel.navigated.connect(func(route): routes.append(route))
	var last: Button = panel._list.get_child(panel._list.get_child_count() - 1)
	last.pressed.emit()
	check(routes.size() == 1 and routes[0].get("skill_id", "") == "woodcutting", "skill guide navigates")
	var browse := find_button(panel, "Browse activities for this skill")
	check(browse != null, "skill has activity browser")
	if browse != null:
		browse.pressed.emit()
		check(panel._mode == "reference" and panel._reference_skill_id == "woodcutting", "skill activities filter opens")
	panel._set_mode("reference")
	check(panel._records("Items").size() == DataLoader.items.size(), "item reference retains live records")
	check(panel._records("Skills").size() == DataLoader.get_skill_ids().size(), "skill reference retains live records")
	check(panel._records("Activities").size() > 100, "activities remain available")
	panel._search.text = "verdigris scimitar"
	panel._category.select(panel.CATEGORIES.find("Items"))
	panel._rebuild()
	check(panel._list.get_child_count() > 1, "reference search finds item")
	var weapon: Dictionary = DataLoader.get_item("bronze_scimitar")
	check(panel._describe({"id":"bronze_scimitar", "name":weapon.name, "category":"Items", "data":weapon}).contains("Equipment bonuses"), "item stats explained")
	panel.queue_free()
	await get_tree().process_frame
	print("ENCYCLOPEDIA REDESIGN: ", checks, " checks; ", failures, " failures")
	get_tree().quit(1 if failures else 0)
