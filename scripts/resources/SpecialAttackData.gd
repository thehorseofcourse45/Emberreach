class_name SpecialAttackData
extends Resource
## A weapon/passive special attack. Percent chances stored as 0..100.

enum Effect { NONE, LIFE_LEACH, GUARANTEED_HIT, STUN, SLOW, MAGIC_RAY, DOUBLE_HIT, BLEED, BURN }

@export var id: String = ""
@export var name: String = ""
@export var trigger_chance: float = 10.0     ## %
@export var effect: Effect = Effect.GUARANTEED_HIT
@export var damage_multiplier: float = 1.0
@export var ignores_accuracy: bool = false
@export var applies_status: String = ""      ## status_effect id
@export var status_chance: float = 100.0
@export var status_duration: float = 0.0
@export var heal_fraction: float = 0.0       ## for LIFE_LEACH
@export var description: String = ""
