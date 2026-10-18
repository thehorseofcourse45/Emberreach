extends Node

const Loot = preload("res://scripts/core/PickpocketLoot.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",label)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	SaveManager._write_in_progress = true
	call_deferred("run")

func run() -> void:
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	BankManager.deserialize({"purchased_slots":1000})
	ModifierManager._sources.clear()
	ModifierManager._mark_dirty()
	PlayerData.set_level("hitpoints",120)
	SimulationMode.begin()
	var specs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/LarcenyExpansion.json"))
	check(DataLoader.get_skill_actions("thieving").size()==36,"36 Larceny targets available")
	for spec in specs:
		var id: String = str(spec.id)
		var action: Dictionary = DataLoader.get_action("thieving",id)
		check(not action.is_empty(),id+" resolves")
		if action.is_empty():
			continue
		check(int(action.level_required)==int(spec.level),id+" unlock level")
		var table: Array = action.get("pickpocket_loot",[])
		check(Loot.valid_table(table,DataLoader.items),id+" valid complete loot table")
		check(table.size()==6 and table.any(func(e):return float(e.chance)<=0.01),id+" has six outcomes including a rare reward")
		var rng := RandomNumberGenerator.new()
		rng.seed = 123+int(spec.level)
		var seen := {}
		for i in range(2000):
			var drop: Dictionary = Loot.roll(table,rng)
			seen[str(drop.get("item_id",""))] = true
		check(seen.size()==6,id+" every reward can roll")
		PlayerData.set_level("thieving",int(spec.level)-1)
		check(not SkillManager.can_perform("thieving",id),id+" rejects underlevel character")
		PlayerData.set_level("thieving",int(spec.level))
		SkillManager.seed_rng(1000+int(spec.level))
		check(SkillManager.start_action("thieving",id),id+" starts at its level")
		var succeeded := 0
		var failed := 0
		var success_valid := true
		var failure_valid := true
		var penalties_valid := true
		for i in range(100):
			CombatManager.player_hp=CombatManager._compute_max_hp()
			SkillManager.stun_timer=0.0
			var hp_before: float = CombatManager.player_hp
			var gp_before: float = PlayerData.gp
			var bank_before: Dictionary = BankManager.items.duplicate(true)
			var result: Dictionary = SkillManager.perform_action()
			if bool(result.get("success",false)):
				succeeded += 1
				success_valid = success_valid and float(result.get("xp",0))>0 and PlayerData.gp>=gp_before+float(action.gp_reward)
				var got_loot := false
				for entry in table:
					var item: String = str(entry.item_id)
					got_loot = got_loot or BankManager.get_count(item)>int(bank_before.get(item,0))
				success_valid = success_valid and got_loot
			else:
				failed += 1
				failure_valid = failure_valid and (result.get("items",{}) as Dictionary).is_empty() and BankManager.items==bank_before and PlayerData.gp==gp_before
				penalties_valid = penalties_valid and is_equal_approx(SkillManager.stun_timer,float(action.stun_seconds)) and is_equal_approx(hp_before-CombatManager.player_hp,float(action.fail_damage))
		check(succeeded>0 and failed>0,id+" both success and failure exercised")
		check(success_valid,id+" successes grant XP, gold and banked loot")
		check(failure_valid,id+" failures grant no gold or items")
		check(penalties_valid,id+" failure damage and stun apply")
		check(MasteryManager.get_xp("thieving",id)>0,id+" earns mastery")
		SkillManager.stop_action()
		var projection: Dictionary = ActionEstimates.for_action("thieving",id)
		var first_item: String = str(table[0].item_id)
		check(float(projection.get("outputs_per_hour",{}).get(first_item,0))>0,id+" loot is included in planning")
		check(Goals._producer_recipes(first_item).any(func(p):return str(p.get("skill_id",""))=="thieving" and str(p.get("action_id",""))==id),id+" acquisition route exists")
		if not "--without-art" in OS.get_cmdline_user_args():
			var texture: Texture2D = AssetRegistry.icon("thieving",id)
			check(texture.resource_path!="" and texture.get_size()==Vector2(32,32),id+" authored 32x32 sprite loads")
			var row: Control = Widgets.activity_row("thieving",action,false,func():pass)
			var used := false
			for node in row.find_children("*","TextureRect",true,false):
				used = used or node.texture==texture
			check(used,id+" activity row uses its own sprite")
			row.free()
	SimulationMode.end()
	print("Larceny expansion: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
