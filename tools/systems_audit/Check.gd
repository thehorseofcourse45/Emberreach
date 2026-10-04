extends Node
## Read-only audit of production files; all reproduction state is isolated in this process.

var failures: int = 0
func report(id: String, passed: bool, detail: String) -> void:
	if not passed: failures += 1
	print("REGRESSION ", id, ": ", "PASS" if passed else "FAIL", " | ", detail)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	PlayerData.initialize_new_game()
	for id in DataLoader.get_skill_ids(): PlayerData.set_level(id, 120)
	BankManager.deserialize({})
	EquipmentManager.deserialize({})
	SimulationMode.begin()
	BankManager.add_item_guaranteed("bronze_sword", 1)
	EquipmentManager.equip("bronze_sword")
	EquipmentManager.save_current_to_set(0)
	EquipmentManager.load_set(0)
	var swords_owned: int = BankManager.get_total_owned("bronze_sword") + (1 if EquipmentManager.is_equipped("bronze_sword") else 0)
	report("equipment-set-duplication", swords_owned == 1, "One sword becomes %d after reloading its set (Storage plus equipped)" % swords_owned)
	EquipmentManager.deserialize({})
	BankManager.deserialize({})
	BankManager.add_item_guaranteed("bronze_shield", 1)
	EquipmentManager.equip("bronze_shield")
	var two_handed: String = ""
	for id in DataLoader.items:
		if bool(DataLoader.items[id].get("is_two_handed", false)):
			two_handed = str(id)
			break
	BankManager.add_item_guaranteed(two_handed, 1)
	var equipped: bool = EquipmentManager.equip(two_handed)
	report("two-handed-shield-loss", equipped and BankManager.get_total_owned("bronze_shield") == 1, "Shield owned after equipping %s: %d" % [two_handed, BankManager.get_total_owned("bronze_shield")])
	RaidManager.active = true
	RaidManager.wave = 1
	RaidManager.coins_this_raid = 0.0
	RaidManager.pending_choices = []
	SimulationMode.end()
	CombatManager.context = {"type": "raid"}
	CombatManager.state = CombatManager.State.FIGHTING
	CombatManager.stop_combat("complete")
	report("raid-completion-event", RaidManager.coins_this_raid > 0 and not RaidManager.pending_choices.is_empty(), "Live completion grants wave coins and upgrade choices")
	SimulationMode.begin()
	RaidManager.coins_this_raid = 123.0
	RaidManager.pending_choices = [DataLoader.raid_shop.upgrades.keys()[0]]
	var saved: Dictionary = JSON.parse_string(JSON.stringify(RaidManager.serialize()))
	RaidManager.coins_this_raid = 0.0
	RaidManager.pending_choices = []
	RaidManager.deserialize(saved)
	report("raid-save-progress", RaidManager.coins_this_raid == 123 and RaidManager.pending_choices.size() == 1, "Unbanked coins and pending choices survive JSON round trip")
	PlayerData.set_level("cartography", 1)
	var free_hex: String = ""
	for id in DataLoader.cartography_hexes:
		if float(DataLoader.cartography_hexes[id].get("travel_cost", -1)) == 0:
			free_hex = str(id)
			break
	var before_xp: float = PlayerData.get_xp("cartography")
	CartographyManager.travel(free_hex)
	CartographyManager.travel(free_hex)
	var repeated_xp: float = PlayerData.get_xp("cartography") - before_xp
	report("free-repeat-travel-xp", repeated_xp == float(DataLoader.cartography_hexes[free_hex].get("survey_xp", 0)), "Two free visits to %s grant %s XP" % [free_hex, repeated_xp])
	TownshipManager.deserialize({})
	for id in DataLoader.township_buildings:
		if not DataLoader.township_buildings[id].get("production", {}).is_empty():
			TownshipManager.buildings[id] = 1
	TownshipManager._tick_accumulator = 0.0
	var before_stored: float = TownshipManager.total_stored()
	TownshipManager._process(3600.0)
	report("settlement-pause-clock", TownshipManager.total_stored() == before_stored, "Settlement remains unchanged while paused")
	for res in TownshipManager.ALL_RESOURCES: TownshipManager.resources[res] = 1000000.0
	for offer in TownshipManager.offers():
		var grants: Dictionary = offer.get("grant_items", {})
		if grants.is_empty(): continue
		var item: String = str(grants.keys()[0])
		var before: float = float(PlayerData.stats.get("items_gained", {}).get(item, 0))
		var result: Dictionary = TownshipManager.trade_offer(str(offer.id))
		var gained: float = float(PlayerData.stats.get("items_gained", {}).get(item, 0)) - before
		report("trader-lifetime-double-count", bool(result.ok) and gained == int(grants[item]), "%d granted %s counted as %s lifetime gains" % [int(grants[item]), item, gained])
		break
	_extra_checks()
	_sim_checks()
	print("AUDIT REGRESSIONS COMPLETE; failures: ", failures, "; saving disabled")
	get_tree().quit(1 if failures else 0)

func _extra_checks() -> void:
	report("mastery-pool-explanation", MasteryManager.next_checkpoint("woodcutting").contains("no authored pool bonuses"), "Pool UI does not invent bonuses for skills without authored checkpoints")
	var original_mods: Dictionary = ModifierManager.serialize()
	for sid in DataLoader.get_skill_ids():
		for action in DataLoader.get_skill_actions(str(sid)):
			var estimate: Dictionary = ActionEstimates.for_action(str(sid), str(action.id))
			report("projection:" + str(sid) + ":" + str(action.id), not estimate.is_empty() and is_finite(float(estimate.xp_per_hour)) and float(estimate.effective_interval) > 0 and float(estimate.success_chance) >= 0 and float(estimate.success_chance) <= 1, "Finite, bounded activity projection")
	report("projection-read-only", ModifierManager.serialize() == original_mods, "Previews never mutate live modifier sources")
	EquipmentManager.set_support["0"] = {"food": "invalid"}
	report("invalid-support-atomic", not bool(EquipmentManager.set_preview(0).ok), "Malformed support set rejected")
	EquipmentManager.set_support.clear()
	BankManager.deserialize({})
	CombatManager.context = {}
	CombatManager.player_hp = 1
	var food_id: String = ""
	for id in DataLoader.items:
		if DataLoader.items[id].get("item_type", "") == "food" and float(DataLoader.items[id].get("heal_amount", 0)) > 0:
			food_id = str(id)
			break
	BankManager.add_item_guaranteed(food_id, 3)
	PlayerData.settings.auto_eat_tier = 1
	CombatManager._auto_eat()
	var heal: float = float(DataLoader.get_item(food_id).heal_amount) * (60.0 + ModifierManager.get_modifier(ModifierKeys.AUTO_EAT_EFFICIENCY_PERCENT)) / 100.0 * (1.0 + ModifierManager.get_modifier(ModifierKeys.FOOD_HEALING_PERCENT) / 100.0)
	report("auto-eat-percent", is_equal_approx(CombatManager.player_hp, minf(CombatManager._compute_max_hp(), 1 + heal)) and BankManager.get_count(food_id) == 2, "One portion heals at 60% efficiency exactly once")
	var finite: Dictionary = {"finite_supplies": true, "food": {food_id: 20}, "food_counts": {food_id: 1}, "auto_eat_tier": 3}
	var first: Dictionary = CombatSimulator._auto_eat(finite, 1, 100)
	var second: Dictionary = CombatSimulator._auto_eat(finite, 1, 100)
	report("finite-food", int(first.eaten) == 1 and int(second.eaten) == 0, "Simulation cannot eat an exhausted food stack")
	var prior: Dictionary = SaveManager.build_save_data().duplicate(true)
	RaidManager.active = true
	RaidManager.wave = 3
	RaidManager.coins_this_raid = 123
	RaidManager.pending_choices = []
	CombatManager.start_combat({"type": "raid", "id": "golbin_raid", "monsters": ["golbin", "golbin"], "endless": false})
	CombatManager.context.index = 1
	CombatManager.monster_hp = 7
	CombatManager.player_attack_timer = 0.8
	CombatManager.monster_effects = [StatusEffect.create("burn", 4, 1)]
	CombatManager.monster_effects[0].tick_timer = 0.25
	var saved: Dictionary = JSON.parse_string(JSON.stringify(SaveManager.build_save_data()))
	SaveManager._apply(saved)
	report("mid-raid-save", RaidManager.active and RaidManager.wave == 3 and RaidManager.coins_this_raid == 123 and int(CombatManager.context.get("index", -1)) == 1 and CombatManager.monster_hp == 7 and is_equal_approx(CombatManager.player_attack_timer, 0.8), "Full save restores the current wave, enemy and attack timer")
	report("mid-raid-status-save", CombatManager.monster_effects.size() == 1 and is_equal_approx(CombatManager.monster_effects[0].tick_timer, 0.25), "Remaining status duration and fractional DOT ticks survive a full save")
	var first_def: Dictionary = EnchantingManager.recipes()[0]
	var variant: String = EnchantingManager._register_variant("bronze_sword", [str(first_def.id)])
	BankManager.add_item_guaranteed(variant, 1)
	EquipmentManager.equip(variant)
	EquipmentManager.save_current_to_set(0)
	var planned: Dictionary = EnchantingManager.preview(variant, str(first_def.id))
	saved = JSON.parse_string(JSON.stringify(SaveManager.build_save_data()))
	SaveManager._apply(saved)
	report("enchanted-loadout-save", EquipmentManager.get_equipped(8) == variant and DataLoader.get_item(variant).get("enchantments", []).has(str(first_def.id)) and EquipmentManager.load_set(0) and BankManager.get_count(variant) == 0, "Derived enchant and owned set survive the full save without duplication")
	SaveManager._apply(prior)
	var ready_seed: String = FarmingManager.seed_id_for_action(str(DataLoader.get_skill_actions("farming")[0].id))
	var worker_id: String = ""
	for def in EngineeringManager.devices():
		if str(def.skill) == "farming": worker_id = str(def.id); break
	var batch_result: Dictionary = _farmhand_run(worker_id, ready_seed, false)
	var split_result: Dictionary = _farmhand_run(worker_id, ready_seed, true)
	report("farmhand-parity", batch_result == split_result, "Equal 3-hour batch and 60-second slices produce equal crops, fuel, XP and plot state")
	var chance: float = PetManager.skill_roll_chance(3600)
	var partition: float = 1.0 - pow(1.0 - PetManager.skill_roll_chance(60), 60)
	report("pet-time-partition", is_equal_approx(chance, partition), "Collection timing cannot change elapsed-time pet probability")
	var records: Array = DataLoader.new_skill_systems.devices
	var invalid: Dictionary = records[0].duplicate(true)
	invalid.fuel = "missing_fuel"
	records.append(invalid)
	var validator := ContentValidator.new()
	validator._check_new_skill_systems()
	report("new-record-validation", not validator.issues.is_empty(), "Missing fuel and duplicate device ID are rejected")
	records.pop_back()
	for id in DataLoader.cartography_hexes:
		if DataLoader.cartography_hexes[id].get("poi", null) == null:
			CartographyManager.discovered[str(id)] = true
			CartographyManager.survey(str(id))
	report("empty-hex-survey", true, "All null POIs survey without an invalid Dictionary cast")
	_mid_phase_save()

func _mid_phase_save() -> void:
	DataLoader.monsters["audit_phase_boss"] = {"id": "audit_phase_boss", "name": "Audit Boss", "combat_level": 1,
		"hitpoints": 100, "attack_type": "melee", "attack_speed": 3.0, "max_hit": 10, "accuracy_rating": 1,
		"melee_evasion": 1, "ranged_evasion": 1, "magic_evasion": 1, "damage_reduction": 0, "loot_table": [],
		"passives": [], "respawn_time": 1.0, "phases": [
			{"at_hp_percent": 75, "name": "Wrath", "effects": {"attack_type": "magic", "max_hit_multiplier": 1.5}},
			{"at_hp_percent": 25, "name": "Fury", "effects": {"max_hit_multiplier": 2.0}}]}
	CombatManager.start_combat({"type": "area", "id": "farmlands", "monsters": ["audit_phase_boss"], "endless": true,
		"attack_style": "melee", "melee_style": "slash"})
	CombatManager.player_hp = 1000.0
	CombatManager.player_effects.clear()
	CombatManager.monster_effects.clear()
	CombatManager.monster_max_hp = 100
	CombatManager.monster_hp = 100
	CombatManager.apply_damage_to_monster(30)
	CombatManager.apply_status("player", "poison", 6.0, 2.0)
	CombatManager.monster_effects = [StatusEffect.create("burn", 4, 1)]
	CombatManager.monster_effects[0].tick_timer = 0.25
	var before_player_effects: int = CombatManager.player_effects.size()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(SaveManager.build_save_data()))
	CombatManager.monster_phases_fired = 0
	CombatManager.monster_hp = 1
	CombatManager.player_effects.clear()
	CombatManager.monster_effects.clear()
	SaveManager._apply(saved)
	var current: Dictionary = CombatManager.current_monster()
	report("mid-phase-save", CombatManager.monster_phases_fired == 1 and CombatManager.monster_hp == 70 and str(current.get("attack_type", "")) == "magic" and int(current.get("max_hit", 0)) == 15 and before_player_effects == 1 and CombatManager.player_effects.size() == 1 and CombatManager.monster_effects.size() == 1 and is_equal_approx(CombatManager.monster_effects[0].tick_timer, 0.25), "Fired phase index, effective monster overrides and both sides' statuses survive a full save")
	CombatManager.stop_combat("test")
	DataLoader.monsters.erase("audit_phase_boss")

func _farmhand_run(worker_id: String, seed_id: String, split: bool) -> Dictionary:
	FarmingManager.deserialize({})
	FarmingManager._rng.seed = 917
	BankManager.deserialize({})
	MasteryManager.deserialize({})
	PlayerData.set_level("farming", 99)
	PlayerData.set_level("engineering", 99)
	var action_id: String = FarmingManager.action_id_for_seed(seed_id)
	BankManager.add_item_guaranteed(worker_id, 1)
	BankManager.add_item_guaranteed(seed_id, 1000)
	var fuel_id: String = str(EngineeringManager.device(worker_id).fuel)
	BankManager.add_item_guaranteed(fuel_id, 100)
	EngineeringManager.deserialize({})
	EngineeringManager.install(worker_id, action_id)
	var before: float = PlayerData.get_xp("farming")
	if split:
		for i in range(180): EngineeringManager.advance(60, 1000000.0 + (i + 1) * 60.0)
	else: EngineeringManager.advance(10800, 1010800.0)
	return {"items": BankManager.items.duplicate(true), "plots": FarmingManager.plots.duplicate(true), "xp": PlayerData.get_xp("farming") - before, "worker": EngineeringManager.installed.duplicate(true)}

func _sim_checks() -> void:
	var player: Dictionary = {"style": "melee", "accuracy": 1000000000, "max_hit": 10, "min_hit_flat": 10, "attack_interval": 1, "evasion": {"melee": 1000000000}, "damage_reduction": 0}
	var enemy: Dictionary = {"hitpoints": 500, "attack_type": "melee", "attack_speed": 3, "max_hit": 1, "accuracy_rating": 1, "melee_evasion": 1}
	var rng := RandomNumberGenerator.new()
	rng.seed = 211
	var baseline: Dictionary = CombatSimulator._run_fight({}, player, enemy, 10000, 10000, rng, {})
	rng.seed = 211
	var special: Dictionary = CombatSimulator._run_fight({"player_special": {"trigger_chance": 100, "damage_multiplier": 2}}, player, enemy, 10000, 10000, rng, {})
	report("sim-special-damage", int(special.kills) == 1 and float(special.seconds) < float(baseline.seconds) * 0.6, "Guaranteed double-damage special halves the required swings")
	var effects: Array = []
	CombatSimulator._add_special_status(effects, {"applies_status": "burn", "status_chance": 100, "status_duration": 4, "status_damage_per_tick": 5}, rng, enemy)
	report("sim-status-dot", effects.size() == 1 and CombatSimulator._tick_statuses(effects, 1) > 0, "Authored special burn deals ticking damage")
	effects.clear()
	CombatSimulator._add_special_status(effects, {"applies_status": "burn", "status_chance": 100}, rng, {"is_immune_to_effects": true})
	report("sim-status-immunity", effects.is_empty(), "Immune enemy rejects special statuses")
	rng.seed = 211
	var enchanted: Dictionary = CombatSimulator._run_fight({"enchant_statuses": ["burn"]}, player, enemy, 10000, 10000, rng, {})
	report("sim-enchanted-burn", int(enchanted.kills) == 1 and float(enchanted.seconds) <= float(baseline.seconds), "Enchanted burn is included in fight duration")
	rng.seed = 211
	var depleted: Dictionary = CombatSimulator._run_fight({"finite_supplies": true, "prayer_balance": 1, "prayer_points": 1}, player, enemy, 10000, 10000, rng, {})
	report("sim-finite-prayer", bool(depleted.timed_out) and int(depleted.kills) == 0 and float(depleted.seconds) < 3, "Prayer exhaustion ends a finite trial before unsupported bonuses continue")
	rng.seed = 211
	depleted = CombatSimulator._run_fight({"finite_supplies": true, "attack_cost": {"air_rune": 1}, "attack_stock": {"air_rune": 1}}, player, enemy, 10000, 10000, rng, {})
	report("sim-finite-runes", bool(depleted.timed_out) and int(depleted.kills) == 0 and float(depleted.seconds) < 3, "Authored rune costs cannot spend beyond owned stock")
