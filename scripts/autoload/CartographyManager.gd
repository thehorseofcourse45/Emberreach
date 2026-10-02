extends Node
## CartographyManager — a hex world map: travel for GP, survey to reveal Points of
## Interest, whose permanent effects register as modifier sources. Ships discount travel.

const CATEGORY: String = "poi"
const DEFAULT_SHIP: String = "river_skiff"

var discovered: Dictionary = {}   # hex_id -> true (visited)
var surveyed: Dictionary = {}     # hex_id -> true (POI claimed)
var ship: String = DEFAULT_SHIP           # hull currently under the player
var ships_owned: Array[String] = [DEFAULT_SHIP]

func get_hex(hex_id: String) -> Dictionary:
    return DataLoader.cartography_hexes.get(hex_id, {})

func is_discovered(hex_id: String) -> bool:
    return discovered.has(hex_id)

func travel(hex_id: String) -> bool:
    var h: Dictionary = get_hex(hex_id)
    if h.is_empty():
        return false
    var base_cost: float = float(h.get("travel_cost", 0))
    var cost: float = base_cost * travel_percent() / 100.0
    if not PlayerData.spend_gp(cost):
        EventBus.notification.emit("Not enough GP to travel", "warn")
        return false
    if not discovered.has(hex_id):
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
    var value: Variant = h.get("poi", {})
    var poi: Dictionary = value if value is Dictionary else {}
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

# ---------------- Ships ----------------
## Hulls in upgrade order; the first is owned from the start and each later one
## charges a smaller percentage of the base travel cost.
func ships() -> Array:
    var out: Array = []
    for ship_id in DataLoader.cartography_ships.keys():
        var s: Variant = DataLoader.cartography_ships[ship_id]
        if typeof(s) == TYPE_DICTIONARY:
            out.append(s)
    out.sort_custom(func(a, b): return int((a as Dictionary).get("order", 0)) < int((b as Dictionary).get("order", 0)))
    return out

func current_ship() -> Dictionary:
    var s: Variant = DataLoader.cartography_ships.get(ship, {})
    return s if typeof(s) == TYPE_DICTIONARY else {}

## Percent of the base travel cost this hull charges (100 = no discount).
func travel_percent() -> float:
    var s: Dictionary = current_ship()
    if s.is_empty():
        return 100.0
    return float(s.get("travel_cost_percent", 100))

func can_buy_ship(ship_id: String) -> Dictionary:
    var s: Variant = DataLoader.cartography_ships.get(ship_id, {})
    if typeof(s) != TYPE_DICTIONARY or (s as Dictionary).is_empty():
        return {"ok": false, "reason": "Unknown hull"}
    if ships_owned.has(ship_id):
        return {"ok": false, "reason": "Already owned"}
    var order: int = int((s as Dictionary).get("order", 1))
    var prev_owned: bool = order <= 1
    for owned_id in ships_owned:
        var o: Variant = DataLoader.cartography_ships.get(str(owned_id), {})
        if typeof(o) == TYPE_DICTIONARY and int((o as Dictionary).get("order", 0)) == order - 1:
            prev_owned = true
    if not prev_owned:
        return {"ok": false, "reason": "Buy the previous hull first"}
    var cost: float = float((s as Dictionary).get("cost", 0))
    if PlayerData.gp < cost:
        return {"ok": false, "reason": "Not enough GP (%s / %s)" % [UIStyle.fmt(PlayerData.gp), UIStyle.fmt(cost)]}
    return {"ok": true, "reason": ""}

func buy_ship(ship_id: String) -> bool:
    var check: Dictionary = can_buy_ship(ship_id)
    if not bool(check["ok"]):
        EventBus.notification.emit(str(check["reason"]), "warn")
        return false
    var s: Dictionary = DataLoader.cartography_ships[ship_id]
    if not PlayerData.spend_gp(float(s.get("cost", 0))):
        return false
    ships_owned.append(ship_id)
    ship = ship_id
    EventBus.notification.emit("Bought %s — travel now costs %d%% of base" % [
        s.get("name", ship_id), int(travel_percent())], "success")
    EventBus.state_refreshed.emit()
    return true

## Sail an already-owned hull (a newly bought hull becomes the active one).
func set_ship(ship_id: String) -> bool:
    if not ships_owned.has(ship_id) or ship == ship_id:
        return false
    ship = ship_id
    EventBus.state_refreshed.emit()
    return true

func _reregister() -> void:
    ModifierManager.unregister("%s:effects" % CATEGORY)
    var mods: Dictionary = {}
    for hex_id in surveyed.keys():
        var value: Variant = get_hex(hex_id).get("poi", {})
        var eff: Dictionary = value.get("effect", {}) if value is Dictionary else {}
        for k in eff.keys():
            mods[k] = float(mods.get(k, 0.0)) + float(eff[k])
    if not mods.is_empty():
        ModifierManager.register("%s:effects" % CATEGORY, mods, CATEGORY, "Points of Interest")

func serialize() -> Dictionary:
    return {"discovered": discovered, "surveyed": surveyed,
        "ship": ship, "ships_owned": ships_owned}

func deserialize(d: Dictionary) -> void:
    discovered = d.get("discovered", {})
    surveyed = d.get("surveyed", {})
    ship = str(d.get("ship", DEFAULT_SHIP))
    ships_owned = []
    for v in (d.get("ships_owned", [DEFAULT_SHIP]) as Array):
        ships_owned.append(str(v))
    if ships_owned.is_empty():
        ships_owned = [DEFAULT_SHIP]
    if not ships_owned.has(ship):
        ship = ships_owned[ships_owned.size() - 1]
    _reregister()
