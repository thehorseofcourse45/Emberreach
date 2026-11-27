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
	BankManager.deserialize({"purchased_slots":200})
	EquipmentManager.deserialize({})
	for sid in DataLoader.get_skill_ids(): PlayerData.set_level(str(sid),120)
	Quests.deserialize({"claimed":{"expedition_charter":true}})
	call_deferred("run")

func run() -> void:
	var ids := ["infernal_crucible", "leviathan_cathedral", "verdant_oblivion", "eclipse_citadel", "throne_beyond_stars"]
	var prior := "worldheart_citadel"
	var seen := {}
	for id in ids:
		var d: Dictionary = DataLoader.get_dungeon(id)
		ok(bool(d.get("raid",false)) and CombatManager.is_expedition(id), "raid uses expedition combat")
		ok(d.monsters.size() > 23 and d.requires_dungeon == prior, "long ordered progression")
		var boss: Dictionary = DataLoader.get_monster(str(d.monsters[-1]))
		ok(int(boss.combat_level) > 1250000 and int(boss.combat_level) <= 5000000 and bool(boss.is_boss) and boss.hitpoints > 19000, "new endgame boss")
		ok(not seen.has(boss.id), "unique final boss")
		seen[boss.id] = true
		ok(ContentValidator.validate_monster_mechanics(boss.id,boss).is_empty(), "boss mechanics validate")
		var item: String = str(d.rewards_first_clear.items.keys()[0])
		ok(not DataLoader.get_item(item).is_empty() and not seen.has(item), "unique guaranteed reward")
		seen[item] = true
		var rare: String = str(boss.loot_table[0].item_id)
		ok(not DataLoader.get_item(rare).is_empty() and not seen.has(rare) and float(boss.loot_table[0].chance) > 0.0, "unique repeatable boss drop")
		seen[rare] = true
		prior = id
	var panel := preload("res://scripts/ui/panels/CombatPanel.gd").new()
	panel.expeditions_only = true
	add_child(panel)
	panel.call("_show_raids")
	ok(panel.get("_places").size() == 15, "raids have their own tab")
	panel.focus_route({"area_id":ids[2]})
	ok(bool(panel.get("_raids_only")) and str(panel.get("_selected_area")) == ids[2], "direct route opens raids tab")
	panel.call("_show_strongholds", true)
	ok(panel.get("_places").size() == 18, "strongholds remain separate")
	panel.free()
	var d: Dictionary = DataLoader.get_dungeon(ids[0])
	PlayerData.completion_log.dungeons[d.requires_dungeon] = true
	for item in d.entry_items: BankManager.add_item_guaranteed(str(item), int(d.entry_items[item])*2)
	var ctx := {"type":"dungeon", "id":ids[0], "monsters":d.monsters, "endless":false}
	var food := BankManager.get_count("shark")
	ok(not CombatManager.start_combat({"type":"dungeon", "id":ids[0], "monsters":[d.monsters[-1]]}), "cannot skip raid encounters")
	ok(BankManager.get_count("shark") == food, "rejected raid spends nothing")
	ok(CombatManager.start_combat(ctx) and CombatManager.equipment_locked(), "raid starts and locks equipment")
	CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
	CombatManager.tick(6)
	var save: Dictionary = CombatManager.serialize().duplicate(true)
	CombatManager.stop_combat()
	CombatManager.deserialize(save)
	ok(CombatManager.current_monster_id == d.monsters[1], "saved raid resumes at the correct encounter")
	for mid in d.monsters.slice(1):
		CombatManager.player_hp = 100000000.0
		ok(CombatManager.current_monster_id == mid, "encounter order")
		CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
		CombatManager.tick(60)
	ok(CombatManager.state == CombatManager.State.IDLE and PlayerData.completion_log.dungeons.has(ids[0]), "full clear recorded")
	var reward: String = str(d.rewards_first_clear.items.keys()[0])
	ok(BankManager.get_count(reward) == 1, "first-clear weapon awarded")
	ok(EquipmentManager.equip(reward), "raid reward can be equipped")
	ok(ModifierManager.get_modifier(ModifierKeys.MELEE_MAX_HIT_PERCENT) >= 10.0, "raid reward bonus is active")
	ok(EquipmentManager.unequip(int(DataLoader.get_item(reward).equipment_slot)), "reward can be unequipped")
	ok(CombatManager.start_combat(ctx), "cleared raid can be repeated")
	for mid in d.monsters:
		CombatManager.player_hp = 100000000.0
		ok(CombatManager.current_monster_id == mid, "repeat encounter order")
		CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
		CombatManager.tick(60)
	ok(BankManager.get_count(reward) == 1, "repeat clear does not duplicate first-clear weapon")
	var previous_coins := 1234.0
	PlayerData.raid_coins = previous_coins
	var old_run: Dictionary = RaidManager.serialize().duplicate(true)
	RaidManager.deserialize(old_run)
	ok(PlayerData.raid_coins == previous_coins and Screens.LABELS[Screens.RAIDS] == "Astral Trial Chamber", "legacy currency and current chamber label preserved")
	print("Endgame raids: ",checks," checks; ",failures," failures")
	get_tree().quit(0 if failures == 0 else 1)
