extends Node
var checks := 0
var failures := 0
var plan: Dictionary
const WORK := "C:/Users/TheTaZe/Documents/Codex/2026-09-25/for/work/skills_expansion_192/"

func ok(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", label)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	SaveManager._write_in_progress = true
	call_deferred("run")

func run() -> void:
	plan = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/SkillExpansion192.json"))
	var staged: bool = "--staged" in OS.get_cmdline_user_args()
	if staged:
		DataLoader.skills = JSON.parse_string(FileAccess.get_file_as_string(WORK + "staged/data/skills.json"))
		DataLoader.items = JSON.parse_string(FileAccess.get_file_as_string(WORK + "staged/data/items.json"))
		DataLoader.new_skill_systems = JSON.parse_string(FileAccess.get_file_as_string(WORK + "staged/data/new_skill_systems.json"))
		DataLoader.shop_store = JSON.parse_string(FileAccess.get_file_as_string(WORK + "staged/data/shop_store.json"))
		DataLoader.special_attacks = JSON.parse_string(FileAccess.get_file_as_string(WORK + "staged/data/special_attacks.json"))
		for table in [DataLoader.skills, DataLoader.items, DataLoader.new_skill_systems, DataLoader.shop_store, DataLoader.special_attacks]:
			table.erase("_comment")
		DataLoader._build_indexes()
	var findings: Array = ContentValidator.new().validate_all()
	for finding in findings:
		if str(finding.get("severity", "")) == "error":
			ok(false, "content validation: " + str(finding))
	PlayerData.initialize_new_game()
	BankManager.deserialize({"purchased_slots": 1000})
	ModifierManager._sources.clear()
	ModifierManager._mark_dirty()
	MasteryManager.deserialize({})
	for sid in DataLoader.get_skill_ids():
		PlayerData.set_level(str(sid), 120)
	PlayerData.add_gp(1e12)
	PlayerData.settings.riftkeeping_mode = "safe"
	SkillManager.seed_rng(12345)
	for sid in plan.added:
		ok(plan.added[sid].size() == 12, str(sid) + " gets 12 additions")
		if sid == "ranching":
			continue
		for aid in plan.added[sid]:
			var action: Dictionary = DataLoader.get_action(str(sid), str(aid))
			ok(not action.is_empty(), str(aid) + " resolves")
			for item_id in action.get("input_items", {}):
				BankManager.add_item_guaranteed(str(item_id), int(action.input_items[item_id]) * 20)
			PlayerData.set_level(str(sid), int(action.level_required) - 1)
			ok(not SkillManager.can_perform(str(sid), str(aid)), str(aid) + " level locked")
			PlayerData.set_level(str(sid), 120)
			ok(SkillManager.start_action(str(sid), str(aid)), str(aid) + " starts")
			var result: Dictionary = SkillManager.perform_action()
			ok(bool(result.get("success", false)), str(aid) + " completes")
			ok(MasteryManager.get_xp(str(sid), str(aid)) > 0.0, str(aid) + " earns mastery")
			if sid != "farming":
				ok(float(result.get("xp", 0)) > 0.0, str(aid) + " earns XP")
			for item_id in action.get("output_items", {}):
				var found := false
				for produced_id in result.get("items", {}):
					if str(produced_id) == str(item_id) or str(DataLoader.get_item(str(produced_id)).get("icon_id", "")) == str(item_id):
						found = true
				ok(found, str(aid) + " produces " + str(item_id) + " or its crafted variant")
			SkillManager.stop_action()
			if sid == "farming":
				var seed_id: String = FarmingManager.seed_id_for_action(str(aid))
				var index := -1
				for i in range(FarmingManager.plots.size()):
					if str(FarmingManager.plots[i].seed_id) == seed_id:
						index = i
				ok(index >= 0, str(aid) + " plants correct seed")
				if index >= 0:
					FarmingManager.plots[index].alive = true
					FarmingManager.plots[index].planted_unix = Time.get_unix_time_from_system() - float(FarmingManager.plots[index].grow_seconds) - 1
					var crop_id: String = str(DataLoader.get_item(seed_id).product_item)
					var before: int = BankManager.get_count(crop_id)
					ok(not FarmingManager.harvest(index).is_empty(), str(aid) + " harvests")
					ok(BankManager.get_count(crop_id) > before, str(aid) + " pays crops")
				ok(DataLoader.shop_store.has("store_" + seed_id), str(aid) + " seeds obtainable")
			if sid == "herblore":
				var potion_id: String = str(action.output_items.keys()[0])
				ok(PotionManager.use_potion(potion_id), potion_id + " activates")
				var charges: int = PlayerData.potion_charges
				PotionManager.consume_charge(str(DataLoader.get_item(potion_id).get("charge_scope", "herblore")))
				ok(PlayerData.potion_charges == charges - 1, potion_id + " charge consumed in intended scope")
				PotionManager.clear()
			if sid == "spellweaving":
				ok(ArcaneSkills.learned(action), str(aid) + " learned permanently")
				EquipmentManager.slots[8] = "fire_staff"
				PlayerData.settings.spellweaving_pattern = aid
				ok(not ArcaneSkills.active_pattern("magic").is_empty(), str(aid) + " casts")
				ok(not ArcaneSkills.special("magic").is_empty(), str(aid) + " special resolves")
			if sid == "archaeology":
				ok(int(ArchaeologyManager.excavated.get(aid, 0)) > 0, str(aid) + " excavation tracked")
	for aid in plan.get("supporting", {}).get("cooking", []):
		var action: Dictionary = DataLoader.get_action("cooking", str(aid))
		ok(not action.is_empty(), str(aid) + " supporting meal resolves")
		for item_id in action.get("input_items", {}):
			BankManager.add_item_guaranteed(str(item_id), int(action.input_items[item_id]) * 30)
		ok(SkillManager.start_action("cooking", str(aid)), str(aid) + " starts")
		var produced := false
		for attempt in 20:
			var result: Dictionary = SkillManager.perform_action()
			if bool(result.get("success", false)):
				for item_id in action.output_items:
					produced = produced or int(result.get("items", {}).get(item_id, 0)) > 0
				break
		ok(produced, str(aid) + " cooks new crop into food")
		ok(MasteryManager.get_xp("cooking", str(aid)) > 0, str(aid) + " earns mastery")
		SkillManager.stop_action()
	for def in DataLoader.new_skill_systems.species:
		if not plan.added.ranching.has("raise_" + str(def.id)):
			continue
		RanchingManager.deserialize({})
		ok(RanchingManager.build_pen(), str(def.id) + " pen built")
		BankManager.add_item_guaranteed(str(def.stock), 2)
		PlayerData.set_level("ranching", int(def.level) - 1)
		ok(not RanchingManager.stock(0, str(def.id)), str(def.id) + " livestock level locked")
		PlayerData.set_level("ranching", 120)
		ok(RanchingManager.stock(0, str(def.id)) and RanchingManager.stock(0, str(def.id)), str(def.id) + " pair stocks")
		BankManager.add_item_guaranteed("ranch_feed", 1000)
		ok(RanchingManager.feed_pen(0, 1000), str(def.id) + " fed")
		RanchingManager.advance(float(def.seconds) + 0.1)
		var before: int = BankManager.get_count(str(def.produce))
		ok(RanchingManager.collect(0), str(def.id) + " collects")
		ok(BankManager.get_count(str(def.produce)) > before, str(def.id) + " produces reward")
		ok(MasteryManager.get_xp("ranching", "raise_" + str(def.id)) > 0, str(def.id) + " earns mastery")
		RanchingManager.advance(maxf(0.0, 21600.0 - float(def.seconds)))
		ok(RanchingManager.breed(0), str(def.id) + " breeding resolves")
		var saved: Dictionary = RanchingManager.serialize()
		RanchingManager.deserialize(saved)
		ok(str(RanchingManager.pens[0].species) == str(def.id), str(def.id) + " survives save roundtrip")
		ok(DataLoader.shop_store.has("store_" + str(def.stock)), str(def.id) + " stock obtainable")
	if not staged:
		for aid in plan.added.engineering:
			var recipe: Dictionary = DataLoader.get_action("engineering", str(aid))
			var device_id: String = str(recipe.output_items.keys()[0])
			var def: Dictionary = EngineeringManager.device(device_id)
			var target: Dictionary = DataLoader.get_skill_actions(str(def.skill))[0]
			EngineeringManager.installed.clear()
			BankManager.add_item_guaranteed(device_id, 1)
			BankManager.add_item_guaranteed(str(def.fuel), 100)
			for material in target.get("input_items", {}):
				BankManager.add_item_guaranteed(str(material), 10000)
			ok(EngineeringManager.install(device_id, str(target.id)), device_id + " installs")
			var before: float = MasteryManager.get_xp("engineering", str(aid))
			EngineeringManager.advance(100.0)
			ok(MasteryManager.get_xp("engineering", str(aid)) > before, device_id + " automation earns actual recipe mastery")
			ok(str(EngineeringManager.installed[0].status) == "Working", device_id + " performs supported work")
			var owned: int = BankManager.get_count(device_id)
			ok(EngineeringManager.uninstall(0) and BankManager.get_count(device_id) == owned + 1, device_id + " returns intact for reuse")
		var hashes: Dictionary = {}
		for entry in plan.art:
			for path in entry.paths:
				var texture: Texture2D = load("res://" + str(path))
				ok(texture != null and texture.get_size() == Vector2(32, 32), str(entry.id) + " imports at 32x32")
				if texture == null:
					continue
				var image: Image = texture.get_image()
				ok(image.get_pixel(0, 0).a == 0 and image.get_pixel(31,31).a == 0, str(entry.id) + " transparent corners")
			var texture: Texture2D = load("res://" + str(entry.paths[0]))
			if texture == null:
				continue
			var hash: String = texture.get_image().get_data().hex_encode().sha256_text()
			ok(not hashes.has(hash), str(entry.id) + " distinct art")
			hashes[hash] = true
			if not entry.get("resource_only", false) and entry.skill != "ranching":
				var row := Widgets.activity_row(str(entry.skill), DataLoader.get_action(str(entry.skill), str(entry.action)), false, func(): pass)
				add_child(row)
				var previews: Array = row.find_children("*", "TextureRect", true, false)
				ok(not previews.is_empty() and previews[0].texture == AssetRegistry.icon(str(entry.skill), str(entry.action)), str(entry.id) + " row uses dedicated icon")
				row.free()
		var existing_mastery: Dictionary = MasteryManager.serialize()
		var legacy_save: Dictionary = {"mastery_xp": {"engineering": {"assemble_lumberjack": 1000.0, "assemble_device_lumberjack": 500.0}}, "challenges": {"engineering:assemble_lumberjack": {"seconds": 100.0, "claimed": true}}}
		MasteryManager.deserialize(legacy_save)
		ok(MasteryManager.get_xp("engineering", "assemble_device_lumberjack") == 1500.0, "legacy automation mastery merges with recipe mastery")
		ok(not MasteryManager.serialize().mastery_xp.engineering.has("assemble_lumberjack"), "legacy mastery moved once")
		ok(MasteryManager.challenge("engineering", "assemble_device_lumberjack").claimed, "legacy challenge claims preserved")
		var migrated: Dictionary = MasteryManager.serialize()
		MasteryManager.deserialize(migrated)
		ok(MasteryManager.get_xp("engineering", "assemble_device_lumberjack") == 1500.0, "mastery migration does not repeat on reload")
		ok(legacy_save.mastery_xp.engineering.has("assemble_lumberjack"), "migration leaves caller snapshot unchanged")
		MasteryManager.deserialize({"challenges": []})
		ok(MasteryManager.serialize().challenges.is_empty(), "invalid challenge container remains safely ignored")
		MasteryManager.deserialize({"mastery_xp": {"engineering": {"assemble_lumberjack": [], "assemble_device_lumberjack": 500.0}}, "challenges": {"engineering:assemble_lumberjack": {"seconds": {}}}})
		ok(MasteryManager.get_xp("engineering", "assemble_device_lumberjack") == 500.0, "malformed legacy fields cannot destroy valid recipe mastery")
		MasteryManager.deserialize(existing_mastery)
	print("Expansion192Check: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
