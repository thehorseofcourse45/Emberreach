extends Node
var checks := 0
var failures := 0
var cleared_saves: Array = []

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
	PlayerData.initialize_new_game()
	PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
	BankManager.deserialize({"purchased_slots":200})
	EquipmentManager.deserialize({})
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid), 120)
	Quests.deserialize({"claimed":{"expedition_charter":true}})
	EventBus.dungeon_completed.connect(func(id):
		if bool(DataLoader.get_dungeon(id).get("stronghold", false)): cleared_saves.append(CombatManager.serialize().duplicate(true)))
	call_deferred("run")

func supplies(d: Dictionary) -> void:
	for item in d.entry_items: BankManager.add_item_guaranteed(str(item), int(d.entry_items[item])*3)

func finish(d: Dictionary) -> void:
	for mid in d.monsters:
		ok(CombatManager.current_monster_id == mid, "authored stage order: " + str(mid))
		CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
		CombatManager.tick(6)
	ok(CombatManager.state == CombatManager.State.IDLE, "siege ends after final stage")

func run() -> void:
	var ids: Array = []
	var unique: Dictionary = {}
	for id in DataLoader.dungeons:
		if bool(DataLoader.dungeons[id].get("stronghold",false)): ids.append(id)
	ids.sort_custom(func(a,b): return int(DataLoader.dungeons[a].level_range[0]) < int(DataLoader.dungeons[b].level_range[0]))
	ok(ids.size() in [1,5], "five strongholds, or first vertical slice")
	for id in ids:
		var d: Dictionary = DataLoader.get_dungeon(str(id))
		ok(d.monsters.size()==3 and d.stages.size()==3, "three unique boss stages")
		for i in range(3):
			var mid: String = str(d.monsters[i])
			ok(not unique.has(mid) and d.stages[i].monster==mid, "unique stage monster matches briefing")
			unique[mid]=true
			var m: Dictionary = DataLoader.get_monster(mid)
			ok(bool(m.is_boss) and not m.phases.is_empty(), "stage boss has mechanics")
			ok(ContentValidator.validate_monster_mechanics(mid,m).is_empty(), "valid boss phase mechanics")
		supplies(d)
		PlayerData.completion_log.dungeons.erase(str(d.requires_dungeon))
		ok(CombatManager.dungeon_lock_reason(str(id)).begins_with("Clear"), "prior clear gates entry")
		PlayerData.completion_log.dungeons[str(d.requires_dungeon)]=true
		PlayerData.set_level("slayer", 1)
		ok(not CombatManager.start_combat({"type":"dungeon","id":id,"monsters":d.monsters}), "skill gate enforced")
		PlayerData.set_level("slayer", 120)
		var food: int = BankManager.get_count("shark")
		ok(not CombatManager.start_combat({"type":"dungeon","id":id,"monsters":[d.monsters[-1]]}), "cannot skip stronghold stages")
		ok(not CombatManager.start_combat({"type":"dungeon","id":id,"monsters":d.monsters,"endless":true}), "stronghold cannot start as an endless encounter")
		ok(BankManager.get_count("shark")==food, "rejected entry spends no provisions")
		var ctx: Dictionary = {"type":"dungeon","id":id,"monsters":d.monsters,"endless":false}
		ok(CombatManager.start_combat(ctx), "prepared siege starts")
		CombatManager.apply_damage_to_monster(ceili(CombatManager.monster_max_hp*.51))
		ok(CombatManager.monster_phases_fired==1, "live stronghold stage phase fires at its HP threshold")
		ok(CombatManager.current_monster().max_hit>DataLoader.get_monster(str(d.monsters[0])).max_hit, "authored phase raises live monster damage")
		ok(BankManager.get_count("shark")==food-int(d.entry_items.shark), "entry cost spent once")
		ok(CombatManager.equipment_locked(), "loadout locked during siege")
		var gp: float = PlayerData.gp
		CombatManager.stop_combat("retreat")
		ok(PlayerData.gp==gp and not PlayerData.completion_log.dungeons.has(id), "retreat gives no clear reward")
		ok(CombatManager.start_combat(ctx), "defeat fixture starts")
		CombatManager._player_death("stronghold test")
		ok(PlayerData.gp==gp and not PlayerData.completion_log.dungeons.has(id), "defeat gives no clear reward")
		ok(CombatManager.start_combat(ctx), "second attempt starts")
		CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
		CombatManager.tick(6)
		var saved: Dictionary = CombatManager.serialize().duplicate(true)
		CombatManager.stop_combat()
		CombatManager.deserialize(saved)
		ok(CombatManager.current_monster_id==d.monsters[1], "saved siege resumes at second stage")
		for mid in d.monsters.slice(1):
			ok(CombatManager.current_monster_id==mid, "resumed sequence remains ordered")
			CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
			CombatManager.tick(6)
		ok(PlayerData.gp==gp+float(d.completion_reward.gp)+float(d.rewards_first_clear.gp), "repeat and first-clear gold paid once")
		var gear: String = str(d.rewards_first_clear.items.keys()[0])
		ok(BankManager.get_count(gear)==1, "unique first-clear equipment awarded")
		ok(not cleared_saves.is_empty() and int(cleared_saves[-1].state)==CombatManager.State.IDLE, "clear signal observes finished combat for saving")
		CombatManager.deserialize(cleared_saves[-1])
		ok(CombatManager.state==CombatManager.State.IDLE, "completed save cannot replay final fight")
		supplies(d)
		ok(CombatManager.start_combat(ctx), "cleared siege is repeatable")
		finish(d)
		ok(BankManager.get_count(gear)==1, "first-clear item never duplicates")
		ok(PlayerData.gp==gp+2*float(d.completion_reward.gp)+float(d.rewards_first_clear.gp), "repeat clear pays only repeat gold")
		for item in d.completion_reward.items:
			ok(BankManager.get_count(str(item))>=int(d.completion_reward.items[item])*2, "guaranteed repeat materials: "+str(item))
		supplies(d)
		gp=PlayerData.gp
		ok(CombatManager.start_combat(ctx), "offline siege starts")
		SimulationMode.begin()
		finish(d)
		ok(int(SimulationMode.get_table(SimulationMode.BUCKET_DUNGEONS).get(id,0))==1, "offline clear is recorded")
		SimulationMode.end()
		ok(PlayerData.gp==gp+float(d.completion_reward.gp) and BankManager.get_count(gear)==1, "offline clear rewards stay correct")
	var panel := preload("res://scripts/ui/panels/CombatPanel.gd").new()
	panel.expeditions_only=true
	add_child(panel)
	panel.call("_show_strongholds",true)
	ok(panel.get("_places").size()==ids.size(), "strongholds have separate encounter list")
	panel.focus_route({"area_id":ids[0]})
	ok(bool(panel.get("_strongholds_only")), "direct routes select Strongholds section")
	panel.free()
	var original: Dictionary=DataLoader.dungeons[ids[0]].duplicate(true)
	DataLoader.dungeons[ids[0]].stages[0].monster="invalid_stage"
	var rejected := false
	for issue in ContentValidator.new().validate_all():
		if issue.severity=="error" and str(issue.message).contains("stage 0"): rejected=true
	ok(rejected, "validator rejects broken stronghold stage metadata")
	DataLoader.dungeons[ids[0]]=original
	var issues: Array = ContentValidator.new().validate_all()
	var invalid := 0
	for issue in issues:
		if issue.severity in ["error","warning"]:
			invalid += 1
			print(issue)
	ok(invalid==0, "content has no errors or warnings")
	print("Strongholds: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
