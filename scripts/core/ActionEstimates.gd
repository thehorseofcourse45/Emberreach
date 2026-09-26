class_name ActionEstimates
extends RefCounted
## ActionEstimates — pure, testable projections for an activity.
##
## These numbers are the ones the brief demands every activity screen show: XP per action,
## estimated XP/hour, estimated output/hour, and time to the next level. They are DERIVED from
## the live modifier set, never stored, and every result carries an `assumptions` string so the
## UI can state what the projection ignores. Nothing here is presented as exact.

## Returns {} when the action does not exist.
static func for_action(skill_id: String, action_id: String) -> Dictionary:
	var action: Dictionary = DataLoader.get_action(skill_id, action_id)
	if action.is_empty():
		return {}
	var interval: float = ModifierManager.get_interval(skill_id, float(action.get("base_interval", 3.0)),
		float(action.get("interval_floor", 0.25)))
	var actions_per_hour: float = 3600.0 / maxf(interval, 0.05)
	var xp_mult: float = ModifierManager.get_skill_xp_multiplier(skill_id)
	var xp_per_action: float = float(action.get("base_xp", 0.0)) * xp_mult
	var doubling: float = ModifierManager.get_doubling_chance(skill_id) / 100.0
	var flat_bonus: int = ModifierManager.get_resource_flat(skill_id)
	var success: float = _success_chance(skill_id, action)

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
		consumption[str(item_id)] = float(action["input_items"][item_id]) * actions_per_hour * success

	var level: int = PlayerData.get_level(skill_id)
	var xp: float = PlayerData.get_xp(skill_id)
	var xp_to_next: float = float(XPTable.xp_to_next_level(xp, level))
	var hours_to_next: float = 0.0
	if xp_per_action > 0.0 and actions_per_hour > 0.0:
		hours_to_next = xp_to_next / (xp_per_action * actions_per_hour)

	# Exhaustion: how long the current stock lasts at this rate.
	var supply_hours: float = -1.0
	for item_id in consumption.keys():
		var have: float = float(BankManager.get_count(str(item_id)))
		var per_hour: float = maxf(0.001, float(consumption[item_id]))
		var hours: float = have / per_hour
		supply_hours = hours if supply_hours < 0.0 else minf(supply_hours, hours)

	return {
		"interval": interval,
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

static func _success_chance(skill_id: String, action: Dictionary) -> float:
	if action.has("perception"):
		var stealth: float = 50.0 + ModifierManager.get_modifier(ModifierKeys.skill_key(skill_id, "stealth"))
		return clampf(0.5 + (stealth - float(action["perception"])) / 300.0, 0.05, 0.95)
	var c: float = float(action.get("success_chance", 1.0))
	if action.has("success_chance_percent"):
		c += float(action["success_chance_percent"]) / 100.0
	return clampf(c, 0.0, 1.0)

## What the projection deliberately ignores. Shown in the UI so a rate is never over-claimed.
static func assumptions(skill_id: String, action: Dictionary) -> String:
	var notes: Array[String] = ["assumes uninterrupted supplies"]
	if int(action.get("node_hp", 0)) > 0:
		notes.append("ignores node depletion and respawn (%.1fs)" % float(action.get("respawn_seconds", 3.0)))
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
