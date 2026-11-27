extends Node

func _ready() -> void:
	var expectations := [["ashward_fortress",250,265,"ashen_bastion_keep"], ["nightfen_citadel",265,280,"ashward_fortress"], ["riftmaw_keep",280,300,"nightfen_citadel"], ["hushspire_hold",300,320,"riftmaw_keep"], ["starforge_gatehouse",320,340,"hushspire_hold"], ["eventide_rampart",475,490,"starfall_bastion"]]
	for entry in expectations:
		var d: Dictionary = DataLoader.get_dungeon(entry[0])
		if d.is_empty():
			printerr("STRONGHOLD RANGE FAIL: missing ", entry[0]); get_tree().quit(1); return
		assert(bool(d.stronghold) and int(d.player_reference_level_range[0]) == int(entry[1]) and int(d.player_reference_level_range[1]) == int(entry[2]))
		assert(d.requires_dungeon == entry[3] and d.stages.size() == 3 and d.monsters.size() == 3)
		var seen: Dictionary = {}
		for i in range(3):
			var mid: String = str(d.monsters[i])
			var monster: Dictionary = DataLoader.get_monster(mid)
			assert(not monster.is_empty() and bool(monster.is_boss) and not seen.has(mid))
			assert(int(monster.combat_level) >= int(d.level_range[0]) and int(monster.combat_level) <= int(d.level_range[1]))
			assert(str(d.stages[i].monster) == mid)
			seen[mid] = true
		assert(not d.completion_reward.items.is_empty() and not d.rewards_first_clear.items.is_empty())
	var existing: Dictionary = DataLoader.get_dungeon("worldheart_citadel")
	assert(existing.requires_dungeon == "starfall_bastion" and existing.level_range[-1] == 1250000)
	print("STRONGHOLD RANGE CHECK PASS")
	get_tree().quit()
