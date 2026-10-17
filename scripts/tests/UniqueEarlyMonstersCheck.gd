extends Node
const REGIONS=["reedbank_meadows","ashwood_trails","barrow_moor","rookwood_crossing","shale_ravine","tidebreak_cliffs"]
const DUNGEONS=["scarecrow_cellar","ashwood_nest","barrow_chapel","rookwatch_tower","shaleheart_vault","saltglass_catacombs"]
var checks := 0
var failures := 0
func ok(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		print("FAIL: ",message)
func _ready() -> void:
	GameManager.cli_mode=true
	GameManager.is_paused=true
	SaveManager.autosave_enabled=false
	SaveManager.save_on_major_event=false
	SaveManager._write_in_progress=true
	PlayerData.initialize_new_game()
	PlayerData.settings=SettingsDefaults.DEFAULTS.duplicate(true)
	BankManager.deserialize({"purchased_slots":200})
	EquipmentManager.deserialize({})
	var known: Dictionary={}
	var hashes: Dictionary={}
	for i in range(REGIONS.size()):
		var area: Dictionary=DataLoader.areas[REGIONS[i]]
		var styles: Dictionary={}
		ok(area.monsters.size()==3,"three regional enemies")
		for id in area.monsters:
			ok(not known.has(id),"unique regional monster")
			known[id]=true
			var monster: Dictionary=DataLoader.get_monster(str(id))
			styles[monster.attack_type]=true
			ok(not monster.is_boss,"regional monster is farmable")
		ok(styles.size()==3,"region covers all combat styles")
		var dungeon: Dictionary=DataLoader.get_dungeon(DUNGEONS[i])
		var boss: String=str(dungeon.monsters[-1])
		ok(not known.has(boss),"boss distinct from regional monsters")
		known[boss]=true
		var monster: Dictionary=DataLoader.get_monster(boss)
		ok(monster.is_boss and monster.special_attacks.size()==1,"boss has dedicated special")
		ok(str(monster.special_attacks[0])==boss+"_special","special belongs to this boss")
		ok(not CombatManager.is_expedition(DUNGEONS[i]),"dungeon stays in ordinary Dungeons tab")
		for id in dungeon.monsters: ok(known.has(id) or id=="mourning_lantern","dungeon uses new enemies")
	ok(known.size()==24,"24 unique monsters")
	for id in known:
		var monster: Dictionary=DataLoader.get_monster(str(id))
		ok(ContentValidator.validate_monster_mechanics(str(id),monster).is_empty(),"valid combat mechanics")
		var texture: Texture2D=AssetRegistry.monster_sprite(str(id))
		ok(texture.resource_path.ends_with(str(id)+".png"),"real sprite loaded: "+str(id))
		ok(texture.get_size()==Vector2(96,96),"96x96 sprite")
		var im: Image=texture.get_image()
		ok(im.get_pixel(0,0).a==0 and im.get_pixel(95,95).a==0,"transparent sprite corners")
		var hash: String=im.get_data().hex_encode().sha256_text()
		ok(not hashes.has(hash),"unique sprite pixels")
		hashes[hash]=true
	var invalid := 0
	for issue in ContentValidator.new().validate_all():
		if issue.severity in ["error","warning"]: invalid+=1; print(issue)
	ok(invalid==0,"content has no errors or warnings")
	print("Unique early monsters: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
