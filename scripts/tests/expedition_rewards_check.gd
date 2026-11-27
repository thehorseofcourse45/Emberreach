extends Node

func _ready() -> void:
	GameManager.start_new_game("standard")
	for skill in DataLoader.get_skill_ids(): PlayerData.set_level(str(skill), 120)
	Quests._claimed["expedition_charter"] = true
	PlayerData.bump_stat("dream_seconds", "crown", 24.0 * 3600.0)
	BankManager.add_item_guaranteed("dream_essence", 1200)
	var dungeon: Dictionary = DataLoader.get_dungeon("dream_sovereign")
	var sequence: Array = dungeon.monsters
	assert(sequence == ["abyssal_imp", "abyssal_fiend", "umbral_stalker", "dream_sovereign"])
	assert(CombatManager.start_combat({"type":"dungeon", "id":"dream_sovereign", "monsters":sequence, "endless":false}))
	assert(BankManager.get_count("dream_essence") == 200)
	assert(BankManager.get_count("sovereign_core") == 0)
	for index in range(sequence.size()):
		assert(CombatManager.current_monster_id == sequence[index])
		CombatManager._on_monster_death()
		if index < sequence.size()-1: assert(BankManager.get_count("sovereign_core") == 0)
		CombatManager.tick(20.0)
	assert(CombatManager.state == CombatManager.State.IDLE)
	assert(BankManager.get_count("sovereign_core") >= 1)
	assert(BankManager.get_count("dream_essence") == 400)
	assert(BankManager.get_count("enchant_catalyst") >= 4)
	assert(PlayerData.gp >= 100000000.0)
	assert(PlayerData.completion_log.dungeons.has("dream_sovereign"))
	var panel := preload("res://scripts/ui/DetailPanel.gd").new()
	add_child(panel)
	panel.show_region("dream_sovereign")
	assert(_contains(panel, "Base reward per clear"))
	assert(_contains(panel, "Dream Essence"))
	assert(_contains(panel, "Sleeping Sovereign"))
	panel.show_region("endless_ashes")
	assert(_contains(panel, "Base reward per floor"))
	assert(_contains(panel, "Every tenth floor pays six times"))
	var clear_id := "air_god_dungeon"
	var helm := "air_god_helmet"
	var before: int = BankManager.get_count(helm)
	CombatManager.context = {"type":"dungeon", "id":clear_id}
	CombatManager._complete_combat()
	assert(BankManager.get_count(helm) == before + 1)
	CombatManager.context = {"type":"dungeon", "id":clear_id}
	CombatManager._complete_combat()
	assert(BankManager.get_count(helm) == before + 1)
	var floor: Dictionary = DataLoader.get_dungeon("endless_ashes").floor_reward
	var gp_before: float = PlayerData.gp
	var shards_before: int = BankManager.get_count("ash_depth_shard")
	CombatManager.context = {"type":"dungeon", "id":"endless_ashes", "monsters":DataLoader.get_dungeon("endless_ashes").monsters, "floor":10, "index":0}
	CombatManager._complete_combat()
	assert(BankManager.get_count("ash_depth_shard") == shards_before + 6 * int(floor.items.ash_depth_shard))
	assert(is_equal_approx(PlayerData.gp - gp_before, 6.0 * float(floor.gp)))
	CombatManager.stop_combat("test")
	print("EXPEDITION REWARDS CHECK PASS")
	get_tree().quit()

func _contains(node: Node, text: String) -> bool:
	for label in node.find_children("*", "Label", true, false):
		if str((label as Label).text).contains(text): return true
	return false
