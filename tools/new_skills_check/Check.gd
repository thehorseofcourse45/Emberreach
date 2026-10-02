extends Node
const Support = preload("res://scripts/tests/TestSupport.gd")
const Systems = preload("res://scripts/ui/panels/NewSkillSystems.gd")
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	GameManager.cli_mode = true
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("NEW SKILLS FAIL: " + label)

func reset() -> void:
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	PlayerData.gp = 1000000000.0
	BankManager.purchased_slots = 2000

func _run() -> void:
	var files: Dictionary = Support.backup_save_files()
	var state: Dictionary = SaveManager.build_save_data()
	var paused: bool = GameManager.is_paused
	SimulationMode.begin()
	_test_actions()
	_test_ranch()
	_test_research()
	_test_workers()
	_test_passive_potions()
	_test_enchanting()
	_test_dreams()
	_test_offline_allocation()
	_test_persistence()
	await _test_ui()
	Support.restore_snapshot(state, files)
	GameManager.is_paused = paused
	SimulationMode.end()
	check(Support.backup_save_files() == files, "player save files restored byte-for-byte")
	print("NEW SKILLS RESULT: %d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_actions() -> void:
	for skill in ["inscription", "engineering", "enchanting"]:
		for action in DataLoader.get_skill_actions(skill):
			reset()
			PlayerData.set_level(skill, int(action.level_required))
			if action.has("requires_research"):
				InscriptionManager.researched[str(action.requires_research)] = true
			for id in (action.get("input_items", {}) as Dictionary):
				BankManager.add_item_guaranteed(str(id), int(action.input_items[id]) * 10)
			var before: float = PlayerData.get_xp(skill)
			check(GameManager.request_skill_action(skill, str(action.id), 1), "%s/%s starts" % [skill, action.id])
			SkillManager.tick(SkillManager.current_interval + 0.001, false)
			check(SkillManager.total_action_count == 1 and not SkillManager.running, "%s/%s completes once" % [skill, action.id])
			check(PlayerData.get_xp(skill) > before, "%s/%s grants XP" % [skill, action.id])
			if action.has("quality_product"):
				var total: int = 0
				for quality in ["faded", "inked", "illuminated"]:
					total += BankManager.get_count(str(action.quality_product) + "_" + quality)
				check(total >= 1, "scribing creates a valid quality product")
			else:
				for id in (action.get("output_items", {}) as Dictionary):
					check(BankManager.get_count(str(id)) >= int(action.output_items[id]), "craft output exists: " + str(id))

func _test_ranch() -> void:
	reset()
	check(not SkillManager.can_perform("ranching", "raise_hen"), "Ranching cannot farm XP from active stock actions")
	check(RanchingManager.build_pen(), "first pen builds")
	check(not RanchingManager.build_pen(), "second pen respects its level gate")
	BankManager.add_item_guaranteed("ranch_hen", 2)
	BankManager.add_item_guaranteed("ranch_feed", 100)
	check(RanchingManager.stock(0, "hen") and RanchingManager.stock(0, "hen"), "pair can be stocked")
	check(not RanchingManager.stock(0, "hen"), "pen holds at most two")
	check(RanchingManager.feed_pen(0, 100), "feed is stocked")
	var before: float = PlayerData.get_xp("ranching")
	RanchingManager.advance(7200.0)
	check(PlayerData.get_xp("ranching") == before, "passive produce waits for collection XP")
	check(int(RanchingManager.pens[0].cycles) == 1, "fed pen produces one two-hour cycle")
	check(RanchingManager.collect(0), "produce collects")
	check(BankManager.get_count("ranch_egg") == 2 and BankManager.get_count("ranch_manure") == 2, "two animals give produce and manure")
	check(PlayerData.get_xp("ranching") > before, "collection grants XP")
	check(not RanchingManager.collect(0), "same cycle cannot be collected twice")
	check(FarmingManager.apply_manure(0), "manure applies to empty plot")
	check(not FarmingManager.apply_manure(0), "manure cannot stack on same plot")
	var serialized: Dictionary = RanchingManager.serialize().duplicate(true)
	RanchingManager.deserialize(serialized)
	check(RanchingManager.serialize() == serialized, "ranch timers and feed survive round trip")
	RanchingManager.pens[0].feed = 0.0
	RanchingManager.advance(86400.0)
	check(is_equal_approx(float(RanchingManager.pens[0].happiness), 25.0), "hungry animals floor at 25%")
	check(RanchingManager.retire(0) and int(RanchingManager.pens[0].animals) == 1, "retirement removes one animal")
	check(BankManager.get_count("ranch_meat") > 0, "retirement supplies Cooking meat")
	BankManager.add_item_guaranteed("garum_herb", 1)
	check(RanchingManager.crop_feed("garum_herb", 1) and not RanchingManager.crop_feed("coal", 1), "feed uses Farming crops only")

func _test_research() -> void:
	reset()
	BankManager.add_item_guaranteed("scribe_paper", 100)
	BankManager.add_item_guaranteed("scribe_ink", 100)
	BankManager.add_item_guaranteed("rune_essence", 100)
	check(not SkillManager.can_perform("inscription", "scribe_minor_haste"), "unresearched recipe is locked")
	check(GameManager.request_skill_action("inscription", "research_minor_haste"), "research begins")
	SkillManager.tick(301.0, false)
	check(InscriptionManager.researched.has("minor_haste") and not SkillManager.running, "research unlocks recipe and stops after one completion")
	check(not SkillManager.can_perform("inscription", "research_minor_haste"), "research cannot repeat for XP")
	check(SkillManager.can_perform("inscription", "scribe_minor_haste"), "researched crafting unlocks")
	BankManager.add_item_guaranteed("scribe_minor_haste_inked", 1)
	check(InscriptionManager.use_text("scribe_minor_haste_inked", "woodcutting"), "haste scroll is usable")
	check(ModifierManager.get_interval("woodcutting", 10.0) < 10.0, "haste affects live interval")
	InscriptionManager.advance(3601.0)
	check(is_equal_approx(ModifierManager.get_interval("woodcutting", 10.0), 10.0), "haste expires")
	BankManager.add_item_guaranteed("scribe_xp_tome_1_inked", 1)
	var before: float = PlayerData.get_xp("woodcutting")
	var amount: float = float(DataLoader.get_item("scribe_xp_tome_1_inked").scribe_amount)
	check(InscriptionManager.use_text("scribe_xp_tome_1_inked", "woodcutting") and PlayerData.get_xp("woodcutting") == before + amount, "XP tome pays its selected skill")
	BankManager.add_item_guaranteed("scribe_doubling_inked", 1)
	check(InscriptionManager.use_text("scribe_doubling_inked", "woodcutting") and ModifierManager.get_doubling_chance("woodcutting") >= 10.0, "doubling scroll reaches the actual reward calculation")

func _test_workers() -> void:
	reset()
	BankManager.add_item_guaranteed("device_lumberjack", 1)
	BankManager.add_item_guaranteed("coal", 5)
	check(EngineeringManager.install("device_lumberjack", "normal_tree"), "worker installs with valid work")
	ModifierManager.register("test:worker_bonus", {"woodcutting_skill_xp_percent": 900, "woodcutting_doubling_percent": 100}, "test", "Ignored worker bonuses")
	EngineeringManager.advance(30.0)
	check(BankManager.get_count("coal") == 0, "hourly fuel is prepaid")
	check(BankManager.get_count("normal_log") == 4 and PlayerData.get_xp("woodcutting") == 48.0, "40% worker ignores player XP/doubling bonuses")
	EngineeringManager.advance(3570.0)
	var xp: float = PlayerData.get_xp("woodcutting")
	EngineeringManager.advance(3600.0)
	check(PlayerData.get_xp("woodcutting") == xp and str(EngineeringManager.installed[0].status) == "Out of fuel", "fuel exhaustion stops all production")
	ModifierManager.unregister("test:worker_bonus")
	check(EngineeringManager.uninstall(0) and BankManager.get_count("device_lumberjack") == 1, "uninstall returns owned device")

func _test_passive_potions() -> void:
	reset()
	BankManager.add_item_guaranteed("potion_ranching", 1)
	PotionManager.use_potion("potion_ranching")
	PotionManager.consume_charge("woodcutting")
	check(PlayerData.potion_charges == 100, "main actions do not burn passive Ranching potion charges")
	PotionManager.consume_charge("ranching:collection")
	check(PlayerData.potion_charges == 99, "Ranching potion charges pay per collection")
	BankManager.add_item_guaranteed("potion_engineering", 1)
	PotionManager.use_potion("potion_engineering")
	PotionManager.consume_charge("engineering")
	check(PlayerData.potion_charges == 100, "device crafting does not consume fuel-potion charges")
	BankManager.add_item_guaranteed("device_lumberjack", 1)
	BankManager.add_item_guaranteed("coal", 10)
	EngineeringManager.install("device_lumberjack", "normal_tree")
	EngineeringManager.advance(30.0)
	check(PlayerData.potion_charges == 99, "worker consumes a potion charge once per fuel purchase")

func _test_enchanting() -> void:
	reset()
	BankManager.add_item_guaranteed("bronze_sword", 3)
	BankManager.add_item_guaranteed("enchant_martial_essence", 100)
	BankManager.add_item_guaranteed("rune_essence", 100)
	check(EnchantingManager.begin_enchant("bronze_sword", "might_1"), "weapon enchant starts")
	SkillManager.tick(6.0, false)
	var enchanted: String = ""
	for id in BankManager.items:
		if str(id).begins_with("enchanted__bronze_sword"):
			enchanted = str(id)
	check(enchanted != "" and BankManager.get_count("bronze_sword") == 2, "enchant splits exactly one item from original stack")
	check(not SkillManager.running and EnchantingManager.pending.is_empty(), "enchant job ends once")
	check(BankManager.get_count("enchant_martial_essence") == 90 and BankManager.get_count("rune_essence") == 95, "enchantment materials are consumed")
	if enchanted != "":
		check(EquipmentManager.equip(enchanted), "enchanted gear equips")
		check(ModifierManager.get_modifier("melee_max_hit_percent") >= 2.0, "equipped enchantment affects real modifiers")
		check(DataLoader.get_item("bronze_sword").get("passive_modifiers", {}).is_empty(), "ordinary copies keep ordinary stats")
		EquipmentManager.unequip(8)
		check(EnchantingManager.begin_disenchant(enchanted), "enchanted piece recycles")
		SkillManager.tick(6.0, false)
		check(BankManager.get_count(enchanted) == 0 and BankManager.get_count("enchant_martial_essence") >= 97, "recycling removes gear and partially refunds essence")
	check(EnchantingManager.can_enchant("bronze_sword", "ward_1") != "", "armor-only enchant cannot attach to weapon")
	BankManager.set_protected("bronze_sword", true)
	check(not EnchantingManager.begin_disenchant("bronze_sword"), "protected gear cannot be destroyed")

func _test_dreams() -> void:
	reset()
	check(not SkillManager.can_perform("dreamwalking", "meadow"), "Dreamwalking has no online action XP")
	check(DreamwalkingManager.select("meadow", 0.5), "offline allocation selects")
	check(not DreamwalkingManager.select("crown", 1.0), "locked dreamscape cannot select")
	var before: float = PlayerData.get_xp("dreamwalking")
	var result: Dictionary = DreamwalkingManager.advance_offline(3600.0)
	check(PlayerData.get_xp("dreamwalking") > before and int(result.essence) > 0, "offline dream gives XP and Essence")
	check(float(DreamwalkingManager.advance_offline(-1.0).seconds) == 0.0, "negative time gives nothing")
	BankManager.add_item_guaranteed("potion_dreamwalking", 1)
	check(PotionManager.use_potion("potion_dreamwalking") and DreamwalkingManager.next_essence_bonus == 15.0, "draught is reserved for next offline session")
	DreamwalkingManager.advance_offline(3600.0)
	check(DreamwalkingManager.next_essence_bonus == 0.0, "reserved draught is spent once")
	BankManager.add_item_guaranteed("dream_essence", 1000)
	check(DreamwalkingManager.buy("insight") and ModifierManager.get_skill_xp_multiplier("woodcutting") >= 1.1, "bazaar waking XP buff works")
	DreamwalkingManager.events = [{"kind": "garden", "text": "A garden"}]
	check(DreamwalkingManager.resolve_event(0, true) and BankManager.get_count("ranch_manure") == 5, "dream event choice produces actual reward")
	check(not DreamwalkingManager.resolve_event(0, true), "dream event cannot replay")

func _test_offline_allocation() -> void:
	reset()
	DreamwalkingManager.select("meadow", 1.0)
	TownshipManager.buildings["township_building_homes"] = 1
	InscriptionManager.activate_buff("short_dream_buff", {"global_skill_xp_percent": 10}, 60.0)
	var summary: Dictionary = OfflineProgression.empty_summary()
	summary.elapsed_seconds = 3600.0
	OfflineProgression._begin_job(summary, Time.get_unix_time_from_system())
	while OfflineProgression.is_running:
		OfflineProgression._step_chunk()
	var result: Dictionary = OfflineProgression.last_summary()
	check(float(result.dreamwalking.seconds) == 3600.0 and float(result.processed_seconds) == 3600.0, "100% dream allocation processes all assigned hours")
	check(PlayerData.get_xp("township") == 10000.0, "Settlement still ticks while all offline time is allocated to dreams")
	check(not InscriptionManager.buffs.has("short_dream_buff"), "short buffs expire during a full dream allocation")
	var before: float = PlayerData.get_xp("dreamwalking")
	OfflineProgression.run_on_load()
	check(PlayerData.get_xp("dreamwalking") == before and not OfflineProgression.is_running, "same offline marker cannot pay dreams twice")
	SimulationMode.begin()
	reset()
	DreamwalkingManager.select("meadow", 0.5)
	GameManager.request_skill_action("woodcutting", "normal_tree")
	summary = OfflineProgression.empty_summary()
	summary.elapsed_seconds = 60.0
	OfflineProgression._begin_job(summary, Time.get_unix_time_from_system())
	while OfflineProgression.is_running:
		OfflineProgression._step_chunk()
	check(PlayerData.get_xp("woodcutting") == 120.0 and PlayerData.get_xp("dreamwalking") > 0.0, "50% split grants 30 waking seconds and 30 dream seconds")
	SimulationMode.begin()

func _test_persistence() -> void:
	reset()
	PlayerData.set_level("enchanting", 120)
	BankManager.add_item_guaranteed("bronze_sword", 1)
	BankManager.add_item_guaranteed("enchant_martial_essence", 100)
	BankManager.add_item_guaranteed("rune_essence", 100)
	EnchantingManager.begin_enchant("bronze_sword", "might_1")
	SkillManager.tick(6.0, false)
	InscriptionManager.researched["minor_haste"] = true
	DreamwalkingManager.select("meadow", 0.5)
	InscriptionManager.activate_buff("test_roundtrip", {"global_skill_xp_percent": 10}, 1000.0)
	var save: Dictionary = JSON.parse_string(JSON.stringify(SaveManager.build_save_data()))
	SaveManager._apply(save)
	check(InscriptionManager.researched.has("minor_haste") and DreamwalkingManager.share == 0.5, "new skill progress survives JSON save round trip")
	check(InscriptionManager.buffs.has("test_roundtrip"), "timed buffs restore")
	var found: bool = false
	for id in BankManager.items:
		if str(id).begins_with("enchanted__"):
			found = true
			check(DataLoader.get_item(str(id)).has("enchantments"), "derived equipment restores before bank lookup")
	check(found, "enchanted inventory survives save round trip")
	for id in ["ranching", "inscription", "engineering", "enchanting", "dreamwalking"]:
		var texture: Texture2D = AssetRegistry.skill_icon(id)
		check(texture.get_width() == 32 and texture.get_height() == 32, id + " sprite is 32x32")
		check(texture.get_image().get_pixel(0, 0).a == 0.0, id + " sprite has transparent background")

	# Internal sprites must resolve to real art, not badges or generated placeholders.
	for id in ["border_collie_mark", "border_collie_tablet", "clockwork_frame", "clockwork_gear", "clockwork_spring", "device_angler", "device_arcane_miner", "device_celestial_angler", "device_cook", "device_farmer", "device_looter", "device_lumberjack", "device_miner", "device_stoker", "dream_essence", "dreamwalking_skillcape", "enchant_arcane_essence", "enchant_catalyst", "enchant_martial_essence", "enchant_verdant_essence", "enchant_warding_essence", "enchanting_skillcape", "engineering_skillcape", "equipped_tome_apprentice_faded", "equipped_tome_apprentice_illuminated", "equipped_tome_apprentice_inked", "equipped_tome_grand_tome_faded", "equipped_tome_grand_tome_illuminated", "equipped_tome_grand_tome_inked", "equipped_tome_sage_faded", "equipped_tome_sage_illuminated", "equipped_tome_sage_inked", "equipped_tome_scholar_faded", "equipped_tome_scholar_illuminated", "equipped_tome_scholar_inked", "golden_hen_stock", "inscription_skillcape", "mooncalf_stock", "potion_dreamwalking", "potion_enchanting", "potion_engineering", "potion_inscription", "potion_ranching", "ranch_antler", "ranch_boar", "ranch_celestial_dragon", "ranch_cooked_meat", "ranch_cow", "ranch_dragon", "ranch_egg", "ranch_ember", "ranch_feed", "ranch_griffin", "ranch_hen", "ranch_manure", "ranch_meat", "ranch_milk", "ranch_moonstag", "ranch_plume", "ranch_scale", "ranch_sheep", "ranch_star_scale", "ranch_tusk", "ranch_wool", "ranch_wyvern", "ranching_skillcape", "raw_squid", "sandman_mark", "sandman_tablet", "scribe_apprentice_faded", "scribe_apprentice_illuminated", "scribe_apprentice_inked", "scribe_blue_ink", "scribe_celestial_ink", "scribe_doubling_faded", "scribe_doubling_illuminated", "scribe_doubling_inked", "scribe_grand_tome_faded", "scribe_grand_tome_illuminated", "scribe_grand_tome_inked", "scribe_ink", "scribe_mastery_faded", "scribe_mastery_illuminated", "scribe_mastery_inked", "scribe_minor_haste_faded", "scribe_minor_haste_illuminated", "scribe_minor_haste_inked", "scribe_mythic_haste_faded", "scribe_mythic_haste_illuminated", "scribe_mythic_haste_inked", "scribe_paper", "scribe_sage_faded", "scribe_sage_illuminated", "scribe_sage_inked", "scribe_scholar_faded", "scribe_scholar_illuminated", "scribe_scholar_inked", "scribe_time_faded", "scribe_time_illuminated", "scribe_time_inked", "scribe_xp_tome_1_faded", "scribe_xp_tome_1_illuminated", "scribe_xp_tome_1_inked", "scribe_xp_tome_2_faded", "scribe_xp_tome_2_illuminated", "scribe_xp_tome_2_inked"]:
		check(ResourceLoader.exists("res://assets/icons/items/%s.png" % id), id + " internal art exists")
		var art: Texture2D = AssetRegistry.item_icon(id)
		check(art.get_width() == 32 and art.get_height() == 32 and art.get_image().get_pixel(0, 0).a == 0.0, id + " internal art is transparent 32x32")
	for id in ["meadow", "shore", "wood", "library", "citadel", "rift", "void", "astral", "crown"]:
		check(ResourceLoader.exists("res://assets/icons/dreams/%s.png" % id), id + " selector art exists")
	for id in ["might_1", "might_2", "might_3", "might_4", "might_5", "precision_1", "precision_2", "precision_3", "precision_4", "precision_5", "ward_1", "ward_2", "ward_3", "ward_4", "ward_5", "scholar_1", "scholar_2", "scholar_3", "scholar_4", "scholar_5", "fortune_1", "fortune_2", "fortune_3", "fortune_4", "fortune_5", "volcan", "tide"]:
		check(ResourceLoader.exists("res://assets/icons/enchants/%s.png" % id), id + " selector art exists")

func _test_ui() -> void:
	reset()
	PlayerData.set_level("ranching", 120)
	PlayerData.set_level("engineering", 120)
	RanchingManager.build_pen()
	BankManager.add_item_guaranteed("ranch_hen", 1)
	BankManager.add_item_guaranteed("ranch_feed", 100)
	RanchingManager.stock(0, "hen")
	RanchingManager.feed_pen(0, 100)
	BankManager.add_item_guaranteed("device_lumberjack", 1)
	BankManager.add_item_guaranteed("coal", 10)
	EngineeringManager.install("device_lumberjack", "normal_tree")
	BankManager.add_item_guaranteed("device_angler", 1)
	BankManager.add_item_guaranteed("bronze_sword", 1)
	BankManager.add_item_guaranteed("scribe_xp_tome_1_inked", 1)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.theme = UIStyle.build_theme()
	add_child(layout)
	for skill in ["ranching", "inscription", "engineering", "enchanting", "dreamwalking"]:
		var panel := Systems.new()
		layout.add_child(panel)
		panel.set_skill(skill)
		for width in [420, 1440]:
			get_window().size = Vector2i(width, 900)
			for frame in range(4):
				await get_tree().process_frame
			check(panel.get_combined_minimum_size().x <= width, "%s fits %dpx (%s)" % [skill, width, Support.widest_descendant(panel)])
			if "--render-new-skills" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/new_skills_%d_%s.png" % [width, skill])
		check(panel.get_child_count() > 0, skill + " has usable system controls")
		layout.remove_child(panel)
		panel.queue_free()
	layout.queue_free()
