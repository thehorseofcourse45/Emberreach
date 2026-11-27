extends Node
var failures := 0
func _ready() -> void:
	GameManager.cli_mode = true
	GameManager.is_paused = true
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		print("FAIL ", message)
func report(label: String, snap: Dictionary, minimum_wins: int) -> void:
	var result: Dictionary = CombatSimulator.simulate(snap, 10, 20261103)
	print("VERIFIED|", label, "|wins=", result.wins, "/10|deaths=", result.deaths, "|timeouts=", result.timeouts, "|minutes=", snappedf(float(result.elapsed_seconds)/600.0,0.1), "|food=", snappedf(float(result.food_eaten)/10.0,0.1))
	check(int(result.wins) >= minimum_wins, label + " expected wins")
	check(int(result.timeouts) == 0, label + " has no 15-minute single-fight stalls")
func run() -> void:
	var fixture = load("res://scripts/tests/EndgamePathProbe.gd").new()
	var gear: Array = fixture.ARMOR + ["worldheart_crown", "blightroot_cuirass", "starfall_aegis", "embercrown_blade"]
	for id in ["voidglass_monolith", "astral_concord", "eternal_horizon_citadel"]:
		fixture.setup(gear)
		var snap: Dictionary = fixture.make_snapshot(id)
		check(not snap.is_empty(), id + " snapshot builds")
		if not snap.is_empty(): report(id, snap, 9)
	var previous_hp := 0.0
	var previous_damage := 0
	for i in range(RaidManager.ASTRAL_TRIALS.size()):
		var boss: Dictionary = DataLoader.get_monster(str(RaidManager.ASTRAL_TRIALS[i].enemy))
		var hp: float = float(boss.hitpoints) * (1.0 + float(i) * 0.025)
		check(hp >= previous_hp, "trial boss HP rises at " + str(i))
		check(int(boss.max_hit) >= previous_damage, "trial boss max hit rises at " + str(i))
		previous_hp = hp
		previous_damage = int(boss.max_hit)
	fixture.setup(fixture.ARMOR + ["worldheart_crown", "blightroot_cuirass", "starfall_aegis", "astral_vanguard_blade"])
	var snap: Dictionary = fixture.make_snapshot("final_horizon")
	var monsters: Array = []
	for id in RaidManager.astral_sequence(4):
		var enemy: Dictionary = CombatSimulatorManager._monster_record(str(id))
		enemy.hitpoints = roundi(float(enemy.hitpoints) * 1.1)
		monsters.append(enemy)
	snap.monsters = monsters
	report("horizon_nexus", snap, 8)
	fixture.setup(fixture.ARMOR + ["worldheart_crown", "blightroot_cuirass", "starfall_aegis", "leviathan_spear"])
	var archive: Dictionary = fixture.make_snapshot("archive_of_the_last_moon")
	check(not archive.is_empty(), "archive snapshot builds with prior raid weapon")
	if not archive.is_empty(): report("archive_of_the_last_moon", archive, 9)
	check(int(DataLoader.get_dungeon("moonbriar_mausoleum").completion_reward.items.get("throneguard_platelegs", 0)) == 1, "moonbriar repeat reward")
	check(int(DataLoader.get_dungeon("stormglass_observatory").completion_reward.items.get("throneguard_helm", 0)) == 1, "stormglass repeat reward")
	check(int(DataLoader.get_dungeon("moonbriar_mausoleum").rewards_first_clear.items.get("potion_dr_3", 0)) == 8, "existing first-clear rewards remain")
	check(fixture.problems == 0, "fixtures equipped")
	fixture.free()
	print("ENDGAME PROGRESSION: ", failures, " failures")
	get_tree().quit(1 if failures else 0)
