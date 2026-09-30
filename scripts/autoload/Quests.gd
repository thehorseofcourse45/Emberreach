extends Node
## Quests — authored, data-driven progression tasks (res://data/quests.json), plus the
## rotating pool (res://data/rotating_tasks.json) whose featured selection changes every six
## hours; the selection is deterministic per window, so every player sees the same rotation.
##
## Lifecycle:  locked -> available -> active -> complete -> claimed
##
##  - "locked": prerequisites (other quests) are not met yet.
##  - "available": the player has not accepted it; objectives may already be partly satisfied.
##  - "active": accepted; objectives track from real game events plus lifetime counters.
##  - "complete": every objective is satisfied. The reward is NOT granted yet.
##  - "claimed": the reward has been granted. Exactly once, enforced by the claimed set.
##
## Objectives distinguish counters honestly:
##   "have_item"  -> currently held (spending it can un-satisfy the objective)
##   "gain_item"  -> lifetime obtained (never regresses; counted from PlayerData.stats)
## Both kinds count progress earned BEFORE accepting the quest, because lifetime counters
## and the bank are absolute, not session-relative.

const DATA_PATH: String = "res://data/quests.json"
const ROTATING_PATH: String = "res://data/rotating_tasks.json"
## The rotation window: every six hours the featured selection changes.
const ROTATION_PERIOD_SECONDS: int = 6 * 3600
## How many of the pool's tasks are featured per window.
const FEATURED_ROTATING_COUNT: int = 5
## Fixed seed so every player sees the same rotation for the same window.
const ROTATION_SEED: int = 20_260_928
## Difficulty tiers, in display order; these drive the Tasks screen sub-tabs.
const DIFFICULTIES: Array[String] = ["easy", "normal", "hard", "expert", "nightmare"]

var _quests: Dictionary = {}          # quest_id -> definition
var _order: Array[String] = []
var _accepted: Dictionary = {}        # quest_id -> true
var _claimed: Dictionary = {}         # quest_id -> true
var _rotating: Dictionary = {}          # rotating task id -> true
var _rotating_order: Array[String] = []
## Verification hook: pins the rotation window so screenshots and checks stay stable.
## Negative (the default) means the window follows the wall clock.
var rotation_window_override: int = -1

func _ready() -> void:
	_load()

func _load() -> void:
	_quests.clear()
	_order.clear()
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("Quests: %s missing" % DATA_PATH)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Quests: quests.json is not a JSON object")
		return
	var raw: Dictionary = parsed
	raw.erase("_comment")
	for quest_id in raw.keys():
		var q: Variant = raw[quest_id]
		if typeof(q) != TYPE_DICTIONARY:
			continue
		_quests[quest_id] = q
		_order.append(quest_id)
	_order.sort_custom(func(a, b): return int(_quests[a].get("chapter", 0)) < int(_quests[b].get("chapter", 0)))
	# Rotation tasks load after the main table and sit at the end of the order: the difficulty
	# tabs filter them out by flag, and nothing that walks the main progression sees them
	# interleaved with the chapter chain.
	_load_rotating()
	_order.append_array(_rotating_order)

func _load_rotating() -> void:
	_rotating.clear()
	_rotating_order.clear()
	if not FileAccess.file_exists(ROTATING_PATH):
		push_warning("Quests: %s missing" % ROTATING_PATH)
		return
	var f := FileAccess.open(ROTATING_PATH, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Quests: rotating_tasks.json is not a JSON object")
		return
	var raw: Dictionary = parsed
	raw.erase("_comment")
	for quest_id in raw.keys():
		var q: Variant = raw[quest_id]
		if typeof(q) != TYPE_DICTIONARY:
			continue
		_quests[quest_id] = q
		_rotating[quest_id] = true
		_rotating_order.append(quest_id)

# ---------------- queries ----------------

func all_quest_ids() -> Array[String]:
	return _order.duplicate()

## Accepted but not yet claimed — the only quests whose progress the UI needs to watch.
func accepted_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _order:
		if _accepted.has(id) and not _claimed.has(id):
			out.append(id)
	return out

## Everything currently visible to the player: available, active, complete or claimed.
func visible_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _order:
		if prerequisites_met(id):
			out.append(id)
	return out

## Rotation: the featured selection steps to a new set every six hours.
func is_rotating(quest_id: String) -> bool:
	return _rotating.has(quest_id)

## The full rotation pool, in file order (stable: the featured pick depends on it).
func rotating_pool_ids() -> Array[String]:
	return _rotating_order.duplicate()

## Unix-time window index; every six hours this steps to the next rotation.
func rotation_window() -> int:
	if rotation_window_override >= 0:
		return rotation_window_override
	return int(Time.get_unix_time_from_system() / float(ROTATION_PERIOD_SECONDS))

## Seconds until the current window ends (always in (0, ROTATION_PERIOD_SECONDS]).
func seconds_until_rotation() -> int:
	if rotation_window_override >= 0:
		return ROTATION_PERIOD_SECONDS
	return ROTATION_PERIOD_SECONDS - int(Time.get_unix_time_from_system()) % ROTATION_PERIOD_SECONDS

## Deterministic featured selection for a window: same window, same tasks, for everyone.
func featured_rotating_ids_for_window(window: int) -> Array[String]:
	var pool: Array[String] = rotating_pool_ids()
	var take: int = mini(FEATURED_ROTATING_COUNT, pool.size())
	var out: Array[String] = []
	if take <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = ROTATION_SEED + window
	var keyed: Array = []
	for quest_id in pool:
		keyed.append([rng.randi(), quest_id])
	keyed.sort()
	for i in range(take):
		out.append(str(keyed[i][1]))
	return out

func featured_rotating_ids() -> Array[String]:
	return featured_rotating_ids_for_window(rotation_window())

func get_quest(quest_id: String) -> Dictionary:
	return _quests.get(quest_id, {})

func has_quest(quest_id: String) -> bool:
	return _quests.has(quest_id)

func count() -> int:
	return _quests.size()

func is_accepted_or_claimed(quest_id: String) -> bool:
	return _accepted.has(quest_id) or _claimed.has(quest_id)

func accepted_count() -> int:
	var n: int = 0
	for id in _order:
		if _accepted.has(id):
			n += 1
	return n

func claimed_count() -> int:
	var n: int = 0
	for id in _order:
		if _claimed.has(id):
			n += 1
	return n

func is_accepted(quest_id: String) -> bool:
	return _accepted.has(quest_id)

func is_claimed(quest_id: String) -> bool:
	return _claimed.has(quest_id)

func is_complete(quest_id: String) -> bool:
	if not _quests.has(quest_id) or _claimed.has(quest_id):
		return false
	return progress(quest_id)["all_satisfied"]

func is_available(quest_id: String) -> bool:
	return prerequisites_met(quest_id) and not is_claimed(quest_id)

func prerequisites_met(quest_id: String) -> bool:
	var q: Dictionary = get_quest(quest_id)
	if q.is_empty():
		return false
	for pre in q.get("prerequisites", []):
		if not is_claimed(str(pre)):
			return false
	for req in q.get("requires", {}).get("skill_level", {}).keys():
		if PlayerData.get_level(str(req)) < int(q["requires"]["skill_level"][req]):
			return false
	for req in q.get("requires", {}).get("completed_quests", []):
		if not is_claimed(str(req)):
			return false
	return true

## Why a quest is locked, in player-facing words.
func lock_reason(quest_id: String) -> String:
	var q: Dictionary = get_quest(quest_id)
	if q.is_empty():
		return "Unknown task"
	var missing: Array[String] = []
	for pre in q.get("prerequisites", []):
		if not is_claimed(str(pre)):
			missing.append("complete \"%s\"" % str(get_quest(str(pre)).get("name", pre)))
	var sk: Dictionary = q.get("requires", {}).get("skill_level", {})
	for skill_id in sk.keys():
		var level: int = PlayerData.get_level(str(skill_id))
		if level < int(sk[skill_id]):
			missing.append("%s %d (you are %d)" % [DataLoader.get_skill(str(skill_id)).get("name", skill_id), int(sk[skill_id]), level])
	if missing.is_empty():
		return ""
	return "Requires " + ", ".join(missing)

# ---------------- objectives ----------------

## Live objective state for one quest.
func progress(quest_id: String) -> Dictionary:
	var q: Dictionary = get_quest(quest_id)
	var out: Dictionary = {"objectives": [], "satisfied": 0, "total": 0, "all_satisfied": false}
	if q.is_empty():
		return out
	for i in range((q.get("objectives", []) as Array).size()):
		var obj: Dictionary = q["objectives"][i]
		var row: Dictionary = describe_objective(obj)
		row["index"] = i
		out["objectives"].append(row)
		if bool(row["satisfied"]):
			out["satisfied"] += 1
		out["total"] += 1
	out["all_satisfied"] = out["total"] > 0 and out["satisfied"] == out["total"]
	return out

## Evaluate one objective against authoritative state. Pure: no side effects.
func describe_objective(obj: Dictionary) -> Dictionary:
	var kind: String = str(obj.get("kind", ""))
	var required: float = float(obj.get("required", 1))
	var current: float = 0.0
	var lifetime: bool = false
	var hint: String = ""
	match kind:
		"have_item":
			var item_id: String = str(obj.get("item_id", ""))
			current = float(BankManager.get_count(item_id))
			hint = "Held in your stores right now"
		"gain_item":
			var item_id2: String = str(obj.get("item_id", ""))
			current = PlayerData.get_stat("items_gained", item_id2)
			lifetime = true
			hint = "Counted over the whole run, including before you accepted this"
		"skill_level":
			current = float(PlayerData.get_level(str(obj.get("skill_id", ""))))
			hint = "Skill level"
		"combat_level":
			current = float(PlayerData.get_combat_level())
			hint = "Overall combat level"
		"mastery_level":
			current = float(MasteryManager.get_level(str(obj.get("skill_id", "")), str(obj.get("action_id", ""))))
			hint = "Action mastery level"
		"kill_monster":
			current = PlayerData.get_stat("monsters_killed", str(obj.get("monster_id", "")))
			lifetime = true
			hint = "Total defeats"
		"defeat_boss":
			current = PlayerData.get_stat("monsters_killed", str(obj.get("monster_id", "")))
			lifetime = true
			hint = "Total defeats"
		"complete_dungeon":
			current = PlayerData.get_stat("dungeons_cleared", str(obj.get("dungeon_id", "")))
			lifetime = true
			hint = "Total clears"
		"craft_item":
			current = PlayerData.get_stat("items_crafted", str(obj.get("item_id", "")))
			lifetime = true
			hint = "Items you produced yourself"
		"do_actions":
			current = PlayerData.get_stat("actions", "%s:%s" % [str(obj.get("skill_id", "")), str(obj.get("action_id", ""))])
			lifetime = true
			hint = "Completed actions"
		"reach_region":
			current = 1.0 if PlayerData.stats.get("region_visits", {}).has(str(obj.get("area_id", ""))) else 0.0
			lifetime = true
			hint = "Fight at least once in the region"
		"buy_upgrade":
			current = 1.0 if PlayerData.shop_upgrades.has(str(obj.get("upgrade_id", ""))) else 0.0
			hint = "Owned upgrade"
		"build_structure":
			current = float(TownshipManager.buildings.get(str(obj.get("building_id", "")), 0))
			hint = "Structure level"
		"gp_total":
			current = PlayerData.get_stat("gp_earned")
			lifetime = true
			hint = "Total GP earned this run"
		"unlock_pet":
			current = 1.0 if PlayerData.unlocked_pets.has(str(obj.get("pet_id", ""))) else 0.0
			hint = "Companion unlocked"
		"discover_items":
			current = float((PlayerData.completion_log.get("items", {}) as Dictionary).size())
			lifetime = true
			hint = "Distinct items discovered"
		_:
			hint = "Unsupported objective kind '%s'" % kind
	return {
		"kind": kind,
		"label": str(obj.get("label", _default_label(obj, kind))),
		"current": current,
		"required": required,
		"lifetime": lifetime,
		"satisfied": current >= required,
		"percent": clampf(0.0 if required <= 0.0 else current / required, 0.0, 1.0),
		"hint": hint,
		"route": obj.get("route", {}),
		"consumes": kind == "have_item",
	}

func _default_label(obj: Dictionary, kind: String) -> String:
	match kind:
		"have_item", "gain_item", "craft_item":
			return "%s ×%d" % [DataLoader.get_item(str(obj.get("item_id", ""))).get("name", "?"), int(obj.get("required", 1))]
		"skill_level":
			return "%s level %d" % [DataLoader.get_skill(str(obj.get("skill_id", ""))).get("name", "?"), int(obj.get("required", 1))]
		"kill_monster", "defeat_boss":
			return "Defeat %s ×%d" % [DataLoader.get_monster(str(obj.get("monster_id", ""))).get("name", "?"), int(obj.get("required", 1))]
		"complete_dungeon":
			return "Clear %s" % DataLoader.get_dungeon(str(obj.get("dungeon_id", ""))).get("name", "?")
		"gp_total":
			return "Earn %s GP" % Goals._fmt(float(obj.get("required", 0)))
	return kind.capitalize()

# ---------------- actions ----------------

## Accepting is optional bookkeeping; objectives count from the whole run either way.
func accept(quest_id: String) -> bool:
	if not _quests.has(quest_id) or _accepted.has(quest_id):
		return false
	if not prerequisites_met(quest_id):
		EventBus.notify("Cannot accept: %s" % lock_reason(quest_id), "warn")
		return false
	_accepted[quest_id] = true
	EventBus.notify("New task: %s" % str(get_quest(quest_id).get("name", quest_id)), "success")
	EventBus.quest_objective_progress.emit(quest_id, -1, 0.0, 0.0)
	SaveManager.save_game()
	return true

## Grant the reward. Exactly once: the claimed set is checked and set inside this call.
func claim(quest_id: String) -> bool:
	if not _quests.has(quest_id):
		return false
	if _claimed.has(quest_id):
		EventBus.notify("That reward was already collected.", "warn")
		return false
	if not prerequisites_met(quest_id):
		EventBus.notify("Task locked: %s" % lock_reason(quest_id), "warn")
		return false
	if not is_complete(quest_id):
		EventBus.notify("Objectives are not met yet.", "warn")
		return false
	_claimed[quest_id] = true
	_accepted[quest_id] = true
	PlayerData.bump_total("quests_completed", 1.0)
	grant_reward(get_quest(quest_id).get("reward", {}))
	EventBus.quest_completed.emit(quest_id)
	EventBus.quest_reward_claimed.emit(quest_id)
	EventBus.notify("Reward collected: %s" % str(get_quest(quest_id).get("name", quest_id)), "success")
	ProgressTracker.evaluate_now()
	SaveManager.save_game()
	return true

## Apply a reward bundle. Shared with dungeons-style rewards but routed through one place so
## every quest reward is auditable and idempotent when combined with the claimed set.
func grant_reward(reward: Dictionary) -> void:
	if reward.is_empty():
		return
	if reward.has("gp"):
		PlayerData.add_gp(float(reward["gp"]))
	for item_id in (reward.get("items", {}) as Dictionary).keys():
		BankManager.add_item(str(item_id), int(reward["items"][item_id]))
	for item_id in (reward.get("unlock_items", {}) as Dictionary).keys():
		# "Unlock" means: guaranteed first copy even if the bank is at capacity.
		BankManager.add_item_guaranteed(str(item_id), int(reward["unlock_items"][item_id]))
	for skill_id in (reward.get("xp", {}) as Dictionary).keys():
		PlayerData.add_xp(str(skill_id), float(reward["xp"][skill_id]) * ModifierManager.get_skill_xp_multiplier(str(skill_id)))

# ---------------- goal integration ----------------

## Goals.resolve() delegates quest goals here so a pinned quest shows its objectives,
## prerequisites and rewards in the same shape as every other goal type.
func describe_for_goal(quest_id: String) -> Dictionary:
	var q: Dictionary = get_quest(quest_id)
	if q.is_empty():
		return {"ok": false, "problem": "Unknown task '%s'" % quest_id, "kind": "quest", "id": quest_id}
	var p: Dictionary = progress(quest_id)
	var requirements: Array = []
	for row in p["objectives"]:
		requirements.append({
			"label": row["label"], "current": row["current"], "required": row["required"],
			"satisfied": row["satisfied"], "hint": row["hint"],
		})
	var routes: Array = []
	for row in p["objectives"]:
		var r: Dictionary = row.get("route", {})
		if typeof(r) == TYPE_DICTIONARY and not r.is_empty():
			var entry: Dictionary = r.duplicate()
			entry["label"] = "Go: %s" % str(row["label"])
			routes.append(entry)
	return {
		"ok": true, "kind": "quest", "id": quest_id,
		"label": str(q.get("name", quest_id)),
		"description": str(q.get("description", "")),
		"icon_kind": "currencies", "icon_id": "gp",
		"requirements": requirements,
		"missing": [],
		"sources": [],
		"routes": routes,
		"objectives": p["objectives"],
		"reward": q.get("reward", {}),
		"reward_description": describe_reward(q.get("reward", {})),
		"locked": not prerequisites_met(quest_id),
		"lock_reason": lock_reason(quest_id),
		"claimed": is_claimed(quest_id),
		"accepted": is_accepted(quest_id),
		"progress_current": p["satisfied"],
		"progress_required": p["total"],
		"progress": clampf(0.0 if p["total"] == 0 else float(p["satisfied"]) / float(p["total"]), 0.0, 1.0),
		"complete": p["all_satisfied"],
		"cycle": [],
	}

## Player-facing reward summary, e.g. "250 GP · Emberpine Log ×5 · 200 Timbercraft XP".
func describe_reward(reward: Dictionary) -> String:
	if reward.is_empty():
		return "No reward"
	var parts: Array[String] = []
	if reward.has("gp"):
		parts.append("%s GP" % Goals._fmt(float(reward["gp"])))
	for item_id in (reward.get("items", {}) as Dictionary).keys():
		parts.append("%s ×%d" % [DataLoader.get_item(str(item_id)).get("name", item_id), int(reward["items"][item_id])])
	for item_id in (reward.get("unlock_items", {}) as Dictionary).keys():
		parts.append("unlocks %s" % DataLoader.get_item(str(item_id)).get("name", item_id))
	for skill_id in (reward.get("xp", {}) as Dictionary).keys():
		parts.append("%s %s XP" % [Goals._fmt(float(reward["xp"][skill_id])), DataLoader.get_skill(str(skill_id)).get("name", skill_id)])
	for note in reward.get("notes", []):
		parts.append(str(note))
	return " · ".join(parts)

# ---------------- persistence ----------------

func serialize() -> Dictionary:
	return {"accepted": _accepted.duplicate(), "claimed": _claimed.duplicate()}

func deserialize(d: Dictionary) -> void:
	_accepted = d.get("accepted", {})
	_claimed = d.get("claimed", {})
	if typeof(_accepted) != TYPE_DICTIONARY:
		_accepted = {}
	if typeof(_claimed) != TYPE_DICTIONARY:
		_claimed = {}
	# Drop records for quests that no longer exist so a content change can never leave
	# a phantom "completed" flag blocking a rebuilt quest chain.
	for id in _accepted.keys():
		if not _quests.has(id):
			_accepted.erase(id)
	for id in _claimed.keys():
		if not _quests.has(id):
			_claimed.erase(id)
