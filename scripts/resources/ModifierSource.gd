class_name ModifierSource
extends Resource
## A named bundle of modifiers contributed by one source (an equipped item, an active
## prayer, a potion, an agility obstacle, a pet, a mastery checkpoint, ...).
## Systems register/unregister these with ModifierManager; the manager caches the sum.

@export var id: String = ""                      ## unique source id, e.g. "item:bronze_scimitar" or "prayer:ultimate_strength"
@export var display_name: String = ""
@export var category: String = "generic"         ## equipment | prayer | potion | agility | astrology | summoning | pet | cape | shop | mastery | township | relic | poi
## key -> percent or flat value (see ModifierKeys)
@export var modifiers: Dictionary = {}

static func make(p_id: String, p_mods: Dictionary, p_category: String = "generic", p_display: String = "") -> ModifierSource:
    var s := ModifierSource.new()
    s.id = p_id
    s.modifiers = p_mods
    s.category = p_category
    s.display_name = p_display
    return s
