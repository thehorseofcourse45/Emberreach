extends Node
const Text = preload("res://scripts/ui/BossMechanicText.gd")
const IDS = ["air_god", "water_god", "earth_god", "fire_god", "the_mist", "dark_herald", "underwater_king", "bastion_warden", "gloam_matron", "warden_of_the_hush", "the_herald", "the_silence"]
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
	call_deferred("run")
func run() -> void:
	for id in IDS:
		var boss: Dictionary = DataLoader.get_monster(id)
		ok(bool(boss.get("is_boss", false)), id + " is a boss")
		ok(ContentValidator.validate_monster_mechanics(id, boss).is_empty(), id + " mechanics validate")
		ok(MonsterMechanics.affinity_multiplier(boss, str(boss.weak_to[0])) == 1.25, id + " weakness affects damage")
		ok(MonsterMechanics.affinity_multiplier(boss, str(boss.resists[0])) == 0.75, id + " resistance affects damage")
		var phases: Array = boss.phases
		var text: String = " ".join(Text.describe(boss))
		for phase in phases:
			var threshold: float = float(phase.at_hp_percent) / 100.0
			ok(MonsterMechanics.phases_due(phases, 0, threshold) >= 1, id + " phase fires at threshold")
			ok(text.contains(str(phase.name)), id + " phase appears in details")
		ok(text.contains("Weak to") and text.contains("Resists"), id + " affinities shown")
	var stone: Dictionary = DataLoader.get_monster("earth_god")
	var armored: Dictionary = MonsterMechanics.effective(stone, 2)
	ok(armored.passives.has("armored"), "stone boss gains armor")
	ok(MonsterMechanics.armored_reduce(armored, 100) < 100, "armor reduces damage")
	CombatManager.current_monster_id = "water_god"
	CombatManager.monster_max_hp = 1000
	CombatManager.monster_hp = 600
	CombatManager.monster_phases_fired = 0
	CombatManager.player_effects.clear()
	CombatManager._fire_due_phases()
	ok(CombatManager.monster_phases_fired == 1, "live combat triggers tide phase")
	ok(not CombatManager.player_effects.is_empty() and CombatManager.player_effects[0].id == "slow", "live tide applies slow")
	var effects: Array = []
	var rng := RandomNumberGenerator.new()
	var simulated: Dictionary = CombatSimulator._fire_phases({}, {}, DataLoader.get_monster("water_god"), {"fired": 0}, 0.6, effects, rng)
	ok(int(simulated.fired) == 1 and not effects.is_empty() and effects[0].id == "slow", "simulator applies same tide phase")
	var details = preload("res://scripts/ui/DetailPanel.gd").new()
	add_child(details)
	details.show_region("air_god_dungeon")
	var regions := 0
	for id in DataLoader.dungeons:
		if (DataLoader.get_dungeon(str(id)).get("monsters", []) as Array).has("earth_god"):
			details.show_region(str(id))
			regions += 1
			break
	ok(regions == 1, "boss encounter details render")
	var displayed := false
	for child in details._body.get_children():
		if child is Label and str(child.text).contains("Stone Bulwark"): displayed = true
	ok(displayed, "encounter details show stone phase")
	details.queue_free()
	await get_tree().process_frame
	print("BOSS VARIETY: ", checks, " checks; ", failures, " failures")
	get_tree().quit(1 if failures else 0)
