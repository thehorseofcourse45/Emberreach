extends Node
## Focused end-to-end checks. Run with:
## Godot --headless --path . res://scripts/tests/frontier_expansions_check.tscn

const CraftQualityScript = preload("res://scripts/core/CraftingQuality.gd")

var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", label)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("run")

func run() -> void:
	GameManager.start_new_game("standard")
	check(DataLoader.crafting_quality.size() == 4, "Four crafted-quality tiers loaded")
	check(DataLoader.crafting_affixes.size() == 4, "Four crafting affixes loaded")
	check(DataLoader.settlement_specializations.size() == 4, "Four settlement paths loaded")
	var base: Dictionary = DataLoader.get_item("bronze_platebody")
	var fine: Dictionary = DataLoader.get_item("bronze_platebody__quality_fine")
	var legendary: Dictionary = DataLoader.get_item("bronze_platebody__quality_legendary")
	check(not base.is_empty() and str(fine.get("name", "")).begins_with("Fine"), "Variant definitions resolve from normal gear")
	check(int(legendary.get("equipment_stats", {}).get("melee_defence", 0)) > int(base.get("equipment_stats", {}).get("melee_defence", 0)), "High quality increases worn stats")
	check(DataLoader.get_item("bronze_platebody__quality_unknown").is_empty(), "Unknown variant rejected")
	var affixed: Dictionary = DataLoader.get_item("bronze_platebody__quality_legendary__affix_fortunate")
	check(float(affixed.get("passive_modifiers", {}).get("global_gp_percent", 0.0)) >= 2.0, "Craft affixes add real modifiers")
	check(not Goals.sources_for_item("bronze_platebody__affix_warded").is_empty(), "Affix-only gear has acquisition routes")
	var rng := RandomNumberGenerator.new()
	rng.seed = 314159
	var valid_rolls: bool = true
	var premium_rolls: int = 0
	for _i in range(500):
		var result_id: String = CraftQualityScript.roll("bronze_platebody", 120, rng, DataLoader.items, DataLoader.crafting_quality, DataLoader.crafting_affixes)
		valid_rolls = valid_rolls and not DataLoader.get_item(result_id).is_empty()
		if result_id != "bronze_platebody":
			premium_rolls += 1
	check(valid_rolls and premium_rolls > 0, "Quality and affix rolls always resolve to real equipment")
	var crafted_before: float = PlayerData.get_stat("items_crafted", "bronze_platebody")
	ProgressTracker.record_item_crafted("bronze_platebody__quality_fine__affix_fortunate", 1)
	check(PlayerData.get_stat("items_crafted", "bronze_platebody") == crafted_before + 1.0, "Quality-crafted gear counts toward base equipment contracts")
	for skill_id in DataLoader.get_skill_ids():
		PlayerData.set_level(skill_id, 120)
	BankManager.deserialize({"purchased_slots": 200})
	BankManager.add_item("bronze_platebody__quality_legendary", 1)
	check(EquipmentManager.equip("bronze_platebody__quality_legendary"), "Quality gear can be equipped")
	var saved_gear: Dictionary = EquipmentManager.serialize().duplicate(true)
	EquipmentManager.deserialize(saved_gear)
	check(EquipmentManager.is_equipped("bronze_platebody__quality_legendary"), "Equipment quality survives serialization")
	check(EquipmentManager.unequip(int(base.get("equipment_slot", -1))), "Quality gear can be unequipped")
	check(BankManager.get_count("bronze_platebody__quality_legendary") == 1, "Unequipping returns the same quality variant")
	BankManager.add_item("bronze_platebody__affix_fortunate", 1)
	check(EquipmentManager.equip("bronze_platebody__affix_fortunate"), "Affix-only gear can be equipped")
	check(ModifierManager.get_modifier("global_gp_percent") >= 2.0, "Affix applies passive gear bonuses")
	EquipmentManager.unequip(int(base.get("equipment_slot", -1)))
	var saved_bank: Dictionary = BankManager.serialize().duplicate(true)
	BankManager.deserialize(saved_bank)
	check(BankManager.get_count("bronze_platebody__quality_legendary") == 1, "Quality stacks survive bank serialization")
	var mining: Dictionary = DataLoader.settlement_specializations["mining_city"]
	TownshipManager.deserialize({"buildings": {"township_building_mine": 1}})
	PlayerData.gp = float(mining.gp_cost) + 10.0
	for resource in mining.store_cost:
		TownshipManager.resources[resource] = float(mining.store_cost[resource])
	var before: float = TownshipManager.production_per_hour("metal")
	check(TownshipManager.choose_specialization("mining_city"), "Paid specialization can be selected")
	check(TownshipManager.specialization == "mining_city", "Selected path persists in manager")
	check(TownshipManager.production_per_hour("metal") > before, "Mining path improves metal production")
	check(not TownshipManager.choose_specialization("mining_city"), "Same path does not charge twice")
	var saved_town: Dictionary = TownshipManager.serialize().duplicate(true)
	TownshipManager.deserialize(saved_town)
	check(TownshipManager.specialization == "mining_city", "Settlement specialization survives save roundtrip")
	TownshipManager.deserialize({})
	check(TownshipManager.specialization == "", "Old saves get neutral specialization")
	# Contracts read fresh authoritative counters, including those recorded offline.
	check(ContractManager.get_offers().size() == 3, "Contract board has three offers")
	check(ContractManager.total_variant_count() == 45, "Contract templates have three difficulty tiers")
	check(FactionManager.all_faction_ids().size() == 3, "Three reputations are available")
	var offers: Array = ContractManager.get_offers()
	var seen_factions: Dictionary = {}
	for index in range(offers.size()):
		var offer: Dictionary = offers[index]
		var objective: Dictionary = offer.get("objective", {})
		var count: int = int(objective.get("required", 1))
		var faction: String = str(offer.get("faction_id", ""))
		check(not seen_factions.has(faction) and FactionManager.all_faction_ids().has(faction), "Each contract belongs to a distinct faction")
		seen_factions[faction] = true
		check(count > 0 and is_zero_approx(float(ContractManager.progress(index).get("current", -1))), "New offers baseline previous lifetime work")
		check(not ContractManager.can_claim(index), "Fresh contract requires new progress")
		check(ContractManager.describe_reward(index).contains("GP") and ContractManager.describe_reward(index).contains("reputation"), "Contract describes its currency and reputation rewards")
		match str(objective.get("kind", "")):
			"gain_item": ProgressTracker.record_item_gained(str(objective.get("item_id", "")), count)
			"craft_item": ProgressTracker.record_item_crafted(str(objective.get("item_id", "")), count)
			"kill_monster":
				for _j in range(count): ProgressTracker.record_kill(str(objective.get("monster_id", "")))
			"complete_dungeon":
				for _j in range(count): ProgressTracker.record_dungeon_clear(str(objective.get("dungeon_id", "")))
			_:
				check(false, "Contract objective has a supported kind: " + str(objective.get("kind", "")))
		check(bool(ContractManager.progress(index).get("satisfied", false)), "Contract progress tracks new work: " + str(offer.get("template_id", "")))
		var old_reputation: int = FactionManager.get_reputation(faction)
		var old_gp: float = PlayerData.gp
		check(ContractManager.claim_contract(index), "Complete contract can be claimed")
		check(FactionManager.get_reputation(faction) == old_reputation + int(offer.get("reputation", 0)), "Reward grants faction reputation once")
		check(is_equal_approx(PlayerData.gp, old_gp + float(offer.get("reward", {}).get("gp", 0))), "Reward grants expected gold")
		var replacement: Dictionary = ContractManager.get_offer(index)
		check(int(replacement.get("serial", 0)) != int(offer.get("serial", 0)) and str(replacement.get("faction_id", "")) == faction, "Claim replaces only its faction's offer with a new serial")
		check(str(replacement.get("template_id", "")) != str(offer.get("template_id", "")), "Replacement chooses another template")
		check(is_zero_approx(float(ContractManager.progress(index).get("current", -1))) and not ContractManager.can_claim(index), "Replacement requires new work from its own baseline")
		check(not ContractManager.claim_contract(index), "Repeated claim cannot duplicate rewards from the replaced slot")
		check(FactionManager.get_reputation(faction) == old_reputation + int(offer.get("reputation", 0)) and is_equal_approx(PlayerData.gp, old_gp + float(offer.get("reward", {}).get("gp", 0))), "Rejected duplicate claim leaves rewards unchanged")
	var saved_contracts: Dictionary = ContractManager.serialize().duplicate(true)
	ContractManager.deserialize(saved_contracts)
	check(ContractManager.serialize() == saved_contracts, "Refreshed contract slots, baselines and serials survive save roundtrip")
	check(not ContractManager.can_claim(0), "New contract cannot be claimed after reloading")
	var saved_factions: Dictionary = FactionManager.serialize().duplicate(true)
	FactionManager.deserialize(saved_factions)
	check(FactionManager.serialize() == saved_factions, "Reputation and allegiance round-trip")
	check(FactionManager.vendor_offers("ledger").size() == 2 and FactionManager.vendor_offers("wardens").size() == 2 and FactionManager.vendor_offers("vanguard").size() == 2, "Each faction offers two exclusive rewards")
	check(FactionManager.select_faction("ledger"), "Pledge to a faction")
	check(FactionManager.vendor_blocker("ledger", "broker_writ") != "", "Vendor reward requires sufficient rank and gold")
	FactionManager.add_reputation("ledger", 500)
	PlayerData.gp = 100000.0
	check(FactionManager.vendor_blocker("ledger", "broker_writ") == "", "Reached rank unlocks faction vendor")
	var vendor_gold: float = PlayerData.gp
	check(FactionManager.purchase_vendor_reward("ledger", "broker_writ"), "Faction reward can be purchased")
	check(PlayerData.gp == vendor_gold - 20000.0 and FactionManager.vendor_purchased("ledger", "broker_writ"), "Faction reward costs gold exactly once")
	check(not FactionManager.purchase_vendor_reward("ledger", "broker_writ"), "Vendor purchase cannot duplicate")
	var ledger_bonus: float = ModifierManager.get_modifier("global_gp_percent")
	check(ledger_bonus >= 3.0, "Purchased faction perk registers gold bonus")
	var saved_vendors: Dictionary = FactionManager.serialize().duplicate(true)
	FactionManager.deserialize(saved_vendors)
	check(FactionManager.vendor_purchased("ledger", "broker_writ"), "Owned faction reward survives load")
	check(FactionManager.select_faction("wardens") and ModifierManager.get_modifier("global_gp_percent") < ledger_bonus, "Switching allegiance disables former faction perks")
	check(FactionManager.select_faction("ledger") and ModifierManager.get_modifier("global_gp_percent") == ledger_bonus, "Returning allegiance reactivates purchased perk")
	PlayerData.gp = 0
	var board_before: Dictionary = ContractManager.serialize().duplicate(true)
	check(ContractManager.get_refresh_cost() > 0, "Board refresh has a positive gold price")
	check(not ContractManager.refresh_board() and board_before == ContractManager.serialize(), "Unaffordable refresh preserves contract board")
	var refresh_cost: int = ContractManager.get_refresh_cost()
	PlayerData.gp = float(refresh_cost) + 1000.0
	var paid_refresh_before: Array = ContractManager.get_offers()
	var gp_before_refresh: float = PlayerData.gp
	check(ContractManager.refresh_board(), "Affordable refresh replaces the whole contract board")
	check(is_equal_approx(PlayerData.gp, gp_before_refresh - float(refresh_cost)), "Refresh charges gold exactly once")
	var paid_refresh_after: Array = ContractManager.get_offers()
	check(paid_refresh_after.size() == paid_refresh_before.size(), "Refresh preserves the faction slot count")
	for index in range(paid_refresh_before.size()):
		var old_offer: Dictionary = paid_refresh_before[index]
		var new_offer: Dictionary = paid_refresh_after[index]
		check(int(new_offer.get("serial", 0)) != int(old_offer.get("serial", 0)) and str(new_offer.get("faction_id", "")) == str(old_offer.get("faction_id", "")), "Paid refresh issues a new serial for the same faction")
		check(str(new_offer.get("template_id", "")) != str(old_offer.get("template_id", "")), "Paid refresh rotates each faction's template")
		check(is_zero_approx(float(ContractManager.progress(index).get("current", -1))) and not ContractManager.can_claim(index), "Paid refresh resets progress baselines")
	var saved_refreshed_board: Dictionary = ContractManager.serialize().duplicate(true)
	ContractManager.deserialize(saved_refreshed_board)
	check(ContractManager.serialize() == saved_refreshed_board, "Paid refresh and serial counter survive save roundtrip")
	# Regional conditions rotate with simulated time and preserve their active effects.
	check(RegionalEventsManager.conditions.size() == 6, "Six regional conditions loaded")
	RegionalEventsManager.deserialize({})
	var region_before: String = RegionalEventsManager.active_id()
	var region_data: Dictionary = RegionalEventsManager.active_event()
	check(RegionalEventsManager.enemy_damage_multiplier(str(region_data.get("region_id", ""))) >= 0.5, "Active event supplies region-specific combat scaling")
	RegionalEventsManager.advance_offline(RegionalEventsManager.PERIOD_SECONDS + 20.0)
	check(RegionalEventsManager.active_id() != region_before and absf(RegionalEventsManager.elapsed_seconds - 20.0) < 0.01, "Offline world event rotation consumes elapsed time")
	var saved_regions: Dictionary = RegionalEventsManager.serialize().duplicate(true)
	RegionalEventsManager.deserialize(saved_regions)
	check(RegionalEventsManager.serialize() == saved_regions, "Regional condition and timer persist")
	# Challenge selections are capped, run with the actual dungeon fight and retain state.
	check(DungeonModifierManager.definitions.size() == 10, "Ten dungeon challenges loaded")
	var quest_panel_script: GDScript = load("res://scripts/ui/panels/QuestsPanel.gd")
	check(quest_panel_script != null and quest_panel_script.can_instantiate(), "Contracts & factions screen compiles")
	if quest_panel_script != null and quest_panel_script.can_instantiate():
		var tasks_panel: Control = quest_panel_script.new()
		add_child(tasks_panel)
		check(tasks_panel._tab_ids.has("contracts"), "Contracts & factions tab appears in Tasks")
		tasks_panel._select_tab("contracts")
		check(tasks_panel._list.get_child_count() >= 6, "Contract and faction cards render")
		tasks_panel.queue_free()
	var combat_panel_script: GDScript = load("res://scripts/ui/panels/CombatPanel.gd")
	check(combat_panel_script != null and combat_panel_script.can_instantiate(), "Dungeon challenges screen compiles")
	DungeonModifierManager.deserialize({})
	check(DungeonModifierManager.toggle("iron_skin") and DungeonModifierManager.toggle("blood_moon") and DungeonModifierManager.toggle("cursed_echo"), "Choose three unique challenge affixes")
	check(not DungeonModifierManager.toggle("sundering"), "Cannot select more than three challenges")
	var snapshot: Dictionary = CombatSimulatorManager.build_snapshot("dungeon", "chicken_coop", "melee", "stab")
	check(float(snapshot.get("challenge_effects", {}).get("enemy_hp_percent", 0)) >= 35.0, "Combat simulator includes selected dungeon affixes")
	var dungeon: Dictionary = DataLoader.get_dungeon("chicken_coop")
	if dungeon.is_empty():
		check(false, "Starter dungeon exists")
	else:
		Quests.deserialize({"claimed": {"expedition_charter": true}})
		var ctx: Dictionary = {"type": "dungeon", "id": "chicken_coop", "monsters": dungeon.get("monsters", [])}
		check(CombatManager.start_combat(ctx), "Challenge dungeon starts")
		check(DungeonModifierManager.active_ids.size() == 3 and DungeonModifierManager.reward_multiplier() > 1.0, "Challenge selection locks and raises reward")
		check(CombatManager.monster_max_hp > int(DataLoader.get_monster(CombatManager.current_monster_id).get("hitpoints", 0)), "Challenge modifiers increase real enemy health")
		check(not DungeonModifierManager.toggle("iron_skin"), "Modifiers cannot change mid-fight")
		var saved_mods: Dictionary = DungeonModifierManager.serialize().duplicate(true)
		DungeonModifierManager.deserialize(saved_mods)
		check(DungeonModifierManager.active_ids.size() == 3, "Active challenge survives serialization")
		CombatManager.stop_combat("test")
		check(DungeonModifierManager.active_ids.is_empty(), "Retreat clears active modifiers")
	print("Frontier expansion check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
