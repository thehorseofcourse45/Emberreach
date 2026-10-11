extends Node
func _ready() -> void:
	GameManager.cli_mode = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.start_new_game("standard")
	var suite = preload("res://scripts/tests/TestRunner.gd").new()
	suite.call("_test_every_bonus_key_is_read")
	suite.call("_test_township_has_no_dead_ends")
	suite.call("_test_slayer_pools_are_huntable")
	var placed := 0
	var expected := 0
	for table in [DataLoader.areas, DataLoader.dungeons, DataLoader.archaeology_sites]:
		expected += table.size()
		for row in table.values():
			if DataLoader.cartography_hexes.has(str(row.get("hex", ""))): placed += 1
	suite.call("_eq", placed, expected, "Every area, dungeon and dig site remains on the map")
	print("Integration recheck: ", suite.get("_passed"), " passed, ", suite.get("_failed"), " failed")
	get_tree().quit(0 if int(suite.get("_failed")) == 0 else 1)
