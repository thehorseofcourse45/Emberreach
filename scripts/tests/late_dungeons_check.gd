extends Node

func _ready() -> void:
	var entries := [["emberrift_cavern", 250, 280, "ashen_bastion_keep"], ["tidewrought_temple", 272, 322, "emberrift_cavern"], ["moonbriar_mausoleum", 305, 360, "tidewrought_temple"], ["gilded_clockwork_vault", 335, 399, "moonbriar_mausoleum"], ["stormglass_observatory", 395, 440, "gilded_clockwork_vault"], ["celestial_rift_gate", 435, 500, "stormglass_observatory"]]
	for entry in entries:
		var dungeon: Dictionary = DataLoader.get_dungeon(entry[0])
		assert(not dungeon.is_empty() and not dungeon.get("stronghold", false) and not dungeon.get("legendary", false))
		assert(not CombatManager.is_expedition(entry[0]))
		assert(int(dungeon.player_reference_level_range[0]) == entry[1] and int(dungeon.player_reference_level_range[1]) == entry[2] and dungeon.requires_dungeon == entry[3])
		assert(dungeon.monsters.size() >= 3 and not dungeon.completion_reward.items.is_empty() and not dungeon.rewards_first_clear.items.is_empty())
		for id in dungeon.monsters:
			var monster: Dictionary = DataLoader.get_monster(str(id))
			assert(not monster.is_empty() and int(monster.combat_level) >= int(dungeon.level_range[0]) and int(monster.combat_level) <= int(dungeon.level_range[1]))
	print("LATE DUNGEONS CHECK PASS")
	get_tree().quit()
