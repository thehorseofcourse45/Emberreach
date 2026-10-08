extends Node
## EquipmentManager — 14 equipment slots, saved equipment sets, stat aggregation and
## special-attack lookup. Every equipped item registers its passive modifiers with
## ModifierManager under id "item:<slot>", so stat math flows through one place.

const SLOT_COUNT: int = 15   # 0..14 (see ItemData.EquipmentSlot). SUMMON_1/2 and PASSIVE included.

## slot_index -> item_id ("" when empty)
var slots: Dictionary = {}
## Saved loadouts: Array[ Dictionary(slot->item_id) ]
var sets: Array = []
var active_set: int = 0
var set_support: Dictionary = {}
const FOOD_SLOT_COUNT: int = 3
## Food slots reference Storage stacks; assigning never moves or duplicates supplies.
var food_slots: Array[String] = ["", "", ""]

# ---------------- Equip / unequip ----------------
func equip(item_id: String) -> bool:
    var data: Dictionary = DataLoader.get_item(item_id)
    if data.is_empty():
        return false
    var slot: int = int(data.get("equipment_slot", -1))
    if slot < 0:
        return false
    if CombatManager.equipment_locked():
        EventBus.notification.emit("Equipment is locked during this expedition", "warn")
        return false
    if not _meets_requirements(data):
        EventBus.notification.emit("Requirements not met for %s" % data.get("name", item_id), "warn")
        return false
    if not BankManager.has_item(item_id, 1):
        return false
    # Two-handed weapons occupy the shield slot too.
    if bool(data.get("is_two_handed", false)):
        unequip(ItemData.EquipmentSlot.SHIELD)
    elif slot == ItemData.EquipmentSlot.SHIELD and bool(DataLoader.get_item(get_equipped(ItemData.EquipmentSlot.WEAPON)).get("is_two_handed", false)):
        unequip(ItemData.EquipmentSlot.WEAPON)
    BankManager.remove_item(item_id, 1)
    if slots.has(slot) and slots[slot] != "":
        BankManager.return_item(slots[slot], 1)   # return the displaced item
    slots[slot] = item_id
    _reregister_modifiers()
    EventBus.item_equipped.emit(slot, item_id)
    return true

func unequip(slot: int) -> bool:
    if not slots.has(slot) or slots[slot] == "":
        return false
    if CombatManager.equipment_locked():
        EventBus.notification.emit("Equipment is locked during this expedition", "warn")
        return false
    var item_id: String = slots[slot]
    BankManager.return_item(item_id, 1)
    slots.erase(slot)
    _reregister_modifiers()
    EventBus.item_unequipped.emit(slot, item_id)
    return true

func get_equipped(slot: int) -> String:
    return slots.get(slot, "")

func is_equipped(item_id: String) -> bool:
    return slots.values().has(item_id)

func _meets_requirements(data: Dictionary) -> bool:
    for skill_id in data.get("level_requirements", {}).keys():
        if PlayerData.get_level(skill_id) < int(data["level_requirements"][skill_id]):
            return false
    # Capes carry their gate in `requires_level` ({skill, level}); the mastery stall is the only
    # shop for them, and this keeps the requirement true even for a cape obtained another way.
    var cape_gate: Dictionary = data.get("requires_level", {})
    if not cape_gate.is_empty():
        if PlayerData.get_level(str(cape_gate.get("skill", ""))) < int(cape_gate.get("level", 0)):
            return false
    return true

# ---------------- Upgrades ----------------
## An item row carrying `upgrade_path` + `upgrade_materials` is a recipe, not loot. The data
## declared these and the validator checked them, but no gameplay code ever consumed them, so
## every (S)/(G) tier below the base item was unobtainable. This is that missing path.

## What the player needs before the upgrade fires. Empty means "yes, go ahead".
func upgrade_blocker(item_id: String) -> String:
    var data: Dictionary = DataLoader.get_item(item_id)
    var target: String = str(data.get("upgrade_path", ""))
    if target == "" or DataLoader.get_item(target).is_empty():
        return ""
    if not (BankManager.has_item(item_id, 1) or is_equipped(item_id)):
        return "You do not have a %s" % data.get("name", item_id)
    var cost: Dictionary = data.get("upgrade_materials", {})
    for material in cost.keys():
        if BankManager.get_count(str(material)) < int(cost[material]):
            return "Needs %s ×%d" % [
                DataLoader.get_item(str(material)).get("name", material),
                int(cost[material]) - BankManager.get_count(str(material))]
    return ""

## Consume the base item and its materials, then place the upgraded item. The base item comes
## back if it is worn rather than banked, so upgrading something equipped swaps it in place.
func upgrade(item_id: String) -> Dictionary:
    var data: Dictionary = DataLoader.get_item(item_id)
    var target: String = str(data.get("upgrade_path", ""))
    if target == "" or DataLoader.get_item(target).is_empty():
        return {"ok": false, "reason": "%s has no upgrade" % data.get("name", item_id)}
    var blocker: String = upgrade_blocker(item_id)
    if blocker != "":
        return {"ok": false, "reason": blocker}
    # Refuse rather than upgrade-and-lose: a full bank would take the materials and drop the result.
    if not BankManager.has_item(target, 1) and BankManager.is_full():
        return {"ok": false, "reason": "No storage space for the result"}
    var cost: Dictionary = data.get("upgrade_materials", {})
    var spent: Dictionary = BankManager.consume_bundle(cost)
    if not bool(spent.get("ok", false)):
        return {"ok": false, "reason": str(spent.get("reason", "missing materials"))}
    var was_equipped: bool = is_equipped(item_id)
    if was_equipped:
        # Take it off first so the upgraded piece lands in the same slot.
        for slot in slots.keys():
            if slots[slot] == item_id:
                slots.erase(slot)
                break
    else:
        BankManager.remove_item(item_id, 1)
    BankManager.add_item_guaranteed(target, 1)
    if was_equipped:
        equip(target)
    _reregister_modifiers()
    EventBus.state_refreshed.emit()
    EventBus.notify("Upgraded to %s" % DataLoader.get_item(target).get("name", target), "success")
    ProgressTracker.record_item_crafted(target, 1)
    return {"ok": true, "reason": "", "item_id": target}

# ---------------- Stat aggregation ----------------
## attack_key: "stab"|"slash"|"block"|"ranged_attack"|"magic_attack"
func get_attack_bonus(attack_key: String) -> int:
    var total: int = 0
    for slot in slots.keys():
        total += int(DataLoader.get_item(slots[slot]).get("equipment_stats", {}).get(attack_key, 0))
    return total

## style: "melee"|"ranged"|"magic"
func get_strength_bonus(style: String) -> int:
    var key: String = {"melee": "melee_strength", "ranged": "ranged_strength", "magic": "magic_damage_percent"}.get(style, "melee_strength")
    var total: int = 0
    for slot in slots.keys():
        total += int(DataLoader.get_item(slots[slot]).get("equipment_stats", {}).get(key, 0))
    # Arrows are not worn; the one the bow is about to loose adds its own strength.
    if style == "ranged":
        var ammo: String = active_ammo()
        if ammo != "":
            total += int((DataLoader.get_item(ammo).get("ammo_stats", {}) as Dictionary).get("ranged_strength", 0))
    return total

# ---------------- Ammunition ----------------
var _ammo_ids: Array = []

## The arrow a tiered bow will actually loose: the highest-tier arrow in storage whose
## ammo_tier is within the bow's ammo_tier_max. "" when the weapon takes no tiered ammo or
## nothing it can fire is in storage (the weapon's own attack_cost_items then applies).
func active_ammo() -> String:
    var cap: int = int(DataLoader.get_item(get_equipped(ItemData.EquipmentSlot.WEAPON)).get("ammo_tier_max", 0))
    if cap <= 0:
        return ""
    if _ammo_ids.is_empty():
        for item_id in DataLoader.items.keys():
            var it: Variant = DataLoader.items[item_id]
            if typeof(it) == TYPE_DICTIONARY and int((it as Dictionary).get("ammo_tier", 0)) > 0:
                _ammo_ids.append(str(item_id))
    var best: String = ""
    var best_tier: int = 0
    for ammo_id in _ammo_ids:
        var tier: int = int(DataLoader.get_item(ammo_id).get("ammo_tier", 0))
        if tier > best_tier and tier <= cap and BankManager.get_count(ammo_id) > 0:
            best = ammo_id
            best_tier = tier
    return best

## What one attack with the equipped weapon spends: its attack_cost_items, with the ammunition
## entry swapped for the arrow active_ammo() picked. Live combat and the simulator both read this.
func get_attack_cost() -> Dictionary:
    var cost: Dictionary = (DataLoader.get_item(get_equipped(ItemData.EquipmentSlot.WEAPON)).get("attack_cost_items", {}) as Dictionary).duplicate()
    var ammo: String = active_ammo()
    if ammo == "":
        return cost
    var out: Dictionary = {}
    for item_id in cost.keys():
        if str(DataLoader.get_item(str(item_id)).get("item_type", "")) == "ammo":
            out[ammo] = int(out.get(ammo, 0)) + int(cost[item_id])
        else:
            out[item_id] = cost[item_id]
    return out

func get_defence_bonus(style: String) -> int:
    var key: String = {"melee": "melee_defence", "ranged": "ranged_defence", "magic": "magic_defence"}.get(style, "melee_defence")
    var total: int = 0
    for slot in slots.keys():
        total += int(DataLoader.get_item(slots[slot]).get("equipment_stats", {}).get(key, 0))
    return total

## Flat percentage damage reduction granted by worn equipment. 23 items declare
## `equipment_stats.damage_reduction`; without this getter the stat was shown in tooltips and
## contributed nothing to any damage calculation.
func get_damage_reduction() -> float:
    var total: float = 0.0
    for slot in slots.keys():
        total += float(DataLoader.get_item(slots[slot]).get("equipment_stats", {}).get("damage_reduction", 0))
    return total

## Percent resistance to a status family ("poison", "burn", "stun") from worn equipment, read
## from `equipment_stats["<family>_resistance"]`.
func get_status_resistance(family: String) -> float:
    var key: String = "%s_resistance" % family
    var total: float = 0.0
    for slot in slots.keys():
        total += float(DataLoader.get_item(slots[slot]).get("equipment_stats", {}).get(key, 0))
    return total

func get_weapon_attack_speed() -> float:
    var weapon: String = get_equipped(ItemData.EquipmentSlot.WEAPON)
    if weapon == "":
        return 3.0
    return float(DataLoader.get_item(weapon).get("attack_speed", 3.0))

func get_weapon_special_attack() -> Dictionary:
    var weapon: String = get_equipped(ItemData.EquipmentSlot.WEAPON)
    if weapon == "":
        return {}
    var sa_id: String = DataLoader.get_item(weapon).get("special_attack", "")
    if sa_id == "":
        return {}
    return DataLoader.get_special_attack(sa_id)

## Aggregate passive_modifiers from all equipped items into ModifierManager.
func _reregister_modifiers() -> void:
    for slot in range(SLOT_COUNT):
        ModifierManager.unregister("item:%d" % slot)
    for slot in slots.keys():
        var data: Dictionary = DataLoader.get_item(slots[slot])
        var mods: Dictionary = data.get("passive_modifiers", {})
        if not mods.is_empty():
            ModifierManager.register("item:%d" % slot, mods, "equipment", data.get("name", slots[slot]))

# ---------------- Sets ----------------
func save_current_to_set(index: int) -> void:
    while sets.size() <= index:
        sets.append({})
    sets[index] = slots.duplicate()
    set_support[str(index)] = {"food": food_slots.duplicate(), "prayers": PlayerData.active_prayers.duplicate(), "familiars": SummoningManager.equipped.duplicate()}
    active_set = index

func set_preview(index: int) -> Dictionary:
    if index < 0 or index >= sets.size():
        return {"ok": false, "reason": "Unknown set"}
    var target: Dictionary = _normalize_slots(sets[index])
    var needed: Dictionary = {}
    for slot in target:
        var id: String = str(target[slot])
        var item: Dictionary = DataLoader.get_item(id)
        if item.is_empty() or int(item.get("equipment_slot", -1)) != int(slot) or not _meets_requirements(item):
            return {"ok": false, "reason": "Invalid slot or unmet requirements: " + id}
        needed[id] = int(needed.get(id, 0)) + 1
    if target.has(ItemData.EquipmentSlot.SHIELD) and bool(DataLoader.get_item(str(target.get(ItemData.EquipmentSlot.WEAPON, ""))).get("is_two_handed", false)):
        return {"ok": false, "reason": "Two-handed weapon conflicts with shield"}
    for id in needed:
        var available: int = BankManager.get_count(str(id)) + slots.values().count(id)
        if available < int(needed[id]):
            return {"ok": false, "reason": "Missing owned equipment: " + str(id)}
    var support_value: Variant = set_support.get(str(index), {})
    if not support_value is Dictionary: return {"ok": false, "reason": "Invalid support loadout"}
    var support: Dictionary = support_value
    for key in ["food", "prayers", "familiars"]:
        if not support.get(key, []) is Array: return {"ok": false, "reason": "Invalid support list"}
        var seen: Array = []
        for value in support.get(key, []):
            if not value is String or (value != "" and seen.has(value)): return {"ok": false, "reason": "Invalid or duplicate support entry"}
            seen.append(value)
    var foods: Array = support.get("food", [])
    if foods.size() > FOOD_SLOT_COUNT: return {"ok": false, "reason": "Too many food slots"}
    for food in foods:
        if str(food) != "" and (DataLoader.get_item(str(food)).get("item_type", "") != "food" or not BankManager.has_item(str(food), 1)): return {"ok": false, "reason": "Missing owned food: " + str(food)}
    var prayers: Array = support.get("prayers", [])
    if prayers.size() > PrayerManager.MAX_ACTIVE: return {"ok": false, "reason": "Too many prayers"}
    for prayer in prayers:
        if PrayerManager.get_prayer(str(prayer)).is_empty() or PlayerData.get_level("prayer") < int(PrayerManager.get_prayer(str(prayer)).get("level", 1)): return {"ok": false, "reason": "Locked prayer: " + str(prayer)}
    var familiars: Array = support.get("familiars", [])
    if familiars.size() > SummoningManager.MAX_EQUIPPED: return {"ok": false, "reason": "Too many familiars"}
    for familiar in familiars:
        var tablet: String = str(DataLoader.familiars.get(str(familiar), {}).get("tablet_item", ""))
        if SummoningManager.get_mark_level(str(familiar)) < 1 or (int(SummoningManager.charges.get(str(familiar), 0)) <= 0 and not BankManager.has_item(tablet, 1)): return {"ok": false, "reason": "Missing familiar marks or tablets: " + str(familiar)}
    var before: Dictionary = {}
    var after: Dictionary = {}
    for slot in slots:
        for key in DataLoader.get_item(str(slots[slot])).get("equipment_stats", {}): before[key] = float(before.get(key, 0)) + float(DataLoader.get_item(str(slots[slot])).equipment_stats[key])
    for slot in target:
        for key in DataLoader.get_item(str(target[slot])).get("equipment_stats", {}): after[key] = float(after.get(key, 0)) + float(DataLoader.get_item(str(target[slot])).equipment_stats[key])
    return {"ok": true, "reason": "", "slots": target, "support": support, "before": before, "after": after}

func load_set(index: int) -> bool:
    var check: Dictionary = set_preview(index)
    if not bool(check.ok):
        EventBus.notify(str(check.reason), "warn")
        return false
    # Validate the whole set before any transfer. Unchanged pieces never enter Storage.
    var target: Dictionary = check.slots
    var consume: Dictionary = {}
    var returning: Dictionary = {}
    for id in target.values(): consume[id] = int(consume.get(id, 0)) + 1
    for id in slots.values():
        if int(consume.get(id, 0)) > 0: consume[id] -= 1
        else: returning[id] = int(returning.get(id, 0)) + 1
    for id in consume:
        if int(consume[id]) > 0: BankManager.remove_item(str(id), int(consume[id]))
    for id in returning: BankManager.return_item(str(id), int(returning[id]))
    slots = target.duplicate()
    if not check.support.is_empty():
        food_slots = ["", "", ""]
        for i in range(check.support.get("food", []).size()): food_slots[i] = str(check.support.food[i])
        PrayerManager.deactivate_all()
        for prayer in check.support.get("prayers", []): PrayerManager.toggle(str(prayer))
        for familiar in SummoningManager.equipped.duplicate(): SummoningManager.unequip_familiar(str(familiar))
        for familiar in check.support.get("familiars", []): SummoningManager.equip_familiar(str(familiar))
    active_set = index
    _reregister_modifiers()
    EventBus.state_refreshed.emit()
    return true

func add_set() -> int:
    sets.append({})
    return sets.size() - 1

# ---------------- Persistence ----------------
func serialize() -> Dictionary:
    return {"slots": slots, "sets": sets, "active_set": active_set, "food_slots": food_slots.duplicate(), "set_support": set_support.duplicate(true)}

func deserialize(d: Dictionary) -> void:
    set_support = d.get("set_support", {}).duplicate(true) if d.get("set_support", {}) is Dictionary else {}
    slots = _normalize_slots(d.get("slots", {}))
    sets = []
    for entry in (d.get("sets", []) as Array):
        sets.append(_normalize_slots(entry))
    food_slots = ["", "", ""]
    var saved_food: Variant = d.get("food_slots", [])
    if saved_food is Array:
        for index in range(mini(saved_food.size(), FOOD_SLOT_COUNT)):
            var item_id: String = str(saved_food[index])
            var item: Dictionary = DataLoader.get_item(item_id)
            if item.get("item_type", "") == "food" and int(item.get("heal_amount", 0)) > 0 and not food_slots.has(item_id):
                food_slots[index] = item_id
    active_set = int(d.get("active_set", 0))
    _reregister_modifiers()

## JSON object keys are always Strings, but every lookup in this game addresses a slot by its
## integer index. Normalising on load is what keeps equipped gear working after a reload:
## without it get_equipped() would miss and "item:%d" formatting would fail outright.
func _normalize_slots(source: Variant) -> Dictionary:
    var out: Dictionary = {}
    if typeof(source) != TYPE_DICTIONARY:
        return out
    for key in (source as Dictionary).keys():
        var file_slot: String = str(key)
        if not file_slot.is_valid_int():
            continue
        var item_id: String = str((source as Dictionary)[key])
        if item_id == "":
            continue
        out[int(file_slot)] = item_id
    return out

func equip_food(slot: int, item_id: String) -> bool:
    if slot < 0 or slot >= FOOD_SLOT_COUNT:
        return false
    if item_id != "":
        var item: Dictionary = DataLoader.get_item(item_id)
        if item.get("item_type", "") != "food" or int(item.get("heal_amount", 0)) <= 0 or not BankManager.has_item(item_id, 1):
            return false
        if food_slots.has(item_id) and food_slots[slot] != item_id:
            return false
    food_slots[slot] = item_id
    EventBus.state_refreshed.emit()
    return true

func eat_food_slot(slot: int) -> String:
    if slot < 0 or slot >= FOOD_SLOT_COUNT or CombatManager.player_hp >= CombatManager._compute_max_hp():
        return ""
    return CombatManager.consume_food(food_slots[slot])

func compare_item(item_id: String) -> String:
    var candidate: Dictionary = DataLoader.get_item(item_id)
    var current: Dictionary = DataLoader.get_item(get_equipped(int(candidate.get("equipment_slot", -1))))
    var values: Array[String] = []
    var before: Dictionary = current.get("equipment_stats", {})
    var after: Dictionary = candidate.get("equipment_stats", {})
    var keys: Array = before.keys()
    for key in after: if not keys.has(key): keys.append(key)
    for key in keys:
        var difference: float = float(after.get(key, 0)) - float(before.get(key, 0))
        if difference != 0: values.append("%s %+.0f" % [str(key).replace("_", " "), difference])
    if bool(candidate.get("is_two_handed", false)): values.append("Shield returned to Storage")
    values.append("Passive bonuses: " + UIStyle.describe_modifier_table(candidate.get("passive_modifiers", {})))
    return "Compared with " + str(current.get("name", "empty slot")) + ": " + "; ".join(values)
