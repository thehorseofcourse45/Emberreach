extends Node
## One world condition at a time. Progression is measured in game real seconds and replayed
## by OfflineProgression, so offline catch-up rotates conditions along the same timeline.

const DATA_PATH: String = "res://data/regional_events.json"
const PERIOD_SECONDS: float = 4.0 * 3600.0
const CATEGORY: String = "regional_events"

var conditions: Dictionary = {}
var order: Array[String] = []
var current_index: int = 0
var elapsed_seconds: float = 0.0

func _ready() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			conditions = parsed
			order.assign(conditions.keys())
			order.sort()
	EventBus.game_loaded.connect(_apply_modifiers)
	_apply_modifiers()

func active_id() -> String:
	if order.is_empty():
		return ""
	return order[clampi(current_index, 0, order.size() - 1)]

func active_event() -> Dictionary:
	return conditions.get(active_id(), {})

func remaining_seconds() -> float:
	return maxf(0.0, PERIOD_SECONDS - elapsed_seconds)

func _process(delta: float) -> void:
	if GameManager.is_paused or OfflineProgression.is_running or SimulationMode.is_silent():
		return
	advance(delta / maxf(0.001, Engine.time_scale))

func advance(delta: float) -> void:
	if delta <= 0.0 or order.is_empty():
		return
	elapsed_seconds += delta
	var steps: int = floori(elapsed_seconds / PERIOD_SECONDS)
	if steps > 0:
		elapsed_seconds = fmod(elapsed_seconds, PERIOD_SECONDS)
		current_index = (current_index + steps) % order.size()
		_apply_modifiers()
		EventBus.state_refreshed.emit()

## Shares a clock with passive systems; end_time exists for the integration hook signature.
func advance_offline(delta: float, _end_time: float = 0.0) -> void:
	advance(delta)

## The existing combat engine can consult this for regional extra enemy damage.
func enemy_damage_multiplier(area_id: String) -> float:
	var event: Dictionary = active_event()
	if str(event.get("region_id", "")) != area_id:
		return 1.0
	return 1.0 + clampf(float(event.get("enemy_damage_percent", 0.0)), -50.0, 100.0) / 100.0

func _apply_modifiers() -> void:
	ModifierManager.clear_category(CATEGORY)
	var event: Dictionary = active_event()
	if event.is_empty():
		return
	var mods: Dictionary = event.get("modifiers", {})
	if not mods.is_empty():
		ModifierManager.register("regional:current", mods, CATEGORY,
			"World condition: " + str(event.get("name", "")))

func serialize() -> Dictionary:
	return {"current_index": current_index, "elapsed_seconds": elapsed_seconds}

func deserialize(data: Dictionary) -> void:
	current_index = posmod(int(data.get("current_index", 0)), maxi(1, order.size()))
	var saved: float = float(data.get("elapsed_seconds", 0.0))
	elapsed_seconds = clampf(saved, 0.0, PERIOD_SECONDS - 0.001) if is_finite(saved) else 0.0
	_apply_modifiers()
