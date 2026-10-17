extends Node
## Three independently generated offers, one for each faction. Every offer measures
## progress from its issue-time lifetime counter, including offline ProgressTracker work.
## Fifteen data templates across three reputation-gated tiers yield 45 variants.

signal board_changed()
signal contract_progress_changed(slot_index: int)
signal contract_claimed(serial: int, faction_id: String)

const DATA_PATH: String = "res://data/contracts.json"
const SLOT_COUNT: int = 3
const PROGRESS_POLL_SECONDS: float = 0.5

var _templates: Dictionary = {}
var _template_order: Array[String] = []
var _tiers: Array = []
var _slots: Array = []
var _next_serial: int = 1
var _refresh_count: int = 0
var _refresh_gp: int = 150
var _rng := RandomNumberGenerator.new()
var _poll_remaining: float = 0.0
var _last_progress: Dictionary = {}
var _announced_ready: Dictionary = {}


func _ready() -> void:
	_load_definitions()
	_rng.randomize()
	reset()
	EventBus.state_refreshed.connect(_check_progress)
	EventBus.game_loaded.connect(_check_progress)
	EventBus.offline_catchup_finished.connect(func(_summary): _check_progress())


func _process(delta: float) -> void:
	_poll_remaining -= delta
	if _poll_remaining <= 0.0:
		_poll_remaining = PROGRESS_POLL_SECONDS
		_check_progress()


func _load_definitions() -> void:
	_templates.clear()
	_template_order.clear()
	_tiers.clear()
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("ContractManager: Missing %s" % DATA_PATH)
		return
	var source := FileAccess.open(DATA_PATH, FileAccess.READ)
	if source == null:
		return
	var parsed: Variant = JSON.parse_string(source.get_as_text())
	source.close()
	if not parsed is Dictionary:
		push_warning("ContractManager: Invalid contracts.json")
		return
	_refresh_gp = maxi(0, int(parsed.get("refresh_gp", 150)))
	for tier in parsed.get("tiers", []):
		if tier is Dictionary and str(tier.get("id", "")) != "":
			_tiers.append(tier)
	for entry in parsed.get("templates", []):
		if not entry is Dictionary:
			continue
		var id: String = str(entry.get("id", ""))
		if id == "" or _templates.has(id):
			continue
		if not FactionManager.all_faction_ids().has(str(entry.get("faction", ""))):
			continue
		_templates[id] = entry
		_template_order.append(id)


func total_variant_count() -> int:
	return _template_order.size() * _tiers.size()


func get_refresh_cost() -> int:
	return _refresh_gp


func get_offers() -> Array:
	return _slots.duplicate(true)


func get_offer(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _slots.size():
		return {}
	return (_slots[slot_index] as Dictionary).duplicate(true)


func _counter(objective: Dictionary) -> float:
	return float(Quests.describe_objective(objective).get("current", 0.0))


func progress(slot_index: int) -> Dictionary:
	var offer: Dictionary = get_offer(slot_index)
	if offer.is_empty():
		return {"current": 0.0, "required": 1.0, "satisfied": false, "percent": 0.0}
	var objective: Dictionary = offer.get("objective", {})
	var row: Dictionary = Quests.describe_objective(objective)
	var earned: float = maxf(0.0, float(row["current"]) - float(offer.get("baseline", 0.0)))
	var target: float = maxf(1.0, float(objective.get("required", 1)))
	row["current"] = earned
	row["required"] = target
	row["satisfied"] = earned >= target
	row["percent"] = clampf(earned / target, 0.0, 1.0)
	row["hint"] = "Progress since this contract was issued; offline gains count"
	return row


func can_claim(slot_index: int) -> bool:
	return not get_offer(slot_index).is_empty() and bool(progress(slot_index)["satisfied"])


func describe_reward(slot_index: int) -> String:
	var offer: Dictionary = get_offer(slot_index)
	if offer.is_empty():
		return ""
	return "%s · %d faction reputation" % [Quests.describe_reward(offer.get("reward", {})), int(offer.get("reputation", 0))]


## Claim removes the old serial before granting currency/XP/reputation. Repeated clicks
## cannot claim it twice because that serial is no longer present on the board.
func claim_contract(slot_index: int) -> bool:
	if not can_claim(slot_index):
		return false
	var old: Dictionary = get_offer(slot_index)
	var faction_id: String = str(old["faction_id"])
	_slots[slot_index] = _new_offer(faction_id, str(old["template_id"]))
	_last_progress.clear()
	_announced_ready.clear()
	Quests.grant_reward(old.get("reward", {}))
	FactionManager.add_reputation(faction_id, int(old.get("reputation", 0)))
	contract_claimed.emit(int(old["serial"]), faction_id)
	board_changed.emit()
	EventBus.notify("Contract completed: %s (+%d reputation)" % [str(old["name"]), int(old["reputation"])], "success")
	SaveManager.save_game()
	return true


## Refreshes all three offers for a single flat GP fee, discarding their progress.
## The requirement to pay is checked before any slot is changed.
func refresh_board() -> bool:
	if _templates.is_empty() or _tiers.is_empty():
		return false
	if not PlayerData.spend_gp(float(_refresh_gp)):
		EventBus.notify("Need %d GP to refresh the Contract Board." % _refresh_gp, "warn")
		return false
	var previous: Array = _slots.duplicate(true)
	_slots.clear()
	for faction_id in FactionManager.all_faction_ids():
		if _slots.size() >= SLOT_COUNT:
			break
		var avoid: String = ""
		for offer in previous:
			if str(offer.get("faction_id", "")) == faction_id:
				avoid = str(offer.get("template_id", ""))
		_slots.append(_new_offer(faction_id, avoid))
	_refresh_count += 1
	_last_progress.clear()
	_announced_ready.clear()
	board_changed.emit()
	SaveManager.save_game()
	return true


func _new_offer(faction_id: String, avoid_template: String = "") -> Dictionary:
	var candidates: Array = []
	for id in _template_order:
		if str(_templates[id].get("faction", "")) != faction_id:
			continue
		for tier in _tiers:
			var unlock: String = str(tier.get("unlock", ""))
			if unlock != "" and not FactionManager.has_unlock(faction_id, unlock):
				continue
			if id != avoid_template:
				candidates.append([id, str(tier["id"])])
	if candidates.is_empty():
		return {}
	var choice: Array = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var offer: Dictionary = _make_offer(str(choice[0]), str(choice[1]), _next_serial)
	_next_serial += 1
	return offer


func _make_offer(template_id: String, tier_id: String, serial: int) -> Dictionary:
	if not _templates.has(template_id):
		return {}
	var template: Dictionary = _templates[template_id]
	var tier: Dictionary = {}
	for entry in _tiers:
		if str(entry.get("id", "")) == tier_id:
			tier = entry
			break
	if tier.is_empty():
		return {}
	var required: int = maxi(1, int(template.get("required", 1)) * int(tier.get("quantity_multiplier", 1)))
	var objective: Dictionary = {
		"kind": str(template.get("kind", "")),
		"required": required,
		"label": "%s ×%d" % [str(template.get("target", "Activity")), required],
		"route": template.get("route", {}),
	}
	for field in ["item_id", "monster_id", "dungeon_id", "skill_id", "action_id"]:
		if template.has(field):
			objective[field] = template[field]
	var xp_skill: String = str(template.get("xp_skill", ""))
	var xp_reward: Dictionary = {}
	if xp_skill != "":
		xp_reward[xp_skill] = maxi(0, int(tier.get("xp", 0)))
	return {
		"serial": serial,
		"template_id": template_id,
		"variant_id": "%s:%s" % [template_id, tier_id],
		"tier_id": tier_id,
		"tier_name": str(tier.get("name", tier_id)),
		"faction_id": str(template["faction"]),
		"name": str(template.get("name", template_id)),
		"description": str(template.get("description", "")),
		"objective": objective,
		"baseline": _counter(objective),
		"reward": {"gp": maxi(0, int(tier.get("gp", 0))), "xp": xp_reward},
		"reputation": maxi(0, int(tier.get("reputation", 0))),
	}


func _check_progress() -> void:
	for i in range(_slots.size()):
		var offer: Dictionary = _slots[i]
		if offer.is_empty():
			continue
		var serial: int = int(offer.get("serial", 0))
		var row: Dictionary = progress(i)
		var current: float = float(row["current"])
		if not _last_progress.has(serial) or not is_equal_approx(current, float(_last_progress[serial])):
			_last_progress[serial] = current
			contract_progress_changed.emit(i)
		if bool(row["satisfied"]) and not _announced_ready.has(serial):
			_announced_ready[serial] = true
			EventBus.notify("Contract ready to claim: %s" % str(offer["name"]), "success")


func serialize() -> Dictionary:
	return {"slots": _slots.duplicate(true), "next_serial": _next_serial, "refresh_count": _refresh_count}


## Only serialized identity and baseline are trusted. All reward and objective values are
## rebuilt from current content definitions to prevent stale saves from paying twice.
func deserialize(data: Dictionary) -> void:
	_slots.clear()
	_last_progress.clear()
	_announced_ready.clear()
	_next_serial = maxi(1, int(data.get("next_serial", 1)))
	_refresh_count = maxi(0, int(data.get("refresh_count", 0)))
	var raw: Variant = data.get("slots", [])
	var seen_serials: Dictionary = {}
	var restored_factions: Dictionary = {}
	if raw is Array:
		for record in raw:
			if not record is Dictionary or _slots.size() >= SLOT_COUNT:
				break
			var template_id: String = str(record.get("template_id", ""))
			var tier_id: String = str(record.get("tier_id", ""))
			var serial: int = int(record.get("serial", 0))
			if serial <= 0 or seen_serials.has(serial):
				continue
			var candidate: Dictionary = _make_offer(template_id, tier_id, serial)
			if candidate.is_empty():
				continue
			var faction_id: String = str(candidate.get("faction_id", ""))
			if restored_factions.has(faction_id):
				continue
			# A serialized offer may have been generated when a different faction tier
			# was unlocked. The issued offer remains valid after a later rank change.
			candidate["baseline"] = maxf(0.0, float(record.get("baseline", 0.0)))
			restored_factions[faction_id] = true
			seen_serials[serial] = true
			_next_serial = maxi(_next_serial, serial + 1)
			_slots.append(candidate)
	for faction_id in FactionManager.all_faction_ids():
		if _slots.size() >= SLOT_COUNT:
			break
		if not restored_factions.has(faction_id):
			_slots.append(_new_offer(faction_id))
	# The board always follows faction order, even for partially corrupted saves.
	_slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return FactionManager.all_faction_ids().find(str(a.get("faction_id", ""))) < FactionManager.all_faction_ids().find(str(b.get("faction_id", ""))))
	board_changed.emit()
	_check_progress()


func reset() -> void:
	deserialize({})
