extends Node
## TownshipManager — Emberreach's settlement simulation.
##
## The settlement is a self-contained economy: it produces its own stores on real elapsed time
## (one tick per hour, online or offline) and spends those stores on structures that feed the
## main game's bottlenecks. It never meters progress behind a second grind — every structure
## either produces a resource another system consumes, raises storage, or unlocks a convenience.
##
## Production for offline time is applied from elapsed seconds, not from rendered frames, so a
## closed game and an open game advance the settlement identically.

const SECONDS_PER_TICK: float = 3600.0
## Population is 4–24 in this town; each resident supplies hourly skill XP.
const XP_PER_RESIDENT: float = 2500.0
const CATEGORY: String = "township"
const DEFAULT_MAX_LEVEL: int = 5

## Every resource the settlement can hold. Population is deliberately NOT here: it is a gate
## (a derived count), not a spendable store, and the panel shows it separately.
const ALL_RESOURCES: Array[String] = [
	"wood", "stone", "metal", "food",
	"goods", "reagents", "drills", "supplies",
	"faith", "astral_dust",
]

const RESOURCE_NAMES: Dictionary = {
	"wood": "Timber",
	"stone": "Stone",
	"metal": "Metal",
	"food": "Provisions",
	"goods": "Trade Goods",
	"reagents": "Reagents",
	"drills": "Drill Hours",
	"supplies": "Expedition Supplies",
	"faith": "Faith",
	"astral_dust": "Astral Dust",
	"population": "Residents",
}

## What each resource is FOR, so a store is never a mystery number on a dashboard.
const RESOURCE_ROLES: Dictionary = {
	"wood": "Construction & Kilncraft",
	"stone": "Construction",
	"metal": "Forgecraft inputs",
	"food": "Population & crates",
	"goods": "Trader crates",
	"reagents": "Apothecary inputs",
	"drills": "Combat preparation",
	"supplies": "Expedition readiness",
	"faith": "Devotion points (trader)",
	"astral_dust": "Sifted into Starreading dust",
	"population": "Gates larger structures",
}

var resources: Dictionary = {}
var buildings: Dictionary = {}       # building_id -> level
var population: int = 0
var worship: String = ""
var _tick_accumulator: float = 0.0

func _ready() -> void:
	_reset_resources()
	EventBus.game_loaded.connect(_reregister_modifiers)

func _process(delta: float) -> void:
	if GameManager.is_paused or OfflineProgression.is_running or SimulationMode.is_silent(): return
	_tick_accumulator += delta / maxf(0.001, Engine.time_scale)
	while _tick_accumulator >= SECONDS_PER_TICK:
		_tick_accumulator -= SECONDS_PER_TICK
		produce_tick()

func _reset_resources() -> void:
	for res_id in ALL_RESOURCES:
		if not resources.has(res_id):
			resources[res_id] = 0.0

# =========================================================================
#  Queries used by the UI and by goals
# =========================================================================

func buildings_data() -> Dictionary:
	return DataLoader.township_buildings

func resource_name(res_id: String) -> String:
	return str(RESOURCE_NAMES.get(res_id, res_id.capitalize()))

func resource_role(res_id: String) -> String:
	return str(RESOURCE_ROLES.get(res_id, ""))

func max_level_of(building_id: String) -> int:
	return int(buildings_data().get(building_id, {}).get("max_level", DEFAULT_MAX_LEVEL))

func level_of(building_id: String) -> int:
	return int(buildings.get(building_id, 0))

func is_max_level(building_id: String) -> bool:
	return level_of(building_id) >= max_level_of(building_id)

## Total hourly output of one resource across every structure. This is the number the panel
## shows next to the store, so the settlement's rate is never implied.
func production_per_hour(res_id: String) -> float:
	var total: float = 0.0
	for building_id in buildings.keys():
		var def: Dictionary = buildings_data().get(building_id, {})
		var per_level: float = float((def.get("production", {}) as Dictionary).get(res_id, 0.0))
		total += per_level * float(level_of(str(building_id)))
	return total

## Cost of the NEXT level of a structure, grown by `cost_growth` per level already built.
func scaled_cost(building_id: String) -> Dictionary:
	var def: Dictionary = buildings_data().get(building_id, {})
	if def.is_empty():
		return {}
	var base: Dictionary = def.get("cost", {})
	var growth: float = float(def.get("cost_growth", 1.0))
	var level: int = level_of(building_id)
	var factor: float = pow(maxf(growth, 1.0), float(level))
	var out: Dictionary = {}
	for res_id in base.keys():
		out[str(res_id)] = maxf(1.0, ceil(float(base[res_id]) * factor))
	return out

func can_build(building_id: String) -> Dictionary:
	if not buildings_data().has(building_id):
		return {"ok": false, "reason": "Unknown structure"}
	if is_max_level(building_id):
		return {"ok": false, "reason": "Fully built"}
	var cost: Dictionary = scaled_cost(building_id)
	for res_id in cost.keys():
		var have: float = float(resources.get(res_id, 0.0))
		if have < float(cost[res_id]):
			return {"ok": false, "reason": "Not enough %s (%s / %s)" % [
				resource_name(str(res_id)), UIStyle.fmt(have), UIStyle.fmt(float(cost[res_id]))]}
	return {"ok": true, "reason": ""}

func seconds_to_next_tick() -> float:
	return maxf(0.0, SECONDS_PER_TICK - _tick_accumulator)

func total_stored() -> float:
	var total: float = 0.0
	for res_id in ALL_RESOURCES:
		total += float(resources.get(res_id, 0.0))
	return total

# =========================================================================
#  Production
# =========================================================================

func produce_tick() -> void:
	for building_id in buildings.keys():
		var def: Dictionary = buildings_data().get(building_id, {})
		var production: Dictionary = def.get("production", {})
		for res in production.keys():
			if str(res) == "population":
				continue   # population is derived, never stored as a spendable resource
			resources[str(res)] = float(resources.get(str(res), 0.0)) \
				+ float(production[res]) * float(level_of(str(building_id)))
	population = int(productions_population())
	var xp: float = xp_per_hour()
	if xp > 0.0:
		PlayerData.add_xp("township", xp)

func xp_per_hour() -> float:
	return float(productions_population()) * XP_PER_RESIDENT * ModifierManager.get_skill_xp_multiplier("township")

func productions_population() -> int:
	var pop: int = 0
	for building_id in buildings.keys():
		var def: Dictionary = buildings_data().get(building_id, {})
		pop += int((def.get("production", {}) as Dictionary).get("population", 0)) * level_of(str(building_id))
	return pop

# =========================================================================
#  Build
# =========================================================================

func build(building_id: String) -> bool:
	var def: Dictionary = buildings_data().get(building_id, {})
	if def.is_empty():
		EventBus.notify("Unknown structure.", "warn")
		return false
	if is_max_level(building_id):
		EventBus.notify("%s is already fully built." % def.get("name", building_id), "info")
		return false
	# One validation pass on the SAME numbers the panel displayed, then one atomic spend.
	var check: Dictionary = can_build(building_id)
	if not bool(check["ok"]):
		EventBus.notify("Cannot build: %s" % str(check["reason"]), "warn")
		return false
	var cost: Dictionary = scaled_cost(building_id)
	for res in cost.keys():
		resources[res] = float(resources.get(res, 0.0)) - float(cost[res])
	buildings[building_id] = level_of(building_id) + 1
	PlayerData.add_xp("township", 25.0 * float(level_of(building_id)) * ModifierManager.get_skill_xp_multiplier("township"))
	population = int(productions_population())
	_reregister_modifiers()
	ProgressTracker.record_building(building_id)
	EventBus.notify("Built %s (level %d)." % [def.get("name", building_id), level_of(building_id)], "success")
	EventBus.state_refreshed.emit()
	EventBus.activity_changed.emit()
	return true

## The storehouse is the one structure that changes a main-game limit, so its effect is
## registered as a modifier rather than applied inline. Derived state, re-registered on load.
func _reregister_modifiers() -> void:
	ModifierManager.unregister("%s:storehouse" % CATEGORY)
	var level: int = level_of("township_building_storehouse")
	if level <= 0:
		return
	ModifierManager.register("%s:storehouse" % CATEGORY,
		{ModifierKeys.BANK_SPACE_FLAT: 5 * level}, CATEGORY,
		"Storehouse (level %d)" % level)

# =========================================================================
#  Offline
# =========================================================================

## Advance the settlement by `elapsed` real seconds. Returns the number of full ticks applied.
func advance_offline(elapsed: float) -> int:
	if elapsed <= 0.0:
		return 0
	_tick_accumulator += elapsed
	var ticks: int = int(floor(_tick_accumulator / SECONDS_PER_TICK))
	if ticks <= 0:
		return 0
	_tick_accumulator -= float(ticks) * SECONDS_PER_TICK
	for _i in range(ticks):
		produce_tick()
	return ticks

# =========================================================================
#  Trader & worship
# =========================================================================

# =========================================================================
#  Trader — what gives the settlement's stores a purpose
# =========================================================================

## Every offer the settlement can fulfil, in catalogue order.
func offers() -> Array:
	var out: Array = []
	for offer_id in DataLoader.trader.keys():
		var offer: Variant = DataLoader.trader[offer_id]
		if typeof(offer) == TYPE_DICTIONARY:
			out.append(offer)
	return out

## A trader offer needs the structure that produces its goods, then the stores themselves.
func can_trade(offer_id: String) -> Dictionary:
	var offer: Dictionary = DataLoader.trader.get(offer_id, {})
	if offer.is_empty():
		return {"ok": false, "reason": "Unknown offer"}
	var required: String = str(offer.get("requires_building", ""))
	if required != "" and level_of(required) <= 0:
		return {"ok": false, "reason": "Requires a %s" % str(buildings_data().get(required, {}).get("name", required))}
	for res_id in (offer.get("cost", {}) as Dictionary).keys():
		var have: float = float(resources.get(res_id, 0.0))
		var need: float = float(offer["cost"][res_id])
		if have < need:
			return {"ok": false, "reason": "Not enough %s (%s / %s)" % [
				resource_name(str(res_id)), UIStyle.fmt(have), UIStyle.fmt(need)]}
	return {"ok": true, "reason": ""}

## Spend the stores and grant the reward. Validates first, so a shortfall never half-pays.
func trade_offer(offer_id: String) -> Dictionary:
	var offer: Dictionary = DataLoader.trader.get(offer_id, {})
	if offer.is_empty():
		return {"ok": false, "reason": "Unknown offer", "granted": ""}
	var check: Dictionary = can_trade(offer_id)
	if not bool(check["ok"]):
		return {"ok": false, "reason": str(check["reason"]), "granted": ""}
	for res_id in (offer.get("cost", {}) as Dictionary).keys():
		resources[str(res_id)] = float(resources.get(str(res_id), 0.0)) - float(offer["cost"][res_id])
	var granted: Array[String] = []
	for item_id in (offer.get("grant_items", {}) as Dictionary).keys():
		var qty: int = int(offer["grant_items"][item_id])
		BankManager.add_item_guaranteed(str(item_id), qty)
		granted.append("%s ×%d" % [DataLoader.get_item(str(item_id)).get("name", item_id), qty])
	for currency in (offer.get("grant_currency", {}) as Dictionary).keys():
		var amount: float = float(offer["grant_currency"][currency])
		match str(currency):
			"gp":
				PlayerData.add_gp(amount)
				granted.append("%s GP" % UIStyle.fmt(amount))
			"prayer_points":
				PlayerData.add_prayer_points(amount)
				granted.append("%s Devotion points" % UIStyle.fmt(amount))
			"slayer_coins":
				PlayerData.add_slayer_coins(amount)
				granted.append("%s Huntsman coins" % UIStyle.fmt(amount))
	EventBus.notify("Traded: %s" % ", ".join(granted), "success")
	EventBus.state_refreshed.emit()
	return {"ok": true, "reason": "", "granted": ", ".join(granted)}

## Human-readable summary of what an offer gives, for the panel and for goal hints.
func describe_offer(offer: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id in (offer.get("grant_items", {}) as Dictionary).keys():
		parts.append("%s ×%d" % [DataLoader.get_item(str(item_id)).get("name", item_id),
			int(offer["grant_items"][item_id])])
	for currency in (offer.get("grant_currency", {}) as Dictionary).keys():
		parts.append("%s %s" % [UIStyle.fmt(float(offer["grant_currency"][currency])),
			str(currency).replace("_", " ")])
	return ", ".join(parts) if not parts.is_empty() else "Nothing"

func set_worship(god_id: String) -> void:
	worship = god_id
	ModifierManager.unregister("%s:worship" % CATEGORY)
	var eff: Dictionary = DataLoader.game_modes.get("worship_effects", {}).get(god_id, {})
	if not eff.is_empty():
		ModifierManager.register("%s:worship" % CATEGORY, eff, CATEGORY, "Worship: %s" % god_id)

# =========================================================================
#  Persistence
# =========================================================================

func serialize() -> Dictionary:
	return {
		"resources": resources,
		"buildings": buildings,
		"population": population,
		"worship": worship,
		"tick_accumulator": _tick_accumulator,
	}

func deserialize(d: Dictionary) -> void:
	_reset_resources()
	var src: Variant = d.get("resources", {})
	if typeof(src) == TYPE_DICTIONARY:
		for res_id in (src as Dictionary).keys():
			var v: float = float((src as Dictionary)[res_id])
			resources[str(res_id)] = v if is_finite(v) and v >= 0.0 else 0.0
	buildings = {}
	var bid_src: Variant = d.get("buildings", {})
	if typeof(bid_src) == TYPE_DICTIONARY:
		for building_id in (bid_src as Dictionary).keys():
			var level: int = int((bid_src as Dictionary)[building_id])
			if level > 0 and DataLoader.township_buildings.has(str(building_id)):
				buildings[str(building_id)] = mini(level, max_level_of(str(building_id)))
	population = int(productions_population())
	worship = str(d.get("worship", ""))
	var acc: float = float(d.get("tick_accumulator", 0.0))
	_tick_accumulator = clampf(acc, 0.0, SECONDS_PER_TICK) if is_finite(acc) else 0.0
	if worship != "":
		set_worship(worship)
	_reregister_modifiers()

func build_preview(building_id: String) -> Dictionary:
	var cost: Dictionary = scaled_cost(building_id)
	var wait: float = 0
	var bottleneck: String = "none"
	var payoff: float = 0
	var output: Dictionary = buildings_data().get(building_id, {}).get("production", {})
	for id in cost:
		var deficit: float = maxf(0.0, float(cost[id]) - float(resources.get(id, 0)))
		var hours: float = deficit / production_per_hour(str(id)) if production_per_hour(str(id)) > 0 else (INF if deficit > 0 else 0.0)
		if hours > wait: wait = hours; bottleneck = resource_name(str(id))
		if float(output.get(id, 0)) > 0: payoff = maxf(payoff, float(cost[id]) / float(output[id]))
	return {"wait_hours": wait, "bottleneck": bottleneck, "payoff_hours": payoff, "affordable": bool(can_build(building_id).ok)}
