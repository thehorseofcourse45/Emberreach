extends Node
var checks := 0
var failures := 0
const NEW_WANDS: Array[String] = ["mist_wand", "cinder_wand", "aether_wand", "bloom_wand", "rime_wand", "tempest_wand", "eclipse_wand", "dawn_wand"]

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)

func check_preview(action: Dictionary) -> void:
	if "--content-only" in OS.get_cmdline_user_args():
		return
	var ident: String = str(action.output_items.keys()[0])
	var path: String = "res://assets/icons/items/%s.png" % ident
	var card := Widgets.activity_row("runecrafting", action, false, func(): pass)
	var preview: TextureRect = card.get_child(0).get_child(0).get_child(0)
	verify(preview.texture != null and preview.texture.resource_path == path and preview.texture.get_size() == Vector2(32,32), ident + " authored preview")
	card.free()

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	PlayerData.set_level("hitpoints", 120)
	var rune_ids: Array[String] = []
	var last_hit := 0
	for ident in NEW_WANDS:
		var wand: Dictionary = DataLoader.get_item(ident)
		var rune_id: String = str(wand.attack_cost_items.keys()[0])
		rune_ids.append(rune_id)
		var rune: Dictionary = DataLoader.get_action("runecrafting", rune_id)
		var craft: Dictionary = DataLoader.get_action("runecrafting", "craft_" + ident)
		verify(not rune.is_empty() and not craft.is_empty(), ident + " both recipes exist")
		verify(int(rune.level_required) <= int(craft.level_required), ident + " rune unlocks first")
		for action in [rune, craft]:
			PlayerData.set_level("runecrafting", int(action.level_required)-1)
			verify(not SkillManager.start_action("runecrafting", str(action.id)), str(action.id) + " level gate")
			PlayerData.set_level("runecrafting", int(action.level_required))
			var before_inputs: Dictionary = {}
			for material in action.input_items:
				BankManager.add_item(str(material), int(action.input_items[material])*4)
				before_inputs[material]=BankManager.get_count(str(material))
			var output: String = str(action.output_items.keys()[0])
			var before: int = BankManager.get_count(output)
			var xp: float = PlayerData.get_xp("runecrafting")
			verify(SkillManager.start_action("runecrafting", str(action.id), 1), str(action.id) + " starts")
			SkillManager.tick(SkillManager.current_interval+0.01)
			verify(BankManager.get_count(output)>before, str(action.id) + " produces output")
			var capped: bool = int(action.level_required) >= PlayerData.get_level_cap("runecrafting")
			verify(PlayerData.get_xp("runecrafting")==xp if capped else PlayerData.get_xp("runecrafting")>xp, str(action.id) + " grants XP or respects level cap")
			verify(BankManager.get_count(str(action.input_items.keys()[0])) < int(before_inputs[action.input_items.keys()[0]]), str(action.id) + " spends materials")
			SkillManager.stop_action()
			check_preview(action)
		PlayerData.set_level("magic", int(wand.level_requirements.magic)-1)
		verify(not EquipmentManager.equip(ident), ident + " equip level gate")
		PlayerData.set_level("magic", int(wand.level_requirements.magic))
		verify(EquipmentManager.equip(ident), ident + " equips")
		verify(is_equal_approx(EquipmentManager.get_weapon_attack_speed(),2.6), ident + " faster casting")
		verify(int(wand.spell_max_hit)>last_hit, ident + " rising wand spell tier")
		last_hit=int(wand.spell_max_hit)
		BankManager.add_item(rune_id,10)
		var summary: Dictionary = CombatManager.player_combat_summary("magic","stab")
		var snapshot: Dictionary = CombatSimulatorManager.build_snapshot("area","farmlands","magic","stab",true)
		verify(snapshot.attack_cost == wand.attack_cost_items, ident + " simulator rune cost")
		verify(is_equal_approx(float(snapshot.player.attack_interval), float(summary.attack_interval)) and int(snapshot.player.max_hit)==int(summary.max_hit), ident + " live/simulator damage and speed parity")
		var before_runes: int = BankManager.get_count(rune_id)
		verify(CombatManager.start_combat({"type":"area","id":"farmlands","monsters":["chicken"],"attack_style":"magic"}), ident + " combat starts")
		CombatManager.call("_player_attack")
		verify(BankManager.get_count(rune_id)==before_runes-1, ident + " live cast spends rune")
		CombatManager.stop_combat()
		BankManager.remove_item(rune_id,BankManager.get_count(rune_id))
		CombatManager.start_combat({"type":"area","id":"farmlands","monsters":["chicken"],"attack_style":"magic"})
		CombatManager.call("_player_attack")
		verify(CombatManager.state==CombatManager.State.IDLE, ident + " stops without rune supply")
		EquipmentManager.unequip(8)
		for material in rune.input_items:
			BankManager.add_item(str(material),int(rune.input_items[material])*20)
		var before: int = BankManager.get_count(rune_id)
		SkillManager.start_action("runecrafting",rune_id)
		SkillManager.simulate_elapsed(SkillManager.current_interval*3.0+0.01)
		verify(BankManager.get_count(rune_id)>=before+6, rune_id + " offline production")
		SkillManager.stop_action()
	verify(rune_ids.size()==8, "eight new rune families")
	for action in DataLoader.get_skill_actions("runecrafting"):
		var outputs: Dictionary = action.get("output_items",{})
		if outputs.size()==1:
			var ident: String = str(outputs.keys()[0])
			if ident.ends_with("_staff"):
				check_preview(action)
	var suite = preload("res://scripts/tests/TestRunner.gd").new()
	suite.call("_test_magic_gear")
	verify(int(suite.get("_failed"))==0, "existing magic gear progression still passes")
	suite = null
	print("Glyphcraft expansion checks: ",checks," passed: ",checks-failures," failures: ",failures)
	get_tree().quit(0 if failures==0 else 1)
