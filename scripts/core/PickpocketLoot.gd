class_name PickpocketLoot
extends RefCounted
## A single weighted item draw on each successful Larceny pickpocket.
## chance is a fraction of successful steals; all entries must total 1.0.
## Independent secondary_outputs (seeds, special drops) are rolled separately.

static func roll(table: Array, rng: RandomNumberGenerator) -> Dictionary:
	if table.is_empty():
		return {}
	var ticket: float = rng.randf()
	var cumulative: float = 0.0
	for entry in table:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var chance: float = clampf(float(entry.get("chance", 0.0)), 0.0, 1.0)
		cumulative += chance
		if ticket < cumulative:
			var low: int = maxi(1, int(entry.get("min_qty", 1)))
			var high: int = maxi(low, int(entry.get("max_qty", low)))
			return {"item_id": str(entry.get("item_id", "")),
				"quantity": rng.randi_range(low, high), "chance": chance}
	return {}

static func valid_table(table: Array, items: Dictionary) -> bool:
	if table.size() < 3:
		return false
	var chance_sum: float = 0.0
	var seen: Dictionary = {}
	for entry in table:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var item_id: String = str(entry.get("item_id", ""))
		if not items.has(item_id) or seen.has(item_id):
			return false
		seen[item_id] = true
		var chance: float = float(entry.get("chance", -1.0))
		if not is_finite(chance) or chance <= 0.0 or chance > 1.0:
			return false
		if int(entry.get("min_qty", 0)) < 1 or int(entry.get("max_qty", 0)) < int(entry.get("min_qty", 0)):
			return false
		chance_sum += chance
	return absf(chance_sum - 1.0) < 0.00001
