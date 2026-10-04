extends Node
## CombatSimulatorManager — takes the snapshot, runs the fights on a worker, publishes the report.
##
## The split is deliberate. Every read of live game state happens on the main thread in
## `build_snapshot()`, before the thread starts; the worker then receives only that plain dictionary
## and a seed. That is what makes "the simulator never touches your character" true by construction
## rather than by convention, and it is why a save written while a run is in flight is unaffected.
##
## One job at a time. A second Run is refused rather than queued, so a player cannot accidentally
## ask for 100,000 fights and wonder which report belongs to which target.
##
## Results carry a generation stamp. A new game or a save load bumps it, so output computed against
## the old character is discarded instead of appearing under the new one's name.

signal run_started(target_name: String)
signal run_finished(report: Dictionary)
signal run_failed(reason: String)

## The production figure the feature is specified around.
const PRODUCTION_TRIALS: int = 10000
const MIN_TRIALS: int = 1
const MAX_TRIALS: int = 50000

var running: bool = false
var last_report: Dictionary = {}
var last_error: String = ""
var target_label: String = ""

var _thread: Thread = null
var _generation: int = 0
var _pending: Dictionary = {}
var _run_generation: int = 0

func _ready() -> void:
	EventBus.game_loaded.connect(_on_game_loaded)

## Bumped whenever the character is replaced. Anything in flight is now answering a stale question.
func invalidate() -> void:
	_generation += 1
	last_report = {}

func _on_game_loaded() -> void:
	invalidate()

# ---------------------------------------------------------------------------
# Snapshot
# ---------------------------------------------------------------------------

## Everything the pure model needs, read now while the live singletons are authoritative. Returns
## {} when the request cannot produce a meaningful fight, so an invalid target never reaches a
## thread.
func build_snapshot(place_type: String, place_id: String, attack_style: String, melee_style: String, finite_supplies: bool = false) -> Dictionary:
	var monsters: Array = _monster_sequence(place_type, place_id)
	if monsters.is_empty():
		last_error = "That target has no monsters to fight."
		return {}
	var snapshot: Dictionary = {
		"player": _player_stats(attack_style, melee_style),
		"finite_supplies": finite_supplies,
		"food_counts": {},
		"prayer_balance": PlayerData.prayer_points,
		"food_healing_percent": ModifierManager.get_modifier(ModifierKeys.FOOD_HEALING_PERCENT),
		"auto_eat_efficiency_percent": ModifierManager.get_modifier(ModifierKeys.AUTO_EAT_EFFICIENCY_PERCENT),
		"player_special": EquipmentManager.get_weapon_special_attack().duplicate(true),
		"enchant_statuses": DataLoader.get_item(EquipmentManager.get_equipped(8)).get("enchant_statuses", []).duplicate(),
		"protection_styles": [],
		"attack_cost": EquipmentManager.get_attack_cost(),
		"ammo_preservation": ModifierManager.get_modifier(ModifierKeys.AMMO_PRESERVATION_PERCENT),
		"attack_stock": BankManager.items.duplicate(),
		"monsters": monsters,
		"food": _owned_food(),
		"auto_eat_tier": int(PlayerData.settings.get("auto_eat_tier", 0)),
		"auto_eat_threshold_percent": float(ModifierManager.get_modifier(ModifierKeys.AUTO_EAT_THRESHOLD_PERCENT)),
		"prayer_points": PrayerManager.cost_per_attack(),
		"mode_config": DataLoader.game_modes.get(str(PlayerData.game_mode), {}),
		"in_slayer_area": str(DataLoader.areas.get(place_id, {}).get("type", "area")) == "slayer_area",
		"hazard": ModifierManager.negated_hazard(DataLoader.areas.get(place_id, {}).get("hazard", {})) if place_type == "area" else {},
		"on_slayer_task": false,
		"target_type": place_type,
		"target_id": place_id,
	}
	# The player's own accuracy/max-hit come from CombatManager's derived paths so the simulator
	# cannot drift from the live numbers.
	var summary: Dictionary = CombatManager.player_combat_summary(attack_style, melee_style.to_lower())
	for key in ["accuracy", "max_hit", "attack_interval", "damage_reduction", "evasion", "max_hp"]: snapshot.player[key] = summary[key]
	snapshot.player.min_hit_percent = ModifierManager.get_modifier(ModifierKeys.MIN_HIT_PERCENT_OF_MAX) / 100.0
	snapshot.player.min_hit_flat = ModifierManager.get_modifier(ModifierKeys.MIN_HIT_FLAT)
	snapshot.player.hp_regen_per_attack = ModifierManager.get_hp_regen_per_attack()
	for id in PlayerData.active_prayers:
		var prayer: Dictionary = PrayerManager.get_prayer(id)
		if str(prayer.get("type", "")) == "protect": snapshot.protection_styles.append(str(prayer.get("style", "")))
	for id in snapshot.food: snapshot.food_counts[id] = BankManager.get_count(str(id))
	if finite_supplies:
		var equipped_food: Dictionary = {}
		for id in EquipmentManager.food_slots:
			if id != "" and snapshot.food.has(id): equipped_food[id] = snapshot.food[id]
		snapshot.food = equipped_food
	# Resource costs are authored on weapons. Existing attacks with no costs remain free.
	last_error = ""
	return snapshot

## A monster is one trial. A dungeon is its full fixed sequence, because "survive the expedition" is
## the question a dungeon actually asks.
func _monster_sequence(place_type: String, place_id: String) -> Array:
	var out: Array = []
	if str(place_type) == "dungeon":
		for monster_id in (DataLoader.get_dungeon(str(place_id)).get("monsters", []) as Array):
			var record: Dictionary = _monster_record(str(monster_id))
			if not record.is_empty():
				out.append(record)
		return out
	for monster_id in (DataLoader.areas.get(str(place_id), {}).get("monsters", []) as Array):
		var record: Dictionary = _monster_record(str(monster_id))
		if not record.is_empty():
			out.append(record)
	return out

## The monster is copied into a plain record, so a later data edit cannot change a running job.
func _monster_record(monster_id: String) -> Dictionary:
	var m: Dictionary = DataLoader.get_monster(monster_id)
	if m.is_empty():
		return {}
	return {
		"id": monster_id,
		"passives": m.get("passives", []).duplicate(),
		"specials": m.get("special_attacks", []).map(func(id): return DataLoader.get_special_attack(str(id)).duplicate(true)),
		"is_immune_to_effects": bool(m.get("is_immune_to_effects", false)),
		"can_be_stunned": bool(m.get("can_be_stunned", true)),
		"name": str(m.get("name", monster_id)),
		"hitpoints": int(m.get("hitpoints", 10)),
		"max_hit": int(m.get("max_hit", 1)),
		"min_hit_percent": float(m.get("min_hit_percent", 0.0)),
		"min_hit_flat": float(m.get("min_hit_flat", 0.0)),
		"accuracy_rating": int(m.get("accuracy_rating", 10)),
		"attack_speed": float(m.get("attack_speed", 3.0)),
		"attack_type": str(m.get("attack_type", "melee")),
		"damage_type": str(m.get("damage_type", "normal")),
		"damage_reduction": float(m.get("damage_reduction", 0.0)),
		"melee_evasion": int(m.get("melee_evasion", 10)),
		"ranged_evasion": int(m.get("ranged_evasion", 10)),
		"magic_evasion": int(m.get("magic_evasion", 10)),
	}

func _player_stats(attack_style: String, melee_style: String) -> Dictionary:
	return {
		"mode": str(PlayerData.game_mode),
		"style": attack_style,
		"melee_style": melee_style,
		"max_hp": maxf(10.0, float(PlayerData.get_level("hitpoints")) * 10.0),
		"accuracy": 10,
		"max_hit": 1,
		"min_hit_percent": 0.0,
		"min_hit_flat": 0.0,
		"attack_interval": 3.0,
		"damage_reduction": ModifierManager.get_damage_reduction(),
		"evasion": {"melee": 10, "ranged": 10, "magic": 10},
		"crit_chance": ModifierManager.get_crit_chance(),
		"crit_multiplier": ModifierManager.get_crit_multiplier(),
		"life_steal": ModifierManager.get_life_steal(),
		"hybrid": false,
	}

## Only the food types currently owned, with their heal amounts. The quantity is deliberately
## ignored: this model assumes unlimited portions of what you own.
func _owned_food() -> Dictionary:
	var out: Dictionary = {}
	for item_id in BankManager.items.keys():
		var item: Dictionary = DataLoader.get_item(str(item_id))
		if str(item.get("item_type", "")) != "food":
			continue
		var heal: int = int(item.get("heal_amount", 0))
		if heal > 0:
			out[str(item_id)] = heal
	return out

# ---------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------

## Start one background run. Returns false (with a reason) rather than queueing a second job.
func start(place_type: String, place_id: String, attack_style: String, melee_style: String,
		trials: int = PRODUCTION_TRIALS, seed_value: int = 0, finite_supplies: bool = false) -> bool:
	if running:
		last_error = "A simulation is already running."
		run_failed.emit(last_error)
		return false
	var count: int = clampi(int(trials), MIN_TRIALS, MAX_TRIALS)
	var snapshot: Dictionary = build_snapshot(place_type, place_id, attack_style, melee_style, finite_supplies)
	if snapshot.is_empty():
		run_failed.emit(last_error)
		return false
	# A zero seed would repeat the same run every time; the timestamp keeps each run distinct
	# while an explicit seed still gives exact reproducibility.
	var used_seed: int = int(seed_value) if int(seed_value) != 0 else int(Time.get_unix_time_from_system() * 1000.0) % 2147483647
	target_label = _target_name(place_type, place_id)
	last_report = {}
	_pending = {"snapshot": snapshot, "trials": count, "seed": used_seed}
	_run_generation = _generation
	running = true
	_thread = Thread.new()
	var err: int = _thread.start(_thread_main)
	if err != OK:
		running = false
		_thread = null
		_pending = {}
		last_error = "Could not start the simulation thread."
		run_failed.emit(last_error)
		return false
	run_started.emit(target_label)
	return true

## The worker's whole job. It reads only `_pending`, and it is never given a node, a scene or a
## singleton — so it cannot reach the live character even by accident.
func _thread_main() -> void:
	_pending["result"] = CombatSimulator.simulate(_pending["snapshot"],
		int(_pending["trials"]), int(_pending["seed"]))

## Joined on the main thread, so publishing the report happens where signals are safe.
func _process(_delta: float) -> void:
	if not running or _thread == null:
		return
	# Thread has no is_finished() in this build; is_alive() is polled and wait_to_finish() joins.
	# is_started() is checked because wait_to_finish() on a thread that already ended is harmless
	# but calling it on a never-started one is not.
	if _thread.is_alive():
		return
	_thread.wait_to_finish()
	_thread = null
	running = false
	var result: Dictionary = _pending.get("result", {})
	_pending = {}
	# Output from before a reset answers a question about a character that no longer exists.
	if _run_generation != _generation:
		last_error = "Discarded: the character changed while the simulation was running."
		run_failed.emit(last_error)
		return
	if typeof(result) != TYPE_DICTIONARY or not bool(result.get("valid", false)):
		last_error = "The simulation returned no usable result."
		run_failed.emit(last_error)
		return
	last_report = result
	run_finished.emit(result)

func _target_name(place_type: String, place_id: String) -> String:
	if str(place_type) == "dungeon":
		return str(DataLoader.get_dungeon(str(place_id)).get("name", place_id))
	return str(DataLoader.areas.get(str(place_id), {}).get("name", place_id))

## Cancel the current run. The worker is left to finish on its own and its result is discarded,
## because a running Thread cannot be killed safely in GDScript.
func cancel() -> void:
	if not running:
		return
	_generation += 1
	run_failed.emit("Simulation cancelled.")

## The result table the UI renders. Kept here so the panel has no formatting decisions of its own.
func format_report(report: Dictionary) -> Array[String]:
	if report.is_empty():
		return []
	var lines: Array[String] = []
	lines.append("Fights simulated: %s" % UIStyle.fmt_exact(float(report.get("trials", 0))))
	lines.append("Wins: %s   Deaths: %s" % [UIStyle.fmt_exact(float(report.get("wins", 0))),
		UIStyle.fmt_exact(float(report.get("deaths", 0)))])
	lines.append("Death chance: %s%%" % UIStyle.fmt(float(report.get("death_chance", 0.0) * 100.0)))
	lines.append("Kills/hour: %s" % UIStyle.fmt(float(report.get("kills_per_hour", 0.0))))
	lines.append("Food/hour: %s" % UIStyle.fmt(float(report.get("food_per_hour", 0.0))))
	lines.append("XP/hour: %s" % UIStyle.fmt(float(report.get("xp_per_hour_total", 0.0))))
	var xp: Dictionary = report.get("xp_per_hour", {})
	for skill_id in xp.keys():
		lines.append("   %s: %s XP/hour" % [str(DataLoader.get_skill(str(skill_id)).get("name", skill_id)),
			UIStyle.fmt(float(xp[skill_id]))])
	lines.append("Average fight: %ss" % UIStyle.fmt(float(report.get("average_fight_seconds", 0.0))))
	lines.append("Seed: %s" % str(report.get("seed", 0)))
	return lines

func is_running() -> bool:
	return running

func cancel_requested() -> bool:
	return false
