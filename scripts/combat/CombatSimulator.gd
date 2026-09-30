class_name CombatSimulator
extends RefCounted
## CombatSimulator — the pure fight model behind the built-in simulator.
##
## This file touches no autoload, no scene tree, no save and no signal. It is handed one plain
## dictionary (a snapshot of the character and the target) plus a seed, and it returns a report.
## That is the whole point: the 10,000-fight run can happen on a worker thread without ever being
## able to observe or disturb live game state, and the model is testable without booting the game.
##
## The fight loop deliberately mirrors CombatManager's: player attacks resolve first, attacks are
## simultaneous within a tick, damage-over-time ticks at the same cadence, and Auto Eat is checked
## after attacks. A simulator that used a different ordering would quietly disagree with the live
## game, which is the one thing a player would notice first.
##
## ASSUMPTIONS, all reported alongside the numbers rather than buried here:
##   - Food is unlimited: the types you own are always available. Food/hour is consumption under
##     that assumption, not a prediction about running out.
##   - Every trial starts at full HP, so 10,000 repeats of a dungeon stay meaningful.
##   - A fight that reaches FIGHT_SECONDS_CEILING is a loss for rate purposes (a stalemate).
##   - Prayer points are unlimited within a trial; the live prayer XP formulas still apply.

## Hard ceiling on one fight. Prevents a two-sided stalemate (a monster that cannot be hit and a
## player who cannot be hit) from running forever. Reaching it counts as a loss.
const FIGHT_SECONDS_CEILING: float = 300.0
## Resolution of the inner loop. Small enough that attack ordering is faithful, large enough that
## 10,000 fights finish in a sensible time.
const STEP_SECONDS: float = 0.1
## Guards against a pathological loop where a step of 0 advances nothing.
const MAX_STEPS_PER_FIGHT: int = 6000
## Mirrors CombatManager.ENEMY_REGEN_FRACTION: a regenerating monster heals this
## fraction of max HP per own attack. Kept literal so the pure model stays
## dependency-free; the simulator suite pins parity with the live loop.
const ENEMY_REGEN_FRACTION: float = 0.02
## Mirrors CombatManager.ENEMY_THORNS_FRACTION / ENRAGE_* — kept literal for the same reason.
const ENEMY_THORNS_FRACTION: float = 0.10
const ENRAGE_HP_FRACTION: float = 0.25
const ENRAGE_MULTIPLIER: float = 1.5

## Run the whole simulation. `snapshot` must already be flattened — see CombatSimulatorManager.
## `trials` is the count; the production UI always passes 10,000.
static func simulate(snapshot: Dictionary, trials: int, seed_value: int) -> Dictionary:
	var report: Dictionary = {
		"trials": maxi(1, int(trials)),
		"seed": int(seed_value),
		"wins": 0,
		"deaths": 0,
		"timeouts": 0,
		"kills": 0,
		"food_eaten": 0,
		"elapsed_seconds": 0.0,
		"fights": 0,
		"damage_dealt": 0.0,
		"xp": {},
		"assumptions": _assumptions(),
	}
	var total: int = maxi(1, int(trials))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_value)
	var xp: Dictionary = {}
	var wins: int = 0
	var deaths: int = 0
	var timeouts: int = 0
	var kills: int = 0
	var food: int = 0
	var elapsed: float = 0.0
	var fights: int = 0
	var damage: float = 0.0

	for _trial in range(total):
		var outcome: Dictionary = _run_trial(snapshot, rng, xp)
		fights += int(outcome["fights"])
		elapsed += float(outcome["seconds"])
		damage += float(outcome["damage"])
		food += int(outcome["food"])
		match str(outcome["result"]):
			"win":
				wins += 1
				kills += int(outcome["kills"])
			"death":
				deaths += 1
			_:
				timeouts += 1

	report["wins"] = wins
	report["deaths"] = deaths
	report["timeouts"] = timeouts
	report["kills"] = kills
	report["food_eaten"] = food
	report["elapsed_seconds"] = elapsed
	report["fights"] = fights
	report["damage_dealt"] = damage
	report["xp"] = xp
	report["death_chance"] = (float(deaths) + float(timeouts)) / float(total)
	# Rates are per hour of simulated fighting time, not per wall-clock second of the run.
	var hours: float = elapsed / 3600.0
	if hours <= 0.0:
		hours = float(total) / 3600.0
	report["simulated_hours"] = hours
	report["kills_per_hour"] = float(kills) / maxf(hours, 0.000001)
	report["food_per_hour"] = float(food) / maxf(hours, 0.000001)
	report["trials_per_hour"] = float(total) / maxf(hours, 0.000001)
	var xp_per_hour: Dictionary = {}
	var total_xp: float = 0.0
	for key in xp.keys():
		var value: float = float(xp[key]) / maxf(hours, 0.000001)
		xp_per_hour[str(key)] = value
		total_xp += value
	report["xp_per_hour"] = xp_per_hour
	report["xp_per_hour_total"] = total_xp
	report["average_fight_seconds"] = elapsed / maxf(float(fights), 1.0)
	report["valid"] = true
	return report

## One full trial: the target's monster sequence, from full HP, until the run is won or lost.
static func _run_trial(snapshot: Dictionary, rng: RandomNumberGenerator, xp: Dictionary) -> Dictionary:
	var player: Dictionary = snapshot.get("player", {})
	var monsters: Array = snapshot.get("monsters", [])
	var max_hp: float = maxf(1.0, float(player.get("max_hp", 10.0)))
	var hp: float = max_hp
	var seconds: float = 0.0
	var kills: int = 0
	var food: int = 0
	var damage: float = 0.0
	var result: String = "win"
	for monster in monsters:
		if typeof(monster) != TYPE_DICTIONARY:
			continue
		var fight: Dictionary = _run_fight(snapshot, player, monster, max_hp, hp, rng, xp)
		seconds += float(fight["seconds"])
		damage += float(fight["damage"])
		food += int(fight["food"])
		if bool(fight["player_died"]):
			return {"result": "death", "seconds": seconds, "kills": kills, "food": food,
				"damage": damage, "fights": _fights_so_far(monsters, monster)}
		hp = float(fight["hp_after"])
		# A kill is only a kill if the fight was actually won.
		kills += int(fight["kills"])
		if bool(fight["timed_out"]):
			result = "timeout"
			return {"result": result, "seconds": seconds, "kills": kills, "food": food,
				"damage": damage, "fights": _fights_so_far(monsters, monster)}
	return {"result": result, "seconds": seconds, "kills": kills, "food": food,
		"damage": damage, "fights": monsters.size()}

## Index of the monster just fought, plus one, so a trial abandoned mid-way still reports the
## fights it actually spent.
static func _fights_so_far(monsters: Array, monster: Dictionary) -> int:
	var index: int = 0
	for i in range(monsters.size()):
		if monsters[i] == monster:
			index = i + 1
			break
	return maxi(1, index)

## The fight loop. Player-first, simultaneous within a step, exactly like CombatManager.
static func _run_fight(snapshot: Dictionary, player: Dictionary, monster: Dictionary,
		max_hp: float, hp_start: float, rng: RandomNumberGenerator, xp: Dictionary) -> Dictionary:
	var style: String = str(player.get("style", "melee"))
	var monster_style: String = str(monster.get("attack_type", "melee"))
	var mode_config: Dictionary = snapshot.get("mode_config", {})
	var triangle: Dictionary = CombatFormulas.triangle(style, monster_style, mode_config)
	var hazard: Dictionary = snapshot.get("hazard", {})
	var accuracy: float = float(player.get("accuracy", 10)) * (1.0 + float(triangle["accuracy_percent"]) / 100.0)
	# Flat hit-chance points, exactly like the live loop (not rating points).
	var player_hit_bonus: float = float(hazard.get("player_accuracy_percent", 0.0))
	var max_hit: int = maxi(1, int(player.get("max_hit", 1)))
	var min_hit: int = CombatFormulas.min_hit(max_hit, float(player.get("min_hit_percent", 0.0)),
		float(player.get("min_hit_flat", 0.0)))
	var player_interval: float = maxf(0.1, float(player.get("attack_interval", 3.0)))
	var monster_interval: float = maxf(0.1, float(monster.get("attack_speed", 3.0)))
	var monster_max_hit: int = maxi(1, int(monster.get("max_hit", 1)))
	var monster_min_hit: int = CombatFormulas.min_hit(monster_max_hit,
		float(monster.get("min_hit_percent", 0.0)), float(monster.get("min_hit_flat", 0.0)))
	var monster_accuracy: float = float(monster.get("accuracy_rating", 10))
	var monster_dr: float = float(monster.get("damage_reduction", 0.0))
	var monster_hp_max: float = maxf(1.0, float(monster.get("hitpoints", 10)))
	var monster_hp: float = monster_hp_max
	var evasion: int = _evasion_for(monster, style)
	var player_dr: float = float(player.get("damage_reduction", 0.0))
	var player_evasion: int = maxi(0, int(float(_player_evasion(player, monster_style)) * (1.0 + float(hazard.get("player_evasion_percent", 0.0)) / 100.0)))
	var crit_chance: float = float(player.get("crit_chance", 0.0))
	var crit_mult: float = float(player.get("crit_multiplier", 50.0))
	var life_steal: float = float(player.get("life_steal", 0.0))
	var hp: float = hp_start
	var seconds: float = 0.0
	var food: int = 0
	var damage: float = 0.0
	var kills: int = 0
	var player_timer: float = 0.0
	var monster_timer: float = 0.0
	var steps: int = 0

	while monster_hp > 0.0 and hp > 0.0:
		steps += 1
		if steps > MAX_STEPS_PER_FIGHT or seconds >= FIGHT_SECONDS_CEILING:
			return {"hp_after": hp, "seconds": seconds, "food": food, "damage": damage,
				"kills": kills, "player_died": false, "timed_out": true}
		player_timer += STEP_SECONDS
		monster_timer += STEP_SECONDS
		# Player first: the live loop resolves player attacks before monster attacks in the same
		# tick, so a monster that would have died this step never gets its swing.
		if player_timer >= player_interval:
			player_timer -= player_interval
			var roll: Dictionary = CombatFormulas.roll_damage(rng, min_hit, max_hit, monster_dr,
				crit_chance, crit_mult, str(monster.get("damage_type", "normal")))
			if clampf(CombatFormulas.chance_to_hit(accuracy, float(evasion)) + player_hit_bonus, 0.0, 100.0) > rng.randf() * 100.0:
				var dealt: float = float(roll["damage"]) * (1.0 + float(triangle["damage_percent"]) / 100.0)
				dealt = maxf(0.0, dealt)
				monster_hp -= dealt
				damage += dealt
				# XP follows the live formulas, on damage actually dealt.
				_xp(xp, "hitpoints", CombatFormulas.hitpoints_xp(dealt))
				_xp(xp, str(style), CombatFormulas.style_xp(dealt, bool(player.get("hybrid", false))))
				if float(snapshot.get("prayer_points", 0.0)) > 0.0:
					_xp(xp, "prayer", CombatFormulas.prayer_xp(dealt, float(snapshot.get("prayer_points", 0.0))))
				if life_steal > 0.0:
					hp = minf(max_hp, hp + dealt * life_steal / 100.0)
				# Thorns: a spiny creature pays back a fraction of what it was dealt while it
				# still stands (the live loop reflects before the monster gets to swing).
				if monster_hp > 0.0 and (monster.get("passives", []) as Array).has("thorns"):
					hp -= float(CombatFormulas.thorns_reflect(int(dealt), ENEMY_THORNS_FRACTION))
		if monster_hp <= 0.0:
			kills = 1
			_xp(xp, "slayer", CombatFormulas.slayer_xp_for_kill(monster_hp_max,
				bool(player.get("on_slayer_task", false)), bool(snapshot.get("in_slayer_area", false))))
			break
		if monster_timer >= monster_interval:
			monster_timer -= monster_interval
			var their_roll: Dictionary = CombatFormulas.roll_damage(rng, monster_min_hit, monster_max_hit,
				0.0, 0.0, 0.0, "normal")
			if CombatFormulas.chance_to_hit(monster_accuracy, float(player_evasion)) > rng.randf() * 100.0:
				# A raging monster hits harder as it nears death (applied before DR, like the live
				# loop) — gated on the passive, exactly as CombatManager gates it.
				var raw_taken: float = float(their_roll["damage"])
				if (monster.get("passives", []) as Array).has("enrage"):
					raw_taken *= CombatFormulas.enrage_multiplier( 						monster_hp / monster_hp_max, ENRAGE_HP_FRACTION, ENRAGE_MULTIPLIER)
				# Clamped for the same reason as the live loop: an unbounded reduction would make
				# the multiplier negative and every hit a heal.
				var taken: float = raw_taken * (1.0 - clampf(player_dr, 0.0, 90.0) / 100.0)
				taken *= (1.0 + float(hazard.get("enemy_damage_percent", 0.0)) / 100.0)
				hp -= maxf(0.0, taken)
			if monster_hp > 0.0 and (monster.get("passives", []) as Array).has("regeneration"):
				monster_hp = minf(monster_hp_max, monster_hp + maxf(1.0, monster_hp_max * ENEMY_REGEN_FRACTION))
		# Auto Eat is evaluated after attacks, like the live loop.
		var meal: Dictionary = _auto_eat(snapshot, hp, max_hp)
		if int(meal["eaten"]) > 0:
			food += int(meal["eaten"])
			hp = minf(max_hp, hp + float(meal["heal"]))
		seconds += STEP_SECONDS
	return {"hp_after": hp, "seconds": seconds, "food": food, "damage": damage,
		"kills": kills, "player_died": hp <= 0.0, "timed_out": false}

## The live Auto Eat thresholds and efficiencies, mirrored here so the simulator does not read
## CombatManager from a worker thread.
const AUTO_EAT_THRESHOLDS: Dictionary = {1: 20.0, 2: 30.0, 3: 40.0}
const AUTO_EAT_EFFICIENCY: Dictionary = {1: 0.60, 2: 0.80, 3: 1.00}

## Eat if the threshold is crossed. Returns {"eaten": int, "heal": float}.
##
## The food choice mirrors the live manager: the cheapest food that covers the missing health, and
## otherwise the biggest, so food/hour is comparable to what the same character would actually
## consume. Portions are unlimited here by design.
static func _auto_eat(snapshot: Dictionary, hp: float, max_hp: float) -> Dictionary:
	var none: Dictionary = {"eaten": 0, "heal": 0.0}
	var tier: int = int(snapshot.get("auto_eat_tier", 0))
	var foods: Dictionary = snapshot.get("food", {})
	if tier <= 0 or foods.is_empty():
		return none
	var threshold: float = float(AUTO_EAT_THRESHOLDS.get(tier, 0.0)) \
		+ float(snapshot.get("auto_eat_threshold_percent", 0.0))
	if threshold <= 0.0:
		return none
	if hp / maxf(max_hp, 1.0) * 100.0 > threshold:
		return none
	var missing: float = maxf(1.0, max_hp - hp)
	var best: int = -1
	var chosen: int = 0
	# Sorted by heal so the first food that covers the gap is the cheapest such food, which is
	# what the live manager does.
	var ids: Array = foods.keys()
	ids.sort_custom(func(a, b): return int(foods[a]) < int(foods[b]))
	for food_id in ids:
		var heal: int = int(foods[food_id])
		if best < 0:
			best = heal
			chosen = heal
		if heal >= missing:
			chosen = heal
			break
	var efficiency: float = float(AUTO_EAT_EFFICIENCY.get(tier, 1.0)) \
		* (1.0 + float(snapshot.get("food_healing_percent", 0.0)) / 100.0)
	return {"eaten": 1, "heal": float(chosen) * efficiency}

static func _evasion_for(monster: Dictionary, style: String) -> int:
	match style:
		"melee": return int(monster.get("melee_evasion", 10))
		"ranged": return int(monster.get("ranged_evasion", 10))
		_: return int(monster.get("magic_evasion", 10))

static func _player_evasion(player: Dictionary, monster_style: String) -> int:
	var evasion: Dictionary = player.get("evasion", {})
	return int(evasion.get(monster_style, evasion.get("melee", 10)))

static func _xp(table: Dictionary, key: String, amount: float) -> void:
	if amount <= 0.0:
		return
	table[key] = float(table.get(key, 0.0)) + amount

## The assumptions are shown in the UI, not hidden in this file, because every one of them is a
## reason a player's real results could differ from the report.
static func _assumptions() -> Array[String]:
	return [
		"Food is unlimited: the food types you own are always available, so food/hour is consumption rather than a run-out prediction.",
		"Every fight starts at full HP, so repeated dungeon trials stay comparable.",
		"A fight that reaches %d seconds is counted as a loss." % int(FIGHT_SECONDS_CEILING),
		"Prayer points are unlimited within a fight; prayer XP still uses the live formula.",
		"Level-ups, potion charges and loot drops are not simulated.",
	]
