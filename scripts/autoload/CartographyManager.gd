extends Node
## CartographyManager — a hex world map: travel for GP, survey to reveal Points of
## Interest, whose permanent effects register as modifier sources.

const CATEGORY: String = "poi"

var discovered: Dictionary = {}   # hex_id -> true (visited)
var surveyed: Dictionary = {}     # hex_id -> true (POI claimed)

func get_hex(hex_id: String) -> Dictionary:
    return DataLoader.cartography_hexes.get(hex_id, {})

func is_discovered(hex_id: String) -> bool:
    return discovered.has(hex_id)

func travel(hex_id: String) -> bool:
    var h: Dictionary = get_hex(hex_id)
    if h.is_empty():
        return false
    var cost: float = float(h.get("travel_cost", 0))
    if not PlayerData.spend_gp(cost):
        EventBus.notification.emit("Not enough GP to travel", "warn")
        return false
    discovered[hex_id] = true
    PlayerData.add_xp("cartography", float(h.get("survey_xp", 10)) * ModifierManager.get_skill_xp_multiplier("cartography"))
    return true

## Survey the current hex; claim its POI reward once.
func survey(hex_id: String) -> Dictionary:
    var h: Dictionary = get_hex(hex_id)
    if h.is_empty() or not is_discovered(hex_id):
        return {}
    if surveyed.has(hex_id):
        return {}
    var poi: Dictionary = h.get("poi", {})
    if poi.is_empty():
        return {}
    surveyed[hex_id] = true
    var reward: Dictionary = poi.get("reward", {})
    if reward.has("gp"):
        PlayerData.add_gp(float(reward["gp"]))
    for item_id in reward.get("items", {}).keys():
        BankManager.add_item(item_id, int(reward["items"][item_id]))
    _reregister()
    EventBus.notification.emit("Discovered %s" % poi.get("name", "POI"), "success")
    return poi

func _reregister() -> void:
    ModifierManager.unregister("%s:effects" % CATEGORY)
    var mods: Dictionary = {}
    for hex_id in surveyed.keys():
        var eff: Dictionary = get_hex(hex_id).get("poi", {}).get("effect", {})
        for k in eff.keys():
            mods[k] = float(mods.get(k, 0.0)) + float(eff[k])
    if not mods.is_empty():
        ModifierManager.register("%s:effects" % CATEGORY, mods, CATEGORY, "Points of Interest")

func serialize() -> Dictionary:
    return {"discovered": discovered, "surveyed": surveyed}

func deserialize(d: Dictionary) -> void:
    discovered = d.get("discovered", {})
    surveyed = d.get("surveyed", {})
    _reregister()
