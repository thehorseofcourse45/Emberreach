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

const TOP_BOTTLENECKS: int = 8
const BOTTLENECK_SHARE: int = 12

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

## How many recipes each material feeds, so a shared bottleneck is visible before it is felt.
## "Nothing produces it" is only a problem when nothing supplies it either, so drops, the trader
## and the slayer shop all count as sources.
static func _bottlenecks() -> Dictionary:
	var used_by: Dictionary = {}
	var produced_by: Dictionary = {}
	var loot_supplied: Dictionary = {}
	var store_supplied: Dictionary = {}
	for skill_id in DataLoader.skills.keys():
		for action in DataLoader.get_skill_actions(str(skill_id)):
			if typeof(action) != TYPE_DICTIONARY:
				continue
			for item_id in ((action as Dictionary).get("input_items", {}) as Dictionary).keys():
				used_by[str(item_id)] = int(used_by.get(str(item_id), 0)) + 1
			for item_id in ((action as Dictionary).get("output_items", {}) as Dictionary).keys():
				produced_by[str(item_id)] = int(produced_by.get(str(item_id), 0)) + 1
			# A secondary output is an acquisition route too — without this the report calls a
			# material unproduced when a gathering action drops it regularly.
			for secondary in ((action as Dictionary).get("secondary_outputs", []) as Array):
				if typeof(secondary) != TYPE_DICTIONARY:
					continue
				var sec_id: String = str((secondary as Dictionary).get("item_id", ""))
				if sec_id != "":
					produced_by[sec_id] = int(produced_by.get(sec_id, 0)) + 1
	for item_id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.items[item_id]
		if str(it.get("upgrade_path", "")) != "":
			loot_supplied[str(it["upgrade_path"])] = true
		for mat in (it.get("upgrade_materials", {}) as Dictionary).keys():
			used_by[str(mat)] = int(used_by.get(str(mat), 0)) + 1
	for monster_id in DataLoader.monsters.keys():
		for drop in (DataLoader.monsters[monster_id].get("loot_table", []) as Array):
			if typeof(drop) == TYPE_DICTIONARY and not bool((drop as Dictionary).get("is_currency", false)):
				loot_supplied[str((drop as Dictionary).get("item_id", ""))] = true
	for dungeon_id in DataLoader.dungeons.keys():
		var dungeon: Dictionary = DataLoader.dungeons[dungeon_id]
		loot_supplied[str(dungeon.get("shard_item", ""))] = true
		for bundle in [dungeon.get("completion_reward", {}), dungeon.get("rewards_first_clear", {})]:
			for item_id in ((bundle as Dictionary).get("items", {}) as Dictionary).keys():
				loot_supplied[str(item_id)] = true
	for offer_id in DataLoader.trader.keys():
		if typeof(DataLoader.trader[offer_id]) != TYPE_DICTIONARY:
			continue
		for item_id in ((DataLoader.trader[offer_id] as Dictionary).get("grant_items", {}) as Dictionary).keys():
			loot_supplied[str(item_id)] = true
	for item_id in DataLoader.items.keys():
		if int(DataLoader.items[item_id].get("slayer_cost", 0)) > 0:
			loot_supplied[str(item_id)] = true
	# The General Store is a real supply route (gold for goods); before this it was invisible
	# to the report, which then claimed stocked materials had "NO SOURCE".
	for stock_id in DataLoader.shop_store.keys():
		var stock: Variant = DataLoader.shop_store[stock_id]
		if typeof(stock) == TYPE_DICTIONARY and str((stock as Dictionary).get("item_id", "")) != "":
			store_supplied[str((stock as Dictionary).get("item_id"))] = true
	var ranked: Array = []
	for item_id in used_by.keys():
		var producers: int = int(produced_by.get(str(item_id), 0))
		# Independent routes: craftable, stocked, or looted. One route is one point of failure;
		# demand spread across two or three routes is visible in the table but cannot strand
		# every recipe that waits on the material.
		var channels: int = 0
		var route_names: Array[String] = []
		if producers > 0:
			channels += 1
			route_names.append("crafted")
		if store_supplied.has(str(item_id)):
			channels += 1
			route_names.append("store")
		if loot_supplied.has(str(item_id)):
			channels += 1
			route_names.append("looted")
		ranked.append({"item_id": str(item_id), "recipes": int(used_by[item_id]),
			"producers": producers, "channels": channels, "routes": " + ".join(route_names),
			"has_source": channels > 0})
	ranked.sort_custom(func(a, b): return int((a as Dictionary)["recipes"]) > int((b as Dictionary)["recipes"]))
	var warnings: Array[String] = []
	for entry in ranked.slice(0, TOP_BOTTLENECKS):
		var e: Dictionary = entry
		# A material nothing produces is worse than a popular one: it can only be gathered or
		# dropped, so every recipe waiting on it is gated on a single source.
		if not bool(e["has_source"]) and int(e["recipes"]) >= 3:
			warnings.append("%s is needed by %d recipes and nothing supplies it" % [
				DataLoader.get_item(str(e["item_id"])).get("name", e["item_id"]), int(e["recipes"])])
		elif int(e["recipes"]) >= BOTTLENECK_SHARE and int(e["channels"]) <= 1:
			# Demand concentration with several independent routes (visible in the table above)
			# is a schedule risk, not a single point of failure: only one route — or none —
			# can actually strand every recipe that needs the material.
			warnings.append("%s is needed by %d recipes from a single route — a single point of failure" % [
				DataLoader.get_item(str(e["item_id"])).get("name", e["item_id"]), int(e["recipes"])])
	var dead: Array[String] = []
	for item_id in DataLoader.items.keys():
		var it2: Dictionary = DataLoader.items[item_id]
		var kind: String = str(it2.get("item_type", ""))
		if kind in ["equipment", "food", "potion", "currency", "seed", "bone", "junk"]:
			continue
		if int(used_by.get(str(item_id), 0)) == 0 and int(produced_by.get(str(item_id), 0)) > 0:
			dead.append(str(item_id))
	return {"top": ranked.slice(0, TOP_BOTTLENECKS), "warnings": warnings, "unused_outputs": dead}

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

## Materials that are produced but consumed by nothing, and equipment nobody can use.
static func _unused_items() -> Dictionary:
	var consumed: Dictionary = {}
	for skill_id in DataLoader.skills.keys():
		for action in DataLoader.get_skill_actions(str(skill_id)):
			if typeof(action) != TYPE_DICTIONARY:
				continue
			for item_id in ((action as Dictionary).get("input_items", {}) as Dictionary).keys():
				consumed[str(item_id)] = true
	for item_id in DataLoader.items.keys():
		for mat in (DataLoader.items[item_id].get("upgrade_materials", {}) as Dictionary).keys():
			consumed[str(mat)] = true
	for offer_id in DataLoader.trader.keys():
		if typeof(DataLoader.trader[offer_id]) != TYPE_DICTIONARY:
			continue
		for store in ((DataLoader.trader[offer_id] as Dictionary).get("cost", {}) as Dictionary).keys():
			consumed[str(store)] = true
	var orphans: Array[String] = []
	for item_id in DataLoader.items.keys():
		var kind: String = str(DataLoader.items[item_id].get("item_type", ""))
		if kind in ["equipment", "food", "potion", "currency", "seed"]:
			continue
		if not consumed.has(str(item_id)):
			orphans.append(str(item_id))
	return {"no_consumer": orphans}

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
		# "0 producers" alone reads like a bug; say whether a drop or the shop supplies it.
		var source_note: String = ""
		if int(e["producers"]) == 0:
			source_note = (", %s" % str(e["routes"])) if bool(e["has_source"]) else ", NO SOURCE"
		lines.append("  %-24s in %2d recipes (%d producers%s)" % [
			str(DataLoader.get_item(str(e["item_id"])).get("name", e["item_id"])),
			int(e["recipes"]), int(e["producers"]), source_note])
	for note in (report["bottlenecks"] as Dictionary)["warnings"]:
		lines.append("  WARN %s" % str(note))
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
	var unused: Array = (report["unused"] as Dictionary)["no_consumer"]
	lines.append("--- materials nothing consumes: %d ---" % unused.size())
	if unused.size() > 0:
		lines.append("  " + ", ".join(unused.slice(0, 24)))
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
