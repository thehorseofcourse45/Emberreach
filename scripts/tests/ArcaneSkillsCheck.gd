extends Node
var checks := 0
var failures := 0

func ok(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", message)

func reset() -> void:
	SkillManager.stop_action()
	CombatManager.stop_combat()
	PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
	PlayerData.initialize_new_game()
	BankManager.deserialize({"purchased_slots": 200})
	EquipmentManager.deserialize({})
	MasteryManager.deserialize({})
	SkillManager.deserialize({})
	Quests.deserialize({})
	ModifierManager._sources.clear()
	ModifierManager._mark_dirty()
	PlayerData.game_mode = "standard"

func level(skill: String, value: int) -> void:
	PlayerData.add_xp(skill, XPTable.xp_for_level(value))

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("run")

func run() -> void:
	reset()
	for skill in ["riftkeeping", "spellweaving"]:
		ok(PlayerData.get_level(skill) == 1, skill + " starts at 1")
		var actions: Array = DataLoader.get_skill_actions(skill)
		ok(actions.size() == 36, skill + " has 36 activities")
		ok(int(actions[0].level_required) == 1 and int(actions[-1].level_required) == 120, skill + " covers 1Ã¢â‚¬â€œ120")
		ok(not SkillManager.start_action(skill, str(actions[-1].id)), skill + " enforces level gates")
		level(skill, 120)
	# Real completions exercise materials, stats, XP and mastery for all 72 recipes.
	PlayerData.settings.riftkeeping_mode = "safe"
	for action in DataLoader.get_skill_actions("riftkeeping"):
		var before := PlayerData.get_xp("riftkeeping")
		ok(SkillManager.start_action("riftkeeping", str(action.id)), str(action.id) + " starts")
		var result: Dictionary = SkillManager.perform_action()
		ok(bool(result.get("success", false)), str(action.id) + " completes")
		ok(BankManager.get_count(str(action.output_items.keys()[0])) > 0, str(action.id) + " produces aether")
		ok(float(result.get("xp", 0)) > 0 and MasteryManager.get_xp("riftkeeping", str(action.id)) > 0, str(action.id) + " grants skill and mastery rewards at cap")
		SkillManager.stop_action()
	for action in DataLoader.get_skill_actions("spellweaving"):
		ok(not ArcaneSkills.learned(action), str(action.id) + " begins unlearned")
		for item in action.input_items:
			BankManager.add_item(str(item), int(action.input_items[item]) * 3)
		ok(SkillManager.start_action("spellweaving", str(action.id)), str(action.id) + " starts")
		var result: Dictionary = SkillManager.perform_action()
		ok(bool(result.get("success", false)) and ArcaneSkills.learned(action), str(action.id) + " permanently learns on success")
		ok(MasteryManager.get_xp("spellweaving", str(action.id)) > 0, str(action.id) + " has mastery")
		SkillManager.stop_action()
	var learned_save: Dictionary = PlayerData.serialize().duplicate(true)
	PlayerData.deserialize(learned_save)
	for action in DataLoader.get_skill_actions("spellweaving"):
		ok(ArcaneSkills.learned(action), str(action.id) + " learning survives save roundtrip")
	level("magic", 120)
	EquipmentManager.slots[ItemData.EquipmentSlot.WEAPON] = "fire_staff"
	CombatManager.attack_style = "melee"
	var original_magic: Dictionary = CombatManager.player_combat_summary("magic", "stab")
	var original_melee: Dictionary = CombatManager.player_combat_summary("melee", "stab")
	var base_cost: Dictionary = EquipmentManager.get_attack_cost("magic")
	for action in DataLoader.get_skill_actions("spellweaving"):
		PlayerData.settings.spellweaving_pattern = str(action.id)
		var pattern := ArcaneSkills.active_pattern("magic")
		ok(not pattern.is_empty(), str(action.id) + " can cast when learned")
		ok(ArcaneSkills.active_pattern("melee").is_empty() and ArcaneSkills.active_pattern("ranged").is_empty(), str(action.id) + " does not affect other styles")
		var live: Dictionary = CombatManager.player_combat_summary("magic", "stab")
		var snapshot: Dictionary = CombatSimulatorManager.build_snapshot("area", str(DataLoader.areas.keys()[0]), "magic", "stab", true)
		for key in ["accuracy", "max_hit", "attack_interval"]:
			ok(live[key] == snapshot.player[key], str(action.id) + " simulator shares " + key)
		ok(snapshot.attack_cost == EquipmentManager.get_attack_cost("magic"), str(action.id) + " simulator shares rune costs with live magic despite current melee style")
		ok(snapshot.weapon_special == EquipmentManager.get_weapon_special_attack("magic"), str(action.id) + " simulator shares casting effect")
		ok(CombatManager.player_combat_summary("melee", "stab") == original_melee, str(action.id) + " leaves melee unchanged")
		for rune in base_cost:
			ok(int(snapshot.attack_cost.get(rune, 0)) >= int(base_cost[rune]), str(action.id) + " preserves weapon rune cost")
	PlayerData.settings.spellweaving_pattern = "missing_pattern"
	ok(ArcaneSkills.active_pattern("magic").is_empty(), "invalid saved pattern falls back")
	ok(CombatManager.player_combat_summary("magic", "stab") == original_magic, "fallback retains original spell stats")
	PlayerData.settings.spellweaving_pattern = "ember_dart"
	CombatManager.attack_style = "magic"
	CombatManager.current_monster_id = str(DataLoader.monsters.keys()[0])
	CombatManager.monster_hp = 100000
	CombatManager.monster_max_hp = 100000
	CombatManager.state = CombatManager.State.FIGHTING
	BankManager.add_item("fire_rune", 100)
	var before_runes: Dictionary = {}
	for rune in EquipmentManager.get_attack_cost("magic"):
		BankManager.add_item(str(rune), 100)
		before_runes[rune] = BankManager.get_count(str(rune))
	var shot: Dictionary = EquipmentManager.get_attack_cost("magic")
	CombatManager._player_attack()
	for rune in shot:
		ok(BankManager.get_count(str(rune)) == int(before_runes[rune]) - int(shot[rune]), "actual magic attack spends " + str(rune))
	var cast_snapshot := CombatSimulatorManager.build_snapshot("area", str(DataLoader.areas.keys()[0]), "magic", "stab", true)
	var report := CombatSimulator.simulate(cast_snapshot, 3, 123)
	ok(int(report.get("kills", 0)) > 0, "woven spell fights in pure simulator")
	var spell_panel := preload("res://scripts/ui/panels/NewSkillSystems.gd").new()
	add_child(spell_panel)
	spell_panel.set_skill("spellweaving")
	ok(option_count(spell_panel) == 2, "spell and casting style selectors are built in skill UI")
	spell_panel.free()
	var ordinary: Dictionary = EquipmentManager.get_attack_cost("magic")
	MasteryManager._mastery_xp["spellweaving"]["ember_dart"] = XPTable.xp_for_level(120)
	PlayerData.settings.spellweaving_tuning = "frugal"
	ok(EquipmentManager.get_attack_cost("magic") == base_cost, "mastery/frugal remove extra runes without removing weapon costs")
	PlayerData.settings.spellweaving_tuning = "rapid"
	ok(EquipmentManager.get_weapon_attack_speed("magic") < float(DataLoader.get_item("fire_staff").attack_speed), "rapid casting changes speed")
	EquipmentManager.slots[8] = "bronze_sword"
	ok(ArcaneSkills.active_pattern("magic").is_empty(), "nonmagic weapon cannot use pattern")
	# Stances and failure recovery run through the same action engine.
	reset()
	var output := "aether_candle_fracture"
	for mode in ArcaneSkills.MODES:
		PlayerData.settings.riftkeeping_mode = mode
		var data: Dictionary = DataLoader.get_action("riftkeeping", "candle_fracture")
		ok(data == DataLoader.get_skill_actions("riftkeeping")[0], mode + " list/details use same action")
		ok(float(data.success_chance) >= .65 and int(data.output_items[output]) > 0, mode + " has valid odds and yield")
	PlayerData.settings.riftkeeping_mode = "overcharged"
	SkillManager.seed_rng(12)
	SkillManager.start_action("riftkeeping", "candle_fracture")
	var failed := false
	for i in range(30):
		if not bool(SkillManager.perform_action().get("success", false)):
			failed = true
			break
	ok(failed and SkillManager.stun_timer > 0.0, "overcharged collapse causes recovery")
	SkillManager.stop_action()
	var online := extraction(false)
	var offline := extraction(true)
	ok(online == offline, "online/offline extraction parity including node recovery and random failures")
	reset()
	ok(not SkillManager.start_action("spellweaving", "ember_dart"), "missing materials prevent learning")
	ok(not ArcaneSkills.learned(DataLoader.get_action("spellweaving", "ember_dart")), "failed start never learns")
	PlayerData.settings.riftkeeping_mode = "safe"
	SkillManager.start_action("riftkeeping", "candle_fracture")
	for i in range(10): SkillManager.perform_action()
	SkillManager.stop_action()
	ok(Quests.accept("riftkeeping_foundation") and Quests.claim("riftkeeping_foundation"), "rift starter task can be completed and claimed")
	ok(BankManager.get_count("air_rune") >= 10 and BankManager.get_count("rune_essence") >= 10, "rift task provides first spell ingredients")
	ok(SkillManager.start_action("spellweaving", "ember_dart"), "starter reward enables spellweaving without injected ingredients")
	SkillManager.perform_action()
	SkillManager.stop_action()
	ok(Quests.accept("spellweaving_foundation") and Quests.claim("spellweaving_foundation"), "spell starter task completes after learning")
	PlayerData.deserialize({"skills": {}, "settings": {"sfx_volume": 7}})
	ok(PlayerData.get_level("riftkeeping") == 1 and PlayerData.get_level("spellweaving") == 1, "old save initializes both new skills")
	ok(float(PlayerData.settings.sfx_volume) == 7 and PlayerData.settings.spellweaving_pattern == "", "old save preserves preferences and adds casting defaults")
	var skill_panel := preload("res://scripts/ui/panels/SkillsPanel.gd").new()
	add_child(skill_panel)
	for skill in ["riftkeeping", "spellweaving"]:
		skill_panel.focus_route({"skill_id": skill})
		ok(skill_panel.get("_activities_card").visible, skill + " activity list remains visible")
		ok(skill_panel.get("_activities").get_child_count() >= 24, skill + " renders all activities")
		ok(skill_panel.get("_systems").visible and skill_panel.get("_systems").get_index() < skill_panel.get("_main_grid").get_index(), skill + " controls are above activity grid")
	skill_panel.free()
	var validator := ContentValidator.new()
	ok(not ContentValidator.validate_woven_spell({"runes": {"missing_rune": -1}}).is_empty(), "invalid spell metadata rejected")
	for action in DataLoader.get_skill_actions("spellweaving"):
		ok(ContentValidator.validate_woven_spell(action.woven_spell).is_empty(), str(action.id) + " casting metadata validates")
	var errors := 0
	var warnings := 0
	for issue in validator.validate_all():
		if issue.severity == "error":
			errors += 1
			print("VALIDATION ERROR: ", issue.message)
		if issue.severity == "warning":
			warnings += 1
			print("VALIDATION WARNING: ", issue.message)
	ok(errors == 0 and warnings == 0, "content validation")
	print("Arcane skills: ", checks, " checks; ", failures, " failures; content ", errors, " errors / ", warnings, " warnings")
	get_tree().quit(0 if failures == 0 else 1)

func extraction(offline: bool) -> Dictionary:
	reset()
	SkillManager.seed_rng(9876)
	SkillManager.start_action("riftkeeping", "candle_fracture")
	if offline:
		SkillManager.simulate_elapsed(120.0)
	else:
		for i in range(480):
			SkillManager.tick(.25, false)
	return {"items": BankManager.items.duplicate(), "xp": PlayerData.get_xp("riftkeeping"), "mastery": MasteryManager.get_xp("riftkeeping", "candle_fracture"), "actions": PlayerData.get_stat("actions", "riftkeeping:candle_fracture")}

func option_count(node: Node) -> int:
	var count := 1 if node is OptionButton else 0
	for child in node.get_children(): count += option_count(child)
	return count
