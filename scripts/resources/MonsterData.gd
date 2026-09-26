class_name MonsterData
extends Resource
## A monster definition. Mirrors data/monsters.json.

enum AttackType { MELEE, RANGED, MAGIC }

@export var id: String = ""
@export var name: String = ""
@export var combat_level: int = 1
@export var hitpoints: int = 10
@export var attack_type: AttackType = AttackType.MELEE
@export var attack_speed: float = 3.0
@export var max_hit: int = 1
@export var accuracy_rating: int = 10
@export var melee_evasion: int = 10
@export var ranged_evasion: int = 10
@export var magic_evasion: int = 10
@export var damage_reduction: float = 0.0
@export var special_attacks: Array[String] = []   ## special_attack ids
@export var passives: Array[String] = []
@export var loot_table: Array = []                ## LootDrop-shaped dictionaries
@export var bone_type: String = ""                ## "" | bones | big_bones | dragon_bones | magic_bones
@export var slayer_xp: float = 0.0
@export var is_boss: bool = false
@export var respawn_time: float = 3.0
@export var can_be_stunned: bool = true
@export var is_immune_to_effects: bool = false
@export var image: Texture2D
