extends RefCounted
## RandomEvents: small surprises while idling, from data/random_events.json.
## Rolls use the caller's seeded RNG, so online and offline runs stay identical. Online a hit
## raises a toast; offline it is counted for the welcome-back summary instead.
## Used via preload (no class_name), so no editor scan is needed to register it.

const BUCKET: String = "random_events"

static func roll(event_id: String, rng: RandomNumberGenerator) -> bool:
	var ev: Dictionary = DataLoader.random_events.get(event_id, {})
	if ev.is_empty() or rng.randf() >= float(ev.get("chance", 0.0)):
		return false
	SimulationMode.bump(BUCKET, event_id, 1.0)
	return true

static func announce(event_id: String, detail: String) -> void:
	if SimulationMode.is_silent():
		return
	var ev_name: String = str(DataLoader.random_events.get(event_id, {}).get("name", event_id))
	EventBus.notify("%s %s" % [ev_name, detail], "success")

static func gp_for(event_id: String, level: int) -> float:
	return float(DataLoader.random_events.get(event_id, {}).get("gp_per_level", 0)) * float(maxi(1, level))
