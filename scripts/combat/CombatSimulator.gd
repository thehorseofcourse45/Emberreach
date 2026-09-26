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
## Mirrors CombatManager.ENEMY_RAGE_BONUS_FRACTION / _ENEMY_VEIL_BONUS / _ENEMY_LEECH_FRACTION:
## a wounded monster hits harder, a veiled one is harder to hit, and a leeching one knits back a
## fraction of what it dealt. Literals, same reasons, same reasons they are duplicated rather than
## read from the autoload — this file must stay safe to call from a worker thread.
const ENEMY_RAGE_BONUS_FRACTION: float = 0.5
const ENEMY_VEIL_BONUS: int = 15
const ENEMY_LEECH_FRACTION: float = 0.25

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
		"ability_fires": 0,
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
	var fires: int = 0

	for _trial in range(total):
		var outcome: Dictionary = _run_trial(snapshot, rng, xp)
		fights += int(outcome["fights"])
		elapsed += float(outcome["seconds"])
		damage += float(outcome["damage"])
		food += int(outcome["food"])
		fires += int(outcome["ability_fires"])
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
	# How often the loadout actually fired. A model that silently rolled no abilities would report
	# the same rates as one whose abilities did nothing, so the number is in the report rather than
	# inferred from a difference nobody can attribute.
	report["ability_fires"] = fires
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
## The ability cooldowns are created here and passed into every fight, because the live engine's
## counters live on the combat session rather than on a monster — a trial that ended a fight with
## a Flurry on cooldown has to enter the next one on that same cooldown.
static func _run_trial(snapshot: Dictionary, rng: RandomNumberGenerator, xp: Dictionary) -> Dictionary:
	var player: Dictionary = snapshot.get("player", {})
	var monsters: Array = snapshot.get("monsters", [])
	var max_hp: float = maxf(1.0, float(player.get("max_hp", 10.0)))
	var hp: float = max_hp
	var seconds: float = 0.0
	var kills: int = 0
	var food: int = 0
	var damage: float = 0.0
	var fires: int = 0
	var cooldowns: Dictionary = {}
	var result: String = "win"
	for monster in monsters:
		if typeof(monster) != TYPE_DICTIONARY:
			continue
		var fight: Dictionary = _run_fight(snapshot, player, monster, max_hp, hp, rng, xp, cooldowns)
		seconds += float(fight["seconds"])
		damage += float(fight["damage"])
		food += int(fight["food"])
		fires += int(fight["ability_fires"])
		if bool(fight["player_died"]):
			return {"result": "death", "seconds": seconds, "kills": kills, "food": food,
				"damage": damage, "fights": _fights_so_far(monsters, monster), "ability_fires": fires}
		hp = float(fight["hp_after"])
		# A kill is only a kill if the fight was actually won.
		kills += int(fight["kills"])
		if bool(fight["timed_out"]):
			result = "timeout"
			return {"result": result, "seconds": seconds, "kills": kills, "food": food,
				"damage": damage, "fights": _fights_so_far(monsters, monster), "ability_fires": fires}
	return {"result": result, "seconds": seconds, "kills": kills, "food": food,
		"damage": damage, "fights": monsters.size(), "ability_fires": fires}

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
##
## RNG DRAW ORDER inside one player attack mirrors CombatManager._player_attack step for step, and
## that order is the whole point: an offline catch-up replays the LIVE ticks from the same seeded
## stream, so this model only reports the live game's numbers if it spends its randomness in the
## same sequence.   1. to-hit.   2. one trigger roll per loadout entry IN LOADOUT ORDER, stopping at
## the first that is off cooldown and lands — a blocked entry is skipped WITHOUT a draw, and an
## entry after the winner is never rolled at all.   3. the fired ability's own status-chance draw.
##   4. the damage roll and the crit roll.   5. the weapon special roll.   6. that special's
## status-chance draw. A miss returns after step 1, which is why the damage roll sits BELOW the hit
## test here: it used to sit above it, and spending the damage roll before the to-hit is a
## different stream even though it is the same arithmetic.
static func _run_fight(snapshot: Dictionary, player: Dictionary, monster: Dictionary,
		max_hp: float, hp_start: float, rng: RandomNumberGenerator, xp: Dictionary,
		cooldowns: Dictionary) -> Dictionary:
	var style: String = str(player.get("style", "melee"))
	var monster_style: String = str(monster.get("attack_type", "melee"))
	var mode_config: Dictionary = snapshot.get("mode_config", {})
	var triangle: Dictionary = CombatFormulas.triangle(style, monster_style, mode_config)
	var hazard: Dictionary = snapshot.get("hazard", {})
	var accuracy: float = float(player.get("accuracy", 10))
	# Flat hit-chance points, exactly like the live loop (not rating points).
	var player_hit_bonus: float = float(hazard.get("player_accuracy_percent", 0.0)) \
		+ float(triangle["accuracy_percent"])
	var base_max_hit: int = maxi(1, int(player.get("max_hit", 1)))
	var min_hit_percent: float = float(player.get("min_hit_percent", 0.0))
	var min_hit_flat: float = float(player.get("min_hit_flat", 0.0))
	var base_player_interval: float = maxf(0.1, float(player.get("attack_interval", 3.0)))
	var player_interval: float = base_player_interval
	var loadout: Array = snapshot.get("loadout", [])
	var strategy: Dictionary = snapshot.get("strategy", {})
	var weapon_special: Dictionary = snapshot.get("weapon_special", {})
	## A Flurry-class interval_percent is a PER-TICK speedup, so it is held here and spent at the
	## top of the next step rather than folded into the swing: the live engine re-derives the
	## interval from ModifierManager every tick, and a buff left in the interval would be
	## overwritten before it ever reached a swing.
	var ability_interval_percent: float = 0.0
	var ability_fires: int = 0
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
	var monster_effects: Array = []
	var steps: int = 0

	while monster_hp > 0.0 and hp > 0.0:
		steps += 1
		if steps > MAX_STEPS_PER_FIGHT or seconds >= FIGHT_SECONDS_CEILING:
			return {"hp_after": hp, "seconds": seconds, "food": food, "damage": damage,
				"kills": kills, "player_died": false, "timed_out": true, "ability_fires": ability_fires}
		# Statuses tick BEFORE the swings, as CombatManager.tick() orders them, so a burn that
		# finishes the monster this step kills it before it ever swings back.
		monster_hp -= _tick_effects(monster_effects, STEP_SECONDS)
		player_interval = maxf(0.1, base_player_interval * (1.0 - ability_interval_percent / 100.0))
		ability_interval_percent = 0.0
		player_timer += STEP_SECONDS
		monster_timer += STEP_SECONDS
		# Player first: the live loop resolves player attacks before monster attacks in the same
		# tick, so a monster that would have died this step never gets its swing.
		if player_timer >= player_interval:
			player_timer -= player_interval
			# Step 1. A whiff fires nothing, so no ability is rolled and no damage is drawn. The
			# comparison is the live one: a roll at or under the chance lands.
			if clampf(CombatFormulas.chance_to_hit(accuracy, float(evasion)) + player_hit_bonus,
					0.0, 100.0) >= rng.randf() * 100.0:
				# Steps 2-3: at most one ability takes the swing.
				var ab: Dictionary = _roll_abilities(loadout, cooldowns, rng)
				var ab_effect: Dictionary = ab.get("effect", {}) as Dictionary
				if not ab.is_empty():
					ability_fires += 1
					ability_interval_percent += float(ab_effect.get("interval_percent", 0.0))
					var applied: StatusEffect = _apply_ability_status(rng, ab)
					if applied != null:
						monster_effects.append(applied)
				# Step 4. max_hit_percent folds into THIS swing's max hit and the triangle folds in
				# after it, both the way the live loop folds them; an ability never registers a
				# ModifierManager source, because a permanent buff would need unregistering across
				# fights and was ruled out for that reason.
				var swing_max_hit: int = maxi(1, int(floor(float(base_max_hit)
					* (1.0 + float(ab_effect.get("max_hit_percent", 0.0)) / 100.0))))
				swing_max_hit = maxi(1, int(floor(float(swing_max_hit)
					* (1.0 + float(triangle["damage_percent"]) / 100.0))))
				var roll: Dictionary = CombatFormulas.roll_damage(rng,
					CombatFormulas.min_hit(swing_max_hit, min_hit_percent, min_hit_flat),
					swing_max_hit, monster_dr,
					crit_chance + float(ab_effect.get("crit_chance_percent", 0.0)), crit_mult,
					str(monster.get("damage_type", "normal")))
				var dealt: float = float(roll["damage"])
				# Steps 5-6: the weapon special, then that special's own status chance.
				var sa: Dictionary = _roll_special_attack(rng, weapon_special,
					str(strategy.get("special_bias", "normal")))
				if not sa.is_empty():
					dealt = maxf(1.0, floor(dealt * float(sa.get("damage_multiplier", 1.0))))
					var sa_status: StatusEffect = _apply_status(rng, sa, monster)
					if sa_status != null:
						monster_effects.append(sa_status)
					# heal_fraction is a FRACTION of the damage dealt, never a percent of it.
					hp = minf(max_hp, hp + dealt * float(sa.get("heal_fraction", 0.0)))
				# heal_on_hit_fraction, likewise, is a fraction of this swing's damage.
				hp = minf(max_hp, hp + dealt * float(ab_effect.get("heal_on_hit_fraction", 0.0)))
				monster_hp -= dealt
				damage += dealt
				# XP follows the live formulas, on damage actually dealt.
				_xp(xp, "hitpoints", CombatFormulas.hitpoints_xp(dealt))
				_xp(xp, str(style), CombatFormulas.style_xp(dealt, bool(player.get("hybrid", false))))
				if float(snapshot.get("prayer_points", 0.0)) > 0.0:
					_xp(xp, "prayer", CombatFormulas.prayer_xp(dealt, float(snapshot.get("prayer_points", 0.0))))
				if life_steal > 0.0:
					hp = minf(max_hp, hp + dealt * life_steal / 100.0)
		if monster_hp <= 0.0:
			kills = 1
			_xp(xp, "slayer", CombatFormulas.slayer_xp_for_kill(monster_hp_max,
				bool(player.get("on_slayer_task", false)), bool(snapshot.get("in_slayer_area", false))))
			break
		if monster_timer >= monster_interval:
			monster_timer -= monster_interval
			# The monster's to-hit before its damage roll, for the same stream reason as above.
			if CombatFormulas.chance_to_hit(monster_accuracy, float(player_evasion)) >= rng.randf() * 100.0:
				var their_roll: Dictionary = CombatFormulas.roll_damage(rng, monster_min_hit, monster_max_hit,
					0.0, 0.0, 0.0, "normal")
				var taken: float = float(their_roll["damage"]) * (1.0 - player_dr / 100.0)
				taken *= (1.0 + float(hazard.get("enemy_damage_percent", 0.0)) / 100.0)
				# Rage scales off the monster's CURRENT health, so a monster that regenerates or
				# leechs is never free damage. The passive test is the caller's, because this
				# helper is the curve and nothing but the curve — the live engine reads the same
				# shape off its own monster record one call away.
				if _has_passive(monster, "rage"):
					taken *= _rage_multiplier(monster_hp, monster_hp_max)
				hp -= maxf(0.0, taken)
				# Leech knits back a fraction of what this swing dealt, never past its maximum, and
				# only while it is still standing.
				if monster_hp > 0.0 and _has_passive(monster, "leech"):
					monster_hp = _leech_heal(monster_hp, monster_hp_max, taken)
			if monster_hp > 0.0 and _has_passive(monster, "regeneration"):
				monster_hp = minf(monster_hp_max, monster_hp + maxf(1.0, monster_hp_max * ENEMY_REGEN_FRACTION))
		# Auto Eat is evaluated after attacks, like the live loop.
		var meal: Dictionary = _auto_eat(snapshot, hp, max_hp)
		if int(meal["eaten"]) > 0:
			food += int(meal["eaten"])
			hp = minf(max_hp, hp + float(meal["heal"]))
		seconds += STEP_SECONDS
	return {"hp_after": hp, "seconds": seconds, "food": food, "damage": damage,
		"kills": kills, "player_died": hp <= 0.0, "timed_out": false, "ability_fires": ability_fires}

## Mirrors CombatManager._roll_abilities: ONE trigger roll per loadout entry in loadout order,
## stopping at the first that is off cooldown and lands. A blocked entry is skipped WITHOUT a draw
## and an entry after the winner is never rolled, which is what makes the number of draws a swing
## takes part of the balance contract. `cooldowns` is the trial's counter table and is shared by
## every fight in the trial, exactly as CombatManager's lives across a whole combat session.
static func _roll_abilities(loadout: Array, cooldowns: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	for entry in loadout:
		var ab: Dictionary = entry as Dictionary
		if typeof(ab) != TYPE_DICTIONARY or ab.is_empty():
			continue
		var ability_id: String = str(ab.get("id", ""))
		if ability_id == "" or int(cooldowns.get(ability_id, 0)) > 0:
			continue
		if rng.randf() * 100.0 > float(ab.get("trigger_chance", 0.0)):
			continue
		cooldowns[ability_id] = int(ab.get("cooldown_attacks", 0))
		return ab
	return {}

## Mirrors CombatManager._apply_ability_status: the ability's own `apply_status` spelling and its
## top-level status_duration / status_damage_per_tick siblings, bridged into the special-attack
## shape the status path takes. The chance is fixed at 100% for an ability — the trigger roll above
## is the chance — so the draw is still spent and always passes.
static func _apply_ability_status(rng: RandomNumberGenerator, ab: Dictionary) -> StatusEffect:
	var status_id: String = str((ab.get("effect", {}) as Dictionary).get("apply_status", ""))
	if status_id == "":
		return null
	return _apply_status(rng, {
		"applies_status": status_id,
		"status_chance": 100.0,
		"status_duration": float(ab.get("status_duration", 0.0)),
		"status_damage_per_tick": float(ab.get("status_damage_per_tick", 0.0)),
	}, {})

## Mirrors CombatManager._apply_special_status and then apply_status: the status-chance draw is
## spent whenever the record names a status, because a draw that was skipped on a miss would shift
## every roll after it, and only then do the target's own gates get a say.
static func _apply_status(rng: RandomNumberGenerator, record: Dictionary,
		monster: Dictionary) -> StatusEffect:
	var status_id: String = str(record.get("applies_status", ""))
	if status_id == "":
		return null
	if rng.randf() * 100.0 > float(record.get("status_chance", 100.0)):
		return null
	if bool(monster.get("is_immune_to_effects", false)):
		return null
	var effect: StatusEffect = StatusEffect.create(status_id,
		float(record.get("status_duration", 3.0)), float(record.get("status_damage_per_tick", 0.0)))
	if effect.blocks_attack() and not bool(monster.get("can_be_stunned", true)):
		return null
	return effect

## Mirrors CombatManager._tick_effects on the monster: advance every status, drop the finished ones,
## and report the damage they dealt. The DOT damage comes out of StatusEffect.tick() itself, so the
## per-tick figure and the tick_interval that spaces it are the live ones rather than a re-reading
## of the ability record.
static func _tick_effects(effects: Array, delta: float) -> float:
	var damage: float = 0.0
	var live: Array = []
	for entry in effects:
		var e: StatusEffect = entry as StatusEffect
		damage += e.tick(delta)
		if not e.is_expired():
			live.append(e)
	effects.assign(live)
	return damage

## Mirrors CombatManager._roll_special_attack: ONE draw, compared against the biased chance. The
## strategy scales the number that draw is compared against rather than adding a second draw, so
## "hold" suppresses the special without shifting the stream an offline replay walks.
static func _roll_special_attack(rng: RandomNumberGenerator, sa_def: Dictionary,
		bias: String) -> Dictionary:
	if sa_def.is_empty():
		return {}
	var chance: float = _biased_special_chance(float(sa_def.get("trigger_chance", 10.0)), bias)
	if chance <= 0.0 or rng.randf() * 100.0 > chance:
		return {}
	return sa_def

## Mirrors CombatManager._biased_special_chance: eager doubles up to the 100% ceiling, hold is a hard
## zero, and anything else — including an empty or misspelt bias — is the identity. A multiplier on
## the record's own trigger chance, never a new roll.
static func _biased_special_chance(base: float, bias: String) -> float:
	match bias:
		"eager":
			return minf(base * 2.0, 100.0)
		"hold":
			return 0.0
		_:
			return clampf(base, 0.0, 100.0)

## Mirrors CombatManager._food_threshold_percent: the strategy's fraction replaces the auto-eat
## tier's threshold percent, and 0.0 means "defer to the tier", so a preset nobody edited leaves the
## tier's own number in place. No draw — this only moves the number the HP comparison is made
## against.
static func _food_threshold_percent(tier_threshold: float, strategy: Dictionary) -> float:
	var override: float = float(strategy.get("food_threshold", 0.0))
	return override * 100.0 if override > 0.0 else tier_threshold

## Mirrors CombatManager._enemy_rage_multiplier, on the numbers rather than on the live monster:
## 1.0 at full health, rising to 1.0 + ENEMY_RAGE_BONUS_FRACTION as its health falls.
static func _rage_multiplier(monster_hp: float, monster_hp_max: float) -> float:
	var wounded: float = 1.0 - clampf(monster_hp / maxf(1.0, monster_hp_max), 0.0, 1.0)
	return 1.0 + ENEMY_RAGE_BONUS_FRACTION * wounded

## Mirrors the leech heal in CombatManager._monster_attack: a FRACTION (0..1) of the damage dealt,
## never nothing at all, and capped at the monster's own maximum. A function so the cap has
## somewhere to be pinned — the same arithmetic inlined would be a rule no test could reach.
static func _leech_heal(monster_hp: float, monster_hp_max: float, damage: float) -> float:
	return minf(monster_hp_max, monster_hp + maxf(1.0, damage * ENEMY_LEECH_FRACTION))

static func _has_passive(monster: Dictionary, passive_id: String) -> bool:
	return (monster.get("passives", []) as Array).has(passive_id)

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
	var threshold: float = _food_threshold_percent(float(AUTO_EAT_THRESHOLDS.get(tier, 0.0)),
		snapshot.get("strategy", {}))
	threshold += float(snapshot.get("auto_eat_threshold_percent", 0.0))
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

## Mirrors CombatManager._monster_evasion_for, including the veil passive's flat bonus: the model has
## to reach the same rating the live roll compares against, or the same player is told two
## different hit chances.
static func _evasion_for(monster: Dictionary, style: String) -> int:
	var rating: int = 0
	match style:
		"melee": rating = int(monster.get("melee_evasion", 10))
		"ranged": rating = int(monster.get("ranged_evasion", 10))
		_: rating = int(monster.get("magic_evasion", 10))
	if _has_passive(monster, "veil"):
		rating += ENEMY_VEIL_BONUS
	return rating

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
