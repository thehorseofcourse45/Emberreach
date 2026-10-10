extends Node
const NEW = ["follow_footprints", "question_ferryman", "search_watchtower", "decode_cipher", "recover_sunken_cache", "unmask_phantom"]
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)
func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	var rng: RandomNumberGenerator = SkillManager.get("_rng")
	rng.seed = 8301
	for ident in NEW:
		var a: Dictionary = DataLoader.get_action("lostfinding", ident)
		check(not a.is_empty(), ident+" exists")
		for item in a.input_items:
			BankManager.add_item(str(item), 500)
		PlayerData.set_level("lostfinding", int(a.level_required)-1)
		check(not SkillManager.start_action("lostfinding", ident), ident+" level gate")
		PlayerData.set_level("lostfinding", int(a.level_required))
		var output: String = str(a.output_items.keys()[0])
		var input: String = str(a.input_items.keys()[0])
		var before: int = BankManager.get_count(output)
		var before_input: int = BankManager.get_count(input)
		var xp: float = PlayerData.get_xp("lostfinding")
		check(SkillManager.start_action("lostfinding", ident), ident+" starts")
		for i in 20:
			SkillManager.tick(SkillManager.current_interval+.01)
		check(BankManager.get_count(output)>before and PlayerData.get_xp("lostfinding")>xp, ident+" live rewards and XP")
		check(BankManager.get_count(input)<before_input, ident+" consumes evidence")
		var saved: Dictionary = SkillManager.serialize().duplicate(true)
		SkillManager.stop_action()
		SkillManager.deserialize(saved)
		check(SkillManager.active_action_id==ident, ident+" active case survives save roundtrip")
		SkillManager.stop_action()
		before=BankManager.get_count(output)
		check(SkillManager.start_action("lostfinding", ident, 20), ident+" offline starts")
		SimulationMode.begin()
		var result: Dictionary = SkillManager.simulate_elapsed(300.)
		SimulationMode.end()
		check(int(result.actions)>=20 and BankManager.get_count(output)>before, ident+" offline rewards")
		SkillManager.stop_action()
	var icons := {}
	for a in DataLoader.get_skill("lostfinding").actions:
		check(bool(a.get("icon_activity", false)), str(a.id)+" uses dedicated artwork")
		if "--content-only" in OS.get_cmdline_user_args():
			continue
		var card := Widgets.activity_row("lostfinding", a, false, func(): pass)
		var preview: TextureRect = card.get_child(0).get_child(0).get_child(0)
		check(preview.texture!=null and preview.texture.resource_path=="res://assets/icons/lostfinding/%s.png" % a.id and preview.texture.get_size()==Vector2(32,32), str(a.id)+" loads correct 32px artwork")
		if preview.texture!=null:
			icons[preview.texture.get_image().get_data().hex_encode().sha256_text()] = true
		card.free()
	if not "--content-only" in OS.get_cmdline_user_args():
		check(icons.size()==24, "all 24 activity sprites are different")
	print("Lostfinding expansion: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures==0 else 1)
