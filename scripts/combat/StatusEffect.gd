class_name StatusEffect
extends RefCounted
## A runtime status effect on the player or a monster.
## Kinds: stun | sleep | dot | slow | debuff | buff.

enum Kind { STUN, SLEEP, DOT, SLOW, DEBUFF, BUFF }

var id: String = ""
var display_name: String = ""
var kind: Kind = Kind.DEBUFF
var duration: float = 0.0           ## remaining seconds
var tick_interval: float = 1.0      ## for DOT
var tick_timer: float = 0.0
var damage_per_tick: float = 0.0
var damage_type: String = "normal"  ## normal | pure | abyssal
var damage_taken_percent: float = 0.0  ## e.g. Stun +30, Sleep +20, Crystallize +50
var attack_interval_percent: float = 0.0  ## Slow
var damage_dealt_percent: float = 0.0  ## Debuffs: negative weakens the afflicted one's own hits
var source_id: String = ""

const TABLE := {
    "stun": {"kind": Kind.STUN, "damage_taken_percent": 30.0, "blocks_attack": true},
    "freeze": {"kind": Kind.STUN, "damage_taken_percent": 30.0, "blocks_attack": true},
    "sleep": {"kind": Kind.SLEEP, "damage_taken_percent": 20.0, "blocks_attack": true},
    "crystallize": {"kind": Kind.STUN, "damage_taken_percent": 50.0, "blocks_attack": true},
    "burn": {"kind": Kind.DOT, "tick_interval": 1.0},
    "poison": {"kind": Kind.DOT, "tick_interval": 1.0},
    "bleed": {"kind": Kind.DOT, "tick_interval": 1.0},
    "slow": {"kind": Kind.SLOW, "attack_interval_percent": 30.0},
    "fear": {"kind": Kind.DEBUFF, "damage_dealt_percent": -25.0},
    "silence": {"kind": Kind.DEBUFF, "damage_dealt_percent": -25.0},
    "curse": {"kind": Kind.DEBUFF, "damage_dealt_percent": -20.0, "damage_taken_percent": 10.0},
    "blight": {"kind": Kind.DOT},
    "laceration": {"kind": Kind.DOT},
    "voidburst": {"kind": Kind.DOT},
    "eldritch_curse": {"kind": Kind.DEBUFF, "damage_dealt_percent": -30.0, "damage_taken_percent": 15.0},
    "ablaze": {"kind": Kind.DOT},
    "toxin": {"kind": Kind.DOT},
    "deadly_poison": {"kind": Kind.DOT},
    "frostburn": {"kind": Kind.DOT},
    "corruption": {"kind": Kind.DEBUFF, "damage_dealt_percent": -20.0, "damage_taken_percent": 15.0},
}

static func create(effect_id: String, p_duration: float, p_damage_per_tick: float = 0.0,
        p_source: String = "") -> StatusEffect:
    var e := StatusEffect.new()
    e.id = effect_id
    e.display_name = effect_id.capitalize()
    var def: Dictionary = TABLE.get(effect_id, {})
    e.kind = def.get("kind", Kind.DEBUFF)
    e.tick_interval = float(def.get("tick_interval", 1.0))
    e.damage_taken_percent = float(def.get("damage_taken_percent", 0.0))
    e.attack_interval_percent = float(def.get("attack_interval_percent", 0.0))
    e.damage_dealt_percent = float(def.get("damage_dealt_percent", 0.0))
    e.duration = p_duration
    e.damage_per_tick = p_damage_per_tick
    e.source_id = p_source
    return e

## Sum one numeric field over a list of effects (slow, damage taken, damage dealt).
static func total(list: Array, field: String) -> float:
    var t: float = 0.0
    for e in list:
        t += float(e.get(field))
    return t

func blocks_attack() -> bool:
    return kind == Kind.STUN or kind == Kind.SLEEP

## Advance by delta; returns damage dealt this step (0 if none).
func tick(delta: float) -> float:
    duration -= delta
    if kind != Kind.DOT or damage_per_tick <= 0.0:
        return 0.0
    var dmg: float = 0.0
    tick_timer += delta
    while tick_timer >= tick_interval:
        tick_timer -= tick_interval
        dmg += damage_per_tick
    return dmg

func is_expired() -> bool:
    return duration <= 0.0

func serialize() -> Dictionary:
    return {"id": id, "duration": duration, "damage_per_tick": damage_per_tick, "source_id": source_id, "tick_timer": tick_timer}

static func from_save(value: Variant) -> StatusEffect:
    if not value is Dictionary or not TABLE.has(str(value.get("id", ""))): return null
    for key in ["duration", "damage_per_tick", "tick_timer"]:
        var number: Variant = value.get(key, 0)
        if not (number is float or number is int) or not is_finite(float(number)) or float(number) < 0: return null
    if float(value.get("duration", 0)) <= 0: return null
    var effect: StatusEffect = create(str(value.id), float(value.duration), float(value.get("damage_per_tick", 0)), str(value.get("source_id", "")))
    effect.tick_timer = fmod(float(value.get("tick_timer", 0)), effect.tick_interval)
    return effect
