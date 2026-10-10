extends Node
const SITES = ["riverbank", "barrow", "fungal", "desert", "frostbound", "astral", "cinder", "voidglass"]
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",label)
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	seed(4936)
	var paths := {}
	var hexes := {}
	for ident in SITES:
		var a: Dictionary = DataLoader.get_action("archaeology",ident)
		var s: Dictionary = ArchaeologyManager.get_site(ident)
		check(not a.is_empty() and s.get("excavate_xp")==a.get("base_xp") and s.get("level_required")==a.get("level_required"), ident+" matching site metadata")
		check(DataLoader.cartography_hexes.has(s.hex) and not hexes.has(s.hex), ident+" distinct map placement")
		hexes[s.hex]=true
		PlayerData.set_level("archaeology",int(a.level_required)-1)
		check(not SkillManager.start_action("archaeology",ident),ident+" level gate")
		PlayerData.set_level("archaeology",int(a.level_required))
		var xp: float = PlayerData.get_xp("archaeology")
		var count: int = int(ArchaeologyManager.excavated.get(ident,0))
		check(SkillManager.start_action("archaeology",ident,1),ident+" starts")
		SkillManager.tick(SkillManager.current_interval+.01)
		check(PlayerData.get_xp("archaeology")>xp and int(ArchaeologyManager.excavated.get(ident,0))==count+1,ident+" live XP and excavation tracking")
		SkillManager.stop_action()
		check(SkillManager.start_action("archaeology",ident,10),ident+" offline starts")
		SkillManager.simulate_elapsed(SkillManager.current_interval*10+.1)
		check(int(ArchaeologyManager.excavated.get(ident,0))>=count+11,ident+" offline excavation tracking")
		SkillManager.stop_action()
		var save: Dictionary = ArchaeologyManager.serialize().duplicate(true)
		ArchaeologyManager.deserialize({})
		ArchaeologyManager.deserialize(save)
		check(int(ArchaeologyManager.excavated.get(ident,0))>=count+11,ident+" saved site progress")
		if not "--content-only" in OS.get_cmdline_user_args():
			var card := Widgets.activity_row("archaeology",a,false,func(): pass)
			var image: TextureRect = card.get_child(0).get_child(0).get_child(0)
			var path: String = "res://assets/icons/archaeology/%s.png" % ident
			check(image.texture!=null and image.texture.resource_path==path and image.texture.get_size()==Vector2(32,32),ident+" authored 32px activity icon")
			paths[path]=true
			card.free()
	var loot := {}
	var tables := {}
	for a in DataLoader.get_skill_actions("archaeology"):
		var ids: Array[String] = []
		for drop in a.secondary_outputs:
			ids.append(str(drop.item_id))
		ids.sort()
		tables[",".join(ids)]=true
	check(tables.size()==DataLoader.get_skill_actions("archaeology").size(),"every site has different finds")
	PlayerData.set_level("archaeology",1)
	SkillManager.start_action("archaeology","riverbank",300)
	SkillManager.simulate_elapsed(SkillManager.current_interval*300+.1)
	SkillManager.stop_action()
	check(BankManager.get_count("artefact_common")>0 and BankManager.get_count("copper_ore")>0,"new site produces museum artefacts and themed bonus loot")
	check(ArchaeologyManager.donate("artefact_common") and ArchaeologyManager.tokens>0,"new site artefacts work with museum donations")
	print("Excavation expansion: ",checks," checks, ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
