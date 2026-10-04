class_name MonsterMechanics
extends RefCounted
## Pure, static monster-mechanics rules: style affinities, the venomous / lifedrain /
## armored passives, boss phases and status-resistance helpers. No node dependencies, so
## the live CombatManager and the offline CombatSimulator share one rule set.

const WEAK_MULTIPLIER := 1.25
const RESIST_MULTIPLIER := 0.75
const VENOM_CHANCE := 0.25
const VENOM_DURATION := 6.0
const VENOM_TICK_FRACTION := 0.05
const LIFEDRAIN_FRACTION := 0.30
const ARMORED_FRACTION := 0.08
const RESISTANCE_CAP := 75.0

const NEW_PASSIVES: Array[String] = ["venomous", "lifedrain", "armored"]
const STYLES: Array[String] = ["melee", "ranged", "magic"]
const PHASE_EFFECT_KEYS: Array[String] = ["attack_speed_multiplier", "max_hit_multiplier",
        "add_passives", "attack_type", "apply_status"]

const STATUS_FAMILIES := {
    "poison": ["poison", "toxin", "deadly_poison", "venom"],
    "burn": ["burn", "ablaze", "frostburn"],
    "stun": ["stun", "freeze", "sleep", "crystallize"],
}

static func affinity_multiplier(monster: Dictionary, style: String) -> float:
    if (monster.get("weak_to", []) as Array).has(style):
        return WEAK_MULTIPLIER
    if (monster.get("resists", []) as Array).has(style):
        return RESIST_MULTIPLIER
    return 1.0

static func armored_reduce(monster: Dictionary, dealt: int) -> int:
    if dealt <= 0 or not (monster.get("passives", []) as Array).has("armored"):
        return dealt
    var flat: int = maxi(1, floori(float(monster.get("hitpoints", 0)) * ARMORED_FRACTION))
    return maxi(1, dealt - flat)

static func lifedrain_heal(dealt: int) -> int:
    if dealt <= 0:
        return 0
    return maxi(1, floori(float(dealt) * LIFEDRAIN_FRACTION))

static func venom_status(monster_max_hit: int) -> Dictionary:
    return {"id": "poison", "duration": VENOM_DURATION,
        "damage_per_tick": maxf(1.0, float(monster_max_hit) * VENOM_TICK_FRACTION)}

## New fired count after every threshold now crossed (phases are in descending order).
static func phases_due(phases: Array, fired: int, hp_fraction: float) -> int:
    var count: int = maxi(0, fired)
    while count < phases.size():
        var threshold: float = float((phases[count] as Dictionary).get("at_hp_percent", 0)) / 100.0
        if hp_fraction <= threshold:
            count += 1
        else:
            break
    return count

static func effective(monster: Dictionary, fired: int) -> Dictionary:
    var result: Dictionary = monster.duplicate(true)
    var phases: Array = monster.get("phases", [])
    for i in range(mini(fired, phases.size())):
        var phase: Dictionary = phases[i]
        if phase.has("attack_speed_multiplier"):
            result["attack_speed"] = float(result.get("attack_speed", 1.0)) / float(phase["attack_speed_multiplier"])
        if phase.has("max_hit_multiplier"):
            result["max_hit"] = roundi(float(result.get("max_hit", 0)) * float(phase["max_hit_multiplier"]))
        if phase.has("attack_type"):
            result["attack_type"] = phase["attack_type"]
        if phase.has("add_passives"):
            var passives: Array = result.get("passives", []).duplicate()
            for passive_id in phase["add_passives"]:
                if not passives.has(passive_id):
                    passives.append(passive_id)
            result["passives"] = passives
    return result

static func status_family(effect_id: String) -> String:
    for family in STATUS_FAMILIES:
        if (STATUS_FAMILIES[family] as Array).has(effect_id):
            return family
    return ""

## 0.0 means the status was resisted outright; otherwise the shortened duration.
static func resisted_duration(_effect_id: String, duration: float, resistance_percent: float, roll: float) -> float:
    var resist: float = minf(resistance_percent, RESISTANCE_CAP)
    if roll * 100.0 < resist:
        return 0.0
    return duration * (1.0 - resist / 100.0)
