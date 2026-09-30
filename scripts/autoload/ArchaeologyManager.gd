extends Node
## ArchaeologyManager — tracks excavation and the museum. Dig-site artefacts drop through
## the normal action loot path; donating them here rewards GP and raises completion.

const DONATE_GP := {"artefact_common": 100, "artefact_uncommon": 500, "artefact_rare": 2500, "artefact_unique": 15000}
## Museum Tokens are the donation reward that keeps on rewarding: GP is the immediate
## thanks, tokens are the museum's own currency spent on its stock (data/shop_museum.json).
const DONATE_TOKENS := {"artefact_common": 1, "artefact_uncommon": 3, "artefact_rare": 10, "artefact_unique": 30}

var excavated: Dictionary = {}   # site_id -> count
var donated: Dictionary = {}     # artefact_id -> count
var tokens: int = 0              # Museum Tokens (spend at the museum shop)

func get_site(site_id: String) -> Dictionary:
    return DataLoader.archaeology_sites.get(site_id, {})

## Called by SkillManager after a successful archaeology action.
func on_excavate(site_id: String) -> void:
    excavated[site_id] = int(excavated.get(site_id, 0)) + 1

func donate(artefact_id: String) -> bool:
    if not BankManager.has_item(artefact_id, 1):
        return false
    if not DONATE_GP.has(artefact_id):
        return false
    BankManager.remove_item(artefact_id, 1)
    donated[artefact_id] = int(donated.get(artefact_id, 0)) + 1
    PlayerData.add_gp(float(DONATE_GP[artefact_id]))
    tokens += int(DONATE_TOKENS.get(artefact_id, 0))
    EventBus.notification.emit("Donated %s: +%d GP, +%d Museum Tokens" % [
        DataLoader.get_item(artefact_id).get("name", artefact_id),
        int(DONATE_GP[artefact_id]), int(DONATE_TOKENS.get(artefact_id, 0))], "success")
    EventBus.state_refreshed.emit()
    return true

# ---------------- Museum shop ----------------
func museum_stock() -> Array:
    var out: Array = []
    for entry_id in DataLoader.shop_museum.keys():
        var e: Variant = DataLoader.shop_museum[entry_id]
        if typeof(e) == TYPE_DICTIONARY:
            out.append(e)
    return out

func can_buy_museum(entry_id: String) -> Dictionary:
    var e: Variant = DataLoader.shop_museum.get(entry_id, {})
    if typeof(e) != TYPE_DICTIONARY or (e as Dictionary).is_empty():
        return {"ok": false, "reason": "Unknown museum stock"}
    var cost: int = int((e as Dictionary).get("cost", 0))
    if tokens < cost:
        return {"ok": false, "reason": "Need %d Museum Tokens (%d)" % [cost, tokens]}
    for item_id in ((e as Dictionary).get("grant_items", {}) as Dictionary).keys():
        if not DataLoader.items.has(str(item_id)):
            return {"ok": false, "reason": "Stock references a missing item"}
    return {"ok": true, "reason": ""}

func buy_museum(entry_id: String) -> bool:
    var check: Dictionary = can_buy_museum(entry_id)
    if not bool(check["ok"]):
        EventBus.notification.emit(str(check["reason"]), "warn")
        return false
    var e: Dictionary = DataLoader.shop_museum[entry_id]
    tokens -= int(e.get("cost", 0))
    for item_id in (e.get("grant_items", {}) as Dictionary).keys():
        BankManager.add_item(str(item_id), int(e["grant_items"][item_id]))
    if float(e.get("gp", 0)) > 0.0:
        PlayerData.add_gp(float(e["gp"]))
    EventBus.notification.emit("Bought %s" % e.get("name", entry_id), "success")
    EventBus.state_refreshed.emit()
    return true

func total_donated() -> int:
    var n: int = 0
    for k in donated.keys():
        n += int(donated[k])
    return n

func serialize() -> Dictionary:
    return {"excavated": excavated, "donated": donated, "tokens": tokens}

func deserialize(d: Dictionary) -> void:
    excavated = d.get("excavated", {})
    donated = d.get("donated", {})
    tokens = int(d.get("tokens", 0))
