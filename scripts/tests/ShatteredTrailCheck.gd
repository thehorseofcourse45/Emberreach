extends Node
var checks := 0
var failures := 0
func ok(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	BankManager.deserialize({"purchased_slots":200})
	PlayerData.set_level("hitpoints", 100)
	call_deferred("run")

func defeat_encounter() -> void:
	var guard := 0
	while CombatManager.state != CombatManager.State.IDLE and guard < 12:
		CombatManager.player_hp = 1000000.0
		if CombatManager.state == CombatManager.State.FIGHTING:
			CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
		CombatManager.tick(60)
		guard += 1
	ok(CombatManager.state == CombatManager.State.IDLE, "encounter finishes")

func run() -> void:
	PlayerData.raid_coins = 3000.0
	ok(RaidManager.buy("raid_wave_skip"), "legacy upgrade can be purchased")
	ok(PlayerData.raid_coins == 1000.0 and int(RaidManager.purchased.raid_wave_skip) == 1, "marks and purchase retained")
	ok(RaidManager.start_raid("normal"), "journey starts")
	ok(RaidManager.trail_mode and RaidManager.run_stage == "route" and RaidManager.trail_supplies == 3, "old upgrade adds starting supplies")
	var panel := preload("res://scripts/ui/panels/RaidPanel.gd").new()
	add_child(panel)
	var patrol_button: Button = null
	for button in panel.find_children("*", "Button", true, false):
		if button.text == "Choose Patrol": patrol_button = button
	ok(patrol_button != null, "route choice appears in the panel")
	if patrol_button != null: patrol_button.pressed.emit()
	ok(CombatManager.state == CombatManager.State.FIGHTING and RaidManager.wave == 1, "patrol button starts combat")
	panel.free()
	var combat_save: Dictionary = SaveManager.build_save_data()
	SaveManager._apply(combat_save)
	ok(RaidManager.trail_mode and RaidManager.run_stage == "combat" and RaidManager.wave == 1 and CombatManager.state == CombatManager.State.FIGHTING, "combat save resumes")
	defeat_encounter()
	ok(RaidManager.run_stage == "route" and RaidManager.coins_this_raid > 0, "patrol pays unbanked marks")
	var route_save: Dictionary = SaveManager.build_save_data()
	SaveManager._apply(route_save)
	ok(RaidManager.run_stage == "route" and RaidManager.pending_routes.size() == 3 and RaidManager.trail_supplies == 3, "route save resumes")
	ok(RaidManager.choose_route(1) and RaidManager.trail_supplies == 2 and str(RaidManager.current_encounter.id) == "trail_cache", "cache costs a supply and starts a stronger fight")
	defeat_encounter()
	CombatManager.player_hp = 10.0
	ok(RaidManager.choose_route(2) and RaidManager.trail_camps == 1 and RaidManager.trail_supplies == 3, "camp grants supplies")
	ok(CombatManager.player_hp > 10.0, "camp heals")
	ok(RaidManager.choose_route(2) and RaidManager.trail_camps == 2, "second camp allowed")
	ok(not RaidManager.choose_route(2) and RaidManager.wave == 4, "third camp rejected without advancing")
	ok(RaidManager.choose_route(0), "fifth stop starts")
	defeat_encounter()
	ok(RaidManager.pending_routes.size() == 1 and str(RaidManager.pending_routes[0].id) == "trail_boss", "guardian follows five stops")
	ok(RaidManager.choose_route(0) and CombatManager.current_monster_id == "golbin_chief", "normal guardian starts")
	var before: float = PlayerData.raid_coins
	var reward_snapshot := {}
	EventBus.item_obtained.connect(func(id, _qty):
		if id == "shark": reward_snapshot.merge(SaveManager.build_save_data(), true))
	defeat_encounter()
	ok(not RaidManager.active and int(RaidManager.trail_completions.get("normal", 0)) == 1, "guardian completes the journey")
	ok(PlayerData.raid_coins > before and BankManager.get_total_owned("shark") >= 20, "completion banks marks and grants its reward")
	ok(not reward_snapshot.is_empty() and not bool(reward_snapshot.raid.active) and float(reward_snapshot.player.raid_coins) > before, "reward signal observes the committed completion and banked marks")
	var persisted: Dictionary = RaidManager.serialize().duplicate(true)
	RaidManager.deserialize(persisted)
	ok(int(RaidManager.purchased.raid_wave_skip) == 1 and int(RaidManager.trail_completions.normal) == 1, "purchases and completion persist")
	ok(RaidManager.start_raid("normal"), "repeat journey starts")
	var saved_supplies := RaidManager.trail_supplies
	RaidManager.trail_supplies = 0
	ok(not RaidManager.choose_route(1) and RaidManager.wave == 0, "cache cannot start without supplies")
	RaidManager.trail_supplies = saved_supplies
	ok(RaidManager.choose_route(0), "repeat patrol starts")
	defeat_encounter()
	before = PlayerData.raid_coins
	RaidManager.end_raid()
	ok(not RaidManager.active and PlayerData.raid_coins > before, "retreat banks earned marks")
	ok(RaidManager.start_raid("normal") and RaidManager.choose_route(0), "defeat fixture begins")
	defeat_encounter()
	ok(RaidManager.choose_route(0), "defeat fixture enters another fight")
	before = PlayerData.raid_coins
	CombatManager._player_death("trail fixture")
	ok(not RaidManager.active and PlayerData.raid_coins > before, "defeat banks earned marks")
	var legacy := {"active":true, "difficulty":"normal", "wave":3, "coins_this_raid":120, "run_stage":"route", "pending_routes":[{"id":"skirmish"}], "purchased":{"raid_wave_skip":1}, "run_relics":{"keen_eye":2}}
	RaidManager.deserialize(legacy)
	ok(RaidManager.active and not RaidManager.trail_mode and str(RaidManager.pending_routes[0].id) == "skirmish", "in-progress old save keeps its original rules")
	ok(ModifierManager.get_modifier("global_accuracy_percent") >= 16.0, "legacy temporary relic remains active")
	ok(RaidManager.choose_route(0), "legacy route continues to combat")
	defeat_encounter()
	ok(RaidManager.run_stage == "reward" and RaidManager.pending_choices.size() == 3, "legacy reward selection remains playable")
	before = PlayerData.raid_coins
	RaidManager.end_raid()
	ok(PlayerData.raid_coins >= before + 120.0 and int(RaidManager.purchased.raid_wave_skip) == 1, "legacy earned marks and upgrades survive")
	ok(RaidManager.start_raid("normal"), "journey allows a later route decision")
	ok(CombatManager.start_combat({"type":"area", "id":"farmlands", "monsters":["golbin"], "endless":false}), "unrelated fight can start while choosing")
	RaidManager.end_raid()
	ok(CombatManager.state == CombatManager.State.FIGHTING and str(CombatManager.context.type) == "area", "retreat leaves unrelated combat running")
	CombatManager.stop_combat()
	for item_id in DataLoader.items:
		if BankManager.is_full(): break
		if str(item_id) != "raid_alt_weapon_1": BankManager.add_item_guaranteed(str(item_id), 1)
	ok(BankManager.is_full(), "fixture fills storage")
	PlayerData.raid_coins = 100000.0
	var owned := BankManager.get_total_owned("raid_alt_weapon_1")
	ok(RaidManager.buy("raid_alt_weapon_1") and BankManager.get_total_owned("raid_alt_weapon_1") == owned + 1, "full storage cannot lose a purchased item")
	ok(RaidManager.start_raid("normal") and RaidManager.choose_route(0), "offline fixture begins a patrol")
	SimulationMode.begin()
	defeat_encounter()
	ok(RaidManager.active and RaidManager.run_stage == "route", "offline combat pauses for the next route choice")
	SimulationMode.end()
	RaidManager.end_raid()
	for skill in DataLoader.get_skill_ids(): PlayerData.set_level(str(skill), 120)
	for diff in ["easy", "hard", "mythic"]:
		ok(RaidManager.start_raid(diff), "%s journey starts" % diff)
		for _stop in range(RaidManager.TRAIL_STOPS):
			ok(RaidManager.choose_route(0), "%s patrol starts" % diff)
			defeat_encounter()
		ok(RaidManager.choose_route(0) and CombatManager.current_monster_id == RaidManager.TRAIL_BOSSES[diff], "%s guardian starts" % diff)
		defeat_encounter()
		ok(not RaidManager.active and int(RaidManager.trail_completions.get(diff, 0)) == 1, "%s journey completes" % diff)
	print("Shattered Trail: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures == 0 else 1)
