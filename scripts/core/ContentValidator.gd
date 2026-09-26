class_name ContentValidator
extends RefCounted
## ContentValidator — static analysis of every content JSON file.
##
## Runs on demand (`--validate` CLI flag) and automatically in debug builds. It is the guard
## rail that keeps 700+ hand-authored content records coherent, so a typo in one file shows up
## as a named problem instead of a silent "blank panel" in the game.
##
## Severity:
##   "error"   — the game cannot behave correctly (dangling reference, impossible recipe).
##   "warning" — content is probably wrong or is unreachable, but the game still runs.
##   "info"    — useful completeness statistics.

const VALID_ITEM_TYPES: Array[String] = [
	"resource", "food", "equipment", "potion", "rune", "bone", "ammo", "consumable",
	"currency", "tablet", "seed",
]
## The vocabulary the content actually uses. "processing", "passive" and "exploration" are
## real skill types in data/skills.json (Kilncraft, Emberreach itself, Surveying).
const VALID_SKILL_TYPES: Array[String] = ["gathering", "artisan", "processing", "support",
	"passive", "exploration", "combat"]
const VALID_SKILL_CATEGORIES: Array[String] = ["combat", "non_combat"]
const VALID_MONSTER_ATTACK_TYPES: Array[String] = ["melee", "ranged", "magic"]
const VALID_ACTION_CATEGORIES: Array[String] = ["gather", "artisan", "support", "combat"]
## The closed ability vocabulary from data/abilities.json. Tasks 3/5 map each key to a
## ModifierKeys constant, so a key outside this set has nowhere to go and would be a silent no-op.
const KNOWN_ABILITY_EFFECTS: Array[String] = ["max_hit_percent", "interval_percent",
	"crit_chance_percent", "apply_status", "heal_on_hit_fraction"]
const VALID_ABILITY_STYLES: Array[String] = ["melee", "ranged", "magic", "any"]
const VALID_SPECIAL_BIAS: Array[String] = ["eager", "normal", "hold"]
const EQUIPMENT_SLOT_NAMES: Dictionary = {
	0: "helmet", 1: "platebody", 2: "platelegs", 3: "boots", 4: "gloves", 5: "cape",
	6: "amulet", 7: "ring", 8: "weapon", 9: "shield", 10: "quiver", 11: "summon_1",
	12: "summon_2", 13: "passive", 14: "consumable",
}

var issues: Array = []

func validate_all() -> Array:
	issues.clear()
	_check_ids()
	_check_items()
	_check_skills_and_recipes()
	_check_recipe_graph()
	_check_monsters()
	_check_abilities()
	_check_regions()
	_check_shop()
	_check_side_systems()
	_check_acquisition_coverage()
	return issues

# ---------------- helpers ----------------

func _add(severity: String, code: String, message: String) -> void:
	issues.append({"severity": severity, "code": code, "message": message})

func _has_item(id: String) -> bool:
	return DataLoader.items.has(id)

# Static so the record validators below (which callers use as free functions) can reuse them.
static func _has_skill(id: String) -> bool:
	return DataLoader.skills.has(id)

func _err(code: String, msg: String) -> void:
	_add("error", code, msg)

func _warn(code: String, msg: String) -> void:
	_add("warning", code, msg)

static func _is_finite_number(v: Variant) -> bool:
	var kind: int = typeof(v)
	if kind != TYPE_INT and kind != TYPE_FLOAT:
		return false
	return is_finite(float(v))

# ---------------- id hygiene ----------------

func _check_ids() -> void:
	var seen: Dictionary = {}
	for collection in [
		["item", DataLoader.items], ["monster", DataLoader.monsters], ["skill", DataLoader.skills],
		["area", DataLoader.areas], ["dungeon", DataLoader.dungeons], ["prayer", DataLoader.prayers],
		["constellation", DataLoader.constellations], ["familiar", DataLoader.familiars],
		["pet", DataLoader.pets], ["obstacle", DataLoader.obstacles],
		["dungeon_shop", DataLoader.shop], ["township_building", DataLoader.township_buildings],
		["special_attack", DataLoader.special_attacks], ["ability", DataLoader.abilities],
		["cartography_hex", DataLoader.cartography_hexes],
	]:
		var kind: String = collection[0]
		var table: Dictionary = collection[1]
		for id in table.keys():
			var key: String = "%s:%s" % [kind, id]
			if seen.has(key):
				_err("duplicate_id", "duplicate %s id '%s'" % [kind, id])
			seen[key] = true
			var row: Variant = table[id]
			if typeof(row) != TYPE_DICTIONARY:
				_err("invalid_record", "%s '%s' is not an object" % [kind, id])
				continue
			var row_id: String = str((row as Dictionary).get("id", id))
			if row_id != id:
				_warn("id_mismatch", "%s key '%s' declares id '%s'" % [kind, id, row_id])
			if id.strip_edges() == "":
				_err("empty_id", "a %s has an empty id" % kind)

	# Action ids must be unique within their skill.
	for skill_id in DataLoader.skills.keys():
		var acts: Array = DataLoader.get_skill_actions(skill_id)
		var seen_actions: Dictionary = {}
		for a in acts:
			if typeof(a) != TYPE_DICTIONARY:
				_err("invalid_action", "%s has a non-object action" % skill_id)
				continue
			var aid: String = str(a.get("id", ""))
			if aid == "":
				_err("empty_action_id", "%s has an action with no id" % skill_id)
			if seen_actions.has(aid):
				_err("duplicate_action_id", "%s declares action '%s' twice" % [skill_id, aid])
			seen_actions[aid] = true

# ---------------- items ----------------

func _check_items() -> void:
	for id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.items[id]
		var type: String = str(it.get("item_type", ""))
		if not VALID_ITEM_TYPES.has(type):
			_err("invalid_item_type", "item '%s' has unknown item_type '%s'" % [id, type])
		if not _is_finite_number(it.get("sell_price", 0)):
			_err("invalid_number", "item '%s' sell_price is not a number" % id)
		elif float(it["sell_price"]) < 0.0:
			_err("negative_value", "item '%s' has negative sell_price" % id)
		if type == "equipment":
			var slot_v: Variant = it.get("equipment_slot", -1)
			if not _is_finite_number(slot_v) or int(slot_v) < 0:
				_err("missing_equipment_slot", "equipment item '%s' has no equipment_slot" % id)
			elif not EQUIPMENT_SLOT_NAMES.has(int(slot_v)):
				_err("invalid_equipment_slot", "equipment item '%s' uses slot %d" % [id, int(slot_v)])
			if float(it.get("attack_speed", 0.0)) < 0.0:
				_err("negative_value", "item '%s' has negative attack_speed" % id)
			var sa: String = str(it.get("special_attack", ""))
			if sa != "" and not DataLoader.special_attacks.has(sa):
				_err("missing_reference", "item '%s' references unknown special_attack '%s'" % [id, sa])
			var stats: Variant = it.get("equipment_stats", {})
			if typeof(stats) != TYPE_DICTIONARY:
				_err("invalid_record", "item '%s' equipment_stats is not an object" % id)
		if type == "food" and int(it.get("heal_amount", 0)) < 0:
			_err("negative_value", "food '%s' has negative heal_amount" % id)
		if type == "seed":
			for field in ["product_item"]:
				var target: String = str(it.get(field, ""))
				if target != "" and not _has_item(target):
					_err("missing_reference", "seed '%s' %s -> unknown item '%s'" % [id, field, target])
			if float(it.get("grow_seconds", 0.0)) <= 0.0:
				_err("invalid_duration", "seed '%s' has non-positive grow_seconds" % id)
		for req_skill in it.get("level_requirements", {}).keys():
			if not _has_skill(str(req_skill)):
				_err("missing_reference", "item '%s' requires unknown skill '%s'" % [id, req_skill])
		var upgrade_to: String = str(it.get("upgrade_path", ""))
		if upgrade_to != "" and not _has_item(upgrade_to):
			_err("missing_reference", "item '%s' upgrade_path -> unknown item '%s'" % [id, upgrade_to])
		for mat in it.get("upgrade_materials", {}).keys():
			if not _has_item(str(mat)):
				_err("missing_reference", "item '%s' upgrade_materials references unknown item '%s'" % [id, mat])

# ---------------- skills, actions, recipes ----------------

func _check_skills_and_recipes() -> void:
	for skill_id in DataLoader.skills.keys():
		var s: Dictionary = DataLoader.skills[skill_id]
		var cat: String = str(s.get("category", ""))
		if not VALID_SKILL_CATEGORIES.has(cat):
			_err("invalid_skill_category", "skill '%s' has category '%s'" % [skill_id, cat])
		var type: String = str(s.get("type", ""))
		if not VALID_SKILL_TYPES.has(type):
			_err("invalid_skill_type", "skill '%s' has type '%s'" % [skill_id, type])
		var max_level: int = int(s.get("max_level", 120))
		if max_level < 1 or max_level > XPTable.MAX_LEVEL:
			_err("invalid_level_cap", "skill '%s' max_level %d is out of range" % [skill_id, max_level])
		for threshold in s.get("mastery_unlocks", {}).keys():
			var t: int = int(threshold)
			if t < 1 or t > max_level:
				_warn("unreachable_mastery", "skill '%s' mastery unlock %d is outside 1..%d" % [skill_id, t, max_level])
		var seen_levels: Array = []
		for a in DataLoader.get_skill_actions(skill_id):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var aid: String = str(a.get("id", ""))
			_check_action(skill_id, aid, a, max_level)
			seen_levels.append(int(a.get("level_required", 1)))
		if seen_levels.size() > 0:
			var lo: int = int(seen_levels.min())
			if lo > 1 and DataLoader.get_skill_actions(skill_id).size() > 1:
				_info("late_first_unlock", "skill '%s' first action unlocks at level %d" % [skill_id, lo])

func _check_action(skill_id: String, aid: String, a: Dictionary, max_level: int) -> void:
	var label: String = "%s:%s" % [skill_id, aid]
	var lvl: int = int(a.get("level_required", 1))
	if lvl < 1:
		_err("invalid_level", "%s level_required %d < 1" % [label, lvl])
	elif lvl > max_level:
		_err("unreachable_unlock", "%s requires level %d but the skill caps at %d" % [label, lvl, max_level])
	var interval: float = float(a.get("base_interval", 0.0))
	if not _is_finite_number(a.get("base_interval", 0.0)) or interval <= 0.0:
		_err("negative_duration", "%s base_interval must be > 0 (found %s)" % [label, str(a.get("base_interval"))])
	var xp: float = float(a.get("base_xp", 0.0))
	if not _is_finite_number(a.get("base_xp", 0.0)) or xp < 0.0:
		_err("negative_value", "%s base_xp must be >= 0" % label)
	if a.has("category") and not VALID_ACTION_CATEGORIES.has(str(a["category"])):
		_warn("invalid_action_category", "%s has unknown category '%s'" % [label, str(a["category"])])
	if a.has("success_chance"):
		var c: float = float(a["success_chance"])
		if c < 0.0 or c > 1.0:
			_err("invalid_probability", "%s success_chance %f is outside 0..1" % [label, c])

	var inputs: Dictionary = a.get("input_items", {})
	var outputs: Dictionary = a.get("output_items", {})
	for item_id in inputs.keys():
		if not _has_item(str(item_id)):
			_err("missing_reference", "%s input references unknown item '%s'" % [label, item_id])
		if int(inputs[item_id]) <= 0:
			_err("invalid_quantity", "%s input '%s' must be a positive integer" % [label, item_id])
	for item_id in outputs.keys():
		if not _has_item(str(item_id)):
			_err("missing_reference", "%s output references unknown item '%s'" % [label, item_id])
		if int(outputs[item_id]) <= 0:
			_err("invalid_quantity", "%s output '%s' must be a positive integer" % [label, item_id])
	var skill_type: String = str(DataLoader.get_skill(skill_id).get("type", ""))
	var has_reward_channel: bool = not outputs.is_empty() or not inputs.is_empty() \
		or not (a.get("secondary_outputs", []) as Array).is_empty() \
		or float(a.get("gp_reward", 0.0)) > 0.0
	if not has_reward_channel:
		# A few systems drive their own rewards from other data (Farming grows a seed's
		# product_item, Cartography/Agility hand out GP and modifiers). Those are legitimate;
		# an artisan action that produces nothing at all is not.
		if str(a.get("category", "")) == "artisan" or skill_type == "artisan":
			_err("invalid_recipe", "%s is an artisan action that produces nothing" % label)
		else:
			_info("system_driven_action", "%s grants no items directly (its system owns the reward)" % label)
	elif outputs.is_empty() and skill_type == "artisan":
		_err("invalid_recipe", "%s is an artisan action with no output items" % label)
	if inputs.is_empty() and not outputs.is_empty() and skill_type == "artisan":
		# Gathering actions are fine; work at a station with no materials is not.
		_warn("free_recipe", "%s is an artisan action with no inputs" % label)
	for sec in a.get("secondary_outputs", []):
		if typeof(sec) != TYPE_DICTIONARY:
			_err("invalid_record", "%s has a malformed secondary_output" % label)
			continue
		var sid: String = str(sec.get("item_id", ""))
		if not _has_item(sid):
			_err("missing_reference", "%s secondary_output references unknown item '%s'" % [label, sid])
		var chance: float = float(sec.get("chance", 0.0))
		if chance < 0.0 or chance > 1.0:
			_err("invalid_probability", "%s secondary_output '%s' chance %f is outside 0..1" % [label, sid, chance])
		if int(sec.get("min_qty", 1)) > int(sec.get("max_qty", 1)):
			_err("invalid_quantity", "%s secondary_output '%s' min_qty > max_qty" % [label, sid])
	var tool: String = str(a.get("required_tool", ""))
	if tool != "" and not DataLoader.shop.has(tool):
		_err("unreachable_unlock", "%s requires tool '%s' which is not a shop upgrade" % [label, tool])
	for req in a.get("required_items_equipped", []):
		if not _has_item(str(req)):
			_err("missing_reference", "%s required_items_equipped references unknown item '%s'" % [label, req])
	if float(a.get("node_hp", 0)) < 0:
		_err("negative_value", "%s node_hp must be >= 0" % label)
	for key in a.get("mastery_unlocks", {}).keys():
		if int(key) < 1 or int(key) > max_level:
			_warn("unreachable_mastery", "%s mastery unlock %s is outside 1..%d" % [label, key, max_level])

# ---------------- recipe graph ----------------

## Detects recipe cycles such as A requires B and B requires A, which can never be started.
func _check_recipe_graph() -> void:
	var producers: Dictionary = {}   # item_id -> Array of "skill:action" that produce it
	for skill_id in DataLoader.skills.keys():
		for a in DataLoader.get_skill_actions(skill_id):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var label: String = "%s:%s" % [skill_id, a.get("id", "")]
			for out_id in (a.get("output_items", {}) as Dictionary).keys():
				if not producers.has(out_id):
					producers[out_id] = []
				producers[out_id].append(label)

	var visiting: Dictionary = {}
	var done: Dictionary = {}

	for skill_id in DataLoader.skills.keys():
		for a in DataLoader.get_skill_actions(skill_id):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var label: String = "%s:%s" % [skill_id, a.get("id", "")]
			var cycle: Array = _find_cycle(label, producers, visiting, done, [])
			if not cycle.is_empty():
				_err("circular_dependency", "recipe cycle: %s" % " -> ".join(cycle))

func _find_cycle(node: String, producers: Dictionary, visiting: Dictionary, done: Dictionary, stack: Array) -> Array:
	if done.has(node):
		return []
	if visiting.has(node):
		var start: int = stack.find(node)
		var out: Array = stack.slice(maxi(start, 0))
		out.append(node)
		return out
	visiting[node] = true
	stack.append(node)
	var parts: PackedStringArray = node.split(":")
	var skill_id: String = parts[0] if parts.size() > 0 else ""
	var action_id: String = parts[1] if parts.size() > 1 else ""
	var action: Dictionary = DataLoader.get_action(skill_id, action_id)
	for in_id in (action.get("input_items", {}) as Dictionary).keys():
		for parent in producers.get(in_id, []):
			# Only self-referential chains inside the same skill can deadlock the player.
			if str(parent).split(":")[0] != skill_id:
				continue
			var found: Array = _find_cycle(str(parent), producers, visiting, done, stack)
			if not found.is_empty():
				return found
	stack.pop_back()
	visiting.erase(node)
	done[node] = true
	return []

# ---------------- monsters ----------------

func _check_monsters() -> void:
	for id in DataLoader.monsters.keys():
		var m: Dictionary = DataLoader.monsters[id]
		var label: String = "monster:%s" % id
		if int(m.get("hitpoints", 0)) <= 0:
			_err("invalid_quantity", "%s hitpoints must be > 0" % label)
		if int(m.get("max_hit", 0)) < 0:
			_err("negative_value", "%s max_hit must be >= 0" % label)
		var at: String = str(m.get("attack_type", ""))
		if not VALID_MONSTER_ATTACK_TYPES.has(at):
			_err("invalid_attack_type", "%s attack_type '%s' is invalid" % [label, at])
		if float(m.get("attack_speed", 0.0)) <= 0.0:
			_err("invalid_duration", "%s attack_speed must be > 0" % label)
		var dr: float = float(m.get("damage_reduction", 0.0))
		if dr < 0.0 or dr >= 100.0:
			_err("invalid_probability", "%s damage_reduction %f must be in [0,100)" % [label, dr])
		if float(m.get("respawn_time", 0.0)) < 0.0:
			_err("negative_duration", "%s respawn_time must be >= 0" % label)
		var bone: String = str(m.get("bone_type", ""))
		if bone != "" and not _has_item(bone):
			_err("missing_reference", "%s bone_type -> unknown item '%s'" % [label, bone])
		for sa in m.get("special_attacks", []):
			if not DataLoader.special_attacks.has(str(sa)):
				_err("missing_reference", "%s references unknown special_attack '%s'" % [label, sa])
		for passive in m.get("passives", []):
			if not CombatManager.KNOWN_MONSTER_PASSIVES.has(str(passive)):
				_err("missing_reference", "%s references unknown passive '%s'" % [label, passive])
		for drop in m.get("loot_table", []):
			if typeof(drop) != TYPE_DICTIONARY:
				_err("invalid_record", "%s has a malformed loot entry" % label)
				continue
			var chance: float = float(drop.get("chance", 0.0))
			if chance <= 0.0 or chance > 1.0:
				_err("invalid_probability", "%s loot chance %f must be in (0,1]" % [label, chance])
			if bool(drop.get("is_currency", false)):
				continue
			var item_id: String = str(drop.get("item_id", ""))
			if not _has_item(item_id):
				_err("missing_reference", "%s loot references unknown item '%s'" % [label, item_id])
			if int(drop.get("quantity", 0)) <= 0:
				_err("invalid_quantity", "%s loot '%s' quantity must be > 0" % [label, item_id])
			if int(drop.get("min_quantity", 0)) < 0:
				_err("negative_value", "%s loot '%s' min_quantity must be >= 0" % [label, item_id])

# ---------------- abilities + strategies ----------------

## Validates one abilities.json record. Returns error strings (empty == valid) so the engine tasks
## can call it on a player-authored loadout without instantiating the whole validator.
static func check_ability_record(ab: Dictionary) -> Array:
	var errs: Array[String] = []
	var id: String = str(ab.get("id", "")).strip_edges()
	var label: String = "ability '%s'" % id
	if id == "":
		errs.append("an ability has no id")
	var style: String = str(ab.get("style", ""))
	if not VALID_ABILITY_STYLES.has(style):
		errs.append("%s has style '%s'" % [label, style])
	var effect: Variant = ab.get("effect", {})
	if typeof(effect) != TYPE_DICTIONARY:
		errs.append("%s effect is not an object" % label)
		effect = {}
	elif (effect as Dictionary).is_empty():
		errs.append("%s has an empty effect" % label)
	for key in (effect as Dictionary).keys():
		var k: String = str(key)
		var value: Variant = (effect as Dictionary)[key]
		if not KNOWN_ABILITY_EFFECTS.has(k):
			errs.append("%s effect has unknown key '%s'" % [label, k])
		elif k == "apply_status":
			# A status id, not a number: StatusEffect.create would silently no-op on a typo.
			if typeof(value) != TYPE_STRING or not StatusEffect.TABLE.has(value):
				errs.append("%s apply_status '%s' is not a known status" % [label, str(value)])
		elif not _is_finite_number(value):
			errs.append("%s effect '%s' is not a number" % [label, k])
	# status_duration is CONDITIONAL: the only reader is the apply_status branch, so a record with
	# one and no apply_status carries a value nothing consumes, and one with apply_status and no
	# duration would apply an instant- expiry status. Both directions are bugs.
	var has_status: bool = (effect as Dictionary).has("apply_status")
	var duration: Variant = ab.get("status_duration", null)
	if has_status and not _is_finite_number(duration):
		errs.append("%s applies a status but has no numeric status_duration" % label)
	elif has_status and float(duration) <= 0.0:
		errs.append("%s status_duration %f must be > 0" % [label, float(duration)])
	elif not has_status and duration != null:
		errs.append("%s has status_duration but no apply_status effect" % label)
	var chance: Variant = ab.get("trigger_chance", 0.0)
	if not _is_finite_number(chance) or float(chance) <= 0.0 or float(chance) > 100.0:
		errs.append("%s trigger_chance %s must be in (0,100]" % [label, str(chance)])
	var cooldown: Variant = ab.get("cooldown_attacks", 0)
	if not _is_finite_number(cooldown) or float(cooldown) != float(int(cooldown)) or float(cooldown) < 0.0:
		errs.append("%s cooldown_attacks %s must be a non-negative integer" % [label, str(cooldown)])
	var reqs: Variant = ab.get("req_levels", {})
	if typeof(reqs) != TYPE_DICTIONARY:
		errs.append("%s req_levels is not an object" % label)
	else:
		for skill_id in (reqs as Dictionary).keys():
			var level: Variant = (reqs as Dictionary)[skill_id]
			if not _has_skill(str(skill_id)):
				errs.append("%s requires unknown skill '%s'" % [label, skill_id])
			elif not _is_finite_number(level) or float(level) != float(int(level)) or int(level) < 1:
				errs.append("%s requires %s %s, which is not an integer >= 1" % [label, skill_id, str(level)])
	return errs

## Validates one combat strategy. Every key is required: a strategy the engine fills in a default
## for is a decision the player never made, and a loadout id that no longer exists is a dead slot.
static func check_strategy_record(strategy: Dictionary) -> Array:
	var errs: Array[String] = []
	var name_v: Variant = strategy.get("name", "")
	var label: String = "strategy '%s'" % (str(name_v) if str(name_v).strip_edges() != "" else "?")
	if typeof(name_v) != TYPE_STRING or str(name_v).strip_edges() == "":
		errs.append("%s has no name" % label)
	var loadout: Variant = strategy.get("ability_loadout", null)
	if typeof(loadout) != TYPE_ARRAY:
		errs.append("%s ability_loadout is not an array" % label)
	else:
		for entry in (loadout as Array):
			if typeof(entry) != TYPE_STRING or not DataLoader.abilities.has(entry):
				errs.append("%s ability_loadout references unknown ability '%s'" % [label, str(entry)])
	var bias: String = str(strategy.get("special_bias", ""))
	if not VALID_SPECIAL_BIAS.has(bias):
		errs.append("%s has special_bias '%s'" % [label, bias])
	var threshold: Variant = strategy.get("food_threshold", null)
	if not _is_finite_number(threshold) or float(threshold) < 0.0 or float(threshold) > 1.0:
		errs.append("%s food_threshold %s must be in 0..1" % [label, str(threshold)])
	return errs

func _check_abilities() -> void:
	for id in DataLoader.abilities.keys():
		var ab: Variant = DataLoader.abilities[id]
		if typeof(ab) != TYPE_DICTIONARY:
			_err("invalid_record", "ability '%s' is not an object" % id)
			continue
		for message in check_ability_record(ab):
			_err("invalid_record", message)

# ---------------- regions ----------------

func _check_regions() -> void:
	for id in DataLoader.areas.keys():
		var a: Dictionary = DataLoader.areas[id]
		if (a.get("monsters", []) as Array).is_empty():
			_warn("empty_region", "area '%s' contains no monsters" % id)
		for mid in a.get("monsters", []):
			if not DataLoader.monsters.has(str(mid)):
				_err("missing_reference", "area '%s' lists unknown monster '%s'" % [id, mid])
		_check_hazard("area '%s'" % id, a.get("hazard", {}))
		_check_region_requirements("area", id, a)
	for id in DataLoader.dungeons.keys():
		var d: Dictionary = DataLoader.dungeons[id]
		if (d.get("monsters", []) as Array).is_empty():
			_err("empty_region", "dungeon '%s' has no encounter list" % id)
		for mid in d.get("monsters", []):
			if not DataLoader.monsters.has(str(mid)):
				_err("missing_reference", "dungeon '%s' lists unknown monster '%s'" % [id, mid])
		_check_region_requirements("dungeon", id, d)

func _check_region_requirements(kind: String, id: String, row: Dictionary) -> void:
	var reqs: Variant = row.get("requires", {})
	if typeof(reqs) == TYPE_DICTIONARY:
		for skill_id in reqs.keys():
			if not _has_skill(str(skill_id)):
				_err("missing_reference", "%s '%s' requires unknown skill '%s'" % [kind, id, skill_id])
			elif int(reqs[skill_id]) > int(DataLoader.get_skill(str(skill_id)).get("max_level", 120)):
				_err("unreachable_unlock", "%s '%s' requires %s %d above the skill cap" % [kind, id, skill_id, int(reqs[skill_id])])
	var rng: Variant = row.get("level_range", [])
	if typeof(rng) == TYPE_ARRAY and (rng as Array).size() == 2:
		if int(rng[0]) > int(rng[1]):
			_err("invalid_range", "%s '%s' level_range is inverted" % [kind, id])

func _check_hazard(label: String, hazard: Variant) -> void:
	if typeof(hazard) != TYPE_DICTIONARY:
		_err("invalid_record", "%s hazard is not an object" % label)
		return
	for key in (hazard as Dictionary).keys():
		if not ["enemy_damage_percent", "player_accuracy_percent", "player_evasion_percent", "label"].has(str(key)):
			_err("invalid_record", "%s hazard has unknown key '%s'" % [label, key])
	var enemy_damage: float = float((hazard as Dictionary).get("enemy_damage_percent", 0.0))
	var accuracy: float = float((hazard as Dictionary).get("player_accuracy_percent", 0.0))
	var evasion: float = float((hazard as Dictionary).get("player_evasion_percent", 0.0))
	if not _is_finite_number(enemy_damage) or enemy_damage < -50.0 or enemy_damage > 200.0:
		_err("invalid_number", "%s hazard enemy_damage_percent %f must be in [-50,200]" % [label, enemy_damage])
	if not _is_finite_number(accuracy) or accuracy < -50.0 or accuracy > 50.0:
		_err("invalid_number", "%s hazard player_accuracy_percent %f must be in [-50,50]" % [label, accuracy])
	if not _is_finite_number(evasion) or evasion < -100.0 or evasion > 100.0:
		_err("invalid_number", "%s hazard player_evasion_percent %f must be in [-100,100]" % [label, evasion])

# ---------------- shop / settlement ----------------

func _check_shop() -> void:
	for id in DataLoader.shop.keys():
		var u: Dictionary = DataLoader.shop[id]
		if float(u.get("cost", 0)) < 0.0:
			_err("negative_value", "shop '%s' has negative cost" % id)
		for req in u.get("requires", []):
			if not DataLoader.shop.has(str(req)):
				_err("missing_reference", "shop '%s' requires unknown upgrade '%s'" % [id, req])
			if str(req) == id:
				_err("circular_dependency", "shop '%s' requires itself" % id)
		for skill_id in u.get("requires_skill", {}).keys():
			if not _has_skill(str(skill_id)):
				_err("missing_reference", "shop '%s' requires unknown skill '%s'" % [id, skill_id])
		var dungeon: String = str(u.get("requires_dungeon", ""))
		if dungeon != "" and not DataLoader.dungeons.has(dungeon):
			_err("missing_reference", "shop '%s' requires unknown dungeon '%s'" % [id, dungeon])
		var effect: Variant = u.get("effect", {})
		if typeof(effect) == TYPE_DICTIONARY:
			for key in (effect as Dictionary).keys():
				if not _is_finite_number(effect[key]):
					_err("invalid_number", "shop '%s' effect '%s' is not numeric" % [id, key])

	for id in DataLoader.township_buildings.keys():
		var b: Dictionary = DataLoader.township_buildings[id]
		var cost: Variant = b.get("cost", {})
		if typeof(cost) != TYPE_DICTIONARY or (cost as Dictionary).is_empty():
			_err("invalid_recipe", "township building '%s' has no cost" % id)
		else:
			for res in (cost as Dictionary).keys():
				if float(cost[res]) < 0.0:
					_err("negative_value", "township building '%s' cost '%s' is negative" % [id, res])

# ---------------- side systems ----------------

func _check_side_systems() -> void:
	for id in DataLoader.constellations.keys():
		var c: Dictionary = DataLoader.constellations[id]
		var seen: Dictionary = {}
		for star in c.get("stars", []):
			if typeof(star) != TYPE_DICTIONARY:
				_err("invalid_record", "constellation '%s' has a malformed star" % id)
				continue
			var sid: String = str(star.get("id", ""))
			if seen.has(sid):
				_err("duplicate_id", "constellation '%s' declares star '%s' twice" % [id, sid])
			seen[sid] = true
			if int(star.get("cost", 0)) < 0:
				_err("negative_value", "constellation '%s' star '%s' has negative cost" % [id, sid])

	for id in DataLoader.obstacles.keys():
		var o: Dictionary = DataLoader.obstacles[id]
		if str(o.get("type", "")).contains("pillar"):
			# Pillars (and their elite upgrades at level 120) are not placed in a numbered slot.
			if int(o.get("level_required", 0)) <= 0:
				_err("invalid_level", "agility pillar '%s' has no level requirement" % id)
		else:
			# Obstacle slots are numbered 1..SLOTS (AgilityManager iterates that range).
			var slot: int = int(o.get("slot", -1))
			if slot < 1 or slot > AgilityManager.SLOTS:
				_err("invalid_slot", "obstacle '%s' has slot %s outside 1..%d" % [id, str(o.get("slot")), AgilityManager.SLOTS])
		for mat in (o.get("cost_items", {}) as Dictionary).keys():
			if not _has_item(str(mat)):
				_err("missing_reference", "obstacle '%s' cost_items references unknown item '%s'" % [id, mat])

	for id in DataLoader.familiars.keys():
		var fam: Dictionary = DataLoader.familiars[id]
		var tablet: String = str(fam.get("tablet_item", ""))
		if tablet != "" and not _has_item(tablet):
			_err("missing_reference", "familiar '%s' tablet_item -> unknown item '%s'" % [id, tablet])
		var mark: String = str(fam.get("mark_item", ""))
		if mark != "" and not _has_item(mark):
			_err("missing_reference", "familiar '%s' mark_item -> unknown item '%s'" % [id, mark])
		for syn in fam.get("synergies", []):
			if typeof(syn) != TYPE_DICTIONARY:
				continue
			var partner: String = str(syn.get("familiar_id", syn.get("with", "")))
			if partner != "" and not DataLoader.familiars.has(partner):
				_err("missing_reference", "familiar '%s' synergy references unknown familiar '%s'" % [id, partner])

	for id in DataLoader.pets.keys():
		var p: Dictionary = DataLoader.pets[id]
		var src: String = str(p.get("source_skill", ""))
		if src != "" and not _has_skill(src):
			_err("missing_reference", "pet '%s' source_skill -> unknown skill '%s'" % [id, src])

	for id in DataLoader.prayers.keys():
		var pr: Dictionary = DataLoader.prayers[id]
		if int(pr.get("prayer_point_cost", 0)) < 0:
			_err("negative_value", "prayer '%s' has a negative point cost" % id)
		if not _has_skill("prayer"):
			_warn("missing_reference", "prayer '%s' exists but there is no prayer skill" % id)

	for id in DataLoader.harvesting_veins.keys():
		var v: Dictionary = DataLoader.harvesting_veins[id]
		if int(v.get("node_hp", 0)) <= 0:
			_err("invalid_quantity", "harvesting vein '%s' node_hp must be > 0" % id)
		if float(v.get("respawn_seconds", 0.0)) <= 0.0:
			_err("invalid_duration", "harvesting vein '%s' respawn_seconds must be > 0" % id)

	for id in DataLoader.cartography_hexes.keys():
		var h: Dictionary = DataLoader.cartography_hexes[id]
		if float(h.get("travel_cost", 0)) < 0.0:
			_err("negative_value", "hex '%s' has a negative travel_cost" % id)

	# Quests and achievements.
	for id in Quests.all_quest_ids():
		var q: Dictionary = Quests.get_quest(id)
		if (q.get("objectives", []) as Array).is_empty():
			_err("invalid_record", "quest '%s' has no objectives" % id)
		for obj in q.get("objectives", []):
			_check_objective("quest '%s'" % id, obj)
		_check_reward("quest '%s'" % id, q.get("reward", {}))
	for id in Achievements.all_ids():
		var a: Dictionary = Achievements.get_record(id)
		var cond: Variant = a.get("condition", {})
		if typeof(cond) != TYPE_DICTIONARY or (cond as Dictionary).is_empty():
			_err("invalid_record", "achievement '%s' has no condition" % id)
		else:
			_check_condition("achievement '%s'" % id, cond)
		_check_reward("achievement '%s'" % id, a.get("reward", {}))

func _check_objective(label: String, obj: Variant) -> void:
	if typeof(obj) != TYPE_DICTIONARY:
		_err("invalid_record", "%s has a malformed objective" % label)
		return
	var o: Dictionary = obj
	var kind: String = str(o.get("kind", ""))
	var known: Array[String] = ["have_item", "gain_item", "skill_level", "combat_level", "mastery_level", "kill_monster",
		"defeat_boss", "complete_dungeon", "craft_item", "do_actions", "reach_region",
		"buy_upgrade", "build_structure", "gp_total", "unlock_pet", "discover_items"]
	if not known.has(kind):
		_err("invalid_objective", "%s objective kind '%s' is unknown" % [label, kind])
		return
	if o.has("item_id") and not _has_item(str(o["item_id"])):
		_err("missing_reference", "%s objective references unknown item '%s'" % [label, str(o["item_id"])])
	if o.has("monster_id") and not DataLoader.monsters.has(str(o["monster_id"])):
		_err("missing_reference", "%s objective references unknown monster '%s'" % [label, str(o["monster_id"])])
	if o.has("dungeon_id") and not DataLoader.dungeons.has(str(o["dungeon_id"])):
		_err("missing_reference", "%s objective references unknown dungeon '%s'" % [label, str(o["dungeon_id"])])
	if o.has("action_id") and str(o.get("skill_id", "")) != "":
		if DataLoader.get_action(str(o["skill_id"]), str(o["action_id"])).is_empty():
			_err("missing_reference", "%s objective references unknown action '%s:%s'" % [label, str(o["skill_id"]), str(o["action_id"])])
	if o.has("skill_id") and not _has_skill(str(o["skill_id"])):
		_err("missing_reference", "%s objective references unknown skill '%s'" % [label, str(o["skill_id"])])
	if o.has("upgrade_id") and not DataLoader.shop.has(str(o["upgrade_id"])):
		_err("missing_reference", "%s objective references unknown shop upgrade '%s'" % [label, str(o["upgrade_id"])])
	if o.has("building_id") and not DataLoader.township_buildings.has(str(o["building_id"])):
		_err("missing_reference", "%s objective references unknown building '%s'" % [label, str(o["building_id"])])
	if float(o.get("required", 1)) <= 0.0:
		_err("invalid_quantity", "%s objective required must be > 0" % label)

func _check_condition(label: String, cond: Variant) -> void:
	if typeof(cond) != TYPE_DICTIONARY:
		return
	var c: Dictionary = cond
	var kind: String = str(c.get("kind", ""))
	var known: Array[String] = ["skill_level", "total_level", "item_count", "lifetime_item",
		"monsters_killed", "dungeons_cleared", "items_discovered", "gp_earned", "actions_completed",
		"quests_completed", "pets_unlocked", "settlement_buildings"]
	if not known.has(kind):
		_err("invalid_condition", "%s condition kind '%s' is unknown" % [label, kind])
		return
	if c.has("skill_id") and not _has_skill(str(c["skill_id"])):
		_err("missing_reference", "%s condition references unknown skill '%s'" % [label, str(c["skill_id"])])
	if c.has("item_id") and not _has_item(str(c["item_id"])):
		_err("missing_reference", "%s condition references unknown item '%s'" % [label, str(c["item_id"])])
	if float(c.get("value", 1)) <= 0.0:
		_err("invalid_quantity", "%s condition value must be > 0" % label)

func _check_reward(label: String, reward: Variant) -> void:
	if typeof(reward) != TYPE_DICTIONARY:
		return
	var r: Dictionary = reward
	for item_id in (r.get("items", {}) as Dictionary).keys():
		if not _has_item(str(item_id)):
			_err("missing_reference", "%s reward grants unknown item '%s'" % [label, item_id])
		if int(r["items"][item_id]) <= 0:
			_err("invalid_quantity", "%s reward item '%s' must be positive" % [label, item_id])
	for item_id in (r.get("unlock_items", {}) as Dictionary).keys():
		if not _has_item(str(item_id)):
			_err("missing_reference", "%s unlock_items references unknown item '%s'" % [label, item_id])
	if float(r.get("gp", 0.0)) < 0.0:
		_err("negative_value", "%s reward gp is negative" % label)
	for skill_id in (r.get("xp", {}) as Dictionary).keys():
		if not _has_skill(str(skill_id)):
			_err("missing_reference", "%s reward xp references unknown skill '%s'" % [label, skill_id])

# ---------------- coverage statistics ----------------

## Every item should have somewhere to come from and something to be used for.
func _check_acquisition_coverage() -> void:
	var sources: Dictionary = {}
	for skill_id in DataLoader.skills.keys():
		for a in DataLoader.get_skill_actions(skill_id):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			for out_id in (a.get("output_items", {}) as Dictionary).keys():
				sources[str(out_id)] = true
			for sec in a.get("secondary_outputs", []):
				if typeof(sec) == TYPE_DICTIONARY:
					sources[str(sec.get("item_id", ""))] = true
	# Being an ingredient is NOT a way to obtain something: if the only reference to an item is
	# that a recipe eats it, that recipe can never run. Marks are the one real exception — they are
	# awarded by the familiar's own skill actions rather than appearing as a table entry.
	for familiar_id in DataLoader.familiars.keys():
		var familiar: Dictionary = DataLoader.familiars[familiar_id]
		var mark: String = str(familiar.get("mark_item", ""))
		if mark != "":
			sources[mark] = true
	for monster_id in DataLoader.monsters.keys():
		for drop in (DataLoader.monsters[monster_id].get("loot_table", []) as Array):
			if typeof(drop) == TYPE_DICTIONARY and not bool(drop.get("is_currency", false)):
				sources[str(drop.get("item_id", ""))] = true
	for dungeon_id in DataLoader.dungeons.keys():
		var d: Dictionary = DataLoader.dungeons[dungeon_id]
		for bundle in [d.get("completion_reward", {}), d.get("rewards_first_clear", {})]:
			for item_id in (bundle.get("items", {}) as Dictionary).keys():
				sources[str(item_id)] = true
		# The signature shard a dungeon grants on every clear.
		var shard: String = str(d.get("shard_item", ""))
		if shard != "":
			sources[shard] = true
	# An item something else upgrades INTO is obtainable through that upgrade.
	for item_id in DataLoader.items.keys():
		var upgrade_to: String = str(DataLoader.items[item_id].get("upgrade_path", ""))
		if upgrade_to != "":
			sources[upgrade_to] = true
	# Items the mastery stall sells are bought, not found.
	for item_id in ShopManager.stall_item_ids():
		sources[str(item_id)] = true
	for id in DataLoader.shop.keys():
		for item_id in (DataLoader.shop[id].get("grants_items", {}) as Dictionary).keys():
			sources[str(item_id)] = true
	# Farming: a harvested crop is defined by the SEED item's product_item.
	for item_id in DataLoader.items.keys():
		var seed_item: Dictionary = DataLoader.items[item_id]
		if str(seed_item.get("item_type", "")) == "seed":
			var product: String = str(seed_item.get("product_item", ""))
			if product != "":
				sources[product] = true
	# Slayer shop: any item with a slayer coin price is purchasable.
	for item_id in DataLoader.items.keys():
		if int(DataLoader.items[item_id].get("slayer_cost", 0)) > 0:
			sources[str(item_id)] = true
	# Township trader: settlement stores exchanged for crates.
	for offer_id in DataLoader.trader.keys():
		var offer: Variant = DataLoader.trader[offer_id]
		if typeof(offer) != TYPE_DICTIONARY:
			continue
		var granted_any: String = str((offer as Dictionary).get("item_id", ""))
		if granted_any != "":
			sources[granted_any] = true
		for item_id in ((offer as Dictionary).get("grant_items", {}) as Dictionary).keys():
			sources[str(item_id)] = true
	# Archaeology dig-site tables.
	for site_id in DataLoader.archaeology_sites.keys():
		for artefact in (DataLoader.archaeology_sites[site_id].get("artefacts", []) as Array):
			if typeof(artefact) == TYPE_DICTIONARY:
				sources[str((artefact as Dictionary).get("item_id", ""))] = true
	# Raids award their alternate weapon pool.
	for item_id in (DataLoader.raid_shop.get("alt_items", []) as Array):
		sources[str(item_id)] = true
	# Quest and achievement rewards are real acquisition paths.
	for quest_id in Quests.all_quest_ids():
		var reward: Dictionary = Quests.get_quest(quest_id).get("reward", {})
		for item_id in (reward.get("items", {}) as Dictionary).keys():
			sources[str(item_id)] = true
		for item_id in (reward.get("unlock_items", {}) as Dictionary).keys():
			sources[str(item_id)] = true
	for achievement_id in Achievements.all_ids():
		var a_reward: Dictionary = Achievements.get_record(achievement_id).get("reward", {})
		for item_id in (a_reward.get("items", {}) as Dictionary).keys():
			sources[str(item_id)] = true

	var orphaned: int = 0
	for item_id in DataLoader.items.keys():
		if not sources.has(item_id):
			var it: Dictionary = DataLoader.items[item_id]
			# Tokens, currencies and quest-only rewards are legitimately rare.
			if str(it.get("item_type", "")) in ["currency"]:
				continue
			orphaned += 1
			_warn("no_acquisition_path", "item '%s' (%s) has no known acquisition source" % [item_id, str(it.get("name", ""))])
	if orphaned > 0:
		_info("coverage", "%d items have no acquisition path" % orphaned)

func _info(code: String, message: String) -> void:
	_add("info", code, message)

# ---------------- reporting ----------------

func count_by_severity(severity: String) -> int:
	var n: int = 0
	for i in issues:
		if i["severity"] == severity:
			n += 1
	return n

func summary_line() -> String:
	return "%d errors, %d warnings, %d notes" % [
		count_by_severity("error"), count_by_severity("warning"), count_by_severity("info")]

func format_report(include_info: bool = true) -> String:
	var lines: Array[String] = []
	lines.append("=== content validation: %s ===" % summary_line())
	for sev in ["error", "warning", "info"]:
		if sev == "info" and not include_info:
			continue
		var group: Array = []
		for i in issues:
			if i["severity"] == sev:
				group.append(i)
		if group.is_empty():
			continue
		lines.append("--- %s (%d)" % [sev.to_upper(), group.size()])
		for i in group:
			lines.append("  [%s] %s" % [i["code"], i["message"]])
	return "\n".join(lines)
