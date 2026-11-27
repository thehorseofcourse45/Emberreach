extends Node

func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.start_new_game("standard")
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	for skill in DataLoader.get_skill_ids(): PlayerData.set_level(str(skill), 120)
	Quests._claimed["expedition_charter"] = true
	assert(DataLoader.get_monster("worldheart_eternal").combat_level == 1250000)
	assert(DataLoader.get_monster("horizon_sovereign").combat_level == 1250000)
	for id in ["starfall_bastion", "worldheart_citadel", "riftbound_spire", "final_horizon"]:
		var d: Dictionary = DataLoader.get_dungeon(id)
		assert(not d.is_empty() and d.monsters.size() >= 3 and d.requires_dungeon != "")
		assert(not CombatManager.dungeon_lock_reason(id).is_empty())
		PlayerData.completion_log.dungeons[d.requires_dungeon] = true
		for item in d.entry_items: BankManager.add_item_guaranteed(str(item), int(d.entry_items[item])*2)
		assert(CombatManager.dungeon_lock_reason(id) == "")
		var context := {"type":"dungeon", "id":id, "monsters":d.monsters, "endless":false}
		if bool(d.get("stronghold", false)):
			assert(not CombatManager.start_combat({"type":"dungeon", "id":id, "monsters":[d.monsters[-1]]}))
		var cost_before: int = BankManager.get_count("shark")
		assert(CombatManager.start_combat(context))
		assert(CombatManager.equipment_locked())
		assert(BankManager.get_count("shark") == cost_before - int(d.entry_items.shark))
		for monster in d.monsters:
			assert(CombatManager.current_monster_id == monster)
			CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
			CombatManager.tick(10.0)
		assert(CombatManager.state == CombatManager.State.IDLE)
		assert(PlayerData.completion_log.dungeons.has(id))
		var reward: String = str(d.rewards_first_clear.items.keys()[0])
		assert(BankManager.get_count(reward) == 1)
		assert(CombatManager.start_combat(context))
		for monster in d.monsters:
			assert(CombatManager.current_monster_id == monster)
			CombatManager.apply_damage_to_monster(CombatManager.monster_max_hp)
			CombatManager.tick(10.0)
		assert(BankManager.get_count(reward) == 1)
	var snapshot: Dictionary = SaveManager.build_save_data()
	GameManager.start_new_game("standard")
	SaveManager._apply(snapshot)
	for id in ["starfall_bastion", "worldheart_citadel", "riftbound_spire", "final_horizon"]:
		assert(PlayerData.completion_log.dungeons.has(id))
	var panel := preload("res://scripts/ui/panels/CombatPanel.gd").new()
	panel.expeditions_only = true
	add_child(panel)
	panel.focus_route({"area_id":"worldheart_citadel"})
	assert(panel._strongholds_only and panel._selected_area == "worldheart_citadel")
	panel.focus_route({"area_id":"final_horizon"})
	assert(not panel._strongholds_only and panel._selected_area == "final_horizon")
	print("LEVEL 500 CONTENT CHECK PASS")
	get_tree().quit()
