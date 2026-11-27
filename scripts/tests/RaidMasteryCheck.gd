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
	PlayerData.initialize_new_game()
	BankManager.deserialize({"purchased_slots": 200})
	EquipmentManager.deserialize({})
	call_deferred("run")

func run() -> void:
	var raid := "infernal_crucible"
	var other := "leviathan_cathedral"
	var choices: Array = PlayerData.raid_exchange_items(raid)
	ok(choices.size() == 3, "only three repeatable boss rewards are exchangeable")
	ok(int(choices[0].cost) == 8 and int(choices[1].cost) == 12 and int(choices[2].cost) == 16, "cost reflects drop rarity")
	ok(PlayerData.raid_marks(raid) == 0, "new player has no marks")
	ok(not PlayerData.exchange_raid_reward(raid, str(choices[0].item_id)), "cannot exchange without enough marks")
	PlayerData.completion_log.dungeons[other] = true
	ok(PlayerData.raid_marks(other) == 2, "older completion log proves at least one clear")
	PlayerData.completion_log.dungeons.erase(other)
	PlayerData.stats.dungeons_cleared[raid] = 10
	ok(PlayerData.raid_marks(raid) == 16, "historical clears receive milestone marks")
	ok(PlayerData.raid_marks(other) == 0, "each raid has separate marks")
	var id := str(choices[0].item_id)
	ok(not PlayerData.exchange_raid_reward(other, id), "cannot exchange another raid's item")
	ok(PlayerData.exchange_raid_reward(raid, id), "exchange awards the chosen item")
	ok(BankManager.get_total_owned(id) == 1, "item enters bank or overflow")
	ok(not PlayerData.exchange_raid_reward(raid, id), "owned reward cannot be exchanged again")
	var after := PlayerData.raid_marks(raid)
	var state := PlayerData.serialize().duplicate(true)
	PlayerData.initialize_new_game()
	PlayerData.deserialize(state)
	ok(PlayerData.raid_marks(raid) == after, "spent marks survive save and load")
	ok(SaveManager.save_game(true), "exchange state writes to disk")
	PlayerData.initialize_new_game()
	BankManager.deserialize({"purchased_slots": 200})
	ok(SaveManager.load_game(), "exchange state loads from disk")
	ok(PlayerData.raid_marks(raid) == after and BankManager.get_total_owned(id) == 1, "spent marks and purchased item survive together")
	var old_state := state.duplicate(true)
	old_state.stats.erase("raid_marks_spent")
	PlayerData.deserialize(old_state)
	ok(PlayerData.raid_marks(raid) == 16, "old saves preserve historical clears")
	ok(PlayerData.raid_exchange_items("chicken_coop").is_empty(), "non-raid cannot exchange")
	PlayerData.stats.dungeons_cleared[raid] = 25
	ok(PlayerData.raid_marks(raid) == 36, "all mastery milestones pay once")
	ProgressTracker.record_dungeon_clear(raid)
	ok(PlayerData.raid_marks(raid) == 37, "a further clear earns one mark")
	var raid_count := 0
	for d in DataLoader.dungeons.values():
		if not bool(d.get("raid", false)): continue
		raid_count += 1
		ok(PlayerData.raid_exchange_items(str(d.id)).size() == 3, str(d.name) + " has three exchangeable drops")
	ok(raid_count == 15, "all raids have mastery")
	CombatManager.context = {"type": "dungeon", "id": raid, "monsters": DataLoader.get_dungeon(raid).monsters, "index": 0}
	CombatManager._complete_combat()
	ok(PlayerData.raid_marks(raid) == 38, "real combat completion awards a mark")
	var panel := preload("res://scripts/ui/panels/CombatPanel.gd").new()
	panel.expeditions_only = true
	add_child(panel)
	panel.call("focus_route", {"area_id": raid})
	var display := panel.find_children("*", "Button", true, false)
	var exchange_buttons := 0
	var buy_button: Button
	for button in display:
		if "marks" in str(button.text) or str(button.text) == "Owned": exchange_buttons += 1
		if str(button.text) == "12 marks": buy_button = button
	ok(exchange_buttons >= 3, "raid panel presents all exchanges")
	ok(buy_button != null and not buy_button.disabled, "affordable missing reward is clickable")
	if buy_button != null:
		buy_button.pressed.emit()
		ok(PlayerData.raid_marks(raid) == 26 and BankManager.get_total_owned(str(choices[1].item_id)) == 1, "UI exchange spends marks and grants item")
	panel.free()
	ok(SaveManager.save_game(true), "save writes to the isolated profile")
	PlayerData.initialize_new_game()
	BankManager.deserialize({"purchased_slots": 200})
	ok(SaveManager.load_game(), "saved game loads")
	ok(PlayerData.raid_marks(raid) == 26, "marks survive the full game save")
	print("Raid mastery: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
