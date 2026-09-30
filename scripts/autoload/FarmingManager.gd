extends Node
## FarmingManager — real-time crop growth (timestamps), so growth continues offline
## with zero extra simulation. Plots: allotment / herb / tree.
##
## Two entry points reach these plots now: the Farm screen calls plant()/harvest()/clear_plot()
## directly, and the skill's plant_* actions bridge through SkillManager — the action's
## input_items spend the seed, then plant_first_free(consume_from_bank = false) lands it.
## Planting never pays XP; harvesting does. Per-crop mastery (doubling / +1 resource) is
## read at harvest time from the crop's own action, so it works from either entry point.

signal plots_changed()

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

# =========================================================================
#  Seed / action helpers
# =========================================================================

## plant_garum_herb -> garum_herb_seed; anything else names no seed.
func seed_id_for_action(action_id: String) -> String:
	if not action_id.begins_with("plant_"):
		return ""
	return action_id.trim_prefix("plant_") + "_seed"

## garum_herb_seed -> plant_garum_herb; anything else grows under no action.
func action_id_for_seed(seed_id: String) -> String:
	if not seed_id.ends_with("_seed"):
		return ""
	return "plant_" + seed_id.trim_suffix("_seed")

## The crop's own level gate, read from its plant action (0 when there is no action).
func plant_level(seed_id: String) -> int:
	return int(DataLoader.get_action("farming", action_id_for_seed(seed_id)).get("level_required", 0))

func has_free_plot() -> bool:
	return free_plot_count() > 0

func free_plot_count() -> int:
	var n: int = 0
	for p in plots:
		if str(p["seed_id"]) == "":
			n += 1
	return n

func ready_count() -> int:
	var n: int = 0
	for i in range(plots.size()):
		if is_ready(i):
			n += 1
	return n

# =========================================================================
#  Actions
# =========================================================================

## Plant a seed into a specific plot. `consume_from_bank` is false only for the skill-tab
## bridge, where the seed was already paid through the action's input_items.
func plant(index: int, seed_id: String, consume_from_bank: bool = true) -> bool:
	if index < 0 or index >= plots.size():
		return false
	var plot: Dictionary = plots[index]
	if plot["seed_id"] != "":
		return false
	var seed_data: Dictionary = DataLoader.get_item(seed_id)
	if seed_data.is_empty() or seed_data.get("item_type", "") != "seed":
		return false
	var need: int = plant_level(seed_id)
	if need > 0 and PlayerData.get_level("farming") < need:
		return false
	if consume_from_bank and not BankManager.remove_item(seed_id, 1):
		return false
	_occupy(index, seed_id, seed_data)
	plots_changed.emit()
	return true

func _occupy(index: int, seed_id: String, seed_data: Dictionary) -> void:
	var plot: Dictionary = plots[index]
	plot["seed_id"] = seed_id
	plot["planted_unix"] = Time.get_unix_time_from_system()
	plot["grow_seconds"] = float(seed_data.get("grow_seconds", 3600))
	plot["harvested"] = false
	# Survival chance: base + 10% per compost, capped 100%.
	var survival: float = clampf(float(seed_data.get("base_survival", 0.5)) + 0.1 * float(plot["compost"]), 0.0, 1.0)
	plot["alive"] = _rng.randf() <= survival

## First empty plot wins. Returns the plot index, or -1 when nothing was plantable.
func plant_first_free(seed_id: String, consume_from_bank: bool = true) -> int:
	for i in range(plots.size()):
		if str(plots[i]["seed_id"]) == "":
			if plant(i, seed_id, consume_from_bank):
				return i
			return -1
	return -1

func apply_compost(plot_index: int) -> bool:
	if plot_index < 0 or plot_index >= plots.size():
		return false
	if not BankManager.has_item("compost", 1):
		return false
	BankManager.remove_item("compost", 1)
	plots[plot_index]["compost"] = int(plots[plot_index]["compost"]) + 1
	plots_changed.emit()
	return true

func is_ready(plot_index: int) -> bool:
	if plot_index < 0 or plot_index >= plots.size():
		return false
	var p: Dictionary = plots[plot_index]
	if p["seed_id"] == "" or not p["alive"]:
		return false
	return float(Time.get_unix_time_from_system()) >= float(p["planted_unix"]) + float(p["grow_seconds"])

## A crop that failed its survival roll stays on the plot until explicitly cleared.
func clear_plot(plot_index: int) -> bool:
	if plot_index < 0 or plot_index >= plots.size():
		return false
	var p: Dictionary = plots[plot_index]
	if p["seed_id"] == "" or p["alive"]:
		return false
	p["seed_id"] = ""
	p["planted_unix"] = 0.0
	p["grow_seconds"] = 0.0
	p["compost"] = 0
	p["alive"] = true
	p["harvested"] = false
	plots_changed.emit()
	return true

## Per-crop mastery bonuses, summed the way update_item_mastery_source sums them for an
## active action — but computed at harvest time from the crop's own mastery.
func _crop_mastery_bonus(action_id: String) -> Dictionary:
	var unlocks: Dictionary = DataLoader.get_skill("farming").get("mastery_unlocks", {})
	var lvl: int = MasteryManager.get_level("farming", action_id)
	var doubling: float = 0.0
	var flat: int = 0
	for threshold in unlocks.keys():
		if lvl >= int(threshold):
			var mods: Dictionary = unlocks[threshold]
			doubling += float(mods.get("farming_doubling_percent", 0.0))
			flat += int(mods.get("farming_resource_flat", 0))
	return {"doubling": doubling, "flat": flat}

func harvest(plot_index: int) -> Dictionary:
	if not is_ready(plot_index):
		return {}
	var p: Dictionary = plots[plot_index]
	var seed_data: Dictionary = DataLoader.get_item(p["seed_id"])
	var action_id: String = action_id_for_seed(str(p["seed_id"]))
	var bonus: Dictionary = _crop_mastery_bonus(action_id)
	var yield_qty: int = maxi(1, _rng.randi_range(int(seed_data.get("min_yield", 1)), int(seed_data.get("max_yield", 3))) + int(bonus["flat"]))
	# Per-unit doubling, mirroring SkillManager._produce_outputs.
	var total: int = 0
	for _i in range(yield_qty):
		total += 2 if _rng.randf() * 100.0 < float(bonus["doubling"]) else 1
	var out_item: String = seed_data.get("product_item", "")
	if out_item != "" and total > 0:
		BankManager.add_item(out_item, total)
		SimulationMode.bump(SimulationMode.BUCKET_ITEMS_PRODUCED, out_item, float(total))
	var xp: float = float(seed_data.get("harvest_xp", 0.0)) * ModifierManager.get_skill_xp_multiplier("farming")
	if xp > 0.0:
		PlayerData.add_xp("farming", xp)
	MasteryManager.add_mastery_xp("farming", action_id, float(p["grow_seconds"]) / 3600.0, 0.0)
	p["seed_id"] = ""
	p["harvested"] = true
	plots_changed.emit()
	return {"item_id": out_item, "quantity": total, "xp": xp}

## One pass over every plot; returns {plots, items, xp} covering only the ready crops.
func harvest_all() -> Dictionary:
	var out: Dictionary = {"plots": 0, "items": {}, "xp": 0.0}
	for i in range(plots.size()):
		if not is_ready(i):
			continue
		var res: Dictionary = harvest(i)
		if res.is_empty():
			continue
		out["plots"] = int(out["plots"]) + 1
		out["xp"] = float(out["xp"]) + float(res.get("xp", 0.0))
		var item_id: String = str(res.get("item_id", ""))
		if item_id != "":
			out["items"][item_id] = int(out["items"].get(item_id, 0)) + int(res.get("quantity", 0))
	return out

## Growth is time-based, so offline advancement only needs to detect newly-ready plots.
func advance_offline(_elapsed: float) -> int:
	return ready_count()

func serialize() -> Dictionary:
	return {"plots": plots}

func deserialize(d: Dictionary) -> void:
	plots = d.get("plots", [])
	if plots.is_empty():
		_build_plots()
