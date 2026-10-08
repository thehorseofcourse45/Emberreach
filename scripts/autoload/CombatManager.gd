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
## Fraction of damage a "thorns" monster reflects back at the attacker while it still stands.
const ENEMY_THORNS_FRACTION: float = 0.10
## An "enrage" monster hits this much harder once at or below this fraction of its max HP.
const ENRAGE_HP_FRACTION: float = 0.25
const ENRAGE_MULTIPLIER: float = 1.5
## Monster passive ids the engine understands (data may list more only after engine support).
## Built from MonsterMechanics.NEW_PASSIVES so the new ids cannot drift from the rules module.
const KNOWN_MONSTER_PASSIVES: Array[String] = ["regeneration", "thorns", "enrage"] + MonsterMechanics.NEW_PASSIVES

var state: int = State.IDLE
var context: Dictionary = {}          # {type, id, monsters:[...], index, endless, attack_style}
var current_monster_id: String = ""
## How many of the current monster's phases have fired (phases fire once, in order).
var monster_phases_fired: int = 0
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

# --- Session meters ---------------------------------------------------------------
# A rolling window, not a lifetime total: the question a player asks is "is this fight
# faster than the last one", which a lifetime average cannot answer. Deque of [time, damage]
# is a ponytail: a full history plus a linear scan is not worth it at one window's width.
const DPS_WINDOW: float = 60.0
var _dmg_deque: Array = []          # [elapsed_time, damage] pairs, oldest first
var _dmg_window_time: float = 0.0
var session_damage_dealt: float = 0.0
var session_damage_taken: float = 0.0
var session_gp_earned: float = 0.0
var _fight_clock: float = 0.0
var _fight_damage_start: float = 0.0
var _fight_dps_clock_start: float = 0.0

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

func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value

# --- Bus wrappers ---------------------------------------------------------------------------
# Combat emits a lot of UI events (every attack). During a silent offline catch-up these must
# not fire, or a 24-hour fight would produce tens of thousands of UI notifications. These tiny
# typed wrappers are the single place that decides whether anyone is watching.
func _sig_combat_started(ctx: Dictionary) -> void:
	if not SimulationMode.is_silent():
		EventBus.combat_started.emit(ctx)

func _sig_combat_ended(reason: String, completed: Dictionary = {}) -> void:
	var payload: Dictionary = (context if completed.is_empty() else completed).duplicate(true)
	payload["reason"] = reason
	# Gameplay transitions must run during silent catch-up too.
	RaidManager._on_combat_ended(payload)
	if not SimulationMode.is_silent():
		EventBus.combat_ended.emit(payload)

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

func _sig_monster_phase(monster_id: String, phase_name: String) -> void:
	if not SimulationMode.is_silent():
		EventBus.monster_phase_entered.emit(monster_id, phase_name)

## The monster as it fights right now: the base record with every fired phase applied. Use
## DataLoader.get_monster() instead where the unmodified record is meant (loot, slayer, death).
func current_monster() -> Dictionary:
	var record: Dictionary = DataLoader.get_monster(current_monster_id)
	if monster_phases_fired <= 0:
		return record  # callers only read it; avoid a deep copy per call
	return MonsterMechanics.effective(record, monster_phases_fired)

func _sig_status(target: String, effect_id: String, applied: bool) -> void:
	if SimulationMode.is_silent():
		return
	if applied:
		EventBus.status_effect_applied.emit(target, effect_id)
	else:
		EventBus.status_effect_expired.emit(target, effect_id)

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

## Why a dungeon is still shut: "" when it can be entered. `requires` is a {skill: level} map;
## `requires_dungeon` reuses the shop-upgrade vocabulary to chain one clear to the next unlock.
## The single evaluator every UI reads, so the list, the card and the detail pane cannot disagree.
## True while a fight inside an `equipment_locked` dungeon is running.
func equipment_locked() -> bool:
	return state != State.IDLE and state != State.DEAD and str(context.get("type", "")) == "dungeon" \
		and bool(DataLoader.get_dungeon(str(context.get("id", ""))).get("equipment_locked", false))

func dungeon_lock_reason(dungeon_id: String) -> String:
	var dungeon: Dictionary = DataLoader.get_dungeon(dungeon_id)
	var reqs: Dictionary = dungeon.get("requires", {}) as Dictionary
	for skill_id in reqs.keys():
		var needed: int = int(reqs[skill_id])
		if PlayerData.get_level(str(skill_id)) < needed:
			return "Reach %s %d" % [str(DataLoader.get_skill(str(skill_id)).get("name", skill_id)), needed]
	var prev: String = str(dungeon.get("requires_dungeon", ""))
	if prev != "" and not (PlayerData.completion_log.get("dungeons", {}) as Dictionary).has(prev):
		return "Clear %s" % str(DataLoader.get_dungeon(prev).get("name", prev))
	return ""

func start_combat(ctx: Dictionary) -> bool:
	if str(ctx.get("type", "")) == "dungeon":
		var dungeon_id: String = str(ctx.get("id", ""))
		if is_expedition(dungeon_id):
			var reason: String = expedition_unlock_reason()
			if reason != "":
				EventBus.notify("Expedition locked: %s" % reason, "warn")
				return false
		var gate: String = dungeon_lock_reason(dungeon_id)
		if gate != "":
			EventBus.notify("%s is locked: %s" % [str(DataLoader.get_dungeon(dungeon_id).get("name", dungeon_id)), gate], "warn")
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
	_begin_fight_clock()
	ProgressTracker.record_region_visit(str(ctx.get("id", "")))
	_sig_combat_started(ctx)
	EventBus.activity_changed.emit()
	_spawn_current()
	return true

## Retreat. Always available, never punished.
func stop_combat(reason: String = "") -> void:
	var was_active: bool = state != State.IDLE
	var completed: Dictionary = context.duplicate(true)
	state = State.IDLE
	current_monster_id = ""
	context = {}
	player_effects.clear()
	monster_effects.clear()
	respawn_timer = 0.0
	if was_active:
		_sig_combat_ended("retreat" if reason == "" else reason, completed)
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
	monster_phases_fired = 0
	var m: Dictionary = DataLoader.get_monster(monster_id)
	monster_max_hp = maxi(1, int(m.get("hitpoints", 10)))
	# A raid difficulty's hp_mult makes its golbins actually tankier. Every raid enemy is spawned
	# through here, so this is the one place the multiplier has to be applied.
	if _in_raid():
		monster_max_hp = maxi(1, int(round(float(monster_max_hp) * RaidManager.enemy_hp_mult())))
	monster_hp = monster_max_hp
	monster_attack_interval = maxf(CombatSimulator.MONSTER_INTERVAL_FLOOR, float(m.get("attack_speed", 3.0)))
	monster_attack_timer = 0.0
	player_attack_timer = 0.0
	player_attack_interval = ModifierManager.get_attack_interval(EquipmentManager.get_weapon_attack_speed())
	monster_effects.clear()
	state = State.FIGHTING
	_sig_monster_spawned(monster_id, monster_hp)
	# A new enemy IS a new activity: the fight readout, the activity strip and the overview
	# rebuild from activity_changed and read current_monster_id when they do, so a spawn
	# must announce itself or those portraits freeze on the session's first enemy.
	if not SimulationMode.is_silent():
		EventBus.activity_changed.emit()
	SimulationMode.bump("encounters", monster_id, 1.0)

# =========================================================================
#  Tick
# =========================================================================

func _process(delta: float) -> void:
	if SimulationMode.is_silent():
		return   # offline catch-up drives tick() explicitly
	if GameManager.is_paused:
		return   # Pause must stop the fight, not just the playtime clock
	tick(delta)

func tick(delta: float) -> void:
	if not combat_enabled or delta <= 0.0:
		return
	if state == State.IDLE:
		return
	_fight_clock += delta
	_trim_dps_window()
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
	player_attack_interval = maxf(0.25, ModifierManager.get_attack_interval(EquipmentManager.get_weapon_attack_speed()))
	if _in_raid():
		player_attack_interval *= 0.5   # everyone attacks at 2x speed in the raid
	monster_attack_interval = maxf(CombatSimulator.MONSTER_INTERVAL_FLOOR, float(current_monster().get("attack_speed", 3.0)))
	player_attack_interval *= 1.0 + StatusEffect.total(player_effects, "attack_interval_percent") / 100.0
	monster_attack_interval *= 1.0 + StatusEffect.total(monster_effects, "attack_interval_percent") / 100.0
	if not _is_player_stunned(): player_attack_timer += delta
	if not CombatSimulator._blocked(monster_effects): monster_attack_timer += delta
	var guard: int = 0
	while player_attack_timer >= player_attack_interval and state == State.FIGHTING and guard < 512 and not _is_player_stunned():
		guard += 1
		player_attack_timer -= player_attack_interval
		_player_attack()
		_regen_after_attack()
	guard = 0
	while monster_attack_timer >= monster_attack_interval and state == State.FIGHTING and guard < 512 and not CombatSimulator._blocked(monster_effects):
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

# =========================================================================
#  Session meters (DPS window, damage and gold tallies)
# =========================================================================

## Add a player hit to the rolling DPS window. Called from the one place that resolves a
## player attack, so every damage source (styles, crits, special attacks) is counted once.
func _record_damage(dmg: int) -> void:
	var amount: float = float(maxi(0, dmg))
	if amount <= 0.0:
		return
	session_damage_dealt += amount
	_dmg_deque.append([_fight_clock, amount])
	_trim_dps_window()

## Damage the player took. Every site that lowers player_hp routes through here so the
## "taken" column can never disagree with the HP bar.
func _record_damage_taken(dmg: float) -> void:
	session_damage_taken += maxf(0.0, dmg)

func _record_gp(amount: float) -> void:
	if amount > 0.0:
		session_gp_earned += amount

## Drop window entries that have aged out, and rebase the window clock so `_fight_clock`
## growing without bound cannot eventually lose float precision.
func _trim_dps_window() -> void:
	while not _dmg_deque.is_empty() and (_fight_clock - float(_dmg_deque[0][0])) > DPS_WINDOW:
		_dmg_deque.pop_front()
	if _fight_clock - _dmg_window_time > DPS_WINDOW:
		_dmg_window_time = _fight_clock - DPS_WINDOW

## Damage per second over the trailing window.
##
## The total is summed from the deque every read rather than kept as a running cache that
## _trim_dps_window subtracts from: a window that ages out while nobody is attacking (a
## monster being slow, a player being stunned) would otherwise keep reporting a rate built
## on hits that are no longer inside the window. Summing 60s of hits is not a hot path.
func dps() -> float:
	if _dmg_deque.is_empty():
		return 0.0
	var span: float = minf(_fight_clock, DPS_WINDOW)
	if span <= 0.0:
		return 0.0
	var total: float = 0.0
	for entry in _dmg_deque:
		total += float((entry as Array)[1])
	return total / span

## One dictionary for the whole readout, so the panel never recomputes the window itself.
func session_readout() -> Dictionary:
	var fight_damage: float = session_damage_dealt - _fight_damage_start
	var fight_time: float = _fight_clock - _fight_dps_clock_start
	return {
		"dps": dps(),
		"damage_dealt": session_damage_dealt,
		"damage_taken": session_damage_taken,
		"gp_earned": session_gp_earned,
		"kills": kills_this_session,
		"deaths": deaths_this_session,
		"fight_dps": (fight_damage / fight_time) if fight_time > 0.0 else 0.0,
		"fight_time": fight_time,
		"fighting": state == State.FIGHTING,
	}

## Reset the per-fight averages. Called on start_combat; session totals survive so the
## player can still see the whole run's numbers.
func _begin_fight_clock() -> void:
	_fight_dps_clock_start = _fight_clock
	_fight_damage_start = session_damage_dealt

func _player_accuracy(style: String, selected_melee: String = "") -> int:
	var attack_key: String = "stab"
	if style == "melee":
		attack_key = melee_style if selected_melee == "" else selected_melee
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

## Every magic attack casts the spell of the equipped staff, and the spell's base max hit is what
## makes a better staff hit harder. Weapons that declare no spell keep the old fixed base of 10.
const DEFAULT_SPELL_MAX_HIT: float = 10.0

func _spell_max_hit() -> float:
	var weapon: Dictionary = DataLoader.get_item(EquipmentManager.get_equipped(ItemData.EquipmentSlot.WEAPON))
	return float(weapon.get("spell_max_hit", DEFAULT_SPELL_MAX_HIT))

func _player_max_hit(style: String) -> int:
	if style == "magic":
		var eff_magic: int = _player_effective("magic")
		return CombatFormulas.max_hit_magic(_spell_max_hit(), float(EquipmentManager.get_strength_bonus("magic")),
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
func player_combat_summary(style: String = "", selected_melee: String = "") -> Dictionary:
	var use_style: String = attack_style if style == "" else style
	var use_melee: String = melee_style if selected_melee == "" else selected_melee
	return {
		"max_hp": _compute_max_hp(),
		"hp": player_hp,
		"style": use_style,
		"melee_style": use_melee,
		"accuracy": _player_accuracy(use_style, use_melee),
		"max_hit": _player_max_hit(use_style),
		"attack_interval": maxf(0.25, ModifierManager.get_attack_interval(EquipmentManager.get_weapon_attack_speed())),
		"damage_reduction": clampf(ModifierManager.get_damage_reduction() + EquipmentManager.get_damage_reduction(), 0.0, 90.0),
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
	var m: Dictionary = current_monster()
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
	# Arrows and runes are spent per swing, not per hit, so a miss still costs a shot. The
	# Marksmanship skillcapes refund a share of them; CombatFormulas keeps this identical to the
	# simulator's depletion model.
	var weapon_cost: Dictionary = EquipmentManager.get_attack_cost()
	var attack_cost: Dictionary = CombatFormulas.ammo_cost(_rng, weapon_cost,
		ModifierManager.get_modifier(ModifierKeys.AMMO_PRESERVATION_PERCENT)
		+ (ModifierManager.get_modifier(ModifierKeys.RUNE_PRESERVATION_PERCENT) if attack_style == "magic" else 0.0))
	if not bool(BankManager.consume_bundle(attack_cost).ok):
		stop_combat("supplies exhausted")
		return
	PrayerManager.spend_for_attack()   # active prayers cost points per attack
	PotionManager.consume_charge("combat")
	var m: Dictionary = current_monster()
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
	# Specials roll first so an accuracy-ignoring one can land through a miss.
	var sa: Dictionary = _roll_special_attack(EquipmentManager.get_weapon_special_attack())
	if not bool(sa.get("ignores_accuracy", false)) and _rng.randf() * 100.0 > hit_chance:
		return
	var mh: int = maxi(1, _player_max_hit(attack_style))
	mh = maxi(1, int(floor(float(mh) * (1.0 + float(tri["damage_percent"]) / 100.0))))
	var mn: int = CombatFormulas.min_hit(mh,
		ModifierManager.get_modifier(ModifierKeys.MIN_HIT_PERCENT_OF_MAX) / 100.0,
		ModifierManager.get_modifier(ModifierKeys.MIN_HIT_FLAT))
	var res: Dictionary = CombatFormulas.roll_damage(_rng, mn, mh, float(m.get("damage_reduction", 0.0)),
		ModifierManager.get_crit_chance(), ModifierManager.get_crit_multiplier())
	var dmg: int = int(res["damage"])
	var is_crit: bool = bool(res["is_crit"])
	# Weapon special attack: replaces the normal attack and may apply a status.
	if not sa.is_empty():
		dmg = maxi(1, int(floor(float(dmg) * float(sa.get("damage_multiplier", 1.0)))))
		_sig_player_special(str(sa.get("id", "")))
		_apply_special_status(sa, "monster")
		var heal_frac: float = float(sa.get("heal_fraction", 0.0))
		if heal_frac > 0.0:
			player_hp = minf(player_hp + float(dmg) * heal_frac, _compute_max_hp())
	# Monster style affinity and armor apply once, to the final hit (specials included). The
	# minimum of 1 only keeps a positive hit from rounding away; a hit DR floored to 0 stays 0.
	if dmg > 0:
		dmg = maxi(1, int(floor(float(dmg) * MonsterMechanics.affinity_multiplier(m, attack_style))))
	dmg = MonsterMechanics.armored_reduce(m, dmg)
	dmg = _status_scaled(dmg, player_effects, monster_effects)
	EnchantingManager.on_hit(dmg)
	apply_damage_to_monster(dmg)
	_sig_player_attacked(dmg, is_crit)
	_record_damage(dmg)
	_grant_combat_xp(dmg)
	SummoningManager.on_combat_action()
	var ls: float = ModifierManager.get_life_steal()
	if ls > 0.0:
		player_hp = minf(player_hp + float(dmg) * ls / 100.0, _compute_max_hp())

## A hit after status effects: the attacker's own debuffs (damage dealt) and the target's
## vulnerabilities (damage taken). A positive hit never rounds to nothing.
func _status_scaled(dmg: int, attacker_effects: Array, target_effects: Array) -> int:
	if dmg <= 0 or (attacker_effects.is_empty() and target_effects.is_empty()):
		return dmg
	var mult: float = 1.0 + (StatusEffect.total(attacker_effects, "damage_dealt_percent") 		+ StatusEffect.total(target_effects, "damage_taken_percent")) / 100.0
	return maxi(1, int(floor(float(dmg) * maxf(0.0, mult))))

## Regeneration is per own attack, hit or miss, so it wraps the swing.
func _monster_attack() -> void:
	if state != State.FIGHTING:
		return
	_monster_swing()
	if state == State.FIGHTING and monster_hp > 0 and (current_monster().get("passives", []) as Array).has("regeneration"):
		monster_hp = mini(monster_max_hp, monster_hp + maxi(1, int(float(monster_max_hp) * ENEMY_REGEN_FRACTION)))

func _monster_swing() -> void:
	var m: Dictionary = current_monster()
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
	# A raging monster hits harder as it nears death — but only one that actually has the
	# enrage passive; every other monster swings at the same strength all fight.
	if (m.get("passives", []) as Array).has("enrage"):
		raw *= CombatFormulas.enrage_multiplier(float(monster_hp) / float(maxi(1, monster_max_hp)),
			ENRAGE_HP_FRACTION, ENRAGE_MULTIPLIER)
	# Open-region hazard: hostile ground hits harder.
	raw *= (1.0 + float(_active_hazard().get("enemy_damage_percent", 0.0)) / 100.0)
	# ModifierManager combines its own sources; worn equipment adds on top. Clamped because
	# _combine multiplies out and can exceed 100%, which would make the multiplier negative and
	# turn every hit into a heal.
	var dr: float = clampf(ModifierManager.get_damage_reduction() + EquipmentManager.get_damage_reduction(), 0.0, 90.0)
	var dmg: int = maxi(0, int(floor(raw * (1.0 - dr / 100.0))))
	var sa: Dictionary = _roll_special_attack_from_ids(m.get("special_attacks", []))
	if not sa.is_empty():
		dmg = maxi(1, int(floor(float(dmg) * float(sa.get("damage_multiplier", 1.0)))))
		_sig_monster_special(str(sa.get("id", "")))
		_apply_special_status(sa, "player")
	dmg = _status_scaled(dmg, monster_effects, player_effects)
	player_hp -= float(dmg)
	_record_damage_taken(float(dmg))
	_sig_monster_attacked(dmg)
	var passives: Array = m.get("passives", [])
	# Venom: a landed hit may poison the player (the status is applied to the player only).
	if dmg > 0 and passives.has("venomous") and _rng.randf() < MonsterMechanics.VENOM_CHANCE:
		var venom: Dictionary = MonsterMechanics.venom_status(int(m.get("max_hit", 1)))
		apply_status("player", str(venom["id"]), float(venom["duration"]), float(venom["damage_per_tick"]))
	# Lifedrain: the monster heals a share of the damage it dealt, capped at its max HP.
	if dmg > 0 and monster_hp > 0 and passives.has("lifedrain"):
		monster_hp = mini(monster_max_hp, monster_hp + MonsterMechanics.lifedrain_heal(dmg))
	if player_hp <= 0.0:
		_player_death(m.get("name", current_monster_id))

## The current open-region hazard, if any (dungeons and towns are sheltered).
## hitpoints_regen_flat: heal a flat amount after each of the player's own attacks. The
## simulator applies the same rule at the same point, so its survival numbers match.
func _regen_after_attack() -> void:
	var regen: float = ModifierManager.get_hp_regen_per_attack()
	if regen > 0.0 and state == State.FIGHTING and player_hp > 0.0:
		player_hp = minf(player_hp + regen, _compute_max_hp())

func _active_hazard() -> Dictionary:
	if str(context.get("type", "")) != "area":
		return {}
	return ModifierManager.negated_hazard(DataLoader.areas.get(str(context.get("id", "")), {}).get("hazard", {}))

## True while a raid is running. RaidManager marks the fight by context "type" only, so every
## raid-specific rule in the engine asks here rather than reading a key that is never set.
func _in_raid() -> bool:
	return str(context.get("type", "")) == "raid"

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
		return
	_fire_due_phases()
	# Thorns: a spiny creature pays back a fraction of what it was dealt while it still
	# stands. Reflected damage is not an attack, so DR and prayers do not apply to it.
	var m: Dictionary = current_monster()
	if (m.get("passives", []) as Array).has("thorns"):
		var reflect: int = CombatFormulas.thorns_reflect(dmg, ENEMY_THORNS_FRACTION)
		if reflect > 0:
			player_hp -= float(reflect)
			_record_damage_taken(float(reflect))
			_sig_monster_attacked(reflect)
			if player_hp <= 0.0:
				_player_death(str(m.get("name", current_monster_id)))

## Fire every boss phase whose HP threshold is now crossed (HP fraction of the possibly
## raid-scaled pool), once each and in order. A phase status goes straight to the player
## through apply_status; the monster's own effect immunity never gates it.
func _fire_due_phases() -> void:
	var phases: Array = DataLoader.get_monster(current_monster_id).get("phases", [])
	if phases.is_empty():
		return
	var due: int = MonsterMechanics.phases_due(phases, monster_phases_fired,
		float(monster_hp) / float(maxi(1, monster_max_hp)))
	while monster_phases_fired < due:
		var phase: Dictionary = phases[monster_phases_fired]
		monster_phases_fired += 1
		var status: Dictionary = (phase.get("effects", {}) as Dictionary).get("apply_status", {})
		if not status.is_empty():
			apply_status("player", str(status.get("id", "")), float(status.get("duration", 3.0)),
				float(status.get("damage_per_tick", 0.0)))
		_sig_monster_phase(current_monster_id, str(phase.get("name", "")))

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
	var on_task: bool = str(PlayerData.slayer_task.get("monster_id", "")) == current_monster_id
	SlayerManager._on_kill(current_monster_id)
	_sig_monster_killed(current_monster_id)
	kills_this_session += 1
	PlayerData.discover_monster(current_monster_id)
	ProgressTracker.record_kill(current_monster_id)
	SimulationMode.bump(SimulationMode.BUCKET_KILLS, current_monster_id, 1.0)
	_grant_loot(m)
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

## loot_only re-rolls just the loot table (the Champion foe event), skipping per-kill side effects.
func _grant_loot(m: Dictionary, loot_only: bool = false) -> void:
	if not loot_only:
		EngineeringManager.on_kill(m)
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
				_:
					PlayerData.add_gp(float(qty) * gp_pct)
					_record_gp(float(qty) * gp_pct)
			continue
		var item_id: String = str(drop.get("item_id", ""))
		if item_id == "":
			continue
		# Loot uses the guaranteed path: a rare drop must never be lost to a full bank.
		BankManager.add_item_guaranteed(item_id, qty)
		SimulationMode.bump(SimulationMode.BUCKET_ITEMS_PRODUCED, item_id, float(qty))
		if float(drop.get("chance", 1.0)) <= SimulationMode.RARE_DROP_CHANCE_THRESHOLD:
			SimulationMode.bump(SimulationMode.BUCKET_RARE_DROPS, item_id, float(qty))
			PlayerData.record_rare_drop(item_id, qty, "combat")
	if loot_only:
		return
	const RandomEvents = preload("res://scripts/core/RandomEvents.gd")
	if RandomEvents.roll("champion_foe", _rng):
		RandomEvents.announce("champion_foe", "%s dropped its loot twice." % str(m.get("name", "")))
		_grant_loot(m, true)
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
##   * in every game mode the worst outcome is that ONE unequipped, unprotected, non-consumable,
##     non-companion slot is returned to storage.
## No mode deletes a character. Hardcore differs by a lower storage cap and a harsher combat
## triangle (data/game_modes.json), not by death.
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
	for prayer_id in PlayerData.active_prayers:
		if PrayerManager.get_prayer(str(prayer_id)).get("type", "") == "protect_item":
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
		# A direct call, not the EventBus signal: _sig_dungeon_completed is muted during a silent
		# offline simulation, and an offline expedition clear must still grant its pet.
		PetManager.on_dungeon_cleared(dungeon_id)
		SlayerManager.on_dungeon_cleared(dungeon_id)
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
				_record_damage_taken(dmg)
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
	elif not is_player and state == State.FIGHTING:
		_fire_due_phases()   # DoT damage crosses boss thresholds too

## Total player resistance (percent) to a status family: worn gear plus prayer/potion modifiers,
## capped at MonsterMechanics.RESISTANCE_CAP.
func player_status_resistance(family: String) -> float:
	if family == "":
		return 0.0
	# Explicit constants (not a formatted key) so the bonus-key reader audit can see them.
	var modifier_keys: Dictionary = {
		"poison": ModifierKeys.POISON_RESISTANCE_PERCENT,
		"burn": ModifierKeys.BURN_RESISTANCE_PERCENT,
		"stun": ModifierKeys.STUN_RESISTANCE_PERCENT,
	}
	var total: float = EquipmentManager.get_status_resistance(family) \
		+ ModifierManager.get_modifier(str(modifier_keys[family]))
	return minf(total, MonsterMechanics.RESISTANCE_CAP)

func apply_status(target: String, effect_id: String, duration: float, damage_per_tick: float = 0.0) -> void:
	if target == "player":
		var family: String = MonsterMechanics.status_family(effect_id)
		if family != "":
			var resistance: float = player_status_resistance(family)
			if resistance > 0.0:
				duration = MonsterMechanics.resisted_duration(effect_id, duration, resistance, _rng.randf())
				if duration <= 0.0:
					return
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
	if _in_raid():
		tier = maxi(tier, 2)   # Auto Eat Tier II is always active in the raid
	if tier <= 0 or not AUTO_EAT.has(tier):
		return
	var cfg: Dictionary = AUTO_EAT[tier]
	var maxhp: float = _compute_max_hp()
	var pct: float = player_hp / maxf(maxhp, 1.0) * 100.0
	var threshold: float = float(cfg["threshold"]) + ModifierManager.get_modifier(ModifierKeys.AUTO_EAT_THRESHOLD_PERCENT)
	if pct > threshold:
		return
	var eff: float = float(cfg["efficiency"]) + ModifierManager.get_modifier(ModifierKeys.AUTO_EAT_EFFICIENCY_PERCENT)
	consume_food(find_food(), eff, "Auto-eat")

## Eat one food from the bank and heal. The single place food becomes health: auto-eat, the manual
## button and the offline simulator all route through here, so they cannot disagree about what a
## food is worth. Returns the food eaten, or "" if nothing was usable.
## `efficiency` is a percent (100 = the food's full heal_amount), so a bought auto-eat tier's
## penalty applies to automatic eating but never to a deliberate one.
func consume_food(food_id: String, efficiency: float = 100.0, source: String = "Ate") -> String:
	if food_id == "" or DataLoader.get_item(food_id).get("item_type", "") != "food":
		return ""
	var heal: float = float(DataLoader.get_item(food_id).get("heal_amount", 0))
	if heal <= 0.0:
		return ""
	heal *= (efficiency / 100.0) * (1.0 + ModifierManager.get_modifier(ModifierKeys.FOOD_HEALING_PERCENT) / 100.0)
	if heal <= 0.0 or not BankManager.remove_item(food_id, 1):
		return ""
	player_hp = minf(player_hp + heal, _compute_max_hp())
	if not SimulationMode.is_silent():
		EventBus.notification.emit("%s: %s (+%d HP)" % [source,
			str(DataLoader.get_item(food_id).get("name", food_id)), int(heal)], "info")
	return food_id

## Eat the food that best covers the missing health. This is what the manual button calls.
func eat_best_food() -> String:
	return consume_food(find_food(), 100.0, "Ate")

## Deterministic food choice: the smallest food that still fills the missing health, so a
## long fight does not burn the player's best supplies first. Public so the Eat button can label
## itself with the food it will actually pick.
func find_food() -> String:
	var best: String = ""
	var best_heal: int = -1
	var maxhp: float = _compute_max_hp()
	var missing: float = maxf(1.0, maxhp - player_hp)
	# Foods assigned to a slot are the ones the player chose to burn; with none assigned, any food goes.
	var slotted: Array = EquipmentManager.food_slots.filter(func(id): return id != "")
	for item_id in BankManager.items.keys():
		if DataLoader.get_item(item_id).get("item_type", "") != "food":
			continue
		if int(BankManager.items[item_id]) <= 0:
			continue
		if not slotted.is_empty() and not slotted.has(item_id):
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
		elif covers == best_covers and ((heal < best_heal) if covers else (heal > best_heal)):
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
		var deaths_before: int = deaths_this_session
		tick(step)
		remaining -= step
		out["seconds_processed"] = elapsed - remaining
		if state == State.IDLE:
			out["stopped"] = true
			# A defeat also ends in IDLE (stop_combat), so tell the two apart by the death count.
			out["reason"] = "defeated" if deaths_this_session > deaths_before else "fight ended"
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
		"player_attack_timer": player_attack_timer, "monster_attack_timer": monster_attack_timer,
		"monster_max_hp": monster_max_hp, "phases_fired": monster_phases_fired,
		"player_effects": player_effects.map(func(effect): return effect.serialize()),
		"monster_effects": monster_effects.map(func(effect): return effect.serialize()),
	}

func deserialize(d: Dictionary) -> void:
	state = int(d.get("state", State.IDLE))
	context = d.get("context", {})
	current_monster_id = str(d.get("monster_id", ""))
	monster_hp = int(d.get("monster_hp", 0))
	player_hp = float(d.get("player_hp", _compute_max_hp()))
	attack_style = str(d.get("attack_style", "melee"))
	melee_style = str(d.get("melee_style", "stab"))
	respawn_timer = maxf(0.0, float(d.get("respawn_timer", 0.0)))
	player_max_hp = _compute_max_hp()
	player_attack_timer = maxf(0.0, float(d.get("player_attack_timer", 0)))
	monster_attack_timer = maxf(0.0, float(d.get("monster_attack_timer", 0)))
	if not is_finite(player_attack_timer): player_attack_timer = 0
	if not is_finite(monster_attack_timer): monster_attack_timer = 0
	player_effects.clear()
	monster_effects.clear()
	for key in ["player_effects", "monster_effects"]:
		var values: Variant = d.get(key, [])
		if values is Array:
			for value in values.slice(0, 64):
				var effect: StatusEffect = StatusEffect.from_save(value)
				if effect != null:
					if key == "player_effects": player_effects.append(effect)
					else: monster_effects.append(effect)
	# A fight that cannot be reconstructed (content changed, or the save is older than the
	# region) is dropped cleanly rather than resumed against a missing monster.
	monster_phases_fired = 0
	if not DataLoader.get_monster(current_monster_id).is_empty():
		monster_max_hp = maxi(1, int(d.get("monster_max_hp", DataLoader.get_monster(current_monster_id).get("hitpoints", monster_hp))))
		var phase_count: int = (DataLoader.get_monster(current_monster_id).get("phases", []) as Array).size()
		monster_phases_fired = clampi(int(d.get("phases_fired", 0)), 0, phase_count)
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
