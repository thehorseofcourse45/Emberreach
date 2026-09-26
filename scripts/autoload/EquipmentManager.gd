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
    return {"slots": slots, "sets": sets, "active_set": active_set}

func deserialize(d: Dictionary) -> void:
    slots = _normalize_slots(d.get("slots", {}))
    sets = []
    for entry in (d.get("sets", []) as Array):
        sets.append(_normalize_slots(entry))
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
