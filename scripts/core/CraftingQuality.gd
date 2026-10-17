class_name CraftingQuality
extends RefCounted
## A tier is part of the item ID, so qualities occupy distinct bank stacks and equipment
## retains its exact roll through save/load. Regular items and existing IDs are unchanged.

const SEPARATOR := "__quality_"
const AFFIX_SEPARATOR := "__affix_"
const ORDER: Array[String] = ["legendary", "masterwork", "superior", "fine"]

static func resolve(item_id: String, items: Dictionary, tiers: Dictionary, affixes: Dictionary) -> Dictionary:
	var work_id: String = item_id
	var affix_id: String = ""
	var affix_split: int = work_id.rfind(AFFIX_SEPARATOR)
	if affix_split > 0:
		affix_id = work_id.substr(affix_split + AFFIX_SEPARATOR.length())
		work_id = work_id.substr(0, affix_split)
	var split_at: int = work_id.rfind(SEPARATOR)
	var base_id: String = work_id.substr(0, split_at) if split_at > 0 else work_id
	var tier_id: String = work_id.substr(split_at + SEPARATOR.length()) if split_at > 0 else ""
	if tier_id == "" and affix_id == "":
		return {}
	var tier: Dictionary = tiers.get(tier_id, {})
	var affix: Dictionary = affixes.get(affix_id, {})
	if (tier_id != "" and tier.is_empty()) or (affix_id != "" and affix.is_empty()):
		return {}
	var base: Dictionary = items.get(base_id, {})
	if str(base.get("item_type", "")) != "equipment":
		return {}
	var item: Dictionary = base.duplicate(true)
	item["id"] = item_id
	var prefix: String = str(tier.get("name", ""))
	item["name"] = (prefix + " " if prefix != "" else "") + str(base.get("name", base_id))
	if affix_id != "":
		item["name"] += " of " + str(affix.get("name", affix_id.capitalize()))
	item["icon_id"] = str(base.get("icon_id", base_id))
	item["crafted_quality"] = tier_id if tier_id != "" else "common"
	item["crafted_affix"] = affix_id
	item["description"] = "%s Quality-crafted equipment (+%s%% positive equipment stats)." % [str(base.get("description", "")), str(tier.get("stat_bonus_percent", 0))]
	item["sell_price"] = int(round(float(base.get("sell_price", 0)) * (1.0 + float(tier.get("value_bonus_percent", 0.0)) / 100.0)))
	var stats: Dictionary = item.get("equipment_stats", {})
	for stat in stats.keys():
		if float(stats[stat]) > 0.0:
			stats[stat] = int(round(float(stats[stat]) * (1.0 + float(tier.get("stat_bonus_percent", 0.0)) / 100.0)))
	item["equipment_stats"] = stats
	if not affix.is_empty():
		var passives: Dictionary = item.get("passive_modifiers", {})
		for key in (affix.get("modifiers", {}) as Dictionary):
			passives[key] = float(passives.get(key, 0.0)) + float(affix.modifiers[key])
		item["passive_modifiers"] = passives
		item["description"] += " Affix: %s." % str(affix.get("name", affix_id))
	# Upgrades are fixed recipes for the ordinary base item; quality items remain finished pieces.
	item.erase("upgrade_path")
	item.erase("upgrade_materials")
	return item

static func roll(item_id: String, level: int, rng: RandomNumberGenerator, items: Dictionary, tiers: Dictionary, affixes: Dictionary) -> String:
	var base: Dictionary = items.get(item_id, {})
	if str(base.get("item_type", "")) != "equipment" or tiers.is_empty():
		return item_id
	var draw: float = rng.randf()
	var result_id: String = item_id
	for tier_id in ORDER:
		var tier: Dictionary = tiers.get(tier_id, {})
		if level < int(tier.get("min_level", 120)):
			continue
		# Higher crafting levels improve the odds without allowing rare tiers below their gate.
		var chance: float = float(tier.get("chance", 0.0)) * (1.0 + float(level) / 240.0)
		if draw < chance:
			result_id += SEPARATOR + tier_id
			break
		draw -= chance
	var affix_draw: float = rng.randf()
	for affix_id in affixes.keys():
		var affix: Dictionary = affixes[affix_id]
		if level < int(affix.get("min_level", 120)):
			continue
		var chance: float = float(affix.get("chance", 0.0)) * (1.0 + float(level) / 240.0)
		if affix_draw < chance:
			result_id += AFFIX_SEPARATOR + str(affix_id)
			break
		affix_draw -= chance
	return result_id
