extends Node

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",label)

func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	SaveManager._write_in_progress=true
	call_deferred("run")

func run() -> void:
	GameManager.start_new_game("standard")
	GameManager.is_paused=true
	BankManager.deserialize({"purchased_slots":1000})
	ModifierManager._sources.clear()
	ModifierManager._mark_dirty()
	SkillManager.seed_rng(20261018)
	SimulationMode.begin()
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/PotionExpansion.json"))
	var icon_hashes := {}
	var potions := 0
	for id in DataLoader.items:
		if DataLoader.get_item(id).get("item_type","")=="potion":potions+=1
	check(potions==234,"234 potions across 39 complete families")
	check(DataLoader.get_skill_actions("herblore").size()==225,"225 Apothecary recipes")
	check((spec.new_ids as Array).all(func(id):return not DataLoader.get_item(id).is_empty()),"182 new potions resolve")
	if potions!=234:
		finish()
		return
	for recipe in spec.recipes:
		var id: String=recipe.id
		var item_id: String=recipe.output_items.keys()[0]
		PotionManager.clear()
		# Pet/event bonuses must not change these baseline recipe assertions.
		ModifierManager._sources.clear()
		ModifierManager._mark_dirty()
		for ingredient in recipe.input_items:
			BankManager.remove_item(ingredient,BankManager.get_count(ingredient))
		PlayerData.set_level("herblore",120)
		check(not SkillManager.can_perform("herblore",id),id+" requires its ingredients")
		for ingredient in recipe.input_items:BankManager.add_item_guaranteed(ingredient,int(recipe.input_items[ingredient]))
		PlayerData.set_level("herblore",int(recipe.level_required)-1)
		check(not SkillManager.can_perform("herblore",id),id+" respects unlock level")
		PlayerData.set_level("herblore",int(recipe.level_required))
		check(SkillManager.start_action("herblore",id),id+" starts with materials")
		var before: int=BankManager.get_count(item_id)
		var result: Dictionary=SkillManager.perform_action()
		check(bool(result.get("success",false)) and float(result.get("xp",0))>0 and BankManager.get_count(item_id)>before,id+" crafts potion and grants XP")
		check(MasteryManager.get_xp("herblore",id)>0,id+" gains mastery")
		check((recipe.input_items as Dictionary).keys().all(func(ingredient):return BankManager.get_count(ingredient)==0),id+" consumes upgrade ingredients")
		SkillManager.stop_action()
	for family in spec.families:
		var tiers: Dictionary=spec.families[family].tiers
		var prior: Dictionary={}
		for tier in range(1,7):
			var id: String=tiers[str(tier)]
			var item: Dictionary=DataLoader.get_item(id)
			check(str(item.get("potion_family",""))==family and int(item.get("potion_tier",0))==tier,id+" has family/tier metadata")
			var effect: Dictionary=item.potion_effect
			check(int(item.charges)>0 and not effect.is_empty(),id+" has charges and effects")
			check(prior.is_empty() or effect.keys().all(func(key):return float(effect[key])>float(prior.get(key,0))),id+" potency increases by tier")
			prior=effect
			PotionManager.clear()
			ModifierManager._sources.clear()
			ModifierManager._mark_dirty()
			BankManager.add_item_guaranteed(id,1)
			var count_before: int=BankManager.get_count(id)
			check(PotionManager.use_potion(id) and BankManager.get_count(id)==count_before-1,id+" uses one banked bottle")
			if family=="potion_dreamwalking":
				check(is_equal_approx(DreamwalkingManager.next_essence_bonus,float(effect.dreamwalking_essence_percent)) and not PotionManager.is_active(),id+" prepares correct dream bonus")
				var saved: Dictionary=DreamwalkingManager.serialize()
				DreamwalkingManager.next_essence_bonus=0
				DreamwalkingManager.deserialize(saved)
				check(is_equal_approx(DreamwalkingManager.next_essence_bonus,float(effect.dreamwalking_essence_percent)),id+" prepared bonus survives save/load")
			else:
				check(PlayerData.active_potion==id and PlayerData.potion_charges==int(item.charges),id+" activates with correct charges")
				check(effect.keys().all(func(key):return is_equal_approx(ModifierManager.get_modifier(key),float(effect[key]))),id+" registers real modifiers")
				var scope: String=str(item.get("charge_scope",""))
				var charges: int=PlayerData.potion_charges
				if scope!="":
					PotionManager.consume_charge("unrelated")
					check(PlayerData.potion_charges==charges,id+" ignores unrelated activity")
				PotionManager.consume_charge(scope)
				check(PlayerData.potion_charges==charges-1,id+" consumes charge in intended scope")
				PlayerData.potion_charges=1
				PotionManager.consume_charge(scope)
				check(not PotionManager.is_active() and not ModifierManager._sources.has(PotionManager.SOURCE_ID),id+" expires and removes modifiers")
			if not "--without-art" in OS.get_cmdline_user_args():
				var texture: Texture2D=AssetRegistry.item_icon(id)
				check(texture.resource_path.ends_with("/"+id+".png") and texture.get_size()==Vector2(32,32),id+" own authored tier icon loads")
				var icon_hash: int=hash(texture.get_image().get_data())
				check(not icon_hashes.has(icon_hash),id+" artwork is distinct from every other potion")
				icon_hashes[icon_hash]=true
	PotionManager.clear()
	for family in ["potion_lumberjack","potion_tidecatch","potion_forgekeeper","potion_artisan"]:
		var id: String=spec.families[family].tiers["6"]
		BankManager.add_item_guaranteed(id,1)
		PotionManager.use_potion(id)
		var actual: float=ModifierManager.get_doubling_chance("woodcutting" if family=="potion_lumberjack" else "fishing") if family in ["potion_lumberjack","potion_tidecatch"] else ModifierManager.get_preservation_chance("smithing" if family=="potion_forgekeeper" else "crafting")
		check(is_equal_approx(actual,30.0),family+" reaches skill's real output/preservation calculation")
		PotionManager.clear()
	check(not DreamwalkingManager.prepare_draught("potion_dr_1"),"unrelated potion rejected as dream draught")
	if not "--without-art" in OS.get_cmdline_user_args():
		for action in DataLoader.get_skill_actions("herblore"):
			var item_id: String=action.output_items.keys()[0]
			var expected: PackedByteArray=AssetRegistry.item_icon(item_id).get_image().get_data()
			var row: Control=Widgets.activity_row("herblore",action,false,func():pass)
			var previews: Array=row.find_children("*","TextureRect",true,false)
			var matches: bool=not previews.is_empty() and previews[0].texture!=null and previews[0].texture.get_image().get_data()==expected
			check(matches,str(action.id)+" Apothecary row matches its tier artwork")
			row.free()
		for action in DataLoader.get_skill_actions("inscription"):
			var art_ok := true
			for item_id in action.get("output_items",{}):art_ok=art_ok and AssetRegistry.item_icon(item_id).resource_path!=""
			check(art_ok,str(action.id)+" Scribing output has authored art")
		for id in spec.scribing:
			var texture: Texture2D=AssetRegistry.item_icon(id)
			check(texture.resource_path.ends_with("/"+str(id)+".png") and texture.get_size()==Vector2(32,32),str(id)+" own tome icon loads")
	SimulationMode.end()
	finish()

func finish() -> void:
	print("Potion expansion: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
