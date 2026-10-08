extends Node
## CartographyManager — a hex world map: travel for GP, survey to reveal Points of
## Interest, whose permanent effects register as modifier sources. Ships discount travel.

const CATEGORY: String = "poi"
const DEFAULT_SHIP: String = "river_skiff"

var discovered: Dictionary = {}   # hex_id -> true (visited)
var surveyed: Dictionary = {}     # hex_id -> true (POI claimed)
var ship: String = DEFAULT_SHIP           # hull currently under the player
var ships_owned: Array[String] = [DEFAULT_SHIP]
## The last region travelled to; the map draws the ship token here.
var current_hex: String = ""

func get_hex(hex_id: String) -> Dictionary:
    return DataLoader.cartography_hexes.get(hex_id, {})

func is_discovered(hex_id: String) -> bool:
    return discovered.has(hex_id)

## The map is a frontier: a region is reachable from the origin or from a charted neighbour.
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 1)]
var _by_coord: Dictionary = {}   # Vector2i(q, r) -> hex_id, built on first use

func coord_of(hex_id: String) -> Vector2i:
    var h: Dictionary = get_hex(hex_id)
    return Vector2i(int(h.get("q", 0)), int(h.get("r", 0)))

func hex_at(c: Vector2i) -> String:
    if _by_coord.is_empty():
        for id in DataLoader.cartography_hexes.keys():
            _by_coord[coord_of(str(id))] = str(id)
    return str(_by_coord.get(c, ""))

## Terrain rules from data/cartography_terrain.json; unlisted terrain uses the defaults.
func terrain_rule(hex_id: String) -> Dictionary:
    return DataLoader.cartography_terrain.get(str(get_hex(hex_id).get("terrain", "")), {})

func travel_cost(hex_id: String) -> float:
    return float(get_hex(hex_id).get("travel_cost", 0)) * float(terrain_rule(hex_id).get("cost_mult", 1.0)) * travel_percent() / 100.0

func survey_reveals(hex_id: String) -> int:
    return int(terrain_rule(hex_id).get("reveals", 12))

## Why a region cannot be travelled to, or "" when it can.
func travel_block(hex_id: String) -> String:
    if get_hex(hex_id).is_empty():
        return "Unknown region"
    if discovered.has(hex_id):
        return ""
    var c: Vector2i = coord_of(hex_id)
    if c != Vector2i.ZERO:
        var linked: bool = false
        for d in NEIGHBOURS:
            if discovered.has(hex_at(c + d)):
                linked = true
                break
        if not linked:
            return "Chart a neighbouring region first"
    var need: int = int(terrain_rule(hex_id).get("min_ship_order", 1))
    if int(current_ship().get("order", 1)) < need:
        for s in ships():
            if int(s.get("order", 0)) == need:
                return "Sail the %s or better to reach this terrain" % str(s.get("name", "next hull"))
        return "Needs a larger hull"
    return ""

func travel(hex_id: String) -> bool:
    var h: Dictionary = get_hex(hex_id)
    if h.is_empty():
        return false
    var block: String = travel_block(hex_id)
    if block != "":
        EventBus.notification.emit(block, "warn")
        return false
    var cost: float = travel_cost(hex_id)
    if not PlayerData.spend_gp(cost):
        EventBus.notification.emit("Not enough GP to travel", "warn")
        return false
    if not discovered.has(hex_id):
        discovered[hex_id] = true
        PlayerData.add_xp("cartography", float(h.get("survey_xp", 10)) * ModifierManager.get_skill_xp_multiplier("cartography"))
    current_hex = hex_id
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
    # Region sets: every landmark on one terrain claimed grants that terrain's "modifiers".
    ModifierManager.unregister("%s:regions" % CATEGORY)
    var sets: Dictionary = {}
    for terrain in DataLoader.cartography_terrain.keys():
        var bonus: Dictionary = DataLoader.cartography_terrain[terrain].get("modifiers", {})
        var prog: Vector2i = terrain_progress(str(terrain))
        if bonus.is_empty() or prog.y == 0 or prog.x < prog.y:
            continue
        for key in bonus.keys():
            sets[key] = float(sets.get(key, 0.0)) + float(bonus[key])
    if not sets.is_empty():
        ModifierManager.register("%s:regions" % CATEGORY, sets, CATEGORY, "Region sets")

## Landmarks on one terrain type: x = claimed, y = total.
func terrain_progress(terrain: String) -> Vector2i:
    var out := Vector2i.ZERO
    for id in DataLoader.cartography_hexes.keys():
        var h: Dictionary = DataLoader.cartography_hexes[id]
        if str(h.get("terrain", "")) != terrain or (h.get("poi", {}) as Dictionary).is_empty():
            continue
        out.y += 1
        if surveyed.has(id):
            out.x += 1
    return out

func serialize() -> Dictionary:
    return {"discovered": discovered, "surveyed": surveyed,
        "ship": ship, "ships_owned": ships_owned, "current_hex": current_hex}

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
    # The origin region is home: always charted, so its neighbours are the first frontier.
    var origin: String = hex_at(Vector2i.ZERO)
    if origin != "":
        discovered[origin] = true
    current_hex = str(d.get("current_hex", origin))
    if not discovered.has(current_hex): current_hex = origin
    _reregister()
