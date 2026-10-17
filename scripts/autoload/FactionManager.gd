extends Node
## Three persistent faction reputation tracks. Players pledge to one faction at a time;
## only that faction's cumulative rank bonus is active in ModifierManager.

signal faction_changed(faction_id: String)
signal reputation_changed(faction_id: String, reputation: int)
signal faction_rank_up(faction_id: String, new_rank: int)

const DATA_PATH: String = "res://data/factions.json"
const CATEGORY: String = "faction"

var selected_faction: String = ""
var _factions: Dictionary = {}
var _order: Array[String] = []
var _reputation: Dictionary = {}
var _vendor_purchases: Dictionary = {}


func _ready() -> void:
	_load_definitions()
	EventBus.game_loaded.connect(_apply_modifiers)


func _load_definitions() -> void:
	_factions.clear()
	_order.clear()
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("FactionManager: Missing %s" % DATA_PATH)
		return
	var source := FileAccess.open(DATA_PATH, FileAccess.READ)
	if source == null:
		return
	var parsed: Variant = JSON.parse_string(source.get_as_text())
	source.close()
	if not parsed is Dictionary:
		push_warning("FactionManager: Invalid factions.json")
		return
	for entry in parsed.get("factions", []):
		if not entry is Dictionary or not entry.get("ranks", []) is Array:
			continue
		var id: String = str(entry.get("id", ""))
		if id == "" or _factions.has(id) or entry["ranks"].is_empty():
			continue
		_factions[id] = entry
		_order.append(id)
		_reputation[id] = 0


func all_faction_ids() -> Array[String]:
	return _order.duplicate()


func get_faction(faction_id: String) -> Dictionary:
	return (_factions.get(faction_id, {}) as Dictionary).duplicate(true)


func get_reputation(faction_id: String) -> int:
	return int(_reputation.get(faction_id, 0))


func get_rank(faction_id: String) -> int:
	if not _factions.has(faction_id):
		return 0
	var rank: int = 0
	var ranks: Array = _factions[faction_id].get("ranks", [])
	for i in range(ranks.size()):
		if get_reputation(faction_id) >= int(ranks[i].get("reputation", 0)):
			rank = i
	return rank


func get_rank_name(faction_id: String) -> String:
	if not _factions.has(faction_id):
		return "Unknown"
	return str(_factions[faction_id]["ranks"][get_rank(faction_id)].get("name", "Unknown"))


func get_next_rank(faction_id: String) -> Dictionary:
	if not _factions.has(faction_id):
		return {}
	var ranks: Array = _factions[faction_id]["ranks"]
	var next: int = get_rank(faction_id) + 1
	return (ranks[next] as Dictionary).duplicate(true) if next < ranks.size() else {}


func get_rank_modifiers(faction_id: String) -> Dictionary:
	if not _factions.has(faction_id):
		return {}
	return (_factions[faction_id]["ranks"][get_rank(faction_id)].get("modifiers", {}) as Dictionary).duplicate()


func get_unlocks(faction_id: String) -> Array[String]:
	var unlocked: Array[String] = []
	if not _factions.has(faction_id):
		return unlocked
	var ranks: Array = _factions[faction_id]["ranks"]
	for i in range(get_rank(faction_id) + 1):
		for unlock in ranks[i].get("unlocks", []):
			if not unlocked.has(str(unlock)):
				unlocked.append(str(unlock))
	return unlocked


func has_unlock(faction_id: String, unlock_id: String) -> bool:
	return get_unlocks(faction_id).has(unlock_id)

func vendor_offers(faction_id: String) -> Array:
	return (_factions.get(faction_id, {}) as Dictionary).get("vendors", []).duplicate(true)

func vendor_purchased(faction_id: String, upgrade_id: String) -> bool:
	return (_vendor_purchases.get(faction_id, {}) as Dictionary).has(upgrade_id)

func vendor_blocker(faction_id: String, upgrade_id: String) -> String:
	if not _factions.has(faction_id):
		return "Unknown faction"
	var offer: Dictionary = {}
	for candidate in vendor_offers(faction_id):
		if str(candidate.get("id", "")) == upgrade_id:
			offer = candidate
			break
	if offer.is_empty():
		return "Unknown reward"
	if vendor_purchased(faction_id, upgrade_id):
		return "Already owned"
	if selected_faction != faction_id:
		return "Pledge to this faction first"
	if get_rank(faction_id) < int(offer.get("requires_rank", 0)):
		return "Requires faction rank %d" % int(offer.get("requires_rank", 0))
	if PlayerData.gp < float(offer.get("cost_gp", 0)):
		return "Not enough gold"
	return ""

func purchase_vendor_reward(faction_id: String, upgrade_id: String) -> bool:
	if vendor_blocker(faction_id, upgrade_id) != "":
		return false
	for offer in vendor_offers(faction_id):
		if str(offer.get("id", "")) != upgrade_id:
			continue
		if not PlayerData.spend_gp(float(offer.get("cost_gp", 0))):
			return false
		var purchases: Dictionary = _vendor_purchases.get(faction_id, {})
		purchases[upgrade_id] = true
		_vendor_purchases[faction_id] = purchases
		_apply_modifiers()
		EventBus.notify("Purchased faction reward: %s" % offer.get("name", upgrade_id), "success")
		EventBus.state_refreshed.emit()
		if not GameManager.cli_mode and not SimulationMode.is_silent():
			SaveManager.save_game()
		return true
	return false


## Faction choice is reversible; changing pledges replaces the active modifier source.
## Progress with other factions is kept for future pledges.
func select_faction(faction_id: String) -> bool:
	if not _factions.has(faction_id) or faction_id == selected_faction:
		return false
	selected_faction = faction_id
	_apply_modifiers()
	faction_changed.emit(faction_id)
	EventBus.state_refreshed.emit()
	EventBus.notify("Pledged to %s" % str(_factions[faction_id].get("name", faction_id)), "success")
	if not GameManager.cli_mode and not SimulationMode.is_silent():
		SaveManager.save_game()
	return true


## Reputation changes only through gameplay rewards, never through UI refreshes.
func add_reputation(faction_id: String, amount: int) -> bool:
	if amount <= 0 or not _factions.has(faction_id):
		return false
	var prior: int = get_rank(faction_id)
	_reputation[faction_id] = mini(2147483647, get_reputation(faction_id) + amount)
	reputation_changed.emit(faction_id, get_reputation(faction_id))
	var current: int = get_rank(faction_id)
	if current > prior:
		if faction_id == selected_faction:
			_apply_modifiers()
		faction_rank_up.emit(faction_id, current)
		EventBus.notify("%s: %s rank reached!" % [str(_factions[faction_id]["name"]), get_rank_name(faction_id)], "success")
	return true


func _apply_modifiers() -> void:
	ModifierManager.clear_category(CATEGORY)
	if not _factions.has(selected_faction):
		return
	var bonuses: Dictionary = get_rank_modifiers(selected_faction)
	if not bonuses.is_empty():
		ModifierManager.register("faction:pledge", bonuses, CATEGORY,
			"%s — %s" % [str(_factions[selected_faction]["name"]), get_rank_name(selected_faction)])
	for offer in vendor_offers(selected_faction):
		if vendor_purchased(selected_faction, str(offer.get("id", ""))):
			ModifierManager.register("faction:vendor:" + str(offer.id), offer.get("modifiers", {}), CATEGORY,
			"Faction reward: " + str(offer.get("name", "")))


func serialize() -> Dictionary:
	return {"selected": selected_faction, "reputation": _reputation.duplicate(), "vendor_purchases": _vendor_purchases.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	_vendor_purchases.clear()
	var purchased: Dictionary = data.get("vendor_purchases", {}) if data.get("vendor_purchases", {}) is Dictionary else {}
	for faction_id in _order:
		var valid: Dictionary = {}
		var raw: Dictionary = purchased.get(faction_id, {}) if purchased.get(faction_id, {}) is Dictionary else {}
		for offer in vendor_offers(faction_id):
			if bool(raw.get(str(offer.get("id", "")), false)):
				valid[str(offer.id)] = true
		_vendor_purchases[faction_id] = valid
	_reputation.clear()
	var rep: Variant = data.get("reputation", {})
	for id in _order:
		var amount: Variant = (rep as Dictionary).get(id, 0) if rep is Dictionary else 0
		_reputation[id] = clampi(int(amount), 0, 2147483647) if amount is int or amount is float else 0
	var selected: String = str(data.get("selected", ""))
	selected_faction = selected if _factions.has(selected) else ""
	_apply_modifiers()
	faction_changed.emit(selected_faction)


func reset() -> void:
	deserialize({})
