extends Node
## FarmingManager — real-time crop growth (timestamps), so growth continues offline
## with zero extra simulation. Plots: allotment / herb / tree.

const PLOT_COUNTS := {"allotment": 6, "herb": 6, "tree": 3}

# Array of plot dictionaries: {type, seed_id, planted_unix, grow_seconds, compost, alive, harvested}
var plots: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
    _rng.randomize()
    if plots.is_empty():
        _build_plots()

func _build_plots() -> void:
    plots.clear()
    for type_id in PLOT_COUNTS.keys():
        for _i in range(PLOT_COUNTS[type_id]):
            plots.append({"type": type_id, "seed_id": "", "planted_unix": 0.0,
                "grow_seconds": 0.0, "compost": 0, "alive": true, "harvested": false})

func plant(plot_index: int, seed_id: String) -> bool:
    if plot_index < 0 or plot_index >= plots.size():
        return false
    var plot: Dictionary = plots[plot_index]
    if plot["seed_id"] != "":
        return false
    var seed: Dictionary = DataLoader.get_item(seed_id)
    if seed.is_empty() or seed.get("item_type", "") != "seed":
        return false
    if not BankManager.remove_item(seed_id, 1):
        return false
    plot["seed_id"] = seed_id
    plot["planted_unix"] = Time.get_unix_time_from_system()
    plot["grow_seconds"] = float(seed.get("grow_seconds", 3600))
    plot["harvested"] = false
    # Survival chance: base + 10% per compost, capped 100%.
    var survival: float = clampf(float(seed.get("base_survival", 0.5)) + 0.1 * float(plot["compost"]), 0.0, 1.0)
    plot["alive"] = _rng.randf() <= survival
    return true

func apply_compost(plot_index: int) -> bool:
    if plot_index < 0 or plot_index >= plots.size():
        return false
    if not BankManager.has_item("compost", 1):
        return false
    BankManager.remove_item("compost", 1)
    plots[plot_index]["compost"] = int(plots[plot_index]["compost"]) + 1
    return true

func is_ready(plot_index: int) -> bool:
    if plot_index < 0 or plot_index >= plots.size():
        return false
    var p: Dictionary = plots[plot_index]
    if p["seed_id"] == "" or not p["alive"]:
        return false
    return float(Time.get_unix_time_from_system()) >= float(p["planted_unix"]) + float(p["grow_seconds"])

func harvest(plot_index: int) -> Dictionary:
    if not is_ready(plot_index):
        return {}
    var p: Dictionary = plots[plot_index]
    var seed: Dictionary = DataLoader.get_item(p["seed_id"])
    var yield_qty: int = _rng.randi_range(int(seed.get("min_yield", 1)), int(seed.get("max_yield", 3)))
    var out_item: String = seed.get("product_item", "")
    if out_item != "":
        BankManager.add_item(out_item, yield_qty)
    var xp: float = float(seed.get("harvest_xp", 0.0)) * ModifierManager.get_skill_xp_multiplier("farming")
    PlayerData.add_xp("farming", xp)
    MasteryManager.add_mastery_xp("farming", p["seed_id"], float(p["grow_seconds"]) / 3600.0, 0.0)
    p["seed_id"] = ""
    p["harvested"] = true
    return {"item_id": out_item, "quantity": yield_qty, "xp": xp}

## Growth is time-based, so offline advancement only needs to detect newly-ready plots.
func advance_offline(_elapsed: float) -> int:
    var ready: int = 0
    for i in range(plots.size()):
        if is_ready(i):
            ready += 1
    return ready

func serialize() -> Dictionary:
    return {"plots": plots}

func deserialize(d: Dictionary) -> void:
    plots = d.get("plots", [])
    if plots.is_empty():
        _build_plots()
