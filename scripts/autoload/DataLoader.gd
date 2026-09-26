extends Node
## DataLoader — loads every JSON content file from res://data/ once at startup and
## exposes read-only lookups. Nothing in the game may hardcode content: all skills,
## items, monsters, dungeons, recipes, shop entries and modes come from here.
##
## Save data NEVER lives here — that is PlayerData / SaveManager.

const DATA_DIR: String = "res://data/"

var skills: Dictionary = {}          # skill_id -> {id, name, category, type, max_level, actions:[...]}
var items: Dictionary = {}           # item_id  -> {...}
var monsters: Dictionary = {}        # monster_id -> {...}
var dungeons: Dictionary = {}        # dungeon_id -> {...}
var areas: Dictionary = {}           # area_id -> {...}
var shop: Dictionary = {}            # upgrade_id -> {...}
var game_modes: Dictionary = {}      # mode_id -> {...}
var prayers: Dictionary = {}
var constellations: Dictionary = {}
var obstacles: Dictionary = {}
var familiars: Dictionary = {}
var pets: Dictionary = {}
var slayer_tasks: Dictionary = {}
var special_attacks: Dictionary = {}
var abilities: Dictionary = {}          # ability_id -> {id, name, description, style, req_levels, unlock, effect, status_duration, trigger_chance, cooldown_attacks}
var township_buildings: Dictionary = {}
var cartography_hexes: Dictionary = {}
var archaeology_sites: Dictionary = {}
var harvesting_veins: Dictionary = {}
var raid_shop: Dictionary = {}
## Settlement trader offers: exchange settlement stores for a specific item.
var trader: Dictionary = {}
## General store stock: goods bought outright with gold.
var shop_store: Dictionary = {}

# Derived indexes
var _actions_by_skill: Dictionary = {}      # skill_id -> Array[Dictionary]
var _actions_by_id: Dictionary = {}         # "skill:action" -> Dictionary
var _skill_order: Array[String] = []

func _ready() -> void:
    _load_all()

func _load_all() -> void:
    skills = _load_file("skills.json")
    items = _load_file("items.json")
    monsters = _load_file("monsters.json")
    dungeons = _load_file("dungeons.json")
    areas = _load_file("areas.json")
    shop = _load_file("shop.json")
    game_modes = _load_file("game_modes.json")
    prayers = _load_file("prayers.json")
    constellations = _load_file("constellations.json")
    obstacles = _load_file("obstacles.json")
    familiars = _load_file("familiars.json")
    pets = _load_file("pets.json")
    slayer_tasks = _load_file("slayer_tasks.json")
    special_attacks = _load_file("special_attacks.json")
    abilities = _load_file("abilities.json")
    township_buildings = _load_file("shop_township.json")
    cartography_hexes = _load_file("cartography_hexes.json")
    archaeology_sites = _load_file("archaeology_sites.json")
    harvesting_veins = _load_file("harvesting_veins.json")
    raid_shop = _load_file("raid_shop.json")
    trader = _load_file("trader.json")
    shop_store = _load_file("shop_store.json")
    _build_indexes()

func _load_file(file_name: String) -> Dictionary:
    var path: String = DATA_DIR + file_name
    if not FileAccess.file_exists(path):
        push_warning("DataLoader: missing data file %s" % path)
        return {}
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        push_warning("DataLoader: cannot open %s" % path)
        return {}
    var text: String = f.get_as_text()
    f.close()
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_warning("DataLoader: %s is not a JSON object" % path)
        return {}
    var d: Dictionary = parsed
    d.erase("_comment")   # authoring note, not content
    return d

func _build_indexes() -> void:
    _actions_by_skill.clear()
    _actions_by_id.clear()
    _skill_order.clear()
    for skill_id in skills.keys():
        var s: Variant = skills[skill_id]
        if typeof(s) != TYPE_DICTIONARY:
            continue   # skip non-skill metadata keys defensively
        _skill_order.append(skill_id)
        var acts: Array = (s as Dictionary).get("actions", [])
        _actions_by_skill[skill_id] = acts
        for a in acts:
            if typeof(a) == TYPE_DICTIONARY:
                _actions_by_id["%s:%s" % [skill_id, a.get("id", "")]] = a

# --- Lookups ---
func get_skill(skill_id: String) -> Dictionary:
    return skills.get(skill_id, {})

func get_skill_actions(skill_id: String) -> Array:
    return _actions_by_skill.get(skill_id, [])

func get_action(skill_id: String, action_id: String) -> Dictionary:
    return _actions_by_id.get("%s:%s" % [skill_id, action_id], {})

func get_item(item_id: String) -> Dictionary:
    return items.get(item_id, {})

func get_monster(monster_id: String) -> Dictionary:
    return monsters.get(monster_id, {})

func get_dungeon(dungeon_id: String) -> Dictionary:
    return dungeons.get(dungeon_id, {})

func get_shop_upgrade(upgrade_id: String) -> Dictionary:
    return shop.get(upgrade_id, {})

func get_special_attack(sa_id: String) -> Dictionary:
    return special_attacks.get(sa_id, {})

func get_ability(ability_id: String) -> Dictionary:
    return abilities.get(ability_id, {})

func get_skill_ids() -> Array[String]:
    return _skill_order.duplicate()

## Number of distinct actions/recipes in a skill == "TotalItemsInSkill" in the mastery formula.
func get_action_count(skill_id: String) -> int:
    return get_skill_actions(skill_id).size()

## Number of actions whose level requirement is met at `skill_level` ("UnlockedActions").
func get_unlocked_action_count(skill_id: String, skill_level: int) -> int:
    var n: int = 0
    for a in get_skill_actions(skill_id):
        if int(a.get("level_required", 1)) <= skill_level:
            n += 1
    return n
