extends Node
## CombatManager — tick-based combat state machine: monster spawn, player/monster attack
## timers, damage, status effects, loot, dungeon progression, auto-eat, defeat.
##
## Preparation over reflex (design pillar): there is no real-time input during a fight.
## The player prepares a loadout, prayers, food and style, then commits. The only in-fight
## control is retreat, which is always available and never punishes the player beyond
## stopping the fight.
##
## Offline safety (documented policy):
##   * Combat continues offline only if the player enabled it in settings.
##   * A defeat permanently ends the offline session (settings.offline_combat_stops_on_defeat).
##     Endless automatic deaths are therefore impossible.
##   * Offline stepping is bounded by a step budget; running out reports the time actually
##     processed rather than silently truncating rewards.
##   * Defeat never destroys equipment. The worst case is that one item is returned to
##     storage, and protected items are excluded from that roll entirely.

enum State { IDLE, FIGHTING, RESPAWNING, DEAD }

const OFFLINE_STEP: float = 1.0
const MAX_OFFLINE_STEPS: int = 120_000
const DEFAULT_RESPAWN: float = 3.0
const EXPEDITION_COMBAT_LEVEL: int = 60
const EXPEDITION_CHARTER: String = "expedition_charter"
## Fraction of max HP a monster with the "regeneration" passive heals per own attack.
const ENEMY_REGEN_FRACTION: float = 0.02
## Monster passive ids the engine understands (data may list more only after engine support).
const KNOWN_MONSTER_PASSIVES: Array[String] = ["regeneration"]

var state: int = State.IDLE
var context: Dictionary = {}          # {type, id, monsters:[...], index, endless, attack_style}
var current_monster_id: String = ""
var monster_hp: int = 0
var monster_max_hp: int = 0
var player_max_hp: float = 100.0
var player_hp: float = 100.0

var player_attack_timer: float = 0.0
var player_attack_interval: float = 3.0
var monster_attack_timer: float = 0.0
var monster_attack_interval: float = 3.0
var respawn_timer: float = 0.0

var player_effects: Array = []
var monster_effects: Array = []

var attack_style: String = "melee"    # melee | ranged | magic
var melee_style: String = "stab"      # stab | slash | block

var kills_this_session: int = 0
var deaths_this_session: int = 0
var last_defeat_reason: String = ""

var _rng := RandomNumberGenerator.new()
var combat_enabled: bool = true

# Auto Eat thresholds: [threshold%, heal-to%, efficiency%]
const AUTO_EAT = {
	1: {"threshold": 20.0, "heal_to": 40.0, "efficiency": 60.0},
	2: {"threshold": 30.0, "heal_to": 60.0, "efficiency": 80.0},
	3: {"threshold": 40.0, "heal_to": 80.0, "efficiency": 100.0},
}

func _ready() -> void:
	_rng.randomize()
	player_max_hp = _compute_max_hp()
	player_hp = player_max_hp
	set_loadout(PlayerData.ability_loadout)

func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value

# --- Bus wrappers ---------------------------------------------------------------------------
# Combat emits a lot of UI events (every attack). During a silent offline catch-up these must
# not fire, or a 24-hour fight would produce tens of thousands of UI notifications. These tiny
# typed wrappers are the single place that decides whether anyone is watching.
func _sig_combat_started(ctx: Dictionary) -> void:
	if not SimulationMode.is_silent():
		EventBus.combat_started.emit(ctx)

func _sig_combat_ended(reason: String) -> void:
	if not SimulationMode.is_silent():
		EventBus.combat_ended.emit({"reason": reason})

func _sig_monster_spawned(monster_id: String, hp: int) -> void:
	if not SimulationMode.is_silent():
		EventBus.monster_spawned.emit(monster_id, hp)

func _sig_player_special(sa_id: String) -> void:
	if not SimulationMode.is_silent():
		EventBus.player_special_attack.emit(sa_id)

func _sig_monster_special(sa_id: String) -> void:
	if not SimulationMode.is_silent():
		EventBus.monster_special_attack.emit(sa_id)

func _sig_player_attacked(damage: int, is_crit: bool) -> void:
	if not SimulationMode.is_silent():
		EventBus.player_attacked.emit(damage, is_crit)

func _sig_monster_attacked(damage: int) -> void:
	if not SimulationMode.is_silent():
		EventBus.monster_attacked.emit(damage)

func _sig_monster_killed(monster_id: String) -> void:
	if not SimulationMode.is_silent():
		EventBus.monster_killed.emit(monster_id)

func _sig_player_died(payload: Dictionary) -> void:
	if not SimulationMode.is_silent():
		EventBus.player_died.emit(payload)

func _sig_dungeon_completed(dungeon_id: String) -> void:
	if not SimulationMode.is_silent():
		EventBus.dungeon_completed.emit(dungeon_id)

func _sig_status(target: String, effect_id: String, applied: bool) -> void:
	if SimulationMode.is_silent():
		return
	if applied:
		EventBus.status_effect_applied.emit(target, effect_id)
	else:
		EventBus.status_effect_expired.emit(target, effect_id)

func _sig_ability_triggered(ability_id: String) -> void:
	if not SimulationMode.is_silent():
		EventBus.ability_triggered.emit(ability_id)

# =========================================================================
#  Control
# =========================================================================

## ctx: {type: "area"|"dungeon"|"slayer_area", id, monsters: [], endless: bool,
##       attack_style, melee_style, shard_item}
func is_expedition(dungeon_id: String) -> bool:
	var dungeon: Dictionary = DataLoader.get_dungeon(dungeon_id)
	var levels: Array = dungeon.get("level_range", [])
	return levels.size() > 0 and int(levels[0]) >= EXPEDITION_COMBAT_LEVEL

func expedition_unlock_reason() -> String:
	if PlayerData.get_combat_level() < EXPEDITION_COMBAT_LEVEL:
		return "Reach combat level %d" % EXPEDITION_COMBAT_LEVEL
	if not Quests.is_claimed(EXPEDITION_CHARTER):
		return "Claim the Expedition Charter task"
	return ""

func start_combat(ctx: Dictionary) -> bool:
	if str(ctx.get("type", "")) == "dungeon" and is_expedition(str(ctx.get("id", ""))):
		var reason: String = expedition_unlock_reason()
		if reason != "":
			EventBus.notify("Expedition locked: %s" % reason, "warn")
			return false
	if state != State.IDLE and state != State.DEAD:
		EventBus.notify("Already fighting — retreat first.", "warn")
		return false
	if (ctx.get("monsters", []) as Array).is_empty():
		EventBus.notify("Nothing to fight here yet.", "warn")
		return false
	context = ctx
	context["index"] = 0
	attack_style = str(ctx.get("attack_style", attack_style))
	melee_style = str(ctx.get("melee_style", melee_style))
	player_max_hp = _compute_max_hp()
	if player_hp <= 0.0:
		player_hp = player_max_hp
	player_hp = minf(player_hp, player_max_hp)
	player_attack_timer = 0.0
	monster_attack_timer = 0.0
	state = State.FIGHTING
	ProgressTracker.record_region_visit(str(ctx.get("id", "")))
	_sig_combat_started(ctx)
	EventBus.activity_changed.emit()
	_spawn_current()
	return true

## Retreat. Always available, never punished.
func stop_combat(reason: String = "") -> void:
	var was_active: bool = state != State.IDLE
	state = State.IDLE
	current_monster_id = ""
	context = {}
	player_effects.clear()
	monster_effects.clear()
	# A speedup still waiting to be spent belongs to the fight that earned it.
	_ability_interval_percent = 0.0
	respawn_timer = 0.0
	if was_active:
		_sig_combat_ended("retreat" if reason == "" else reason)
		EventBus.activity_changed.emit()

func _monster_sequence() -> Array:
	return context.get("monsters", [])

func _spawn_current() -> void:
	var seq: Array = _monster_sequence()
	if seq.is_empty():
		_complete_combat()
		return
	# Open regions are endless: a random spawn from the pool each time.
	if bool(context.get("endless", false)):
		_spawn_monster(str(seq[_rng.randi_range(0, seq.size() - 1)]))
		return
	var idx: int = int(context.get("index", 0))
	if idx >= seq.size():
		_complete_combat()
		return
	_spawn_monster(str(seq[idx]))

func _spawn_monster(monster_id: String) -> void:
	if DataLoader.get_monster(monster_id).is_empty():
		# Content guard: a bad reference ends the fight instead of fighting a ghost.
		push_warning("CombatManager: unknown monster '%s'" % monster_id)
		_complete_combat()
		return
	current_monster_id = monster_id
	var m: Dictionary = DataLoader.get_monster(monster_id)
	monster_max_hp = maxi(1, int(m.get("hitpoints", 10)))
	monster_hp = monster_max_hp
	monster_attack_interval = maxf(0.25, float(m.get("attack_speed", 3.0)))
	monster_attack_timer = 0.0
	player_attack_timer = 0.0
	player_attack_interval = ModifierManager.get_attack_interval(EquipmentManager.get_weapon_attack_speed())
	monster_effects.clear()
	state = State.FIGHTING
	_sig_monster_spawned(monster_id, monster_hp)
	SimulationMode.bump("encounters", monster_id, 1.0)

# =========================================================================
#  Tick
# =========================================================================

func _process(delta: float) -> void:
	if SimulationMode.is_silent():
		return   # offline catch-up drives tick() explicitly
	tick(delta)

func tick(delta: float) -> void:
	if not combat_enabled or delta <= 0.0:
		return
	if state == State.IDLE:
		return
	_tick_player_effects(delta)
	_tick_monster_effects(delta)
	match state:
		State.FIGHTING:
			_tick_fighting(delta)
		State.RESPAWNING:
			respawn_timer -= delta
			if respawn_timer <= 0.0:
				if not bool(context.get("endless", false)):
					context["index"] = int(context.get("index", 0)) + 1
				_spawn_current()
		State.DEAD:
			# A defeated character does not keep fighting. The player must act.
			pass

func _tick_fighting(delta: float) -> void:
	if _is_player_stunned():
		return
	player_attack_interval = maxf(0.25, ModifierManager.get_attack_interval(EquipmentManager.get_weapon_attack_speed()))
	# A Flurry-class ability is a one-swing speedup. The interval is recomputed from
	# ModifierManager on every tick, so a speedup held anywhere else would be overwritten before it
	# ever reached a swing; it is spent here instead. Positive percent = faster, as in
	# ModifierManager.get_attack_interval.
	player_attack_interval = maxf(0.25, player_attack_interval * (1.0 - _ability_interval_percent / 100.0))
	_ability_interval_percent = 0.0
	if bool(context.get("raid", false)):
		player_attack_interval *= 0.5   # everyone attacks at 2x speed in the raid
	monster_attack_interval = maxf(0.25, float(DataLoader.get_monster(current_monster_id).get("attack_speed", 3.0)))
	player_attack_timer += delta
	monster_attack_timer += delta
	var guard: int = 0
	while player_attack_timer >= player_attack_interval and state == State.FIGHTING and guard < 512:
		guard += 1
		player_attack_timer -= player_attack_interval
		_player_attack()
	guard = 0
	while monster_attack_timer >= monster_attack_interval and state == State.FIGHTING and guard < 512:
		guard += 1
		monster_attack_timer -= monster_attack_interval
		_monster_attack()
	_auto_eat()

# =========================================================================
#  Stats
# =========================================================================

func _compute_max_hp() -> float:
	return maxf(10.0, float(PlayerData.get_level("hitpoints")) * 10.0)

func _player_effective(skill_id: String) -> int:
	return PlayerData.get_level(skill_id) + ModifierManager.get_hidden_levels(skill_id)

func _player_accuracy(style: String) -> int:
	var attack_key: String = "stab"
	if style == "melee":
		attack_key = melee_style
	elif style == "ranged":
		attack_key = "ranged_attack"
	else:
		attack_key = "magic_attack"
	var eff: int = 1
	match style:
		"melee":
			eff = _player_effective("attack")
		"ranged":
			eff = _player_effective("ranged")
		"magic":
			eff = _player_effective("magic")
	return CombatFormulas.accuracy_rating(eff, EquipmentManager.get_attack_bonus(attack_key),
		ModifierManager.get_accuracy_percent(style))

func _player_max_hit(style: String) -> int:
	if style == "magic":
		var eff_magic: int = _player_effective("magic")
		return CombatFormulas.max_hit_magic(10.0, float(EquipmentManager.get_strength_bonus("magic")),
			eff_magic, ModifierManager.get_max_hit_percent("magic"), ModifierManager.get_max_hit_flat("magic"))
	var strength_skill: String = "strength" if style == "melee" else "ranged"
	var eff: int = _player_effective(strength_skill)
	var sb: float = float(EquipmentManager.get_strength_bonus(style))
	return CombatFormulas.max_hit_melee_ranged(PlayerData.game_mode, eff, sb,
		ModifierManager.get_max_hit_percent(style), ModifierManager.get_max_hit_flat(style))

func _monster_evasion_for(style: String) -> int:
	var m: Dictionary = DataLoader.get_monster(current_monster_id)
	match style:
		"melee":
			return int(m.get("melee_evasion", 10))
		"ranged":
			return int(m.get("ranged_evasion", 10))
		_:
			return int(m.get("magic_evasion", 10))

func _player_evasion_for(monster_style: String) -> int:
	var eff_def: int = _player_effective("defence")
	if monster_style == "magic":
		return CombatFormulas.evasion_magic(eff_def, _player_effective("magic"),
			EquipmentManager.get_defence_bonus("magic"), ModifierManager.get_evasion_percent("magic"))
	return CombatFormulas.evasion_melee_ranged(eff_def, EquipmentManager.get_defence_bonus(monster_style),
		ModifierManager.get_evasion_percent(monster_style))

## Public read-only summary so the UI can show stat comparisons without duplicating maths.
func player_combat_summary() -> Dictionary:
	return {
		"max_hp": _compute_max_hp(),
		"hp": player_hp,
		"style": attack_style,
		"melee_style": melee_style,
		"accuracy": _player_accuracy(attack_style),
		"max_hit": _player_max_hit(attack_style),
		"attack_interval": maxf(0.25, ModifierManager.get_attack_interval(EquipmentManager.get_weapon_attack_speed())),
		"damage_reduction": ModifierManager.get_damage_reduction(),
		"evasion": {
			"melee": _player_evasion_for("melee"),
			"ranged": _player_evasion_for("ranged"),
			"magic": _player_evasion_for("magic"),
		},
	}

## Stat comparison against the current target, derived from the live model.
func target_comparison() -> Dictionary:
	if current_monster_id == "":
		return {}
	var m: Dictionary = DataLoader.get_monster(current_monster_id)
	var m_style: String = str(m.get("attack_type", "melee"))
	var player_acc: int = _player_accuracy(attack_style)
	var player_ev: int = _player_evasion_for(m_style)
	return {
		"monster_id": current_monster_id,
		"monster_name": str(m.get("name", current_monster_id)),
		"monster_level": int(m.get("combat_level", 1)),
		"monster_damage_type": m_style,
		"monster_max_hit": int(m.get("max_hit", 0)),
		"monster_damage_reduction": float(m.get("damage_reduction", 0.0)),
		"your_hit_chance_percent": CombatFormulas.chance_to_hit(float(player_acc), float(_monster_evasion_for(attack_style))),
		"their_hit_chance_percent": CombatFormulas.chance_to_hit(float(m.get("accuracy_rating", 10)), float(player_ev)),
		"your_max_hit": _player_max_hit(attack_style),
	}

# =========================================================================
#  Attacks
# =========================================================================

func _player_attack() -> void:
	if state != State.FIGHTING:
		return
	# Abilities: the cooldown is spent on every player attack, before any roll, so the cost of an
	# ability is the same whether or not the swing connects.
	_decrement_ability_cooldowns()
	PrayerManager.spend_for_attack()   # active prayers cost points per attack
	PotionManager.consume_charge()
	var m: Dictionary = DataLoader.get_monster(current_monster_id)
	var m_style: String = str(m.get("attack_type", "melee"))
	var acc: int = _player_accuracy(attack_style)
	var eva: int = _monster_evasion_for(attack_style)
	var hit_chance: float = CombatFormulas.chance_to_hit(float(acc), float(eva))
	# Combat triangle (player attacks monster).
	var mode_cfg: Dictionary = DataLoader.game_modes.get(PlayerData.game_mode, {})
	var tri: Dictionary = CombatFormulas.triangle(attack_style, m_style, mode_cfg)
	hit_chance = clampf(hit_chance + float(tri["accuracy_percent"]), 0.0, 100.0)
	# Open-region hazard: hostile ground costs accuracy.
	hit_chance = clampf(hit_chance + float(_active_hazard().get("player_accuracy_percent", 0.0)), 0.0, 100.0)
	if _rng.randf() * 100.0 > hit_chance:
		return
	# Abilities roll only on a landed hit, and at most one of them takes the swing.
	_roll_abilities_for_test()
	var ab: Dictionary = DataLoader.get_ability(_last_ability_fired)
	var ab_effect: Dictionary = ab.get("effect", {})
	# apply_status and interval_percent need no damage number, so they land right here; the three
	# damage-shaped effects are applied below, where the number they scale exists.
	_apply_ability_status(ab)
	_ability_interval_percent += float(ab_effect.get("interval_percent", 0.0))
	var mh: int = maxi(1, _player_max_hit(attack_style))
	# max_hit_percent is a percentage of this swing's max hit, the same convention (and the same
	# place) as the combat triangle below.
	mh = maxi(1, int(floor(float(mh) * (1.0 + float(ab_effect.get("max_hit_percent", 0.0)) / 100.0))))
	mh = maxi(1, int(floor(float(mh) * (1.0 + float(tri["damage_percent"]) / 100.0))))
	var mn: int = CombatFormulas.min_hit(mh,
		ModifierManager.get_modifier(ModifierKeys.MIN_HIT_PERCENT_OF_MAX) / 100.0,
		ModifierManager.get_modifier(ModifierKeys.MIN_HIT_FLAT))
	var res: Dictionary = CombatFormulas.roll_damage(_rng, mn, mh, float(m.get("damage_reduction", 0.0)),
		ModifierManager.get_crit_chance() + float(ab_effect.get("crit_chance_percent", 0.0)),
		ModifierManager.get_crit_multiplier())
	var dmg: int = int(res["damage"])
	var is_crit: bool = bool(res["is_crit"])
	# Weapon special attack: replaces the normal attack and may apply a status.
	var sa: Dictionary = _roll_special_attack(EquipmentManager.get_weapon_special_attack())
	if not sa.is_empty():
		dmg = maxi(1, int(floor(float(dmg) * float(sa.get("damage_multiplier", 1.0)))))
		_sig_player_special(str(sa.get("id", "")))
		_apply_special_status(sa, "monster")
		var heal_frac: float = float(sa.get("heal_fraction", 0.0))
		if heal_frac > 0.0:
			player_hp = minf(player_hp + float(dmg) * heal_frac, _compute_max_hp())
	# heal_on_hit_fraction is a FRACTION (0..1) of the damage this swing dealt, the same precedent
	# as special_attacks.json's heal_fraction — never a percent.
	var ab_heal: float = float(ab_effect.get("heal_on_hit_fraction", 0.0))
	if ab_heal > 0.0:
		_apply_ability_heal(float(dmg) * ab_heal)
	apply_damage_to_monster(dmg)
	_sig_player_attacked(dmg, is_crit)
	_grant_combat_xp(dmg)
	var ls: float = ModifierManager.get_life_steal()
	if ls > 0.0:
		player_hp = minf(player_hp + float(dmg) * ls / 100.0, _compute_max_hp())

func _monster_attack() -> void:
	if state != State.FIGHTING:
		return
	var m: Dictionary = DataLoader.get_monster(current_monster_id)
	var m_style: String = str(m.get("attack_type", "melee"))
	var acc: float = float(m.get("accuracy_rating", 10))
	var eva: int = _player_evasion_for(m_style)
	# Open-region hazard: fouled footing costs evasion rating.
	eva = maxi(0, int(float(eva) * (1.0 + float(_active_hazard().get("player_evasion_percent", 0.0)) / 100.0)))
	var hit_chance: float = CombatFormulas.chance_to_hit(acc, float(eva))
	var mode_cfg: Dictionary = DataLoader.game_modes.get(PlayerData.game_mode, {})
	var tri: Dictionary = CombatFormulas.triangle(m_style, attack_style, mode_cfg)
	hit_chance = clampf(hit_chance + float(tri["accuracy_percent"]), 0.0, 100.0)
	if _rng.randf() * 100.0 > hit_chance:
		return
	# Prayers: Protect from X gives an 80% dodge chance.
	if _has_protection_prayer(m_style):
		if _rng.randf() < 0.8:
			return
	var raw: float = float(_rng.randi_range(1, maxi(1, int(m.get("max_hit", 1)))))
	raw *= (1.0 + float(tri["damage_percent"]) / 100.0)
	# Open-region hazard: hostile ground hits harder.
	raw *= (1.0 + float(_active_hazard().get("enemy_damage_percent", 0.0)) / 100.0)
	var dr: float = ModifierManager.get_damage_reduction()
	var dmg: int = maxi(0, int(floor(raw * (1.0 - dr / 100.0))))
	var sa: Dictionary = _roll_special_attack_from_ids(m.get("special_attacks", []))
	if not sa.is_empty():
		dmg = maxi(1, int(floor(float(dmg) * float(sa.get("damage_multiplier", 1.0)))))
		_sig_monster_special(str(sa.get("id", "")))
		_apply_special_status(sa, "player")
	player_hp -= float(dmg)
	_sig_monster_attacked(dmg)
	# Regenerating monsters knit wounds on every own attack while still standing.
	if monster_hp > 0 and (m.get("passives", []) as Array).has("regeneration"):
		monster_hp = mini(monster_max_hp, monster_hp + maxi(1, int(float(monster_max_hp) * ENEMY_REGEN_FRACTION)))
	if player_hp <= 0.0:
		_player_death(m.get("name", current_monster_id))

## The current open-region hazard, if any (dungeons and towns are sheltered).
func _active_hazard() -> Dictionary:
	if str(context.get("type", "")) != "area":
		return {}
	return DataLoader.areas.get(str(context.get("id", "")), {}).get("hazard", {})

func _has_protection_prayer(style: String) -> bool:
	var want: String = {"melee": "protect_from_melee", "ranged": "protect_from_ranged", "magic": "protect_from_magic"}.get(style, "")
	return want != "" and PlayerData.active_prayers.has(want)

func apply_damage_to_monster(dmg: int) -> void:
	if dmg <= 0 or state != State.FIGHTING:
		return
	monster_hp -= dmg
	if monster_hp <= 0:
		monster_hp = 0
		_on_monster_death()

func _grant_combat_xp(damage: int) -> void:
	PlayerData.add_xp("hitpoints", CombatFormulas.hitpoints_xp(float(damage)))
	if attack_style == "melee":
		match melee_style:
			"stab": PlayerData.add_xp("attack", CombatFormulas.style_xp(float(damage)))
			"slash": PlayerData.add_xp("strength", CombatFormulas.style_xp(float(damage)))
			"block": PlayerData.add_xp("defence", CombatFormulas.style_xp(float(damage)))
	else:
		PlayerData.add_xp(attack_style, CombatFormulas.style_xp(float(damage)))
	if not PlayerData.active_prayers.is_empty():
		PlayerData.add_xp("prayer", CombatFormulas.prayer_xp(float(damage), float(PlayerData.active_prayers.size())))

# =========================================================================
#  Special attacks
# =========================================================================

func _roll_special_attack(sa_def: Dictionary) -> Dictionary:
	if sa_def.is_empty():
		return {}
	if _rng.randf() * 100.0 > float(sa_def.get("trigger_chance", 10.0)):
		return {}
	return sa_def

func _roll_special_attack_from_ids(ids: Array) -> Dictionary:
	for sa_id in ids:
		var sa_def: Dictionary = DataLoader.get_special_attack(str(sa_id))
		if not sa_def.is_empty() and _rng.randf() * 100.0 <= float(sa_def.get("trigger_chance", 10.0)):
			return sa_def
	return {}

func _apply_special_status(sa: Dictionary, target: String) -> void:
	var status_id: String = str(sa.get("applies_status", ""))
	if status_id == "":
		return
	if _rng.randf() * 100.0 > float(sa.get("status_chance", 100.0)):
		return
	apply_status(target, status_id, float(sa.get("status_duration", 3.0)), float(sa.get("status_damage_per_tick", 0.0)))

# =========================================================================
#  Death & loot
# =========================================================================

func _on_monster_death() -> void:
	var m: Dictionary = DataLoader.get_monster(current_monster_id)
	_sig_monster_killed(current_monster_id)
	kills_this_session += 1
	PlayerData.discover_monster(current_monster_id)
	ProgressTracker.record_kill(current_monster_id)
	SimulationMode.bump(SimulationMode.BUCKET_KILLS, current_monster_id, 1.0)
	_grant_loot(m)
	var on_task: bool = str(PlayerData.slayer_task.get("monster_id", "")) == current_monster_id
	var slayer_xp: float = CombatFormulas.slayer_xp_for_kill(float(m.get("hitpoints", 0)), on_task, str(context.get("type", "")) == "slayer_area")
	if slayer_xp > 0.0:
		PlayerData.add_xp("slayer", slayer_xp)
	var respawn: float = maxf(0.25, float(m.get("respawn_time", DEFAULT_RESPAWN))
		* (1.0 - ModifierManager.get_modifier(ModifierKeys.RESPWAN_TIME_PERCENT) / 100.0))
	if bool(context.get("endless", false)):
		_spawn_current()
	else:
		state = State.RESPAWNING
		respawn_timer = respawn

func _grant_loot(m: Dictionary) -> void:
	var gp_pct: float = 1.0 + ModifierManager.get_modifier(ModifierKeys.GLOBAL_GP_PERCENT) / 100.0
	var dbl: float = ModifierManager.get_modifier(ModifierKeys.GLOBAL_DOUBLE_LOOT_PERCENT)
	for drop in m.get("loot_table", []):
		if typeof(drop) != TYPE_DICTIONARY:
			continue
		if _rng.randf() > float(drop.get("chance", 1.0)):
			continue
		var qty: int = maxi(1, int(drop.get("quantity", 1)))
		var lo: int = int(drop.get("min_quantity", 0))
		if lo > 0:
			qty = _rng.randi_range(lo, qty)
		if _rng.randf() * 100.0 < dbl:
			qty *= 2
		if bool(drop.get("is_currency", false)):
			match str(drop.get("currency_id", "gp")):
				"slayer_coins": PlayerData.add_slayer_coins(float(qty))
				"abyssal_coins": PlayerData.add_abyssal_coins(float(qty))
				_: PlayerData.add_gp(float(qty) * gp_pct)
			continue
		var item_id: String = str(drop.get("item_id", ""))
		if item_id == "":
			continue
		# Loot uses the guaranteed path: a rare drop must never be lost to a full bank.
		BankManager.add_item_guaranteed(item_id, qty)
		SimulationMode.bump(SimulationMode.BUCKET_ITEMS_PRODUCED, item_id, float(qty))
		if float(drop.get("chance", 1.0)) <= SimulationMode.RARE_DROP_CHANCE_THRESHOLD:
			SimulationMode.bump(SimulationMode.BUCKET_RARE_DROPS, item_id, float(qty))
	var bone: String = str(m.get("bone_type", ""))
	if bone != "":
		BankManager.add_item_guaranteed(bone, 1)
	var shard: String = str(context.get("shard_item", ""))
	if shard != "":
		BankManager.add_item_guaranteed(shard, 1)
	PetManager.roll_for_combat()

## Damage taken outside combat (a failed skill action). Never kills below 1 HP.
func damage_player_out_of_combat(amount: float, reason: String = "") -> void:
	if amount <= 0.0:
		return
	player_max_hp = _compute_max_hp()
	player_hp = maxf(1.0, player_hp - amount)
	if reason != "":
		EventBus.notify("%s (−%d HP)" % [reason, int(amount)], "warn")

## Defeat policy, stated explicitly:
##   * the fight ends immediately;
##   * nothing is destroyed;
##   * in the default mode the worst outcome is that ONE unequipped-protected,
##     non-consumable, non-companion slot is returned to storage;
##   * hardcore mode flags the character for deletion by the shell, which asks first.
func _player_death(killer: String) -> void:
	if state == State.DEAD:
		return
	player_hp = 0.0
	state = State.DEAD
	deaths_this_session += 1
	last_defeat_reason = killer
	ProgressTracker.record_death()
	SimulationMode.bump(SimulationMode.BUCKET_DEATHS, "defeat", 1.0)
	var lost: String = _lose_one_item()
	_sig_player_died({"lost_item": lost, "killer": killer})
	EventBus.activity_changed.emit()
	if not SimulationMode.is_silent():
		EventBus.notify("Defeated by %s.%s" % [killer, "" if lost == "" else " You dropped %s (returned to storage)." % lost], "error")
	stop_combat("defeat")

## Choose at most one item to send back to storage. Protected items and the weapon are
## excluded so a defeat can never strip the player's only weapon or a cherished drop.
func _lose_one_item() -> String:
	if PlayerData.active_prayers.has("protect_item"):
		return ""
	var candidates: Array[int] = []
	for slot in EquipmentManager.slots.keys():
		var slot_index: int = int(slot)
		if slot_index == ItemData.EquipmentSlot.WEAPON:
			continue
		if slot_index == ItemData.EquipmentSlot.SUMMON_1 or slot_index == ItemData.EquipmentSlot.SUMMON_2:
			continue
		var candidate_id: String = str(EquipmentManager.slots[slot])
		if candidate_id == "" or BankManager.is_protected(candidate_id):
			continue
		candidates.append(slot_index)
	if candidates.is_empty():
		return ""
	var chosen: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var item_id: String = str(EquipmentManager.slots.get(chosen, ""))
	EquipmentManager.unequip(chosen)
	return item_id

func _complete_combat() -> void:
	if str(context.get("type", "")) == "dungeon":
		var dungeon_id: String = str(context.get("id", ""))
		var d: Dictionary = DataLoader.get_dungeon(dungeon_id)
		var first_clear: bool = not (PlayerData.completion_log.get("dungeons", {}) as Dictionary).has(dungeon_id)
		PlayerData.discover_dungeon(dungeon_id)
		ProgressTracker.record_dungeon_clear(dungeon_id)
		SimulationMode.bump(SimulationMode.BUCKET_DUNGEONS, dungeon_id, 1.0)
		_grant_reward(d.get("completion_reward", {}))
		if first_clear:
			_grant_reward(d.get("rewards_first_clear", {}))
		_sig_dungeon_completed(dungeon_id)
		if not SimulationMode.is_silent():
			EventBus.notify("Expedition complete: %s" % d.get("name", dungeon_id), "success")
	stop_combat("complete")

## Grant a {gp, items:{id:qty}} reward bundle. Rewards use the guaranteed path.
func _grant_reward(reward: Dictionary) -> void:
	if reward.is_empty():
		return
	if reward.has("gp"):
		PlayerData.add_gp(float(reward["gp"]))
	for item_id in (reward.get("items", {}) as Dictionary).keys():
		BankManager.add_item_guaranteed(str(item_id), int(reward["items"][item_id]))

func _is_player_stunned() -> bool:
	for e in player_effects:
		if e.blocks_attack():
			return true
	return false

# =========================================================================
#  Status effects
# =========================================================================

func _tick_player_effects(delta: float) -> void:
	_tick_effects(player_effects, delta, true)

func _tick_monster_effects(delta: float) -> void:
	_tick_effects(monster_effects, delta, false)

func _tick_effects(list: Array, delta: float, is_player: bool) -> void:
	var keep: Array = []
	for e in list:
		var dmg: float = e.tick(delta)
		if dmg > 0.0:
			if is_player:
				player_hp -= dmg
			else:
				monster_hp -= int(dmg)
		if not e.is_expired():
			keep.append(e)
		else:
			_sig_status("player" if is_player else "monster", e.id, false)
	list.clear()
	list.append_array(keep)
	if is_player and player_hp <= 0.0:
		_player_death("a lingering affliction")
	if not is_player and monster_hp <= 0 and state == State.FIGHTING:
		monster_hp = 0
		_on_monster_death()

func apply_status(target: String, effect_id: String, duration: float, damage_per_tick: float = 0.0) -> void:
	var e: StatusEffect = StatusEffect.create(effect_id, duration, damage_per_tick)
	if target == "player":
		player_effects.append(e)
	else:
		var m: Dictionary = DataLoader.get_monster(current_monster_id)
		if bool(m.get("is_immune_to_effects", false)):
			return
		if e.blocks_attack() and not bool(m.get("can_be_stunned", true)):
			return
		monster_effects.append(e)
	_sig_status(target, effect_id, true)

# =========================================================================
#  Auto Eat
# =========================================================================

func _auto_eat() -> void:
	var tier: int = int(PlayerData.settings.get("auto_eat_tier", 0))
	if bool(context.get("raid", false)):
		tier = maxi(tier, 2)   # Auto Eat Tier II is always active in the raid
	if tier <= 0 or not AUTO_EAT.has(tier):
		return
	var cfg: Dictionary = AUTO_EAT[tier]
	var maxhp: float = _compute_max_hp()
	var pct: float = player_hp / maxf(maxhp, 1.0) * 100.0
	var threshold: float = float(cfg["threshold"]) + ModifierManager.get_modifier(ModifierKeys.AUTO_EAT_THRESHOLD_PERCENT)
	if pct > threshold:
		return
	var food_id: String = _find_food()
	if food_id == "":
		return
	var heal: float = float(DataLoader.get_item(food_id).get("heal_amount", 0))
	var eff: float = (float(cfg["efficiency"]) + ModifierManager.get_modifier(ModifierKeys.AUTO_EAT_EFFICIENCY_PERCENT)) / 100.0
	heal *= eff * (1.0 + ModifierManager.get_modifier(ModifierKeys.FOOD_HEALING_PERCENT) / 100.0)
	if not BankManager.remove_item(food_id, 1):
		return
	player_hp = minf(player_hp + heal, maxhp)
	if not SimulationMode.is_silent():
		EventBus.notification.emit("Auto-eat: %s" % DataLoader.get_item(food_id).get("name", food_id), "info")

## Deterministic food choice: the smallest food that still fills the missing health, so a
## long fight does not burn the player's best supplies first.
func _find_food() -> String:
	var best: String = ""
	var best_heal: int = -1
	var maxhp: float = _compute_max_hp()
	var missing: float = maxf(1.0, maxhp - player_hp)
	for item_id in BankManager.items.keys():
		if DataLoader.get_item(item_id).get("item_type", "") != "food":
			continue
		if int(BankManager.items[item_id]) <= 0:
			continue
		var heal: int = int(DataLoader.get_item(item_id).get("heal_amount", 0))
		if heal <= 0:
			continue
		# Prefer the cheapest food that covers the missing health; otherwise keep the biggest.
		var covers: bool = float(heal) >= missing
		if best == "":
			best = item_id
			best_heal = heal
			continue
		var best_covers: bool = float(best_heal) >= missing
		if covers and not best_covers:
			best = item_id
			best_heal = heal
		elif covers == best_covers and heal < best_heal:
			best = item_id
			best_heal = heal
	return best

# =========================================================================
#  Offline / bounded simulation
# =========================================================================

## Advance combat by `elapsed` seconds using the same tick path, in bounded 1-second steps.
## Caller must set SimulationMode.begin() first.
## Returns {seconds_processed, steps, stopped, reason}.
func simulate_elapsed(elapsed: float) -> Dictionary:
	var out: Dictionary = {"seconds_processed": 0.0, "steps": 0, "stopped": false, "reason": ""}
	if elapsed <= 0.0 or state == State.IDLE:
		return out
	var remaining: float = elapsed
	var stops_on_defeat: bool = bool(PlayerData.settings.get("offline_combat_stops_on_defeat", true))
	var guard: int = 0
	while remaining > 1e-6 and guard < MAX_OFFLINE_STEPS:
		guard += 1
		var step: float = minf(remaining, OFFLINE_STEP)
		tick(step)
		remaining -= step
		out["seconds_processed"] = elapsed - remaining
		if state == State.IDLE:
			out["stopped"] = true
			out["reason"] = "fight ended"
			break
		if state == State.DEAD:
			out["stopped"] = true
			out["reason"] = "defeated"
			break
		if deaths_this_session > 0 and stops_on_defeat:
			out["stopped"] = true
			out["reason"] = "defeated"
			break
	out["steps"] = guard
	if guard >= MAX_OFFLINE_STEPS:
		out["stopped"] = true
		out["reason"] = "offline combat step budget reached"
	return out

# =========================================================================
#  Persistence
# =========================================================================

func serialize() -> Dictionary:
	return {
		"state": state, "context": context, "monster_id": current_monster_id,
		"monster_hp": monster_hp, "player_hp": player_hp, "attack_style": attack_style,
		"melee_style": melee_style, "respawn_timer": respawn_timer,
	}

func deserialize(d: Dictionary) -> void:
	# Cooldowns and the last fired id are attack counters, not saved state: the live attack timer
	# is dropped the same way, and a reload must not hand out a free trigger. The loadout is
	# re-derived through set_loadout, so a loadout a hand-edited or older save no longer qualifies
	# for is dropped rather than trusted.
	_ability_cooldowns.clear()
	_last_ability_fired = ""
	_ability_interval_percent = 0.0
	set_loadout(PlayerData.ability_loadout)
	state = int(d.get("state", State.IDLE))
	context = d.get("context", {})
	current_monster_id = str(d.get("monster_id", ""))
	monster_hp = int(d.get("monster_hp", 0))
	player_hp = float(d.get("player_hp", _compute_max_hp()))
	attack_style = str(d.get("attack_style", "melee"))
	melee_style = str(d.get("melee_style", "stab"))
	respawn_timer = maxf(0.0, float(d.get("respawn_timer", 0.0)))
	player_max_hp = _compute_max_hp()
	# A fight that cannot be reconstructed (content changed, or the save is older than the
	# region) is dropped cleanly rather than resumed against a missing monster.
	if not DataLoader.get_monster(current_monster_id).is_empty():
		monster_max_hp = maxi(1, int(DataLoader.get_monster(current_monster_id).get("hitpoints", monster_hp)))
	elif state != State.IDLE:
		push_warning("CombatManager: dropping unreconstructable fight in '%s'" % str(context.get("id", "")))
		state = State.IDLE
		context = {}
		current_monster_id = ""
	if state == State.DEAD:
		state = State.IDLE
		player_hp = maxf(1.0, _compute_max_hp())
	if player_hp <= 0.0:
		player_hp = _compute_max_hp()
	EventBus.activity_changed.emit()

# =========================================================================
#  Abilities
# =========================================================================
## Slottable combat abilities, from data/abilities.json. Two rules make the feature safe to replay
## offline, and both are load-bearing rather than stylistic:
##   * the loadout order IS the roll order, and AT MOST ONE ability fires per player attack — the
##     first entry that is off cooldown and wins its trigger roll takes the swing, and no entry
##     after it is ever rolled;
##   * a rolled-but-missed entry and a blocked entry cost different amounts of randomness (1 and 0
##     draws), which is why both cases are pinned by the suite.
## The costs are fixed and the order is fixed, so simulate_elapsed() replaying these same ticks
## from the same seeded _rng lands on the same numbers the live fight did.

## Slot cap: one slot, plus one per 25 Defence, never more than four. data/skills.json's Defence
## skill id is "defence".
const ABILITY_SLOT_MAX: int = 4

var active_loadout: Array[String] = []      ## ability ids, in roll order
var _ability_cooldowns: Dictionary = {}    ## ability_id -> player attacks still to wait
var _ability_interval_percent: float = 0.0 ## a one-swing speedup, spent by the next interval
var _last_ability_fired: String = ""       ## "" when no ability fired on the last attack

func ability_slot_cap() -> int:
	return mini(ABILITY_SLOT_MAX, 1 + int(PlayerData.get_level("defence") / 25))

## Slots `ids`, dropping unknown ids, duplicates, abilities whose req_levels the player has not
## reached, and anything past the slot cap — in that order, so the survivors are the first entries
## the player offered. That order is the roll order, which is why it is preserved rather than
## sorted. Persists through PlayerData, the same path as every other player choice.
func set_loadout(ids: Array) -> void:
	var kept: Array[String] = []
	for entry in ids:
		if kept.size() >= ability_slot_cap():
			break
		var ability_id: String = str(entry)
		if kept.has(ability_id):
			continue
		var ab: Dictionary = DataLoader.get_ability(ability_id)
		if ab.is_empty() or not _ability_unlocked(ab):
			continue
		kept.append(ability_id)
	active_loadout = kept
	var stale: Array[String] = []
	for ability_id in _ability_cooldowns.keys():
		if not active_loadout.has(str(ability_id)):
			stale.append(str(ability_id))
	for ability_id in stale:
		_ability_cooldowns.erase(ability_id)
	_last_ability_fired = ""
	PlayerData.ability_loadout.clear()
	PlayerData.ability_loadout.append_array(active_loadout)

func _ability_unlocked(ab: Dictionary) -> bool:
	var reqs: Dictionary = ab.get("req_levels", {})
	for skill_id in reqs.keys():
		if PlayerData.get_level(str(skill_id)) < int(reqs[skill_id]):
			return false
	return true

## Cooldowns count PLAYER ATTACKS and are spent at the top of _player_attack(), before any roll:
## a fixed cost in a fixed place is what keeps the stream reproducible.
func _decrement_ability_cooldowns() -> void:
	for ability_id in _ability_cooldowns.keys():
		_ability_cooldowns[ability_id] = maxi(0, int(_ability_cooldowns[ability_id]) - 1)

## The ability step of one player attack: which ability, if any, has this swing. It only selects —
## every effect is applied by _player_attack() at the point the number it scales exists.
##
## RNG CONSUMPTION ORDER inside one player attack. Task 5's simulator mirror must draw in exactly
## this sequence; a stream that differs between the live and offline paths desynchronises offline
## gains without any error being raised.
##   1. to-hit roll                                    (_player_attack, before this is called)
##   2. one trigger roll per loadout entry IN LOADOUT ORDER, stopping at the first entry that is
##      off cooldown and whose roll lands. A blocked entry is skipped WITHOUT a draw; an entry
##      after the winner is never rolled at all.
##   3. when the winner carried apply_status, ONE status-chance roll from _apply_special_status,
##      fixed at 100% for an ability and so never blocking (the trigger roll is the chance)
##   4. the damage roll and the crit roll              (both inside CombatFormulas.roll_damage)
##   5. the weapon special-attack roll, then that special's own status-chance roll
## Steps 1, 4 and 5 are exactly where they were before abilities existed.
func _roll_abilities_for_test() -> void:
	_last_ability_fired = ""
	for ability_id in active_loadout:
		if int(_ability_cooldowns.get(ability_id, 0)) > 0:
			continue
		var ab: Dictionary = DataLoader.get_ability(ability_id)
		if ab.is_empty():
			continue
		if _rng.randf() * 100.0 > float(ab.get("trigger_chance", 0.0)):
			continue
		_ability_cooldowns[ability_id] = int(ab.get("cooldown_attacks", 0))
		_last_ability_fired = ability_id
		_sig_ability_triggered(ability_id)
		return

## apply_status names an id in StatusEffect.TABLE, and the record's sibling status_duration is how
## long it lasts (ContentValidator enforces that pairing, so neither can be missing here). It reuses
## the existing special-attack status path, whose extra status_chance roll is fixed at 100% for an
## ability: the trigger roll above is the chance. status_damage_per_tick is read the same way
## special_attacks.json supplies it, so the data file alone decides how hard a status bites; no
## shipped ability sets it yet, so those statuses mark the target and expire without ticking.
func _apply_ability_status(ab: Dictionary) -> void:
	var status_id: String = str((ab.get("effect", {}) as Dictionary).get("apply_status", ""))
	if status_id == "":
		return
	_apply_special_status({
		"applies_status": status_id,
		"status_chance": 100.0,
		"status_duration": float(ab.get("status_duration", 0.0)),
		"status_damage_per_tick": float(ab.get("status_damage_per_tick", 0.0)),
	}, "monster")

## Heals without ever overhealing: a fraction of a big hit on a wounded character would otherwise
## print a nonsense HP total, so the clamp is the same _compute_max_hp() the auto-eat and
## life-steal paths use.
func _apply_ability_heal(amount: float) -> void:
	if amount <= 0.0:
		return
	player_hp = minf(player_hp + amount, _compute_max_hp())
