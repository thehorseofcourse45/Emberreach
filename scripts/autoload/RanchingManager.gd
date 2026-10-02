extends Node
## Real-time animal pens. Produce waits for collection; feed and cycle progress persist.
var pens: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func species(id: String) -> Dictionary:
	for entry in DataLoader.new_skill_systems.get("species", []):
		if str(entry.id) == id:
			return entry
	return {}

func pen_price() -> float:
	return 500.0 * pow(float(pens.size() + 1), 2.0)

func build_pen() -> bool:
	if pens.size() >= 6 or PlayerData.get_level("ranching") < 1 + pens.size() * 15 or PlayerData.gp < pen_price():
		return false
	PlayerData.spend_gp(pen_price())
	pens.append({"species": "", "animals": 0, "variant": false, "feed": 0.0, "happiness": 100.0,
		"progress": 0.0, "pending": {}, "pending_xp": 0.0, "cycles": 0, "breed_seconds": 0.0})
	EventBus.state_refreshed.emit()
	return true

func stock(index: int, id: String, variant: bool = false) -> bool:
	var def: Dictionary = species(id)
	if index < 0 or index >= pens.size() or def.is_empty() or PlayerData.get_level("ranching") < int(def.level):
		return false
	var pen: Dictionary = pens[index]
	if int(pen.animals) >= 2 or (int(pen.animals) > 0 and (str(pen.species) != id or bool(pen.variant) != variant)):
		return false
	var stock_id: String = str(def.stock)
	if variant:
		stock_id = "golden_hen_stock" if id == "hen" else "mooncalf_stock" if id == "cow" else ""
	if stock_id == "" or not BankManager.has_item(stock_id, 1):
		return false
	BankManager.remove_item(stock_id, 1)
	pen.species = id
	pen.variant = variant
	pen.animals = int(pen.animals) + 1
	EventBus.state_refreshed.emit()
	return true

func crop_feed(item_id: String, quantity: int) -> bool:
	var valid: bool = false
	for def in DataLoader.items.values():
		if typeof(def) == TYPE_DICTIONARY and str(def.get("product_item", "")) == item_id:
			valid = true
	if not valid or quantity <= 0 or not BankManager.has_item(item_id, quantity):
		return false
	BankManager.remove_item(item_id, quantity)
	BankManager.add_item_guaranteed("ranch_feed", quantity * 10)
	return true

func feed_pen(index: int, quantity: int) -> bool:
	if index < 0 or index >= pens.size() or quantity <= 0 or not BankManager.has_item("ranch_feed", quantity):
		return false
	BankManager.remove_item("ranch_feed", quantity)
	pens[index].feed = float(pens[index].feed) + quantity
	pens[index].happiness = 100.0
	EventBus.state_refreshed.emit()
	return true

func _process(delta: float) -> void:
	if GameManager.is_paused or OfflineProgression.is_running or SimulationMode.is_silent():
		return
	advance(delta / maxf(Engine.time_scale, 0.01))

func advance(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0.0:
		return
	var changed: bool = false
	for pen in pens:
		if int(pen.animals) <= 0:
			continue
		var def: Dictionary = species(str(pen.species))
		if def.is_empty():
			continue
		var mastery: int = MasteryManager.get_level("ranching", "raise_" + str(def.id))
		var feed_rate: float = float(def.feed) * float(pen.animals) / 3600.0 * maxf(0.1, 1.0 - ModifierManager.get_modifier("ranching_feed_reduction_percent") / 100.0)
		var fed: float = minf(seconds, float(pen.feed) / feed_rate)
		pen.feed = maxf(0.0, float(pen.feed) - fed * feed_rate)
		var hungry: float = seconds - fed
		var floor_happiness: float = maxf(25.0, ModifierManager.get_modifier("ranching_happiness_floor"))
		var old_happiness: float = 100.0 if fed > 0 else float(pen.happiness)
		pen.happiness = maxf(floor_happiness, old_happiness - hungry / 3600.0 * 10.0)
		var decay_seconds: float = minf(hungry, maxf(0.0, old_happiness - floor_happiness) / 10.0 * 3600.0)
		var productive_seconds: float = fed + decay_seconds * (old_happiness + float(pen.happiness)) / 200.0 + (hungry - decay_seconds) * floor_happiness / 100.0
		var speed: float = (1.0 + 0.02 * float(mastery - 1)) * (1.0 + ModifierManager.get_modifier("ranching_interval_percent") / 100.0)
		pen.progress = float(pen.progress) + productive_seconds * speed
		var cycles: int = int(float(pen.progress) / float(def.seconds))
		pen.progress = fmod(float(pen.progress), float(def.seconds))
		if cycles > 0:
			changed = true
			var qty: int = cycles * int(pen.animals) * (2 if bool(pen.variant) else 1)
			qty += cycles * int(ModifierManager.get_resource_flat("ranching"))
			if _rng.randf() * 100.0 < ModifierManager.get_doubling_chance("ranching"):
				qty *= 2
			pen.pending[str(def.produce)] = int(pen.pending.get(str(def.produce), 0)) + qty
			pen.pending["ranch_manure"] = int(pen.pending.get("ranch_manure", 0)) + cycles * int(pen.animals)
			pen.pending_xp = float(pen.pending_xp) + cycles * int(pen.animals) * float(def.xp)
			pen.cycles = int(pen.cycles) + cycles
		pen.breed_seconds = float(pen.breed_seconds) + seconds
		if ModifierManager.get_modifier("ranching_autocollect") > 0.0 and int(pen.cycles) > 0:
			collect(pens.find(pen))
	if changed and not SimulationMode.is_silent():
		EventBus.state_refreshed.emit()

func collect(index: int) -> bool:
	if index < 0 or index >= pens.size():
		return false
	var pen: Dictionary = pens[index]
	if int(pen.cycles) <= 0:
		return false
	for id in pen.pending:
		BankManager.add_item_guaranteed(str(id), int(pen.pending[id]))
		SimulationMode.bump(SimulationMode.BUCKET_ITEMS_PRODUCED, str(id), float(pen.pending[id]))
	PlayerData.add_xp("ranching", float(pen.pending_xp) * ModifierManager.get_skill_xp_multiplier("ranching"))
	MasteryManager.add_mastery_xp("ranching", "raise_" + str(pen.species), float(pen.cycles) * float(species(str(pen.species)).get("seconds", 7200.0)), ModifierManager.get_mastery_xp_bonus("ranching"))
	SummoningManager.on_action("ranching", 60.0)
	PetManager.roll_for_skill("ranching", float(pen.cycles) * float(species(str(pen.species)).get("seconds", 7200.0)))
	if str(DataLoader.get_item(PlayerData.active_potion).get("id", "")) == "potion_ranching":
		PotionManager.consume_charge("ranching:collection")
	pen.pending = {}
	pen.pending_xp = 0.0
	pen.cycles = 0
	EventBus.state_refreshed.emit()
	return true

func breed(index: int) -> bool:
	if index < 0 or index >= pens.size():
		return false
	var pen: Dictionary = pens[index]
	if int(pen.animals) != 2 or float(pen.breed_seconds) < 21600.0 or float(pen.happiness) < 50.0:
		return false
	pen.breed_seconds = 0.0
	if _rng.randf() > 0.75:
		EventBus.notify("No offspring this time. Your animals can breed again in six hours.", "info")
		EventBus.state_refreshed.emit()
		return true
	var def: Dictionary = species(str(pen.species))
	var chance: float = 0.03 + ModifierManager.get_modifier("ranching_variant_percent") / 100.0
	var mastery: int = MasteryManager.get_level("ranching", "raise_" + str(pen.species))
	chance += 0.02 if mastery >= 50 else 0.0
	chance += 0.05 if mastery >= 99 else 0.0
	var rare: bool = _rng.randf() < chance and str(pen.species) in ["hen", "cow"]
	BankManager.add_item_guaranteed(("golden_hen_stock" if str(pen.species) == "hen" else "mooncalf_stock") if rare else str(def.stock), 1)
	EventBus.notify("Breeding produced " + ("a rare variant!" if rare else str(def.name) + " stock."), "success")
	EventBus.state_refreshed.emit()
	return true

func retire(index: int) -> bool:
	if index < 0 or index >= pens.size() or int(pens[index].animals) <= 0:
		return false
	var pen: Dictionary = pens[index]
	collect(index)
	var def: Dictionary = species(str(pen.species))
	BankManager.add_item_guaranteed("ranch_meat", int(def.meat))
	BankManager.add_item_guaranteed(str(def.hide), 2)
	pen.animals = int(pen.animals) - 1
	if int(pen.animals) == 0:
		pen.species = ""
		pen.progress = 0.0
		pen.breed_seconds = 0.0
	EventBus.state_refreshed.emit()
	return true

func serialize() -> Dictionary:
	return {"pens": pens.duplicate(true)}

func deserialize(data: Dictionary) -> void:
	pens = []
	var source: Variant = data.get("pens", [])
	if typeof(source) != TYPE_ARRAY:
		return
	for value in source.slice(0, 6):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = value.duplicate(true)
		if not species(str(p.get("species", ""))).is_empty() or str(p.get("species", "")) == "":
			p.animals = clampi(int(p.get("animals", 0)), 0, 2)
			p.variant = bool(p.get("variant", false))
			for key in ["feed", "progress", "pending_xp", "breed_seconds"]:
				var n: float = float(p.get(key, 0.0))
				p[key] = maxf(0.0, n) if is_finite(n) else 0.0
			p.happiness = clampf(float(p.get("happiness", 100.0)), 25.0, 100.0)
			p.cycles = maxi(0, int(p.get("cycles", 0)))
			p.pending = p.get("pending", {}) if typeof(p.get("pending", {})) == TYPE_DICTIONARY else {}
			pens.append(p)
