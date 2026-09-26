class_name SimulationMode
extends RefCounted
## SimulationMode — one switch that tells the authoritative simulation whether anyone is
## watching, plus a telemetry channel for the offline summary.
##
## The same code path runs online and offline (`SkillManager.tick`, `CombatManager.tick`).
## When `silent` is true those systems skip UI-only work (per-tick signals, toasts) and record
## what happened into `events` instead, so a 24-hour catch-up produces ONE summary rather than
## tens of thousands of UI events.
##
## This is deliberately not a "different offline formula": the maths, stop conditions and
## consumption rules are identical, only the observation is different.

static var silent: bool = false
static var events: Dictionary = {}

const BUCKET_ITEMS_CONSUMED: String = "items_consumed"
const BUCKET_ITEMS_PRODUCED: String = "items_produced"
const BUCKET_KILLS: String = "kills"
const BUCKET_DEATHS: String = "deaths"
const BUCKET_DUNGEONS: String = "dungeons"
const BUCKET_ACTIONS: String = "actions"
const BUCKET_RARE_DROPS: String = "rare_drops"
const RARE_DROP_CHANCE_THRESHOLD: float = 0.01

static func begin() -> void:
	silent = true
	events.clear()

static func end() -> void:
	silent = false

static func is_silent() -> bool:
	return silent

## Record something that happened during a silent simulation.
static func bump(bucket: String, key: String, amount: float = 1.0) -> void:
	if not silent:
		return
	if not events.has(bucket):
		events[bucket] = {}
	var table: Dictionary = events[bucket]
	if key == "":
		table["_total"] = float(table.get("_total", 0.0)) + amount
	else:
		table[key] = float(table.get(key, 0.0)) + amount

static func get_table(bucket: String) -> Dictionary:
	return events.get(bucket, {})

## Sum a bucket out of an explicit events dictionary (used after take_events()).
static func get_total_from(source: Dictionary, bucket: String) -> float:
	var table: Variant = source.get(bucket, {})
	if typeof(table) != TYPE_DICTIONARY:
		return 0.0
	var total: float = 0.0
	for k in (table as Dictionary).keys():
		total += float((table as Dictionary)[k])
	return total

static func get_total(bucket: String) -> float:
	var table: Dictionary = events.get(bucket, {})
	var total: float = 0.0
	for k in table.keys():
		total += float(table[k])
	return total

static func take_events() -> Dictionary:
	var out: Dictionary = events
	events = {}
	return out
