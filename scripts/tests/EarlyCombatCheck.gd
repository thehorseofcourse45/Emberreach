extends Node
const AREAS = ["reedbank_meadows","ashwood_trails","barrow_moor","rookwood_crossing","shale_ravine","tidebreak_cliffs"]
const DUNGEONS = ["scarecrow_cellar","ashwood_nest","barrow_chapel","rookwatch_tower","shaleheart_vault","saltglass_catacombs"]
var checks := 0
var failures := 0
func ok(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)
func _ready() -> void:
	GameManager.cli_mode=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	SaveManager._write_in_progress=true
	GameManager.start_new_game("standard")
	GameManager.is_paused=true
	BankManager.deserialize({"purchased_slots":200})
	DungeonModifierManager.selected_ids.clear()
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid),120)
	call_deferred("run")
func check_place(kind: String, id: String, place: Dictionary) -> void:
	ok(not place.is_empty(),"new encounter exists: "+id)
	var minimum := 10000
	var maximum := 0
	for mid in place.monsters:
		var level: int=DataLoader.get_monster(str(mid)).combat_level
		minimum=mini(minimum,level)
		maximum=maxi(maximum,level)
	ok(int(place.level_range[0])==minimum and int(place.level_range[1])==maximum,"range matches actual enemies: "+id)
	var texture=AssetRegistry.icon(kind,id)
	ok(texture.resource_path.ends_with(id+".png"),"authored icon loads: "+id)
	ok(texture.get_image().get_pixel(0,0).a==0,"transparent icon: "+id)
func clear_dungeon(id: String, d: Dictionary) -> void:
	CombatManager.player_hp=CombatManager._compute_max_hp()
	ok(CombatManager.start_combat({"type":"dungeon","id":id,"monsters":d.monsters,"endless":false,"attack_style":"melee","melee_style":"slash"}),"entry succeeds: "+id)
	for mid in d.monsters:
		ok(CombatManager.current_monster_id==mid,"ordered encounter: "+str(mid))
		CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
		CombatManager.tick(6)
	ok(CombatManager.state==CombatManager.State.IDLE,"finite dungeon stops: "+id)
func run() -> void:
	for id in AREAS:
		var area: Dictionary=DataLoader.areas[id]
		check_place("areas",id,area)
		CombatManager.player_hp=CombatManager._compute_max_hp()
		ok(CombatManager.start_combat({"type":"area","id":id,"monsters":area.monsters,"endless":true}),"region starts: "+id)
		ok(area.monsters.has(CombatManager.current_monster_id),"region spawns from its pool")
		CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
		ok(CombatManager.state in [CombatManager.State.FIGHTING,CombatManager.State.RESPAWNING] and CombatManager.context.id==id,"region keeps farming after a kill")
		CombatManager.stop_combat("retreat")
	for id in DUNGEONS:
		var d: Dictionary=DataLoader.get_dungeon(id)
		check_place("dungeons",id,d)
		ok(not CombatManager.is_expedition(id),"early dungeon stays in ordinary Combat")
		PlayerData.set_level("hitpoints",1)
		ok((CombatManager.dungeon_lock_reason(id)=="")== (int(d.requires.hitpoints)==1),"Vitality gate is enforced")
		PlayerData.set_level("hitpoints",120)
		var gp: float=PlayerData.gp
		var before: Dictionary={}
		for item in d.completion_reward.items: before[item]=BankManager.get_count(str(item))
		var gear: String=str(d.rewards_first_clear.items.keys()[0])
		var gear_before: int=BankManager.get_count(gear)
		clear_dungeon(id,d)
		ok(PlayerData.gp>=gp+float(d.completion_reward.gp),"clear pays guaranteed gold")
		for item in d.completion_reward.items: ok(BankManager.get_count(str(item))>=int(before[item])+int(d.completion_reward.items[item]),"clear pays guaranteed material")
		ok(PlayerData.completion_log.dungeons.has(id),"first clear is recorded")
		ok(BankManager.get_count(gear)>=gear_before+1,"first-clear equipment granted")
		gear_before=BankManager.get_count(gear)
		gp=PlayerData.gp
		clear_dungeon(id,d)
		ok(PlayerData.gp>=gp+float(d.completion_reward.gp),"repeat clear pays gold")
		var loot_has_gear := false
		for mid in d.monsters:
			for drop in DataLoader.get_monster(str(mid)).loot_table:
				if str(drop.get("item_id",""))==gear: loot_has_gear=true
		if not loot_has_gear: ok(BankManager.get_count(gear)==gear_before,"first-clear equipment does not repeat")
	var errors := 0
	var warnings := 0
	for issue in ContentValidator.new().validate_all():
		if issue.severity=="error": errors+=1; print(issue)
		if issue.severity=="warning": warnings+=1; print(issue)
	ok(errors==0,"content validator has no errors")
	print("Content validation: ",errors," errors; ",warnings," warnings")
	print("Early combat: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
