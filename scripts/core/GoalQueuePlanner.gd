extends RefCounted
## Draft only: the action queue remains untouched until the player accepts it.

static func producers(item_id: String) -> Array:
	var result: Array = []
	for source in Goals._producer_recipes(item_id):
		var skill: String = str(source.get("skill_id", ""))
		if skill in ["ranching", "dreamwalking", "caravaneering", "enchanting"]:
			continue
		if float(source.get("chance", 1.0)) <= 0.0:
			continue
		result.append(source)
	result.sort_custom(func(a, b):
		var a_random: bool = bool(a.get("byproduct", false))
		var b_random: bool = bool(b.get("byproduct", false))
		if a_random != b_random: return not a_random
		var a_inputs: bool = not (a.action.get("input_items", {}) as Dictionary).is_empty()
		var b_inputs: bool = not (b.action.get("input_items", {}) as Dictionary).is_empty()
		if a_inputs != b_inputs: return not a_inputs
		return int(a.action.get("level_required", 1)) < int(b.action.get("level_required", 1)))
	return result

static func build(goal: Dictionary, choices: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"steps": [], "warnings": [], "errors": [], "choices": {}}
	var kind: String = str(goal.get("kind", ""))
	var item_id: String = ""
	var target: int = 1
	if kind == "item":
		item_id = str(goal.get("id", ""))
		target = maxi(1, int(goal.get("target_quantity", goal.get("level", 1))))
	elif kind == "recipe":
		var parts: PackedStringArray = str(goal.get("id", "")).split(":")
		if parts.size() != 2:
			out.errors.append("The recipe is invalid.")
			return out
		var action: Dictionary = DataLoader.get_action(parts[0], parts[1])
		var outputs: Dictionary = action.get("output_items", {})
		if outputs.is_empty():
			out.errors.append("This activity has no primary item that the queue can target.")
			return out
		item_id = str(outputs.keys()[0])
		target = maxi(1, int(goal.get("target_quantity", BankManager.count_with_variants(item_id) + maxi(1, int(outputs[item_id])))))
		choices = choices.duplicate()
		choices[item_id] = str(goal.get("id", ""))
	else:
		out.errors.append("Choose an item or recipe goal.")
		return out
	if DataLoader.get_item(item_id).is_empty():
		out.errors.append("The target item is unavailable.")
		return out
	if target > 1000000:
		out.errors.append("The target exceeds the queue's one-million-item preview limit.")
		return out
	out["target"] = target
	out["target_item"] = item_id
	_require(item_id, target, {}, {}, choices, out, 0)
	return out

static func _require(item_id: String, amount: int, stock: Dictionary, visiting: Dictionary, choices: Dictionary, out: Dictionary, depth: int) -> void:
	if amount > 1000000:
		out.errors.append("The required quantity of %s exceeds the one-million-item preview limit." % DataLoader.get_item(item_id).get("name", item_id))
		return
	if not stock.has(item_id):
		stock[item_id] = BankManager.count_with_variants(item_id)
		if BankManager.count_with_variants(item_id, true) > int(stock[item_id]):
			out.errors.append("Move %s out of overflow first: queue targets count overflow, but crafting cannot spend it." % DataLoader.get_item(item_id).get("name", item_id))
	var missing: int = maxi(0, amount - int(stock[item_id]))
	if missing == 0: return
	if depth >= 12 or visiting.has(item_id):
		out.errors.append("A recipe loop or depth limit blocks %s." % DataLoader.get_item(item_id).get("name", item_id))
		return
	var options: Array = producers(item_id)
	if options.is_empty():
		out.errors.append("No queueable skill source for %s; obtain it separately." % DataLoader.get_item(item_id).get("name", item_id))
		return
	out.choices[item_id] = options
	var selected: Dictionary = options[0]
	for option in options:
		if str(option.skill_id) + ":" + str(option.action_id) == str(choices.get(item_id, "")):
			selected = option
			break
	var action: Dictionary = selected.action
	var skill: String = str(selected.skill_id)
	var action_id: String = str(selected.action_id)
	var chance: float = float(selected.get("chance", 1.0)) if bool(selected.get("byproduct", false)) else 1.0
	chance *= ActionEstimates._success_chance(skill, action)
	if chance <= 0.0:
		out.errors.append("%s has no usable success chance." % action.get("name", action_id))
		return
	var yield_qty: int = maxi(1, int(selected.get("max_qty", 1))) if bool(selected.get("byproduct", false)) else maxi(1, int((action.get("output_items", {}) as Dictionary).get(item_id, 1)))
	var runs: int = ceili(float(missing) / (float(yield_qty) * chance))
	if runs > 1000000:
		out.errors.append("%s needs too many actions to preview safely." % action.get("name", action_id))
		return
	if chance < 1.0:
		out.warnings.append("%s has random yields or success; %d actions is an estimate, not a guarantee. The queue may need more supplies." % [action.get("name", action_id), runs])
	var gate: Dictionary = SkillManager.check_action(skill, action_id)
	if not bool(gate.get("ok", false)) and str(gate.get("reason", "")) != "materials":
		out.warnings.append("%s: %s" % [action.get("name", action_id), gate.get("detail", "Unavailable")])
	var branch: Dictionary = visiting.duplicate()
	branch[item_id] = true
	for input_id in (action.get("input_items", {}) as Dictionary):
		var needed: int = int(action.input_items[input_id]) * runs
		_require(str(input_id), needed, stock, branch, choices, out, depth + 1)
		stock[str(input_id)] = maxi(0, int(stock.get(str(input_id), 0)) - needed)
	var destination: int = int(stock[item_id]) + missing
	out.steps.append({"skill_id": skill, "action_id": action_id, "item_id": item_id, "target": destination, "runs": runs})
	stock[item_id] = destination
