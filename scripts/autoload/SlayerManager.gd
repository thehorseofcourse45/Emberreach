extends Node
## SlayerManager — task assignment, kill tracking, rewards, and the Slayer Shop.
## Slayer armour is bought here; its bonuses live in the item's passive_modifiers and are
## registered by EquipmentManager when worn.

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
    _rng.randomize()
    EventBus.monster_killed.connect(_on_kill)

func get_task() -> Dictionary:
    return PlayerData.slayer_task

func has_task() -> bool:
    return not PlayerData.slayer_task.is_empty()

## Assign a task from a tier. Returns false if the tier is locked or already on a task.
func assign_task(tier_id: String) -> bool:
    if has_task():
        return false
    var t: Dictionary = DataLoader.slayer_tasks.get(tier_id, {})
    if t.is_empty() or PlayerData.get_level("slayer") < int(t.get("level_required", 1)):
        return false
    var pool: Array = DataLoader.slayer_tasks.get("_monsters", {}).get(tier_id, [])
    if pool.is_empty():
        return false
    var monster: String = pool[_rng.randi_range(0, pool.size() - 1)]
    PlayerData.slayer_task = {
        "tier": tier_id, "monster_id": monster,
        "kills_required": _rng.randi_range(int(t.get("min_kills", 10)), int(t.get("max_kills", 25))),
        "kills_done": 0, "coin_multiplier": float(t.get("slayer_coin_multiplier", 1.0)),
    }
    EventBus.notification.emit("Slayer task: kill %s× %s" % [PlayerData.slayer_task["kills_required"], monster], "info")
    return true

func reroll(cost_coins: float = 0.0) -> bool:
    if cost_coins > 0.0:
        if PlayerData.slayer_coins < cost_coins:
            return false
        PlayerData.add_slayer_coins(-cost_coins)
    var tier: String = PlayerData.slayer_task.get("tier", "easy")
    PlayerData.slayer_task = {}
    return assign_task(tier)

func extend(extra: int, cost_coins: float) -> bool:
    if not has_task() or PlayerData.slayer_coins < cost_coins:
        return false
    PlayerData.add_slayer_coins(-cost_coins)
    PlayerData.slayer_task["kills_required"] = int(PlayerData.slayer_task["kills_required"]) + extra
    return true

func _on_kill(monster_id: String) -> void:
    if not has_task() or PlayerData.slayer_task.get("monster_id", "") != monster_id:
        return
    PlayerData.slayer_task["kills_done"] = int(PlayerData.slayer_task["kills_done"]) + 1
    if int(PlayerData.slayer_task["kills_done"]) >= int(PlayerData.slayer_task["kills_required"]):
        _complete_task()

func _complete_task() -> void:
    var m: Dictionary = DataLoader.get_monster(PlayerData.slayer_task.get("monster_id", ""))
    var coins: float = float(m.get("slayer_xp", 10)) * float(PlayerData.slayer_task.get("coin_multiplier", 1.0))
    coins *= 1.0 + ModifierManager.get_modifier(ModifierKeys.GLOBAL_SLAYER_COINS_PERCENT) / 100.0
    PlayerData.add_slayer_coins(coins)
    EventBus.notification.emit("Slayer task complete! +%d Slayer Coins" % int(coins), "success")
    PlayerData.slayer_task = {}

# ---------------- Slayer Shop ----------------
func shop_items() -> Array:
    var out: Array = []
    for item_id in DataLoader.items.keys():
        var d: Dictionary = DataLoader.items[item_id]
        if d.get("slayer_cost", 0) > 0:
            out.append({"item_id": item_id, "name": d.get("name", item_id), "cost": int(d["slayer_cost"])})
    return out

func buy_slayer_item(item_id: String) -> bool:
    var d: Dictionary = DataLoader.get_item(item_id)
    var cost: float = float(d.get("slayer_cost", 0))
    if cost <= 0.0 or PlayerData.slayer_coins < cost:
        return false
    PlayerData.add_slayer_coins(-cost)
    BankManager.add_item(item_id, 1)
    EventBus.notification.emit("Bought %s" % d.get("name", item_id), "success")
    return true

func serialize() -> Dictionary:
    return {"task": PlayerData.slayer_task}

func deserialize(d: Dictionary) -> void:
    PlayerData.slayer_task = d.get("task", {})
