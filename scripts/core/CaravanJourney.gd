extends RefCounted
## Saved trip seed keeps routes and danger rolls stable through reloads.
const STOP_NAMES = ["Departure", "Wayside camp", "River crossing", "Trade outpost", "Old watchtower", "Roadside market", "Destination"]
const EVENTS = ["Clear road", "Bandit ambush", "Sudden storm", "Damaged bridge", "Lost merchant", "Abandoned cache"]
static var _sites: Dictionary = {}
const APPROACHES = ["cautious", "balanced", "bold"]

static func create(route_id: String, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + absi(hash(route_id))
	if _sites.is_empty(): _sites = JSON.parse_string(FileAccess.get_file_as_string("res://data/caravan_map_sites.json"))
	var landscape: Dictionary = _sites[route_id]
	var pool: Array = landscape.stops.duplicate(true)
	var chosen: Array = []
	for i in range(5): chosen.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	chosen.sort_custom(func(a, b): return float(a.x) < float(b.x))
	chosen.push_front(landscape.start)
	chosen.append(landscape.end)
	var points: Array = []
	for i in range(7):
		points.append({"x": float(chosen[i].x), "y": float(chosen[i].y), "name": str(chosen[i].name),
			"event": 0 if i == 0 or i == 6 else rng.randi_range(0, EVENTS.size() - 1),
			"roll": rng.randf(), "severity": rng.randf_range(0.04, 0.08), "approach": "balanced"})
	return {"seed": seed, "next_stop": 1, "loss": 0.0, "bonus_gp": 0, "points": points, "log": []}

static func restore(route_id: String, raw: Dictionary) -> Dictionary:
	var journey: Dictionary = create(route_id, maxi(1, int(raw.get("seed", 1))))
	journey.next_stop = clampi(int(raw.get("next_stop", 1)), 1, 6)
	var loss: float = float(raw.get("loss", 0.0))
	journey.loss = clampf(loss if is_finite(loss) else 0.0, 0.0, 0.4)
	journey.bonus_gp = maxi(0, int(raw.get("bonus_gp", 0)))
	var points: Variant = raw.get("points", [])
	if points is Array and points.size() == 7:
		for i in range(7):
			if points[i] is Dictionary and APPROACHES.has(str(points[i].get("approach", ""))):
				journey.points[i].approach = str(points[i].approach)
	var log: Variant = raw.get("log", [])
	if log is Array:
		for entry in log.slice(0, 5):
			if entry is Dictionary:
				journey.log.append({"stop": clampi(int(entry.get("stop", 1)), 1, 5), "text": str(entry.get("text", "")), "gp": maxi(0, int(entry.get("gp", 0)))})
	return journey

static func resolve(c: Dictionary, stop: int, route: Dictionary, guard_power: float) -> Dictionary:
	var j: Dictionary = c.journey
	var point: Dictionary = j.points[stop]
	var choice: String = str(point.approach)
	var reward: int = maxi(1, floori(float(route.xp) * 0.001))
	var risk: float = clampf((float(route.risk) - guard_power) / 100.0, 0.0, 0.8)
	var event: int = int(point.event)
	# Weather and damaged roads remain dangerous even with a veteran guard.
	if event == 2 or event == 3: risk = maxf(risk, 0.15)
	if choice == "cautious":
		risk *= 0.4
		reward = maxi(1, reward / 2)
	elif choice == "bold":
		risk = minf(0.95, risk * 1.5)
		reward *= 2
	var text: String = EVENTS[event]
	if event in [1, 2, 3]:
		if float(point.roll) < risk:
			var before: float = float(j.loss)
			j.loss = minf(0.4, before + float(point.severity) * (1.5 if choice == "bold" else 1.0))
			reward = 0
			text += " · cargo value lost %.0f%%" % ((float(j.loss) - before) * 100.0)
		else: text += " · passed safely"
	elif event == 4 or event == 5:
		reward *= 2
		text += " · extra trade rewards"
	j.bonus_gp = int(j.bonus_gp) + reward
	return {"stop": stop, "text": text, "gp": reward}
