extends Node
## Caravaneering: caravans carry Storage items along trade routes over discovered Cartography hexes.
## A trip is a countdown in seconds (no wall clock), so reloads and clock changes cannot pay twice.
## Prices are deterministic per route + good + day. Bandits are a data roll: route risk vs guard power.

const DAY_SECONDS: float = 86400.0
const HISTORY_LIMIT: int = 10

var caravans: Array = []            # {route, wagon, guard, cargo, remaining, total, repeat, status}
var owned_wagons: Array = ["handcart"]
var history: Array = []             # newest first: {route, revenue, loss, xp, items}
var _tally: Dictionary = {"trips": 0, "gp": 0, "xp": 0, "items": {}}
var _rng := RandomNumberGenerator.new()
var _dirty: bool = false

func _ready() -> void:
	_rng.randomize()

func seed_rng(value: int) -> void:
	_rng.seed = value

# ---------------- data ----------------
func _group(key: String) -> Array:
	return DataLoader.new_skill_systems.get(key, [])

func _find(key: String, id: String) -> Dictionary:
	for def in _group(key):
		if str(def.id) == id:
			return def
	return {}

func route(id: String) -> Dictionary: return _find("caravan_routes", id)
func wagon(id: String) -> Dictionary: return _find("caravan_wagons", id)
func guard(id: String) -> Dictionary: return _find("caravan_guards", id)
func routes() -> Array: return _group("caravan_routes")
func wagons() -> Array: return _group("caravan_wagons")
func guards() -> Array: return _group("caravan_guards")

func slots() -> int:
	var level: int = PlayerData.get_level("caravaneering")
	return mini(6, 1 + (1 if level >= 40 else 0) + (1 if level >= 80 else 0) + int(ModifierManager.get_modifier("caravaneering_slots")))

func capacity(wagon_id: String) -> int:
	return int(wagon(wagon_id).get("capacity", 0))

func today() -> int:
	return floori(Time.get_unix_time_from_system() / DAY_SECONDS)

# ---------------- prices ----------------
func _hash(route_id: String, item_id: String, salt: String) -> int:
	return absi(hash(route_id + "|" + item_id + "|" + salt))

## Daily drift, 0.85 to 1.20, fixed by route + good + day.
func price_factor(route_id: String, item_id: String, day: int) -> float:
	return 0.85 + float(_hash(route_id, item_id, str(day)) % 351) / 1000.0

## Demand goods pay 1.3 to 1.6x at their destination; everything else 1.0x.
func demand_factor(route_id: String, item_id: String) -> float:
	if not (route(route_id).get("demand", []) as Array).has(item_id):
		return 1.0
	return 1.3 + float(_hash(route_id, item_id, "demand") % 31) / 100.0

## The General Store's unit price for an item (0 when it is not sold there). A caravan never pays
## more per unit than the store charges, so buy-and-ship can never mint gold.
func store_price(item_id: String) -> float:
	var best: float = 0.0
	for offer in DataLoader.shop_store.values():
		if offer is Dictionary and str(offer.get("item_id", "")) == item_id:
			var price: float = float(offer.get("unit_price", 0.0))
			if price > 0.0 and (best <= 0.0 or price < best):
				best = price
	return best

func unit_price(route_id: String, item_id: String, day: int) -> float:
	var def: Dictionary = route(route_id)
	if def.is_empty():
		return 0.0
	var profit: float = 1.0 + ModifierManager.get_modifier("caravaneering_profit_percent") / 100.0
	var price: float = float(DataLoader.get_item(item_id).get("sell_price", 0)) * float(def.multiplier) * demand_factor(route_id, item_id) * price_factor(route_id, item_id, day) * profit
	var cap: float = store_price(item_id)
	return minf(price, cap) if cap > 0.0 else price

func sale_value(route_id: String, item_id: String, qty: int, day: int) -> int:
	return floori(unit_price(route_id, item_id, day) * float(maxi(0, qty)))

func load_of(cargo: Dictionary) -> int:
	var total: int = 0
	for item_id in cargo:
		total += maxi(0, int(cargo[item_id]))
	return total

func trip_seconds(route_id: String) -> float:
	var def: Dictionary = route(route_id)
	var cut: float = clampf(ModifierManager.get_modifier("caravaneering_interval_percent"), 0.0, 60.0)
	return float(def.get("hours", 0.0)) * 3600.0 * (1.0 - cut / 100.0)

func loss_chance(route_id: String, guard_id: String) -> float:
	return clampf(float(route(route_id).get("risk", 0)) - float(guard(guard_id).get("power", 0)), 0.0, 100.0) / 100.0

func preview(route_id: String, wagon_id: String, guard_id: String, cargo: Dictionary) -> Dictionary:
	var day: int = today()
	var base: float = 0.0
	var revenue: float = 0.0
	for item_id in cargo:
		var qty: int = maxi(0, int(cargo[item_id]))
		base += float(DataLoader.get_item(str(item_id)).get("sell_price", 0)) * qty
		revenue += float(sale_value(route_id, str(item_id), qty, day))
	var chance: float = loss_chance(route_id, guard_id)
	var expected: float = revenue * ((1.0 - chance) * 1.05 + chance * 0.75)
	var wage: float = float(guard(guard_id).get("wage", 0))
	var hours: float = trip_seconds(route_id) / 3600.0
	return {"revenue": revenue, "expected_revenue": expected, "wages": wage, "base_value": base,
		"profit": expected - wage - base, "loss_risk": chance, "hours": hours,
		"gp_per_hour": (expected - wage) / maxf(hours, 0.001), "xp": float(route(route_id).get("xp", 0))}

# ---------------- dispatch ----------------
func wagon_in_use(wagon_id: String) -> bool:
	for c in caravans:
		if str(c.wagon) == wagon_id and not bool(c.get("idle", false)):
			return true
	return false

func buy_wagon(wagon_id: String) -> bool:
	var def: Dictionary = wagon(wagon_id)
	if def.is_empty() or owned_wagons.has(wagon_id) or PlayerData.get_level("caravaneering") < int(def.level):
		return false
	if not PlayerData.spend_gp(float(def.price)):
		return false
	owned_wagons.append(wagon_id)
	EventBus.state_refreshed.emit()
	return true

## "" when the dispatch is allowed, otherwise the reason (also what the UI shows).
func can_dispatch(route_id: String, wagon_id: String, guard_id: String, cargo: Dictionary, ignore_index: int = -1) -> String:
	var r: Dictionary = route(route_id)
	var w: Dictionary = wagon(wagon_id)
	var g: Dictionary = guard(guard_id)
	if r.is_empty(): return "Unknown route"
	if w.is_empty(): return "Unknown wagon"
	if g.is_empty(): return "Unknown guard"
	var level: int = PlayerData.get_level("caravaneering")
	if level < int(r.level): return "Route unlocks at Caravaneering %d" % int(r.level)
	if level < int(w.level): return "Wagon unlocks at Caravaneering %d" % int(w.level)
	if level < int(g.level): return "Guard unlocks at Caravaneering %d" % int(g.level)
	if not CartographyManager.is_discovered(str(r.hex)): return "Destination not discovered yet"
	if not owned_wagons.has(wagon_id): return "You do not own that wagon"
	var busy: int = 0
	for i in range(caravans.size()):
		if i == ignore_index:
			continue
		busy += 1
		if str(caravans[i].wagon) == wagon_id and not bool(caravans[i].get("idle", false)):
			return "That wagon is already out"
	if busy >= slots(): return "No free caravan slot"
	var total: int = load_of(cargo)
	if total <= 0: return "Load some cargo first"
	if total > int(w.capacity): return "Cargo exceeds the wagon's capacity"
	for item_id in cargo:
		if int(cargo[item_id]) < 0 or not BankManager.has_item(str(item_id), int(cargo[item_id])):
			return "Out of cargo"
	if PlayerData.gp < float(g.wage): return "Out of gold for the guard's wage"
	return ""

func dispatch(route_id: String, wagon_id: String, guard_id: String, cargo: Dictionary, repeat: bool = false) -> bool:
	if can_dispatch(route_id, wagon_id, guard_id, cargo) != "":
		return false
	_launch(route_id, wagon_id, guard_id, cargo, repeat)
	_notify()
	return true

func _launch(route_id: String, wagon_id: String, guard_id: String, cargo: Dictionary, repeat: bool, at: int = -1) -> void:
	var clean: Dictionary = {}
	for item_id in cargo:
		var qty: int = int(cargo[item_id])
		if qty > 0:
			BankManager.remove_item(str(item_id), qty)
			SimulationMode.bump(SimulationMode.BUCKET_ITEMS_CONSUMED, str(item_id), qty)
			clean[str(item_id)] = qty
	PlayerData.spend_gp(float(guard(guard_id).wage))
	var seconds: float = trip_seconds(route_id)
	var entry: Dictionary = {"route": route_id, "wagon": wagon_id, "guard": guard_id, "cargo": clean,
		"remaining": seconds, "total": seconds, "repeat": repeat, "status": "Travelling"}
	if at >= 0 and at < caravans.size():
		caravans[at] = entry
	else:
		caravans.append(entry)
	_dirty = true

func set_repeat(index: int, on: bool) -> void:
	if index >= 0 and index < caravans.size():
		caravans[index].repeat = on

## Try to send a parked (idle) caravan out again on its old orders, e.g. after restocking.
func resume(index: int) -> bool:
	if index < 0 or index >= caravans.size() or not bool(caravans[index].get("idle", false)):
		return false
	var c: Dictionary = caravans[index]
	var why: String = can_dispatch(str(c.route), str(c.wagon), str(c.guard), c.cargo, index)
	if why != "":
		c.status = why
		return false
	_launch(str(c.route), str(c.wagon), str(c.guard), c.cargo, true, index)
	_notify()
	return true

## Remove an idle (blocked) caravan entry.
func dismiss(index: int) -> bool:
	if index < 0 or index >= caravans.size() or not bool(caravans[index].get("idle", false)):
		return false
	caravans.remove_at(index)
	_notify()
	return true

# ---------------- time ----------------
func _process(delta: float) -> void:
	if GameManager.is_paused or OfflineProgression.is_running or SimulationMode.is_silent():
		return
	advance(delta / maxf(Engine.time_scale, 0.01))

## Advance every travelling caravan by `seconds`. `_end_time` is accepted for symmetry with the
## other passive systems; trips are countdowns, so it is not needed.
func advance(seconds: float, _end_time: float = 0.0) -> void:
	if not is_finite(seconds) or seconds <= 0.0:
		return
	# Every caravan already out keeps moving, whatever the slot count is now (a cape swap must not
	# strand one). Back to front so a finished (removed) caravan never shifts one we have yet to visit.
	for index in range(caravans.size() - 1, -1, -1):
		var left: float = seconds
		var guard_trips: int = 0
		while left > 0.0 and guard_trips < 5000 and index < caravans.size():
			guard_trips += 1
			var c: Dictionary = caravans[index]
			if bool(c.get("idle", false)):
				break
			if float(c.remaining) > left:
				c.remaining = float(c.remaining) - left
				break
			left -= float(c.remaining)
			if not _complete(index):
				break   # the slot was freed; the caravan now at `index` was already advanced
	if _dirty:
		_notify()

## One UI refresh per change batch, and none while a silent/offline simulation is running.
func _notify() -> void:
	if SimulationMode.is_silent() or OfflineProgression.is_running:
		_dirty = false
		return
	_dirty = false
	EventBus.state_refreshed.emit()

## Returns true when a caravan still occupies `index` afterwards (a repeat trip or a parked one).
func _complete(index: int) -> bool:
	_dirty = true
	var c: Dictionary = caravans[index]
	var r: Dictionary = route(str(c.route))
	var day: int = today()
	var revenue: float = 0.0
	for item_id in c.cargo:
		revenue += float(sale_value(str(c.route), str(item_id), int(c.cargo[item_id]), day))
	var loss: float = 0.0
	if _rng.randf() < loss_chance(str(c.route), str(c.guard)):
		loss = _rng.randf_range(0.10, 0.40)
		revenue *= 1.0 - loss
	else:
		revenue *= 1.05
	var gold: int = floori(revenue)
	PlayerData.add_gp(gold)
	var xp: float = float(r.get("xp", 0)) * ModifierManager.get_skill_xp_multiplier("caravaneering")
	PlayerData.add_xp("caravaneering", xp)
	MasteryManager.add_mastery_xp("caravaneering", str(c.route), float(c.total), ModifierManager.get_mastery_xp_bonus("caravaneering"))
	var doubling: float = ModifierManager.get_modifier("caravaneering_doubling_percent") / 100.0
	var found: Dictionary = {}
	for item_id in (r.get("specialty", {}) as Dictionary):
		var qty: int = int(r.specialty[item_id]) * (2 if _rng.randf() < doubling else 1)
		BankManager.add_item_guaranteed(str(item_id), qty)
		SimulationMode.bump(SimulationMode.BUCKET_ITEMS_PRODUCED, str(item_id), qty)
		found[str(item_id)] = qty
	if PlayerData.active_potion == "potion_caravaneering":
		PotionManager.consume_charge("caravaneering:trip")
	history.push_front({"route": str(c.route), "revenue": gold, "loss": loss, "xp": xp, "items": found})
	if history.size() > HISTORY_LIMIT:
		history.resize(HISTORY_LIMIT)
	_tally.trips = int(_tally.trips) + 1
	_tally.gp = int(_tally.gp) + gold
	_tally.xp = int(_tally.xp) + int(xp)
	for item_id in found:
		_tally.items[item_id] = int(_tally.items.get(item_id, 0)) + int(found[item_id])
	# Same orders again, or park the caravan with the reason it cannot go.
	var again: Dictionary = {"route": str(c.route), "wagon": str(c.wagon), "guard": str(c.guard), "cargo": (c.cargo as Dictionary).duplicate()}
	if bool(c.repeat):
		caravans.remove_at(index)
		var why: String = can_dispatch(again.route, again.wagon, again.guard, again.cargo)
		if why == "":
			caravans.insert(index, {})
			_launch(again.route, again.wagon, again.guard, again.cargo, true, index)
		else:
			caravans.insert(index, {"route": again.route, "wagon": again.wagon, "guard": again.guard, "cargo": again.cargo,
				"remaining": 0.0, "total": 0.0, "repeat": true, "idle": true, "status": why})
		return true
	caravans.remove_at(index)
	return false

func take_tally() -> Dictionary:
	var out: Dictionary = _tally.duplicate(true)
	_tally = {"trips": 0, "gp": 0, "xp": 0, "items": {}}
	return out

# ---------------- save ----------------
func serialize() -> Dictionary:
	return {"caravans": caravans.duplicate(true), "owned_wagons": owned_wagons.duplicate(), "history": history.duplicate(true)}

func deserialize(data: Dictionary) -> void:
	caravans = []
	owned_wagons = ["handcart"]
	history = []
	var owned: Variant = data.get("owned_wagons", [])
	if owned is Array:
		for id in owned:
			if not wagon(str(id)).is_empty() and not owned_wagons.has(str(id)):
				owned_wagons.append(str(id))
	var saved: Variant = data.get("caravans", [])
	if saved is Array:
		for entry in saved:
			if not entry is Dictionary or route(str(entry.get("route", ""))).is_empty() or wagon(str(entry.get("wagon", ""))).is_empty() or guard(str(entry.get("guard", ""))).is_empty():
				continue
			var cargo: Dictionary = {}
			var raw: Variant = entry.get("cargo", {})
			if raw is Dictionary:
				for item_id in raw:
					var qty: int = int(raw[item_id])
					if qty > 0 and not DataLoader.get_item(str(item_id)).is_empty():
						cargo[str(item_id)] = qty
			var total: float = float(entry.get("total", 0.0))
			var remaining: float = float(entry.get("remaining", 0.0))
			total = total if is_finite(total) and total >= 0.0 else 0.0
			remaining = clampf(remaining if is_finite(remaining) else 0.0, 0.0, maxf(total, 3600.0 * 24.0))
			caravans.append({"route": str(entry.route), "wagon": str(entry.wagon), "guard": str(entry.guard), "cargo": cargo,
				"remaining": remaining, "total": total, "repeat": bool(entry.get("repeat", false)),
				"idle": bool(entry.get("idle", false)), "status": str(entry.get("status", "Travelling"))})
			if not owned_wagons.has(str(entry.wagon)):
				owned_wagons.append(str(entry.wagon))
		caravans = caravans.slice(0, 6)
	var past: Variant = data.get("history", [])
	if past is Array:
		for entry in past:
			if entry is Dictionary and not route(str(entry.get("route", ""))).is_empty():
				history.append({"route": str(entry.route), "revenue": maxi(0, int(entry.get("revenue", 0))),
					"loss": clampf(float(entry.get("loss", 0.0)), 0.0, 1.0), "xp": maxf(0.0, float(entry.get("xp", 0.0))),
					"items": entry.get("items", {}) if entry.get("items", {}) is Dictionary else {}})
		history = history.slice(0, HISTORY_LIMIT)
	_tally = {"trips": 0, "gp": 0, "xp": 0, "items": {}}
