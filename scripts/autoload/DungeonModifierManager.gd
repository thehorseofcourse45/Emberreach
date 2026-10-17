extends Node
## Select up to three challenge affixes before dungeon entry. Active affixes are fixed
## throughout a fight and serialized so reloading cannot replay an easier encounter.

const DATA_PATH: String = "res://data/dungeon_modifiers.json"
const MAX_SELECTED: int = 3

var definitions: Dictionary = {}
var selected_ids: Array[String] = []
var active_ids: Array[String] = []
var active_dungeon: String = ""

func _ready() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			definitions = parsed

func toggle(id: String) -> bool:
	if not definitions.has(id) or active_dungeon != "":
		return false
	if selected_ids.has(id):
		selected_ids.erase(id)
	elif selected_ids.size() < MAX_SELECTED:
		selected_ids.append(id)
	else:
		EventBus.notify("Choose at most %d dungeon modifiers." % MAX_SELECTED, "warn")
		return false
	EventBus.state_refreshed.emit()
	return true

func clear_selection() -> void:
	if active_dungeon != "":
		return
	selected_ids.clear()
	EventBus.state_refreshed.emit()

func begin_attempt(ctx: Dictionary) -> void:
	active_ids.clear()
	active_dungeon = ""
	if str(ctx.get("type", "")) == "dungeon":
		active_dungeon = str(ctx.get("id", ""))
		active_ids.assign(selected_ids)

func end_attempt() -> void:
	active_ids.clear()
	active_dungeon = ""

func modifier(key: String) -> float:
	var total: float = 0.0
	for id in active_ids:
		var effect: Dictionary = definitions.get(id, {}).get("effects", {})
		total += float(effect.get(key, 0.0))
	return total

func reward_multiplier() -> float:
	var bonus: float = 0.0
	for id in active_ids:
		bonus += float(definitions.get(id, {}).get("reward_bonus_percent", 0.0))
	return 1.0 + bonus / 100.0

func serialize() -> Dictionary:
	return {"selected_ids": selected_ids.duplicate(), "active_ids": active_ids.duplicate(), "active_dungeon": active_dungeon}

func deserialize(data: Dictionary) -> void:
	selected_ids.clear()
	active_ids.clear()
	active_dungeon = ""
	var selected: Variant = data.get("selected_ids", [])
	if selected is Array:
		for id in selected:
			if definitions.has(str(id)) and selected_ids.size() < MAX_SELECTED and not selected_ids.has(str(id)):
				selected_ids.append(str(id))
	var active: Variant = data.get("active_ids", [])
	if active is Array and str(data.get("active_dungeon", "")) != "" and not DataLoader.get_dungeon(str(data.get("active_dungeon", ""))).is_empty():
		active_dungeon = str(data.active_dungeon)
		for id in active:
			if definitions.has(str(id)) and active_ids.size() < MAX_SELECTED and not active_ids.has(str(id)):
				active_ids.append(str(id))
