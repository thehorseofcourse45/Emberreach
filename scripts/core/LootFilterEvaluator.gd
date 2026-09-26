class_name LootFilterEvaluator
extends RefCounted
## LootFilterEvaluator — the pure rule engine behind auto-sell.
##
## Nothing here touches the bank, the player, gold or the scene tree: it takes a plain list of
## candidate item stacks plus the rule list and returns what should be sold. That makes the whole
## policy testable without a running game, and it is why "apply now" and automatic filtering
## cannot drift apart — they call the same function.
##
## RULE SEMANTICS
##   Rules are evaluated in order. The FIRST enabled rule that matches an item decides that item's
##   fate; later rules never re-open an item that an earlier rule already claimed. keep_count is a
##   floor, not a target: a rule that keeps 5,000 arrows sells everything above 5,000, and a rule
##   that keeps 0 sells the entire matching stack.
##
## SAFETY
##   Three things are never sold, whatever the rules say:
##     - items the player protected through the normal bank protection toggle;
##     - items with a special attack, while protect_special_items is on;
##     - items worth nothing, because a sale that pays nothing is data loss, not tidying.
##   Items with no tier metadata never match a tier-bounded rule. Missing data must not cause an
##   accidental sale, so an unknown item is treated as "not a match" rather than "tier zero".

## Match a single item against a single rule. `item` is the item's data record and
## `current` is how many are in the bank. Returns the quantity that may be sold.
static func evaluate(rule: Dictionary, item: Dictionary, item_id: String, current: int) -> int:
	if not bool(rule.get("enabled", true)):
		return 0
	if not _matches(rule, item, item_id):
		return 0
	var keep: int = maxi(0, int(rule.get("keep_count", 0)))
	return maxi(0, current - keep)

## True when this rule claims the item, independent of how many are held.
static func _matches(rule: Dictionary, item: Dictionary, item_id: String) -> bool:
	# An item id list is an explicit selection and wins over the broader criteria: a rule naming
	# "dragonscale" means that one item, whatever its tier or type.
	var ids: Array = rule.get("item_ids", [])
	if not ids.is_empty():
		return ids.has(item_id)
	var types: Array = rule.get("item_types", [])
	if not types.is_empty() and not types.has(str(item.get("item_type", ""))):
		return false
	var min_tier: int = int(rule.get("min_tier", -1))
	var max_tier: int = int(rule.get("max_tier", -1))
	if min_tier >= 0 or max_tier >= 0:
		if not item.has("tier"):
			return false
		var tier: int = int(item.get("tier", 0))
		if min_tier >= 0 and tier < min_tier:
			return false
		if max_tier >= 0 and tier > max_tier:
			return false
	return true

## The whole bank, one pass. `entries` is an array of
## {"item_id": String, "item": Dictionary, "count": int, "protected": bool, "special": bool}.
##
## Returns an array of the same shape, containing only what may be sold, in the same order. The
## caller performs the actual sales so a failed sale cannot leave the evaluator's view of the bank
## out of step with reality.
static func evaluate_bank(rules: Array, entries: Array) -> Array:
	var out: Array = []
	if rules.is_empty():
		return out
	for entry in entries:
		var e: Dictionary = entry
		var item_id: String = str(e.get("item_id", ""))
		var item: Dictionary = e.get("item", {})
		var current: int = maxi(0, int(e.get("count", 0)))
		if current <= 0:
			continue
		if bool(e.get("protected", false)):
			continue
		if bool(e.get("special", false)) and bool(e.get("protect_special", true)):
			continue
		if int(item.get("sell_price", 0)) <= 0:
			continue
		for rule in rules:
			if typeof(rule) != TYPE_DICTIONARY:
				continue
			var sale: int = evaluate(rule, item, item_id, current)
			if sale > 0:
				out.append({"item_id": item_id, "quantity": sale,
					"label": str(rule.get("label", ""))})
				break
	return out

## A rule is only usable if it could ever match something. Rejecting these at the API boundary
## keeps the UI from creating a rule that silently does nothing.
static func validate(rule: Dictionary) -> Dictionary:
	var item_ids: Array = rule.get("item_ids", [])
	var item_types: Array = rule.get("item_types", [])
	var min_tier: int = int(rule.get("min_tier", -1))
	var max_tier: int = int(rule.get("max_tier", -1))
	if min_tier < -1 or max_tier < -1:
		return {"ok": false, "detail": "Tier bounds cannot be negative below -1"}
	if min_tier >= 0 and max_tier >= 0 and min_tier > max_tier:
		return {"ok": false, "detail": "Minimum tier is above the maximum tier"}
	if item_ids.is_empty() and item_types.is_empty() and min_tier < 0 and max_tier < 0:
		return {"ok": false, "detail": "A rule must select an item, a type, or a tier range"}
	return {"ok": true, "detail": ""}

## Coerce anything loaded from a save into a well-formed rule. A hand-edited or truncated save
## must not be able to produce a rule that sells the entire bank.
static func sanitize(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = raw
	var out: Dictionary = {
		"id": str(source.get("id", "")),
		"enabled": bool(source.get("enabled", true)),
		"label": str(source.get("label", "")),
		"item_ids": [],
		"item_types": [],
		"min_tier": int(source.get("min_tier", -1)),
		"max_tier": int(source.get("max_tier", -1)),
		"keep_count": maxi(0, int(source.get("keep_count", 0))),
	}
	if str(out["id"]) == "":
		return {}
	for item_id in source.get("item_ids", []):
		var id_str: String = str(item_id)
		if DataLoader.items.has(id_str) and not (out["item_ids"] as Array).has(id_str):
			(out["item_ids"] as Array).append(id_str)
	for item_type in source.get("item_types", []):
		var type_str: String = str(item_type)
		if type_str != "" and not (out["item_types"] as Array).has(type_str):
			(out["item_types"] as Array).append(type_str)
	out["min_tier"] = maxi(-1, int(out["min_tier"]))
	out["max_tier"] = maxi(-1, int(out["max_tier"]))
	return out

## One line describing what the player asked for, shown beside each rule.
static func describe(rule: Dictionary) -> String:
	var parts: Array[String] = []
	var ids: Array = rule.get("item_ids", [])
	if not ids.is_empty():
		var names: Array[String] = []
		for item_id in ids:
			names.append(str(DataLoader.get_item(str(item_id)).get("name", item_id)))
		parts.append(", ".join(names))
	else:
		var types: Array = rule.get("item_types", [])
		if not types.is_empty():
			var type_names: Array[String] = []
			for t in types:
				type_names.append(str(t).capitalize())
			parts.append("%s items" % "/".join(type_names))
	var min_tier: int = int(rule.get("min_tier", -1))
	var max_tier: int = int(rule.get("max_tier", -1))
	if min_tier >= 0 or max_tier >= 0:
		var lo: String = "any" if min_tier < 0 else _tier_name(min_tier)
		var hi: String = "any" if max_tier < 0 else _tier_name(max_tier)
		parts.append("tier %s to %s" % [lo, hi])
	var keep: int = int(rule.get("keep_count", 0))
	parts.append("keep %s" % ("none" if keep == 0 else _format(keep)))
	parts.append("sell the rest")
	return " · ".join(parts)

static func _tier_name(tier: int) -> String:
	match tier:
		0: return "common"
		1: return "large"
		2: return "dragon"
		_: return "tier %d" % tier

static func _format(value: int) -> String:
	var text: String = str(absi(int(value)))
	var out: String = ""
	var count: int = 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
