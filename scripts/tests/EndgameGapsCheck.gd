extends Node
## Focused checks for the end-game gap content: legendary armour/jewellery, the Archive of
## Echoes wonder and its expedition, completionist capes, mythic rotating tasks and the mythic raid.
## Run: Godot --headless --path . res://scripts/tests/endgame_gaps_check.tscn
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)

const RECIPES := {
	"assemble_sunforged_aegis": ["smithing", "sunforged_aegis"],
	"assemble_nightweaver_mantle": ["fletching", "nightweaver_mantle"],
	"assemble_starbound_vestments": ["runecrafting", "starbound_vestments"],
	"attune_worldheart_signet": ["enchanting", "worldheart_signet"],
	"attune_sovereign_locket": ["enchanting", "sovereign_locket"],
}

func stock(skill: String, action: String) -> void:
	var inputs: Dictionary = DataLoader.get_action(skill, action).get("input_items", {})
	for id in inputs:
		BankManager.add_item_guaranteed(str(id), int(inputs[id]))

func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	for skill in DataLoader.get_skill_ids(): PlayerData.set_level(str(skill), 120)

	# --- legendary armour and jewellery
	for action in RECIPES:
		var skill: String = RECIPES[action][0]
		var out: String = RECIPES[action][1]
		var data: Dictionary = DataLoader.get_action(skill, action)
		check(not data.is_empty(), "recipe exists: " + action)
		check(not DataLoader.get_item(out).is_empty(), "item exists: " + out)
		check(ResourceLoader.exists("res://assets/icons/items/%s.png" % str(DataLoader.get_item(out).get("icon_id", out))), "item icon exists: " + out)
		for b in data.get("requires_building", {}):
			TownshipManager.buildings[b] = 0
		stock(skill, action)
		check(not bool(SkillManager.check_action(skill, action).ok), "recipe locked without its wonder: " + action)
		for b in data.get("requires_building", {}):
			TownshipManager.buildings[b] = 3
		var gate: Dictionary = SkillManager.check_action(skill, action)
		check(bool(gate.ok), "recipe available when supplied: " + action + " " + str(gate.detail))
		check(SkillManager.start_action(skill, action), "recipe starts: " + action)
		var result: Dictionary = SkillManager.perform_action()
		SkillManager.stop_action()
		var produced_id: String = str(result.get("items", {}).keys()[0]) if (result.get("items", {}) as Dictionary).size() > 0 else out
		check(BankManager.get_count(produced_id) >= 1, "recipe produces its item: " + action + " " + str(result))
	for id in ["sunforged_aegis", "nightweaver_mantle", "starbound_vestments"]:
		check(int(DataLoader.get_item(id).equipment_slot) == ItemData.EquipmentSlot.PLATEBODY, "body slot: " + id)
	check(int(DataLoader.get_item("worldheart_signet").equipment_slot) == ItemData.EquipmentSlot.RING, "ring slot")
	check(int(DataLoader.get_item("sovereign_locket").equipment_slot) == ItemData.EquipmentSlot.AMULET, "amulet slot")
	check(int(DataLoader.get_item("archivist_crown").equipment_slot) == ItemData.EquipmentSlot.HELMET, "helmet slot")
	check(int(DataLoader.get_item("sunforged_aegis").equipment_stats.melee_defence) > int(DataLoader.get_item("throneguard_cuirass").equipment_stats.melee_defence), "aegis outclasses Throneguard")

	# --- fourth wonder, hooked to the previously unused skills
	var wid := "wonder_archive_echoes"
	var def: Dictionary = DataLoader.township_buildings.get(wid, {})
	check(bool(def.get("is_wonder", false)), "archive is a wonder")
	for s in ["echo_keeping", "lostfinding", "wayfolding", "customcraft", "inscription"]:
		check((def.requires as Dictionary).has(s), "wonder needs " + s)
	check(str(def.project_final_items.keys()[0]) == "masterwork_codex", "wonder final material is the codex")
	check((DataLoader.get_skill("inscription").get("mastery_challenge_reward", {}) as Dictionary).has("masterwork_codex"), "Scribing mastery challenge awards the codex")
	TownshipManager.buildings[wid] = 0
	PlayerData.set_level("township", 1)
	supply(wid)
	var gp: float = PlayerData.gp
	check(not TownshipManager.build(wid) and PlayerData.gp == gp, "locked archive spends nothing")
	PlayerData.set_level("township", 120)
	for stage in range(3):
		supply(wid)
		check(TownshipManager.build(wid) and TownshipManager.level_of(wid) == stage + 1, "archive stage %d builds" % (stage + 1))
	check(not TownshipManager.build(wid), "finished archive cannot build again")

	# --- fourth expedition
	var dun := "archive_of_the_unwritten"
	var d: Dictionary = DataLoader.get_dungeon(dun)
	check(not d.is_empty() and d.monsters.size() == 23, "archive expedition has 23 encounters")
	for mid in d.monsters: check(ResourceLoader.exists("res://assets/sprites/monsters/%s.png" % mid), "monster sprite: " + str(mid))
	check(ResourceLoader.exists("res://assets/icons/dungeons/%s.png" % dun), "expedition icon")
	Quests.deserialize({"claimed": {"expedition_charter": true}})
	PlayerData.completion_log.dungeons["ascendant_trials"] = true
	TownshipManager.buildings[wid] = 2
	check(CombatManager.dungeon_lock_reason(dun).contains("Complete"), "unfinished archive locks expedition")
	TownshipManager.buildings[wid] = 3
	for item in d.entry_items: BankManager.add_item_guaranteed(str(item), int(d.entry_items[item]))
	PlayerData.completion_log.dungeons.erase("crown_of_embers")
	check(CombatManager.dungeon_lock_reason(dun) == "Clear Crown of Embers", "expedition follows Crown of Embers")
	PlayerData.completion_log.dungeons["crown_of_embers"] = true
	check(CombatManager.dungeon_lock_reason(dun) == "", "prepared expedition unlocks")
	var ctx: Dictionary = {"type": "dungeon", "id": dun, "monsters": d.monsters}
	check(CombatManager.start_combat(ctx), "archive expedition starts")
	CombatManager._complete_combat()
	check(BankManager.get_count("archivist_crown") == 1, "first clear awards the crown")
	for item in d.entry_items: BankManager.add_item_guaranteed(str(item), int(d.entry_items[item]))
	check(CombatManager.start_combat(ctx), "repeat attempt starts")
	CombatManager._complete_combat()
	check(BankManager.get_count("archivist_crown") == 1, "crown does not duplicate")

	# --- completionist capes
	var q1: Dictionary = Quests.get_quest("path_of_completion")
	var q2: Dictionary = Quests.get_quest("path_of_mastery")
	check((q1.objectives as Array).size() == DataLoader.get_skill_ids().size(), "completion quest covers every skill")
	check(q2.prerequisites == ["path_of_completion"], "mastery quest follows completion")
	for s in DataLoader.get_skill_ids(): PlayerData.set_level(str(s), 98)
	check(not Quests.is_complete("path_of_completion"), "98s do not complete it")
	for s in DataLoader.get_skill_ids(): PlayerData.set_level(str(s), 99)
	Quests.accept("path_of_completion")
	check(Quests.is_complete("path_of_completion"), "all skills at 99 completes it")
	check(Quests.claim("path_of_completion") and BankManager.get_count("completionist_cape") == 1, "claim awards the cape")
	check(not Quests.claim("path_of_completion"), "cape claims once")
	for s in DataLoader.get_skill_ids(): PlayerData.set_level(str(s), 120)
	Quests.accept("path_of_mastery")
	check((q2.objectives as Array).size() == DataLoader.get_skill_ids().size(), "mastery quest covers every skill")
	check(Quests.claim("path_of_mastery") and BankManager.get_count("completionist_cape_superior") == 1, "superior cape awarded")
	check(EquipmentManager.equip("completionist_cape"), "cape equips")

	# --- collection pursuit and acquisition routes
	check(Quests.get_quest("collection_archivist").objectives[0].item_ids.size() == 6, "archivist pursuit lists six items")
	check(not Goals.sources_for_item("sunforged_aegis").is_empty(), "armour acquisition explained")
	check(not Goals.sources_for_item("masterwork_codex").is_empty(), "codex acquisition explained")

	# --- mythic rotating tasks
	var mythic_ids: Array = Quests.rotating_pool_ids().filter(func(x): return str(x).begins_with("mythic_"))
	check(mythic_ids.size() == 8, "eight mythic rotating tasks")

	# --- mythic raid
	var cfg: Dictionary = DataLoader.raid_shop.difficulties.mythic
	PlayerData.set_level("slayer", 1)
	check(RaidManager.locked_reason("mythic") != "" and not RaidManager.start_raid("mythic"), "mythic raid is level-gated")
	check(RaidManager.locked_reason("hard") == "", "other difficulties are ungated")
	PlayerData.set_level("slayer", 120)
	check(RaidManager.start_raid("mythic"), "mythic raid starts")
	check(str(CombatManager.context.monsters[0]) == str(cfg.enemy), "mythic waves use the configured enemy")
	RaidManager.end_raid()
	RaidManager.wave = int(cfg.boss_every) - 1
	RaidManager.difficulty = "mythic"
	RaidManager.active = true
	RaidManager._start_wave()
	check((CombatManager.context.monsters as Array).size() == 1 and str(CombatManager.context.monsters[0]) == str(cfg.bosses[0]), "every fifth wave is a boss")
	RaidManager.end_raid()
	var seals: int = BankManager.get_count("masterwork_seal")
	RaidManager.difficulty = "mythic"
	RaidManager.active = true
	RaidManager.wave = int(cfg.seal_every)
	RaidManager.pending_choices = []
	RaidManager._on_combat_ended({"type": "raid", "reason": "complete"})
	check(BankManager.get_count("masterwork_seal") == seals + 1, "raid milestone awards a seal")
	RaidManager.end_raid()

	var issues: Array = ContentValidator.new().validate_all()
	check(not issues.any(func(x): return str(x.get("severity", "")) in ["error", "warning"]), "content validation clean")
	print("Endgame gaps: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)

func supply(id: String) -> void:
	var cost: Dictionary = TownshipManager.scaled_cost(id)
	for res in cost: TownshipManager.resources[res] = float(cost[res])
	var items: Dictionary = TownshipManager.project_item_cost(id)
	for item in items: BankManager.add_item_guaranteed(str(item), int(items[item]))
	PlayerData.gp = TownshipManager.project_gp_cost(id)
