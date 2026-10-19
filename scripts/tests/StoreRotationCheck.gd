extends Node
const Sidebar = preload("res://scripts/ui/SidebarNav.gd")

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	var t := TestRunner.new()
	var a: Array = ShopManager.store_offers_for_period(100)
	var b: Array = ShopManager.store_offers_for_period(101)
	t._ok(a.size() == 80, "80 rotating offers")
	t._ok(a == ShopManager.store_offers_for_period(100), "same window is deterministic across reloads")
	t._ok(a != b, "next six-hour window changes stock")
	t._ok(ShopManager.STORE_ROTATION_SECONDS == 21600, "rotation is six real-world hours")
	t._ok(ShopManager.store_refresh_seconds() > 0 and ShopManager.store_refresh_seconds() <= 21600, "countdown is bounded")
	var catalogue := 0
	for id in DataLoader.shop_store:
		var offer: Variant = DataLoader.shop_store[id]
		if not offer is Dictionary:
			continue
		catalogue += 1
		t._ok(DataLoader.items.has(offer.item_id), "valid item " + id)
		t._ok(float(offer.cost) > float(DataLoader.items[offer.item_id].get("sell_price", 0)) * int(offer.quantity), "no resale exploit " + id)
	t._ok(catalogue >= 300, "large catalogue")
	var current: Array = ShopManager.store_offers()
	var ids := {}
	for offer in current:
		ids[offer.id] = true
	t._ok(ids.size() == 80, "no duplicate offers")
	for id in DataLoader.shop_store:
		if id == "_comment" or str(id).begins_with("store_ranch_") or ids.has(id):
			continue
		var gp: float = PlayerData.gp
		var item: String = DataLoader.shop_store[id].item_id
		var held: int = BankManager.get_count(item)
		t._ok(not ShopManager.can_buy_store(id).ok, "off-rotation item cannot be bought")
		t._ok(not ShopManager.buy_store(id), "stale purchase refused")
		t._ok(PlayerData.gp == gp and BankManager.get_count(item) == held, "refused purchase changes nothing")
		var hinted := false
		for source in Goals.sources_for_item(item):
			if source.get("route", {}).get("screen", "") == Screens.STORE:
				hinted = not bool(source.get("unlocked", true)) and str(source.detail).contains("future six-hour")
		t._ok(hinted, "off-rotation source explains future stock and is not marked available")
		break
	for item in ["clockwork_gear", "clockwork_spring", "earth_rune", "fire_rune", "scribe_blue_ink"]:
		t._ok(not DataLoader.shop_store.has("store_" + item), "deliberate scarcity preserved: " + item)
	t._ok(not ShopManager.get_store_offer("store_ranch_hen").is_empty(), "ranch still sells livestock")
	t._test_general_store()
	var host = load("res://scripts/ui/MainUI.gd").new()
	add_child(host)
	await get_tree().process_frame
	t.test_chapters(host)
	t._test_general_store_screen(host)
	host.navigate({"screen": Screens.BANK})
	t._ok(Sidebar.chapter_of(Screens.BANK) == "storage", "Storage belongs to a dedicated chapter")
	t._ok(host._screen == Screens.BANK, "dedicated Storage opens inventory")
	host.navigate({"screen": Screens.STORE})
	host._nav_buttons[Screens.BANK].pressed.emit()
	t._ok(host._screen == Screens.BANK, "Storage heading directly opens inventory")
	t._ok(host._chapters.storage.body.get_child_count() == 0, "Storage has no redundant nested entry")
	Sidebar.populate_drawer(host, host._drawer)
	var storage_buttons := 0
	for button in host._drawer.find_children("*", "Button", true, false):
		if button.text == "Storage":
			storage_buttons += 1
	t._ok(storage_buttons == 1, "compact drawer has exactly one Storage tab")
	host.queue_free()
	await get_tree().process_frame
	print("STORE ROTATION: ",t._passed," passed; ",t._failed," failures")
	get_tree().quit(0 if t._failed == 0 else 1)
