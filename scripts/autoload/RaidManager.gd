extends Node
## RaidManager — the Golbin Raid roguelike minigame. Waves of golbins (wave size =
## floor(2 + wave/4)); after each wave a 3-choice upgrade/ALT-item pick; Raid Coins scale
## with difficulty and wave; purchased upgrades live in the "raid" modifier category.
## In a raid everyone attacks at 2x speed and Auto Eat Tier II is always active.

const WAVE_ENEMY: String = "golbin"
const CATEGORY: String = "raid"

var active: bool = false
var wave: int = 0
var difficulty: String = "normal"
var coins_this_raid: float = 0.0
var pending_choices: Array = []
var purchased: Dictionary = {}     # upgrade_id -> count
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
    _rng.randomize()
    EventBus.combat_ended.connect(_on_combat_ended)
    EventBus.game_loaded.connect(_reapply)

func difficulty_cfg() -> Dictionary:
    return DataLoader.raid_shop.get("difficulties", {}).get(difficulty, {})

func start_raid(diff: String = "normal") -> bool:
    if active:
        return false
    difficulty = diff
    active = true
    coins_this_raid = 0.0
    pending_choices = []
    # Wave Skip: start past the early waves instead of grinding them. The wave COUNTER is the
    # reward curve (see _on_combat_ended), so a skipped wave costs the coins it would have paid
    # and gains nothing for free.
    wave = maxi(0, int(ModifierManager.get_modifier(ModifierKeys.RAID_WAVE_SKIP)))
    _start_wave()
    return true

func _wave_size(w: int) -> int:
    return int(floor(2.0 + float(w) / 4.0))

## Enemy hitpoint multiplier for this difficulty. Read by CombatManager at spawn, so hard mode
## really is a tougher fight instead of only a prettier label in the panel.
func enemy_hp_mult() -> float:
    return maxf(0.1, float(difficulty_cfg().get("hp_mult", 1.0)))

func _start_wave() -> void:
    wave += 1
    var list: Array = []
    for _i in range(_wave_size(wave)):
        list.append(WAVE_ENEMY)
    EventBus.notification.emit("Golbin Raid — wave %d" % wave, "info")
    CombatManager.start_combat({"type": "raid", "id": "golbin_raid", "monsters": list,
        "endless": false, "raid": true, "attack_style": "melee", "melee_style": "slash"})

func _on_combat_ended(ctx: Dictionary) -> void:
    if not active or ctx.get("type", "") != "raid":
        return
    var mult: float = float(difficulty_cfg().get("coin_mult", 1.0))
    var earned: float = mult * 3.6 * float(wave) * float(_wave_size(wave)) * float(int(floor(1.0 + float(wave) / 15.0)))
    coins_this_raid += earned
    pending_choices = _roll_choices()
    EventBus.notification.emit("Wave %d cleared (+%d raid coins) — choose an upgrade" % [wave, int(earned)], "success")

func _roll_choices() -> Array:
    var pool: Array = []
    pool.append_array(DataLoader.raid_shop.get("alt_items", []))
    for k in DataLoader.raid_shop.get("upgrades", {}).keys():
        pool.append(k)
    var picks: Array = []
    for _i in range(mini(3, pool.size())):
        picks.append(pool[_rng.randi_range(0, pool.size() - 1)])
    return picks

## Pick one of the three offered rewards; advances to the next wave.
func choose(index: int) -> bool:
    if index < 0 or index >= pending_choices.size():
        return false
    var choice: String = pending_choices[index]
    if DataLoader.raid_shop.get("alt_items", []).has(choice):
        BankManager.add_item(choice, 1)
    else:
        purchased[choice] = int(purchased.get(choice, 0)) + 1
        _apply_upgrade(choice)
        EventBus.shop_upgrade_purchased.emit(choice)
    pending_choices = []
    _start_wave()
    return true

func _apply_upgrade(upgrade_id: String) -> void:
    var eff: Dictionary = DataLoader.raid_shop.get("upgrades", {}).get(upgrade_id, {}).get("effect", {})
    if not eff.is_empty():
        ModifierManager.register("%s:%s" % [CATEGORY, upgrade_id], eff, CATEGORY, upgrade_id)

func end_raid() -> void:
    if not active:
        return
    active = false
    pending_choices = []
    CombatManager.stop_combat()
    PlayerData.raid_coins += coins_this_raid
    EventBus.notification.emit("Raid ended: +%d Raid Coins" % int(coins_this_raid), "success")
    coins_this_raid = 0.0

# ---------------- Raid Shop ----------------
func shop_items() -> Array:
    var out: Array = []
    for item_id in DataLoader.raid_shop.get("alt_items", []):
        var d: Dictionary = DataLoader.get_item(item_id)
        if not d.is_empty():
            out.append({"item_id": item_id, "name": d.get("name", item_id), "cost": int(d.get("raid_cost", 0))})
    for uid in DataLoader.raid_shop.get("upgrades", {}).keys():
        var u: Dictionary = DataLoader.raid_shop["upgrades"][uid]
        out.append({"item_id": uid, "name": u.get("name", uid), "cost": int(u.get("cost", 0))})
    return out

func buy(item_id: String) -> bool:
    var cost: float = 0.0
    if DataLoader.raid_shop.get("alt_items", []).has(item_id):
        cost = float(DataLoader.get_item(item_id).get("raid_cost", 0))
    elif DataLoader.raid_shop.get("upgrades", {}).has(item_id):
        cost = float(DataLoader.raid_shop["upgrades"][item_id].get("cost", 0))
    else:
        return false
    if PlayerData.raid_coins < cost:
        return false
    PlayerData.raid_coins -= cost
    if DataLoader.raid_shop.get("alt_items", []).has(item_id):
        BankManager.add_item(item_id, 1)
    else:
        purchased[item_id] = int(purchased.get(item_id, 0)) + 1
        _apply_upgrade(item_id)
    return true

func _reapply() -> void:
    for upgrade_id in purchased.keys():
        _apply_upgrade(upgrade_id)

func serialize() -> Dictionary:
    return {"purchased": purchased, "active": active, "wave": wave, "difficulty": difficulty}

func deserialize(d: Dictionary) -> void:
    purchased = d.get("purchased", {})
    active = bool(d.get("active", false))
    wave = int(d.get("wave", 0))
    difficulty = d.get("difficulty", "normal")
    _reapply()
