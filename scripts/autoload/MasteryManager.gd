extends Node
## MasteryManager — per-action mastery levels, shared per-skill mastery pools and
## pool checkpoints (10% / 25% / 50% / 95%).
##
## Mastery XP per action (verbatim from spec):
##   MXP = [ (UnlockedActions * (PlayerTotalMastery / TotalMasteryForSkill))
##           + (ItemMasteryLevel * TotalItemsInSkill / 10) ]
##         * ActionTime * 0.5 * (1 + Bonus)
##
## Pool rules:
##   - 25% of earned MXP goes to the skill pool (50% once the skill is level 99+).
##   - Pool cap = 500,000 * number of items in the skill.
##   - Pool XP can be spent to raise any item's mastery at a 1:1 rate.
##   - Mastery Tokens fill 0.1% of the pool.

const POOL_CHECKPOINTS: Array[float] = [10.0, 25.0, 50.0, 95.0]
const POOL_PER_ITEM: float = 500_000.0
const TOKEN_POOL_FRACTION: float = 0.001

# skill_id -> { action_id: xp }
var _mastery_xp: Dictionary = {}
# skill_id -> pool xp (float)
var _pools: Dictionary = {}
# skill_id -> Array[bool] state of each checkpoint (index-aligned with POOL_CHECKPOINTS)
var _checkpoint_state: Dictionary = {}

func _ready() -> void:
    EventBus.mastery_level_up.connect(_on_mastery_level_up)

func _on_mastery_level_up(skill_id: String, action_id: String, _level: int) -> void:
    update_item_mastery_source(skill_id, action_id)

## Register the modifier source granted by the active action's ITEM mastery unlocks
## (thresholds 1/10/20/.../95/99 in the skill's "mastery_unlocks" data). Cumulative.
const ITEM_UNLOCK_CATEGORY: String = "mastery_item"

func update_item_mastery_source(skill_id: String, action_id: String) -> void:
    ModifierManager.unregister("mastery_item:%s" % skill_id)
    if skill_id == "" or action_id == "":
        return
    var unlocks: Dictionary = DataLoader.get_skill(skill_id).get("mastery_unlocks", {})
    if unlocks.is_empty():
        return
    var lvl: int = get_level(skill_id, action_id)
    var mods: Dictionary = {}
    for threshold in unlocks.keys():
        if lvl >= int(threshold):
            for key in unlocks[threshold].keys():
                mods[key] = float(mods.get(key, 0.0)) + float(unlocks[threshold][key])
    if not mods.is_empty():
        ModifierManager.register("mastery_item:%s" % skill_id, mods, ITEM_UNLOCK_CATEGORY,
            "%s mastery" % skill_id)

# ---------------- Mastery levels ----------------
func get_xp(skill_id: String, action_id: String) -> float:
    var m: Dictionary = _mastery_xp.get(skill_id, {})
    return float(m.get(action_id, 0.0))

func get_level(skill_id: String, action_id: String) -> int:
    return XPTable.level_for_xp(get_xp(skill_id, action_id))

func get_skill_total_mastery_levels(skill_id: String) -> float:
    ## Sum of every action's mastery LEVEL in the skill (PlayerTotalMastery).
    var m: Dictionary = _mastery_xp.get(skill_id, {})
    var total: float = 0.0
    for action_id in m.keys():
        total += float(XPTable.level_for_xp(float(m[action_id])))
    return total

## Compute the mastery XP granted by one action completion (before pool split).
func compute_mxp(skill_id: String, action_id: String, action_time: float, bonus: float = 0.0) -> float:
    var total_items: float = float(DataLoader.get_action_count(skill_id))
    if total_items <= 0.0:
        return 0.0
    var skill_level: int = PlayerData.get_level(skill_id)
    var unlocked: float = float(DataLoader.get_unlocked_action_count(skill_id, skill_level))
    var player_total: float = get_skill_total_mastery_levels(skill_id)
    var total_mastery_for_skill: float = total_items * 99.0
    var item_level: float = float(get_level(skill_id, action_id))
    var base: float = (unlocked * (player_total / total_mastery_for_skill)) + (item_level * total_items / 10.0)
    return base * action_time * 0.5 * (1.0 + bonus)

## Grant mastery XP for an action. Returns a summary Dictionary.
func add_mastery_xp(skill_id: String, action_id: String, action_time: float, bonus: float = 0.0) -> Dictionary:
    var mxp: float = compute_mxp(skill_id, action_id, action_time, bonus)
    if mxp <= 0.0:
        return {"mxp": 0.0, "pool_gain": 0.0, "level_up": false, "level": get_level(skill_id, action_id)}
    var before_level: int = get_level(skill_id, action_id)
    if not _mastery_xp.has(skill_id):
        _mastery_xp[skill_id] = {}
    _mastery_xp[skill_id][action_id] = get_xp(skill_id, action_id) + mxp
    EventBus.mastery_xp_gained.emit(skill_id, action_id, mxp)
    var after_level: int = get_level(skill_id, action_id)
    if after_level > before_level:
        EventBus.mastery_level_up.emit(skill_id, action_id, after_level)
    # Pool split: 50% post-99, else 25%.
    var pool_rate: float = 0.5 if PlayerData.get_level(skill_id) >= 99 else 0.25
    var pool_gain: float = mxp * pool_rate
    add_pool_xp(skill_id, pool_gain)
    return {"mxp": mxp, "pool_gain": pool_gain, "level_up": after_level > before_level, "level": after_level}

# ---------------- Pools ----------------
func get_pool_cap(skill_id: String) -> float:
    return POOL_PER_ITEM * float(DataLoader.get_action_count(skill_id))

func get_pool_xp(skill_id: String) -> float:
    return float(_pools.get(skill_id, 0.0))

func get_pool_percent(skill_id: String) -> float:
    var cap: float = get_pool_cap(skill_id)
    if cap <= 0.0:
        return 0.0
    return clampf(get_pool_xp(skill_id) / cap * 100.0, 0.0, 100.0)

func add_pool_xp(skill_id: String, amount: float) -> void:
    var cap: float = get_pool_cap(skill_id)
    var new_val: float = clampf(get_pool_xp(skill_id) + amount, 0.0, cap)
    _pools[skill_id] = new_val
    EventBus.mastery_pool_changed.emit(skill_id, new_val)
    _evaluate_checkpoints(skill_id)

## Spend pool XP to level an item's mastery 1:1 (spec).
func spend_pool_xp(skill_id: String, action_id: String, amount: float) -> bool:
    if get_pool_xp(skill_id) < amount:
        return false
    _pools[skill_id] = get_pool_xp(skill_id) - amount
    if not _mastery_xp.has(skill_id):
        _mastery_xp[skill_id] = {}
    _mastery_xp[skill_id][action_id] = get_xp(skill_id, action_id) + amount
    EventBus.mastery_pool_changed.emit(skill_id, _pools[skill_id])
    _evaluate_checkpoints(skill_id)
    return true

## Spend pool XP to raise an item by whole levels (returns XP actually spent).
func spend_pool_xp_for_levels(skill_id: String, action_id: String, levels: int) -> float:
    var target_xp: float = get_xp(skill_id, action_id)
    var cur_level: int = XPTable.level_for_xp(target_xp)
    var want: int = mini(cur_level + levels, XPTable.MAX_LEVEL)
    var needed: float = float(XPTable.xp_for_level(want)) - target_xp
    if needed <= 0.0:
        return 0.0
    var affordable: float = minf(needed, get_pool_xp(skill_id))
    if affordable <= 0.0:
        return 0.0
    _pools[skill_id] = get_pool_xp(skill_id) - affordable
    _mastery_xp[skill_id][action_id] = target_xp + affordable
    _evaluate_checkpoints(skill_id)
    return affordable

func claim_mastery_token(skill_id: String) -> void:
    add_pool_xp(skill_id, get_pool_cap(skill_id) * TOKEN_POOL_FRACTION)

func _evaluate_checkpoints(skill_id: String) -> void:
    var pct: float = get_pool_percent(skill_id)
    if not _checkpoint_state.has(skill_id):
        _checkpoint_state[skill_id] = [false, false, false, false]
    var states: Array = _checkpoint_state[skill_id]
    for i in range(POOL_CHECKPOINTS.size()):
        var reached: bool = pct >= POOL_CHECKPOINTS[i]
        if states[i] != reached:
            states[i] = reached
            EventBus.mastery_pool_checkpoint.emit(skill_id, POOL_CHECKPOINTS[i], reached)

func is_checkpoint_active(skill_id: String, percent: float) -> bool:
    var idx: int = POOL_CHECKPOINTS.find(percent)
    if idx < 0:
        return false
    var states: Array = _checkpoint_state.get(skill_id, [])
    return idx < states.size() and bool(states[idx])

# ---------------- Persistence ----------------
func serialize() -> Dictionary:
    return {"mastery_xp": _mastery_xp.duplicate(true), "pools": _pools.duplicate(true)}

func deserialize(data: Dictionary) -> void:
    _mastery_xp = data.get("mastery_xp", {})
    _pools = data.get("pools", {})
    _checkpoint_state.clear()
    for skill_id in _pools.keys():
        _evaluate_checkpoints(skill_id)
