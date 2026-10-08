extends Node
## Achievements — data-driven milestones (res://data/achievements.json).
##
## Completion and payout are separate: satisfying a condition marks the milestone complete
## (persisted and announced), and its reward is collected with an explicit claim — exactly
## once, guarded by the claimed set. Evaluation is a pure function of persisted state (skills,
## completion log, lifetime stats), so a milestone earned offline or before it was added to the
## game is picked up on the next evaluation and waits to be claimed instead of being missed.
## Rewards are modest (a little GP, XP, and a bundle of useful supplies) so milestones never
## become a mandatory grind, per the design brief.

const DATA_PATH: String = "res://data/achievements.json"

var _records: Dictionary = {}
var _order: Array[String] = []
var _completed: Dictionary = {}        # achievement_id -> true (condition satisfied)
var _claimed: Dictionary = {}          # achievement_id -> true (reward collected)
var _completed_unix: Dictionary = {}   # achievement_id -> unix time (tidy timeline)
var _claimed_unix: Dictionary = {}     # achievement_id -> unix time

func _ready() -> void:
	_load()

func _load() -> void:
	_records.clear()
	_order.clear()
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("Achievements: %s missing" % DATA_PATH)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Achievements: achievements.json is not a JSON object")
		return
	var raw: Dictionary = parsed
	raw.erase("_comment")
	for id in raw.keys():
		if typeof(raw[id]) == TYPE_DICTIONARY:
			_records[id] = raw[id]
			_order.append(id)
	_order.sort_custom(func(a, b):
		var ca: String = str(_records[a].get("category", ""))
		var cb: String = str(_records[b].get("category", ""))
		if ca == cb:
			return a < b
		return ca < cb)

# ---------------- queries ----------------

func all_ids() -> Array[String]:
	return _order.duplicate()

func get_record(id: String) -> Dictionary:
	return _records.get(id, {})

func count() -> int:
	return _records.size()

func completed_count() -> int:
	return _completed.size()

func claimed_count() -> int:
	return _claimed.size()

## Completed but not yet collected.
func ready_count() -> int:
	var n: int = 0
	for id in _completed.keys():
		if not _claimed.has(id):
			n += 1
	return n

func is_completed(id: String) -> bool:
	return _completed.has(id)

func is_claimed(id: String) -> bool:
	return _claimed.has(id)

func is_ready(id: String) -> bool:
	return _completed.has(id) and not _claimed.has(id)

func completed_at(id: String) -> int:
	return int(_completed_unix.get(id, 0))

func claimed_at(id: String) -> int:
	return int(_claimed_unix.get(id, 0))

func categories() -> Array[String]:
	var out: Array[String] = []
	for id in _order:
		var c: String = str(_records[id].get("category", "general"))
		if not out.has(c):
			out.append(c)
	return out

## Live progress for the UI: {current, required, percent, completed, claimed, ready}.
func progress(id: String) -> Dictionary:
	var rec: Dictionary = get_record(id)
	if rec.is_empty():
		return {}
	var cond: Dictionary = rec.get("condition", {})
	var value: float = float(cond.get("value", 1))
	var current: float = float(measure(cond))
	return {
		"current": current, "required": value,
		"percent": clampf(0.0 if value <= 0.0 else current / value, 0.0, 1.0),
		"completed": is_completed(id),
		"claimed": is_claimed(id),
		"ready": is_ready(id),
		"description": _describe(cond),
	}

## Pure measurement of a condition's current value against live state.
func measure(cond: Dictionary) -> float:
	match str(cond.get("kind", "")):
		"skill_level":
			return float(PlayerData.get_level(str(cond.get("skill_id", ""))))
		"total_level":
			var total: int = 0
			for skill_id in DataLoader.get_skill_ids():
				total += PlayerData.get_level(skill_id)
			return float(total)
		"item_count":
			return float(BankManager.get_count(str(cond.get("item_id", ""))))
		"lifetime_item":
			return PlayerData.get_stat("items_gained", str(cond.get("item_id", "")))
		"monsters_killed":
			if cond.has("monster_id"):
				return PlayerData.get_stat("monsters_killed", str(cond["monster_id"]))
			var kills: int = 0
			for k in (PlayerData.stats.get("monsters_killed", {}) as Dictionary).keys():
				kills += int(PlayerData.stats["monsters_killed"][k])
			return float(kills)
		"dungeons_cleared":
			if cond.has("dungeon_id"):
				return PlayerData.get_stat("dungeons_cleared", str(cond["dungeon_id"]))
			var clears: int = 0
			for k in (PlayerData.stats.get("dungeons_cleared", {}) as Dictionary).keys():
				clears += int(PlayerData.stats["dungeons_cleared"][k])
			return float(clears)
		"items_discovered":
			return float((PlayerData.completion_log.get("items", {}) as Dictionary).size())
		"gp_earned":
			return PlayerData.get_stat("gp_earned")
		"actions_completed":
			var n: int = 0
			for k in (PlayerData.stats.get("actions", {}) as Dictionary).keys():
				n += int(PlayerData.stats["actions"][k])
			return float(n)
		"quests_completed":
			return PlayerData.get_stat("quests_completed")
		"pets_unlocked":
			return float(PlayerData.unlocked_pets.size())
		"settlement_buildings":
			var levels: int = 0
			for b in TownshipManager.buildings.keys():
				levels += int(TownshipManager.buildings[b])
			return float(levels)
	return 0.0

func _describe(cond: Dictionary) -> String:
	match str(cond.get("kind", "")):
		"skill_level":
			return "%s level %d" % [DataLoader.get_skill(str(cond.get("skill_id", ""))).get("name", "?"), int(cond.get("value", 1))]
		"total_level":
			return "Total skill levels %d" % int(cond.get("value", 1))
		"item_count":
			return "Hold %d × %s" % [int(cond.get("value", 1)), DataLoader.get_item(str(cond.get("item_id", ""))).get("name", "?")]
		"lifetime_item":
			return "Obtain %d × %s" % [int(cond.get("value", 1)), DataLoader.get_item(str(cond.get("item_id", ""))).get("name", "?")]
		"monsters_killed":
			if cond.has("monster_id"):
				return "Defeat %d × %s" % [int(cond.get("value", 1)), DataLoader.get_monster(str(cond["monster_id"])).get("name", "?")]
			return "Defeat %d enemies" % int(cond.get("value", 1))
		"dungeons_cleared":
			if cond.has("dungeon_id"):
				return "Clear %s" % DataLoader.get_dungeon(str(cond["dungeon_id"])).get("name", "?")
			return "Clear %d expeditions" % int(cond.get("value", 1))
		"items_discovered":
			return "Discover %d distinct items" % int(cond.get("value", 1))
		"gp_earned":
			return "Earn %s GP" % Goals._fmt(float(cond.get("value", 0)))
		"actions_completed":
			return "Complete %d actions" % int(cond.get("value", 1))
		"quests_completed":
			return "Complete %d tasks" % int(cond.get("value", 1))
		"pets_unlocked":
			return "Bond with %d companions" % int(cond.get("value", 1))
		"settlement_buildings":
			return "Reach %d total structure levels" % int(cond.get("value", 1))
	return "Unknown condition"

# ---------------- evaluation ----------------

## Evaluate every milestone. Newly satisfied conditions are marked complete (and announced);
## rewards are NOT granted here; they are collected with claim().
func evaluate_all() -> Array[String]:
	var newly: Array[String] = []
	for id in _order:
		if _completed.has(id):
			continue
		var rec: Dictionary = _records[id]
		var cond: Dictionary = rec.get("condition", {})
		if cond.is_empty():
			continue
		var value: float = float(cond.get("value", 1))
		if float(measure(cond)) < value:
			continue
		_completed[id] = true
		_completed_unix[id] = int(Time.get_unix_time_from_system())
		newly.append(id)
		EventBus.achievement_unlocked.emit(id)
		EventBus.notify("Milestone complete: %s" % str(rec.get("name", id)), "success")
	return newly

# ---------------- claiming ----------------

## Collect a completed milestone's reward. Exactly once, guarded by the claimed set.
func claim(id: String) -> bool:
	var rec: Dictionary = get_record(id)
	if rec.is_empty() or not _completed.has(id):
		EventBus.notify("That milestone is not complete yet.", "warn")
		return false
	if _claimed.has(id):
		EventBus.notify("That reward was already collected.", "warn")
		return false
	_claimed[id] = true
	_claimed_unix[id] = int(Time.get_unix_time_from_system())
	_grant(id, rec.get("reward", {}))
	EventBus.achievement_reward_claimed.emit(id)
	EventBus.notify("Milestone reward collected: %s" % str(rec.get("name", id)), "success")
	# Collected supplies can complete further milestones; settle before saving.
	ProgressTracker.evaluate_now()
	SaveManager.save_game()
	return true

## Collect every completed milestone in one pass (batched: one save, one evaluation).
## Returns how many payouts landed.
func claim_all() -> int:
	var n: int = 0
	for id in _order:
		if not _completed.has(id) or _claimed.has(id):
			continue
		var rec: Dictionary = _records[id]
		_claimed[id] = true
		_claimed_unix[id] = int(Time.get_unix_time_from_system())
		_grant(id, rec.get("reward", {}))
		EventBus.achievement_reward_claimed.emit(id)
		n += 1
	if n > 0:
		EventBus.notify("Collected %d milestone rewards." % n, "success")
		ProgressTracker.evaluate_now()
		SaveManager.save_game()
	return n

func _grant(_id: String, reward: Dictionary) -> void:
	if reward.is_empty():
		return
	if reward.has("gp"):
		PlayerData.add_gp(float(reward["gp"]))
	for item_id in (reward.get("items", {}) as Dictionary).keys():
		BankManager.add_item_guaranteed(str(item_id), int(reward["items"][item_id]))
	for skill_id in (reward.get("xp", {}) as Dictionary).keys():
		PlayerData.add_xp(str(skill_id), float(reward["xp"][skill_id]) * ModifierManager.get_skill_xp_multiplier(str(skill_id)))

## Player-facing reward summary.
func describe_reward(id: String) -> String:
	var reward: Dictionary = get_record(id).get("reward", {})
	if reward.is_empty():
		return "Cosmetic milestone"
	var parts: Array[String] = []
	if reward.has("gp"):
		parts.append("%s GP" % Goals._fmt(float(reward["gp"])))
	for item_id in (reward.get("items", {}) as Dictionary).keys():
		parts.append("%s ×%d" % [DataLoader.get_item(str(item_id)).get("name", item_id), int(reward["items"][item_id])])
	for skill_id in (reward.get("xp", {}) as Dictionary).keys():
		parts.append("%s %s XP" % [Goals._fmt(float(reward["xp"][skill_id])), DataLoader.get_skill(str(skill_id)).get("name", skill_id)])
	return " · ".join(parts)

# ---------------- persistence ----------------

func serialize() -> Dictionary:
	return {
		"completed": _completed.duplicate(), "claimed": _claimed.duplicate(),
		"completed_unix": _completed_unix.duplicate(), "claimed_unix": _claimed_unix.duplicate(),
	}

func deserialize(d: Dictionary) -> void:
	if d.has("completed") or d.has("claimed"):
		_completed = d.get("completed", {})
		_claimed = d.get("claimed", {})
		_completed_unix = d.get("completed_unix", {})
		_claimed_unix = d.get("claimed_unix", {})
	else:
		# Migration from the pre-claim era: everything previously unlocked had already been
		# paid out, so it arrives already completed and already claimed; nothing is owed.
		var old: Dictionary = d.get("unlocked", {})
		var old_unix: Dictionary = d.get("unlocked_unix", {})
		_completed = old.duplicate()
		_claimed = old.duplicate()
		_completed_unix = old_unix.duplicate()
		_claimed_unix = old_unix.duplicate()
	if typeof(_completed) != TYPE_DICTIONARY:
		_completed = {}
	if typeof(_claimed) != TYPE_DICTIONARY:
		_claimed = {}
	if typeof(_completed_unix) != TYPE_DICTIONARY:
		_completed_unix = {}
	if typeof(_claimed_unix) != TYPE_DICTIONARY:
		_claimed_unix = {}
	# Claimed implies completed (defensive repair for hand-edited saves).
	for id in _claimed.keys():
		if not _completed.has(id):
			_completed[id] = true
	# Drop records whose achievement no longer exists.
	for id in _completed.keys():
		if not _records.has(id):
			_completed.erase(id)
			_completed_unix.erase(id)
	for id in _claimed.keys():
		if not _records.has(id):
			_claimed.erase(id)
			_claimed_unix.erase(id)
