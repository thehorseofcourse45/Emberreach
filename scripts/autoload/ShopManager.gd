extends Node
## ShopManager — purchases from data/shop.json. Owns the "shop" modifier category:
## each purchased upgrade registers its `effect` dict as a ModifierSource so every
## bonus flows through ModifierManager (never applied inline).

const CATEGORY: String = "shop"

func _ready() -> void:
    # Re-apply any upgrades already owned (e.g. right after a save load).
    EventBus.game_loaded.connect(apply_all)

func get_upgrade(upgrade_id: String) -> Dictionary:
    return DataLoader.get_shop_upgrade(upgrade_id)

func is_purchased(upgrade_id: String) -> bool:
    return int(PlayerData.shop_upgrades.get(upgrade_id, 0)) > 0

func has_requirement(upgrade_id: String) -> bool:
    var u: Dictionary = get_upgrade(upgrade_id)
    if u.is_empty():
        return false
    for req in u.get("requires", []):
        if not is_purchased(req):
            return false
    for skill_id in u.get("requires_skill", {}).keys():
        if PlayerData.get_level(skill_id) < int(u["requires_skill"][skill_id]):
            return false
    if bool(u.get("requires_all_skills_99", false)):
        for skill_id in DataLoader.get_skill_ids():
            if PlayerData.get_level(skill_id) < 99:
                return false
    var dungeon: String = u.get("requires_dungeon", "")
    if dungeon != "" and not PlayerData.completion_log.get("dungeons", {}).has(dungeon):
        return false
    return true

## The currency an upgrade is priced in: "abyssal_coins", or gold for anything else.
func currency_of(upgrade_id: String) -> String:
    return "abyssal_coins" if str(get_upgrade(upgrade_id).get("currency", "gp")) == "abyssal_coins" else "gp"

func balance(currency: String) -> float:
    return PlayerData.abyssal_coins if currency == "abyssal_coins" else PlayerData.gp

func currency_label(currency: String) -> String:
    return "Abyssal Coins" if currency == "abyssal_coins" else "GP"

func _spend(currency: String, amount: float) -> bool:
    return PlayerData.spend_abyssal_coins(amount) if currency == "abyssal_coins" else PlayerData.spend_gp(amount)

## Returns {ok: bool, reason: String} so the UI can show *why* a buy is blocked.
func can_buy(upgrade_id: String) -> Dictionary:
    var u: Dictionary = get_upgrade(upgrade_id)
    if u.is_empty():
        return {"ok": false, "reason": "Unknown upgrade"}
    var max_count: int = int(u.get("max", 0))
    if max_count > 0 and int(PlayerData.shop_upgrades.get(upgrade_id, 0)) >= max_count:
        return {"ok": false, "reason": "Maximum owned"}
    if not has_requirement(upgrade_id):
        return {"ok": false, "reason": "Requirements not met"}
    var cost: float = float(u.get("cost", 0))
    var currency: String = currency_of(upgrade_id)
    if balance(currency) < cost:
        return {"ok": false, "reason": "Not enough %s" % currency_label(currency)}
    return {"ok": true, "reason": ""}

func buy(upgrade_id: String) -> bool:
    var check: Dictionary = can_buy(upgrade_id)
    if not bool(check["ok"]):
        EventBus.notification.emit("Cannot buy: %s" % check["reason"], "warn")
        return false
    var u: Dictionary = get_upgrade(upgrade_id)
    if not _spend(currency_of(upgrade_id), float(u.get("cost", 0))):
        return false
    PlayerData.shop_upgrades[upgrade_id] = int(PlayerData.shop_upgrades.get(upgrade_id, 0)) + 1
    _apply_one(upgrade_id)
    EventBus.shop_upgrade_purchased.emit(upgrade_id)
    EventBus.notification.emit("Purchased %s" % u.get("name", upgrade_id), "success")
    return true

## (Re)register every owned upgrade's modifiers. Safe to call repeatedly.
func apply_all() -> void:
    for upgrade_id in PlayerData.shop_upgrades.keys():
        _apply_one(upgrade_id)

func _apply_one(upgrade_id: String) -> void:
    var u: Dictionary = get_upgrade(upgrade_id)
    if u.is_empty():
        return
    var effect: Dictionary = u.get("effect", {})
    if not effect.is_empty():
        ModifierManager.register("%s:%s" % [CATEGORY, upgrade_id], effect, CATEGORY, u.get("name", upgrade_id))
    if u.get("type", "") == "auto_eat":
        PlayerData.settings["auto_eat_tier"] = int(u.get("tier", 0))

# =========================================================================
#  The general store
# =========================================================================

## Buying a resource is repeatable, unlike an upgrade, so the gate is the three questions the
## UI already asks everywhere: do you have the gold, do you have the skill level, is there room.
## No ownership count: a crate of bronze bars is not a thing you finish buying.
func store_offers() -> Array:
    var out: Array = []
    for offer_id in DataLoader.shop_store.keys():
        var offer: Variant = DataLoader.shop_store[offer_id]
        if typeof(offer) == TYPE_DICTIONARY:
            out.append(offer)
    out.sort_custom(func(a, b):
        var pa: float = float((a as Dictionary).get("cost", 0))
        var pb: float = float((b as Dictionary).get("cost", 0))
        if is_equal_approx(pa, pb):
            return str((a as Dictionary).get("name", "")) < str((b as Dictionary).get("name", ""))
        return pa < pb)
    return out

func get_store_offer(offer_id: String) -> Dictionary:
    return DataLoader.shop_store.get(offer_id, {})

## The level a stock line is gated behind, or {"", 0} when it is always available.
func store_requirement(offer: Dictionary) -> Dictionary:
    var req: Dictionary = offer.get("requires_skill", {}) as Dictionary
    for skill_id in req.keys():
        return {"skill": str(skill_id), "level": int(req[skill_id])}
    return {"skill": "", "level": 0}

func can_buy_store(offer_id: String) -> Dictionary:
    var offer: Dictionary = get_store_offer(offer_id)
    if offer.is_empty():
        return {"ok": false, "reason": "Unknown item"}
    var need: Dictionary = store_requirement(offer)
    var skill_id: String = str(need["skill"])
    if skill_id != "" and PlayerData.get_level(skill_id) < int(need["level"]):
        return {"ok": false, "reason": "%s level %d" % [
            str(DataLoader.get_skill(skill_id).get("name", skill_id)), int(need["level"])]}
    var cost: float = float(offer.get("cost", 0))
    if PlayerData.gp < cost:
        return {"ok": false, "reason": "Needs %s GP" % UIStyle.fmt_exact(cost)}
    return {"ok": true, "reason": ""}

## The guaranteed path makes room if storage is full, so a paid-for crate is never lost.
func buy_store(offer_id: String) -> bool:
    var check: Dictionary = can_buy_store(offer_id)
    if not bool(check["ok"]):
        EventBus.notification.emit("Cannot buy: %s" % str(check["reason"]), "warn")
        return false
    var offer: Dictionary = get_store_offer(offer_id)
    var cost: float = float(offer.get("cost", 0))
    if not PlayerData.spend_gp(cost):
        return false
    var qty: int = maxi(1, int(offer.get("quantity", 1)))
    BankManager.add_item_guaranteed(str(offer.get("item_id", "")), qty)
    EventBus.notification.emit("Bought %s ×%d for %s GP." % [
        str(offer.get("name", offer_id)), qty, UIStyle.fmt_exact(cost)], "success")
    EventBus.bank_changed.emit()
    return true

# =========================================================================
#  The mastery stall
# =========================================================================

## Skillcapes are a memento of a finished skill and the two completion capes are the memento of
## finishing all of them. They live at a stall rather than in a drop table: that puts a bounded,
## lifetime gold sink at the end of every skill line and gives the cape items in the item table a
## real acquisition path instead of leaving them as decoration.
const CAPE_SLOT: int = 5
const STALL_ALL_SKILLS: Dictionary = {
    "max_skillcape": 99,
    "cape_of_completion": 120,
}

## Every item the stall can sell: capes gated on a single skill, plus the completion capes.
func stall_item_ids() -> Array[String]:
    var ids: Array[String] = []
    for key in DataLoader.items.keys():
        var item_id: String = str(key)
        var item: Dictionary = DataLoader.items[key]
        if STALL_ALL_SKILLS.has(item_id):
            ids.append(item_id)
            continue
        if int(item.get("equipment_slot", -1)) != CAPE_SLOT:
            continue
        if (item.get("requires_level", {}) as Dictionary).is_empty():
            continue
        ids.append(item_id)
    return ids

## Offers ready for the UI: {item_id, name, cost, owned, label, current, required, met, hint}.
func stall_offers() -> Array:
    var out: Array = []
    for item_id in stall_item_ids():
        var item: Dictionary = DataLoader.items[item_id]
        var offer: Dictionary = {
            "item_id": item_id,
            "name": str(item.get("name", item_id)),
            "cost": float(item.get("sell_price", 0)),
            "owned": int(BankManager.get_count(item_id)) > 0 or EquipmentManager.is_equipped(item_id),
            "effect": str(item.get("passive_modifiers", {})),
        }
        if STALL_ALL_SKILLS.has(item_id):
            var need: int = int(STALL_ALL_SKILLS[item_id])
            var lowest: int = 999
            var lowest_id: String = ""
            for skill_id in DataLoader.get_skill_ids():
                var lv: int = PlayerData.get_level(skill_id)
                if lv < lowest:
                    lowest = lv
                    lowest_id = skill_id
            offer["label"] = "Every skill at level %d" % need
            offer["current"] = float(lowest)
            offer["required"] = float(need)
            offer["met"] = lowest >= need
            offer["hint"] = "Lowest is %s" % str(DataLoader.get_skill(lowest_id).get("name", lowest_id))
        else:
            var req: Dictionary = item.get("requires_level", {})
            var skill_id: String = str(req.get("skill", ""))
            var power: int = int(req.get("level", 1))
            var level: int = PlayerData.get_level(skill_id)
            offer["label"] = "%s level %d" % [str(DataLoader.get_skill(skill_id).get("name", skill_id)), power]
            offer["current"] = float(level)
            offer["required"] = float(power)
            offer["met"] = level >= power
            offer["hint"] = "Train %s to earn this cape" % str(DataLoader.get_skill(skill_id).get("name", skill_id))
        out.append(offer)
    out.sort_custom(func(a, b):
        return float((a as Dictionary)["cost"]) < float((b as Dictionary)["cost"]))
    return out

func can_buy_stall(item_id: String) -> Dictionary:
    if not stall_item_ids().has(item_id):
        return {"ok": false, "reason": "Not sold here"}
    for offer in stall_offers():
        if str((offer as Dictionary)["item_id"]) != item_id:
            continue
        if not bool((offer as Dictionary)["met"]):
            return {"ok": false, "reason": "%s not yet earned" % str((offer as Dictionary)["label"])}
        var cost: float = float((offer as Dictionary)["cost"])
        if PlayerData.gp < cost:
            return {"ok": false, "reason": "Needs %s GP" % UIStyle.fmt_exact(cost)}
        return {"ok": true, "reason": ""}
    return {"ok": false, "reason": "Unknown item"}

## Buying a cape never risks the item: the guaranteed path makes room for it if storage is full.
func buy_stall(item_id: String) -> bool:
    var check: Dictionary = can_buy_stall(item_id)
    if not bool(check["ok"]):
        EventBus.notification.emit("Cannot buy: %s" % str(check["reason"]), "warn")
        return false
    for offer in stall_offers():
        if str((offer as Dictionary)["item_id"]) != item_id:
            continue
        if not PlayerData.spend_gp(float((offer as Dictionary)["cost"])):
            return false
        BankManager.add_item_guaranteed(item_id, 1)
        EventBus.notification.emit("The stall hands over a %s" % str((offer as Dictionary)["name"]), "success")
        EventBus.bank_changed.emit()
        return true
    return false
