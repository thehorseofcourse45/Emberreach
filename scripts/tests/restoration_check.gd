extends Node

func _ready() -> void:
	var a := "hearthfall_restore_1"
	var b := "hearthfall_restore_2"
	var c := "hearthfall_restore_3"
	assert(Quests.has_quest(a) and Quests.has_quest(b) and Quests.has_quest(c))
	assert(not Quests.prerequisites_met(b))
	PlayerData.bump_stat("items_crafted", "bronze_bar", 10)
	PlayerData.bump_stat("monsters_killed", "golbin", 10)
	assert(Quests.claim(a))
	assert(not Quests.claim(a))
	assert(Quests.prerequisites_met(b) and not Quests.prerequisites_met(c))
	CaravaneeringManager.caravans = [{"route": "ferryman_run", "wagon": "handcart", "guard": "hired_hand", "cargo": {"iron_ore": 60}, "total": 1800.0, "repeat": false}]
	CaravaneeringManager._complete(0)
	var delivered := PlayerData.get_stat("caravan_deliveries", "iron_ore")
	assert(delivered >= 36 and delivered <= 60)
	assert(Quests.claim(b))
	PlayerData.bump_stat("dungeons_cleared", "chicken_coop", 1)
	assert(Quests.claim(c))
	var player := PlayerData.serialize()
	var quests := Quests.serialize()
	PlayerData.reset_stats()
	Quests.deserialize({})
	PlayerData.deserialize(player)
	Quests.deserialize(quests)
	assert(PlayerData.get_stat("caravan_deliveries", "iron_ore") == delivered)
	assert(Quests.is_claimed(a) and Quests.is_claimed(b) and Quests.is_claimed(c))
	assert(not Quests.claim(c))
	print("RESTORATION CHECK PASS")
	get_tree().quit()
