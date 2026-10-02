extends Node
## AgilityManager — build obstacles into 15 slots; each slot's obstacle registers its
## effect as a modifier source. Later slots only count once every earlier slot is filled.
## Pillars (99) and Elite Pillars (120) are one-off permanent bonuses. Blueprints save layouts.

const SLOTS: int = 15
const CATEGORY: String = "agility"

var built: Dictionary = {}          # slot(int) -> obstacle_id
var build_counts: Dictionary = {}   # obstacle_id -> times built (rebuild discount)
var pillar: String = ""
var elite_pillar: String = ""
var blueprints: Array = []          # up to 5 saved layouts

func get_obstacle(obstacle_id: String) -> Dictionary:
    return DataLoader.obstacles.get(obstacle_id, {})

func obstacles_for_slot(slot: int) -> Array:
    var out: Array = []
    for oid in DataLoader.obstacles.keys():
        var o: Dictionary = DataLoader.obstacles[oid]
        if int(o.get("slot", -1)) == slot and o.get("type", "") == "":
            out.append(o)
    return out

## Effective cost of an obstacle given repeated rebuilds (-4% each, max -40%).
func cost_for(obstacle_id: String) -> Dictionary:
    var o: Dictionary = get_obstacle(obstacle_id)
    var times: int = int(build_counts.get(obstacle_id, 0))
    var discount: float = minf(0.04 * float(times), 0.40)
    return {"gp": float(o.get("cost_gp", 0)) * (1.0 - discount), "items": o.get("cost_items", {})}

func build(slot: int, obstacle_id: String) -> bool:
    var o: Dictionary = get_obstacle(obstacle_id)
    if o.is_empty() or int(o.get("slot", -1)) != slot:
        return false
    if PlayerData.get_level("agility") < int(o.get("level_required", 1)):
        return false
    var c: Dictionary = cost_for(obstacle_id)
    if PlayerData.gp < float(c.gp) or not BankManager.can_afford(c.items): return false
    if not PlayerData.spend_gp(float(c["gp"])):
        return false
    BankManager.consume_bundle(c.items)
    built[slot] = obstacle_id
    build_counts[obstacle_id] = int(build_counts.get(obstacle_id, 0)) + 1
    _reregister()
    EventBus.notification.emit("Built %s in slot %d" % [o.get("name", obstacle_id), slot], "success")
    return true

func build_pillar(pillar_id: String) -> bool:
    var o: Dictionary = get_obstacle(pillar_id)
    if o.is_empty() or not str(o.get("type", "")) in ["pillar", "elite_pillar"] or PlayerData.get_level("agility") < int(o.get("level_required", 1)) or not BankManager.can_afford(o.get("cost_items", {})):
        return false
    if not PlayerData.spend_gp(float(o.get("cost_gp", 0))):
        return false
    BankManager.consume_bundle(o.get("cost_items", {}))
    if o.get("type", "") == "elite_pillar":
        elite_pillar = pillar_id
    else:
        pillar = pillar_id
    _reregister()
    return true

func clear_slot(slot: int) -> void:
    built.erase(slot)
    _reregister()

## Register the accumulated course bonuses (only consecutive filled slots from 1).
func _reregister() -> void:
    ModifierManager.clear_category(CATEGORY)
    var mods: Dictionary = course_effects(built)
    if not mods.is_empty():
        ModifierManager.register("%s:course" % CATEGORY, mods, CATEGORY, "Agility course")
    if pillar != "":
        ModifierManager.register("%s:pillar" % CATEGORY, get_obstacle(pillar).get("effect", {}), CATEGORY, "Pillar")
    if elite_pillar != "":
        ModifierManager.register("%s:elite_pillar" % CATEGORY, get_obstacle(elite_pillar).get("effect", {}), CATEGORY, "Elite Pillar")

func save_blueprint(blueprint_name: String) -> void:
    if blueprints.size() >= 5:
        blueprints.pop_front()
    blueprints.append({"name": blueprint_name, "layout": built.duplicate()})

func load_blueprint(index: int) -> bool:
    if index < 0 or index >= blueprints.size():
        return false
    var plan: Dictionary = blueprint_preview(index)
    if not bool(plan.ok): return false
    PlayerData.spend_gp(float(plan.gp))
    BankManager.consume_bundle(plan.items)
    for slot in plan.layout:
        var id: String = str(plan.layout[slot])
        if str(built.get(slot, "")) != id: build_counts[id] = int(build_counts.get(id, 0)) + 1
    built = plan.layout.duplicate()
    _reregister()
    return true

func serialize() -> Dictionary:
    return {"built": built, "build_counts": build_counts, "pillar": pillar,
        "elite_pillar": elite_pillar, "blueprints": blueprints}

func deserialize(d: Dictionary) -> void:
    built = _normalize_layout(d.get("built", {}))
    build_counts = d.get("build_counts", {})
    pillar = d.get("pillar", "")
    elite_pillar = d.get("elite_pillar", "")
    blueprints = []
    for entry in (d.get("blueprints", []) as Array):
        if typeof(entry) != TYPE_DICTIONARY:
            continue
        var blueprint: Dictionary = entry
        blueprints.append({"name": str(blueprint.get("name", "Course")),
            "layout": _normalize_layout(blueprint.get("layout", {}))})
    _reregister()

## JSON object keys are Strings; the course addresses its slots by integer index, so a layout
## read straight from a save would otherwise look empty and silently drop every bonus.
func _normalize_layout(source: Variant) -> Dictionary:
    var out: Dictionary = {}
    if typeof(source) != TYPE_DICTIONARY:
        return out
    for key in (source as Dictionary).keys():
        var as_text: String = str(key)
        if not as_text.is_valid_int():
            continue
        out[int(as_text)] = str((source as Dictionary)[key])
    return out

func course_effects(layout: Dictionary) -> Dictionary:
    var mods: Dictionary = {}
    for slot in range(1, SLOTS + 1):
        if not layout.has(slot): break
        for key in get_obstacle(str(layout[slot])).get("effect", {}): mods[key] = float(mods.get(key, 0)) + float(get_obstacle(str(layout[slot])).effect[key])
    return mods

func blueprint_preview(index: int) -> Dictionary:
    if index < 0 or index >= blueprints.size(): return {"ok": false, "reason": "Unknown blueprint"}
    var layout: Dictionary = _normalize_layout(blueprints[index].layout)
    var gp: float = 0
    var items: Dictionary = {}
    for slot in layout:
        var id: String = str(layout[slot])
        var def: Dictionary = get_obstacle(id)
        if def.is_empty() or int(def.get("slot", -1)) != int(slot) or PlayerData.get_level("agility") < int(def.get("level_required", 1)): return {"ok": false, "reason": "Invalid or locked obstacle"}
        if str(built.get(slot, "")) == id: continue
        var cost: Dictionary = cost_for(id)
        gp += float(cost.gp)
        for material in cost.items: items[material] = int(items.get(material, 0)) + int(cost.items[material])
    return {"ok": PlayerData.gp >= gp and BankManager.can_afford(items), "reason": "Insufficient GP or materials" if PlayerData.gp < gp or not BankManager.can_afford(items) else "", "gp": gp, "items": items, "layout": layout, "effects": course_effects(layout)}
