extends Node
## EventDirector — the seeded, offline-replayable activity-event layer (autoload singleton).
## Registered AFTER SkillManager (project.godot); called from SkillManager._post_action on the
## existing _rng stream. Plan: docs/superpowers/plans/2026-09-26-activity-layers.md (Task 3).
##
## Contract (the parts a later reader must not "fix"):
##  * No new RNG sources. When a pool has an eligible event, roll_post_action consumes EXACTLY
##    one randf() on the rng the caller passes, in action-completion order — the weight sum is
##    the per-action hit chance and the same draw picks which event fires. Empty pools (or pools
##    with nothing at the player's level) consume NOTHING, so skills without events behave
##    byte-identically to a build before this file existed.
##  * A card can never deadlock the loop. Online + a "manual" policy pauses SkillManager and
##    starts CARD_TIMEOUT_SECONDS — counted on the GAME clock via SkillManager.tick (not wall
##    time), so every driver gets the same timeline: real frames, a test's synchronous tick loop,
##    and an offline slice all resolve a walk-away after exactly CARD_TIMEOUT_SECONDS through the
##    SAME resolve("TIMEOUT") a UI button would use, then resume with the rest of the delta.
##    Offline therefore replays the pause exactly as play does, which is what keeps the two
##    paths' action counts equal for the same seed (plan Review Focus, Tasks 3+4).
##  * resolve() is the single path for a player choice, a stored policy and a timeout; every path
##    applies the chosen effect through the same one-shot slot (_pending_card_effect), and emits
##    event_resolved unless the run is silent.
##  * Offline (SimulationMode.is_silent()) never pauses: cards resolve immediately at offer time
##    through that same path, so a seeded replay reaches the same XP as an online run whose
##    stored policy resolves immediately too.
##
## Deviation from the plan's Interfaces block, deliberate and pinned by Task 3's tests:
##  resolve() takes the event RECORD (Dictionary), not an id string — the plan's own test snippet
##  calls resolve(ev, "TIMEOUT") with a Dictionary, and a record avoids a global id registry for
##  something every caller already holds.

## How long an offered card waits for the player before the watchdog applies the stored policy.
const CARD_TIMEOUT_SECONDS: float = 15.0

## The running bonus offer: the event record (duplicate — never a live DataLoader row) with
## runtime keys "skill_id" and "actions_left" merged in. {} when no bonus is active.
var active_spawn: Dictionary = {}

## The card waiting for a player choice: the event record with "timer" merged in. {} when none.
## Only ever non-empty while SkillManager.paused is true; the timer counts down in
## SkillManager.tick's paused branch (advance_timeout), never in _process.
var pending_card: Dictionary = {}

## One-shot modifier the NEXT attempt claims: {xp_percent: float, success_delta: float}.
## A card pays for exactly one attempt, success or failure; see begin_action().
var _pending_card_effect: Dictionary = {}


func _ready() -> void:
	# A save/load must not resurrect an offer belonging to the session that was just replaced.
	EventBus.game_loaded.connect(_reset_transient)
	# Stopping the activity dismisses a card that was offered inside it: the loop is no longer
	# paused at that point (SkillManager.stop_action clears paused), so leaving the card pending
	# would let the next session overwrite it unanswered. Resolve through the stored policy.
	EventBus.action_stopped.connect(_on_action_stopped)


## The countdown. Called ONLY from SkillManager.tick's paused branch — the game clock, not wall
## time — so a loop driven without frame boundaries (a test's tick loop, an offline slice) still
## resolves a walk-away instead of freezing forever. Returns how much of `delta` the countdown
## consumed, so tick can hand the remainder to the loop after resolving: a card costs exactly
## CARD_TIMEOUT_SECONDS of game time, whether the tick that crossed the deadline is 0.016s or 60s.
func advance_timeout(delta: float) -> float:
	if pending_card.is_empty() or delta <= 0.0:
		return 0.0
	var timer: float = float(pending_card.get("timer", 0.0)) - delta
	if timer > 0.0:
		pending_card["timer"] = timer
		return delta
	# The card ran out: consume only up to its remaining budget, then let the caller resume.
	var consumed: float = maxf(0.0, float(pending_card.get("timer", 0.0)))
	resolve(pending_card.duplicate(true), "TIMEOUT")
	return consumed


## Called from SkillManager.start_action — directly, not by signal, because the action_started
## signal is deliberately suppressed during silent runs and session hygiene must hold there too.
## A new session supersedes its predecessor's event state: an unanswered card resolves through
## the stored policy (identical to a timeout), a one-shot effect earned in the old session does
## not charge the new one, and a spawn offer only survives when it is still about THIS action.
func begin_session(skill_id: String, action_id: String) -> void:
	if not pending_card.is_empty():
		resolve(pending_card.duplicate(true), "TIMEOUT")
	_pending_card_effect = {}
	if not active_spawn.is_empty() and (str(active_spawn.get("skill_id", "")) != skill_id
			or str(active_spawn.get("target_action", "")) != action_id):
		active_spawn = {}
		if not SimulationMode.is_silent():
			EventBus.activity_changed.emit()


# =========================================================================
#  The roll — called from SkillManager._post_action, one line, on SkillManager._rng
# =========================================================================

## Decide whether this completed action fires an event. Called ONLY on the success path (it hangs
## off _post_action), so "one randf per completed action" means per successful completion — the
## same count in live play and in a replay, because both run the same perform_action().
## Returns {} on no hit, else the fired event record (spawns carry skill_id/actions_left).
func roll_post_action(skill_id: String, action_id: String, rng: RandomNumberGenerator) -> Dictionary:
	# 1) An active spawn burns one charge per completed action. This runs BEFORE this
	#    completion's roll, so a spawn offered right now starts with its full duration.
	if not active_spawn.is_empty() and str(active_spawn.get("skill_id", "")) == skill_id:
		var left: int = int(active_spawn.get("actions_left", 1)) - 1
		if left <= 0:
			active_spawn = {}
			if not SimulationMode.is_silent():
				EventBus.activity_changed.emit()
		else:
			active_spawn["actions_left"] = left
	# 2) Eligible pool first, roll second: a pool with no eligible event consumes no draw, so a
	#    low-level player's stream is identical to a build with no events at all.
	var pool: Array = DataLoader.get_skill_events(skill_id)
	if pool.is_empty():
		return {}
	var level: int = PlayerData.get_level(skill_id)
	var eligible: Array = []
	for ev in pool:
		if typeof(ev) == TYPE_DICTIONARY and int(ev.get("min_level", 1)) <= level:
			eligible.append(ev)
	if eligible.is_empty():
		return {}
	# 3) Exactly ONE draw: [0, 100) mapped onto cumulative weights. The weight sum IS the
	#    per-action hit chance; the same number picks which event fires (no second roll).
	var point: float = rng.randf() * 100.0
	var total: float = 0.0
	for ev in eligible:
		total += float(ev.get("weight", 0.0))
	if point >= total:
		return {}
	var cumulative: float = 0.0
	for ev in eligible:
		cumulative += float(ev.get("weight", 0.0))
		if point < cumulative:
			return _offer(ev, skill_id, action_id)
	return {}


# =========================================================================
#  Offering
# =========================================================================

func _offer(record: Dictionary, skill_id: String, action_id: String) -> Dictionary:
	var ev: Dictionary = record.duplicate(true)   # never mutate a live DataLoader row
	match str(ev.get("kind", "")):
		"spawn":
			ev["skill_id"] = skill_id
			ev["actions_left"] = maxi(1, int(ev.get("duration_actions", 1)))
			active_spawn = ev
			if not SimulationMode.is_silent():
				EventBus.event_offered.emit(ev.duplicate(true))
				EventBus.activity_changed.emit()
			return ev
		"card":
			var policy: String = policy_for(str(ev.get("category", "")))
			if policy == "safe" or policy == "greedy":
				return resolve(ev, policy)        # decided in advance: no need to interrupt
			# "manual" (the default for a category nobody has decided): pause the loop and let the
			# game-clock watchdog resolve it if the player walks away. Offline takes the SAME path —
			# a silent run replays the pause rather than skipping it, so its timeline (and therefore
			# its action count) matches an online run of the same seed instead of racing ahead.
			pending_card = ev
			pending_card["timer"] = CARD_TIMEOUT_SECONDS
			SkillManager.paused = true
			if not SimulationMode.is_silent():
				EventBus.event_offered.emit(ev.duplicate(true))
			return ev
	return {}


## The stored preference for a category ("safe" / "greedy" / "manual"). Absent or unknown reads
## as "manual": a category nobody has decided about asks the player rather than deciding for them.
func policy_for(category: String) -> String:
	var stored: String = str(PlayerData.event_policies.get(category, "manual"))
	return stored if ["safe", "greedy", "manual"].has(stored) else "manual"


# =========================================================================
#  Resolution — the single path
# =========================================================================

## Apply a choice. `choice_policy` is a player button ("safe"/"greedy") or "TIMEOUT", which maps
## to the stored policy for the event's category and falls back to "safe" when that is "manual"
## (a walk-away must resolve into the CONSERVATIVE choice — resolving back into "manual" would
## re-pause the loop and deadlock it, the exact failure the plan pins against).
## Returns {event_id, choice_policy, effect}; choice_policy is what was ACTUALLY applied.
func resolve(event: Dictionary, choice_policy: String) -> Dictionary:
	var applied: String = choice_policy
	if applied == "TIMEOUT":
		applied = policy_for(str(event.get("category", "")))
	if applied != "safe" and applied != "greedy":
		applied = "safe"
	var chosen: Dictionary = {}
	var choices: Array = event.get("choices", []) if typeof(event.get("choices", [])) == TYPE_ARRAY else []
	for choice in choices:
		if typeof(choice) == TYPE_DICTIONARY and str((choice as Dictionary).get("policy", "")) == applied:
			chosen = choice
			break
	# Data can legally carry two choices of one policy (the validator only pins the vocabulary);
	# fall back to the first so a resolution always lands on SOME effect, and report its policy.
	if chosen.is_empty() and not choices.is_empty() and typeof(choices[0]) == TYPE_DICTIONARY:
		chosen = choices[0]
		applied = str((chosen as Dictionary).get("policy", applied))
	# The effect goes into the one-shot slot: claimed by begin_action() on the next attempt, in
	# every path alike — button, stored policy or timeout — so there is nothing to keep in sync.
	var effect: Variant = chosen.get("effect", {}) if not chosen.is_empty() else {}
	var merged: Dictionary = {"xp_percent": 0.0, "success_delta": 0.0}
	if typeof(effect) == TYPE_DICTIONARY:
		merged["xp_percent"] = float((effect as Dictionary).get("xp_percent", 0.0))
		merged["success_delta"] = -float((effect as Dictionary).get("fail_chance", 0.0)) / 100.0
	_pending_card_effect = merged
	# Clear a pending card of the same id and release the loop.
	if not pending_card.is_empty() and str(pending_card.get("id", "")) == str(event.get("id", "")):
		pending_card = {}
		SkillManager.paused = false
	if not SimulationMode.is_silent():
		EventBus.event_resolved.emit(str(event.get("id", "")), applied)
	return {"event_id": str(event.get("id", "")), "choice_policy": applied, "effect": merged}


## Switch the running activity to the spawn's target action. Same single activity slot, and the
## switch itself consumes NOTHING: the next perform_action() pays the recipe's costs exactly once
## (inputs verified there, per SkillManager's contract), which is what stops a switch from
## duplicating inputs/outputs or double-consuming charges.
func accept_spawn() -> void:
	if active_spawn.is_empty():
		return
	var skill_id: String = str(active_spawn.get("skill_id", ""))
	var target: String = str(active_spawn.get("target_action", ""))
	# The offer was level-gated by min_level when it rolled; the switch re-validates nothing
	# beyond "this offer still belongs to the activity that is running". A stale offer (the
	# player stopped, or moved to another skill) is dismissed instead of re-pointed.
	if not SkillManager.running or SkillManager.active_skill != skill_id \
			or DataLoader.get_action(skill_id, target).is_empty():
		active_spawn = {}
		if not SimulationMode.is_silent():
			EventBus.activity_changed.emit()
		return
	SkillManager.active_action_id = target
	SkillManager.progress = 0.0
	# The slot now runs a different action, so its node/timing state is rebuilt exactly the way
	# start_action() builds it — mid-flight state from the old action must not carry over.
	var data: Dictionary = DataLoader.get_action(skill_id, target)
	SkillManager.node_max_hp = int(data.get("node_hp", 0))
	SkillManager.node_hp = SkillManager.node_max_hp
	SkillManager.node_respawn_timer = 0.0
	SkillManager.stun_timer = 0.0
	SkillManager.current_interval = SkillManager._compute_interval()
	if not SimulationMode.is_silent():
		EventBus.activity_changed.emit()


# =========================================================================
#  Consumption — called from SkillManager.perform_action()
# =========================================================================

## Claimed at the start of every REAL attempt (after the requirement checks, before the success
## roll): combines the active spawn's bonus — only while its own target action is the one running
## — with the pending card effect, then CLEARS the card effect so it pays for exactly one attempt,
## success or failure. Consumes no RNG: the stream cost of events is the one draw in
## roll_post_action, nothing else.
## Returns {xp_percent: float, success_delta: float} (zeros for skills with no events, so an
## empty pool cannot change a single number in the loop).
func begin_action(skill_id: String, action_id: String) -> Dictionary:
	var xp_percent: float = 0.0
	var success_delta: float = 0.0
	if not active_spawn.is_empty() \
			and str(active_spawn.get("skill_id", "")) == skill_id \
			and str(active_spawn.get("target_action", "")) == action_id:
		var bonus: Variant = active_spawn.get("bonus", {})
		if typeof(bonus) == TYPE_DICTIONARY:
			xp_percent += float((bonus as Dictionary).get("xp_percent", 0.0))
			success_delta -= float((bonus as Dictionary).get("success_penalty", 0.0)) / 100.0
	if not _pending_card_effect.is_empty():
		xp_percent += float(_pending_card_effect.get("xp_percent", 0.0))
		success_delta += float(_pending_card_effect.get("success_delta", 0.0))
		_pending_card_effect = {}
	return {"xp_percent": xp_percent, "success_delta": success_delta}


# =========================================================================
#  Test helpers + lifecycle
# =========================================================================

## Task 3 pin helper: place a spawn offer directly, bypassing the weighted roll (which is a
## random draw and cannot be asserted on). duration is the offer's full actions_left.
func offer_spawn_for_test(skill_id: String, action_id: String, duration: int) -> void:
	active_spawn = {
		"id": "test_spawn", "kind": "spawn", "category": "bonus",
		"weight": 1, "min_level": 1, "skill_id": skill_id,
		"target_action": action_id, "duration_actions": duration,
		"actions_left": duration, "bonus": {},
	}


## Task 3 pin helper: place a card in the pending state exactly as an online manual-policy offer
## would, so the watchdog can be driven with a synthetic delta instead of 15 seconds of wall clock.
func offer_card_for_test(event: Dictionary) -> void:
	pending_card = event.duplicate(true)
	pending_card["timer"] = CARD_TIMEOUT_SECONDS
	SkillManager.paused = true


func _reset_transient() -> void:
	active_spawn = {}
	pending_card = {}
	_pending_card_effect = {}
	SkillManager.paused = false


func _on_action_stopped(_skill_id: String, _action_id: String) -> void:
	if not pending_card.is_empty():
		resolve(pending_card.duplicate(true), "TIMEOUT")
