extends Node
## ModifierManager — the heart of the game. Aggregates bonuses from ALL sources
## (equipment, potions, prayers, agility, astrology, summoning, pets, skillcapes,
## shop, mastery pool checkpoints, item mastery, township, relics, cartography POIs)
## into a single cached lookup, so gameplay code just asks one question.
##
## Stacking rule (spec): modifiers stack ADDITIVELY within the same category unless
## the key is listed in MULTIPLICATIVE_KEYS. Damage Reduction is combined with the
## Melvor rule:  total = 1 - Π(1 - dr_i/100).
##
## Performance: sources mutate rarely, queries happen every tick — so we recompute
## the cache only when a source changes (dirty flag), not per query.

var _sources: Dictionary = {}      # source_id -> ModifierSource
var _cache: Dictionary = {}        # key -> combined value
var _dirty: bool = true

## Keys whose contributions multiply instead of adding, e.g. (1+a)(1+b)-1.
const MULTIPLICATIVE_KEYS: Array[String] = [
    ModifierKeys.GLOBAL_SKILL_XP_PERCENT,   # XP multipliers in Melvor compound
    ModifierKeys.GLOBAL_MASTERY_XP_PERCENT,
]
const DAMAGE_REDUCTION_KEY: String = ModifierKeys.DAMAGE_REDUCTION_PERCENT

# ---------------- Source management ----------------
func register(id: String, modifiers: Dictionary, category: String = "generic", display_name: String = "") -> void:
    _sources[id] = ModifierSource.make(id, modifiers, category, display_name)
    _mark_dirty()

func register_source(src: ModifierSource) -> void:
    if src == null or src.id == "":
        return
    _sources[src.id] = src
    _mark_dirty()

func update(id: String, modifiers: Dictionary) -> void:
    if _sources.has(id):
        (_sources[id] as ModifierSource).modifiers = modifiers
        _mark_dirty()

func unregister(id: String) -> void:
    if _sources.erase(id):
        _mark_dirty()

func has_source(id: String) -> bool:
    return _sources.has(id)

## Remove every source in a category (e.g. all active potions on expiry).
func clear_category(category: String) -> void:
    var to_remove: Array[String] = []
    for id in _sources.keys():
        if (_sources[id] as ModifierSource).category == category:
            to_remove.append(id)
    if not to_remove.is_empty():
        for id in to_remove:
            _sources.erase(id)
        _mark_dirty()

func _mark_dirty() -> void:
    _dirty = true
    EventBus.modifiers_changed.emit()

# ---------------- Aggregation ----------------
func recompute() -> void:
    _cache.clear()
    var buckets: Dictionary = {}   # key -> Array[float]
    for id in _sources.keys():
        var src: ModifierSource = _sources[id]
        for key in src.modifiers.keys():
            if not buckets.has(key):
                buckets[key] = []
            (buckets[key] as Array).append(float(src.modifiers[key]))
    for key in buckets.keys():
        _cache[key] = _combine(key, buckets[key])
    _dirty = false

func _combine(key: String, values: Array) -> float:
    if key == DAMAGE_REDUCTION_KEY:
        # total = 1 - Π(1 - v/100), expressed as a percentage.
        var remain: float = 1.0
        for v in values:
            remain *= (1.0 - float(v) / 100.0)
        return (1.0 - remain) * 100.0
    if MULTIPLICATIVE_KEYS.has(key):
        var prod: float = 1.0
        for v in values:
            prod *= (1.0 + float(v) / 100.0)
        return (prod - 1.0) * 100.0
    var sum: float = 0.0
    for v in values:
        sum += float(v)
    return sum

func get_modifier(key: String, default: float = 0.0) -> float:
    if _dirty:
        recompute()
    return float(_cache.get(key, default))

# ---------------- Convenience queries ----------------
func get_skill_xp_multiplier(skill_id: String) -> float:
    var pct: float = get_modifier(ModifierKeys.GLOBAL_SKILL_XP_PERCENT) \
        + get_modifier(ModifierKeys.skill_key(skill_id, ModifierKeys.SUFFIX_SKILL_XP_PERCENT))
    return 1.0 + pct / 100.0

func get_mastery_xp_bonus(skill_id: String) -> float:
    var pct: float = get_modifier(ModifierKeys.GLOBAL_MASTERY_XP_PERCENT) \
        + get_modifier(ModifierKeys.skill_key(skill_id, ModifierKeys.SUFFIX_MASTERY_XP_PERCENT))
    return pct / 100.0

## final_interval = base * (1 - reduction%/100) - flat, with a floor (default 0.25s).
func get_interval(skill_id: String, base: float, floor_seconds: float = 0.25) -> float:
    var pct: float = get_modifier(ModifierKeys.skill_key(skill_id, ModifierKeys.SUFFIX_INTERVAL_PERCENT)) \
        + get_modifier(ModifierKeys.GLOBAL_SKILL_XP_PERCENT.replace("xp_percent", "interval_percent"))
    var flat: float = get_modifier(ModifierKeys.skill_key(skill_id, ModifierKeys.SUFFIX_INTERVAL_FLAT))
    var out: float = base * (1.0 - pct / 100.0) - flat
    return maxf(out, floor_seconds)

func get_doubling_chance(skill_id: String) -> float:
    return get_modifier(ModifierKeys.skill_key(skill_id, ModifierKeys.SUFFIX_DOUBLING_PERCENT))

func get_preservation_chance(skill_id: String) -> float:
    return get_modifier(ModifierKeys.skill_key(skill_id, ModifierKeys.SUFFIX_PRESERVATION_PERCENT))

func get_resource_flat(skill_id: String) -> int:
    return int(get_modifier(ModifierKeys.skill_key(skill_id, ModifierKeys.SUFFIX_RESOURCE_FLAT)))

func get_hidden_levels(skill_id: String) -> int:
    return int(get_modifier(ModifierKeys.skill_key(skill_id, ModifierKeys.SUFFIX_HIDDEN_LEVELS)))

func get_accuracy_percent(style: String) -> float:
    var key: String = "%s_accuracy_percent" % style
    return get_modifier(key) + get_modifier(ModifierKeys.GLOBAL_ACCURACY_PERCENT)

func get_evasion_percent(style: String) -> float:
    return get_modifier("%s_evasion_percent" % style)

func get_max_hit_percent(style: String) -> float:
    return get_modifier("%s_max_hit_percent" % style)

func get_max_hit_flat(style: String) -> float:
    return get_modifier("%s_max_hit_flat" % style)

func get_damage_reduction() -> float:
    return get_modifier(DAMAGE_REDUCTION_KEY)

func get_crit_chance() -> float:
    return get_modifier(ModifierKeys.CRIT_CHANCE_PERCENT)

func get_crit_multiplier() -> float:
    return get_modifier(ModifierKeys.CRIT_MULTIPLIER_PERCENT, 50.0)

func get_life_steal() -> float:
    return get_modifier(ModifierKeys.LIFE_STEAL_PERCENT)

func get_attack_interval(base: float, floor_seconds: float = 0.25) -> float:
    var pct: float = get_modifier(ModifierKeys.ATTACK_INTERVAL_PERCENT)
    var flat: float = get_modifier(ModifierKeys.ATTACK_INTERVAL_FLAT)
    return maxf(base * (1.0 - pct / 100.0) - flat, floor_seconds)

# ---------------- Persistence & debug ----------------
func serialize() -> Dictionary:
    var out: Dictionary = {}
    for id in _sources.keys():
        var s: ModifierSource = _sources[id]
        out[id] = {"modifiers": s.modifiers, "category": s.category, "display_name": s.display_name}
    return out

func deserialize(data: Dictionary) -> void:
    _sources.clear()
    for id in data.keys():
        var e: Dictionary = data[id]
        register(id, e.get("modifiers", {}), e.get("category", "generic"), e.get("display_name", ""))

func debug_active_keys() -> Array:
    if _dirty:
        recompute()
    return _cache.keys()
