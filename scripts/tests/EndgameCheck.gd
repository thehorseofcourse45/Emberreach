extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)
func supply_wonder(id: String) -> void:
	for res in TownshipManager.scaled_cost(id):
		TownshipManager.resources[res] = float(TownshipManager.scaled_cost(id)[res])
	for item in TownshipManager.project_item_cost(id):
		BankManager.add_item_guaranteed(str(item), int(TownshipManager.project_item_cost(id)[item]))
	PlayerData.gp = TownshipManager.project_gp_cost(id)
func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	var sid := "fishing"
	var action: String = str(MasteryManager.activities(sid)[0].id)
	var cap: float = XPTable.xp_for_level(120)
	MasteryManager.deserialize({"mastery_xp": {sid: {action: cap - 1}}})
	MasteryManager.add_mastery_xp(sid, action, 3600)
	check(MasteryManager.get_level(sid, action) == 120, "test reaches mastery 120")
	check(float(MasteryManager.challenge(sid, action).seconds) == 0, "pre-120 work excluded")
	check(not MasteryManager.claim_challenge(sid, action), "unfinished challenge cannot claim")
	MasteryManager.add_mastery_xp(sid, action, 3600)
	check(float(MasteryManager.challenge(sid, action).seconds) == 3600, "post-120 work progresses")
	var saved: Dictionary = MasteryManager.serialize().duplicate(true)
	MasteryManager.deserialize(saved)
	check(float(MasteryManager.challenge(sid, action).seconds) == 3600, "challenge save roundtrip")
	MasteryManager.add_mastery_xp(sid, action, 100000)
	check(float(MasteryManager.challenge(sid, action).seconds) == 21600, "offline batch progress capped")
	var seals: int = BankManager.get_count("masterwork_seal")
	check(MasteryManager.claim_challenge(sid, action), "finished challenge claims")
	check(BankManager.get_count("masterwork_seal") == seals + 1 and BankManager.get_count("legendary_crownfin") == 5, "named rewards delivered")
	check(not MasteryManager.claim_challenge(sid, action) and BankManager.get_count("masterwork_seal") == seals + 1, "duplicate claim rejected")
	saved = MasteryManager.serialize().duplicate(true)
	MasteryManager.deserialize(saved)
	check(bool(MasteryManager.challenge(sid, action).claimed), "claimed state preserved")
	check(not MasteryManager.claim_challenge(sid, "missing"), "unknown challenge rejected")
	MasteryManager.deserialize({})
	check(float(MasteryManager.challenge(sid, action).seconds) == 0, "old save starts without retroactive challenge")
	MasteryManager.deserialize({"challenges": {sid+":"+action: {"seconds": NAN}, "missing:missing": {"seconds": 99999}}})
	check(float(MasteryManager.challenge(sid, action).seconds) == 0, "invalid saved progress rejected")
	for skill in DataLoader.get_skill_ids(): PlayerData.set_level(str(skill), 120)
	Quests.deserialize({"claimed": {"expedition_charter": true}})
	var ids: Array = ["wonder_astral_observatory", "wonder_skyport", "wonder_masterwork_forge"]
	for id in ids:
		supply_wonder(id)
		PlayerData.set_level("township", 1)
		var gp: float = PlayerData.gp
		check(not TownshipManager.build(id) and PlayerData.gp == gp, "locked wonder spends nothing: "+id)
		PlayerData.set_level("township", 120)
		for stage in range(3):
			supply_wonder(id)
			var material: String = str(TownshipManager.project_item_cost(id).keys()[0])
			var needed: int = int(TownshipManager.project_item_cost(id)[material])
			BankManager.remove_item(material, BankManager.get_count(material))
			check(not TownshipManager.build(id) and TownshipManager.level_of(id) == stage, "missing material blocks stage")
			BankManager.add_item_guaranteed(material, needed)
			var before: int = BankManager.get_count(material)
			check(TownshipManager.build(id) and TownshipManager.level_of(id) == stage+1, "build stage once")
			check(PlayerData.gp == 0 and BankManager.get_count(material) == before-needed, "costs spent exactly")
		check(not TownshipManager.build(id), "finished wonder cannot build again")
	var town_saved: Dictionary = TownshipManager.serialize().duplicate(true)
	TownshipManager.deserialize(town_saved)
	for id in ids: check(TownshipManager.level_of(id) == 3, "wonder stages saved")
	var dungeons: Array = ["astral_sanctum", "storm_citadel", "crown_of_embers"]
	PlayerData.completion_log.dungeons["ascendant_trials"] = true
	for i in range(dungeons.size()):
		var id: String = str(dungeons[i])
		var d: Dictionary = DataLoader.get_dungeon(id)
		TownshipManager.buildings[ids[i]] = 2
		check(CombatManager.dungeon_lock_reason(id).contains("Complete"), "unfinished wonder locks expedition")
		TownshipManager.buildings[ids[i]] = 3
		check(CombatManager.dungeon_lock_reason(id) != "", "missing provisions locks expedition")
		for item in d.entry_items: BankManager.add_item_guaranteed(str(item), int(d.entry_items[item]))
		check(CombatManager.dungeon_lock_reason(id) == "", "prepared expedition unlocks")
		var available: Dictionary = CombatSimulatorManager.build_snapshot("dungeon", id, "melee", "slash", true)
		check(not available.is_empty(), "finite simulator accepts prepared inventory")
		check(int(available.food_counts.shark) == BankManager.get_count("shark") - int(d.entry_items.shark), "finite simulation reserves entry food")
		var item: String = str(d.entry_items.keys()[0])
		var before: int = BankManager.get_count(item)
		check(not CombatManager.start_combat({"type":"dungeon", "id":id, "monsters":[]}) and BankManager.get_count(item) == before, "invalid start spends nothing")
		var ctx: Dictionary = {"type":"dungeon", "id":id, "monsters":d.monsters}
		check(CombatManager.start_combat(ctx), "legendary expedition starts")
		check(BankManager.get_count(item) == before-int(d.entry_items[item]), "entry provisions spent once")
		before = BankManager.get_count(item)
		check(not CombatManager.start_combat(ctx) and BankManager.get_count(item) == before, "busy start cannot spend twice")
		CombatManager._complete_combat()
		var gear: String = str(d.rewards_first_clear.items.keys()[0])
		check(BankManager.get_count(gear) == 1, "signature first-clear equipment awarded")
		for cost in d.entry_items: BankManager.add_item_guaranteed(str(cost), int(d.entry_items[cost]))
		check(CombatManager.start_combat(ctx), "repeat attempt requires fresh provisions")
		CombatManager._complete_combat()
		check(BankManager.get_count(gear) == 1, "first-clear equipment cannot duplicate")
		check(ResourceLoader.exists("res://assets/icons/dungeons/%s.png" % id), "expedition icon imported")
		BankManager.remove_item("potion_dr_3", BankManager.get_count("potion_dr_3"))
		check(CombatSimulatorManager.build_snapshot("dungeon", id, "melee", "slash", true).is_empty(), "finite simulator refuses missing provisions")
		for mid in d.monsters: check(ResourceLoader.exists("res://assets/sprites/monsters/%s.png" % mid), "monster sprite imported")
	check(not Goals.sources_for_item("masterwork_seal").is_empty(), "mastery reward acquisition explained")
	check(BalanceReport.consumed_item_ids().has("masterwork_seal"), "wonder material demand recognized")
	var issues: Array = ContentValidator.new().validate_all()
	check(not issues.any(func(x): return str(x.get("severity", "")) in ["error", "warning"]), "content validation clean")
	print("Endgame: ", checks, " checks, ", failures, " failures")
	if "--capture" in OS.get_cmdline_user_args():
		var main = preload("res://scenes/main.tscn").instantiate()
		add_child(main)
		GameManager.cli_mode = true
		await get_tree().create_timer(0.5).timeout
		main.navigate({"screen": Screens.SKILLS, "skill_id": sid, "action_id":action})
		await get_tree().process_frame
		var panel = main.get("_panels")[Screens.SKILLS]
		panel.get("_advanced_body").visible = true
		MasteryManager.deserialize(saved)
		panel.refresh()
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/endgame_preview.png")
		TownshipManager.buildings["wonder_astral_observatory"] = 1
		main.navigate({"screen": Screens.SETTLEMENT, "wonders":true})
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/wonders_preview.png")
	get_tree().quit(0 if failures == 0 else 1)
