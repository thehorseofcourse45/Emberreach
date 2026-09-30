class_name CombatFormulas
extends RefCounted
## Pure, static combat math — no node/scene dependencies, so it is unit-testable and
## reusable by the online tick loop AND the deterministic offline simulator.
## Every formula here is transcribed verbatim from the brief's Section 3.2.

## "M = 10 for Standard/Hardcore, 100 for Adventure mode."
const MODE_DAMAGE_MULTIPLIER = {"standard": 10, "hardcore": 10, "adventure": 100, "ancient_relics": 10}

# ---- 1. Combat level ----
## Base = 0.25*(Defence + Hitpoints + floor(0.5*Prayer)); Off = max(Attack+Str, 1.5*Ranged, 1.5*Magic);
## Combat Level = floor(Base + 0.325*Off).  Starts at 3, caps at 126 (153 expanded).
static func combat_level(defence: int, hitpoints: int, prayer: int,
        attack: int, strength: int, ranged: int, magic: int) -> int:
    var base: float = 0.25 * float(defence + hitpoints + int(floor(0.5 * float(prayer))))
    var melee_off: int = attack + strength
    var ranged_off: int = int(floor(1.5 * float(ranged)))
    var magic_off: int = int(floor(1.5 * float(magic)))
    var best: int = maxi(melee_off, maxi(ranged_off, magic_off))
    return int(floor(base + 0.325 * float(best)))

# ---- 2. Accuracy ----
## Effective Level = Skill Level + Hidden Skill Levels
static func effective_level(skill_level: int, hidden_levels: int = 0) -> int:
    return skill_level + hidden_levels

## Accuracy Rating = floor((Effective + 9) * (Bonus + 64) * (1 + AccMod/100))
static func accuracy_rating(effective_lvl: int, attack_bonus: int, accuracy_mod_percent: float = 0.0) -> int:
    return int(floor(float(effective_lvl + 9) * float(attack_bonus + 64) * (1.0 + accuracy_mod_percent / 100.0)))

# ---- 3. Chance to hit ----
## Equal ratings = 50%; double evasion = 75%; triple = 83.3%.
static func chance_to_hit(attacker_accuracy: float, defender_evasion: float) -> float:
    if defender_evasion <= 0.0:
        return 100.0
    var hit: float
    if attacker_accuracy < defender_evasion:
        hit = (attacker_accuracy / (2.0 * defender_evasion)) * 100.0
    else:
        hit = (1.0 - defender_evasion / (2.0 * attacker_accuracy)) * 100.0
    return clampf(hit, 0.0, 100.0)

# ---- 4. Max hit ----
## Melee/Ranged: floor(M*(2.2 + EffectiveLevel/10 + ((EffectiveLevel+17)*StrengthBonus)/640))
static func max_hit_base(mode: String, effective_lvl: int, strength_bonus: float) -> int:
    var m: float = float(MODE_DAMAGE_MULTIPLIER.get(mode, 10))
    return int(floor(m * (2.2 + float(effective_lvl) / 10.0 + ((float(effective_lvl) + 17.0) * strength_bonus) / 640.0)))

## Max Hit = floor(Base * (1 + PercentMod/100)) + FlatMod  (melee/ranged)
static func max_hit_melee_ranged(mode: String, effective_lvl: int, strength_bonus: float,
        percent_mod: float, flat_mod: float) -> int:
    var base: int = max_hit_base(mode, effective_lvl, strength_bonus)
    return int(floor(float(base) * (1.0 + percent_mod / 100.0))) + int(flat_mod)

## Magic: floor(SpellMaxHit * (1 + MagicDamageBonus/100) * (1 + (EffectiveMagicLevel+1)/200))
static func max_hit_magic_base(spell_max_hit: float, magic_damage_bonus: float, effective_magic_lvl: int) -> int:
    return int(floor(spell_max_hit * (1.0 + magic_damage_bonus / 100.0) * (1.0 + (float(effective_magic_lvl) + 1.0) / 200.0)))

static func max_hit_magic(spell_max_hit: float, magic_damage_bonus: float, effective_magic_lvl: int,
        percent_mod: float, flat_mod: float) -> int:
    var base: int = max_hit_magic_base(spell_max_hit, magic_damage_bonus, effective_magic_lvl)
    return int(floor(float(base) * (1.0 + percent_mod / 100.0))) + int(flat_mod)

# ---- 5. Evasion ----
## Melee/Ranged: floor((EffectiveDefence + 9) * (DefenceBonus + 64) * (1 + EvaMod/100))
static func evasion_melee_ranged(effective_defence: int, defence_bonus: int, evasion_mod_percent: float = 0.0) -> int:
    return int(floor(float(effective_defence + 9) * float(defence_bonus + 64) * (1.0 + evasion_mod_percent / 100.0)))

## Magic: EffLevel = floor(0.3*EffDefence + 0.7*EffMagic); floor((EffLevel+9)*(MagicDefBonus+64)*(1+EvaMod/100))
static func evasion_magic(effective_defence: int, effective_magic: int, magic_defence_bonus: int,
        evasion_mod_percent: float = 0.0) -> int:
    var eff: int = int(floor(0.3 * float(effective_defence) + 0.7 * float(effective_magic)))
    return int(floor(float(eff + 9) * float(magic_defence_bonus + 64) * (1.0 + evasion_mod_percent / 100.0)))

# ---- 6. Min hit ----
## Min Hit = min(max(floor(1 + MaxHit*PercentOfMaxAddedToMin) + FlatMinHitBonus, 1), MaxHit)
static func min_hit(max_hit: int, percent_of_max_added_to_min: float = 0.0, flat_min_hit_bonus: float = 0.0) -> int:
    var v: int = int(floor(1.0 + float(max_hit) * percent_of_max_added_to_min)) + int(flat_min_hit_bonus)
    return mini(maxi(v, 1), max_hit)

# ---- 7. Damage roll ----
## Roll uniform [min,max]; apply enemy DR; crit rolls add a multiplier.
static func roll_damage(rng: RandomNumberGenerator, min_hit_v: int, max_hit_v: int,
        enemy_dr_percent: float, crit_chance_percent: float, crit_multiplier_percent: float,
        damage_type: String = "normal", abyssal_resistance_percent: float = 0.0) -> Dictionary:
    var rolled: int = rng.randi_range(min_hit_v, max_hit_v)
    var is_crit: bool = (rng.randf() * 100.0) < crit_chance_percent
    var raw: float = float(rolled)
    if is_crit:
        raw *= (1.0 + crit_multiplier_percent / 100.0)
    var dr: float = 0.0
    match damage_type:
        "pure":
            dr = 0.0
        "abyssal":
            dr = abyssal_resistance_percent
        _:
            dr = enemy_dr_percent
    var final_damage: int = int(floor(raw * (1.0 - dr / 100.0)))
    final_damage = maxi(final_damage, 0)
    return {"damage": final_damage, "rolled": rolled, "is_crit": is_crit}

# ---- 8. Combat triangle ----
## Config comes from data/game_modes.json so values are tunable (the brief gives no
## explicit numbers, so these are data-driven defaults — documented as [assumption]).
static func triangle(attacker_style: String, defender_style: String, mode_config: Dictionary) -> Dictionary:
    var beats: Dictionary = {"melee": "ranged", "ranged": "magic", "magic": "melee"}
    if attacker_style == defender_style or not beats.has(attacker_style):
        return {"accuracy_percent": 0.0, "damage_percent": 0.0, "relation": "neutral"}
    if beats[attacker_style] == defender_style:
        return {
            "accuracy_percent": float(mode_config.get("advantage_accuracy", 10.0)),
            "damage_percent": float(mode_config.get("advantage_damage", 10.0)),
            "relation": "advantage",
        }
    return {
        "accuracy_percent": float(mode_config.get("disadvantage_accuracy", -10.0)),
        "damage_percent": float(mode_config.get("disadvantage_damage", -10.0)),
        "relation": "disadvantage",
    }

# ---- 9. Combat XP ----
static func hitpoints_xp(damage_dealt: float) -> float:
    return damage_dealt * 0.133

static func style_xp(damage_dealt: float, hybrid: bool = false) -> float:
    return damage_dealt * (0.2 if hybrid else 0.4)

static func prayer_xp(damage_dealt: float, prayer_point_cost: float) -> float:
    return (damage_dealt / 30.0) * prayer_point_cost

static func slayer_xp_for_kill(monster_max_hp: float, on_task: bool, in_slayer_area: bool) -> float:
    var pct: float = 0.0
    if on_task:
        pct = 0.10
    if in_slayer_area:
        pct += 0.05
    return monster_max_hp * pct

# ---- 10. Monster passives ----
## Damage a thorny creature reflects back at its attacker when it is hit. A minimum of 1
## keeps the identity real for chip damage; nothing in reflects nothing.
static func thorns_reflect(damage_dealt_to_monster: int, fraction: float) -> int:
    if damage_dealt_to_monster <= 0 or fraction <= 0.0:
        return 0
    return maxi(1, int(floor(float(damage_dealt_to_monster) * fraction)))

## A raging monster hits harder once it is at or below `threshold` of its maximum health.
static func enrage_multiplier(hp_fraction: float, threshold: float, multiplier: float) -> float:
    if multiplier <= 1.0 or threshold <= 0.0:
        return 1.0
    return multiplier if hp_fraction <= threshold else 1.0
