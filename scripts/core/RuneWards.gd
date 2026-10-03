extends RefCounted
## RuneWards — the timed wards Runescribing weaves.
##
## A ward is an alt_magic action carrying a `ward` block: {mods, seconds, max_seconds}. Each
## completed cast adds `seconds` of charge, capped at `max_seconds`, so a player can stack a few
## hours of a ward and then go and use it in another skill or in combat.
##
## Wards ride InscriptionManager's shared timed-buff clock (as Dreamwalking's do), under a
## "ward_" id prefix. That clock already ticks online, offline and in dreams, is saved, and is
## cleared on a new game or ascension, so wards need no persistence or timekeeping of their own.

const SKILL_ID: String = "alt_magic"
const PREFIX: String = "ward_"
## How many different wards can hold a charge at once.
const MAX_ACTIVE: int = 2

static func is_ward(action: Dictionary) -> bool:
	return typeof(action.get("ward", null)) == TYPE_DICTIONARY

static func buff_id(action: Dictionary) -> String:
	var id: String = str(action.get("id", ""))
	return id if id.begins_with(PREFIX) else PREFIX + id

static func remaining(action: Dictionary) -> float:
	return float(InscriptionManager.buffs.get(buff_id(action), {}).get("remaining", 0.0))

static func max_seconds(action: Dictionary) -> float:
	return maxf(1.0, float(action.ward.get("max_seconds", 14400.0)))

## Ids of every ward currently holding a charge.
static func active_ids() -> Array[String]:
	var out: Array[String] = []
	for id in InscriptionManager.buffs.keys():
		if str(id).begins_with(PREFIX):
			out.append(str(id))
	return out

## Why this ward cannot be cast right now, or "" when it can.
static func blocker(action: Dictionary) -> String:
	if not is_ward(action):
		return ""
	var id: String = buff_id(action)
	if remaining(action) >= max_seconds(action) - 0.5:
		return "%s is fully charged (%s)." % [str(action.get("name", id)), UIStyle.fmt_duration(max_seconds(action))]
	if not InscriptionManager.buffs.has(id) and active_ids().size() >= MAX_ACTIVE:
		return "You can hold %d wards at once. Let one fade before weaving another." % MAX_ACTIVE
	return ""

## Add one cast's worth of charge. Returns the new remaining time.
static func cast(action: Dictionary) -> float:
	if not is_ward(action) or blocker(action) != "":
		return remaining(action)
	var mods: Dictionary = action.ward.get("mods", {})
	var charge: float = minf(remaining(action) + float(action.ward.get("seconds", 1800.0)), max_seconds(action))
	InscriptionManager.activate_buff(buff_id(action), mods, charge)
	return charge

## The ward actions in the data, in level order.
static func ward_actions() -> Array:
	var out: Array = []
	for action in DataLoader.get_skill_actions(SKILL_ID):
		if typeof(action) == TYPE_DICTIONARY and is_ward(action):
			out.append(action)
	return out
