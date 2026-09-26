extends Node
## ActionQueueManager — persisted FIFO planner over the existing single activity slot.
##
## Queue policy never creates a worker. It asks GameManager to start one authoritative SkillManager
## action or CombatManager expedition, observes the stop reason, and advances only at a safe
## transition boundary. Combat is deliberately an explicit gate: an open-ended combat step waits
## for Continue or Skip because this release has no automatic combat exit condition.

signal queue_changed()
signal queue_paused(reason: String)

const STATUS_IDLE: String = "idle"
const STATUS_READY: String = "ready"
const STATUS_RUNNING: String = "running"
const STATUS_COMBAT_WAITING: String = "combat_waiting"
const STATUS_PAUSED: String = "paused"

var steps: Array = []
var current_index: int = 0
var enabled: bool = false
var status: String = STATUS_IDLE
var last_error: String = ""
var last_applied_index: int = -1

var _transition_pending: bool = false
var _next_id: int = 1
## True only while the queue itself is the thing occupying the single activity slot.
var _owns_slot: bool = false

func _ready() -> void:
	EventBus.action_completed.connect(_on_action_completed)
	EventBus.action_stopped.connect(_on_action_stopped)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.state_refreshed.connect(_on_state_refreshed)
	EventBus.game_loaded.connect(_on_game_loaded)

func _process(_delta: float) -> void:
	if _transition_pending:
		return
	if enabled:
		_defer_transition()

# ---------------------------------------------------------------------------
# Public construction / control
# ---------------------------------------------------------------------------

func add_skill_step(skill_id: String, action_id: String, target_item_id: String,
		target_quantity: int = 0) -> Dictionary:
	var step: Dictionary = {
		"id": _new_step_id(), "kind": "skill", "skill_id": str(skill_id),
		"action_id": str(action_id), "target_item_id": str(target_item_id),
		"target_quantity": maxi(0, int(target_quantity)),
	}
	var normalized: Dictionary = _normalize_step(step)
	if normalized.is_empty():
		last_error = "Invalid skill step"
		queue_changed.emit()
		return {}
	steps.append(normalized)
	_recompute_status()
	queue_changed.emit()
	return normalized.duplicate(true)

func add_combat_step(context: Dictionary, attack_style: String = "", melee_style: String = "") -> Dictionary:
	var ctx: Dictionary = context.duplicate(true)
	var step: Dictionary = {
		"id": _new_step_id(), "kind": "combat", "context": ctx,
		"attack_style": str(attack_style), "melee_style": str(melee_style),
	}
	var normalized: Dictionary = _normalize_step(step)
	if normalized.is_empty():
		last_error = "Invalid combat step"
		queue_changed.emit()
		return {}
	steps.append(normalized)
	_recompute_status()
	queue_changed.emit()
	return normalized.duplicate(true)

func remove_step(step_id: String) -> bool:
	var index: int = _find_step(step_id)
	if index < 0:
		return false
	if index == current_index and _owns_current_activity():
		_stop_owned_activity()
	if index < current_index:
		current_index -= 1
	steps.remove_at(index)
	if current_index >= steps.size():
		current_index = maxi(0, steps.size())
	_recompute_status()
	queue_changed.emit()
	if enabled:
		_defer_transition()
	return true

func move_step(step_id: String, direction: int) -> bool:
	var index: int = _find_step(step_id)
	if index < 0 or direction == 0:
		return false
	var target: int = clampi(index + signi(int(direction)), 0, maxi(0, steps.size() - 1))
	if target == index:
		return false
	# Read the current step's id before the array shifts, or we track the wrong element.
	var current_id: String = str(steps[current_index].get("id", "")) if current_index < steps.size() else ""
	var moved: Dictionary = steps[index]
	steps.remove_at(index)
	steps.insert(target, moved)
	if current_id != "" and current_index < steps.size():
		# The current ID may have shifted; restore it when possible.
		for i in range(steps.size()):
			if str(steps[i].get("id", "")) == current_id:
				current_index = i
				break
	_recompute_status()
	queue_changed.emit()
	return true

func start() -> bool:
	if steps.is_empty():
		last_error = "Queue is empty"
		return false
	# Judge ownership against the step that is running *now*, before the index is reset.
	var was_running_index: int = current_index
	var owned: bool = _owns_current_activity()
	current_index = 0
	enabled = true
	last_error = ""
	_recompute_status()
	if owned:
		current_index = was_running_index
		_stop_owned_activity()
		current_index = 0
		_defer_transition()
	else:
		_advance_now()
	return true

func pause(reason: String = "Paused by player") -> void:
	enabled = false
	status = STATUS_PAUSED
	last_error = reason
	if _owns_current_activity():
		_stop_owned_activity()
	queue_paused.emit(reason)
	queue_changed.emit()

func continue_queue() -> bool:
	if steps.is_empty() or current_index >= steps.size():
		return false
	# Continue means resolve the current combat gate. It never invents a skill completion.
	var step: Dictionary = steps[current_index]
	if str(step.get("kind", "")) == "combat":
		if _owns_current_activity():
			CombatManager.stop_combat("queue_continue")
		current_index += 1
		# Only an already-enabled queue may be re-armed, so Pause is not undone by a stray click.
		if enabled:
			last_error = ""
		_recompute_status()
		_defer_transition()
		return true
	# A paused skill can be retried; a running skill is simply left alone. Resuming stays the
	# player's job: this never re-arms a queue that was deliberately paused.
	if enabled:
		last_error = ""
	_recompute_status()
	_defer_transition()
	return true

func skip_current() -> bool:
	if current_index >= steps.size():
		return false
	if _owns_current_activity():
		_stop_owned_activity()
	current_index += 1
	enabled = true
	last_error = ""
	_recompute_status()
	_defer_transition()
	return true

func clear() -> void:
	if _owns_current_activity():
		_stop_owned_activity()
	steps.clear()
	current_index = 0
	enabled = false
	status = STATUS_IDLE
	last_error = ""
	last_applied_index = -1
	queue_changed.emit()

func is_empty() -> bool:
	return steps.is_empty()

func size() -> int:
	return steps.size()

func current_step() -> Dictionary:
	if current_index < 0 or current_index >= steps.size():
		return {}
	return (steps[current_index] as Dictionary).duplicate(true)

func get_step(step_id: String) -> Dictionary:
	var index: int = _find_step(step_id)
	if index < 0:
		return {}
	return (steps[index] as Dictionary).duplicate(true)

func has_pending_work() -> bool:
	return current_index < steps.size()

func waiting_for_combat() -> bool:
	return enabled and current_index < steps.size() and str((steps[current_index] as Dictionary).get("kind", "")) == "combat"

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {"steps": steps.duplicate(true), "current_index": current_index, "enabled": enabled,
		"status": status, "last_error": last_error}

func deserialize(source: Dictionary) -> void:
	steps.clear()
	var raw_steps: Variant = source.get("steps", [])
	if typeof(raw_steps) == TYPE_ARRAY:
		for raw in (raw_steps as Array):
			var normalized: Dictionary = _normalize_step(raw)
			if not normalized.is_empty():
				steps.append(normalized)
	current_index = clampi(int(source.get("current_index", 0)), 0, maxi(0, steps.size()))
	enabled = bool(source.get("enabled", false))
	last_error = str(source.get("last_error", ""))
	# Step ids minted after a load must not collide with loaded ones.
	for step in steps:
		var suffix: String = str((step as Dictionary).get("id", "")).trim_prefix("queue-")
		if suffix.is_valid_int():
			_next_id = maxi(_next_id, int(suffix))
	_owns_slot = false
	# status is derived state: never trust the copy in the save file.
	_recompute_status()
	# A restored combat step waits for the player rather than restarting unattended.
	if current_index < steps.size() and str((steps[current_index] as Dictionary).get("kind", "")) == "combat":
		enabled = false
		status = STATUS_COMBAT_WAITING
	# A restored queue must not claim an unrelated manual activity. Reconcile on the next frame.
	_defer_transition()
	queue_changed.emit()

# ---------------------------------------------------------------------------
# Offline hook
# ---------------------------------------------------------------------------

func after_simulation_slice() -> void:
	if not enabled:
		return
	_defer_transition()

# ---------------------------------------------------------------------------
# Transition engine
# ---------------------------------------------------------------------------

func _defer_transition() -> void:
	if _transition_pending:
		return
	_transition_pending = true
	call_deferred("_advance_now")

func _advance_now() -> void:
	_transition_pending = false
	if not enabled:
		return
	var guard: int = 0
	while enabled and current_index < steps.size() and guard < 32:
		guard += 1
		var step: Dictionary = steps[current_index]
		match str(step.get("kind", "")):
			"skill":
				if not _advance_skill(step):
					break
			"combat":
				if not _advance_combat(step):
					break
			_:
				current_index += 1
		_recompute_status()
		if guard >= 32:
			last_error = "Queue transition guard reached"
			enabled = false
			queue_changed.emit()
			break
	queue_changed.emit()

func _advance_skill(step: Dictionary) -> bool:
	var skill_id: String = str(step.get("skill_id", ""))
	var action_id: String = str(step.get("action_id", ""))
	var target_item: String = str(step.get("target_item_id", ""))
	var target_quantity: int = int(step.get("target_quantity", 0))
	var running_here: bool = SkillManager.running and SkillManager.active_skill == skill_id \
		and SkillManager.active_action_id == action_id
	var count: int = BankManager.get_total_owned(target_item)
	if target_quantity > 0 and count >= target_quantity:
		if running_here:
			SkillManager.stop_action(SkillManager.StopReason.TARGET_REACHED, "Queue target reached")
		current_index += 1
		return true
	if target_quantity == 0 and count <= 0:
		if running_here:
			SkillManager.stop_action(SkillManager.StopReason.TARGET_REACHED, "Queue target reached")
		current_index += 1
		return true
	if running_here:
		return false
	# An unrelated manual activity is not ours. Do not steal the slot; pause instead.
	if SkillManager.running or CombatManager.state != CombatManager.State.IDLE:
		enabled = false
		status = STATUS_PAUSED
		last_error = "Another activity owns the slot"
		queue_paused.emit(last_error)
		return false
	var check: Dictionary = SkillManager.check_action(skill_id, action_id)
	if not bool(check.get("ok", false)):
		enabled = false
		status = STATUS_PAUSED
		last_error = str(check.get("detail", "Action unavailable"))
		queue_paused.emit(last_error)
		return false
	# Queue-owned activity bypasses GameManager's manual-pause hook.
	SkillManager.start_action(skill_id, action_id, 0)
	if not SkillManager.running:
		enabled = false
		status = STATUS_PAUSED
		last_error = "Could not start queued action"
		queue_paused.emit(last_error)
		return false
	status = STATUS_RUNNING
	last_applied_index = current_index
	_owns_slot = true
	return false

func _advance_combat(step: Dictionary) -> bool:
	if CombatManager.state != CombatManager.State.IDLE:
		# A running combat is waiting for the player decision. Do not infer completion.
		status = STATUS_COMBAT_WAITING
		return false
	if SkillManager.running:
		enabled = false
		status = STATUS_PAUSED
		last_error = "Another activity owns the slot"
		queue_paused.emit(last_error)
		return false
	var context: Dictionary = (step.get("context", {}) as Dictionary).duplicate(true)
	if str(step.get("attack_style", "")) != "":
		context["attack_style"] = str(step.get("attack_style", ""))
	if str(step.get("melee_style", "")) != "":
		context["melee_style"] = str(step.get("melee_style", ""))
	CombatManager.start_combat(context)
	if CombatManager.state == CombatManager.State.IDLE:
		enabled = false
		status = STATUS_PAUSED
		last_error = "Could not start queued combat"
		queue_paused.emit(last_error)
		return false
	status = STATUS_COMBAT_WAITING
	last_applied_index = current_index
	_owns_slot = true
	return false

func _on_action_completed(_skill_id: String, _action_id: String, _rewards: Dictionary) -> void:
	if enabled:
		_defer_transition()

func _on_action_stopped(_skill_id: String, _action_id: String) -> void:
	if enabled:
		_defer_transition()

func _on_combat_ended(_context: Dictionary) -> void:
	if enabled:
		# A combat end is not completion. Keep the gate closed for explicit Continue/Skip.
		status = STATUS_COMBAT_WAITING
		queue_changed.emit()

func _on_state_refreshed() -> void:
	# Offline catch-up emits this when it finishes. Starting a queued fight here would bypass the
	# "offline combat" setting, so leave combat steps for the player to launch.
	if enabled and not OfflineProgression.is_running:
		_defer_transition()

func _on_game_loaded() -> void:
	# Serialized state is already loaded by SaveManager; reconcile without assuming ownership.
	_defer_transition()

# ---------------------------------------------------------------------------
# Validation / helpers
# ---------------------------------------------------------------------------

func _normalize_step(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = raw
	var kind: String = str(source.get("kind", ""))
	if kind == "skill":
		var skill_id: String = str(source.get("skill_id", ""))
		var action_id: String = str(source.get("action_id", ""))
		var target_item: String = str(source.get("target_item_id", ""))
		if DataLoader.get_action(skill_id, action_id).is_empty() or not DataLoader.items.has(target_item):
			return {}
		return {"id": str(source.get("id", _new_step_id())), "kind": "skill", "skill_id": skill_id,
			"action_id": action_id, "target_item_id": target_item,
			"target_quantity": maxi(0, int(source.get("target_quantity", 0)))}
	if kind == "combat":
		var context: Dictionary = (source.get("context", {}) as Dictionary).duplicate(true) if typeof(source.get("context", {})) == TYPE_DICTIONARY else {}
		if not _valid_combat_context(context):
			return {}
		return {"id": str(source.get("id", _new_step_id())), "kind": "combat", "context": context,
			"attack_style": str(source.get("attack_style", context.get("attack_style", ""))),
			"melee_style": str(source.get("melee_style", context.get("melee_style", "")))}
	return {}

func _valid_combat_context(context: Dictionary) -> bool:
	var place_id: String = str(context.get("id", ""))
	var monsters: Array = context.get("monsters", [])
	if place_id == "" or typeof(monsters) != TYPE_ARRAY or monsters.is_empty():
		return false
	var place: Dictionary = DataLoader.dungeons.get(place_id, {}) if str(context.get("type", "")) == "dungeon" else DataLoader.areas.get(place_id, {})
	if place.is_empty():
		return false
	for monster_id in monsters:
		if not DataLoader.monsters.has(str(monster_id)):
			return false
	return true

func _new_step_id() -> String:
	_next_id += 1
	return "queue-%d" % _next_id

func _find_step(step_id: String) -> int:
	for i in range(steps.size()):
		if str((steps[i] as Dictionary).get("id", "")) == step_id:
			return i
	return -1

func _recompute_status() -> void:
	if steps.is_empty():
		status = STATUS_IDLE
	elif not enabled:
		if status != STATUS_PAUSED:
			status = STATUS_PAUSED if last_error != "" else STATUS_READY
	elif current_index >= steps.size():
		enabled = false
		status = STATUS_IDLE
	else:
		var kind: String = str((steps[current_index] as Dictionary).get("kind", ""))
		if kind == "combat":
			status = STATUS_COMBAT_WAITING
		else:
			status = STATUS_RUNNING if SkillManager.running else STATUS_READY

func _owns_current_activity() -> bool:
	if not _owns_slot:
		return false
	if current_index < 0 or current_index >= steps.size():
		return false
	var step: Dictionary = steps[current_index]
	if str(step.get("kind", "")) == "skill":
		return SkillManager.running and SkillManager.active_skill == str(step.get("skill_id", "")) \
			and SkillManager.active_action_id == str(step.get("action_id", ""))
	# Identity, not merely "a fight is running": the queue must never stop a fight it did not start.
	return CombatManager.state != CombatManager.State.IDLE \
		and CombatManager.current_monster_id in _queued_monster_ids(step)

func _queued_monster_ids(step: Dictionary) -> Array:
	var out: Array = []
	for monster_id in ((step.get("context", {}) as Dictionary).get("monsters", []) as Array):
		out.append(str(monster_id))
	return out

func _stop_owned_activity() -> void:
	if not _owns_slot:
		return
	_owns_slot = false
	if current_index < 0 or current_index >= steps.size():
		return
	var step: Dictionary = steps[current_index]
	if str(step.get("kind", "")) == "skill" and SkillManager.running:
		SkillManager.stop_action(SkillManager.StopReason.PLAYER, "Queue control")
	elif str(step.get("kind", "")) == "combat" and CombatManager.state != CombatManager.State.IDLE:
		CombatManager.stop_combat("queue_control")

# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------

func step_label(step: Dictionary) -> String:
	if str(step.get("kind", "")) == "skill":
		var action: Dictionary = DataLoader.get_action(str(step.get("skill_id", "")), str(step.get("action_id", "")))
		var item_name: String = str(DataLoader.get_item(str(step.get("target_item_id", ""))).get("name", step.get("target_item_id", "")))
		var target: int = int(step.get("target_quantity", 0))
		return "%s → %s %s" % [str(action.get("name", step.get("action_id", ""))), item_name,
			"all" if target == 0 else "until %s" % _format_number(target)]
	var ctx: Dictionary = step.get("context", {})
	var place: Dictionary = DataLoader.dungeons.get(str(ctx.get("id", "")), {}) if str(ctx.get("type", "")) == "dungeon" else DataLoader.areas.get(str(ctx.get("id", "")), {})
	return "Fight %s" % str(place.get("name", ctx.get("id", "unknown")))

func _format_number(value: int) -> String:
	var text: String = str(absi(int(value)))
	var out: String = ""
	var count: int = 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
