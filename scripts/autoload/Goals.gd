extends Node
## Goals — persistent goal tracking with real dependency resolution.
##
## A goal is a small tuple: {kind, id}. Supported kinds:
##   "item"     — own N of an item
##   "recipe"   — perform a skill action/recipe (id = "skill:action")
##   "skill"    — reach a skill level (extra: level)
##   "quest"    — complete a quest (id = quest id)
##   "building" — construct a settlement structure
##   "upgrade"  — buy a shop upgrade
##
## resolve() answers the questions the brief demands of every screen:
##   What do I need?  ·  What am I missing?  ·  Where do I get it?  ·  What unlocks it?
##
## Every answer is derived from live DataLoader content plus live player state, so a pinned
## goal can never show invented numbers. Circular recipe dependencies are detected and
## reported instead of recursing forever.

const MAX_DEPTH: int = 6
const MAX_SOURCES_PER_ITEM: int = 4

signal goals_updated()

## Array of {kind: String, id: String, level: int}
var pinned: Array = []

# ---------------- pin / unpin ----------------

func pin(kind: String, id: String, level: int = 0) -> bool:
	var key: String = _key(kind, id)
	for g in pinned:
		if _key(g["kind"], g["id"]) == key and int(g.get("level", 0)) == level:
			return false
	if pinned.size() >= 12:
		EventBus.notify("Goal list is full — unpin something first.", "warn")
		return false
	pinned.append({"kind": kind, "id": id, "level": level})
	_emit()
	return true

func unpin(kind: String, id: String) -> bool:
	var before: int = pinned.size()
	pinned = pinned.filter(func(g): return not (g["kind"] == kind and g["id"] == id))
	if pinned.size() != before:
		_emit()
		return true
	return false

func is_pinned(kind: String, id: String) -> bool:
	for g in pinned:
		if g["kind"] == kind and g["id"] == id:
			return true
	return false

func toggle(kind: String, id: String, level: int = 0) -> bool:
	if is_pinned(kind, id):
		unpin(kind, id)
		return false
	pin(kind, id, level)
	return true

func clear() -> void:
	pinned.clear()
	_emit()

func _key(kind: String, id: String) -> String:
	return "%s:%s" % [kind, id]

func _emit() -> void:
	EventBus.goal_changed.emit()
	goals_updated.emit()

# ---------------- resolution ----------------

## Resolve one goal into a fully explained plan. Never throws; returns ok=false with a
## "problem" field when the goal cannot be evaluated.
func resolve(goal: Dictionary) -> Dictionary:
	var kind: String = str(goal.get("kind", ""))
	var id: String = str(goal.get("id", ""))
	match kind:
		"item":
			return _resolve_item(id, int(goal.get("level", 0)))
		"recipe":
			return _resolve_recipe(id)
		"skill":
			return _resolve_skill(id, int(goal.get("level", 1)))
		"quest":
			return Quests.describe_for_goal(id)
		"building":
			return _resolve_building(id)
		"upgrade":
			return _resolve_upgrade(id)
	return {"ok": false, "problem": "Unknown goal kind '%s'" % kind, "kind": kind, "id": id}

func resolve_all() -> Array:
	var out: Array = []
	for g in pinned:
		out.append(resolve(g))
	return out

# ---------------- item goals ----------------

func _resolve_item(item_id: String, target: int) -> Dictionary:
	var item: Dictionary = DataLoader.get_item(item_id)
	if item.is_empty():
		return {"ok": false, "problem": "Unknown item '%s'" % item_id, "kind": "item", "id": item_id}
	var want: int = target if target > 0 else 1
	var have: int = BankManager.get_count(item_id)
	var equipped: int = 1 if EquipmentManager.is_equipped(item_id) else 0
	var out: Dictionary = {
		"ok": true,
		"kind": "item",
		"id": item_id,
		"label": item.get("name", item_id),
		"description": item.get("description", ""),
		"icon_kind": "items",
		"progress_current": mini(have + equipped, want),
		"progress_required": want,
		"progress": clampf(float(have + equipped) / float(maxi(want, 1)), 0.0, 1.0),
		"complete": (have + equipped) >= want,
		"requirements": [],
		"missing": [],
		"sources": [],
		"routes": [],
		"cycle": [],
	}
	var req: Dictionary = {
		"label": "%s ×%d" % [item.get("name", item_id), want],
		"current": have + equipped,
		"required": want,
		"satisfied": (have + equipped) >= want,
		"hint": "In the bank (equipped items count once)",
	}
	out["requirements"].append(req)
	if out["complete"]:
		return out
	var shortfall: int = want - (have + equipped)
	out["missing"].append({"item_id": item_id, "name": item.get("name", item_id), "need": want, "have": have + equipped})
	out["sources"] = sources_for_item(item_id)
	out["routes"] = routes_for_item(item_id)
	# Recursively explain the inputs of the best producing recipe.
	var chain: Dictionary = _material_chain(item_id, shortfall, {}, 0)
	out["materials"] = chain["materials"]
	out["prerequisite_recipes"] = chain["recipes"]
	out["cycle"] = chain["cycle"]
	if not chain["cycle"].is_empty():
		out["problem"] = "Recipe dependency cycle detected: %s" % " → ".join(chain["cycle"])
	return out

# ---------------- recipe goals ----------------

func _resolve_recipe(recipe_key: String) -> Dictionary:
	var parts: PackedStringArray = recipe_key.split(":")
	if parts.size() < 2:
		return {"ok": false, "problem": "Recipe goal id must be \"skill:action\"", "kind": "recipe", "id": recipe_key}
	var skill_id: String = parts[0]
	var action_id: String = parts[1]
	var action: Dictionary = DataLoader.get_action(skill_id, action_id)
	if action.is_empty():
		return {"ok": false, "problem": "Unknown recipe '%s'" % recipe_key, "kind": "recipe", "id": recipe_key}
	var skill: Dictionary = DataLoader.get_skill(skill_id)
	var out: Dictionary = {
		"ok": true,
		"kind": "recipe",
		"id": recipe_key,
		"label": "%s (%s)" % [action.get("name", action_id), skill.get("name", skill_id)],
		"description": action.get("description", ""),
		"icon_kind": "skills",
		"routes": [{"screen": "skill", "skill_id": skill_id, "action_id": action_id,
			"label": "Open %s" % skill.get("name", skill_id)}],
		"requirements": [],
		"missing": [],
		"sources": [],
		"cycle": [],
	}
	var level_req: int = int(action.get("level_required", 1))
	var level: int = PlayerData.get_level(skill_id)
	var level_ok: bool = level >= level_req
	out["requirements"].append({
		"label": "%s level %d" % [skill.get("name", skill_id), level_req],
		"current": level, "required": level_req, "satisfied": level_ok,
		"hint": "Train %s to unlock this action" % skill.get("name", skill_id),
	})
	var inputs: Dictionary = action.get("input_items", {})
	var all_inputs_ok: bool = true
	for item_id in inputs.keys():
		var need: int = int(inputs[item_id])
		var have: int = BankManager.get_count(str(item_id))
		var ok: bool = have >= need
		all_inputs_ok = all_inputs_ok and ok
		out["requirements"].append({
			"label": "%s ×%d" % [DataLoader.get_item(str(item_id)).get("name", item_id), need],
			"current": have, "required": need, "satisfied": ok,
			"hint": _primary_source_hint(str(item_id)),
		})
		if not ok:
			out["missing"].append({"item_id": str(item_id), "name": DataLoader.get_item(str(item_id)).get("name", item_id),
				"need": need, "have": have})
			var chain: Dictionary = _material_chain(str(item_id), need - have, {}, 0)
			for m in chain["materials"]:
				out["materials"] = (out.get("materials", []) as Array)
				if not _has_entry(out["materials"], m):
					out["materials"].append(m)
			for r in chain["recipes"]:
				out["prerequisite_recipes"] = (out.get("prerequisite_recipes", []) as Array)
				if not _has_entry(out["prerequisite_recipes"], r):
					out["prerequisite_recipes"].append(r)
			if not chain["cycle"].is_empty():
				out["cycle"] = chain["cycle"]
			# Tagged with the material they resolve: a goal with two missing ingredients would
			# otherwise present one undifferentiated list of routes.
			for source in sources_for_item(str(item_id)):
				var tagged: Dictionary = source
				tagged["for"] = str(DataLoader.get_item(str(item_id)).get("name", item_id))
				out["sources"].append(tagged)
	var tool: String = str(action.get("required_tool", ""))
	if tool != "":
		var owned: bool = PlayerData.shop_upgrades.has(tool)
		out["requirements"].append({
			"label": "Requires %s" % DataLoader.get_shop_upgrade(tool).get("name", tool),
			"current": 1 if owned else 0, "required": 1, "satisfied": owned,
			"hint": "Buy it in the Provisioner",
		})
	var ready: bool = level_ok and all_inputs_ok
	var outputs: Dictionary = action.get("output_items", {})
	if not outputs.is_empty():
		var produced: int = int(outputs.values()[0])
		out["produces"] = {"item_id": str(outputs.keys()[0]), "quantity": produced,
			"name": DataLoader.get_item(str(outputs.keys()[0])).get("name", str(outputs.keys()[0]))}
		var held: int = BankManager.get_count(str(outputs.keys()[0]))
		# A recipe goal is satisfied as soon as nothing blocks it, so the bar has to agree: reading
		# "0 / 1" next to the word "complete" is what made this card look broken.
		out["progress_current"] = produced if ready else mini(held, produced)
		out["progress_required"] = produced
		out["progress"] = 1.0 if ready else clampf(float(held) / float(maxi(produced, 1)), 0.0, 1.0)
		out["complete"] = ready
	else:
		out["complete"] = level_ok and all_inputs_ok
		out["progress"] = 1.0 if out["complete"] else 0.0
		out["progress_current"] = 0
		out["progress_required"] = 1
	return out

# ---------------- skill / building / upgrade goals ----------------

func _resolve_skill(skill_id: String, target_level: int) -> Dictionary:
	var skill: Dictionary = DataLoader.get_skill(skill_id)
	if skill.is_empty():
		return {"ok": false, "problem": "Unknown skill '%s'" % skill_id, "kind": "skill", "id": skill_id}
	var want: int = clampi(target_level if target_level > 0 else 5, 1, XPTable.MAX_LEVEL)
	var level: int = PlayerData.get_level(skill_id)
	var xp: float = PlayerData.get_xp(skill_id)
	var next_actions: Array = []
	for a in DataLoader.get_skill_actions(skill_id):
		if int(a.get("level_required", 1)) == want:
			next_actions.append({"item_id": str(a.get("id", "")), "name": str(a.get("name", "")),
				"kind": "recipe", "label": str(a.get("name", ""))})
	return {
		"ok": true, "kind": "skill", "id": skill_id,
		"label": "%s level %d" % [skill.get("name", skill_id), want],
		"description": "Training %s unlocks new actions, recipes and bonuses." % skill.get("name", skill_id),
		"icon_kind": "skills",
		"requirements": [{
			"label": "%s level %d" % [skill.get("name", skill_id), want],
			"current": level, "required": want, "satisfied": level >= want,
			"hint": "%s XP to next level" % _fmt(XPTable.xp_to_next_level(xp, level)),
		}],
		"missing": [], "sources": [],
		"routes": [{"screen": "skill", "skill_id": skill_id, "action_id": "", "label": "Open %s" % skill.get("name", skill_id)}],
		"unlocks": next_actions,
		"progress_current": level, "progress_required": want,
		"progress": clampf(float(level) / float(want), 0.0, 1.0),
		"complete": level >= want,
		"cycle": [],
	}

func _resolve_building(building_id: String) -> Dictionary:
	var b: Dictionary = DataLoader.township_buildings.get(building_id, {})
	if b.is_empty():
		return {"ok": false, "problem": "Unknown structure '%s'" % building_id, "kind": "building", "id": building_id}
	var cost: Dictionary = b.get("cost", {})
	var requirements: Array = []
	var missing: Array = []
	for res_id in cost.keys():
		var need: int = int(cost[res_id])
		var have: int = int(TownshipManager.resources.get(res_id, 0))
		var ok: bool = have >= need
		requirements.append({"label": "%s ×%d" % [TownshipManager.resource_name(str(res_id)), need], "current": have,
			"required": need, "satisfied": ok, "hint": "Produced by settlement structures each hour"})
		if not ok:
			missing.append({"item_id": res_id, "name": TownshipManager.resource_name(str(res_id)), "need": need, "have": have})
	var owned: int = int(TownshipManager.buildings.get(building_id, 0))
	var max_level: int = int(b.get("max_level", 1))
	return {
		"ok": true, "kind": "building", "id": building_id,
		"label": str(b.get("name", building_id)),
		"description": str(b.get("description", "")),
		"icon_kind": "concepts",
		"requirements": requirements, "missing": missing, "sources": [],
		"routes": [{"screen": "settlement", "label": "Open the settlement"}],
		"progress_current": owned, "progress_required": max_level,
		"progress": clampf(float(owned) / float(maxi(max_level, 1)), 0.0, 1.0),
		"complete": owned >= max_level,
		"cycle": [],
	}

func _resolve_upgrade(upgrade_id: String) -> Dictionary:
	var u: Dictionary = DataLoader.shop.get(upgrade_id, {})
	if u.is_empty():
		return {"ok": false, "problem": "Unknown upgrade '%s'" % upgrade_id, "kind": "upgrade", "id": upgrade_id}
	var cost: float = float(u.get("cost", 0.0))
	var unlocked: bool = ShopManager.has_requirement(upgrade_id)
	var requirements: Array = [
		{"label": "%s GP" % _fmt(cost), "current": PlayerData.gp, "required": cost,
			"satisfied": PlayerData.gp >= cost, "hint": "Earn GP by selling items and fighting"},
	]
	if not unlocked:
		requirements.append({"label": "Requirements", "current": 0, "required": 1, "satisfied": false,
			"hint": _requirement_hint(u)})
	var owned: int = int(PlayerData.shop_upgrades.get(upgrade_id, 0))
	var max_count: int = int(u.get("max", 1))
	return {
		"ok": true, "kind": "upgrade", "id": upgrade_id,
		"label": str(u.get("name", upgrade_id)),
		"description": str(u.get("description", "")),
		"icon_kind": "currencies",
		"requirements": requirements, "missing": [], "sources": [],
		"routes": [{"screen": "provisioner", "label": "Open the provisioner"}],
		"progress_current": owned, "progress_required": maxi(max_count, 1),
		"progress": clampf(float(owned) / float(maxi(max_count, 1)), 0.0, 1.0),
		"complete": owned >= maxi(max_count, 1),
		"cycle": [],
	}

# ---------------- dependency chains ----------------

## Walk the recipe graph backwards from `item_id`, collecting every material and the recipes
## that produce them. Guarded against cycles and bounded by MAX_DEPTH.
func _material_chain(item_id: String, needed: int, visited_items: Dictionary, depth: int) -> Dictionary:
	var out: Dictionary = {"materials": [], "recipes": [], "cycle": []}
	if depth >= MAX_DEPTH:
		return out
	if visited_items.has(item_id):
		out["cycle"] = [item_id]
		return out
	var locals: Dictionary = visited_items.duplicate()
	locals[item_id] = true

	var producers: Array = _producer_recipes(item_id)
	for prod in producers:
		var skill_id: String = prod["skill_id"]
		var action_id: String = prod["action_id"]
		var action: Dictionary = prod["action"]
		var byproduct: bool = bool(prod.get("byproduct", false))
		var chance: float = clampf(float(prod.get("chance", 1.0)), 0.0, 1.0)
		var yield_qty: int = maxi(1, int(prod.get("max_qty", 1))) if byproduct \
			else maxi(1, int(action.get("output_items", {}).get(item_id, 1)))
		# A byproduct arrives by accident once in a while, so the runs it takes is scaled by its
		# chance: one diamond at 3% is about thirty-four mining actions, not one.
		var per_action: float = float(yield_qty) * (chance if byproduct else 1.0)
		var runs: int = int(ceil(float(needed) / maxf(0.0001, per_action)))
		out["recipes"].append({
			"kind": "recipe", "id": "%s:%s" % [skill_id, action_id],
			"label": "%s ×%d" % [action.get("name", action_id), runs],
			"skill_id": skill_id, "skill_name": DataLoader.get_skill(skill_id).get("name", skill_id),
			"level_required": int(action.get("level_required", 1)),
			"unlocked": PlayerData.get_level(skill_id) >= int(action.get("level_required", 1)),
			"per_craft": yield_qty, "runs_needed": runs,
			"byproduct": byproduct, "chance": chance,
		})
		for input_id in (action.get("input_items", {}) as Dictionary).keys():
			var per_run: int = int(action["input_items"][input_id])
			var total_needed: int = per_run * runs
			var have: int = BankManager.get_count(str(input_id))
			out["materials"].append({
				"item_id": str(input_id),
				"name": DataLoader.get_item(str(input_id)).get("name", str(input_id)),
				"need": total_needed, "have": have, "short": maxi(0, total_needed - have),
				"per_craft": per_run,
				"unlocked": true,
			})
			# Recurse only when this material is itself player-made and still short.
			if have < total_needed and _is_crafted(str(input_id)):
				var deeper: Dictionary = _material_chain(str(input_id), total_needed - have, locals, depth + 1)
				for m in deeper["materials"]:
					if not _has_entry(out["materials"], m):
						out["materials"].append(m)
					elif m["short"] > 0 and m["need"] > 0:
						pass
				for r in deeper["recipes"]:
					if not _has_entry(out["recipes"], r):
						out["recipes"].append(r)
				if not deeper["cycle"].is_empty():
					out["cycle"].append_array(deeper["cycle"])
		break   # explain the best (lowest-level) producer only, to keep the panel readable
	return out

## Did any action produce this item as its main output? (i.e. is it player-made rather than
## gathered directly). Byproducts are excluded on purpose: a gem is not crafted, it turns up while
## something else is being made, so walking its inputs as if it were a recipe would invent a
## dependency the player never needs.
func _is_crafted(item_id: String) -> bool:
	for prod in _producer_recipes(item_id):
		if bool(prod.get("byproduct", false)):
			continue
		if not (prod["action"].get("input_items", {}) as Dictionary).is_empty():
			return true
	return false

func _has_entry(list: Array, entry: Dictionary) -> bool:
	for e in list:
		if str(e.get("item_id", e.get("id", ""))) == str(entry.get("item_id", entry.get("id", ""))):
			return true
	return false

## Every recipe that yields `item_id` — as its main output, or as one of its secondary outputs —
## sorted so the lowest level requirement comes first. Byproducts count as producers: gems come out
## of ore, arrow tips out of a smelt, seeds out of a pocket, the archaeology shard out of any dig.
## Leaving them out is what made the pane call eighty obtainable items unfinished content.
## Each entry is {skill_id, action_id, action, byproduct, chance, max_qty}.
func _producer_recipes(item_id: String) -> Array:
	var out: Array = []
	for skill_id in DataLoader.skills.keys():
		for a in DataLoader.get_skill_actions(skill_id):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var action: Dictionary = a
			if (action.get("output_items", {}) as Dictionary).has(item_id):
				out.append({"skill_id": skill_id, "action_id": str(action.get("id", "")), "action": action,
					"byproduct": false, "chance": 1.0, "max_qty": 1})
				continue
			for sec in (action.get("secondary_outputs", []) as Array):
				if typeof(sec) != TYPE_DICTIONARY or str((sec as Dictionary).get("item_id", "")) != item_id:
					continue
				out.append({"skill_id": skill_id, "action_id": str(action.get("id", "")), "action": action,
					"byproduct": true,
					"chance": clampf(float((sec as Dictionary).get("chance", 1.0)), 0.0, 1.0),
					"max_qty": maxi(1, int((sec as Dictionary).get("max_qty", 1)))})
	out.sort_custom(func(x, y):
		return int(x["action"].get("level_required", 1)) < int(y["action"].get("level_required", 1)))
	return out

# ---------------- "where do I get this?" ----------------

## Every place an item can be obtained from, most actionable first.
func sources_for_item(item_id: String) -> Array:
	var out: Array = []
	if item_id == "" or not DataLoader.items.has(item_id):
		return out
	# Special systems use the same source card contract as recipes and drops.
	for sid in DataLoader.get_skill_ids():
		for action in DataLoader.get_skill_actions(str(sid)):
			var prefix: String = str(action.get("quality_product", ""))
			if prefix != "" and item_id.begins_with(prefix + "_"):
				out.append({"kind": "craft", "label": str(action.name), "detail": "Scribe quality varies with mastery; research prerequisite: " + str(action.get("requires_research", "none")), "level_required": int(action.level_required), "unlocked": PlayerData.get_level(str(sid)) >= int(action.level_required), "route": {"screen": "skills", "skill_id": sid, "action_id": action.id}})
	for animal in DataLoader.new_skill_systems.get("species", []):
		# What a pen hands over: the produce you collect, the stock you breed, and the hide and
		# meat that come off each collection. Only the first two used to be listed, so hides and
		# meat read as unobtainable on the card even though RanchingManager grants both.
		var harvested: Array[String] = [str(animal.stock), str(animal.produce), str(animal.get("hide", ""))]
		if int(animal.get("meat", 0)) > 0:
			harvested.append("ranch_meat")
		if not harvested.has(item_id):
			continue
		out.append({"kind": "passive", "label": str(animal.name) + " ranch", "detail": "Collect produce, hide and meat; breed a happy pair every six hours for stock (rare hen/cow variants possible).", "level_required": int(animal.level), "unlocked": PlayerData.get_level("ranching") >= int(animal.level), "route": {"screen": "skills", "skill_id": "ranching"}})
	# The ranching system's own consumables: feed is rendered from crops, manure falls out of the
	# pen's cycle, and the two rare breeding variants are named by the tables that roll them.
	for system_item in [["ranch_feed", "Rendered from crops at the ranch, ten bags per crop"],
			["ranch_manure", "Cleaned out of a pen as its cycles complete"],
			["golden_hen_stock", "The rare variant a hen pen can breed"],
			["mooncalf_stock", "The rare variant a cow pen can breed"]]:
		if item_id != str(system_item[0]) or not DataLoader.items.has(str(system_item[0])):
			continue
		out.append({"kind": "passive", "label": "Ranching", "detail": str(system_item[1]), "level_required": 1, "unlocked": true, "route": {"screen": "skills", "skill_id": "ranching"}})
	if item_id.begins_with("enchant_") and item_id.ends_with("_essence"):
		out.append({"kind": "recycle", "label": "Disenchant equipment", "detail": "Destroy one unprotected piece; scope determines Essence type. Higher-level gear grants more.", "level_required": 1, "unlocked": true, "route": {"screen": "skills", "skill_id": "enchanting"}})
	if item_id.begins_with("enchanted__"):
		out.append({"kind": "craft", "label": "Enchanting bench", "detail": "Enchant one owned piece using Essence, runes and tier catalysts.", "level_required": 1, "unlocked": true, "route": {"screen": "skills", "skill_id": "enchanting"}})
	for offer in DataLoader.new_skill_systems.get("bazaar", []):
		if offer.get("items", {}).has(item_id): out.append({"kind": "shop", "label": str(offer.name), "detail": "%d Dream Essence in the Dream Bazaar" % int(offer.cost), "level_required": 1, "unlocked": BankManager.get_count("dream_essence") >= int(offer.cost), "route": {"screen": "skills", "skill_id": "dreamwalking"}})
	if item_id == "dream_essence": out.append({"kind": "passive", "label": "Dreamwalking", "detail": "Allocate offline time to a dreamscape, then collect Essence on your return.", "level_required": 1, "unlocked": true, "route": {"screen": "skills", "skill_id": "dreamwalking"}})
	# A familiar's mark is awarded by that familiar's own skill while it is bonded and summoned.
	# Twenty-six of them read as unfinished content because this one table was never consulted.
	for familiar_id in DataLoader.familiars.keys():
		var familiar: Dictionary = DataLoader.familiars[familiar_id]
		if str(familiar.get("mark_item", "")) != item_id:
			continue
		var mark_skill: String = str(familiar.get("mark_skill", ""))
		out.append({"kind": "passive", "label": "%s familiar" % str(familiar.get("name", familiar_id)),
			"detail": "Bond it, summon it, then train %s to be awarded its mark" % str(DataLoader.get_skill(mark_skill).get("name", mark_skill)),
			"level_required": 1, "unlocked": true,
			"route": {"screen": "skills", "skill_id": "summoning" if mark_skill == "" else mark_skill}})
	# A farmed crop is defined by the seed that grows it: `product_item` on the seed is the yield.
	for seed_id in DataLoader.items.keys():
		var seed_item: Dictionary = DataLoader.items[seed_id]
		if str(seed_item.get("item_type", "")) != "seed" or str(seed_item.get("product_item", "")) != item_id:
			continue
		out.append({"kind": "passive", "label": "Harvest %s" % str(seed_item.get("name", seed_id)),
			"detail": "Plant the seed in a farm plot and harvest the crop",
			"level_required": 1, "unlocked": true, "route": {"screen": "farm"}})
	# 1. Direct gathering (a recipe with no inputs).
	for prod in _producer_recipes(item_id):
		if bool(prod.get("byproduct", false)):
			continue
		var action: Dictionary = prod["action"]
		if (action.get("input_items", {}) as Dictionary).is_empty():
			out.append({
				"kind": "gather", "label": str(action.get("name", prod["action_id"])),
				"detail": str(DataLoader.get_skill(prod["skill_id"]).get("name", prod["skill_id"])),
				"level_required": int(action.get("level_required", 1)),
				"unlocked": PlayerData.get_level(prod["skill_id"]) >= int(action.get("level_required", 1)),
				"route": {"screen": "skill", "skill_id": prod["skill_id"], "action_id": prod["action_id"]},
			})
	# 2. Crafting recipes.
	for prod in _producer_recipes(item_id):
		if bool(prod.get("byproduct", false)):
			continue
		var a2: Dictionary = prod["action"]
		if not (a2.get("input_items", {}) as Dictionary).is_empty():
			out.append({
				"kind": "craft",
				"label": "%s at %s" % [str(a2.get("name", prod["action_id"])), str(DataLoader.get_skill(prod["skill_id"]).get("name", prod["skill_id"]))],
				"detail": _input_summary(a2.get("input_items", {})),
				"level_required": int(a2.get("level_required", 1)),
				"unlocked": PlayerData.get_level(prod["skill_id"]) >= int(a2.get("level_required", 1)),
				"route": {"screen": "skill", "skill_id": prod["skill_id"], "action_id": prod["action_id"]},
			})
	# 3. Byproducts: the action's purpose is something else, but it hands this over on the side.
	# Stating the roll matters — "mine adamantite" is not advice unless it says three per cent.
	for prod in _producer_recipes(item_id):
		if not bool(prod.get("byproduct", false)):
			continue
		var a3: Dictionary = prod["action"]
		out.append({
			"kind": "byproduct",
			"label": "%s (%s)" % [str(a3.get("name", prod["action_id"])),
				str(DataLoader.get_skill(prod["skill_id"]).get("name", prod["skill_id"]))],
			"detail": "Side drop: %s per action while you train it" % UIStyle.fmt_percent(float(prod.get("chance", 0.0))),
			"level_required": int(a3.get("level_required", 1)),
			"unlocked": PlayerData.get_level(prod["skill_id"]) >= int(a3.get("level_required", 1)),
			"route": {"screen": "skill", "skill_id": prod["skill_id"], "action_id": prod["action_id"]},
		})
	# 3. Monster drops.
	for monster_id in DataLoader.monsters.keys():
		var m: Dictionary = DataLoader.monsters[monster_id]
		for drop in m.get("loot_table", []):
			if typeof(drop) != TYPE_DICTIONARY or bool(drop.get("is_currency", false)):
				continue
			if str(drop.get("item_id", "")) != item_id:
				continue
			out.append({
				"kind": "drop", "label": str(m.get("name", monster_id)),
				"detail": "Drops at %.2f%% · combat level %d" % [float(drop.get("chance", 0.0)) * 100.0, int(m.get("combat_level", 1))],
				"level_required": int(m.get("combat_level", 1)),
				"unlocked": true,
				"route": _route_for_monster(monster_id),
			})
	# 4. Dungeon rewards, first clears and the signature shard every clear grants.
	for dungeon_id in DataLoader.dungeons.keys():
		var d: Dictionary = DataLoader.dungeons[dungeon_id]
		var is_reward: bool = false
		for bundle in [d.get("completion_reward", {}), d.get("rewards_first_clear", {})]:
			if (bundle.get("items", {}) as Dictionary).has(item_id):
				is_reward = true
		var is_shard: bool = str(d.get("shard_item", "")) == item_id
		if is_reward or is_shard:
			out.append({"kind": "reward", "label": str(d.get("name", dungeon_id)),
				"detail": "Dungeon clear reward" if is_reward else "Granted by every kill inside",
				"level_required": 0, "unlocked": true,
				"route": {"screen": "combat", "area_id": dungeon_id}})
	# 5. Shop and mastery stall stock.
	for shop_id in DataLoader.shop.keys():
		var u: Dictionary = DataLoader.shop[shop_id]
		if (u.get("grants_items", {}) as Dictionary).has(item_id):
			out.append({"kind": "shop", "label": str(u.get("name", shop_id)),
				"detail": "Provisioner · %s GP" % _fmt(float(u.get("cost", 0))), "level_required": 0,
				"unlocked": ShopManager.has_requirement(shop_id),
				"route": {"screen": "provisioner"}})
	if ShopManager.stall_item_ids().has(item_id):
		for offer in ShopManager.stall_offers():
			if str((offer as Dictionary)["item_id"]) != item_id:
				continue
			out.append({"kind": "shop", "label": "%s at the mastery stall" % str((offer as Dictionary)["name"]),
				"detail": "%s GP · %s" % [_fmt(float((offer as Dictionary)["cost"])), str((offer as Dictionary)["label"])],
				"level_required": int((offer as Dictionary)["required"]),
				"unlocked": bool((offer as Dictionary)["met"]),
				"route": {"screen": "provisioner"}})
	# 5b. The general store sells it outright. It is never the cheapest route — every line is
	# priced above the item's sell value — but it is always an available one, which is the whole
	# justification for the counter existing. Without this entry the store was invisible to goal
	# tracking: "where do I get this?" never answered "gold".
	for store_id in DataLoader.shop_store.keys():
		var stock: Variant = DataLoader.shop_store[store_id]
		if typeof(stock) != TYPE_DICTIONARY:
			continue
		if str((stock as Dictionary).get("item_id", "")) != item_id:
			continue
		var gate: Dictionary = ShopManager.store_requirement(stock as Dictionary)
		var bundle: int = maxi(1, int((stock as Dictionary).get("quantity", 1)))
		var bundle_cost: float = float((stock as Dictionary).get("cost", 0))
		out.append({
			"kind": "shop",
			"label": "General store · %d× %s" % [bundle, str(DataLoader.get_item(item_id).get("name", item_id))],
			"detail": "%s GP per bundle · %s each" % [_fmt(bundle_cost), _fmt(bundle_cost / float(bundle))],
			"level_required": int(gate["level"]),
			"unlocked": str(gate["skill"]) == "" or PlayerData.get_level(str(gate["skill"])) >= int(gate["level"]),
			"route": {"screen": "store"},
		})
	# 6. Something else upgrades into this item.
	for other_id in DataLoader.items.keys():
		if str(DataLoader.items[other_id].get("upgrade_path", "")) != item_id:
			continue
		out.append({"kind": "craft", "label": "Upgrade from %s" % str(DataLoader.items[other_id].get("name", other_id)),
			"detail": _input_summary(DataLoader.items[other_id].get("upgrade_materials", {})),
			"level_required": 0, "unlocked": true, "route": {}})
	# 7. The settlement trader exchanges stores for crates.
	for offer_id in DataLoader.trader.keys():
		var offer: Variant = DataLoader.trader[offer_id]
		if typeof(offer) != TYPE_DICTIONARY:
			continue
		if not ((offer as Dictionary).get("grant_items", {}) as Dictionary).has(item_id):
			continue
		var building: String = str((offer as Dictionary).get("requires_building", ""))
		out.append({"kind": "shop", "label": str((offer as Dictionary).get("name", offer_id)),
			"detail": "Settlement trader · %s" % _input_summary((offer as Dictionary).get("cost", {})),
			"level_required": 0,
			"unlocked": building == "" or TownshipManager.level_of(building) > 0,
			"route": {"screen": "settlement"}})
	# 8. Tasks and milestones hand items over on claim. Both were invisible here, so a reward item
	# read as unobtainable even though the screen that grants it said otherwise.
	for quest_id in Quests.all_quest_ids():
		var quest_reward: Dictionary = Quests.get_quest(quest_id).get("reward", {})
		if not ((quest_reward.get("items", {}) as Dictionary).has(item_id)
				or (quest_reward.get("unlock_items", {}) as Dictionary).has(item_id)):
			continue
		out.append({"kind": "quest", "label": str(Quests.get_quest(quest_id).get("name", quest_id)),
			"detail": "Task reward — claim it on the Tasks screen", "level_required": 0, "unlocked": true,
			"route": {"screen": "quests", "quest_id": quest_id}})
	for achievement_id in Achievements.all_ids():
		var milestone: Dictionary = Achievements.get_record(achievement_id)
		if not (((milestone.get("reward", {}) as Dictionary).get("items", {}) as Dictionary).has(item_id)):
			continue
		out.append({"kind": "milestone", "label": str(milestone.get("name", achievement_id)),
			"detail": "Milestone reward — claim it on the Milestones screen", "level_required": 0,
			"unlocked": true, "route": {"screen": "achievements"}})
	# 9. The shops with their own currencies: Slayer Coins, Museum Tokens, and the raid pool you
	# choose from after a clear. None of them is GP, so none of them was in the shop pass above.
	var slayer_cost: int = int(DataLoader.get_item(item_id).get("slayer_cost", 0))
	if slayer_cost > 0:
		out.append({"kind": "shop", "label": "Slayer rewards",
			"detail": "%d Slayer Coins, on the Huntsman screen" % slayer_cost, "level_required": 0,
			"unlocked": PlayerData.slayer_coins >= slayer_cost,
			"route": {"screen": "skills", "skill_id": "slayer"}})
	for entry_id in DataLoader.shop_museum.keys():
		var curio: Variant = DataLoader.shop_museum[entry_id]
		if typeof(curio) != TYPE_DICTIONARY:
			continue
		if not ((curio as Dictionary).get("grant_items", {}) as Dictionary).has(item_id):
			continue
		var token_cost: int = int((curio as Dictionary).get("cost", 0))
		out.append({"kind": "shop", "label": str((curio as Dictionary).get("name", entry_id)),
			"detail": "Museum shop · %d Museum Tokens" % token_cost, "level_required": 0,
			"unlocked": ArchaeologyManager.tokens >= token_cost,
			"route": {"screen": "skills", "skill_id": "archaeology"}})
	if (DataLoader.raid_shop.get("alt_items", []) as Array).has(item_id):
		out.append({"kind": "reward", "label": "Raid reward pool",
			"detail": "Chosen after a completed raid", "level_required": 0, "unlocked": true,
			"route": {"screen": "raids"}})
	# 10. The failure output of an action: burnt food is what Cookery hands over when it goes wrong.
	for skill_id in DataLoader.get_skill_ids():
		for action in DataLoader.get_skill_actions(str(skill_id)):
			if typeof(action) != TYPE_DICTIONARY:
				continue
			if str((action as Dictionary).get("fail_output_item", "")) != item_id:
				continue
			out.append({"kind": "byproduct",
				"label": "%s (%s)" % [str((action as Dictionary).get("name", "")),
					str(DataLoader.get_skill(str(skill_id)).get("name", str(skill_id)))],
				"detail": "Produced when the action burns instead of succeeding",
				"level_required": int((action as Dictionary).get("level_required", 1)), "unlocked": true,
				"route": {"screen": "skill", "skill_id": str(skill_id), "action_id": str((action as Dictionary).get("id", ""))}})
	return _diversify(out, MAX_SOURCES_PER_ITEM + 2)

## One row per route type before a type repeats, then truncated to `limit`. The pane is a summary,
## and the item with the most routes is usually the item with eleven ways to do the same thing: ash
## was showing six near-identical "burn a log" rows while the task that hands it over went unshown.
func _diversify(entries: Array, limit: int) -> Array:
	var buckets: Dictionary = {}
	var order: Array[String] = []
	for entry in entries:
		var kind: String = str((entry as Dictionary).get("kind", ""))
		if not buckets.has(kind):
			buckets[kind] = []
			order.append(kind)
		(buckets[kind] as Array).append(entry)
	var out: Array = []
	var round_index: int = 0
	while out.size() < limit:
		var added: bool = false
		for kind in order:
			var bucket: Array = buckets[kind]
			if round_index >= bucket.size():
				continue
			out.append(bucket[round_index])
			added = true
			if out.size() >= limit:
				break
		if not added:
			break
		round_index += 1
	return out

func routes_for_item(item_id: String) -> Array:
	var routes: Array = []
	for s in sources_for_item(item_id):
		if s.get("route", {}).is_empty():
			continue
		var label: String = str(s["label"])
		var entry: Dictionary = s["route"].duplicate()
		entry["label"] = "Go to %s" % label
		routes.append(entry)
	return routes

func _route_for_monster(monster_id: String) -> Dictionary:
	for area_id in DataLoader.areas.keys():
		if (DataLoader.areas[area_id].get("monsters", []) as Array).has(monster_id):
			return {"screen": "combat", "area_id": area_id}
	for dungeon_id in DataLoader.dungeons.keys():
		if (DataLoader.dungeons[dungeon_id].get("monsters", []) as Array).has(monster_id):
			return {"screen": "combat", "area_id": dungeon_id}
	return {"screen": "combat", "area_id": ""}

func _primary_source_hint(item_id: String) -> String:
	var sources: Array = sources_for_item(item_id)
	if sources.is_empty():
		return "No known source — this may be unfinished content"
	var first: Dictionary = sources[0]
	return "From: %s (%s)" % [str(first.get("label", "")), str(first.get("detail", ""))]

func _input_summary(inputs: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id in inputs.keys():
		parts.append("%s ×%d" % [DataLoader.get_item(str(item_id)).get("name", item_id), int(inputs[item_id])])
	return ", ".join(parts)

func _requirement_hint(u: Dictionary) -> String:
	var parts: Array[String] = []
	for req in u.get("requires", []):
		parts.append("own %s" % str(DataLoader.get_shop_upgrade(str(req)).get("name", req)))
	for skill_id in (u.get("requires_skill", {}) as Dictionary).keys():
		parts.append("%s %d" % [str(DataLoader.get_skill(str(skill_id)).get("name", skill_id)), int(u["requires_skill"][skill_id])])
	if bool(u.get("requires_all_skills_99", false)):
		parts.append("every skill at 99")
	var dungeon: String = str(u.get("requires_dungeon", ""))
	if dungeon != "":
		parts.append("clear %s" % str(DataLoader.get_dungeon(dungeon).get("name", dungeon)))
	return "Needs " + ", ".join(parts) if not parts.is_empty() else "Locked"

func _fmt(v: float) -> String:
	if absf(v) >= 1_000_000_000.0:
		return "%.2fB" % (v / 1_000_000_000.0)
	if absf(v) >= 1_000_000.0:
		return "%.2fM" % (v / 1_000_000.0)
	if absf(v) >= 10_000.0:
		return "%.1fK" % (v / 1_000.0)
	return str(int(v))

# ---------------- suggestions ----------------

## Suggested next steps derived ONLY from live state (never a generic rotating tip list).
func suggestions(limit: int = 5) -> Array:
	var out: Array = []
	# 1. A craftable upgrade for a slot whose item is below the player's best available tier.
	var best: Dictionary = _best_craftable_equipment()
	if not best.is_empty():
		out.append({
			"reason": "You can craft an upgrade for your %s" % best["slot_name"],
			"label": "Craft %s" % best["name"],
			"route": {"screen": "skill", "skill_id": best["skill_id"], "action_id": best["action_id"]},
			"icon_kind": "items", "icon_id": best["item_id"],
			"goal": {"kind": "recipe", "id": "%s:%s" % [best["skill_id"], best["action_id"]]},
		})
	# 2. A region the player can now survive that has not been visited.
	var area: Dictionary = _next_unvisited_area()
	if not area.is_empty():
		out.append({
			"reason": "Combat level %d enemies have not been scouted" % int(area.get("combat_level", 0)),
			"label": "Scout %s" % area["name"],
			"route": {"screen": "combat", "area_id": area["id"]},
			"icon_kind": "areas", "icon_id": area["id"],
		})
	# 3. An unclaimed, completed quest reward.
	for q in Quests.all_quest_ids():
		if Quests.is_complete(q) and not Quests.is_claimed(q):
			out.append({
				"reason": "A finished task is waiting to be claimed",
				"label": "Claim: %s" % Quests.get_quest(q).get("name", q),
				"route": {"screen": "quests", "quest_id": q},
				"icon_kind": "currencies", "icon_id": "gp",
			})
			break
	# 4. An unlockable skill action at (or just above) the current level.
	var unlock: Dictionary = _nearest_skill_unlock()
	if not unlock.is_empty():
		out.append({
			"reason": "%s XP would unlock a new %s action" % [unlock["xp_needed"], unlock["skill_name"]],
			"label": "Train %s to %d" % [unlock["skill_name"], unlock["level"]],
			"route": {"screen": "skill", "skill_id": unlock["skill_id"], "action_id": ""},
			"icon_kind": "skills", "icon_id": unlock["skill_id"],
			"goal": {"kind": "skill", "id": unlock["skill_id"], "level": unlock["level"]},
		})
	# 5. An affordable but unbought upgrade.
	var affordable: Dictionary = _affordable_upgrade()
	if not affordable.is_empty():
		out.append({
			"reason": "Affordable now — %s GP held" % _fmt(PlayerData.gp),
			"label": "Buy %s" % affordable["name"],
			"route": {"screen": "provisioner"},
			"icon_kind": "currencies", "icon_id": "gp",
			"goal": {"kind": "upgrade", "id": affordable["id"]},
		})
	return out.slice(0, limit)

func _best_craftable_equipment() -> Dictionary:
	var best_slot_score: Dictionary = {}
	for slot in EquipmentManager.slots.keys():
		var item_id: String = str(EquipmentManager.slots[slot])
		best_slot_score[int(slot)] = _item_power(item_id)
	var out: Dictionary = {}
	for skill_id in DataLoader.skills.keys():
		for a in DataLoader.get_skill_actions(skill_id):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if int(a.get("level_required", 1)) > PlayerData.get_level(skill_id):
				continue
			var inputs: Dictionary = a.get("input_items", {})
			if inputs.is_empty():
				continue
			var affordable: bool = true
			for item_id in inputs.keys():
				if BankManager.get_count(str(item_id)) < int(inputs[item_id]):
					affordable = false
					break
			if not affordable:
				continue
			for out_id in (a.get("output_items", {}) as Dictionary).keys():
				var item: Dictionary = DataLoader.get_item(str(out_id))
				if item.is_empty() or str(item.get("item_type", "")) != "equipment":
					continue
				var slot: int = int(item.get("equipment_slot", -1))
				if slot < 0:
					continue
				var power: float = _item_power(str(out_id))
				if power > float(best_slot_score.get(slot, -1.0)):
					if out.is_empty() or power > float(out.get("power", -1.0)):
						out = {
							"item_id": str(out_id), "name": str(item.get("name", out_id)),
							"slot_name": ItemData.slot_name(slot),
							"skill_id": skill_id, "action_id": str(a.get("id", "")), "power": power,
						}
	return out

func _item_power(item_id: String) -> float:
	if item_id == "":
		return -1.0
	var item: Dictionary = DataLoader.get_item(item_id)
	var stats: Dictionary = item.get("equipment_stats", {})
	var total: float = 0.0
	for k in stats.keys():
		total += float(stats[k])
	total += float(item.get("damage_reduction", 0.0)) * 10.0
	return total

func _next_unvisited_area() -> Dictionary:
	var visits: Dictionary = PlayerData.stats.get("region_visits", {})
	for area_id in DataLoader.areas.keys():
		if visits.has(area_id):
			continue
		var a: Dictionary = DataLoader.areas[area_id]
		var levels: Array = a.get("level_range", [0, 0])
		var lo: int = int(levels[0]) if levels.size() > 0 else 0
		if PlayerData.get_combat_level() >= lo:
			var first: String = str((a.get("monsters", []) as Array)[0]) if not (a.get("monsters", []) as Array).is_empty() else ""
			return {"id": area_id, "name": str(a.get("name", area_id)),
				"combat_level": int(DataLoader.get_monster(first).get("combat_level", 0))}
	return {}

func _nearest_skill_unlock() -> Dictionary:
	var best: Dictionary = {}
	for skill_id in DataLoader.skills.keys():
		if str(DataLoader.get_skill(skill_id).get("category", "")) == "combat":
			continue
		var level: int = PlayerData.get_level(skill_id)
		var xp: float = PlayerData.get_xp(skill_id)
		for a in DataLoader.get_skill_actions(skill_id):
			var req: int = int(a.get("level_required", 1))
			if req <= level:
				continue
			var needed: float = maxf(0.0, float(XPTable.xp_for_level(req)) - xp)
			if best.is_empty() or needed < float(best.get("needed", 1e18)):
				best = {"skill_id": skill_id, "skill_name": str(DataLoader.get_skill(skill_id).get("name", skill_id)),
					"level": req, "needed": needed,
					"xp_needed": _fmt(needed), "action": str(a.get("name", ""))}
	if best.is_empty():
		return {}
	if float(best["needed"]) > 5_000_000.0:
		return {}
	return best

func _affordable_upgrade() -> Dictionary:
	var candidates: Array = []
	for upgrade_id in DataLoader.shop.keys():
		if int(PlayerData.shop_upgrades.get(upgrade_id, 0)) >= int(DataLoader.shop[upgrade_id].get("max", 1)):
			continue
		var check: Dictionary = ShopManager.can_buy(upgrade_id)
		if bool(check["ok"]):
			candidates.append({"id": upgrade_id, "name": str(DataLoader.shop[upgrade_id].get("name", upgrade_id)),
				"cost": float(DataLoader.shop[upgrade_id].get("cost", 0.0))})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b): return float(a["cost"]) < float(b["cost"]))
	return candidates[0]

# ---------------- persistence ----------------

func serialize() -> Dictionary:
	return {"pinned": pinned}

func deserialize(d: Dictionary) -> void:
	pinned = d.get("pinned", [])
	if typeof(pinned) != TYPE_ARRAY:
		pinned = []
	var clean: Array = []
	for g in pinned:
		if typeof(g) == TYPE_DICTIONARY and str(g.get("kind", "")) != "" and str(g.get("id", "")) != "":
			clean.append({"kind": str(g["kind"]), "id": str(g["id"]), "level": int(g.get("level", 0))})
	pinned = clean
