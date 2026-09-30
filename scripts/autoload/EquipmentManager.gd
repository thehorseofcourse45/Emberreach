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
    if not _meets_requirements(data):
        EventBus.notification.emit("Requirements not met for %s" % data.get("name", item_id), "warn")
        return false
    if not BankManager.has_item(item_id, 1):
        return false
    # Two-handed weapons occupy the shield slot too.
    if bool(data.get("is_two_handed", false)):
        slots.erase(ItemData.EquipmentSlot.SHIELD)
    BankManager.remove_item(item_id, 1)
    if slots.has(slot) and slots[slot] != "":
        BankManager.add_item(slots[slot], 1)   # return the displaced item
    slots[slot] = item_id
    _reregister_modifiers()
    EventBus.item_equipped.emit(slot, item_id)
    return true

func unequip(slot: int) -> bool:
    if not slots.has(slot) or slots[slot] == "":
        return false
    var item_id: String = slots[slot]
    BankManager.add_item(item_id, 1)
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
                unequip(int(slot))
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
    return total

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
    active_set = index

func load_set(index: int) -> bool:
    if index < 0 or index >= sets.size():
        return false
    # Move current equipment to bank first.
    for slot in slots.keys():
        BankManager.add_item(slots[slot], 1)
    slots = _normalize_slots(sets[index])
    active_set = index
    _reregister_modifiers()
    return true

func add_set() -> int:
    sets.append({})
    return sets.size() - 1

# ---------------- Persistence ----------------
func serialize() -> Dictionary:
    return {"slots": slots, "sets": sets, "active_set": active_set, "food_slots": food_slots.duplicate()}

func deserialize(d: Dictionary) -> void:
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
