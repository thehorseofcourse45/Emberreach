extends Node
## AstrologyManager — buy constellation stars with Stardust; each purchased star registers
## a permanent modifier source.

const CATEGORY: String = "astrology"

var purchased: Dictionary = {}   # star_id -> true

func get_constellation(constellation_id: String) -> Dictionary:
    return DataLoader.constellations.get(constellation_id, {})

func is_purchased(star_id: String) -> bool:
    return purchased.has(star_id)

func star_cost(constellation_id: String, star_id: String) -> int:
    for s in get_constellation(constellation_id).get("stars", []):
        if s.get("id", "") == star_id:
            return int(s.get("cost", 0))
    return -1

func can_buy(constellation_id: String, star_id: String) -> Dictionary:
    var c: Dictionary = get_constellation(constellation_id)
    if c.is_empty():
        return {"ok": false, "reason": "Unknown constellation"}
    if PlayerData.get_level("astrology") < int(c.get("level_required", 1)):
        return {"ok": false, "reason": "Astrology level too low"}
    if is_purchased(star_id):
        return {"ok": false, "reason": "Already owned"}
    var cost: int = star_cost(constellation_id, star_id)
    if cost < 0:
        return {"ok": false, "reason": "Unknown star"}
    if BankManager.get_count("stardust") < cost:
        return {"ok": false, "reason": "Not enough Stardust"}
    return {"ok": true, "reason": ""}

func buy_star(constellation_id: String, star_id: String) -> bool:
    var check: Dictionary = can_buy(constellation_id, star_id)
    if not bool(check["ok"]):
        EventBus.notification.emit("Cannot buy star: %s" % check["reason"], "warn")
        return false
    BankManager.remove_item("stardust", star_cost(constellation_id, star_id))
    purchased[star_id] = true
    _reregister()
    EventBus.notification.emit("Star purchased: %s" % star_id, "success")
    return true

func _reregister() -> void:
    ModifierManager.unregister("%s:stars" % CATEGORY)
    var mods: Dictionary = {}
    for cid in DataLoader.constellations.keys():
        for s in DataLoader.constellations[cid].get("stars", []):
            if is_purchased(s.get("id", "")):
                for k in s.get("effect", {}).keys():
                    mods[k] = float(mods.get(k, 0.0)) + float(s["effect"][k])
    if not mods.is_empty():
        ModifierManager.register("%s:stars" % CATEGORY, mods, CATEGORY, "Constellation stars")

func serialize() -> Dictionary:
    return {"purchased": purchased}

func deserialize(d: Dictionary) -> void:
    purchased = d.get("purchased", {})
    _reregister()
