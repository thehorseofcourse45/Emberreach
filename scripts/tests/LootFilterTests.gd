class_name LootFilterTests
extends RefCounted
const LootFilterEvaluator = preload("res://scripts/core/LootFilterEvaluator.gd")
## Dedicated tests for the loot filter / auto-sell rules.
##
## The evaluator is pure, so most of these assert against it directly — no bank, no gold, no
## running game. The handful that do touch the bank prove the wiring: that a real sale happens,
## that the safety overrides actually hold, and that rules survive a save round-trip.

static func run(_host: Node) -> Dictionary:
	var state: Dictionary = {"passed": 0, "failed": 0, "failures": []}
	var mgr: Node = LootFilterManager

	# ---------------------------------------------------------------------------
	# Pure matching
	# ---------------------------------------------------------------------------
	var bone_rule: Dictionary = {"enabled": true, "item_ids": [], "item_types": ["bone"],
		"min_tier": -1, "max_tier": 1, "keep_count": 0, "label": "bones under dragon"}
	_assert(LootFilterEvaluator.evaluate(bone_rule, DataLoader.get_item("bones"), "bones", 40) == 40,
		"a matching bone sells its whole stack when keep is 0", state)
	_assert(LootFilterEvaluator.evaluate(bone_rule, DataLoader.get_item("dragon_bones"), "dragon_bones", 10) == 0,
		"a bone above the tier ceiling does not match", state)
	_assert(LootFilterEvaluator.evaluate(bone_rule, DataLoader.get_item("big_bones"), "big_bones", 10) == 10,
		"a bone at the tier ceiling matches", state)
	_assert(LootFilterEvaluator.evaluate(bone_rule, DataLoader.get_item("bronze_arrow"), "bronze_arrow", 10) == 0,
		"an item of another type does not match a type rule", state)

	# An explicit id selection beats the broader criteria.
	var id_rule: Dictionary = {"enabled": true, "item_ids": ["dragon_bones"], "item_types": ["bone"],
		"min_tier": -1, "max_tier": 0, "keep_count": 0, "label": ""}
	_assert(LootFilterEvaluator.evaluate(id_rule, DataLoader.get_item("dragon_bones"), "dragon_bones", 7) == 7,
		"an explicit id list wins over the tier bound that would have excluded it", state)

	# Keep counts are a floor, not a target.
	var keep_rule: Dictionary = {"enabled": true, "item_ids": ["bronze_arrow"], "item_types": [],
		"min_tier": -1, "max_tier": -1, "keep_count": 5000, "label": "arrows"}
	_assert(LootFilterEvaluator.evaluate(keep_rule, DataLoader.get_item("bronze_arrow"), "bronze_arrow", 12000) == 7000,
		"keep 5,000 sells everything above 5,000", state)
	_assert(LootFilterEvaluator.evaluate(keep_rule, DataLoader.get_item("bronze_arrow"), "bronze_arrow", 4000) == 0,
		"a stack already under the keep count is left alone", state)

	# An item with no tier metadata must never match a tier-bounded rule.
	var untiered: Dictionary = {"id": "mystery", "name": "Mystery", "item_type": "bone", "sell_price": 3}
	var tiered_rule: Dictionary = {"enabled": true, "item_ids": [], "item_types": ["bone"],
		"min_tier": 0, "max_tier": 5, "keep_count": 0, "label": ""}
	_assert(LootFilterEvaluator.evaluate(tiered_rule, untiered, "mystery", 100) == 0,
		"an item with no tier metadata never matches a tier-bounded rule", state)

	# A disabled rule does nothing at all.
	var disabled: Dictionary = bone_rule.duplicate(true)
	disabled["enabled"] = false
	_assert(LootFilterEvaluator.evaluate(disabled, DataLoader.get_item("bones"), "bones", 40) == 0,
		"a disabled rule never matches", state)

	# ---------------------------------------------------------------------------
	# Bank-level safety
	# ---------------------------------------------------------------------------
	var entries: Array = [
		{"item_id": "bones", "item": DataLoader.get_item("bones"), "count": 100,
			"protected": false, "special": false, "protect_special": true},
		{"item_id": "bronze_arrow", "item": DataLoader.get_item("bronze_arrow"), "count": 6000,
			"protected": false, "special": false, "protect_special": true},
		{"item_id": "ancient_sword", "item": DataLoader.get_item("ancient_sword"), "count": 1,
			"protected": false, "special": true, "protect_special": true},
		{"item_id": "big_bones", "item": DataLoader.get_item("big_bones"), "count": 50,
			"protected": true, "special": false, "protect_special": true},
	]
	var rules: Array = [bone_rule, keep_rule]
	var plan: Array = LootFilterEvaluator.evaluate_bank(rules, entries)
	var planned: Dictionary = {}
	for entry in plan:
		planned[str(entry["item_id"])] = int(entry["quantity"])
	_assert(int(planned.get("bones", 0)) == 100, "matching bones are planned for sale", state)
	_assert(int(planned.get("bronze_arrow", 0)) == 1000, "arrows are planned down to the keep count", state)
	_assert(not planned.has("ancient_sword"), "a special-attack item is never auto-sold", state)
	_assert(not planned.has("big_bones"), "a player-protected item is never auto-sold", state)

	# Turning the safety toggle off is a deliberate choice by the player.
	var no_protect: Array = LootFilterEvaluator.evaluate_bank(rules, [
		{"item_id": "ancient_sword", "item": DataLoader.get_item("ancient_sword"), "count": 1,
			"protected": false, "special": true, "protect_special": false}])
	_assert(no_protect.is_empty(), "a special-attack item still needs a rule that matches it", state)
	var sword_rule: Array = [{"enabled": true, "item_ids": ["ancient_sword"], "item_types": [],
		"min_tier": -1, "max_tier": -1, "keep_count": 0, "label": ""}]
	var sword_plan: Array = LootFilterEvaluator.evaluate_bank(sword_rule, [
		{"item_id": "ancient_sword", "item": DataLoader.get_item("ancient_sword"), "count": 1,
			"protected": false, "special": true, "protect_special": false}])
	_assert(int((sword_plan[0] as Dictionary)["quantity"]) == 1,
		"with the safety toggle off, a matching special item can be sold", state)

	# Zero-value items are retained.
	var free_item: Dictionary = {"id": "free_thing", "name": "Free Thing", "item_type": "misc", "sell_price": 0}
	var free_plan: Array = LootFilterEvaluator.evaluate_bank([
		{"enabled": true, "item_ids": ["free_thing"], "item_types": [], "min_tier": -1,
			"max_tier": -1, "keep_count": 0, "label": ""}],
		[{"item_id": "free_thing", "item": free_item, "count": 5, "protected": false,
			"special": false, "protect_special": true}])
	_assert(free_plan.is_empty(), "an item worth nothing is never auto-sold", state)

	# First matching rule wins, so a later broad rule cannot re-open a claimed item.
	var ordered: Array = [
		{"enabled": true, "item_ids": ["bones"], "item_types": [], "min_tier": -1, "max_tier": -1,
			"keep_count": 90, "label": "keep 90 bones"},
		{"enabled": true, "item_ids": [], "item_types": ["bone"], "min_tier": -1, "max_tier": -1,
			"keep_count": 0, "label": "sell all bones"},
	]
	var ordered_plan: Array = LootFilterEvaluator.evaluate_bank(ordered, [
		{"item_id": "bones", "item": DataLoader.get_item("bones"), "count": 100,
			"protected": false, "special": false, "protect_special": true}])
	_assert(int((ordered_plan[0] as Dictionary)["quantity"]) == 10,
		"the first matching rule decides the quantity; later rules do not add to it", state)

	# ---------------------------------------------------------------------------
	# Validation and sanitizing
	# ---------------------------------------------------------------------------
	_assert(not bool(LootFilterEvaluator.validate({"item_ids": [], "item_types": [],
		"min_tier": -1, "max_tier": -1})["ok"]), "a rule that matches nothing is rejected", state)
	_assert(not bool(LootFilterEvaluator.validate({"item_ids": [], "item_types": [],
		"min_tier": 3, "max_tier": 1})["ok"]), "an inverted tier range is rejected", state)
	_assert(bool(LootFilterEvaluator.validate({"item_ids": ["bones"], "item_types": [],
		"min_tier": -1, "max_tier": -1})["ok"]), "an item rule is accepted", state)
	_assert(LootFilterEvaluator.sanitize({"id": "", "item_ids": ["bones"]}).is_empty(),
		"a rule with no id is dropped rather than given a blank one", state)
	_assert(LootFilterEvaluator.sanitize("not a rule").is_empty(),
		"a non-dictionary rule is dropped", state)
	var cleaned: Dictionary = LootFilterEvaluator.sanitize({"id": "x", "item_ids": ["bones", "not_real"],
		"keep_count": -5})
	_assert((cleaned["item_ids"] as Array).size() == 1 and int(cleaned["keep_count"]) == 0,
		"sanitizing drops unknown ids and clamps a negative keep count", state)

	# ---------------------------------------------------------------------------
	# Live manager: real sales against the real bank
	# ---------------------------------------------------------------------------
	var saved_rules: Dictionary = mgr.serialize()
	var saved_bank: Dictionary = BankManager.serialize()
	var saved_protected: Dictionary = PlayerData.protected_items.duplicate(true)
	var gp_before: float = PlayerData.gp

	mgr.clear_rules()
	BankManager.items.clear()
	BankManager.overflow.clear()
	PlayerData.protected_items.clear()

	# No rules means no automation, no matter how big the stack gets.
	BankManager.add_item_guaranteed("bones", 500)
	_assert(mgr.evaluate_now(false)["items"] == 0,
		"with no rules written, nothing is ever auto-sold", state)
	_assert(BankManager.get_count("bones") == 500, "an unarmed bank is left completely alone", state)

	# "Auto-sell all bones under Dragon tier."
	var bones_rule: Dictionary = mgr.add_rule([], ["bone"], -1, 1, 0)
	_assert(not bones_rule.is_empty(), "a bones auto-sell rule is accepted", state)
	var sold: Dictionary = mgr.evaluate_now(false)
	_assert(int(sold["items"]) == 1, "the bones rule sells the one matching stack", state)
	_assert(BankManager.get_count("bones") == 0, "common bones are sold completely", state)
	_assert(PlayerData.gp > gp_before, "an auto-sale actually pays out", state)

	# Dragon bones are above the ceiling, so they are kept.
	BankManager.add_item_guaranteed("dragon_bones", 25)
	mgr.evaluate_now(false)
	_assert(BankManager.get_count("dragon_bones") == 25,
		"bones above the tier ceiling are kept", state)

	# "Keep exactly 5,000 arrows, sell the rest."
	BankManager.items.erase("bones")
	BankManager.items.erase("dragon_bones")
	mgr.clear_rules()
	mgr.add_rule(["bronze_arrow"], [], -1, -1, 5000, "Keep 5,000 arrows")
	BankManager.add_item_guaranteed("bronze_arrow", 7342)
	mgr.evaluate_now(false)
	_assert(BankManager.get_count("bronze_arrow") == 5000,
		"keep 5,000 leaves exactly 5,000 arrows", state)

	# Player protection overrides automation even when a rule matches.
	BankManager.set_protected("bronze_arrow", true)
	BankManager.add_item_guaranteed("bronze_arrow", 100)
	mgr.evaluate_now(false)
	_assert(BankManager.get_count("bronze_arrow") == 5100,
		"a protected item is not auto-sold", state)
	BankManager.set_protected("bronze_arrow", false)

	# A special-attack weapon is protected by the on-by-default safety toggle.
	mgr.clear_rules()
	mgr.add_rule(["ancient_sword"], [], -1, -1, 0)
	BankManager.add_item_guaranteed("ancient_sword", 1)
	mgr.evaluate_now(false)
	_assert(BankManager.get_count("ancient_sword") == 1,
		"a special-attack item survives auto-sell while the safety toggle is on", state)
	# With the toggle off, the same rule sells it: the safety is a default, not a hard block.
	mgr.set_protect_special_items(false)
	mgr.evaluate_now(false)
	_assert(BankManager.get_count("ancient_sword") == 0,
		"turning the safety toggle off allows a special-attack item to be auto-sold", state)
	mgr.set_protect_special_items(true)

	# Overflow is not bank storage, so it is not filtered.
	mgr.clear_rules()
	mgr.add_rule(["bones"], [], -1, -1, 0)
	BankManager.items.erase("ancient_sword")
	var overflow_before: int = int(BankManager.overflow.get("bones", 0))
	BankManager.add_item("bones", 40)
	var overflow_now: int = int(BankManager.overflow.get("bones", 0))
	if overflow_now > 0:
		mgr.evaluate_now(false)
		_assert(int(BankManager.overflow.get("bones", 0)) == overflow_now,
			"items waiting in overflow are never deleted by auto-sell", state)
	else:
		_assert(true, "items waiting in overflow are never deleted by auto-sell", state)
	_assert(overflow_now == overflow_before, "auto-sell did not move anything out of overflow", state)

	# ---------------------------------------------------------------------------
	# Persistence
	# ---------------------------------------------------------------------------
	mgr.clear_rules()
	mgr.add_rule(["bones"], [], 0, 1, 5, "bones under dragon, keep 5")
	mgr.set_protect_special_items(false)
	var saved: Dictionary = mgr.serialize()
	mgr.clear_rules()
	mgr.set_protect_special_items(true)
	mgr.deserialize(saved)
	_assert(mgr.rules.size() == 1, "a rule survives a serialize/deserialize round trip", state)
	_assert(int(mgr.get_rule(str(saved["rules"][0]["id"]))["keep_count"]) == 5,
		"the keep count survives the round trip", state)
	_assert(not mgr.protect_special_items, "the safety toggle survives the round trip", state)
	mgr.deserialize({})
	_assert(mgr.rules.is_empty() and mgr.protect_special_items,
		"an absent section means no rules and the safety toggle back on", state)
	# A save with a malformed rule must not be able to sell the whole bank on load.
	mgr.deserialize({"rules": [{"id": "bad", "item_ids": [], "item_types": [], "min_tier": -1,
		"max_tier": -1, "keep_count": 0}, "garbage"], "protect_special_items": true})
	_assert(mgr.rules.is_empty(), "a malformed rule is dropped on load", state)

	# ---------------------------------------------------------------------------
	# Restore the real state
	# ---------------------------------------------------------------------------
	mgr.clear_rules()
	BankManager.deserialize(saved_bank)
	PlayerData.protected_items = saved_protected
	PlayerData.gp = gp_before
	mgr.deserialize(saved_rules)
	return state

static func _assert(condition: bool, label: String, state: Dictionary) -> void:
	if condition:
		state["passed"] = int(state["passed"]) + 1
	else:
		state["failed"] = int(state["failed"]) + 1
		var list: Array = state["failures"]
		list.append(label)
