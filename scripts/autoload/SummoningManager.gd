extends Node
## SummoningManager — marks discovered while training other skills, tablet crafting
## (via SkillManager), up to 2 equipped familiars, charge consumption and synergies.

const MAX_EQUIPPED: int = 2
const CATEGORY: String = "summoning"
const MARK_LEVELS: Array[int] = [1, 5, 10, 15, 15, 15]   # marks needed for levels 2..6

var _rng := RandomNumberGenerator.new()
var marks: Dictionary = {}          # familiar_id -> mark level (1..6)
var equipped: Array[String] = []    # familiar ids
var charges: Dictionary = {}        # familiar_id -> remaining charges

func _ready() -> void:
    _rng.randomize()

func get_mark_level(familiar_id: String) -> int:
    return int(marks.get(familiar_id, 0))

## Roll a mark discovery when an action completes in `skill_id`.
func on_skill_action(skill_id: String, action_time: float) -> void:
    for fid in DataLoader.familiars.keys():
        var f: Dictionary = DataLoader.familiars[fid]
        if f.get("mark_skill", "") != skill_id:
            continue
        var tier: float = float(f.get("tier", 1))
        var mult: float = 2.5 if equipped.has(fid) else 1.0
        var chance: float = action_time / (pow(tier + 1.0, 2.0) * 200.0) * mult
        if _rng.randf() < chance:
            _gain_mark(fid)

func on_combat_action() -> void:
    for fid in DataLoader.familiars.keys():
        var f: Dictionary = DataLoader.familiars[fid]
        if f.get("mark_skill", "") not in ["attack", "strength", "defence", "ranged", "magic", "hitpoints", "slayer"]:
            continue
        var chance: float = 2.0 * float(f.get("tier", 1)) / 2500.0
        if _rng.randf() < chance:
            _gain_mark(fid)

func _gain_mark(familiar_id: String) -> void:
    var lvl: int = get_mark_level(familiar_id) + 1
    if lvl > 6:
        return
    marks[familiar_id] = lvl
    EventBus.notification.emit("Discovered %s mark (Lv %d)" % [familiar_id, lvl], "success")

func equip_familiar(familiar_id: String) -> bool:
    if equipped.has(familiar_id) or equipped.size() >= MAX_EQUIPPED:
        return false
    if get_mark_level(familiar_id) < 1:
        return false
    equipped.append(familiar_id)
    charges[familiar_id] = int(charges.get(familiar_id, 0)) + 25
    _reregister()
    return true

func unequip_familiar(familiar_id: String) -> void:
    equipped.erase(familiar_id)
    _reregister()

func consume_charge(familiar_id: String) -> void:
    charges[familiar_id] = maxi(0, int(charges.get(familiar_id, 0)) - 1)

## Called by SkillManager after each completed action.
func on_action(skill_id: String, action_time: float) -> void:
    on_skill_action(skill_id, action_time)
    for fid in equipped.duplicate():
        var f: Dictionary = DataLoader.familiars[fid]
        if f.get("mark_skill", "") == skill_id:
            consume_charge(fid)

func _reregister() -> void:
    ModifierManager.unregister("%s:familiars" % CATEGORY)
    ModifierManager.unregister("%s:synergy" % CATEGORY)
    var mods: Dictionary = {}
    for fid in equipped:
        var eff: Dictionary = DataLoader.familiars.get(fid, {}).get("effect", {})
        for k in eff.keys():
            mods[k] = float(mods.get(k, 0.0)) + float(eff[k])
    var syn: Dictionary = {}
    for fid in equipped:
        for s in DataLoader.familiars.get(fid, {}).get("synergies", []):
            if equipped.has(s.get("with", "")) and get_mark_level(fid) >= int(s.get("mark_level", 1)):
                for k in s.get("effect", {}).keys():
                    syn[k] = float(syn.get(k, 0.0)) + float(s["effect"][k])
    if not mods.is_empty():
        ModifierManager.register("%s:familiars" % CATEGORY, mods, CATEGORY, "Familiars")
    if not syn.is_empty():
        ModifierManager.register("%s:synergy" % CATEGORY, syn, CATEGORY, "Familiar synergy")

func serialize() -> Dictionary:
    return {"marks": marks, "equipped": equipped, "charges": charges}

func deserialize(d: Dictionary) -> void:
    marks = d.get("marks", {})
    var arr: Array[String] = []
    for v in d.get("equipped", []):
        arr.append(str(v))
    equipped = arr
    charges = d.get("charges", {})
    _reregister()
