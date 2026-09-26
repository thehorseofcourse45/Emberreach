extends Node
## LootFilterManager — rule-based auto-sell over the existing bank.
##
## The policy itself lives in LootFilterEvaluator, which is pure. This manager owns the rule list,
## the safety toggle, persistence, and the single moment the evaluator runs. Keeping the decision
## separate from the mutation means "apply now" and automatic filtering are literally the same
## code path, so a rule cannot behave one way when created and another way overnight.
##
## Nothing sells until the player has written a rule. There is no default "tidy up everything" pass,
## because a bank the player did not ask to be emptied is a bank they still wanted.

const LootFilterEvaluator = preload("res://scripts/core/LootFilterEvaluator.gd")
## An explicit preload rather than the bare class name: the global class-name cache is only
## rebuilt by an editor import, so a headless run can see a brand-new class_name as undeclared.

signal rules_changed()
signal auto_sold(result: Dictionary)

const AUTO_SELL_ENABLED_KEY: String = "loot_filter_auto_sell"

var rules: Array = []
var protect_special_items: bool = true
## Re-entrancy guard: a sale removes items, and removal must never re-enter the evaluator.
var _evaluating: bool = false
var _next_id: int = 1
var _pending_batch: Array = []

func _ready() -> void:
	EventBus.item_obtained.connect(_on_item_obtained)

# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

## Add a rule. Returns the stored rule, or {} if the rule could never match anything.
func add_rule(item_ids: Array = [], item_types: Array = [], min_tier: int = -1, max_tier: int = -1,
		keep_count: int = 0, label: String = "") -> Dictionary:
	var rule: Dictionary = {
		"id": "filter-%d" % _next_id,
		"enabled": true,
		"label": label,
		"item_ids": _clean_ids(item_ids),
		"item_types": _clean_types(item_types),
		"min_tier": int(min_tier),
		"max_tier": int(max_tier),
		"keep_count": maxi(0, int(keep_count)),
	}
	var check: Dictionary = LootFilterEvaluator.validate(rule)
	if not bool(check["ok"]):
		last_error = str(check["detail"])
		return {}
	_next_id += 1
	if str(rule["label"]) == "":
		rule["label"] = LootFilterEvaluator.describe(rule)
	rules.append(rule)
	last_error = ""
	rules_changed.emit()
	return (rules[rules.size() - 1] as Dictionary).duplicate(true)

## The rule that governs an item, or {} when nothing claims it. Used by the UI to explain why an
## item is being kept.
func matching_rule(item_id: String) -> Dictionary:
	var item: Dictionary = DataLoader.get_item(item_id)
	for rule in rules:
		if typeof(rule) == TYPE_DICTIONARY and bool((rule as Dictionary).get("enabled", true)):
			if LootFilterEvaluator._matches(rule, item, item_id):
				return (rule as Dictionary).duplicate(true)
	return {}

func set_rule_enabled(rule_id: String, enabled: bool) -> bool:
	var index: int = _find_rule(rule_id)
	if index < 0:
		return false
	(rules[index] as Dictionary)["enabled"] = enabled
	rules_changed.emit()
	return true

func move_rule(rule_id: String, direction: int) -> bool:
	var index: int = _find_rule(rule_id)
	var target: int = index + direction
	if index < 0 or target < 0 or target >= rules.size():
		return false
	var rule: Dictionary = rules[index]
	rules.remove_at(index)
	rules.insert(target, rule)
	rules_changed.emit()
	return true

func remove_rule(rule_id: String) -> bool:
	var index: int = _find_rule(rule_id)
	if index < 0:
		return false
	rules.remove_at(index)
	rules_changed.emit()
	return true

func get_rule(rule_id: String) -> Dictionary:
	var index: int = _find_rule(rule_id)
	if index < 0:
		return {}
	return (rules[index] as Dictionary).duplicate(true)

func clear_rules() -> void:
	rules.clear()
	rules_changed.emit()

func set_protect_special_items(on: bool) -> void:
	protect_special_items = on
	rules_changed.emit()

var last_error: String = ""

# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------

## What the current rules would sell right now, without selling anything. The UI shows this so a
## rule can be understood before it is armed.
func preview() -> Array:
	return LootFilterEvaluator.evaluate_bank(_active_rules(), _candidates())

## Run the rules against the live bank and sell the excess. Returns
## {"items": int, "gp": float, "sold": [{item_id, quantity, gp}]}.
##
## "Apply now" and the automatic pass both land here, so a rule cannot mean one thing when it is
## created and another thing when it fires on its own.
func evaluate_now(notify: bool = true) -> Dictionary:
	var result: Dictionary = {"items": 0, "gp": 0.0, "sold": []}
	if rules.is_empty() or _evaluating:
		return result
	_evaluating = true
	var sold: Array = []
	var gp_total: float = 0.0
	var item_count: int = 0
	for entry in LootFilterEvaluator.evaluate_bank(_active_rules(), _candidates()):
		var item_id: String = str(entry["item_id"])
		var quantity: int = int(entry["quantity"])
		# One atomic sale per item: a partial failure leaves that stack untouched rather than
		# selling some of it and reporting the whole quantity.
		var before: int = BankManager.get_count(item_id)
		if not BankManager.sell_item(item_id, quantity):
			continue
		var after: int = BankManager.get_count(item_id)
		var actual: int = maxi(0, before - after)
		if actual <= 0:
			continue
		var unit: float = float(DataLoader.get_item(item_id).get("sell_price", 0))
		var gp: float = unit * float(actual) * (1.0 + ModifierManager.get_modifier("global_gp_percent") / 100.0)
		gp_total += gp
		item_count += 1
		sold.append({"item_id": item_id, "quantity": actual, "gp": gp})
	_evaluating = false
	result["items"] = item_count
	result["gp"] = gp_total
	result["sold"] = sold
	if item_count > 0:
		if notify:
			EventBus.notify("Auto-sold %d stack(s) for %s GP." % [item_count, UIStyle.fmt(gp_total)], "success")
		auto_sold.emit(result)
		rules_changed.emit()
	return result

## The automatic pass, run after a successful bank mutation. Deferred so the whole stack lands
## before anything is sold, and so a sale cannot re-enter the evaluator mid-mutation.
func _on_item_obtained(_item_id: String, _quantity: int) -> void:
	if rules.is_empty():
		return
	schedule()

## Queue a single pass for the end of the frame. Coalesced: a whole stack of drops arriving over
## several frames produces one pass, not one pass per item.
func schedule() -> void:
	if _pending_batch.size() > 0 or not is_inside_tree():
		return
	_pending_batch = ["queued"]
	call_deferred("_run_scheduled")

func _run_scheduled() -> void:
	_pending_batch.clear()
	if rules.is_empty() or _evaluating:
		return
	evaluate_now(false)

func _active_rules() -> Array:
	return rules.duplicate(true)

## Everything the evaluator may consider: bank stacks only. Items still sitting in overflow are
## deliberately excluded, because overflow is not really owned storage — those items are filtered
## when a slot frees up and they enter the bank.
func _candidates() -> Array:
	var out: Array = []
	for item_id in BankManager.items.keys():
		var id_str: String = str(item_id)
		var count: int = int(BankManager.items[item_id])
		if count <= 0:
			continue
		var item: Dictionary = DataLoader.get_item(id_str)
		out.append({
			"item_id": id_str,
			"item": item,
			"count": count,
			"protected": BankManager.is_protected(id_str),
			"special": str(item.get("special_attack", "")) != "",
			"protect_special": protect_special_items,
		})
	return out

func _find_rule(rule_id: String) -> int:
	for i in range(rules.size()):
		if str((rules[i] as Dictionary).get("id", "")) == rule_id:
			return i
	return -1

func _clean_ids(ids: Array) -> Array:
	var out: Array = []
	for item_id in ids:
		var id_str: String = str(item_id)
		if DataLoader.items.has(id_str) and not out.has(id_str):
			out.append(id_str)
	return out

func _clean_types(types: Array) -> Array:
	var out: Array = []
	for t in types:
		var type_str: String = str(t)
		if type_str != "" and not out.has(type_str):
			out.append(type_str)
	return out

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"rules": rules.duplicate(true),
		"protect_special_items": protect_special_items,
		"next_id": _next_id,
	}

## A save written before this feature existed has no section, so an absent or malformed one
## yields no rules and the safety toggle stays on. No version bump is needed because the whole
## section is optional and sanitized on the way in.
func deserialize(source: Dictionary) -> void:
	rules.clear()
	var raw: Variant = source.get("rules", [])
	if typeof(raw) == TYPE_ARRAY:
		for entry in (raw as Array):
			var rule: Dictionary = LootFilterEvaluator.sanitize(entry)
			if rule.is_empty():
				continue
			if not bool(LootFilterEvaluator.validate(rule)["ok"]):
				continue
			# An id collision would make one rule unremovable, so re-key on load.
			if _find_rule(str(rule["id"])) >= 0:
				rule["id"] = "filter-%d" % _next_id
			_next_id += 1
			rules.append(rule)
	protect_special_items = bool(source.get("protect_special_items", true))
	_next_id = maxi(int(source.get("next_id", 1)), _next_id)
	last_error = ""
	rules_changed.emit()
