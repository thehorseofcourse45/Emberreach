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
const EQUIPMENT_SLOT_NAMES: Dictionary = {
	0: "helmet", 1: "platebody", 2: "platelegs", 3: "boots", 4: "gloves", 5: "cape",
	6: "amulet", 7: "ring", 8: "weapon", 9: "shield", 10: "quiver", 11: "summon_1",
	12: "summon_2", 13: "passive", 14: "consumable",
}
## The ONLY keys a game mode may declare. This list is the contract: a mode flag has to be
## read by real code, and the player-facing `description` has to state what that code does.
## Adding a key to data/game_modes.json without adding it here (with code that honours it)
## fails validation, so a mode can never quietly promise behaviour the game does not implement.
const HONOURED_MODE_FLAGS: Array[String] = [
	# presentation, shown verbatim in the mode picker
	"id", "name", "description",
	# honoured by PlayerData.get_level_cap()
	"skill_level_cap", "non_combat_level_capped_by_combat_level",
	# honoured by BankManager.get_slot_limit()
	"bank_limit",
	# honoured by CombatFormulas.triangle() via the mode config
	"advantage_accuracy", "advantage_damage", "disadvantage_accuracy", "disadvantage_damage",
]
## Words that would re-introduce a promise the game cannot keep. Death is never permanent:
## nothing in this game deletes a character, so no mode may claim it.
const FORBIDDEN_MODE_CLAIMS: Array[String] = ["permanent", "deleted", "unrecoverable", "lost forever"]

var issues: Array = []

func validate_all() -> Array:
	issues.clear()
	_check_ids()
	_check_items()
	_check_skills_and_recipes()
	_check_recipe_graph()
	_check_monsters()
	_check_regions()
	_check_shop()
	_check_game_modes()
	_check_side_systems()
	_check_new_skill_systems()
	_check_ascendancy()
	_check_audio()
	_check_acquisition_coverage()
	_check_output_demand()
	_check_bottlenecks()
	return issues

# ---------------- helpers ----------------

func _add(severity: String, code: String, message: String) -> void:
	issues.append({"severity": severity, "code": code, "message": message})

func _has_item(id: String) -> bool:
	return DataLoader.items.has(id)

func _has_skill(id: String) -> bool:
	return DataLoader.skills.has(id)

func _err(code: String, msg: String) -> void:
	_add("error", code, msg)

func _warn(code: String, msg: String) -> void:
	_add("warning", code, msg)

func _is_finite_number(v: Variant) -> bool:
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
		["special_attack", DataLoader.special_attacks], ["cartography_hex", DataLoader.cartography_hexes],
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
			if it.has("spell_max_hit"):
				if not _is_finite_number(it["spell_max_hit"]):
					_err("invalid_number", "item '%s' spell_max_hit is not a number" % id)
				elif float(it["spell_max_hit"]) <= 0.0:
					_err("negative_value", "item '%s' has a non-positive spell_max_hit" % id)
			var cost: Variant = it.get("attack_cost_items", {})
			if typeof(cost) != TYPE_DICTIONARY:
				_err("invalid_record", "item '%s' attack_cost_items is not an object" % id)
			else:
				for cost_id in (cost as Dictionary).keys():
					if not _has_item(str(cost_id)):
						_err("missing_reference", "item '%s' attack_cost_items references unknown item '%s'" % [id, cost_id])
					elif int((cost as Dictionary)[cost_id]) <= 0:
						_err("negative_value", "item '%s' attack_cost_items spends a non-positive amount of '%s'" % [id, cost_id])
				# A tiered bow's default arrow is the best it can loose; a cap with no arrow at that
				# tier, or a default of a different tier, would make the cap and the cost disagree.
				var cap: int = int(it.get("ammo_tier_max", 0))
				if cap > 0:
					var tiers: Array = []
					for cost_id in (cost as Dictionary).keys():
						if _has_item(str(cost_id)) and str(DataLoader.get_item(str(cost_id)).get("item_type", "")) == "ammo":
							tiers.append(int(DataLoader.get_item(str(cost_id)).get("ammo_tier", 0)))
					if tiers != [cap]:
						_err("invalid_record", "item '%s' has ammo_tier_max %d but its default arrow is tier %s" % [id, cap, str(tiers)])
		if type == "ammo" and it.has("ammo_tier") and int(it.get("ammo_tier", 0)) <= 0:
			_err("negative_value", "ammo '%s' has a non-positive ammo_tier" % id)
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
		var research: String = str(a.get("research_unlock", ""))
		var unlocks_recipe: bool = false
		if skill_id == "inscription" and research != "":
			for recipe in DataLoader.get_skill_actions(skill_id):
				if str(recipe.get("requires_research", "")) == research:
					unlocks_recipe = true
		if not unlocks_recipe:
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
	if a.has("ward"):
		var ward: Variant = a["ward"]
		if typeof(ward) != TYPE_DICTIONARY:
			_err("invalid_record", "%s ward is not an object" % label)
		elif skill_id != "alt_magic":
			_err("invalid_record", "%s carries a ward, but only Runescribing casts wards" % label)
		else:
			var mods: Variant = (ward as Dictionary).get("mods", {})
			if typeof(mods) != TYPE_DICTIONARY or (mods as Dictionary).is_empty():
				_err("invalid_record", "%s ward has no modifiers" % label)
			else:
				for key in (mods as Dictionary).keys():
					if not _is_finite_number((mods as Dictionary)[key]):
						_err("invalid_number", "%s ward modifier '%s' is not a number" % [label, key])
			var seconds: float = float((ward as Dictionary).get("seconds", 0.0))
			var cap: float = float((ward as Dictionary).get("max_seconds", 0.0))
			if seconds <= 0.0 or cap < seconds:
				_err("invalid_duration", "%s ward needs seconds > 0 and max_seconds >= seconds" % label)
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
		for mech_msg in validate_monster_mechanics(str(id), m):
			_err("invalid_record", mech_msg)
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
	# A special attack no monster carries is content nobody can ever see. Three of the fourteen
	# sat unused behind an authoring mistake; only an unused-attack check would have caught it.
	var carried: Dictionary = {}
	for id in DataLoader.monsters.keys():
		for sa in (DataLoader.monsters[id] as Dictionary).get("special_attacks", []):
			carried[str(sa)] = true
	for sa_id in DataLoader.special_attacks.keys():
		if not carried.has(str(sa_id)):
			_warn("unused_special_attack", "special attack '%s' is not carried by any monster" % sa_id)

## Checks the monster-mechanics schema (weak_to / resists / phases). Static so tests can feed
## in-memory records; returns one message per problem.
static func validate_monster_mechanics(monster_id: String, m: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var label := "monster:%s" % monster_id
	for key in ["weak_to", "resists"]:
		var list: Variant = m.get(key, [])
		if typeof(list) != TYPE_ARRAY:
			errs.append("%s %s must be an array" % [label, key])
			continue
		var seen: Array = []
		for style in list:
			if not MonsterMechanics.STYLES.has(str(style)):
				errs.append("%s %s has invalid style '%s'" % [label, key, style])
			elif seen.has(style):
				errs.append("%s %s lists style '%s' twice" % [label, key, style])
			seen.append(style)
	if typeof(m.get("weak_to", [])) == TYPE_ARRAY and typeof(m.get("resists", [])) == TYPE_ARRAY:
		for style in m.get("weak_to", []):
			if (m.get("resists", []) as Array).has(style):
				errs.append("%s style '%s' is in both weak_to and resists" % [label, style])
	if not m.has("phases"):
		return errs
	var phases: Variant = m["phases"]
	if typeof(phases) != TYPE_ARRAY:
		errs.append("%s phases must be an array" % label)
		return errs
	var prev: int = 100
	for i in range((phases as Array).size()):
		var ph: Variant = phases[i]
		var plabel := "%s phase %d" % [label, i]
		if typeof(ph) != TYPE_DICTIONARY:
			errs.append("%s must be a dictionary" % plabel)
			continue
		var raw_pct: Variant = ph.get("at_hp_percent", 0)
		var pct: int = int(raw_pct)
		if (typeof(raw_pct) != TYPE_INT and not (typeof(raw_pct) == TYPE_FLOAT and float(raw_pct) == floorf(float(raw_pct)))):
			errs.append("%s at_hp_percent must be an integer" % plabel)
			continue
		if str(ph.get("name", "")).strip_edges() == "":
			errs.append("%s needs a non-empty name" % plabel)
		if pct < 1 or pct > 99:
			errs.append("%s at_hp_percent %d must be in 1-99" % [plabel, pct])
		elif pct >= prev:
			errs.append("%s at_hp_percent %d must be strictly below the previous phase" % [plabel, pct])
		else:
			prev = pct
		var fx: Variant = ph.get("effects", {})
		if typeof(fx) != TYPE_DICTIONARY:
			errs.append("%s effects must be a dictionary" % plabel)
			continue
		for k in fx.keys():
			if not MonsterMechanics.PHASE_EFFECT_KEYS.has(str(k)):
				errs.append("%s has unknown effect '%s'" % [plabel, k])
		if fx.has("attack_speed_multiplier"):
			var a: float = float(fx["attack_speed_multiplier"])
			if a < 0.5 or a > 2.0:
				errs.append("%s attack_speed_multiplier %f must be in [0.5,2.0]" % [plabel, a])
		if fx.has("max_hit_multiplier"):
			var h: float = float(fx["max_hit_multiplier"])
			if h < 0.5 or h > 3.0:
				errs.append("%s max_hit_multiplier %f must be in [0.5,3.0]" % [plabel, h])
		if fx.has("add_passives"):
			if typeof(fx["add_passives"]) != TYPE_ARRAY:
				errs.append("%s add_passives must be an array" % plabel)
			else:
				for p in fx["add_passives"]:
					if not CombatManager.KNOWN_MONSTER_PASSIVES.has(str(p)):
						errs.append("%s add_passives has unknown passive '%s'" % [plabel, p])
		if fx.has("attack_type") and not VALID_MONSTER_ATTACK_TYPES.has(str(fx["attack_type"])):
			errs.append("%s attack_type '%s' is invalid" % [plabel, fx["attack_type"]])
		if fx.has("apply_status"):
			var st: Variant = fx["apply_status"]
			if typeof(st) != TYPE_DICTIONARY or not StatusEffect.TABLE.has(str(st.get("id", ""))):
				errs.append("%s apply_status has unknown status id" % plabel)
			else:
				if float(st.get("duration", 1.0)) <= 0.0:
					errs.append("%s apply_status duration must be > 0" % plabel)
				if float(st.get("damage_per_tick", 0.0)) < 0.0:
					errs.append("%s apply_status damage_per_tick must be >= 0" % plabel)
	return errs

# ---------------- regions ----------------

func _check_regions() -> void:
	# A monster outside every region cannot be fought at all: its drops, its slayer task and its
	# flavour text are all unreachable, so an orphan is a content bug rather than a style choice.
	var placed: Dictionary = {}
	for id in DataLoader.areas.keys():
		var a: Dictionary = DataLoader.areas[id]
		if (a.get("monsters", []) as Array).is_empty():
			_warn("empty_region", "area '%s' contains no monsters" % id)
		for mid in a.get("monsters", []):
			if not DataLoader.monsters.has(str(mid)):
				_err("missing_reference", "area '%s' lists unknown monster '%s'" % [id, mid])
			else:
				placed[str(mid)] = true
		_check_hazard("area '%s'" % id, a.get("hazard", {}))
		_check_region_requirements("area", id, a)
	for id in DataLoader.dungeons.keys():
		var d: Dictionary = DataLoader.dungeons[id]
		if (d.get("monsters", []) as Array).is_empty():
			_err("empty_region", "dungeon '%s' has no encounter list" % id)
		for mid in d.get("monsters", []):
			if not DataLoader.monsters.has(str(mid)):
				_err("missing_reference", "dungeon '%s' lists unknown monster '%s'" % [id, mid])
			else:
				placed[str(mid)] = true
		_check_region_requirements("dungeon", id, d)
	for mid in DataLoader.monsters.keys():
		if not placed.has(str(mid)):
			_warn("orphan_monster", "monster '%s' appears in no area or dungeon, so it can never be fought" % mid)

func _check_region_requirements(kind: String, id: String, row: Dictionary) -> void:
	var reqs: Variant = row.get("requires", {})
	if typeof(reqs) == TYPE_DICTIONARY:
		for skill_id in reqs.keys():
			if not _has_skill(str(skill_id)):
				_err("missing_reference", "%s '%s' requires unknown skill '%s'" % [kind, id, skill_id])
			elif int(reqs[skill_id]) > int(DataLoader.get_skill(str(skill_id)).get("max_level", 120)):
				_err("unreachable_unlock", "%s '%s' requires %s %d above the skill cap" % [kind, id, skill_id, int(reqs[skill_id])])
	var prev: String = str(row.get("requires_dungeon", ""))
	if prev != "":
		if not DataLoader.dungeons.has(prev):
			_err("missing_reference", "%s '%s' requires unknown dungeon '%s'" % [kind, id, prev])
		elif prev == id:
			_err("circular_dependency", "%s '%s' requires itself" % [kind, id])
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

# ---------------- game modes ----------------

## A mode flag only earns its place if some code reads it, and a mode's description is shown
## verbatim to the player, so it may not claim behaviour the game lacks. The check is a key
## allowlist rather than static analysis of the scripts: HONOURED_MODE_FLAGS is the human
## statement of "these are the flags the game honours", and a new key has to be added there
## together with the code that reads it.
func _check_game_modes() -> void:
	var modes: Dictionary = DataLoader.game_modes
	if modes.is_empty():
		_err("missing_content", "game_modes.json is missing or empty")
		return
	for mode_id in modes.keys():
		var mode_id_str: String = str(mode_id)
		if mode_id_str.begins_with("_"):
			continue   # document-level comment, not a mode
		var mode: Variant = modes[mode_id]
		if typeof(mode) != TYPE_DICTIONARY:
			_err("invalid_record", "game mode '%s' is not an object" % mode_id_str)
			continue
		for key in (mode as Dictionary).keys():
			if not HONOURED_MODE_FLAGS.has(str(key)):
				_err("unhonoured_mode_flag", "game mode '%s' declares '%s', which no script reads. "
					% [mode_id_str, key] + "Implement it and add it to HONOURED_MODE_FLAGS, or delete it.")
		var m: Dictionary = mode as Dictionary
		if str(m.get("id", "")) != mode_id_str:
			_err("invalid_record", "game mode '%s' declares id '%s'" % [mode_id_str, str(m.get("id", ""))])
		var description: String = str(m.get("description", ""))
		if description == "":
			_err("invalid_record", "game mode '%s' has no description for the mode picker" % mode_id_str)
		var haystack: String = ("%s %s" % [str(m.get("name", "")), description]).to_lower()
		for claim in FORBIDDEN_MODE_CLAIMS:
			if haystack.contains(claim):
				_err("false_mode_claim", "game mode '%s' claims '%s', which this game never does"
					% [mode_id_str, claim])

# ---------------- audio ----------------

## Audio is data, but its references cross into code (EventBus signal names), so the
## join has to be checked here: a typo'd signal in audio.json would otherwise fail
## silently as a sound that never plays.
func _check_audio() -> void:
	var audio: Dictionary = DataLoader.audio
	if audio.is_empty():
		_err("missing_audio", "audio.json is missing or empty")
		return
	var sfx: Dictionary = audio.get("sfx", {})
	if sfx.is_empty():
		_err("missing_audio", "audio.json defines no sound effects")
	for sound_id in sfx.keys():
		var recipe: Variant = sfx[sound_id]
		if typeof(recipe) != TYPE_DICTIONARY:
			_err("invalid_record", "sound '%s' is not an object" % sound_id)
			continue
		var tones: Array = (recipe as Dictionary).get("tones", [])
		if tones.is_empty():
			_err("invalid_record", "sound '%s' has no tones" % sound_id)
			continue
		for i in range(tones.size()):
			var tone: Variant = tones[i]
			if typeof(tone) != TYPE_DICTIONARY or float((tone as Dictionary).get("freq", 0.0)) <= 0.0:
				_err("invalid_value", "sound '%s' tone %d needs a positive freq" % [sound_id, i])
			elif float((tone as Dictionary).get("dur", 0.0)) <= 0.0:
				_err("invalid_value", "sound '%s' tone %d needs a positive dur" % [sound_id, i])
	var events: Dictionary = audio.get("events", {})
	for signal_name in events.keys():
		if not EventBus.has_signal(str(signal_name)):
			_err("unknown_signal", "audio event '%s' is not an EventBus signal" % signal_name)
		var spec: Variant = events[signal_name]
		var sound_id: String = ""
		if typeof(spec) == TYPE_STRING:
			sound_id = str(spec)
		elif typeof(spec) == TYPE_DICTIONARY:
			sound_id = str((spec as Dictionary).get("sound", ""))
		if sound_id != "" and not sfx.has(sound_id):
			_err("unknown_sound", "audio event '%s' references missing sound '%s'" % [signal_name, sound_id])
	var note_table: Dictionary = audio.get("notification_sounds", {})
	for kind in note_table.keys():
		if str(kind).begins_with("_"):
			continue
		if not sfx.has(str(note_table[kind])):
			_err("unknown_sound", "notification kind '%s' references missing sound '%s'" % [kind, note_table[kind]])

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

	# A pet is only ever unlocked by PetManager, which matches "source_skill" against a real skill
	# id (or the literal "combat"), "source_dungeon" against a cleared expedition, or
	# "source_item" against a container that is opened from Storage. Any other key or value is
	# content that can never be unlocked, so it is an error, not a warning.
	for id in DataLoader.pets.keys():
		var p: Dictionary = DataLoader.pets[id]
		if p.has("source"):
			_err("invalid_record", "pet '%s' uses the key 'source'; PetManager reads 'source_skill', 'source_dungeon' or 'source_item'" % id)
		var src_skill: String = str(p.get("source_skill", ""))
		var src_dungeon: String = str(p.get("source_dungeon", ""))
		var src_item: String = str(p.get("source_item", ""))
		if src_skill == "" and src_dungeon == "" and src_item == "":
			_err("unreachable_unlock", "pet '%s' declares no source_skill, source_dungeon or source_item" % id)
		if src_skill != "" and src_skill != "combat" and not _has_skill(src_skill):
			_err("missing_reference", "pet '%s' source_skill -> unknown skill '%s'" % [id, src_skill])
		if src_dungeon != "" and not DataLoader.dungeons.has(src_dungeon):
			_err("missing_reference", "pet '%s' source_dungeon -> unknown dungeon '%s'" % [id, src_dungeon])
		if src_item != "" and not _has_item(src_item):
			_err("missing_reference", "pet '%s' source_item -> unknown item '%s'" % [id, src_item])

	# Containers are opened from Storage: the crate itself is spent and its contents are handed
	# over through the guaranteed path. A dangling entry would spend the crate for nothing.
	for id in DataLoader.items.keys():
		var container: Dictionary = DataLoader.items[id]
		var contents: Variant = container.get("container_items", {})
		if typeof(contents) != TYPE_DICTIONARY:
			_err("invalid_record", "item '%s' container_items is not an object" % id)
		else:
			for grant in (contents as Dictionary).keys():
				if not _has_item(str(grant)):
					_err("missing_reference", "item '%s' container_items -> unknown item '%s'" % [id, grant])
				elif int((contents as Dictionary)[grant]) <= 0:
					_err("invalid_quantity", "item '%s' container_items grants a non-positive amount of '%s'" % [id, grant])
		var hatch: String = str(container.get("container_pet", ""))
		if hatch != "" and not DataLoader.pets.has(hatch):
			_err("missing_reference", "item '%s' container_pet -> unknown pet '%s'" % [id, hatch])

	for id in DataLoader.prayers.keys():
		var pr: Dictionary = DataLoader.prayers[id]
		if int(pr.get("prayer_point_cost", 0)) < 0:
			_err("negative_value", "prayer '%s' has a negative point cost" % id)
		if not _has_skill("prayer"):
			_warn("missing_reference", "prayer '%s' exists but there is no prayer skill" % id)

	# Vein richness tiers (SkillManager._roll_richness): a zero weight or multiplier would make a
	# tier unreachable or a node with no uses.
	for skill_id in DataLoader.skills.keys():
		for t in (DataLoader.skills[skill_id].get("vein_richness", []) as Array):
			if typeof(t) != TYPE_DICTIONARY or float(t.get("weight", 0.0)) <= 0.0 \
					or float(t.get("hp_mult", 0.0)) <= 0.0 or float(t.get("xp_mult", 0.0)) <= 0.0:
				_err("invalid_record", "skill '%s' has a vein_richness tier without positive weight/hp_mult/xp_mult" % skill_id)

	for id in DataLoader.cartography_hexes.keys():
		var h: Dictionary = DataLoader.cartography_hexes[id]
		if float(h.get("travel_cost", 0)) < 0.0:
			_err("negative_value", "hex '%s' has a negative travel_cost" % id)

	# Slayer task pools: the completion reward is the monster's slayer_xp × the tier
	# multiplier, so a pool monster with no slayer_xp pays nothing for a whole task.
	var pools: Dictionary = DataLoader.slayer_tasks.get("_monsters", {})
	for tier_id in DataLoader.slayer_tasks.keys():
		if str(tier_id).begins_with("_"):
			continue
		var tier: Variant = DataLoader.slayer_tasks[tier_id]
		if typeof(tier) != TYPE_DICTIONARY:
			continue
		var min_kills: int = int((tier as Dictionary).get("min_kills", 1))
		var max_kills: int = int((tier as Dictionary).get("max_kills", 1))
		if min_kills < 1 or max_kills < min_kills:
			_err("invalid_record", "slayer tier '%s' has kills range %d..%d" % [tier_id, min_kills, max_kills])
		# SlayerManager refuses a tier above the player's Slayer level, and that level cannot pass
		# the skill cap, so a requirement above the cap is a tier nobody can ever take.
		var slayer_cap: int = int(DataLoader.get_skill("slayer").get("max_level", XPTable.MAX_LEVEL))
		if int((tier as Dictionary).get("level_required", 1)) > slayer_cap:
			_err("unreachable_unlock", "slayer tier '%s' requires level %d above the slayer cap of %d"
				% [tier_id, int((tier as Dictionary).get("level_required", 1)), slayer_cap])
		var pool: Variant = (pools as Dictionary).get(tier_id, [])
		if typeof(pool) != TYPE_ARRAY or (pool as Array).is_empty():
			_warn("invalid_record", "slayer tier '%s' has an empty monster pool" % tier_id)
			continue
		for monster_id in (pool as Array):
			var mid := str(monster_id)
			if not DataLoader.monsters.has(mid):
				_err("missing_reference", "slayer tier '%s' pool references unknown monster '%s'" % [tier_id, mid])
			elif float((DataLoader.monsters[mid] as Dictionary).get("slayer_xp", 0)) <= 0.0:
				_err("invalid_record", "slayer tier '%s' pool monster '%s' has slayer_xp <= 0, so the task would pay nothing" % [tier_id, mid])
		# A tier with one monster is not a choice: every assignment from it is the same fight,
		# which is what left Master and Legendary as single-monster pools.
		if (pool as Array).size() < 2:
			_warn("thin_slayer_pool", "slayer tier '%s' offers only one monster to hunt" % tier_id)
		# Expedition tasks: the dungeon must exist and the clears range must be sane.
		var dpool: Variant = (DataLoader.slayer_tasks.get("_dungeons", {}) as Dictionary).get(tier_id, [])
		if typeof(dpool) == TYPE_ARRAY and not (dpool as Array).is_empty():
			var min_clears: int = int((tier as Dictionary).get("min_clears", 1))
			var max_clears: int = int((tier as Dictionary).get("max_clears", 3))
			if min_clears < 1 or max_clears < min_clears:
				_err("invalid_record", "slayer tier '%s' has clears range %d..%d" % [tier_id, min_clears, max_clears])
			for dungeon_id in (dpool as Array):
				if not DataLoader.dungeons.has(str(dungeon_id)):
					_err("missing_reference", "slayer tier '%s' lists unknown expedition '%s'" % [tier_id, dungeon_id])

	# Museum stock: token costs must be positive and grants must be real items.
	for entry_id in DataLoader.shop_museum.keys():
		var entry: Variant = DataLoader.shop_museum[entry_id]
		if typeof(entry) != TYPE_DICTIONARY:
			_err("invalid_record", "museum entry '%s' is not an object" % entry_id)
			continue
		if str((entry as Dictionary).get("id", entry_id)) != str(entry_id):
			_err("invalid_record", "museum entry '%s' declares id '%s'" % [entry_id, str((entry as Dictionary).get("id", ""))])
		if int((entry as Dictionary).get("cost", 0)) <= 0:
			_err("invalid_record", "museum entry '%s' has a non-positive token cost" % entry_id)
		if float((entry as Dictionary).get("gp", 0)) < 0.0:
			_err("negative_value", "museum entry '%s' grants negative GP" % entry_id)
		for item_id in ((entry as Dictionary).get("grant_items", {}) as Dictionary).keys():
			if not _has_item(str(item_id)):
				_err("missing_reference", "museum entry '%s' grants unknown item '%s'" % [entry_id, str(item_id)])

	# Cartography ships: a contiguous upgrade chain where every hull discounts travel.
	var ship_orders: Dictionary = {}
	for ship_id in DataLoader.cartography_ships.keys():
		var ship: Variant = DataLoader.cartography_ships[ship_id]
		if typeof(ship) != TYPE_DICTIONARY:
			_err("invalid_record", "ship '%s' is not an object" % ship_id)
			continue
		if str((ship as Dictionary).get("id", ship_id)) != str(ship_id):
			_err("invalid_record", "ship '%s' declares id '%s'" % [ship_id, str((ship as Dictionary).get("id", ""))])
		var order: int = int((ship as Dictionary).get("order", 0))
		if order < 1:
			_err("invalid_record", "ship '%s' has order %d (must be >= 1)" % [ship_id, order])
		elif ship_orders.has(order):
			_err("duplicate_id", "ships '%s' and '%s' share order %d" % [str(ship_orders[order]), ship_id, order])
		else:
			ship_orders[order] = ship_id
		var pct := float((ship as Dictionary).get("travel_cost_percent", 100.0))
		if pct <= 0.0 or pct > 100.0:
			_err("invalid_number", "ship '%s' travel_cost_percent %s must be in (0, 100]" % [ship_id, str(pct)])
		if float((ship as Dictionary).get("cost", 0)) < 0.0:
			_err("negative_value", "ship '%s' has a negative cost" % ship_id)
	if not ship_orders.is_empty():
		var expected_order: int = 1
		var sorted_orders: Array = ship_orders.keys()
		sorted_orders.sort()
		for existing_order in sorted_orders:
			if int(existing_order) != expected_order:
				_err("invalid_record", "ship upgrade chain must be contiguous from 1; order %d is missing" % expected_order)
				break
			expected_order += 1

	# Quests and achievements.
	for id in Quests.all_quest_ids():
		var q: Dictionary = Quests.get_quest(id)
		if (q.get("objectives", []) as Array).is_empty():
			_err("invalid_record", "quest '%s' has no objectives" % id)
		for obj in q.get("objectives", []):
			_check_objective("quest '%s'" % id, obj)
		_check_reward("quest '%s'" % id, q.get("reward", {}))
		var difficulty: String = str(q.get("difficulty", ""))
		if not Quests.DIFFICULTIES.has(difficulty):
			_err("invalid_record", "quest '%s' has unknown difficulty '%s'" % [id, difficulty])
	for id in Quests.rotating_pool_ids():
		var rq: Dictionary = Quests.get_quest(id)
		if not (rq.get("prerequisites", []) as Array).is_empty() or not (rq.get("requires", {}) as Dictionary).is_empty():
			_err("invalid_record", "rotating task '%s' must not be gated by prerequisites" % id)
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
	if c.has("monster_id") and not DataLoader.monsters.has(str(c["monster_id"])):
		_err("missing_reference", "%s condition references unknown monster '%s'" % [label, str(c["monster_id"])])
	if c.has("dungeon_id") and not DataLoader.dungeons.has(str(c["dungeon_id"])):
		_err("missing_reference", "%s condition references unknown dungeon '%s'" % [label, str(c["dungeon_id"])])
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
	# The provisioner's shelves live in shop_store.json. This read `DataLoader.shop` — the GP
	# upgrade catalogue — so all forty shelves stayed invisible even after the `item_id` form was
	# taught to this check. `item_id` names a single item; only bundles use `grants_items`.
	for id in DataLoader.shop_store.keys():
		var shelf: Variant = DataLoader.shop_store[id]
		if typeof(shelf) != TYPE_DICTIONARY:
			continue
		var shelf_item: String = str((shelf as Dictionary).get("item_id", ""))
		if shelf_item != "":
			sources[shelf_item] = true
		for item_id in ((shelf as Dictionary).get("grants_items", {}) as Dictionary).keys():
			sources[str(item_id)] = true
	# The museum's curios are bought with tokens, and the Dream Bazaar with dream essence: both
	# hand over real items, and neither was counted as a source of anything.
	for curio_id in DataLoader.shop_museum.keys():
		var curio: Variant = DataLoader.shop_museum[curio_id]
		if typeof(curio) != TYPE_DICTIONARY:
			continue
		for item_id in ((curio as Dictionary).get("grant_items", {}) as Dictionary).keys():
			sources[str(item_id)] = true
	for offer in (DataLoader.new_skill_systems.get("bazaar", []) as Array):
		if typeof(offer) == TYPE_DICTIONARY:
			for item_id in ((offer as Dictionary).get("items", {}) as Dictionary).keys():
				sources[str(item_id)] = true
	# Farming: a harvested crop is defined by the SEED item's product_item.
	for item_id in DataLoader.items.keys():
		var seed_item: Dictionary = DataLoader.items[item_id]
		if str(seed_item.get("item_type", "")) == "seed":
			var product: String = str(seed_item.get("product_item", ""))
			if product != "":
				sources[product] = true
	# Ranching: the species table IS the source. A pen yields the stock it was raised from, its
	# produce, its hide and its meat, and the system's own code adds feed (rendered from crops),
	# manure (a per-cycle byproduct) and the two rare breeding variants.
	for species_def in (DataLoader.new_skill_systems.get("species", []) as Array):
		if typeof(species_def) != TYPE_DICTIONARY:
			continue
		var animal: Dictionary = species_def
		for field in ["stock", "produce", "hide"]:
			var granted: String = str(animal.get(field, ""))
			if granted != "":
				sources[granted] = true
		if int(animal.get("meat", 0)) > 0:
			sources["ranch_meat"] = true
	for system_item in ["ranch_feed", "ranch_manure", "golden_hen_stock", "mooncalf_stock"]:
		if DataLoader.items.has(system_item):
			sources[system_item] = true
	# Enchanting: recycling equipment yields one essence per enchant family, keyed by the `essence`
	# field on the enchant definitions.
	for enchant_def in (DataLoader.new_skill_systems.get("enchants", []) as Array):
		if typeof(enchant_def) != TYPE_DICTIONARY:
			continue
		var essence: String = str((enchant_def as Dictionary).get("essence", ""))
		if essence == "":
			continue
		var essence_item: String = "enchant_" + essence + "_essence"
		if DataLoader.items.has(essence_item):
			sources[essence_item] = true
	# Inscription: a recipe with a `quality_product` ships three graded variants of it, picked by
	# the roll in InscriptionManager.quality_outputs.
	for skill_id in DataLoader.get_skill_ids():
		for action in DataLoader.get_skill_actions(skill_id):
			if typeof(action) != TYPE_DICTIONARY:
				continue
			var quality_product: String = str((action as Dictionary).get("quality_product", ""))
			if quality_product == "":
				continue
			for quality in ["inked", "faded", "illuminated"]:
				sources["%s_%s" % [quality_product, quality]] = true
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
	# A failed action that names a failure output produces it: burnt food is a real source.
	for skill_id in DataLoader.get_skill_ids():
		for action in DataLoader.get_skill_actions(skill_id):
			if typeof(action) != TYPE_DICTIONARY:
				continue
			var fail_item: String = str((action as Dictionary).get("fail_output_item", ""))
			if fail_item != "":
				sources[fail_item] = true
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
	# This table is the superset; the detail pane is where the player actually asks "where do I get
	# this?", and it reads Goals. Teaching one and not the other is how eighty obtainable items came
	# to be described on their own card as unfinished content, so the two are compared here.
	var unexplained: int = 0
	for item_id in sources.keys():
		var id: String = str(item_id)
		if not DataLoader.items.has(id) or not Goals.sources_for_item(id).is_empty():
			continue
		unexplained += 1
		_warn("unexplained_source", "item '%s' (%s) is obtainable but the detail pane cannot say where from" % [
			id, str(DataLoader.get_item(id).get("name", ""))])
	if unexplained > 0:
		_info("coverage", "%d obtainable items have no route on their card" % unexplained)

## Symmetry with _check_acquisition_coverage: that one asks how every item is OBTAINED, this
## one asks what every item is for. An item that is handed to the player and then spent by
## nothing is content that only exists to be sold, which is fine when it is declared (the
## `terminal_reason` field on the item) and a gap when it is not.
func _check_output_demand() -> void:
	var demand: Dictionary = BalanceReport.dead_outputs()
	for item_id in (demand["undeclared"] as Array):
		_warn("dead_output", "item '%s' (%s) is obtainable but nothing consumes it" % [
			str(item_id), str(DataLoader.get_item(str(item_id)).get("name", ""))])
	for item_id in (demand["stale_declarations"] as Array):
		_warn("stale_declaration", "item '%s' declares terminal_reason but content does consume it" % str(item_id))
	# A channel that matches nothing means the field it reads was renamed or removed, which would
	# silently excuse every dead item that channel used to catch.
	var used: Dictionary = BalanceReport.consumed_item_ids()
	var seen: Dictionary = {}
	for reasons in used.values():
		for reason in (reasons as Array):
			seen[str(reason).split(":")[0]] = true
	for channel in BalanceReport.DEMAND_CHANNELS:
		if not seen.has(channel):
			_err("dead_channel", "the '%s' demand channel matches no item — a field it reads was renamed" % channel)
	# Demand is a claim that something spends an item. A key that is not an item means a channel is
	# reading a namespace that only looks like items — the settlement trader's costs are township
	# resources — and the report then prints a material with demand, no route and no existence.
	var phantom: Array[String] = []
	for item_id in used.keys():
		if not DataLoader.items.has(str(item_id)):
			phantom.append(str(item_id))
	if not phantom.is_empty():
		_err("phantom_demand", "demand names %d things that are not items (%s)" %
			[phantom.size(), ", ".join(phantom)])
	_info("coverage", "%d items are declared terminal: obtainable and consumed by nothing, on purpose" %
		(demand["declared"] as Array).size())

# Supply concentration: the report's risk list, declared in the data when it is meant to be that
# way. A single source is not a bug — it is a decision — so the ones that are deliberate carry
# `bottleneck_reason`, and every unexplained one warns. A declaration that a later change made
# false warns too, so the list cannot rot into decoration.
func _check_bottlenecks() -> void:
	var concentrated: Dictionary = BalanceReport.concentrated_materials()
	for entry in (concentrated["rows"] as Array):
		var row: Dictionary = entry
		if str(row["reason"]) != "":
			continue
		var supply: String = "nothing supplies it" if str(row["shape"]) == "no_source" else "one source (%s)" % str(row["routes"])
		_warn("bottleneck_undeclared", "item '%s' (%s) is needed by %d recipes and has %s; declare bottleneck_reason if that is deliberate" % [
			str(row["item_id"]), str(DataLoader.get_item(str(row["item_id"])).get("name", "")),
			int(row["recipes"]), supply])
	for item_id in (concentrated["stale_declarations"] as Array):
		_warn("stale_bottleneck_declaration", "item '%s' declares bottleneck_reason but is no longer a supply bottleneck" % str(item_id))
	_info("bottlenecks", "%d of %d concentrated materials are declared deliberate" % [
		(concentrated["declared"] as Array).size(), (concentrated["rows"] as Array).size()])

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

func _check_ascendancy() -> void:
	# The Ascendancy node tree: ids, positive cost/max_rank, finite modifier values, and a
	# requires-graph that is acyclic with no dangling references. A broken tree would let a
	# node be unbuyable forever or a point vanish into a cycle.
	var tree: Dictionary = DataLoader.ascendancy
	var node_ids: Dictionary = {}
	for key in tree.keys():
		if str(key) == "_comment":
			continue
		node_ids[str(key)] = true
	for key in tree.keys():
		var id: String = str(key)
		if id == "_comment":
			continue
		var node: Variant = tree[key]
		if not node is Dictionary:
			_err("invalid_record", "ascendancy node '%s' is not an object" % id); continue
		if str(node.get("id", "")) != id:
			_err("invalid_record", "ascendancy node '%s' has a mismatched or missing id field" % id)
		if str(node.get("name", "")) == "":
			_err("invalid_record", "ascendancy node '%s' has no name" % id)
		for field in ["cost", "max_rank"]:
			var value: Variant = node.get(field, null)
			if not _is_finite_number(value) or float(value) <= 0 or float(value) != floor(float(value)):
				_err("invalid_number", "ascendancy.%s.%s must be a positive whole number" % [id, field])
		var mods: Variant = node.get("modifiers", {})
		if not mods is Dictionary or (mods as Dictionary).is_empty():
			_err("invalid_record", "ascendancy node '%s' has no modifiers" % id)
		else:
			for mk in mods:
				if not _is_finite_number(mods[mk]):
					_err("invalid_number", "ascendancy.%s modifier %s is not finite" % [id, str(mk)])
		var requires: Variant = node.get("requires", [])
		if not requires is Array:
			_err("invalid_record", "ascendancy.%s requires must be an array" % id)
		else:
			for req in requires:
				if not node_ids.has(str(req)):
					_err("missing_reference", "ascendancy.%s requires unknown node '%s'" % [id, str(req)])
				elif str(req) == id:
					_err("invalid_record", "ascendancy.%s requires itself" % id)
	# Cycle detection over the requires graph (DFS with a visiting stack).
	var state: Dictionary = {}   # id -> 0 unvisited, 1 visiting, 2 done
	var detect := func(nid: String, detect_ref: Callable) -> bool:
		if int(state.get(nid, 0)) == 1:
			return true
		if int(state.get(nid, 0)) == 2:
			return false
		state[nid] = 1
		for req in (tree.get(nid, {}).get("requires", []) as Array):
			if node_ids.has(str(req)) and detect_ref.call(str(req), detect_ref):
				return true
		state[nid] = 2
		return false
	for id in node_ids.keys():
		if detect.call(str(id), detect):
			_err("invalid_record", "ascendancy requires-graph has a cycle at '%s'" % str(id))
			break

func _check_new_skill_systems() -> void:
	var data: Dictionary = DataLoader.new_skill_systems
	var item_fields: Dictionary = {"species": ["stock", "produce", "hide"], "devices": ["id", "fuel"], "enchants": [], "dreams": [], "bazaar": [], "caravan_wagons": [], "caravan_guards": [], "caravan_routes": []}
	var number_fields: Dictionary = {"species": ["level", "seconds", "feed", "xp", "meat"], "devices": ["level", "fuel_cost"], "enchants": ["level", "tier"], "dreams": ["level", "xp_hour", "essence_hour"], "bazaar": ["cost"], "caravan_wagons": ["level", "price", "capacity"], "caravan_guards": ["level", "power", "wage"], "caravan_routes": ["level", "hours", "multiplier", "xp"]}
	for group in item_fields:
		var records: Variant = data.get(group, [])
		if not records is Array: _err("invalid_record", "new_skill_systems.%s must be an array" % group); continue
		var ids: Dictionary = {}
		for record in records:
			if not record is Dictionary: _err("invalid_record", "new_skill_systems.%s record must be an object" % group); continue
			var id: String = str(record.get("id", ""))
			if id == "" or ids.has(id): _err("duplicate_id", "%s has missing or duplicate id '%s'" % [group, id])
			ids[id] = true
			for field in item_fields[group]:
				if not _has_item(str(record.get(field, ""))): _err("missing_reference", "%s.%s.%s references a missing item" % [group, id, field])
			for field in number_fields[group]:
				var value: Variant = record.get(field, null)
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0: _err("invalid_number", "%s.%s.%s must be a positive finite number" % [group, id, field])
			if group == "devices" and not _has_skill(str(record.get("skill", ""))) and str(record.get("skill", "")) != "combat": _err("missing_reference", "device '%s' has unknown skill" % id)
			if group == "caravan_routes":
				if not DataLoader.cartography_hexes.has(str(record.get("hex", ""))): _err("missing_reference", "caravan route '%s' ends on an unknown hex" % id)
				for good in (record.get("demand", []) as Array):
					if not _has_item(str(good)): _err("missing_reference", "caravan route '%s' demands a missing item '%s'" % [id, str(good)])
				for good in (record.get("specialty", {}) as Dictionary).keys():
					if not _has_item(str(good)): _err("missing_reference", "caravan route '%s' specialty is a missing item '%s'" % [id, str(good)])
			if group == "enchants":
				if str(record.get("scope", "")) not in ["weapon", "armor", "skilling"]: _err("invalid_record", "enchant '%s' has invalid scope" % id)
				if str(record.get("essence", "")) not in ["martial", "warding", "arcane", "verdant"]: _err("invalid_record", "enchant '%s' has invalid Essence" % id)
				if str(record.get("dungeon", "")) != "" and not DataLoader.dungeons.has(str(record.dungeon)): _err("missing_reference", "enchant '%s' has unknown dungeon" % id)
			for numeric in ["seconds", "town_ticks"]:
				if record.has(numeric) and (not _is_finite_number(record[numeric]) or float(record[numeric]) <= 0): _err("invalid_number", "%s.%s.%s must be positive and finite" % [group, id, numeric])
			var mods: Variant = record.get("mods", {})
			if not mods is Dictionary: _err("invalid_record", "%s.%s.mods must be an object" % [group, id])
			else:
				for key in mods:
					if not _is_finite_number(mods[key]): _err("invalid_number", "%s.%s modifier %s is not finite" % [group, id, str(key)])
			if record.has("status") and not StatusEffect.TABLE.has(str(record.status)): _err("missing_reference", "enchant %s has an unknown status" % id)
			var rewards: Variant = record.get("items", {})
			if not rewards is Dictionary: _err("invalid_record", "bazaar %s rewards must be an object" % id); continue
			for item in rewards:
				if not _has_item(str(item)) or int(record.items[item]) <= 0: _err("missing_reference", "bazaar '%s' has invalid reward" % id)
	for action in DataLoader.get_skill_actions("inscription"):
		if action.has("quality_product"):
			for quality in ["faded", "inked", "illuminated"]:
				if not _has_item(str(action.quality_product) + "_" + quality): _err("missing_reference", "scribe recipe '%s' lacks '%s' variant" % [action.id, quality])
		if action.has("requires_research"):
			var found: bool = false
			for research in DataLoader.get_skill_actions("inscription"): found = found or str(research.get("research_unlock", "")) == str(action.requires_research)
			if not found: _err("missing_reference", "scribe recipe '%s' has unknown research" % action.id)
