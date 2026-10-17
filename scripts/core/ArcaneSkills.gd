class_name ArcaneSkills
extends RefCounted
## Choices live in settings; successful recipe counters permanently learn patterns.

const MODES := ["safe", "balanced", "overcharged"]
const TUNINGS := ["balanced", "focused", "rapid", "frugal"]

static func rift_action(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	var data := raw.duplicate(true)
	var mode := str(PlayerData.settings.get("riftkeeping_mode", "balanced"))
	if mode not in MODES:
		mode = "balanced"
	var mastery: int = MasteryManager.get_level("riftkeeping", str(raw.id))
	var tier: float = float(raw.get("level_required", 1)) / 120.0
	var interval := 1.0
	var quantity := 2
	var chance := 0.9
	var xp := 1.0
	var stun := 2.0 + tier * 2.0
	match mode:
		"safe":
			interval = 1.15
			quantity = 1
			chance = 1.0
			xp = 0.9
			stun = 0.0
		"overcharged":
			interval = 0.9
			quantity = 4
			chance = 0.65
			xp = 1.3
			stun = 4.0 + tier * 2.0
	data.base_interval = float(raw.base_interval) * interval
	data.base_xp = float(raw.base_xp) * xp
	data.success_chance = minf(1.0, chance + float(mastery - 1) / 119.0 * 0.05)
	data.stun_seconds = stun
	for item in data.output_items:
		data.output_items[item] = quantity
	return data

static func learned(action: Dictionary) -> bool:
	return not action.is_empty() and PlayerData.get_stat("actions", "spellweaving:" + str(action.id), 0) > 0

static func can_cast(action: Dictionary) -> bool:
	var required := int(action.get("level_required", 1))
	return learned(action) and PlayerData.get_level("spellweaving") >= required and PlayerData.get_level("magic") >= required

static func active_pattern(style: String = "") -> Dictionary:
	var use_style := CombatManager.attack_style if style == "" else style
	if use_style != "magic":
		return {}
	var weapon: Dictionary = DataLoader.get_item(EquipmentManager.get_equipped(ItemData.EquipmentSlot.WEAPON))
	if not weapon.has("spell_max_hit"):
		return {}
	var id := str(PlayerData.settings.get("spellweaving_pattern", ""))
	var action: Dictionary = DataLoader.get_action("spellweaving", id)
	if not can_cast(action):
		return {}
	var pattern: Dictionary = (action.get("woven_spell", {}) as Dictionary).duplicate(true)
	if pattern.is_empty():
		return {}
	pattern["action_id"] = id
	pattern["name"] = str(action.name)
	var tuning := str(PlayerData.settings.get("spellweaving_tuning", "balanced"))
	match tuning:
		"focused":
			pattern.damage_multiplier = float(pattern.damage_multiplier) * 1.12
			pattern.interval_multiplier = float(pattern.interval_multiplier) * 1.18
			pattern.accuracy_percent = float(pattern.accuracy_percent) + 10.0
		"rapid":
			pattern.damage_multiplier = float(pattern.damage_multiplier) * 0.78
			pattern.interval_multiplier = float(pattern.interval_multiplier) * 0.8
			pattern.accuracy_percent = float(pattern.accuracy_percent) - 8.0
		"frugal":
			pattern.damage_multiplier = float(pattern.damage_multiplier) * 0.85
			pattern.interval_multiplier = float(pattern.interval_multiplier) * 1.1
	var mastery: int = MasteryManager.get_level("spellweaving", id)
	var reduction: int = (1 if mastery >= 60 else 0) + (1 if mastery >= 120 else 0) + (1 if tuning == "frugal" else 0)
	for rune in pattern.runes:
		pattern.runes[rune] = maxi(0, int(pattern.runes[rune]) - reduction)
	return pattern

static func damage_multiplier() -> float:
	return float(active_pattern("magic").get("damage_multiplier", 1.0))

static func accuracy_percent(style: String) -> float:
	return float(active_pattern(style).get("accuracy_percent", 0.0))

static func interval_multiplier(style: String = "") -> float:
	return float(active_pattern(style).get("interval_multiplier", 1.0))

static func add_cast_cost(cost: Dictionary, style: String = "") -> Dictionary:
	var out := cost.duplicate()
	var runes: Dictionary = active_pattern(style).get("runes", {})
	for rune in runes:
		var quantity := int(runes[rune])
		if quantity > 0:
			out[rune] = int(out.get(rune, 0)) + quantity
	return out

static func special(style: String = "") -> Dictionary:
	var pattern := active_pattern(style)
	return DataLoader.get_special_attack(str(pattern.get("special_attack", ""))) if not pattern.is_empty() else {}
