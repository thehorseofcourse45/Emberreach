class_name ItemData
extends Resource
## Any item: resource, food, equipment, potion, rune, bone, currency token...

enum ItemType { RESOURCE, FOOD, EQUIPMENT, POTION, RUNE, BONE, AMMO, CONSUMABLE, CURRENCY, TABLET }
enum EquipmentSlot {
    NONE = -1, HELMET = 0, PLATEBODY = 1, PLATELEGS = 2, BOOTS = 3, GLOVES = 4,
    CAPE = 5, AMULET = 6, RING = 7, WEAPON = 8, SHIELD = 9, QUIVER = 10,
    SUMMON_1 = 11, SUMMON_2 = 12, PASSIVE = 13, CONSUMABLE = 14
}

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var sell_price: int = 0
@export var item_type: ItemType = ItemType.RESOURCE
@export var is_stackable: bool = true
@export var equipment_slot: EquipmentSlot = EquipmentSlot.NONE
## attack/strength/defence bonuses: {stab, slash, block, ranged_attack, magic_attack,
##   melee_strength, ranged_strength, magic_damage_percent, melee_defence,
##   ranged_defence, magic_defence, damage_reduction}
@export var equipment_stats: Dictionary = {}
@export var passive_modifiers: Dictionary = {}   ## {modifier_key: value}
@export var special_attack: String = ""          ## special_attack id
@export var level_requirements: Dictionary = {}  ## {skill_id: level}
@export var heal_amount: int = 0                 ## food
@export var charges: int = 0                     ## potions/tablets
@export var potion_effect: Dictionary = {}       ## {modifier_key: value} while active
@export var is_two_handed: bool = false
@export var upgrade_path: String = ""            ## item id it upgrades to (S)->(G)
@export var upgrade_materials: Dictionary = {}   ## {item_id: quantity}
@export var tier: String = ""
@export var attack_speed: float = 0.0            ## weapons only

## Human-readable slot name for a slot index (used by the UI, goals and tooltips).
const SLOT_LABELS: Dictionary = {
	0: "Helm", 1: "Body", 2: "Legs", 3: "Boots", 4: "Gloves", 5: "Cloak", 6: "Amulet",
	7: "Signet", 8: "Weapon", 9: "Off-hand", 10: "Quiver", 11: "Companion I",
	12: "Companion II", 13: "Relic", 14: "Consumable",
}

static func slot_name(slot: int) -> String:
	return str(SLOT_LABELS.get(slot, "Gear"))

## Machine-readable slot key matching the icon convention res://assets/icons/slots/<key>.png.
const SLOT_KEYS: Dictionary = {
	0: "helmet", 1: "platebody", 2: "platelegs", 3: "boots", 4: "gloves", 5: "cape",
	6: "amulet", 7: "ring", 8: "weapon", 9: "shield", 10: "quiver", 11: "summon_1",
	12: "summon_2", 13: "passive", 14: "consumable",
}

static func slot_key(slot: int) -> String:
	return str(SLOT_KEYS.get(slot, "weapon"))
