class_name ActionEstimates
extends RefCounted
## ActionEstimates — pure, testable projections for an activity.
##
## These numbers are the ones the brief demands every activity screen show: XP per action,
## estimated XP/hour, estimated output/hour, and time to the next level. They are DERIVED from
## the live modifier set, never stored, and every result carries an `assumptions` string so the
## UI can state what the projection ignores. Nothing here is presented as exact.

## Returns {} when the action does not exist.
static func for_action(skill_id: String, action_id: String, extra_mods: Dictionary = {}) -> Dictionary:
	var action: Dictionary = DataLoader.get_action(skill_id, action_id)
	if action.is_empty():
		return {}
	var replacements: Dictionary = {"mastery_item:" + skill_id: MasteryManager.item_effects(skill_id, action_id), "rate_preview": extra_mods}
	var interval: float = maxf(float(action.get("interval_floor", 0.25)), float(action.get("base_interval", 3.0)) * (1.0 - (_mod(skill_id + "_interval_percent", replacements) + _mod("global_skill_interval_percent", replacements)) / 100.0) - _mod(skill_id + "_interval_flat", replacements))
	var success: float = _success_chance(skill_id, action, replacements)
	var node_overhead: float = 0.0
	if int(action.get("node_hp", 0)) > 0:
		node_overhead = maxf(0.25, float(action.get("respawn_seconds", 3.0)) * (1.0 - _mod(ModifierKeys.RESPWAN_TIME_PERCENT, replacements) / 100.0)) * (1.0 - clampf(_mod(skill_id + "_node_preservation_percent", replacements) / 100.0, 0, 1)) * success / float(action.node_hp)
	var stun_overhead: float = (1.0 - success) * float(action.get("stun_seconds", 0.0))
	var effective_interval: float = interval + node_overhead + stun_overhead
	var actions_per_hour: float = 3600.0 / maxf(effective_interval, 0.05)
	var xp_mult: float = (1.0 + (_mod("global_skill_xp_percent", replacements) + _mod(skill_id + "_skill_xp_percent", replacements)) / 100.0)
	var xp_per_action: float = float(action.get("base_xp", 0.0)) * xp_mult
	var doubling: float = clampf((_mod(skill_id + "_doubling_percent", replacements) + _mod("global_doubling_percent", replacements)) / 100.0, 0, 1)
	var flat_bonus: int = int(_mod(skill_id + "_resource_flat", replacements))
	var preservation: float = clampf(_mod(skill_id + "_preservation_percent", replacements) / 100.0, 0, 1)

	# Output: base + flat bonus, each unit independently doubled with `doubling` chance.
	var output: Dictionary = {}
	var primary_name: String = ""
	var primary_per_hour: float = 0.0
	for item_id in (action.get("output_items", {}) as Dictionary).keys():
		var base_qty: float = float(maxi(0, int(action["output_items"][item_id]) + flat_bonus))
		var expected: float = base_qty * (1.0 + doubling) * success
		output[str(item_id)] = expected * actions_per_hour
		if primary_name == "":
			primary_name = str(DataLoader.get_item(str(item_id)).get("name", item_id))
			primary_per_hour = expected * actions_per_hour

	var consumption: Dictionary = {}
	for item_id in (action.get("input_items", {}) as Dictionary).keys():
		consumption[str(item_id)] = float(action["input_items"][item_id]) * actions_per_hour * (1.0 - success * preservation)

	var level: int = PlayerData.get_level(skill_id)
	var xp: float = PlayerData.get_xp(skill_id)
	var xp_to_next: float = float(XPTable.xp_to_next_level(xp, level))
	var hours_to_next: float = 0.0
	if xp_per_action > 0.0 and actions_per_hour > 0.0:
		hours_to_next = xp_to_next / maxf(0.001, xp_per_action * actions_per_hour * success)

	# Exhaustion: how long the current stock lasts at this rate.
	var supply_hours: float = -1.0
	for item_id in consumption.keys():
		var have: float = float(BankManager.get_count(str(item_id)))
		var per_hour: float = maxf(0.001, float(consumption[item_id]))
		var hours: float = have / per_hour
		supply_hours = hours * 3600.0 if supply_hours < 0.0 else minf(supply_hours, hours * 3600.0)

	return {
		"interval": interval,
		"effective_interval": effective_interval,
		"node_overhead": node_overhead,
		"stun_overhead": stun_overhead,
		"preservation_chance": preservation,
		"gp_per_hour": float(action.get("gp_reward", 0)) * (1.0 + _mod(ModifierKeys.GLOBAL_GP_PERCENT, replacements) / 100.0) * success * actions_per_hour,
		"next_unlock": next_unlock(skill_id, xp_per_action * actions_per_hour * success),
		"actions_per_hour": actions_per_hour,
		"xp_per_action": xp_per_action,
		"xp_per_hour": xp_per_action * actions_per_hour * success,
		"success_chance": success,
		"output_per_hour": primary_per_hour,
		"output_name": primary_name,
		"outputs_per_hour": output,
		"consumption_per_hour": consumption,
		"xp_to_next": xp_to_next,
		"hours_to_next_level": hours_to_next,
		"supply_hours": supply_hours,
		"doubling_chance": doubling,
		"flat_bonus": flat_bonus,
		"xp_multiplier": xp_mult,
		"assumptions": assumptions(skill_id, action),
	}

static func _success_chance(skill_id: String, action: Dictionary, replacements: Dictionary = {}) -> float:
	if action.has("perception"):
		var stealth: float = 50.0 + _mod(ModifierKeys.skill_key(skill_id, "stealth"), replacements)
		return clampf(0.5 + (stealth - float(action["perception"])) / 300.0, 0.05, 0.95)
	var c: float = float(action.get("success_chance", 1.0))
	if action.has("success_chance_percent"):
		c += float(action["success_chance_percent"]) / 100.0
	return clampf(c, 0.0, 1.0)

## What the projection deliberately ignores. Shown in the UI so a rate is never over-claimed.
static func assumptions(skill_id: String, action: Dictionary) -> String:
	var notes: Array[String] = ["assumes uninterrupted supplies"]
	if int(action.get("node_hp", 0)) > 0:
		notes.append("includes expected node depletion and respawn (%.1fs)" % float(action.get("respawn_seconds", 3.0)))
	if not (action.get("secondary_outputs", []) as Array).is_empty():
		notes.append("excludes rare drops")
	var interval_floor: float = float(action.get("interval_floor", 0.25))
	if ModifierManager.get_interval(skill_id, float(action.get("base_interval", 3.0)), interval_floor) <= interval_floor + 0.0001:
		notes.append("action time is at the %.2fs floor" % interval_floor)
	return "; ".join(notes)

## Compact one-line projection for dense rows.
static func summary_line(skill_id: String, action_id: String) -> String:
	var est: Dictionary = for_action(skill_id, action_id)
	if est.is_empty():
		return ""
	var parts: Array[String] = [
		"%.2fs" % float(est["interval"]),
		"%s XP" % UIStyle.fmt(float(est["xp_per_action"])),
		"≈ %s XP/h" % UIStyle.fmt(float(est["xp_per_hour"])),
	]
	if float(est.get("output_per_hour", 0.0)) > 0.0:
		parts.append("≈ %s %s/h" % [UIStyle.fmt(float(est["output_per_hour"])), str(est.get("output_name", ""))])
	return "  ·  ".join(parts)

static func next_unlock(skill_id: String, xp_hour: float) -> Dictionary:
	var next: Dictionary = {}
	for action in DataLoader.get_skill_actions(skill_id):
		var level: int = int(action.get("level_required", 1))
		if level > PlayerData.get_level(skill_id) and level <= PlayerData.get_level_cap(skill_id) and (next.is_empty() or level < int(next.level)):
			next = {"name": str(action.get("name", "")), "level": level, "seconds": (float(XPTable.xp_for_level(level)) - PlayerData.get_xp(skill_id)) / maxf(0.001, xp_hour) * 3600.0}
	return next

## Quantities count successful crafts, matching repeat_target. Failures still spend inputs.
static func batch(skill_id: String, action_id: String, quantity: int) -> Dictionary:
	var est: Dictionary = for_action(skill_id, action_id)
	if est.is_empty(): return {}
	quantity = maxi(1, quantity)
	var success: float = maxf(0.001, float(est.success_chance))
	var attempts: float = quantity / success
	var seconds: float = attempts * float(est.effective_interval)
	var inputs: Dictionary = {}
	var outputs: Dictionary = {}
	var bottleneck: String = ""
	var worst_limit: int = 2147483647
	for id in DataLoader.get_action(skill_id, action_id).get("input_items", {}):
		var units: int = int(DataLoader.get_action(skill_id, action_id).input_items[id])
		inputs[id] = float(units) * (attempts - quantity * float(est.preservation_chance))
		var limit: int = BankManager.get_count(str(id)) / maxi(1, units)
		if limit < worst_limit:
			worst_limit = limit
			bottleneck = str(DataLoader.get_item(str(id)).get("name", id))
	for id in est.outputs_per_hour: outputs[id] = float(est.outputs_per_hour[id]) * seconds / 3600.0
	return {"seconds": seconds, "inputs": inputs, "outputs": outputs, "bottleneck": bottleneck, "attempts": attempts, "worst_limit": worst_limit}

static func _mod(key: String, replacements: Dictionary) -> float:
	return ModifierManager.get_modifier(key) if replacements.is_empty() else ModifierManager.projected_modifier(key, replacements)
