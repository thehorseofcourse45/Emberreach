extends Node
## Workers own independent timers and prepaid fuel. Target actions never use player modifiers.
var installed: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func devices() -> Array:
	return DataLoader.new_skill_systems.get("devices", [])

func device(id: String) -> Dictionary:
	for def in devices():
		if str(def.id) == id:
			return def
	return {}

func slots() -> int:
	var level: int = PlayerData.get_level("engineering")
	return mini(6, 2 + (1 if level >= 40 else 0) + (1 if level >= 80 else 0) + int(ModifierManager.get_modifier("engineering_device_slots")))

func install(id: String, action_id: String) -> bool:
	var def: Dictionary = device(id)
	if def.is_empty() or installed.size() >= slots() or PlayerData.get_level("engineering") < int(def.level) or not BankManager.has_item(id, 1):
		return false
	if not valid_work(def, action_id):
		return false
	BankManager.remove_item(id, 1)
	installed.append({"id": id, "action": action_id, "progress": 0.0, "fuel_seconds": 0.0, "status": "Waiting for fuel"})
	EventBus.state_refreshed.emit()
	return true

func valid_work(def: Dictionary, action_id: String) -> bool:
	var skill_id: String = str(def.skill)
	if skill_id == "combat":
		return action_id == "loot"
	var action: Dictionary = DataLoader.get_action(skill_id, action_id)
	return not action.is_empty() and PlayerData.get_level(skill_id) >= int(action.get("level_required", 1))

func uninstall(index: int) -> bool:
	if index < 0 or index >= installed.size():
		return false
	BankManager.add_item_guaranteed(str(installed[index].id), 1)
	installed.remove_at(index)
	EventBus.state_refreshed.emit()
	return true

func _process(delta: float) -> void:
	if GameManager.is_paused or OfflineProgression.is_running or SimulationMode.is_silent():
		return
	advance(delta / maxf(Engine.time_scale, 0.01))

func advance(seconds: float, end_time: float = 0.0) -> void:
	if not is_finite(seconds) or seconds <= 0:
		return
	if end_time <= 0.0:
		end_time = Time.get_unix_time_from_system()
	for index in range(mini(installed.size(), slots())):
		var worker: Dictionary = installed[index]
		var def: Dictionary = device(str(worker.id))
		if def.is_empty() or not valid_work(def, str(worker.action)):
			worker.status = "Work is locked"
			continue
		var remaining: float = seconds
		var device_mastery: int = MasteryManager.get_level("engineering", "assemble_" + str(def.id).trim_prefix("device_"))
		while remaining > 0:
			if float(worker.fuel_seconds) <= 0:
				var reduction: float = clampf(ModifierManager.get_modifier("engineering_fuel_reduction_percent") + float(device_mastery - 1) * 0.15, 0.0, 80.0)
				var fuel: int = maxi(1, ceili(float(def.fuel_cost) * (1.0 - reduction / 100.0)))
				if not BankManager.has_item(str(def.fuel), fuel):
					worker.status = "Out of fuel"
					break
				BankManager.remove_item(str(def.fuel), fuel)
				SimulationMode.bump(SimulationMode.BUCKET_ITEMS_CONSUMED, str(def.fuel), fuel)
				worker.fuel_seconds = 3600.0
				if PlayerData.active_potion == "potion_engineering":
					PotionManager.consume_charge("engineering:fuel")
			var farm_efficiency: float = clampf(0.4 + float(device_mastery - 1) * 0.001 + ModifierManager.get_modifier("engineering_efficiency_percent") / 100.0, 0.4, 0.8)
			var slice: float = minf(remaining, float(worker.fuel_seconds))
			if str(def.skill) == "farming": slice = minf(slice, maxf(0.001, (60.0 - float(worker.progress)) / farm_efficiency))
			worker.fuel_seconds = float(worker.fuel_seconds) - slice
			remaining -= slice
			var mastery: int = MasteryManager.get_level("engineering", "assemble_" + str(def.id).trim_prefix("device_"))
			var efficiency: float = clampf(0.4 + float(mastery - 1) * 0.001 + ModifierManager.get_modifier("engineering_efficiency_percent") / 100.0, 0.4, 0.8)
			worker.progress = float(worker.progress) + slice * efficiency
			worker.status = "Working"
			if str(def.skill) == "combat":
				# Scavengers collect defeated foes' pending loot, never generate extra combat rewards.
				if float(worker.progress) >= 59.999999:
					BankManager.withdraw_overflow()
					worker.progress = maxf(0.0, float(worker.progress) - 60.0)
			elif str(def.skill) == "farming":
				if float(worker.progress) >= 59.999999:
					var action: Dictionary = DataLoader.get_action("farming", str(worker.action))
					var seed_id: String = FarmingManager.seed_id_for_action(str(action.id))
					var logical_time: float = end_time - remaining
					for plot_index in range(FarmingManager.plots.size()):
						var plot: Dictionary = FarmingManager.plots[plot_index]
						if str(plot.seed_id) != "" and float(plot.planted_unix) + float(plot.grow_seconds) <= logical_time:
							if bool(plot.alive): FarmingManager.harvest(plot_index, false, logical_time)
							else: FarmingManager.clear_plot(plot_index)
						if str(FarmingManager.plots[plot_index].seed_id) == "" and BankManager.has_item(seed_id, 1):
							if FarmingManager.plant(plot_index, seed_id):
								FarmingManager.plots[plot_index].planted_unix = logical_time
					worker.progress = maxf(0.0, float(worker.progress) - 60.0)
			else:
				_work(worker, def)

func on_kill(monster: Dictionary) -> void:
	for index in range(mini(installed.size(), slots())):
		var worker: Dictionary = installed[index]
		if str(device(str(worker.id)).get("skill", "")) != "combat" or float(worker.fuel_seconds) <= 0:
			continue
		for drop in monster.get("loot_table", []):
			if typeof(drop) != TYPE_DICTIONARY or bool(drop.get("is_currency", false)):
				continue
			var item_id: String = str(drop.get("item_id", ""))
			if item_id != "" and _rng.randf() < 0.4 * float(drop.get("chance", 1.0)):
				var quantity: int = maxi(1, int(drop.get("quantity", 1)))
				BankManager.add_item_guaranteed(item_id, quantity)
				SimulationMode.bump(SimulationMode.BUCKET_ITEMS_PRODUCED, item_id, quantity)

func _work(worker: Dictionary, def: Dictionary) -> void:
	var skill_id: String = str(def.skill)
	var action: Dictionary = DataLoader.get_action(skill_id, str(worker.action))
	var interval: float = maxf(0.1, float(action.get("base_interval", 5.0)))
	if int(action.get("node_hp", 0)) > 0:
		interval += float(action.get("respawn_seconds", 0.0)) / float(action.node_hp)
	var count: int = int(float(worker.progress) / interval)
	if count <= 0:
		return
	for id in (action.get("input_items", {}) as Dictionary):
		count = mini(count, BankManager.get_count(str(id)) / maxi(1, int(action.input_items[id])))
	if count <= 0:
		worker.status = "Missing work materials"
		worker.progress = minf(float(worker.progress), interval)
		return
	var inputs: Dictionary = {}
	for id in (action.get("input_items", {}) as Dictionary):
		inputs[id] = int(action.input_items[id]) * count
	if not bool(BankManager.consume_bundle(inputs).ok):
		return
	for id in inputs:
		SimulationMode.bump(SimulationMode.BUCKET_ITEMS_CONSUMED, str(id), int(inputs[id]))
	worker.progress = maxf(0.0, float(worker.progress) - count * interval)
	var successful_work: float = float(worker.get("success_fraction", 0.0)) + float(count) * clampf(float(action.get("success_chance", 1.0)), 0.0, 1.0)
	var successes: int = floori(successful_work)
	worker.success_fraction = successful_work - successes
	for id in (action.get("output_items", {}) as Dictionary):
		var qty: int = int(action.output_items[id]) * successes
		BankManager.add_item_guaranteed(str(id), qty)
		SimulationMode.bump(SimulationMode.BUCKET_ITEMS_PRODUCED, str(id), qty)
	PlayerData.add_xp(skill_id, float(action.get("base_xp", 0.0)) * successes)
	MasteryManager.add_mastery_xp("engineering", "assemble_" + str(def.id).trim_prefix("device_"), float(count) * interval, ModifierManager.get_mastery_xp_bonus("engineering"))
	PlayerData.bump_stat("actions", "%s:%s" % [skill_id, str(worker.action)], float(successes))
	ProgressTracker.mark_dirty()

func serialize() -> Dictionary:
	return {"installed": installed.duplicate(true)}

func deserialize(data: Dictionary) -> void:
	installed = []
	var source: Variant = data.get("installed", [])
	if typeof(source) != TYPE_ARRAY:
		return
	for value in source.slice(0, 6):
		if typeof(value) != TYPE_DICTIONARY or device(str(value.get("id", ""))).is_empty():
			continue
		var progress: float = float(value.get("progress", 0.0))
		var fuel: float = float(value.get("fuel_seconds", 0.0))
		installed.append({"id": str(value.id), "action": str(value.get("action", "")),
			"progress": maxf(0.0, progress) if is_finite(progress) else 0.0,
			"fuel_seconds": clampf(fuel, 0.0, 3600.0) if is_finite(fuel) else 0.0,
			"success_fraction": clampf(float(value.get("success_fraction", 0.0)), 0.0, 0.999999), "status": "Ready"})

func worker_preview(index: int) -> Dictionary:
	if index < 0 or index >= installed.size(): return {}
	var worker: Dictionary = installed[index]
	var def: Dictionary = device(str(worker.id))
	var mastery: int = MasteryManager.get_level("engineering", "assemble_" + str(def.id).trim_prefix("device_"))
	var efficiency: float = clampf(0.4 + float(mastery - 1) * 0.001 + ModifierManager.get_modifier("engineering_efficiency_percent") / 100.0, 0.4, 0.8)
	var fuel: int = maxi(1, ceili(float(def.fuel_cost) * (1.0 - clampf(ModifierManager.get_modifier("engineering_fuel_reduction_percent") + float(mastery - 1) * 0.15, 0, 80) / 100.0)))
	var action: Dictionary = DataLoader.get_action(str(def.skill), str(worker.action))
	var interval: float = maxf(0.1, float(action.get("base_interval", 5)))
	if int(action.get("node_hp", 0)) > 0: interval += float(action.get("respawn_seconds", 0)) / float(action.node_hp)
	var attempts: float = efficiency * 3600.0 / interval
	var outputs: Dictionary = {}
	for id in action.get("output_items", {}): outputs[id] = float(action.output_items[id]) * attempts * clampf(float(action.get("success_chance", 1)), 0, 1)
	var materials: float = INF
	for id in action.get("input_items", {}): materials = minf(materials, BankManager.get_count(str(id)) / maxf(0.001, float(action.input_items[id]) * attempts))
	if str(def.skill) == "farming":
		outputs.clear()
		var seed_id: String = FarmingManager.seed_id_for_action(str(worker.action))
		var seed: Dictionary = DataLoader.get_item(seed_id)
		var cycles_hour: float = 0
		for i in range(FarmingManager.plots.size()):
			var crop: Dictionary = FarmingManager.planting_preview(i, seed_id)
			var cycles: float = 3600.0 / (float(crop.seconds) + 30.0 / efficiency)
			cycles_hour += cycles
			var id: String = str(seed.get("product_item", ""))
			outputs[id] = float(outputs.get(id, 0)) + cycles * float(crop.survival) * float(int(seed.get("min_yield", 1)) + int(seed.get("max_yield", 3))) / 2.0 * (1.0 + float(crop.yield_bonus) / 100.0)
		materials = BankManager.get_count(seed_id) / maxf(0.001, cycles_hour)
	return {"outputs": outputs, "fuel": fuel, "fuel_hours": float(worker.fuel_seconds) / 3600.0 + floorf(float(BankManager.get_count(str(def.fuel))) / fuel), "material_hours": materials, "efficiency": efficiency, "status": str(worker.status)}
