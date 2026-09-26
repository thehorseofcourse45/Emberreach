class_name SkillActionData
extends Resource
## One trainable action/recipe inside a skill. Mirrors the JSON schema in res://data/skills.json
## so content can be authored either as JSON or as .tres resources.

@export var id: String = ""
@export var skill_id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var level_required: int = 1
@export var base_interval: float = 3.0          ## seconds
@export var base_xp: float = 0.0
## Mastery timing: gathering skills use the real interval; artisan skills use a fixed value.
@export var mastery_action_time: float = -1.0   ## -1 => use effective interval

@export var input_items: Dictionary = {}        ## {item_id: quantity}
@export var output_items: Dictionary = {}       ## {item_id: quantity}
@export var output_chance: float = 1.0          ## 0..1 (Cooking success, Thieving, ...)
@export var secondary_outputs: Array = []       ## [{item_id, chance, min_qty, max_qty}]
@export var required_tool: String = ""          ## shop upgrade id gating the action
@export var required_items_equipped: Array = [] ## e.g. Slayer area entry items
@export var mastery_unlocks: Dictionary = {}    ## {level: modifier_key} 1,10,20,...,99
@export var node_hp: int = 0                    ## Mining rocks / Harvesting veins
@export var respawn_seconds: float = 0.0
@export var category: String = "gather"         ## gather | artisan | support | combat

func effective_action_time(modifier_manager: Node, floor_seconds: float = 0.25) -> float:
    return modifier_manager.get_interval(skill_id, base_interval, floor_seconds)

func mastery_time(modifier_manager: Node) -> float:
    if mastery_action_time > 0.0:
        return mastery_action_time
    return effective_action_time(modifier_manager)
