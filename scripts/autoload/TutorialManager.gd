extends Node
## TutorialManager — first-run onboarding: the short path through a new character's first ten
## minutes, read from res://data/tutorial.json.
##
## Why it exists: 34 skills and a 0.0% progress bar is not a first impression, it is a wall. The
## guide names one next thing at a time and hands the player the button that starts it.
##
## Design, deliberately small:
##   * A step carries a CONDITION and a ROUTE, and nothing else. There is no accept, no claim and
##     no dismiss — a step retires the moment its own condition is already true against live state,
##     so a player who did the thing before ever seeing it is never told to go and do it again.
##   * Conditions read only counters the game already keeps (PlayerData levels, the bank, lifetime
##     stats, claimed tasks). No new event system, so the guide can never disagree with the save.
##   * Only the step INDEX is persisted, in PlayerData.tutorial_step. There is no per-step flag to
##     migrate, and re-deriving from state means a save that loses the index recovers on its own.
##
## Deliberately NOT here: a blocking first-run modal. A dialog in front of a new player is a
## thing to dismiss before the game has told them anything; inline guidance on the screen they
## are already on is the same information with none of the friction.

## Steps resolved in authored `order`, so the JSON file can be edited without reshuffling it.
var _steps: Array[Dictionary] = []

func _ready() -> void:
	_rebuild_index()

func _rebuild_index() -> void:
	_steps.clear()
	for step_id in DataLoader.tutorial.keys():
		var step: Variant = DataLoader.tutorial[step_id]
		if typeof(step) == TYPE_DICTIONARY:
			_steps.append(step as Dictionary)
	_steps.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))

# ---------------------------------------------------------------------------
#  Queries
# ---------------------------------------------------------------------------

func step_count() -> int:
	return _steps.size()

## Index of the step the guide is on. Older than the stored index is impossible (the stored index
## only ever grows within a session) and further ahead than the data is clamped, so a shortened
## step list can never point past its own end.
func current_index() -> int:
	if _steps.is_empty():
		return 0
	return clampi(PlayerData.tutorial_step, 0, _steps.size() - 1)

## The step to show, or {} once the guide is finished. Conditions are re-read on every call rather
## than cached: the panels that draw this refresh on EventBus.state_refreshed, and a stale answer
## is how a guide ends up telling a player to do something they just finished.
func current_step() -> Dictionary:
	if is_finished():
		return {}
	return _steps[current_index()]

## True once the stored index has walked past the last step. This reads the RAW index rather
## than current_index(), which clamps to the last valid step precisely so callers cannot index off
## the end — comparing the clamped value against the size could never be true.
func is_finished() -> bool:
	return _steps.is_empty() or PlayerData.tutorial_step >= _steps.size()

## One row per step for the UI: {index, id, title, body, route, condition}. The index is 0-based
## here; the panel prints "Step N of M" with its own +1 because the panel is what a player reads,
## and an off-by-one in a progress label reads as a bug in the game.
func describe(index: int) -> Dictionary:
	if index < 0 or index >= _steps.size():
		return {}
	var step: Dictionary = _steps[index]
	return {
		"index": index,
		"id": str(step.get("id", "")),
		"title": str(step.get("title", "")),
		"body": str(step.get("body", "")),
		"route": step.get("route", {}),
		"condition": describe_condition(step.get("condition", {})),
		"completion_note": str(step.get("completion_note", "")),
		"satisfied": is_satisfied(step.get("condition", {})),
	}

# ---------------------------------------------------------------------------
#  Conditions
# ---------------------------------------------------------------------------

## Evaluate one condition against authoritative state. Pure: no side effects, no persistence.
func is_satisfied(cond: Variant) -> bool:
	if typeof(cond) != TYPE_DICTIONARY:
		return false
	var c: Dictionary = cond
	var required: float = float(c.get("required", 1))
	var current: float = 0.0
	match str(c.get("kind", "")):
		"skill_level":
			current = float(PlayerData.get_level(str(c.get("skill_id", ""))))
		"have_item":
			current = float(BankManager.get_count(str(c.get("item_id", ""))))
		"kill_monster":
			current = PlayerData.get_stat("monsters_killed", str(c.get("monster_id", "")))
		"do_actions":
			current = _actions_done(c)
		"gp_total":
			current = PlayerData.get_stat("gp_earned")
		"quests_claimed":
			current = float(Quests.claimed_count())
		_:
			# An unknown kind is reported once and never satisfied, so a typo shows up as text
			# rather than as a step that quietly completes itself.
			push_warning("Tutorial: unknown condition kind '%s'" % str(c.get("kind", "")))
			return false
	return current >= required

## Lifetime actions, optionally narrowed to one skill or one skill:action. With neither, every
## action in the game counts: the two buckets below are the ones SkillManager records into.
func _actions_done(c: Dictionary) -> float:
	var skill_id: String = str(c.get("skill_id", ""))
	var action_id: String = str(c.get("action_id", ""))
	var table: Variant = PlayerData.stats.get("actions", {})
	if typeof(table) != TYPE_DICTIONARY:
		return 0.0
	var all: Dictionary = table
	if skill_id != "" and action_id != "":
		return float(all.get("%s:%s" % [skill_id, action_id], 0.0))
	if skill_id != "":
		var total: float = 0.0
		var prefix: String = "%s:" % skill_id
		for key in all.keys():
			if str(key).begins_with(prefix):
				total += float(all[key])
		return total
	var total_all: float = 0.0
	for key in all.keys():
		total_all += float(all[key])
	return total_all

## The condition as {label, current, required, satisfied}, for the panel's progress row.
func describe_condition(cond: Variant) -> Dictionary:
	if typeof(cond) != TYPE_DICTIONARY:
		return {}
	var c: Dictionary = cond
	var required: float = float(c.get("required", 1))
	var current: float = 0.0
	match str(c.get("kind", "")):
		"skill_level":
			current = float(PlayerData.get_level(str(c.get("skill_id", ""))))
		"have_item":
			current = float(BankManager.get_count(str(c.get("item_id", ""))))
		"kill_monster":
			current = PlayerData.get_stat("monsters_killed", str(c.get("monster_id", "")))
		"do_actions":
			current = _actions_done(c)
		"gp_total":
			current = PlayerData.get_stat("gp_earned")
		"quests_claimed":
			current = float(Quests.claimed_count())
	var label: String = str(c.get("label", ""))
	if label == "":
		label = _default_label(c)
	return {
		"label": label,
		"current": current,
		"required": required,
		"satisfied": current >= required,
	}

## A readable goal even when the author left `label` out, so a step never renders as a blank row.
func _default_label(c: Dictionary) -> String:
	match str(c.get("kind", "")):
		"skill_level":
			return "%s level %d" % [str(DataLoader.get_skill(str(c.get("skill_id", ""))).get("name", "?")), int(c.get("required", 1))]
		"have_item":
			return "%s ×%d" % [str(DataLoader.get_item(str(c.get("item_id", ""))).get("name", "?")), int(c.get("required", 1))]
		"kill_monster":
			return "Defeat %s ×%d" % [str(DataLoader.get_monster(str(c.get("monster_id", ""))).get("name", "?")), int(c.get("required", 1))]
		"gp_total":
			return "Earn %s GP" % UIStyle.fmt(float(c.get("required", 0)))
		"quests_claimed":
			return "Claim %d task(s)" % int(c.get("required", 1))
	return "Complete this step"

# ---------------------------------------------------------------------------
#  Advancing
# ---------------------------------------------------------------------------

## Walk past every step the player has already satisfied, in order. Returns true when the guide
## advanced. An ascending veteran clears the whole list in one pass, because the counters the steps
## read are the ones the reset just wiped back to zero — so they are genuinely unmet again.
##
## Called on every Overview refresh rather than on events: the conditions are a handful of
## dictionary reads, and a step completed while the panel was closed must not need a signal to
## notice it.
func next_step() -> bool:
	var start: int = current_index()
	var i: int = start
	while i < _steps.size() and is_satisfied(_steps[i].get("condition", {})):
		i += 1
	if i == start:
		return false
	PlayerData.tutorial_step = i
	SaveManager.save_game()
	return true

# ---------------------------------------------------------------------------
#  Persistence
# ---------------------------------------------------------------------------

## The field itself rides in PlayerData.serialize(); this is the manager-shaped half, wired into
## SaveManager the same way PrestigeManager is.
func serialize() -> Dictionary:
	return {"tutorial_step": PlayerData.tutorial_step}

func deserialize(d: Dictionary) -> void:
	# A save that never had a tutorial section falls back to whatever the player block loaded, so
	# the two halves of the save can never disagree about where the player is. The clamp is the
	# same normaliser PlayerData.deserialize uses, so a hand-edited index cannot leak through.
	PlayerData.tutorial_step = PlayerData.sanitize_tutorial_step(
		d.get("tutorial_step", PlayerData.tutorial_step))
