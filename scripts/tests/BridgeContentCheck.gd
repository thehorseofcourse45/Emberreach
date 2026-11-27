extends Node
var checks := 0
var failures := 0
func ok(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	PlayerData.initialize_new_game()
	PlayerData.settings = SettingsDefaults.DEFAULTS.duplicate(true)
	BankManager.deserialize({"purchased_slots": 200})
	EquipmentManager.deserialize({})
	for id in DataLoader.get_skill_ids(): PlayerData.set_level(str(id), 120)
	call_deferred("run")

func run() -> void:
	var region_ids := ["shardwind_rise", "glasswake_bluffs", "mistbreaker_coast", "tideworn_causeway", "wreckward_shoals"]
	var enemy_ids := ["shardwind_stalker", "glasswake_sentinel", "mistbreaker_hunter", "tideworn_reaver", "wreckward_oracle"]
	var lower := int(DataLoader.areas.sundered_reaches.level_range.back())
	var end := int(DataLoader.areas.drowned_reach.level_range[0])
	for i in region_ids.size():
		var area: Dictionary = DataLoader.areas.get(region_ids[i], {})
		var enemy: Dictionary = DataLoader.get_monster(enemy_ids[i])
		ok(not area.is_empty() and not enemy.is_empty(), "region and enemy exist")
		ok(int(area.level_range[0]) == lower and int(area.level_range[1]) > lower and int(area.level_range[1]) < end, "region bridges previous range")
		ok(area.monsters.has(enemy_ids[i]), "new enemy belongs to region")
		ok(ResourceLoader.exists("res://assets/icons/areas/%s.png" % region_ids[i]), "region has own icon")
		ok(ResourceLoader.exists("res://assets/sprites/monsters/%s.png" % enemy_ids[i]), "new enemy has own artwork")
		lower = int(area.level_range[1])
	var ids := ["shale_watch", "quarry_of_echoes", "broken_sentry_keep", "frostbound_sinkhole", "brine_tunnels", "saltglass_crypt", "undercroft_annex", "sunken_armory", "wyrmwatch_gallery", "shrine_of_squalls", "drowned_archive", "stonebound_labyrinth", "ember_choir_catacombs", "duskward_foundry", "cinder_bastion_depths"]
	var previous := "greyharrow_deep"
	var previous_top := int(DataLoader.get_dungeon(previous).level_range.back())
	var ending := int(DataLoader.get_dungeon("emberrift_cavern").level_range[0])
	var last_encounters := {}
	for id in ids:
		var dungeon: Dictionary = DataLoader.get_dungeon(id)
		ok(not dungeon.is_empty() and not CombatManager.is_expedition(id), id + " is a dungeon")
		ok(str(dungeon.requires_dungeon) == previous, id + " links to the previous dungeon")
		ok(int(dungeon.level_range.back()) > previous_top and int(dungeon.level_range.back()) < ending, id + " advances between endpoints")
		ok(dungeon.monsters.size() >= 3 and not last_encounters.has(str(dungeon.monsters.back())), id + " has a distinct final encounter")
		last_encounters[str(dungeon.monsters.back())] = true
		for mid in dungeon.monsters:
			ok(not DataLoader.get_monster(str(mid)).is_empty(), id + " encounter exists")
		ok(not dungeon.completion_reward.items.is_empty() and not dungeon.rewards_first_clear.items.is_empty(), id + " has clear rewards")
		ok(not Achievements.get_record("dungeon_" + id + "_clear").is_empty(), id + " has a clear milestone")
		ok(ResourceLoader.exists("res://assets/icons/dungeons/%s.png" % id), id + " has own icon")
		previous_top = int(dungeon.level_range.back())
		previous = id
	var first: Dictionary = DataLoader.get_dungeon(ids[0])
	ok(CombatManager.dungeon_lock_reason(ids[0]) != "", "the chain initially requires Greyharrow")
	PlayerData.completion_log.dungeons["greyharrow_deep"] = true
	ok(CombatManager.dungeon_lock_reason(ids[0]) == "", "clearing Greyharrow opens the first dungeon")
	var context := {"type": "dungeon", "id": ids[0], "monsters": first.monsters, "endless": false}
	ok(CombatManager.start_combat(context), "first dungeon starts")
	for mid in first.monsters:
		ok(CombatManager.current_monster_id == mid, "encounters stay in order")
		CombatManager.player_hp = 100000000.0
		CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
		CombatManager.tick(60)
	ok(PlayerData.completion_log.dungeons.has(ids[0]), "clear is recorded")
	ok(BankManager.get_count(str(first.rewards_first_clear.items.keys()[0])) == 1, "first clear gives its reward")
	ok(CombatManager.dungeon_lock_reason(ids[1]) == "", "first clear unlocks next dungeon")
	var state := SaveManager.build_save_data().duplicate(true)
	PlayerData.initialize_new_game()
	SaveManager._apply(state)
	ok(PlayerData.completion_log.dungeons.has(ids[0]), "progress survives save/load")
	print("Bridge content: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
