class_name ActionQueueTests
extends RefCounted
## Dedicated tests for the persisted FIFO action queue.
## Kept separate from TestRunner so queue regressions are independently discoverable.

static func run(host: Node) -> Dictionary:
	var state: Dictionary = {"passed": 0, "failed": 0, "failures": []}
	var queue: Node = ActionQueueManager

	# Isolate the live singleton and restore its exact state after the suite.
	var saved_queue: Dictionary = queue.serialize()
	var saved_skill: Dictionary = SkillManager.serialize()
	var saved_combat: Dictionary = CombatManager.serialize()
	var saved_items: Dictionary = BankManager.serialize()
	queue.clear()
	if SkillManager.running:
		SkillManager.stop_action(SkillManager.StopReason.PLAYER, "Action queue tests")
	if CombatManager.state != CombatManager.State.IDLE:
		CombatManager.stop_combat("queue tests")

	var first: Dictionary = queue.add_skill_step("woodcutting", "yew_tree", "yew_log", 1000)
	var second: Dictionary = queue.add_skill_step("firemaking", "burn_yew_log", "yew_log", 0)
	var combat: Dictionary = queue.add_combat_step({"type": "area", "id": "farmlands", "monsters": ["chicken"]})
	_assert(first != {}, "a valid Yew skill step is accepted", state)
	_assert(second != {}, "a valid burn-all skill step is accepted", state)
	_assert(combat != {}, "a valid combat step is accepted", state)
	_assert(queue.size() == 3, "steps are retained in FIFO order", state)
	var serialized: Dictionary = queue.serialize()
	_assert(serialized.has("steps") and serialized.has("current_index") and serialized.has("enabled"),
		"serialized queue has the durable queue fields", state)
	_assert(str(serialized["steps"][0]["action_id"]) == "yew_tree",
		"the first serialized step is Yew", state)
	_assert(str(serialized["steps"][1]["action_id"]) == "burn_yew_log",
		"the second serialized step is burn Yew", state)
	_assert(str(serialized["steps"][2]["kind"]) == "combat", "the third serialized step is combat", state)
	_assert(queue.add_skill_step("woodcutting", "not_a_real_action", "yew_log", 1).is_empty(),
		"malformed skill steps are rejected", state)

	# A target that is already satisfied must not start an action or consume inputs. The stack is
	# seeded guaranteed: the bank may be at capacity, and an ordinary add would divert the logs to
	# overflow, leaving the queue — correctly — with nothing to do.
	BankManager.add_item_guaranteed("yew_log", 1000)
	var before_satisfied: int = BankManager.get_total_owned("yew_log")
	queue.clear()
	var satisfied: Dictionary = queue.add_skill_step("woodcutting", "yew_tree", "yew_log", 1000)
	queue.start()
	await host.get_tree().process_frame
	_assert(satisfied != {} and BankManager.get_total_owned("yew_log") == before_satisfied,
		"an already-satisfied target is skipped without changing inventory", state)
	_assert(not queue.has_pending_work(), "an already-satisfied target advances past the step", state)

	# A valid combat step waits for an explicit Continue or Skip decision.
	queue.clear()
	var combat_step: Dictionary = queue.add_combat_step({"type": "area", "id": "farmlands", "monsters": ["chicken"]})
	queue.start()
	await host.get_tree().process_frame
	_assert(combat_step != {} and queue.status == queue.STATUS_COMBAT_WAITING,
		"an open-ended combat step is visibly waiting", state)
	var queued_index: int = queue.current_index
	_assert(queue.continue_queue() and queue.current_index > queued_index,
		"Continue advances the queued combat gate", state)
	queue.clear()
	var combat_step_2: Dictionary = queue.add_combat_step({"type": "area", "id": "farmlands", "monsters": ["chicken"]})
	queue.start()
	await host.get_tree().process_frame
	var queued_index_2: int = queue.current_index
	_assert(combat_step_2 != {} and queue.skip_current() and queue.current_index > queued_index_2,
		"Skip advances the queued combat gate", state)

	# Restore all state captured at the beginning of this suite.
	queue.clear()
	SkillManager.deserialize(saved_skill)
	CombatManager.deserialize(saved_combat)
	BankManager.deserialize(saved_items)
	queue.deserialize(saved_queue)
	return state

static func _assert(condition: bool, label: String, state: Dictionary) -> void:
	if condition:
		state["passed"] = int(state["passed"]) + 1
	else:
		state["failed"] = int(state["failed"]) + 1
		var list: Array = state["failures"]
		list.append(label)
