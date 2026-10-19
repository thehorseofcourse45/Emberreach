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
	SimulationMode.begin()
	var specs: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/BlightExpansion.json"))
	check(DataLoader.get_skill_actions("corruption").size()==28,"28 Blight rituals available")
	for spec in specs:
		var id: String=spec[0]
		var action: Dictionary=DataLoader.get_action("corruption",id)
		check(not action.is_empty(),id+" resolves")
		if action.is_empty():continue
		check(int(action.level_required)==int(spec[2]),id+" unlock level")
		PlayerData.set_level("corruption",int(spec[2])-1)
		check(not SkillManager.can_perform("corruption",id),id+" rejects underlevel character")
		PlayerData.set_level("corruption",int(spec[2]))
		check(SkillManager.start_action("corruption",id),id+" starts at unlock level")
		var before: int=BankManager.get_count("abyssal_essence")
		var result: Dictionary=SkillManager.perform_action()
		check(bool(result.get("success",false)) and float(result.get("xp",0))>0,id+" grants XP")
		check(BankManager.get_count("abyssal_essence")-before>=int(action.output_items.abyssal_essence),id+" banks essence")
		check(MasteryManager.get_xp("corruption",id)>0,id+" earns mastery")
		SkillManager.stop_action()
		var estimate: Dictionary=ActionEstimates.for_action("corruption",id)
		check(float(estimate.get("outputs_per_hour",{}).get("abyssal_essence",0))>0,id+" planner projects essence")
		check(Goals._producer_recipes("abyssal_essence").any(func(p):return str(p.get("skill_id",""))=="corruption" and str(p.get("action_id",""))==id),id+" acquisition route exists")
		if not "--without-art" in OS.get_cmdline_user_args():
			var texture: Texture2D=AssetRegistry.icon("corruption",id)
			check(texture.resource_path!="" and texture.get_size()==Vector2(32,32),id+" authored 32x32 icon loads")
			var row: Control=Widgets.activity_row("corruption",action,false,func():pass)
			var used := false
			for node in row.find_children("*","TextureRect",true,false):used=used or node.texture==texture
			check(used,id+" activity row uses unique icon")
			row.free()
	SimulationMode.end()
	print("Blight expansion: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
