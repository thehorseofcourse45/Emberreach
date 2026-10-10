extends Node
const VEINS = ["tin_flecked", "carbon_seam", "argent_seam", "gilded_seam", "azure_seam", "frostcrystal_seam", "ember_seam", "crownstone_seam"]
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
	var rng: RandomNumberGenerator = SkillManager.get("_rng")
	rng.seed=4936
	for ident in VEINS:
		var a: Dictionary = DataLoader.get_action("harvesting",ident)
		check(not a.is_empty(), ident+" exists")
		PlayerData.set_level("harvesting",int(a.level_required)-1)
		check(not SkillManager.start_action("harvesting",ident),ident+" level gate")
		PlayerData.set_level("harvesting",int(a.level_required))
		var output: String = str(a.output_items.keys()[0])
		var stock: int = BankManager.get_count(output)
		var xp: float = PlayerData.get_xp("harvesting")
		check(SkillManager.start_action("harvesting",ident),ident+" starts")
		var tier: Dictionary = SkillManager.richness_tier()
		check(not tier.is_empty() and SkillManager.node_max_hp==maxi(1,roundi(float(a.node_hp)*float(tier.hp_mult))),ident+" rolls and scales richness")
		SkillManager.tick(SkillManager.current_interval+.01)
		check(PlayerData.get_xp("harvesting")>xp and BankManager.get_count(output)>stock,ident+" grants live XP and essence")
		var saved: Dictionary = SkillManager.serialize().duplicate(true)
		var richness: String = SkillManager.node_richness
		var hp: int = SkillManager.node_hp
		SkillManager.stop_action()
		SkillManager.deserialize(saved)
		check(SkillManager.active_action_id==ident and SkillManager.node_richness==richness and SkillManager.node_hp==hp,ident+" active vein survives save round trip")
		SkillManager.node_hp=1
		SkillManager.tick(SkillManager.current_interval+.01)
		check(SkillManager.node_hp==0 and SkillManager.node_respawn_timer>0,ident+" depletes")
		SkillManager.tick(SkillManager.node_respawn_timer+.01)
		check(SkillManager.node_hp>0 and not SkillManager.richness_tier().is_empty(),ident+" respawns with richness")
		SkillManager.stop_action()
		var ore: String = str(a.secondary_outputs[0].item_id)
		var before_ore: int = BankManager.get_count(ore)
		stock=BankManager.get_count(output)
		SkillManager.start_action("harvesting",ident,300)
		SimulationMode.begin()
		var result: Dictionary = SkillManager.simulate_elapsed(2400.)
		SimulationMode.end()
		check(int(result.actions)==300 and BankManager.get_count(output)>=stock+300,ident+" offline production crosses respawns")
		check(BankManager.get_count(ore)>before_ore,ident+" themed ore bonus drops")
		SkillManager.stop_action()
		if not "--content-only" in OS.get_cmdline_user_args():
			var card := Widgets.activity_row("harvesting",a,false,func(): pass)
			var image: TextureRect = card.get_child(0).get_child(0).get_child(0)
			check(image.texture!=null and image.texture.resource_path=="res://assets/icons/harvesting/%s.png" % ident and image.texture.get_size()==Vector2(32,32),ident+" authored 32px vein preview")
			card.free()
	var suite=preload("res://scripts/tests/TestRunner.gd").new()
	suite.call("_test_vein_richness")
	check(int(suite.get("_failed"))==0,"existing richness behaviour remains valid")
	suite=null
	print("Prospecting expansion: ",checks," checks, ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
