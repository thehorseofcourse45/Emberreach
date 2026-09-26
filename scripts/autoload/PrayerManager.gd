extends Node
## PrayerManager — up to 2 active prayers from data/prayers.json. Each active prayer
## registers its `effect` as a ModifierSource (category "prayer"); protection prayers
## are handled by CombatManager via PlayerData.active_prayers. Costs prayer points.

const MAX_ACTIVE: int = 2
const CATEGORY: String = "prayer"

func _ready() -> void:
    # After a load, re-assert the modifier sources for restored active prayers.
    EventBus.game_loaded.connect(_reapply_active)

func _reapply_active() -> void:
    for prayer_id in PlayerData.active_prayers:
        _register(prayer_id)

func get_prayer(prayer_id: String) -> Dictionary:
    return DataLoader.prayers.get(prayer_id, {})

func is_active(prayer_id: String) -> bool:
    return PlayerData.active_prayers.has(prayer_id)

## Why this prayer cannot be activated right now, or "" when it can: the player's Prayer level has
## not reached its requirement, or MAX_ACTIVE prayers are already on. The level and slot rules live
## HERE and nowhere else, so toggle() cannot enforce one thing and an automatic caller another:
## toggle turns this into the message it shows the player, while an automatic caller — a combat
## strategy's protection_prayer_auto, which the player never asked for by hand — reads it and
## stays a SILENT no-op instead of popping a warning on every fight. An unknown id is not answered
## here; the caller holds the record and can see for itself that it does not exist.
func blocked_reason(prayer_id: String) -> String:
    if PlayerData.get_level("prayer") < int(get_prayer(prayer_id).get("level", 1)):
        return "Prayer level too low"
    if PlayerData.active_prayers.size() >= MAX_ACTIVE:
        return "Only %d prayers may be active" % MAX_ACTIVE
    return ""

## Toggle a prayer on/off. Returns true if the state changed.
func toggle(prayer_id: String) -> bool:
    if is_active(prayer_id):
        deactivate(prayer_id)
        return true
    if get_prayer(prayer_id).is_empty():
        return false
    var blocked: String = blocked_reason(prayer_id)
    if blocked != "":
        EventBus.notification.emit(blocked, "warn")
        return false
    PlayerData.active_prayers.append(prayer_id)
    _register(prayer_id)
    EventBus.prayer_activated.emit(prayer_id)
    return true

func deactivate(prayer_id: String) -> void:
    var idx: int = PlayerData.active_prayers.find(prayer_id)
    if idx >= 0:
        PlayerData.active_prayers.remove_at(idx)
        EventBus.prayer_deactivated.emit(prayer_id)
    ModifierManager.unregister("%s:%s" % [CATEGORY, prayer_id])

func deactivate_all() -> void:
    for prayer_id in PlayerData.active_prayers.duplicate():
        deactivate(prayer_id)

func _register(prayer_id: String) -> void:
    var p: Dictionary = get_prayer(prayer_id)
    var effect: Dictionary = p.get("effect", {})
    if not effect.is_empty():
        ModifierManager.register("%s:%s" % [CATEGORY, prayer_id], effect, CATEGORY, p.get("name", prayer_id))

## Prayer points consumed per player attack by all active prayers.
func cost_per_attack() -> float:
    var total: float = 0.0
    for prayer_id in PlayerData.active_prayers:
        total += float(get_prayer(prayer_id).get("prayer_point_cost", 0.0))
    var reduction: float = ModifierManager.get_modifier(ModifierKeys.PRAYER_COST_REDUCTION_PERCENT)
    return total * (1.0 - reduction / 100.0)

## Spend points for one attack. Deactivates prayers if points run out.
func spend_for_attack() -> void:
    if PlayerData.active_prayers.is_empty():
        return
    var cost: float = cost_per_attack()
    if cost <= 0.0:
        return
    if PlayerData.prayer_points >= cost:
        PlayerData.add_prayer_points(-cost)
    else:
        EventBus.notification.emit("Out of Prayer Points — prayers deactivated", "warn")
        deactivate_all()
