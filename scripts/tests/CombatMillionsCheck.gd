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
	call_deferred("run")

func run() -> void:
	var highest := 0
	for id in DataLoader.monsters:
		var m: Dictionary = DataLoader.get_monster(str(id))
		var level := int(m.get("combat_level", 0))
		var old := int(m.get("player_reference_combat_level", 0))
		ok(level > 0 and level <= 5000000, str(id) + " level in range")
		if old <= 120: ok(level == old, str(id) + " preserves early combat")
		highest = maxi(highest, level)
	ok(highest == 5000000, "the cap is five million")
	for group in [DataLoader.areas, DataLoader.dungeons]:
		for id in group:
			var row: Dictionary = group[id]
			var span: Array = row.get("level_range", [])
			if span.size() != 2: continue
			for mid in row.get("monsters", []):
				var level := int(DataLoader.get_monster(str(mid)).get("combat_level", 0))
				ok(level >= int(span[0]) and level <= int(span[1]), str(id) + " contains " + str(mid) + " in its shown range")
			if group == DataLoader.dungeons:
				var old: Array = row.get("player_reference_level_range", [])
				if old.size() == 2:
					var was_expedition := not bool(row.get("regular_dungeon", false)) and int(old[0]) >= CombatManager.EXPEDITION_COMBAT_LEVEL
					ok(CombatManager.is_expedition(str(id)) == was_expedition, str(id) + " retains its activity category")
	var raids := ["infernal_crucible", "leviathan_cathedral", "verdant_oblivion", "eclipse_citadel", "throne_beyond_stars", "clockwork_caldera", "abyssal_crown", "gravebound_dominion", "dreamglass_labyrinth", "solar_apex"]
	var previous := 1250000
	for id in raids:
		var raid: Dictionary = DataLoader.get_dungeon(id)
		var boss: Dictionary = DataLoader.get_monster(str(raid.monsters.back()))
		ok(int(boss.combat_level) > previous, id + " boss rises in raid order")
		previous = int(boss.combat_level)
		ok(raid.level_range.back() == previous, id + " range includes its boss")
	for id in ["attack", "strength", "defence", "hitpoints", "ranged", "magic", "prayer", "slayer"]:
		ok(PlayerData.get_level_cap(id) == 120, str(id) + " keeps player cap")
	print("Combat millions: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
