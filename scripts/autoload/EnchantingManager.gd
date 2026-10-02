extends Node
## Derived item IDs split a single bank piece from its stack; other copies keep their enchantments.
var variants: Dictionary = {}
var pending: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func recipes() -> Array:
	return DataLoader.new_skill_systems.get("enchants", [])

func recipe(id: String) -> Dictionary:
	for def in recipes():
		if str(def.id) == id:
			return def
	return {}

func scope(item: Dictionary) -> String:
	var slot: int = int(item.get("equipment_slot", -1))
	return "weapon" if slot == 8 else "armor" if slot in [0, 1, 2, 3, 4, 9] else "skilling"

func essence(item: Dictionary) -> String:
	if scope(item) == "weapon":
		return "arcane" if int(item.get("equipment_stats", {}).get("magic_attack", 0)) > 0 else "martial"
	return "warding" if scope(item) == "armor" else "verdant"

func item_level(item: Dictionary) -> int:
	var level: int = 1
	for value in (item.get("level_requirements", {}) as Dictionary).values():
		level = maxi(level, int(value))
	var cape: Dictionary = item.get("requires_level", {})
	return maxi(level, int(cape.get("level", 1)))

func can_enchant(item_id: String, enchant_id: String, append: bool = false) -> String:
	var item: Dictionary = DataLoader.get_item(item_id)
	var def: Dictionary = recipe(enchant_id)
	if item.get("item_type", "") != "equipment" or def.is_empty():
		return "Select equipment and an enchantment."
	if not BankManager.has_item(item_id, 1):
		return "Unequip the item into Storage first."
	if BankManager.is_protected(item_id):
		return "Unprotect this item before changing it."
	if PlayerData.get_level("enchanting") < int(def.level):
		return "Requires Enchanting %d" % int(def.level)
	if scope(item) != str(def.scope):
		return "This enchantment does not fit this equipment slot."
	if str(def.get("dungeon", "")) != "" and float(PlayerData.stats.get("dungeons_cleared", {}).get(str(def.dungeon), 0)) <= 0:
		return "Clear " + str(DataLoader.dungeons.get(str(def.dungeon), {}).get("name", def.dungeon)) + " first."
	var enchants: Array = item.get("enchantments", [])
	if append and (ModifierManager.get_modifier("enchanting_slots") < 1 or enchants.size() >= 2 or enchants.has(enchant_id)):
		return "A skillcape permits two different enchantments per item."
	return ""

func begin_enchant(item_id: String, enchant_id: String, append: bool = false) -> bool:
	var reason: String = can_enchant(item_id, enchant_id, append)
	if reason != "":
		EventBus.notify(reason, "warn")
		return false
	SkillManager.stop_action()
	var def: Dictionary = recipe(enchant_id)
	var item: Dictionary = DataLoader.get_item(item_id)
	var base: String = str(item.get("original_item", item_id))
	var enchants: Array = item.get("enchantments", []).duplicate() if append else []
	if enchants.has(enchant_id):
		return false
	enchants.append(enchant_id)
	enchants.sort()
	var output: String = _register_variant(base, enchants)
	var cost: Dictionary = enchant_cost(item_id, enchant_id)
	pending = {"kind": "enchant", "action": "study_" + str(int(def.tier)), "input": cost, "output": {output: 1}, "name": "Enchant: " + str(def.name)}
	if not GameManager.request_skill_action("enchanting", str(pending.action), 1):
		pending = {}
		return false
	return true

func begin_disenchant(item_id: String) -> bool:
	var item: Dictionary = DataLoader.get_item(item_id)
	if item.get("item_type", "") != "equipment" or not BankManager.has_item(item_id, 1) or BankManager.is_protected(item_id):
		return false
	var level: int = item_level(item)
	if PlayerData.get_level("enchanting") < level:
		EventBus.notify("Requires Enchanting %d to recycle this equipment." % level, "warn")
		return false
	SkillManager.stop_action()
	var tier: int = 1
	for threshold in [30, 60, 90, 105, 115]:
		if level >= threshold:
			tier += 1
	var mastery: int = MasteryManager.get_level("enchanting", "study_" + str(tier))
	var yield_qty: int = maxi(1, floori(float(2 + level / 5) * (1.0 + float(mastery - 1) * 0.001 + ModifierManager.get_modifier("enchanting_essence_percent") / 100.0)))
	var outputs: Dictionary = {"enchant_" + essence(item) + "_essence": yield_qty}
	for id in item.get("enchantments", []):
		var def: Dictionary = recipe(str(id))
		if not def.is_empty():
			var eid: String = "enchant_" + str(def.essence) + "_essence"
			outputs[eid] = int(outputs.get(eid, 0)) + int(def.tier) * 5
	pending = {"kind": "disenchant", "action": "study_" + str(tier), "input": {item_id: 1}, "output": outputs, "name": "Disenchant " + str(item.name)}
	if not GameManager.request_skill_action("enchanting", str(pending.action), 1):
		pending = {}
		return false
	return true

func action_data(base: Dictionary) -> Dictionary:
	if pending.is_empty() or str(pending.get("action", "")) != str(base.get("id", "")):
		return base
	var out: Dictionary = base.duplicate(true)
	out.input_items = pending.input
	out.output_items = pending.output
	out.name = pending.name
	out.enchant_job = true
	return out

func _register_variant(base_id: String, enchant_ids: Array, saved_potency: float = -1.0) -> String:
	var id: String = ""
	var base: Dictionary = DataLoader.get_item(base_id).duplicate(true)
	var mods: Dictionary = base.get("passive_modifiers", {}).duplicate(true)
	var titles: Array[String] = []
	var statuses: Array = []
	var potency: float = saved_potency
	if potency < 0.0:
		var mastery: int = 1
		for enchant_id in enchant_ids:
			mastery = maxi(mastery, MasteryManager.get_level("enchanting", "study_" + str(int(recipe(str(enchant_id)).get("tier", 1)))))
		potency = 1.0 + float(mastery - 1) * 0.001 + ModifierManager.get_modifier("enchanting_potency_percent") / 100.0
	potency = clampf(potency, 1.0, 1.5) if is_finite(potency) else 1.0
	potency = snappedf(potency, 0.0001)
	id = "enchanted__" + base_id + "__" + "__".join(enchant_ids) + "__p" + str(roundi(potency * 10000.0))
	for enchant_id in enchant_ids:
		var def: Dictionary = recipe(str(enchant_id))
		if def.is_empty():
			continue
		titles.append(str(def.name))
		for key in def.mods:
			mods[str(key)] = float(mods.get(str(key), 0)) + float(def.mods[key]) * potency
		if def.has("status"):
			statuses.append(str(def.status))
	base.id = id
	base.name = str(base.get("name", base_id)) + " · " + " / ".join(titles)
	base.original_item = base_id
	base.icon_id = str(base.get("icon_id", base_id))
	base.enchantments = enchant_ids.duplicate()
	base.enchant_statuses = statuses
	base.passive_modifiers = mods
	base.is_stackable = true
	DataLoader.items[id] = base
	variants[id] = {"base": base_id, "enchants": enchant_ids.duplicate(), "potency": potency}
	return id

func on_hit(damage: int) -> void:
	var weapon: Dictionary = DataLoader.get_item(EquipmentManager.get_equipped(8))
	for status in weapon.get("enchant_statuses", []):
		if _rng.randf() < 0.2:
			CombatManager.apply_status("monster", str(status), 4.0, maxf(1.0, damage * 0.1) if str(status) == "burn" else 0.0)

func serialize() -> Dictionary:
	return {"variants": variants.duplicate(true), "pending": pending.duplicate(true)}

func deserialize(data: Dictionary) -> void:
	for id in variants:
		DataLoader.items.erase(id)
	variants = {}
	pending = {}
	var source: Variant = data.get("variants", {})
	if typeof(source) == TYPE_DICTIONARY:
		for value in source.values():
			if typeof(value) != TYPE_DICTIONARY or typeof(value.get("enchants", [])) != TYPE_ARRAY:
				continue
			var base: String = str(value.get("base", ""))
			var enchants: Array = value.enchants
			if DataLoader.get_item(base).get("item_type", "") != "equipment" or enchants.is_empty() or enchants.size() > 2:
				continue
			var valid: bool = true
			for id in enchants:
				valid = valid and not recipe(str(id)).is_empty()
			if valid:
				_register_variant(base, enchants, float(value.get("potency", 1.0)))
	if typeof(data.get("pending", {})) == TYPE_DICTIONARY:
		pending = data.get("pending", {}).duplicate(true)

func enchant_cost(item_id: String, enchant_id: String) -> Dictionary:
	var def: Dictionary = recipe(enchant_id)
	if def.is_empty(): return {}
	var rune_cost: int = maxi(1, ceili(float(int(def.tier) * 5) * (1.0 - clampf(ModifierManager.get_modifier("enchanting_rune_reduction_percent"), 0, 80) / 100.0)))
	var mastery: int = MasteryManager.get_level("enchanting", "study_" + str(int(def.tier)))
	var essence_cost: int = maxi(1, ceili(float(int(def.tier) * 10) * (1.0 - float(mastery - 1) * 0.001)))
	var cost: Dictionary = {item_id: 1, "enchant_" + str(def.essence) + "_essence": essence_cost, "rune_essence": rune_cost}
	if int(def.tier) >= 3:
		cost["diamond"] = maxi(1, ceili(float(int(def.tier) - 2) * (1.0 - ModifierManager.get_modifier("enchanting_catalyst_reduction_percent") / 100.0)))
	if int(def.tier) >= 4:
		cost["enchant_catalyst"] = maxi(1, ceili(float((int(def.tier) - 3) * 4) * (1.0 - ModifierManager.get_modifier("enchanting_catalyst_reduction_percent") / 100.0)))
	return cost

func preview(item_id: String, enchant_id: String, append: bool = false) -> Dictionary:
	var item: Dictionary = DataLoader.get_item(item_id)
	var def: Dictionary = recipe(enchant_id)
	if item.is_empty() or def.is_empty(): return {}
	var enchant_ids: Array = item.get("enchantments", []).duplicate() if append else []
	enchant_ids.append(enchant_id)
	var mastery: int = 1
	for id in enchant_ids: mastery = maxi(mastery, MasteryManager.get_level("enchanting", "study_" + str(int(recipe(str(id)).tier))))
	var potency: float = snappedf(clampf(1.0 + float(mastery - 1) * 0.001 + ModifierManager.get_modifier("enchanting_potency_percent") / 100.0, 1, 1.5), 0.0001)
	var before: Dictionary = item.get("passive_modifiers", {})
	var after: Dictionary = DataLoader.get_item(str(item.get("original_item", item_id))).get("passive_modifiers", {}).duplicate(true)
	for id in enchant_ids:
		for key in recipe(str(id)).mods: after[key] = float(after.get(key, 0)) + float(recipe(str(id)).mods[key]) * potency
	return {"cost": enchant_cost(item_id, enchant_id), "before": before, "after": after, "replaced": [] if append else item.get("enchantments", []), "reason": can_enchant(item_id, enchant_id, append), "status": str(def.get("status", ""))}
