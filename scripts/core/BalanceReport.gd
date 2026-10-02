class_name BalanceReport
extends RefCounted
## BalanceReport — the tuning checks the brief asks for, derived from content only.
##
## Every number here comes from the JSON tables with NO player state and NO modifiers applied, so
## the report describes the shape of the content rather than one character's situation. The rates
## are labelled raw for exactly that reason: a real player's interval, doubling chance and
## preservation move them.
##
## It looks for four classes of problem:
##   * a skill whose last unlock is worse per hour than its first (progression inversion),
##   * an item so many recipes need that it is a single point of failure,
##   * an enemy curve that goes down when it should go up,
##   * a currency economy where sinks cannot absorb sources.
## Anything it cannot answer from data it does not print.
##
## Demand is read through `consumed_item_ids()`, which is the ONE place that knows every way
## content spends an item. Recipes alone are not the whole answer: ammunition is burned by
## weapons, summoning eats tablets, a pen eats stock, Engineering eats devices, Inscription
## eats texts, Enchanting eats essences, Prayer eats bones and the museum eats artefacts. A
## dead output is only dead once every one of those has been consulted.

## Item types that are never expected to be eaten by another recipe: they are worn, drunk,
## eaten, banked as currency, planted or sold. `bone` is NOT here — see `consumed_item_ids`.
const CONSUMED_BY_USE: Array[String] = ["equipment", "food", "potion", "currency", "seed"]

const TOP_BOTTLENECKS: int = 8
const BOTTLENECK_SHARE: int = 12
# A material nothing supplies at all is worse than one with a single route, so it is flagged
# at far lower demand.
const NO_SOURCE_SHARE: int = 3

static func build() -> Dictionary:
	return {
		"rates": _rates(),
		"bottlenecks": _bottlenecks(),
		"combat": _combat_curve(),
		"economy": _economy(),
		"unused": _unused_items(),
	}

## Raw XP and output per hour for the first and last unlock of every non-combat skill.
static func _rates() -> Dictionary:
	var rows: Array = []
	var inversions: Array[String] = []
	for skill_id in DataLoader.get_skill_ids():
		var skill: Dictionary = DataLoader.get_skill(skill_id)
		if str(skill.get("category", "")) == "combat":
			continue
		var actions: Array = DataLoader.get_skill_actions(skill_id)
		if actions.is_empty():
			continue
		var sorted_actions: Array = actions.duplicate()
		sorted_actions.sort_custom(func(a, b):
			return int((a as Dictionary).get("level_required", 1)) < int((b as Dictionary).get("level_required", 1)))
		var first: Dictionary = sorted_actions[0]
		var last: Dictionary = sorted_actions[sorted_actions.size() - 1]
		var first_rate: float = _xp_per_hour(first)
		var last_rate: float = _xp_per_hour(last)
		# A zero XP rate means the skill's own system awards the experience (farming plots,
		# cartography surveys), not that the content is broken. Say so instead of printing 0.
		var system_driven: bool = _xp_per_hour(first) <= 0.0 and _xp_per_hour(last) <= 0.0
		rows.append({
			"skill": str(skill.get("name", skill_id)),
			"system_driven": system_driven,
			"actions": actions.size(),
			"first_level": int(first.get("level_required", 1)),
			"first_name": str(first.get("name", first.get("id", ""))),
			"first_xp_hour": first_rate,
			"last_level": int(last.get("level_required", 1)),
			"last_name": str(last.get("name", last.get("id", ""))),
			"last_xp_hour": last_rate,
		})
		if first_rate > 0.0 and last_rate < first_rate:
			inversions.append("%s: %s gives %.0f XP/h but the level-%d unlock %s gives only %.0f XP/h" % [
				skill.get("name", skill_id), first.get("name", ""), first_rate,
				int(last.get("level_required", 1)), last.get("name", ""), last_rate])
	return {"rows": rows, "inversions": inversions}

static func _xp_per_hour(action: Dictionary) -> float:
	var interval: float = maxf(0.05, float(action.get("base_interval", 3.0)))
	var success: float = clampf(float(action.get("success_chance", 1.0)), 0.0, 1.0)
	return float(action.get("base_xp", 0.0)) * (3600.0 / interval) * success

## Every item content spends, and the reason it spends it: item_id -> ["recipe:forge:smelt", ...].
## This is the single model of demand. The report, the validator's dead-output rule and the test
## suite all read it, so a channel can only go missing in one place.
static func consumed_item_ids() -> Dictionary:
	var used: Dictionary = {}
	for skill_id in DataLoader.skills.keys():
		for action in DataLoader.get_skill_actions(str(skill_id)):
			if typeof(action) != TYPE_DICTIONARY:
				continue
			for item_id in ((action as Dictionary).get("input_items", {}) as Dictionary).keys():
				_mark_used(used, item_id, "recipe:%s:%s" % [skill_id, (action as Dictionary).get("id", "")])
	for item_id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.items[item_id]
		for mat in (it.get("upgrade_materials", {}) as Dictionary).keys():
			_mark_used(used, mat, "upgrade:%s" % item_id)
		# Ammunition and runes are spent per attack, not by a recipe.
		for cost_id in (it.get("attack_cost_items", {}) as Dictionary).keys():
			_mark_used(used, cost_id, "attack:%s" % item_id)
		# A text is spent when it is used from Inscription.
		if str(it.get("scribe_effect", "")) != "":
			_mark_used(used, item_id, "text")
		# A bone is spent for Prayer Points when it is buried.
		if float(it.get("prayer_points", 0)) > 0:
			_mark_used(used, item_id, "bury")
		# A crate is spent when it is opened, whatever it holds.
		if not (it.get("container_items", {}) as Dictionary).is_empty() or str(it.get("container_pet", "")) != "":
			_mark_used(used, item_id, "container")
	for familiar_id in DataLoader.familiars.keys():
		var familiar: Variant = DataLoader.familiars[familiar_id]
		if typeof(familiar) == TYPE_DICTIONARY:
			_mark_used(used, (familiar as Dictionary).get("tablet_item", ""), "familiar:%s" % familiar_id)
	# A pet hatched from an egg spends that egg.
	for pet_id in DataLoader.pets.keys():
		var pet: Variant = DataLoader.pets[pet_id]
		if typeof(pet) == TYPE_DICTIONARY:
			_mark_used(used, (pet as Dictionary).get("source_item", ""), "hatch:%s" % pet_id)
	# Ranching: a pen is stocked with the species' own stock item, and the system also spends
	# feed, the manure byproduct and the two rare breeding variants (RanchingManager literals).
	for species_def in (DataLoader.new_skill_systems.get("species", []) as Array):
		if typeof(species_def) != TYPE_DICTIONARY:
			continue
		_mark_used(used, (species_def as Dictionary).get("stock", ""), "pen:%s" % (species_def as Dictionary).get("id", ""))
	for literal in ["ranch_feed", "ranch_manure", "golden_hen_stock", "mooncalf_stock"]:
		_mark_used(used, literal, "ranching")
	# Farming spends compost and manure on a plot.
	for literal in ["compost", "ranch_manure"]:
		_mark_used(used, literal, "farming")
	# Engineering installs a device, which spends the device item.
	for device_def in (DataLoader.new_skill_systems.get("devices", []) as Array):
		if typeof(device_def) == TYPE_DICTIONARY:
			_mark_used(used, (device_def as Dictionary).get("id", ""), "device")
	# Enchanting rebuilds an enchant cost per essence family, and adds a catalyst from tier 4 up.
	for enchant_def in (DataLoader.new_skill_systems.get("enchants", []) as Array):
		if typeof(enchant_def) != TYPE_DICTIONARY:
			continue
		var essence: String = str((enchant_def as Dictionary).get("essence", ""))
		if essence != "":
			_mark_used(used, "enchant_%s_essence" % essence, "enchant")
		if int((enchant_def as Dictionary).get("tier", 1)) >= 4:
			_mark_used(used, "enchant_catalyst", "enchant:tier4+")
	# The museum keeps the four graded artefacts by name; donating them spends them.
	for artefact_id in ArchaeologyManager.DONATE_GP.keys():
		_mark_used(used, artefact_id, "museum")
	# The Dream Bazaar is priced in dream essence, which is an item: a currency, so the dead-output
	# rule skips it by type, but still a spend with a source of its own.
	for offer in (DataLoader.new_skill_systems.get("bazaar", []) as Array):
		if typeof(offer) == TYPE_DICTIONARY and int((offer as Dictionary).get("cost", 0)) > 0:
			_mark_used(used, "dream_essence", "bazaar:%s" % str((offer as Dictionary).get("id", "")))
	# The settlement trader is paid from the township store, not from Storage: its cost keys are
	# resource ids (`data/trader.json`, `TownshipManager.ALL_RESOURCES`). Reading them as items
	# invented demand for "goods", which then had demand, no route and no existence. Only an offer
	# that costs a real item counts, and none does today.
	for offer_id in DataLoader.trader.keys():
		var offer: Variant = DataLoader.trader[offer_id]
		if typeof(offer) != TYPE_DICTIONARY:
			continue
		for cost_id in ((offer as Dictionary).get("cost", {}) as Dictionary).keys():
			if DataLoader.items.has(str(cost_id)):
				_mark_used(used, cost_id, "trader:%s" % offer_id)
	return used

static func _mark_used(used: Dictionary, item_id: Variant, reason: String) -> void:
	var key: String = str(item_id)
	if key == "":
		return
	var bucket: Array = used.get(key, [])
	bucket.append(reason)
	used[key] = bucket

## Every channel `consumed_item_ids()` models, by the prefix its reasons carry. A channel that
## matches nothing means a field was renamed or dropped, which would silently excuse dead
## content — so the test suite asserts each one is still live.
const DEMAND_CHANNELS: Array[String] = ["recipe", "upgrade", "attack", "text", "bury",
	"container", "familiar", "hatch", "pen", "ranching", "farming", "device", "enchant",
	"museum", "bazaar"]

## One independent source of a material, counted by kind. Two recipes that make the same material
## are two ways to keep it coming; twenty monsters that drop it are twenty, not one. Counting
## kinds instead would call a boss catalyst that twenty enemies carry a "single point of failure".
static func _add_source(sources: Dictionary, item_id: Variant, kind: String) -> void:
	var key: String = str(item_id)
	if key == "":
		return
	var kinds: Dictionary = sources.get(key, {})
	kinds[kind] = int(kinds.get(kind, 0)) + 1
	sources[key] = kinds

## Every material the economy spends, with how much demand it carries and how many independent
## sources supply it. One model, so the report's risk list and the validator's warning cannot
## disagree about what a bottleneck is. A source is a way to obtain the material: one per recipe
## that makes it, one per shop that sells it, one per enemy that drops it, and one per system
## that hands it over without an action naming it (farming, ranching, inscription, enchanting).
static func demand_rows() -> Array:
	var used_by: Dictionary = consumed_item_ids()
	var produced_by: Dictionary = {}
	var sources: Dictionary = {}
	for skill_id in DataLoader.skills.keys():
		for action in DataLoader.get_skill_actions(str(skill_id)):
			if typeof(action) != TYPE_DICTIONARY:
				continue
			var act: Dictionary = action
			var made: Array[String] = []
			for item_id in (act.get("output_items", {}) as Dictionary).keys():
				made.append(str(item_id))
			# A secondary output is an acquisition route too — without this the report calls a
			# material unproduced when a gathering action drops it regularly.
			for secondary in (act.get("secondary_outputs", []) as Array):
				if typeof(secondary) == TYPE_DICTIONARY:
					var sec_id: String = str((secondary as Dictionary).get("item_id", ""))
					if sec_id != "":
						made.append(sec_id)
			# Each producing action is its own source: two recipes that make the same material are
			# two ways to keep it coming, whether or not they share a skill.
			for item_id in made:
				produced_by[item_id] = int(produced_by.get(item_id, 0)) + 1
				_add_source(sources, item_id, "crafted:%s" % str(skill_id))
	for item_id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.items[item_id]
		if str(it.get("upgrade_path", "")) != "":
			_add_source(sources, it["upgrade_path"], "loot")
	for monster_id in DataLoader.monsters.keys():
		for drop in (DataLoader.monsters[monster_id].get("loot_table", []) as Array):
			if typeof(drop) == TYPE_DICTIONARY and not bool((drop as Dictionary).get("is_currency", false)):
				_add_source(sources, (drop as Dictionary).get("item_id", ""), "loot")
	for dungeon_id in DataLoader.dungeons.keys():
		var dungeon: Dictionary = DataLoader.dungeons[dungeon_id]
		_add_source(sources, dungeon.get("shard_item", ""), "loot")
		for bundle in [dungeon.get("completion_reward", {}), dungeon.get("rewards_first_clear", {})]:
			for item_id in ((bundle as Dictionary).get("items", {}) as Dictionary).keys():
				_add_source(sources, item_id, "loot")
	# The General Store, the slayer shop and the settlement trader all sell for something the
	# player can grind, so they are one kind of route: buyable.
	for stock_id in DataLoader.shop_store.keys():
		var stock: Variant = DataLoader.shop_store[stock_id]
		if typeof(stock) == TYPE_DICTIONARY and str((stock as Dictionary).get("item_id", "")) != "":
			_add_source(sources, (stock as Dictionary).get("item_id"), "store")
	for offer_id in DataLoader.trader.keys():
		if typeof(DataLoader.trader[offer_id]) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = DataLoader.trader[offer_id]
		_add_source(sources, offer.get("item_id", ""), "store")
		for item_id in (offer.get("grant_items", {}) as Dictionary).keys():
			_add_source(sources, item_id, "store")
	for item_id in DataLoader.items.keys():
		if int(DataLoader.items[item_id].get("slayer_cost", 0)) > 0:
			_add_source(sources, item_id, "store")
	# The four systems the validator already trusts as acquisition paths: a crop, a pen, a
	# scribe's graded copy, a disenchanted essence. A material only they supply has a real
	# source, and calling it unsourced would be a lie about the game.
	for item_id in DataLoader.items.keys():
		var seed_item: Dictionary = DataLoader.items[item_id]
		if str(seed_item.get("item_type", "")) == "seed":
			_add_source(sources, seed_item.get("product_item", ""), "farmed")
	for species_def in (DataLoader.new_skill_systems.get("species", []) as Array):
		if typeof(species_def) != TYPE_DICTIONARY:
			continue
		var animal: Dictionary = species_def
		for field in ["stock", "produce", "hide", "feed"]:
			_add_source(sources, animal.get(field, ""), "ranched")
		if int(animal.get("meat", 0)) > 0:
			_add_source(sources, "ranch_meat", "ranched")
	for system_item in ["ranch_feed", "ranch_manure", "golden_hen_stock", "mooncalf_stock"]:
		if DataLoader.items.has(system_item):
			_add_source(sources, system_item, "ranched")
	for enchant_def in (DataLoader.new_skill_systems.get("enchants", []) as Array):
		if typeof(enchant_def) != TYPE_DICTIONARY:
			continue
		var essence: String = str((enchant_def as Dictionary).get("essence", ""))
		if essence != "" and DataLoader.items.has("enchant_%s_essence" % essence):
			_add_source(sources, "enchant_%s_essence" % essence, "enchanted")
	for skill_id in DataLoader.skills.keys():
		for action in DataLoader.get_skill_actions(str(skill_id)):
			if typeof(action) != TYPE_DICTIONARY:
				continue
			var act2: Dictionary = action
			var quality_product: String = str(act2.get("quality_product", ""))
			if quality_product != "":
				for quality in ["inked", "faded", "illuminated"]:
					_add_source(sources, "%s_%s" % [quality_product, quality], "scribed")
			# A failed action that names a failure output produces that output: burnt food is content.
			_add_source(sources, act2.get("fail_output_item", ""), "fail")
	# The rest of the places an item can come from, mirroring the validator's acquisition model:
	# the Dream Bazaar, quests, achievements, dig sites, raid rewards, the museum's curios and the
	# mastery stall. A material supplied only by one of these has a source — this is the list that
	# made "Scribe Paper has one source" wrong while the bazaar was selling fifty sheets of it.
	for offer in (DataLoader.new_skill_systems.get("bazaar", []) as Array):
		if typeof(offer) == TYPE_DICTIONARY:
			for item_id in ((offer as Dictionary).get("items", {}) as Dictionary).keys():
				_add_source(sources, item_id, "bazaar")
	for quest_id in Quests.all_quest_ids():
		var quest_reward: Dictionary = Quests.get_quest(quest_id).get("reward", {})
		for field in ["items", "unlock_items"]:
			for item_id in (quest_reward.get(field, {}) as Dictionary).keys():
				_add_source(sources, item_id, "quest")
	for achievement_id in Achievements.all_ids():
		var earned: Dictionary = Achievements.get_record(achievement_id).get("reward", {})
		for item_id in (earned.get("items", {}) as Dictionary).keys():
			_add_source(sources, item_id, "achievement")
	for site_id in DataLoader.archaeology_sites.keys():
		for artefact in (DataLoader.archaeology_sites[site_id].get("artefacts", []) as Array):
			if typeof(artefact) == TYPE_DICTIONARY:
				_add_source(sources, (artefact as Dictionary).get("item_id", ""), "dig")
	for item_id in (DataLoader.raid_shop.get("alt_items", []) as Array):
		_add_source(sources, item_id, "raid")
	for curio_id in DataLoader.shop_museum.keys():
		var curio: Variant = DataLoader.shop_museum[curio_id]
		if typeof(curio) != TYPE_DICTIONARY:
			continue
		for item_id in ((curio as Dictionary).get("grant_items", {}) as Dictionary).keys():
			_add_source(sources, item_id, "store")
	for item_id in ShopManager.stall_item_ids():
		_add_source(sources, item_id, "store")
	for familiar_id in DataLoader.familiars.keys():
		_add_source(sources, (DataLoader.familiars[familiar_id] as Dictionary).get("mark_item", ""), "familiar")
	# The dream journeys pay essence every hour they run, and the bazaar above is where it goes.
	for dream_def in (DataLoader.new_skill_systems.get("dreams", []) as Array):
		if typeof(dream_def) == TYPE_DICTIONARY and float((dream_def as Dictionary).get("essence_hour", 0)) > 0.0:
			_add_source(sources, "dream_essence", "dreams")
			break
	var rows: Array = []
	# Every item, not only the demanded ones: a supply-only item — a skillcape from the mastery
	# stall, the burnt food a failed cook leaves behind — still has sources, and they are the half
	# of the model the demand channels cannot see.
	for item_id in DataLoader.items.keys():
		var kinds: Dictionary = sources.get(str(item_id), {})
		var names: Array[String] = []
		for kind in kinds.keys():
			names.append(str(kind))
		names.sort()
		var parts: Array[String] = []
		var total: int = 0
		for kind in names:
			var count: int = int(kinds[kind])
			total += count
			parts.append(kind if count == 1 else "%s x%d" % [kind, count])
		rows.append({
			"item_id": str(item_id),
			"recipes": (used_by.get(str(item_id), []) as Array).size(),
			"producers": int(produced_by.get(str(item_id), 0)),
			"sources": total,
			"routes": " + ".join(parts),
			"has_source": total > 0,
		})
	rows.sort_custom(func(a, b): return int((a as Dictionary)["recipes"]) > int((b as Dictionary)["recipes"]))
	return rows

## Supply concentration: a material many recipes need that at most one route supplies. The
## deliberate ones carry `bottleneck_reason` on the item, exactly as `terminal_reason` declares a
## deliberate dead end, so the warnings left over are the ones still worth acting on.
static func concentrated_materials() -> Dictionary:
	return _concentrate(demand_rows())

static func _concentrate(rows: Array) -> Dictionary:
	var concentrated: Array = []
	var declared: Array[String] = []
	var undeclared: Array[String] = []
	var stale: Array[String] = []
	for entry in rows:
		var row: Dictionary = entry
		var item_id: String = str(row["item_id"])
		var demand: int = int(row["recipes"])
		var source_count: int = int(row["sources"])
		var shape: String = ""
		if source_count == 0 and demand >= NO_SOURCE_SHARE:
			shape = "no_source"
		elif source_count <= 1 and demand >= BOTTLENECK_SHARE:
			shape = "single_source"
		var reason: String = str(DataLoader.get_item(item_id).get("bottleneck_reason", ""))
		if shape == "":
			# A declaration that no longer describes the content is noise: the material gained a
			# second route, or its demand fell below the line.
			if reason != "":
				stale.append(item_id)
			continue
		row["shape"] = shape
		row["reason"] = reason
		concentrated.append(row)
		if reason == "":
			undeclared.append(item_id)
		else:
			declared.append(item_id)
	declared.sort()
	undeclared.sort()
	stale.sort()
	return {"rows": concentrated, "declared": declared, "undeclared": undeclared,
		"stale_declarations": stale}

## Kept as the report's `bottlenecks` section. The risk list is every concentrated material, not
## just the eight shown, because a hub ranked ninth still strands just as many recipes.
static func _bottlenecks() -> Dictionary:
	var rows: Array = demand_rows()
	var concentration: Dictionary = _concentrate(rows)
	var warnings: Array[String] = []
	for entry in (concentration["rows"] as Array):
		var e: Dictionary = entry
		if str(e["reason"]) != "":
			continue
		var shown: String = str(DataLoader.get_item(str(e["item_id"])).get("name", e["item_id"]))
		if str(e["shape"]) == "no_source":
			warnings.append("%s is needed by %d recipes and nothing supplies it" %
				[shown, int(e["recipes"])])
		else:
			warnings.append("%s is needed by %d recipes from one source (%s) — a single point of failure" %
				[shown, int(e["recipes"]), str(e["routes"])])
	for item_id in (concentration["stale_declarations"] as Array):
		warnings.append("%s declares bottleneck_reason but is no longer concentrated" %
			str(DataLoader.get_item(str(item_id)).get("name", item_id)))
	return {"top": rows.slice(0, TOP_BOTTLENECKS), "warnings": warnings,
		"concentrated": concentration}

## Materials that nothing consumes. An item may only be here if it is genuinely dead, so a
## declaration (`terminal_reason`) is the documented way to say "this one is on purpose".
## Equipment, food, potions, currency and seeds are worn, eaten, drunk, banked or planted
## rather than consumed, so they are out of scope by type.
static func dead_outputs() -> Dictionary:
	var used: Dictionary = consumed_item_ids()
	var undeclared: Array[String] = []
	var declared: Array[String] = []
	var stale: Array[String] = []
	for item_id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.items[item_id]
		var reason: String = str(it.get("terminal_reason", ""))
		var is_used: bool = used.has(str(item_id))
		if is_used and reason != "":
			stale.append(str(item_id))
		if is_used or str(it.get("item_type", "")) in CONSUMED_BY_USE:
			continue
		if reason == "":
			undeclared.append(str(item_id))
		else:
			declared.append(str(item_id))
	undeclared.sort()
	declared.sort()
	stale.sort()
	return {"undeclared": undeclared, "declared": declared, "stale_declarations": stale}

## Enemy progression, area by area: a curve that dips is a curve that lies about difficulty.
static func _combat_curve() -> Dictionary:
	# One row per enemy: an enemy that appears in four dungeons is one data point, not four.
	var by_monster: Dictionary = {}
	var order: Array[String] = []
	for area_id in DataLoader.areas.keys():
		var area: Dictionary = DataLoader.areas[area_id]
		for monster_id in (area.get("monsters", []) as Array):
			_add_place(by_monster, order, str(monster_id), str(area.get("name", area_id)))
	for dungeon_id in DataLoader.dungeons.keys():
		var dungeon: Dictionary = DataLoader.dungeons[dungeon_id]
		for monster_id in (dungeon.get("monsters", []) as Array):
			_add_place(by_monster, order, str(monster_id), str(dungeon.get("name", dungeon_id)))
	var rows: Array = []
	for monster_id in order:
		rows.append(by_monster[monster_id])
	rows.sort_custom(func(a, b): return int((a as Dictionary)["level"]) < int((b as Dictionary)["level"]))
	var warnings: Array[String] = []
	var previous: Dictionary = {}
	for row in rows:
		var r: Dictionary = row
		# A boss is meant to spike above its neighbours, so only non-bosses are compared with each
		# other: the dip back down after a boss is intentional, not a curve that lies about
		# difficulty.
		if not bool(r["boss"]):
			if not previous.is_empty() and int(r["level"]) > int(previous["level"]) and float(r["hp"]) < float(previous["hp"]):
				warnings.append("level %d %s has less health (%d) than level %d %s (%d)" % [
					int(r["level"]), r["name"], int(r["hp"]), int(previous["level"]), previous["name"], int(previous["hp"])])
			previous = r
	return {"rows": rows, "warnings": warnings}

static func _add_place(by_monster: Dictionary, order: Array[String], monster_id: String, place: String) -> void:
	if by_monster.has(monster_id):
		var places: Array = (by_monster[monster_id] as Dictionary)["places"]
		if not places.has(place):
			places.append(place)
		return
	var row: Dictionary = _monster_row(monster_id)
	row["places"] = [place] if place != "" else []
	by_monster[monster_id] = row
	order.append(monster_id)

static func _monster_row(monster_id: String) -> Dictionary:
	var m: Dictionary = DataLoader.get_monster(monster_id)
	return {
		"id": monster_id,
		"name": str(m.get("name", monster_id)),
		"level": int(m.get("combat_level", 1)),
		"hp": float(m.get("hitpoints", 1)),
		"max_hit": float(m.get("max_hit", 0)),
		"dr": float(m.get("damage_reduction", 0)),
		"boss": bool(m.get("is_boss", false)),
	}

## Sources versus sinks. Both sides are sums over the content tables, so the ratio says whether
## gold can accumulate faster than the game can absorb it.
static func _economy() -> Dictionary:
	var loot_gp: float = 0.0
	for monster_id in DataLoader.monsters.keys():
		for drop in (DataLoader.monsters[monster_id].get("loot_table", []) as Array):
			if typeof(drop) != TYPE_DICTIONARY:
				continue
			if bool((drop as Dictionary).get("is_currency", false)) and str((drop as Dictionary).get("currency_id", "gp")) == "gp":
				loot_gp += float((drop as Dictionary).get("quantity", 0)) * float((drop as Dictionary).get("chance", 1.0))
	var quest_gp: float = 0.0
	for quest_id in Quests.all_quest_ids():
		quest_gp += float((Quests.get_quest(quest_id).get("reward", {}) as Dictionary).get("gp", 0))
	var dungeon_gp: float = 0.0
	for dungeon_id in DataLoader.dungeons.keys():
		var d: Dictionary = DataLoader.dungeons[dungeon_id]
		dungeon_gp += float((d.get("completion_reward", {}) as Dictionary).get("gp", 0))
		dungeon_gp += float((d.get("rewards_first_clear", {}) as Dictionary).get("gp", 0))
	var shop_gp: float = 0.0
	for upgrade_id in DataLoader.shop.keys():
		shop_gp += float(DataLoader.shop[upgrade_id].get("cost", 0))
	var stall_gp: float = 0.0
	for offer in ShopManager.stall_offers():
		stall_gp += float((offer as Dictionary)["cost"])
	var township_gp: float = 0.0
	for building_id in DataLoader.township_buildings.keys():
		township_gp += float(DataLoader.township_buildings[building_id].get("base_cost", 0))
	var warnings: Array[String] = []
	if shop_gp + stall_gp <= 0.0:
		warnings.append("gold has no catalogue to spend on")
	return {
		"sources": {"monster_loot": loot_gp, "tasks": quest_gp, "expeditions": dungeon_gp},
		"sinks": {"provisioner": shop_gp, "mastery_stall": stall_gp, "settlement": township_gp},
		"source_total": loot_gp + quest_gp + dungeon_gp,
		"sink_total": shop_gp + stall_gp + township_gp,
		"warnings": warnings,
	}

## Kept as the report's `unused` key. The work moved into `dead_outputs()`, which separates a
## genuinely dead output from one the data declares terminal, and flags a declaration that a
## later recipe quietly made false.
static func _unused_items() -> Dictionary:
	return dead_outputs()

# =========================================================================
#  Formatting
# =========================================================================

static func format_text() -> Array[String]:
	var report: Dictionary = build()
	var lines: Array[String] = ["=== balance report (content only, no modifiers applied) ==="]
	lines.append("")
	lines.append("--- raw rates per skill (first vs last unlock) ---")
	for row in (report["rates"] as Dictionary)["rows"]:
		if bool((row as Dictionary)["system_driven"]):
			lines.append("  %-16s %2d actions | XP is awarded by the skill's own system" % [
				str((row as Dictionary)["skill"]), int((row as Dictionary)["actions"])])
			continue
		lines.append("  %-16s %2d actions | L%-3d %-22s %9.0f XP/h | L%-3d %-22s %9.0f XP/h" % [
			str((row as Dictionary)["skill"]), int((row as Dictionary)["actions"]),
			int((row as Dictionary)["first_level"]), str((row as Dictionary)["first_name"]),
			float((row as Dictionary)["first_xp_hour"]),
			int((row as Dictionary)["last_level"]), str((row as Dictionary)["last_name"]),
			float((row as Dictionary)["last_xp_hour"])])
	for note in (report["rates"] as Dictionary)["inversions"]:
		lines.append("  WARN progression inversion: %s" % str(note))
	lines.append("")
	lines.append("--- most demanded materials ---")
	for entry in (report["bottlenecks"] as Dictionary)["top"]:
		var e: Dictionary = entry
		# "0 producers" alone reads like a bug, and a single source is the risk the warnings are
		# about; in both cases say what actually supplies it.
		var source_note: String = ""
		if int(e["producers"]) == 0 or int(e["sources"]) <= 1:
			source_note = (", %s" % str(e["routes"])) if bool(e["has_source"]) else ", NO SOURCE"
		lines.append("  %-24s in %2d recipes (%d producers%s)" % [
			str(DataLoader.get_item(str(e["item_id"])).get("name", e["item_id"])),
			int(e["recipes"]), int(e["producers"]), source_note])
	for note in (report["bottlenecks"] as Dictionary)["warnings"]:
		lines.append("  WARN %s" % str(note))
	var hubs: Array = ((report["bottlenecks"] as Dictionary)["concentrated"] as Dictionary)["rows"]
	for entry in hubs:
		var hub: Dictionary = entry
		# Declared concentration is a decision, not a risk: printed with its reason so a reader can
		# tell it apart from the warnings above it.
		if str(hub["reason"]) == "":
			continue
		lines.append("  declared %s is deliberately one source (%s, %d recipes) — %s" % [
			str(DataLoader.get_item(str(hub["item_id"])).get("name", hub["item_id"])),
			str(hub["routes"]), int(hub["recipes"]), str(hub["reason"])])
	lines.append("")
	lines.append("--- enemy curve ---")
	for row in (report["combat"] as Dictionary)["rows"]:
		var places: Array = (row as Dictionary).get("places", [])
		lines.append("  L%-4d %-26s %-28s hp %6d  max hit %5d  dr %3d%s" % [
			int((row as Dictionary)["level"]), str((row as Dictionary)["name"]),
			str(places[0]) if not places.is_empty() else "-", int((row as Dictionary)["hp"]),
			int((row as Dictionary)["max_hit"]), int((row as Dictionary)["dr"]),
			"  [boss]" if bool((row as Dictionary)["boss"]) else ""])
	for note in (report["combat"] as Dictionary)["warnings"]:
		lines.append("  WARN %s" % str(note))
	lines.append("")
	var economy: Dictionary = report["economy"]
	lines.append("--- currency ---")
	lines.append("  sources (per full clear of everything): %s GP" % _fmt(float(economy["source_total"])))
	for key in (economy["sources"] as Dictionary).keys():
		lines.append("    %-16s %s" % [str(key), _fmt(float((economy["sources"] as Dictionary)[key]))])
	lines.append("  sinks (one-off purchases): %s GP" % _fmt(float(economy["sink_total"])))
	for key in (economy["sinks"] as Dictionary).keys():
		lines.append("    %-16s %s" % [str(key), _fmt(float((economy["sinks"] as Dictionary)[key]))])
	if float(economy["sink_total"]) > 0.0:
		lines.append("  source:sink ratio %.2f" % (float(economy["source_total"]) / float(economy["sink_total"])))
	for note in (economy["warnings"] as Array):
		lines.append("  WARN %s" % str(note))
	lines.append("")
	var unused: Dictionary = report["unused"]
	var undeclared: Array = unused["undeclared"]
	var declared: Array = unused["declared"]
	lines.append("--- materials nothing consumes: %d undeclared, %d declared terminal ---" % [
		undeclared.size(), declared.size()])
	if undeclared.size() > 0:
		lines.append("  " + ", ".join(undeclared))
	if not declared.is_empty():
		# Declared terminals are content, not bugs: say why each one is allowed to be dead.
		for item_id in declared:
			lines.append("  terminal %-24s %s" % [str(item_id),
				str(DataLoader.get_item(str(item_id)).get("terminal_reason", ""))])
	for item_id in (unused["stale_declarations"] as Array):
		lines.append("  WARN %s declares terminal_reason but is consumed by content" % str(item_id))
	lines.append("")
	lines.append("Note: rates are raw data with no modifiers, no doubling and no downtime. They " +
		"compare content to content; they are not a prediction of a session.")
	return lines

static func _fmt(v: float) -> String:
	if absf(v) >= 1_000_000_000.0:
		return "%.2fB" % (v / 1_000_000_000.0)
	if absf(v) >= 1_000_000.0:
		return "%.2fM" % (v / 1_000_000.0)
	if absf(v) >= 1_000.0:
		return "%.1fK" % (v / 1_000.0)
	return "%.0f" % v
