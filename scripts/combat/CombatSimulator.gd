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
## The fastest a monster may attack, shared with CombatManager's live loop.
const MONSTER_INTERVAL_FLOOR: float = 0.25

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
		"assumptions": _assumptions(snapshot),
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
	snapshot = snapshot.duplicate(true) # Fresh finite inventory for each full encounter trial.
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
## Monster mechanics (affinities, armored / lifedrain / venomous, boss phases, player status
## resistance) come from MonsterMechanics, the rule set the live loop uses.
static func _run_fight(snapshot: Dictionary, player: Dictionary, monster: Dictionary,
		max_hp: float, hp_start: float, rng: RandomNumberGenerator, xp: Dictionary) -> Dictionary:
	var style: String = str(player.get("style", "melee"))
	# Everything a boss phase can change (style, speed, max hit, passives) lives in the view and is
	# re-derived whenever a phase fires.
	var view: Dictionary = _monster_view(snapshot, player, monster, 0)
	var accuracy: float = float(player.get("accuracy", 10))
	var monster_accuracy: float = float(monster.get("accuracy_rating", 10))
	var monster_dr: float = float(monster.get("damage_reduction", 0.0))
	var monster_hp_max: float = maxf(1.0, float(monster.get("hitpoints", 10)))
	var monster_hp: float = monster_hp_max
	var evasion: int = _evasion_for(monster, style)
	var player_dr: float = float(player.get("damage_reduction", 0.0))
	var hazard: Dictionary = snapshot.get("hazard", {})
	var resistance: Dictionary = snapshot.get("status_resistance", {})
	var crit_chance: float = float(player.get("crit_chance", 0.0))
	var crit_mult: float = float(player.get("crit_multiplier", 50.0))
	var life_steal: float = float(player.get("life_steal", 0.0))
	var regen_per_attack: float = float(player.get("hp_regen_per_attack", 0.0))
	var hp: float = hp_start
	var seconds: float = 0.0
	var food: int = 0
	var damage: float = 0.0
	var kills: int = 0
	var player_timer: float = 0.0
	var monster_timer: float = 0.0
	var steps: int = 0
	var player_effects: Array = []
	var monster_effects: Array = []

	while monster_hp > 0.0 and hp > 0.0:
		steps += 1
		if steps > MAX_STEPS_PER_FIGHT or seconds >= FIGHT_SECONDS_CEILING:
			return {"hp_after": hp, "seconds": seconds, "food": food, "damage": damage,
				"kills": kills, "player_died": false, "timed_out": true, "phases_fired": int(view["fired"])}
		hp -= _tick_statuses(player_effects, STEP_SECONDS)
		monster_hp -= _tick_statuses(monster_effects, STEP_SECONDS)
		if hp <= 0: break
		if monster_hp <= 0:
			kills = 1
			_xp(xp, "slayer", CombatFormulas.slayer_xp_for_kill(monster_hp_max, bool(player.get("on_slayer_task", false)), bool(snapshot.get("in_slayer_area", false))))
			break
		# Damage over time crosses boss thresholds too, exactly like the live status tick.
		view = _fire_phases(snapshot, player, monster, view, monster_hp / monster_hp_max, player_effects, rng)
		if not _blocked(player_effects): player_timer += STEP_SECONDS
		if not _blocked(monster_effects): monster_timer += STEP_SECONDS
		# Player first: the live loop resolves player attacks before monster attacks in the same
		# tick, so a monster that would have died this step never gets its swing.
		if player_timer >= float(view["player_interval"]) and not _blocked(player_effects):
			player_timer -= float(view["player_interval"])
			if bool(snapshot.get("finite_supplies", false)):
				# Roll the shot once, then both test and spend it: the live loop and the simulator must
				# charge the same ammunition for the same attack.
				var shot: Dictionary = CombatFormulas.ammo_cost(rng, snapshot.get("attack_cost", {}),
					float(snapshot.get("ammo_preservation", 0.0)))
				var affordable: bool = float(snapshot.get("prayer_balance", 0)) >= float(snapshot.get("prayer_points", 0))
				for id in shot: affordable = affordable and int(snapshot.attack_stock.get(id, 0)) >= int(shot[id])
				if not affordable: return {"hp_after": hp, "seconds": seconds, "food": food, "damage": damage, "kills": kills, "player_died": false, "timed_out": true, "phases_fired": int(view["fired"])}
				snapshot.prayer_balance = float(snapshot.get("prayer_balance", 0)) - float(snapshot.get("prayer_points", 0))
				for id in shot: snapshot.attack_stock[id] -= int(shot[id])
			var roll: Dictionary = CombatFormulas.roll_damage(rng, int(view["min_hit"]), int(view["max_hit"]), monster_dr,
				crit_chance, crit_mult, "normal")
			if clampf(CombatFormulas.chance_to_hit(accuracy, float(evasion)) + float(view["player_hit_bonus"]), 0.0, 100.0) > rng.randf() * 100.0:
				var dealt: float = float(roll["damage"])
				var special: Dictionary = _special([snapshot.get("player_special", {})], rng)
				if not special.is_empty():
					dealt = maxi(1, floori(dealt * float(special.get("damage_multiplier", 1))))
					hp = minf(max_hp, hp + dealt * float(special.get("heal_fraction", 0)))
					_add_special_status(monster_effects, special, rng, monster)
				# Style affinity and armor apply once, to the final landed hit (specials included). The
				# minimum of 1 only keeps a positive hit from rounding away; a hit DR floored to 0 stays 0.
				var current: Dictionary = view["monster"]
				if dealt > 0.0:
					dealt = float(maxi(1, floori(dealt * MonsterMechanics.affinity_multiplier(current, style))))
				dealt = float(MonsterMechanics.armored_reduce(current, int(dealt)))
				for status in snapshot.get("enchant_statuses", []):
					if rng.randf() < 0.2 and not bool(monster.get("is_immune_to_effects", false)): monster_effects.append(StatusEffect.create(str(status), 4.0, maxf(1, dealt * 0.1) if str(status) == "burn" else 0))
				dealt = maxf(0.0, dealt)
				monster_hp -= dealt
				damage += dealt
				# Phases fire after the hit lands and before thorns, as in apply_damage_to_monster().
				if monster_hp > 0.0:
					view = _fire_phases(snapshot, player, monster, view, monster_hp / monster_hp_max, player_effects, rng)
				# XP follows the live formulas, on damage actually dealt.
				_xp(xp, "hitpoints", CombatFormulas.hitpoints_xp(dealt))
				_xp(xp, str(style), CombatFormulas.style_xp(dealt, bool(player.get("hybrid", false))))
				if float(snapshot.get("prayer_points", 0.0)) > 0.0:
					_xp(xp, "prayer", CombatFormulas.prayer_xp(dealt, float(snapshot.get("prayer_points", 0.0))))
				if life_steal > 0.0:
					hp = minf(max_hp, hp + dealt * life_steal / 100.0)
				# Thorns: a spiny creature pays back a fraction of what it was dealt while it
				# still stands (the live loop reflects before the monster gets to swing).
				if monster_hp > 0.0 and (view["passives"] as Array).has("thorns"):
					hp -= float(CombatFormulas.thorns_reflect(int(dealt), ENEMY_THORNS_FRACTION))
			# Mirrors CombatManager._regen_after_attack(): every own attack, hit or miss.
			if regen_per_attack > 0.0 and hp > 0.0:
				hp = minf(max_hp, hp + regen_per_attack)
		if monster_hp <= 0.0:
			kills = 1
			_xp(xp, "slayer", CombatFormulas.slayer_xp_for_kill(monster_hp_max,
				bool(player.get("on_slayer_task", false)), bool(snapshot.get("in_slayer_area", false))))
			break
		if monster_timer >= float(view["monster_interval"]) and not _blocked(monster_effects):
			monster_timer -= float(view["monster_interval"])
			var monster_style: String = str(view["monster_style"])
			var against: Dictionary = view["monster_triangle"]
			var passives: Array = view["passives"]
			var their_roll: Dictionary = CombatFormulas.roll_damage(rng, int(view["monster_min_hit"]),
				int(view["monster_max_hit"]), 0.0, 0.0, 0.0, "normal")
			if clampf(CombatFormulas.chance_to_hit(monster_accuracy, float(view["player_evasion"])) + float(against.accuracy_percent), 0, 100) > rng.randf() * 100.0 and (not snapshot.get("protection_styles", []).has(monster_style) or rng.randf() >= 0.8):
				# A raging monster hits harder as it nears death (applied before DR, like the live
				# loop) — gated on the passive, exactly as CombatManager gates it.
				var raw_taken: float = float(their_roll["damage"]) * (1.0 + float(against.damage_percent) / 100.0)
				if passives.has("enrage"):
					raw_taken *= CombatFormulas.enrage_multiplier(monster_hp / monster_hp_max, ENRAGE_HP_FRACTION, ENRAGE_MULTIPLIER)
				# Clamped for the same reason as the live loop: an unbounded reduction would make
				# the multiplier negative and every hit a heal.
				var taken: float = raw_taken * (1.0 - clampf(player_dr, 0.0, 90.0) / 100.0)
				taken *= (1.0 + float(hazard.get("enemy_damage_percent", 0.0)) / 100.0)
				var special: Dictionary = _special(monster.get("specials", []), rng)
				if not special.is_empty():
					taken = maxi(1, floori(taken * float(special.get("damage_multiplier", 1))))
					_add_special_status(player_effects, special, rng, {}, resistance, true)
				var landed: float = maxf(0.0, floorf(taken))
				hp -= landed
				# Venom: a hit that deals damage may poison the player, through their resistance.
				if landed > 0.0 and passives.has("venomous") and rng.randf() < MonsterMechanics.VENOM_CHANCE:
					var venom: Dictionary = MonsterMechanics.venom_status(int((view["monster"] as Dictionary).get("max_hit", 1)))
					_apply_player_status(player_effects, str(venom["id"]), float(venom["duration"]),
						float(venom["damage_per_tick"]), rng, resistance)
				# Lifedrain: the monster heals a share of what it dealt, capped at its max HP.
				if landed > 0.0 and monster_hp > 0.0 and passives.has("lifedrain"):
					monster_hp = minf(monster_hp_max, monster_hp + float(MonsterMechanics.lifedrain_heal(int(landed))))
				if monster_hp > 0.0 and passives.has("regeneration"):
					monster_hp = minf(monster_hp_max, monster_hp + maxf(1.0, monster_hp_max * ENEMY_REGEN_FRACTION))
		# Auto Eat is evaluated after attacks, like the live loop.
		var meal: Dictionary = _auto_eat(snapshot, hp, max_hp)
		if int(meal["eaten"]) > 0:
			food += int(meal["eaten"])
			hp = minf(max_hp, hp + float(meal["heal"]))
		seconds += STEP_SECONDS
	return {"hp_after": hp, "seconds": seconds, "food": food, "damage": damage,
		"kills": kills, "player_died": hp <= 0.0, "timed_out": false, "phases_fired": int(view["fired"])}

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
	var chosen_id: String = ""
	# Sorted by heal so the first food that covers the gap is the cheapest such food, which is
	# what the live manager does.
	var ids: Array = foods.keys()
	ids.sort_custom(func(a, b): return int(foods[a]) < int(foods[b]))
	for food_id in ids:
		if bool(snapshot.get("finite_supplies", false)) and int(snapshot.get("food_counts", {}).get(food_id, 0)) <= 0: continue
		var heal: int = int(foods[food_id])
		if best < 0:
			best = heal
			chosen = heal
			chosen_id = str(food_id)
		if heal >= missing:
			chosen = heal
			chosen_id = str(food_id)
			break
	if chosen_id == "": return none
	if bool(snapshot.get("finite_supplies", false)): snapshot.food_counts[chosen_id] -= 1
	var efficiency: float = (float(AUTO_EAT_EFFICIENCY.get(tier, 1.0)) + float(snapshot.get("auto_eat_efficiency_percent", 0)) / 100.0) \
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
static func _assumptions(snapshot: Dictionary = {}) -> Array[String]:
	return [
		"Finite mode: each trial uses equipped foods and owned quantities; prayer or authored attack-cost depletion ends the trial." if bool(snapshot.get("finite_supplies", false)) else "Unlimited owned food and prayer points; consumption rates are not a supply runway.",
		"Every fight starts at full HP, so repeated dungeon trials stay comparable.",
		"A fight that reaches %d seconds is counted as a loss." % int(FIGHT_SECONDS_CEILING),
		"Ammo/runes use weapon attack_cost_items; attacks without authored costs are free, matching live combat.",
		"Level-ups, potion charges and loot drops are not simulated.",
	]

static func _special(definitions: Array, rng: RandomNumberGenerator) -> Dictionary:
	for definition in definitions:
		if definition is Dictionary and not definition.is_empty() and rng.randf() * 100.0 <= float(definition.get("trigger_chance", 10)): return definition
	return {}

## A special attack's status. Player-targeted ones go through the player's status resistance
## (as CombatManager.apply_status does); monster-targeted ones respect the monster's immunity.
static func _add_special_status(effects: Array, special: Dictionary, rng: RandomNumberGenerator, target: Dictionary,
		resistance: Dictionary = {}, to_player: bool = false) -> void:
	var id: String = str(special.get("applies_status", ""))
	if id == "" or bool(target.get("is_immune_to_effects", false)) or rng.randf() * 100.0 > float(special.get("status_chance", 100)): return
	var duration: float = float(special.get("status_duration", 3))
	var per_tick: float = float(special.get("status_damage_per_tick", 0))
	if to_player:
		_apply_player_status(effects, id, duration, per_tick, rng, resistance)
		return
	var effect: StatusEffect = StatusEffect.create(id, duration, per_tick)
	if effect.blocks_attack() and not bool(target.get("can_be_stunned", true)): return
	effects.append(effect)

## A status landing on the player: a poison/burn/stun-family status is shortened, or resisted
## outright, by the snapshot's resistance for that family. Like the live loop, the roll is
## consumed only when that resistance is above zero.
static func _apply_player_status(effects: Array, id: String, duration: float, per_tick: float,
		rng: RandomNumberGenerator, resistance: Dictionary) -> void:
	var family: String = MonsterMechanics.status_family(id)
	if family != "":
		var percent: float = float(resistance.get(family, 0.0))
		if percent > 0.0:
			duration = MonsterMechanics.resisted_duration(id, duration, percent, rng.randf())
			if duration <= 0.0:
				return
	effects.append(StatusEffect.create(id, duration, per_tick))

## The monster as it fights after `fired` phases, plus every fight number derived from it: the
## triangle both ways (it depends on the monster's style), the player's evasion against that
## style, the monster's interval and hit range, and its passives.
static func _monster_view(snapshot: Dictionary, player: Dictionary, monster: Dictionary, fired: int) -> Dictionary:
	var current: Dictionary = MonsterMechanics.effective(monster, fired) if fired > 0 else monster
	var style: String = str(player.get("style", "melee"))
	var monster_style: String = str(current.get("attack_type", "melee"))
	var mode_config: Dictionary = snapshot.get("mode_config", {})
	var hazard: Dictionary = snapshot.get("hazard", {})
	var triangle: Dictionary = CombatFormulas.triangle(style, monster_style, mode_config)
	var max_hit: int = maxi(1, floori(float(player.get("max_hit", 1)) * (1.0 + float(triangle.damage_percent) / 100.0)))
	var monster_max_hit: int = maxi(1, int(current.get("max_hit", 1)))
	return {
		"fired": fired,
		"monster": current,
		"passives": current.get("passives", []),
		"monster_style": monster_style,
		# Flat hit-chance points, exactly like the live loop (not rating points).
		"player_hit_bonus": float(hazard.get("player_accuracy_percent", 0.0)) + float(triangle.accuracy_percent),
		"max_hit": max_hit,
		"min_hit": CombatFormulas.min_hit(max_hit, float(player.get("min_hit_percent", 0.0)),
			float(player.get("min_hit_flat", 0.0))),
		"player_interval": maxf(0.1, float(player.get("attack_interval", 3.0))),
		"monster_interval": maxf(MONSTER_INTERVAL_FLOOR, float(current.get("attack_speed", 3.0))),
		"monster_max_hit": monster_max_hit,
		"monster_min_hit": CombatFormulas.min_hit(monster_max_hit,
			float(current.get("min_hit_percent", 0.0)), float(current.get("min_hit_flat", 0.0))),
		"player_evasion": maxi(0, int(float(_player_evasion(player, monster_style)) * (1.0 + float(hazard.get("player_evasion_percent", 0.0)) / 100.0))),
		"monster_triangle": CombatFormulas.triangle(monster_style, style, mode_config),
	}

## Fire every boss phase now due at this HP fraction, once each and in order, as
## CombatManager._fire_due_phases() does. A phase status goes to the player through their
## resistance; the monster's own immunity never gates it. Returns the (possibly new) view.
static func _fire_phases(snapshot: Dictionary, player: Dictionary, monster: Dictionary, view: Dictionary,
		hp_fraction: float, player_effects: Array, rng: RandomNumberGenerator) -> Dictionary:
	var phases: Array = monster.get("phases", [])
	if phases.is_empty():
		return view
	var fired: int = int(view["fired"])
	var due: int = MonsterMechanics.phases_due(phases, fired, hp_fraction)
	if due == fired:
		return view
	while fired < due:
		var status: Dictionary = ((phases[fired] as Dictionary).get("effects", {}) as Dictionary).get("apply_status", {})
		fired += 1
		if not status.is_empty():
			_apply_player_status(player_effects, str(status.get("id", "")), float(status.get("duration", 3.0)),
				float(status.get("damage_per_tick", 0.0)), rng, snapshot.get("status_resistance", {}))
	return _monster_view(snapshot, player, monster, fired)

static func _blocked(effects: Array) -> bool:
	for effect in effects: if effect.blocks_attack(): return true
	return false

static func _tick_statuses(effects: Array, seconds: float) -> float:
	var damage: float = 0
	for effect in effects.duplicate():
		damage += effect.tick(seconds)
		if effect.is_expired(): effects.erase(effect)
	return damage
