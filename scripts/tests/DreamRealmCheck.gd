extends Node
var checks := 0
var failures := 0
func ok(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", message)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	BankManager.deserialize({"purchased_slots":200})
	EquipmentManager.deserialize({})
	call_deferred("run")

func run() -> void:
	var realm = DreamwalkingManager.realm
	realm._rng.seed = 12345
	var entries: Array = realm.regions()
	ok(entries.size() == 8, "eight regions")
	ok(Screens.DREAM_REALM in Screens.ORDER, "screen registered")
	ok(preload("res://scripts/ui/SidebarNav.gd").chapter_of(Screens.DREAM_REALM) == "arcane", "screen belongs to Arcane")
	var panel := preload("res://scripts/ui/panels/DreamRealmPanel.gd").new()
	add_child(panel)
	ok(panel.get_child_count() > 0, "screen renders")
	panel.focus_route({"region_id":"mirror_library"})
	ok(str(panel.get("_selected")) == "mirror_library", "direct region route")
	panel.free()
	PlayerData.set_level("dreamwalking", 59)
	BankManager.add_item_guaranteed("dream_essence", 1200)
	ok(not realm.start("lantern_garden") and BankManager.get_count("dream_essence") == 1200, "level gate does not spend essence")
	PlayerData.set_level("dreamwalking", 120)
	ok(not realm.start("mirror_library"), "later region requires preceding clear")
	var interactive := preload("res://scripts/ui/panels/DreamRealmPanel.gd").new()
	add_child(interactive)
	var mirror_button: Button = null
	for child in interactive.find_children("*", "Button", true, false):
		if child.text == "Mirror Library": mirror_button = child
	ok(mirror_button != null, "region selection button exists")
	if mirror_button != null: mirror_button.pressed.emit()
	ok(str(interactive.get("_selected")) == "mirror_library", "region selection button opens its own region")
	interactive.focus_route({"region_id":"lantern_garden"})
	var enter_button: Button = null
	for child in interactive.find_children("*", "Button", true, false):
		if child.text == "Enter dream" and child.is_inside_tree(): enter_button = child
	ok(enter_button != null and not enter_button.disabled, "entry button is enabled")
	if enter_button != null: enter_button.pressed.emit()
	ok(not realm.run.is_empty(), "entry button starts journey")
	var safe_button: Button = null
	for child in interactive.find_children("*", "Button", true, false):
		if child.text.begins_with("Shield the lantern"): safe_button = child
	ok(safe_button != null, "first choice button exists")
	if safe_button != null: safe_button.pressed.emit()
	ok(int(realm.run.get("step", -1)) == 1, "choice button advances the journey")
	realm.abandon()
	interactive.free()
	BankManager.add_item_guaranteed("dream_essence", 100)
	ok(realm.start("lantern_garden") and BankManager.get_count("dream_essence") == 1100, "entry consumes exact cost")
	ok(not realm.start("lantern_garden") and not bool(realm.choose("invalid").ok), "cannot enter twice or use invalid choice")
	ok(str(realm.choose("bold").result) == "continue" and int(realm.run.clarity) == 1, "bold choice earns fragments and costs clarity")
	var pending: Dictionary = realm.run.duplicate(true)
	DreamwalkingManager.advance_offline(60.0)
	ok(realm.run == pending, "offline Dreamwalking does not advance an active journey")
	var snapshot: Dictionary = DreamwalkingManager.serialize().duplicate(true)
	realm.deserialize({})
	DreamwalkingManager.deserialize(snapshot)
	ok(int(realm.run.step) == 1 and int(realm.run.fragments) == 4, "active journey survives save data roundtrip")
	ok(str(realm.choose("bold").result) == "failed" and realm.run.is_empty(), "zero clarity ends journey")
	ok(BankManager.get_count("lucid_fragment") == 0, "failed journey pays nothing")
	var probe := RandomNumberGenerator.new()
	var risky_seed := 0
	for candidate in range(100):
		probe.seed = candidate
		if probe.randf() < 0.25:
			risky_seed = candidate
			break
	realm._rng.seed = risky_seed
	ok(realm.start("lantern_garden") and str(realm.choose("bold").result) == "failed", "bold setback can consume extra clarity")
	realm._rng.seed = 12345
	ok(realm.start("lantern_garden"), "retry available")
	realm.choose("safe")
	realm.choose("bold")
	var result: Dictionary = realm.choose("safe")
	ok(str(result.result) == "complete" and int(result.fragments) == 8, "three choices and region bonus pay fragments")
	ok(BankManager.get_count("lucid_fragment") == 8 and realm.completed.has("lantern_garden"), "completion and fragments recorded")
	ok(realm.lock_reason("mirror_library") == "", "completion unlocks next region")
	ok(not realm.purchase("mirror_library") and realm.purchase("lantern_garden"), "only unlocked affordable relic may be exchanged")
	ok(BankManager.get_count("lucid_fragment") == 0 and BankManager.get_count("lantern_dream_amulet") == 1, "relic purchase spends currency once")
	ok(EquipmentManager.equip("lantern_dream_amulet") and ModifierManager.get_modifier("dreamwalking_essence_percent") >= 15.0, "equipped relic bonus applies")
	var save: Dictionary = SaveManager.build_save_data()
	ok(save.dreamwalking.realm.completed.has("lantern_garden"), "normal save contains realm progress")
	SaveManager._apply(save)
	ok(realm.completed.has("lantern_garden") and realm.run.is_empty(), "normal save application restores region progress")
	BankManager.add_item_guaranteed("dream_essence", 2000)
	for i in range(1, entries.size()):
		var entry: Dictionary = entries[i]
		ok(realm.start(str(entry.id)), "next region starts after previous clear")
		for _step in range(3): realm.choose("safe")
		ok(realm.completed.has(str(entry.id)) and realm.run.is_empty(), "each region completes")
		BankManager.add_item_guaranteed("lucid_fragment", int(entry.price))
		ok(realm.purchase(str(entry.id)) and BankManager.get_count(str(entry.item)) == 1, "each region unlocks its relic")
	var rare_seed := -1
	for seed_value in range(100):
		probe.seed = seed_value
		if probe.randf() < 0.15:
			rare_seed = seed_value
			break
	realm._rng.seed = rare_seed
	BankManager.add_item_guaranteed("dream_essence", 1000)
	var before: int = BankManager.get_count("lucid_fragment")
	ok(realm.start("astral_orchard"), "branching journey starts")
	realm.choose("safe")
	ok(str(realm.run.get("path", "")) == "safe" and bool(realm.run.get("discovery", false)), "choice records path and rare discovery")
	var branch_save: Dictionary = realm.serialize()
	realm.deserialize(branch_save)
	ok(str(realm.run.get("path", "")) == "safe" and bool(realm.run.get("discovery", false)), "branch and discovery survive save roundtrip")
	var branch_panel := preload("res://scripts/ui/panels/DreamRealmPanel.gd").new()
	add_child(branch_panel)
	var branch_text := ""
	for label in branch_panel.find_children("*", "Label", true, false): branch_text += label.text
	ok(branch_text.contains("hidden grove") and branch_text.contains("Rare discovery"), "journey displays selected story and discovery")
	branch_panel.free()
	realm.choose("safe")
	var branch_result: Dictionary = realm.choose("safe")
	ok(int(branch_result.fragments) == 17 and BankManager.get_count("lucid_fragment") == before + 17, "safe path and rare discovery paid on return")
	var bold_seed := -1
	for seed_value in range(100):
		probe.seed = seed_value
		if probe.randf() >= 0.15 and probe.randf() >= 0.25:
			bold_seed = seed_value
			break
	realm._rng.seed = bold_seed
	ok(realm.start("astral_orchard"), "branch journey can be repeated")
	realm.choose("bold")
	ok(not realm.run.is_empty() and str(realm.run.get("path", "")) == "bold", "bold path is distinct")
	var bold_panel := preload("res://scripts/ui/panels/DreamRealmPanel.gd").new()
	add_child(bold_panel)
	var bold_text := ""
	for label in bold_panel.find_children("*", "Label", true, false): bold_text += label.text
	ok(bold_text.contains("broken constellation"), "bold path displays its own story")
	bold_panel.free()
	realm.choose("safe")
	var bold_result: Dictionary = realm.choose("safe")
	ok(int(bold_result.fragments) == 17, "bold path pays its distinct return bonus")
	ok(realm.start("astral_orchard"), "journey can be abandoned")
	realm.choose("safe")
	realm.abandon()
	ok(realm.run.is_empty(), "abandon clears pending branch rewards")
	DreamwalkingManager.deserialize({"dreamscape":"shore", "share":0.5})
	ok(realm.completed.is_empty() and realm.run.is_empty() and DreamwalkingManager.dreamscape == "shore", "old saves load without realm state")
	realm.deserialize({"run":{"region":"lantern_garden","step":2,"clarity":0,"fragments":999}})
	ok(realm.run.is_empty(), "invalid saved journey discarded")
	DreamwalkingManager.deserialize(snapshot)
	GameManager.start_new_game("standard")
	ok(realm.completed.is_empty() and realm.run.is_empty(), "new game resets realm")
	var sources: Array = Goals.sources_for_item("lantern_dream_amulet")
	ok(not sources.is_empty() and str(sources[0].route.screen) == "dream_realm", "collection goals locate relic source")
	print("Dream Realm: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures == 0 else 1)
