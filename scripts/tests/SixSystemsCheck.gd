extends Node
const CaravanJourney = preload("res://scripts/core/CaravanJourney.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)
func ctx(id: String) -> Dictionary:
	return {"type":"dungeon", "id":id, "monsters":DataLoader.get_dungeon(id).monsters, "endless":false}
func supplies(action: Dictionary) -> void:
	for iid in action.input_items: BankManager.add_item_guaranteed(str(iid), int(action.input_items[iid]))
func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	# Direct task claims save explicitly; the existing write guard isolates this test process.
	SaveManager._write_in_progress = true
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid), 120)
	Quests.deserialize({"claimed":{"expedition_charter":true}})
	check(PlayerData.get_stat("dream_seconds", "crown") == 0, "fresh/old save has no dream hours")
	for pair in [["sundered_reaches","fire_elemental"],["drowned_reach","tidebound_revenant"],["heralds_march","umbral_harbinger"]]:
		var region: String = pair[0]
		var patrol := "threat_"+region+"_patrol"
		var win := "threat_"+region+"_victory"
		var dungeon := "threat_"+region
		check(CombatManager.dungeon_lock_reason(dungeon).contains("Claim task"), "threat locked before patrol: "+region)
		check(not CombatManager.start_combat(ctx(dungeon)), "locked threat cannot start")
		check(not CombatManager.region_hazard(region).is_empty(), "siege region has hazard")
		PlayerData.bump_stat("monsters_killed",str(pair[1]),100)
		check(Quests.claim(patrol), "patrol claim unlocks hunt")
		check(CombatManager.start_combat(ctx(dungeon)), "regional boss starts")
		CombatManager._complete_combat()
		check(Quests.claim(win), "regional victory claim")
		check(CombatManager.region_hazard(region).is_empty(), "victory removes real hazard")
		var seal_count := BankManager.get_count("masterwork_seal")
		check(not Quests.claim(win) and BankManager.get_count("masterwork_seal")==seal_count, "victory reward is one-time")
		check(CombatSimulatorManager.build_snapshot("area", region, "melee","slash").hazard.is_empty(), "simulator respects pacification")
	var claims: Dictionary = Quests.serialize().duplicate(true)
	Quests.deserialize(claims)
	check(CombatManager.region_hazard("heralds_march").is_empty(), "regional victory survives save")
	for pair in [["cathedral","dream_choir"],["astral","dream_tide"],["crown","dream_sovereign"]]:
		var land: String = pair[0]
		var id: String = pair[1]
		check(CombatManager.dungeon_lock_reason(id).contains("Dream in"), "boss needs real dream hours")
		DreamwalkingManager.select(land,1.0)
		DreamwalkingManager.advance_offline(NAN)
		check(PlayerData.get_stat("dream_seconds",land)==0, "invalid offline duration gives no credit")
		for _i in range(3): DreamwalkingManager.advance_offline(8*3600)
		check(PlayerData.get_stat("dream_seconds",land)==24*3600, "cumulative offline dreams unlock boss")
		BankManager.add_item_guaranteed("dream_essence",10000)
		var before := BankManager.get_count("dream_essence")
		check(CombatManager.start_combat(ctx(id)), "dream boss starts after hours and level")
		check(BankManager.get_count("dream_essence")==before-int(DataLoader.get_dungeon(id).entry_items.dream_essence), "dream entry paid once")
		check(not CombatManager.start_combat(ctx(id)), "busy fight cannot double spend")
		CombatManager.stop_combat()
	var player_save: Dictionary = PlayerData.serialize().duplicate(true)
	PlayerData.deserialize(player_save)
	check(PlayerData.get_stat("dream_seconds","crown")==86400, "dream hours survive save")
	for id in ["endless_ashes","endless_tides","endless_stars"]:
		var committed: Array = []
		var observe := func(_id): committed.append(CombatManager.serialize().duplicate(true))
		EventBus.dungeon_completed.connect(observe)
		check(CombatManager.start_combat(ctx(id)), "endless dungeon starts: "+id)
		var base_hp := CombatManager.monster_max_hp
		var base_hit := int(CombatManager.current_monster().max_hit)
		var reward_id: String = str(DataLoader.get_dungeon(id).floor_reward.items.keys()[0])
		var before := BankManager.get_count(reward_id)
		# Use real deaths and respawns for the first floor, in silent offline mode.
		SimulationMode.begin()
		for _enemy in range(3):
			CombatManager.apply_damage_to_monster(CombatManager.monster_hp)
			CombatManager.tick(100.0)
		SimulationMode.end()
		EventBus.dungeon_completed.disconnect(observe)
		check(CombatManager.endless_floor()==2 and CombatManager.state==CombatManager.State.FIGHTING, "offline floor continues automatically")
		check(CombatManager.monster_max_hp>base_hp and int(CombatManager.current_monster().max_hit)>base_hit, "next floor scales HP and damage")
		check(BankManager.get_count(reward_id)==before+1, "floor loot granted exactly once")
		var save: Dictionary = CombatManager.serialize().duplicate(true)
		CombatManager.deserialize(save)
		check(CombatManager.endless_floor()==2, "active floor survives reload")
		CombatManager.context.floor=10
		before=BankManager.get_count(reward_id)
		CombatManager._complete_combat()
		check(BankManager.get_count(reward_id)==before+6 and PlayerData.get_stat("endless_best",id)==10, "milestone rewards and personal best")
		CombatManager.stop_combat()
		check(CombatManager.start_combat(ctx(id)) and CombatManager.endless_floor()==1, "retreat resets next attempt")
		CombatManager._player_death("test")
		check(CombatManager.endless_floor()==0 and CombatManager.state==CombatManager.State.IDLE, "defeat ends endless run")
	player_save=PlayerData.serialize().duplicate(true)
	PlayerData.deserialize(player_save)
	check(PlayerData.get_stat("endless_best","endless_stars")==10, "personal best survives save")
	check(GameManager.current_activity().kind!="combat", "endless defeat leaves the shared combat readout")
	CombatManager.start_combat(ctx("endless_ashes"))
	var autosave_state: Array = []
	var on_clear := func(_id): autosave_state.append({"floor":CombatManager.endless_floor(),"shards":BankManager.get_count("ash_depth_shard")})
	EventBus.dungeon_completed.connect(on_clear)
	var shards_before := BankManager.get_count("ash_depth_shard")
	CombatManager._complete_combat()
	EventBus.dungeon_completed.disconnect(on_clear)
	check(autosave_state.size()==1 and int(autosave_state[0].floor)==2 and int(autosave_state[0].shards)==shards_before+1, "automatic save sees committed next floor and loot")
	check(str(GameManager.current_activity().label).contains("Floor 2"), "current floor appears in shared combat readout")
	CombatManager.stop_combat()
	for sid in ["smithing","enchanting","fletching","runecrafting"]:
		for action in DataLoader.get_skill(sid).actions:
			if not action.has("requires_building"): continue
			supplies(action)
			var wonder_id: String = str(action.requires_building.keys()[0])
			TownshipManager.buildings[wonder_id]=0
			check(not SkillManager.check_action(sid,str(action.id)).ok, "unbuilt Forge locks recipe")
			TownshipManager.buildings[wonder_id]=3
			var req: String = str(action.requires_skills.keys()[0])
			PlayerData.set_level(req,1)
			check(not SkillManager.check_action(sid,str(action.id)).ok, "secondary skill gates legendary recipe")
			PlayerData.set_level(req,120)
			check(SkillManager.start_action(sid,str(action.id),1), "legendary recipe starts")
			TownshipManager.buildings[wonder_id]=0
			var first: String = str(action.input_items.keys()[0])
			var before := BankManager.get_count(first)
			check(SkillManager.perform_action().get("stop", "")=="project" and BankManager.get_count(first)==before, "continued recipe revalidates gate before spending")
			TownshipManager.buildings[wonder_id]=3
			check(SkillManager.start_action(sid,str(action.id),1), "reopened recipe starts")
			var result: Dictionary = SkillManager.perform_action()
			check(bool(result.get("success",false)), "legendary recipe produces output")
			var produced_id: String = str(result.get("items", {}).keys()[0]) if (result.get("items", {}) as Dictionary).size() > 0 else str(action.output_items.keys()[0])
			check(BankManager.get_count(produced_id) > 0, "crafted component or weapon in bank")
			SkillManager.stop_action()
			TownshipManager.buildings[wonder_id]=0
	for id in ["glassstorm_crossing","nightveil_passage","worlds_end_convoy"]:
		var route: Dictionary = CaravaneeringManager.route(id)
		var journey: Dictionary = CaravanJourney.create(id,73)
		check(journey.points.size()==7, "dangerous route has map stops")
		journey.points[1].event=2
		journey.points[1].roll=0
		var caravan: Dictionary = {"journey":journey}
		CaravanJourney.resolve(caravan,1,route,1000)
		check(float(journey.loss)>=0.1, "weather still dangerous with best guard")
		journey.points[2].event=2
		journey.points[2].roll=0.2
		journey.points[2].approach="cautious"
		var loss: float = journey.loss
		CaravanJourney.resolve(caravan,2,route,1000)
		check(float(journey.loss)==loss, "cautious orders avoid this weather roll")
		journey.loss=0.7
		var restored: Dictionary = CaravanJourney.restore(id,journey)
		check(float(restored.loss)==0.7 and restored.points[2].approach=="cautious", "danger choices and higher losses saved")
		check(ResourceLoader.exists("res://assets/caravans/maps/%s.png" % id), "dangerous map asset exists")
		CaravaneeringManager.deserialize({})
		BankManager.add_item_guaranteed("herald_bar",10)
		PlayerData.gp=10000000
		check(CaravaneeringManager.dispatch(id,"handcart","hired_hand",{"herald_bar":10}), "dangerous caravan dispatch")
		var goods: String = str(route.specialty.keys()[0])
		var before := BankManager.get_count(goods)
		CaravaneeringManager.advance(float(route.hours)*3600.0+1)
		check(BankManager.get_count(goods)>before and CaravaneeringManager.caravans.is_empty(), "offline route returns crafting goods and completes")
	for qid in Quests.all_quest_ids():
		var q: Dictionary = Quests.get_quest(qid)
		if str(q.get("category", ""))!="collection": continue
		for iid in q.objectives[0].item_ids:
			PlayerData.discover_item(str(iid))
			BankManager.remove_item(str(iid),BankManager.get_count(str(iid)))
		check(bool(Quests.progress(qid).all_satisfied), "collection retained after spending")
		check(Quests.claim(qid), "pursuit claim works")
		var before := BankManager.get_count("masterwork_seal")
		check(not Quests.claim(qid) and BankManager.get_count("masterwork_seal")==before, "pursuit cannot pay twice")
	claims=Quests.serialize().duplicate(true)
	Quests.deserialize(claims)
	check(Quests.is_claimed("collection_master_artisan"), "collection trophy claim survives save")
	check(not Goals.sources_for_item("star_depth_shard").is_empty(), "floor reward has a navigable source")
	for iid in ["stormglass_cargo","nightveil_silk","worldheart_ore","sunforged_frame","nightweaver_frame","starbound_frame","trophy_gemkeeper","trophy_master_artisan"]:
		var icon_id: String = str(DataLoader.get_item(iid).get("icon_id",iid))
		check(ResourceLoader.exists("res://assets/icons/items/%s.png" % icon_id), "new item uses real art, not generated fallback: "+iid)
	var validator := ContentValidator.new()
	var report: Array = validator.validate_all()
	for issue in report:
		if issue.severity in ["error","warning"]: print(issue)
	check(report.filter(func(issue): return issue.severity == "error").is_empty(), "content validation has no errors")
	check(report.filter(func(issue): return issue.severity == "warning").is_empty(), "content validation has no warnings")
	print("Six systems: ",checks," checks; ",failures," failures")
	get_tree().quit(1 if failures>0 else 0)
