extends Node
## SkillManager — the generic skill-action framework. EVERY non-combat skill plugs in here
## through data alone: no skill-specific code paths. One action runs at a time (the game's
## single "main activity slot"), matching the intended loop:
##   [select action] -> [timer] -> [success roll] -> [grant XP/mastery/items] -> [auto-repeat].
##
## Correctness contract (this is the part the overhaul hardened):
##  1. Requirements are re-validated on EVERY completion, not only when the action starts.
##     An activity whose inputs run out stops with an explained reason instead of producing
##     free output. This was a live economy exploit before the overhaul.
##  2. Inputs are verified before outputs are produced, and consumption can never remove
##     more than the recipe requires.
##  3. Output is refused (and the activity stops, explained) when storage cannot accept a
##     brand new stack, so nothing is silently created and destroyed in the same tick.
##  4. `repeat_target` gives "craft one / craft N / repeat until stopped" without a second
##     parallel worker: a queue here still occupies the one activity slot.
##  5. tick() is the single authoritative advance step. Online play calls it from _process;
##     offline catch-up calls it in bounded slices through simulate_elapsed(). Identical
##     maths, stop conditions and consumption rules in both.

enum StopReason {
	NONE,                ## still running
	PLAYER,              ## the player pressed stop
	MISSING_MATERIALS,   ## inputs ran out
	STORAGE_FULL,        ## no room for a new stack of the output
	LEVEL_LOST,          ## a game mode lowered the level cap below the requirement
	TOOL_LOST,           ## a required tool/upgrade is no longer owned
	TARGET_REACHED,      ## repeat_target completed
	CHARACTER_DIED,      ## combat defeat ended the session
	OFFLINE_LIMIT,       ## the bounded offline simulation ran out of budget
}

const SIM_SLICE: float = 60.0
const MAX_SIM_ACTIONS: int = 200_000
const DEFAULT_INTERVAL: float = 3.0

var active_skill: String = ""
var active_action_id: String = ""
var running: bool = false
var progress: float = 0.0          ## seconds elapsed on the current action
var current_interval: float = 0.25
var last_action_count: int = 0     ## completed actions this session (for stats)
var total_action_count: int = 0    ## completed actions since the action last started
var repeat_target: int = 0         ## 0 == repeat until stopped; >0 == stop at this count
var stop_reason: int = StopReason.NONE
var stop_detail: String = ""

# Mining / harvesting node state (nodes deplete and respawn).
var node_hp: int = 0
var node_max_hp: int = 0
var node_respawn_timer: float = 0.0
var stun_timer: float = 0.0

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

# =========================================================================
#  Control
# =========================================================================

## Full requirement check. Returns {ok, reason, detail} so the UI can always explain itself.
func check_action(skill_id: String, action_id: String) -> Dictionary:
	var data: Dictionary = DataLoader.get_action(skill_id, action_id)
	if skill_id in ["ranching", "dreamwalking"]:
		return {"ok": false, "reason": "passive", "detail": "Use this skill’s system controls below; it progresses passively."}
	if skill_id == "enchanting":
		data = EnchantingManager.action_data(data)
	if skill_id == "inscription":
		var blocked: String = InscriptionManager.blocker(data)
		if blocked != "":
			return {"ok": false, "reason": "research", "detail": blocked}
	if data.is_empty():
		return {"ok": false, "reason": "unknown_action", "detail": "Unknown action"}
	if PlayerData.get_level(skill_id) < int(data.get("level_required", 1)):
		return {"ok": false, "reason": "level",
			"detail": "Requires %s %d" % [DataLoader.get_skill(skill_id).get("name", skill_id), int(data.get("level_required", 1))]}
	var req_tool: String = str(data.get("required_tool", ""))
	if req_tool != "" and not PlayerData.shop_upgrades.has(req_tool):
		return {"ok": false, "reason": "tool",
			"detail": "Requires %s" % DataLoader.get_shop_upgrade(req_tool).get("name", req_tool)}
	for item_id in (data.get("required_items_equipped", []) as Array):
		if not EquipmentManager.is_equipped(str(item_id)):
			return {"ok": false, "reason": "equipped",
				"detail": "Requires %s equipped" % DataLoader.get_item(str(item_id)).get("name", item_id)}
	var inputs: Dictionary = data.get("input_items", {})
	for item_id in inputs.keys():
		var need: int = int(inputs[item_id])
		if BankManager.get_count(str(item_id)) < need:
			return {"ok": false, "reason": "materials",
				"detail": "Needs %s ×%d (you have %d)" % [DataLoader.get_item(str(item_id)).get("name", item_id),
					need, BankManager.get_count(str(item_id))]}
	var space: Dictionary = _check_output_space(data)
	if not bool(space["ok"]):
		return space
	if skill_id == "farming" and not FarmingManager.has_free_plot():
		return {"ok": false, "reason": "no_space",
			"detail": "All farm plots are occupied — harvest or clear them first"}
	return {"ok": true, "reason": "", "detail": ""}

## Backwards-compatible boolean form.
func can_perform(skill_id: String, action_id: String) -> bool:
	return bool(check_action(skill_id, action_id)["ok"])

func start_action(skill_id: String, action_id: String, target_quantity: int = 0) -> bool:
	if skill_id != "enchanting" or str(EnchantingManager.pending.get("action", "")) != action_id:
		EnchantingManager.pending = {}
	var check: Dictionary = check_action(skill_id, action_id)
	if not bool(check["ok"]):
		EventBus.notify("Cannot start: %s" % str(check["detail"]), "warn")
		return false
	active_skill = skill_id
	active_action_id = action_id
	progress = 0.0
	running = true
	stop_reason = StopReason.NONE
	stop_detail = ""
	repeat_target = maxi(0, target_quantity)
	total_action_count = 0
	current_interval = _compute_interval()
	var data: Dictionary = DataLoader.get_action(skill_id, action_id)
	node_max_hp = int(data.get("node_hp", 0))
	node_hp = node_max_hp
	node_respawn_timer = 0.0
	stun_timer = 0.0
	MasteryManager.update_item_mastery_source(skill_id, action_id)
	if not SimulationMode.is_silent():
		EventBus.action_started.emit(skill_id, action_id)
		EventBus.activity_changed.emit()
	return true

## Stop the current activity, recording why. Safe to call when nothing is running.
func stop_action(reason: int = StopReason.PLAYER, detail: String = "") -> void:
	var was_running: bool = running
	var prev_skill: String = active_skill
	var prev_action: String = active_action_id
	if prev_skill == "enchanting":
		EnchantingManager.pending = {}
	running = false
	active_skill = ""
	active_action_id = ""
	progress = 0.0
	stun_timer = 0.0
	node_hp = 0
	node_max_hp = 0
	node_respawn_timer = 0.0
	stop_reason = reason
	stop_detail = detail
	if was_running:
		ModifierManager.unregister("mastery_item:%s" % prev_skill)
		if not SimulationMode.is_silent():
			if detail != "":
				EventBus.notify(detail, "warn" if reason != StopReason.PLAYER else "info")
			EventBus.action_stopped.emit(prev_skill, prev_action)
			EventBus.activity_changed.emit()

func get_action_data() -> Dictionary:
	if active_skill == "":
		return {}
	var data: Dictionary = DataLoader.get_action(active_skill, active_action_id)
	return EnchantingManager.action_data(data) if active_skill == "enchanting" else data

## Human-readable description of why the activity stopped, for the activity strip.
func stop_reason_text() -> String:
	match stop_reason:
		StopReason.MISSING_MATERIALS: return stop_detail if stop_detail != "" else "Ran out of materials"
		StopReason.STORAGE_FULL: return stop_detail if stop_detail != "" else "Storage is full"
		StopReason.LEVEL_LOST: return "Your level cap dropped below this action"
		StopReason.TOOL_LOST: return "A required tool is no longer owned"
		StopReason.TARGET_REACHED: return "Target quantity reached"
		StopReason.CHARACTER_DIED: return "You were defeated"
		StopReason.OFFLINE_LIMIT: return "Offline simulation budget reached"
		StopReason.PLAYER: return "Stopped"
	return ""

# =========================================================================
#  Tick — online path
# =========================================================================

func _process(delta: float) -> void:
	if SimulationMode.is_silent():
		return   # offline catch-up drives tick() explicitly
	if GameManager.is_paused:
		return   # Pause must stop the activity, not just the playtime clock
	tick(delta)

func tick(delta: float, emit_progress: bool = true) -> void:
	if not running:
		return
	# A stun or respawn pauses the action, but only for the part of delta it actually covers.
	# Anything left over must continue into progress, or a long offline slice silently loses it.
	if stun_timer > 0.0:
		var stunned: float = minf(stun_timer, delta)
		stun_timer = maxf(0.0, stun_timer - delta)
		delta -= stunned      # stunned (e.g. a failed pickpocket)
	if node_respawn_timer > 0.0:
		var respawning: float = minf(node_respawn_timer, delta)
		node_respawn_timer = maxf(0.0, node_respawn_timer - delta)
		if node_respawn_timer <= 0.0:
			node_hp = node_max_hp
		delta -= respawning
	if delta <= 0.0:
		return
	progress += delta
	if emit_progress and not SimulationMode.is_silent():
		EventBus.action_tick.emit(active_skill, active_action_id, progress / maxf(current_interval, 0.001))
	while running and progress >= current_interval:
		progress -= current_interval
		perform_action()
		if not running:
			return
		current_interval = _compute_interval()
		if current_interval <= 0.0:
			# Defensive: a modifier must never produce a zero or negative interval.
			current_interval = 0.25

func _compute_interval() -> float:
	var data: Dictionary = get_action_data()
	if data.is_empty():
		return 0.25
	var floor_s: float = float(data.get("interval_floor", 0.25))
	return ModifierManager.get_interval(active_skill, float(data.get("base_interval", DEFAULT_INTERVAL)), floor_s)

func _success_chance(data: Dictionary) -> float:
	return ActionEstimates._success_chance(active_skill, data)

# =========================================================================
#  Completion
# =========================================================================

## Complete one action. Returns {success, xp, items, stop}.
func perform_action() -> Dictionary:
	var data: Dictionary = get_action_data()
	if data.is_empty():
		stop_action(StopReason.PLAYER)
		return {}
	# Requirement re-validation: the ONLY correct place for this check is here, because it
	# must hold for the 500th action as well as the first.
	if PlayerData.get_level(active_skill) < int(data.get("level_required", 1)):
		stop_action(StopReason.LEVEL_LOST)
		return {"success": false, "stop": "level_lost"}
	var req_tool: String = str(data.get("required_tool", ""))
	if req_tool != "" and not PlayerData.shop_upgrades.has(req_tool):
		stop_action(StopReason.TOOL_LOST)
		return {"success": false, "stop": "tool_lost"}
	var inputs: Dictionary = data.get("input_items", {})
	for item_id in inputs.keys():
		var need: int = int(inputs[item_id])
		if BankManager.get_count(str(item_id)) < need:
			stop_action(StopReason.MISSING_MATERIALS,
				"Stopped: out of %s" % DataLoader.get_item(str(item_id)).get("name", item_id))
			return {"success": false, "stop": "missing_materials"}
	var space: Dictionary = _check_output_space(data)
	if not bool(space["ok"]):
		stop_action(StopReason.STORAGE_FULL, str(space["detail"]))
		return {"success": false, "stop": "storage_full"}
	if active_skill == "farming" and not FarmingManager.has_free_plot():
		stop_action(StopReason.STORAGE_FULL, "All farm plots are occupied")
		return {"success": false, "stop": "no_space"}

	if active_skill == "inscription":
		var blocked: String = InscriptionManager.blocker(data)
		if blocked != "":
			stop_action(StopReason.TOOL_LOST, blocked)
			return {"success": false, "stop": "research"}

	# 1) Success roll. Thieving uses stealth vs perception; others use success_chance.
	if _rng.randf() > _success_chance(data):
		var waste: Dictionary = _on_action_failure(data)
		if not SimulationMode.is_silent():
			EventBus.action_completed.emit(active_skill, active_action_id,
				{"success": false, "items": waste})
		return {"success": false, "stop": "", "items": waste}

	# 2) Consume inputs (with preservation chance), then produce outputs (with doubling).
	_consume_inputs(data, bool(data.get("enchant_job", false)))
	var produced: Dictionary = _produce_outputs(data)

	# 3) Grant skill XP (multipliers applied) and mastery XP.
	var xp: float = float(data.get("base_xp", 0.0)) * ModifierManager.get_skill_xp_multiplier(active_skill)
	if data.has("research_unlock"):
		xp *= 1.0 + ModifierManager.get_modifier("inscription_research_xp_percent") / 100.0
	if xp > 0.0:
		PlayerData.add_xp(active_skill, xp)
	var mastery_time: float = float(data.get("mastery_action_time", -1.0))
	if mastery_time < 0.0:
		mastery_time = current_interval
	var mastery_bonus: float = ModifierManager.get_mastery_xp_bonus(active_skill)
	MasteryManager.add_mastery_xp(active_skill, active_action_id, mastery_time, mastery_bonus)

	last_action_count += 1
	total_action_count += 1
	# Explicit (not signal-driven) so charges also tick during the silent offline catch-up.
	PotionManager.consume_charge(active_skill)
	ProgressTracker.record_action(active_skill, active_action_id)
	SimulationMode.bump(SimulationMode.BUCKET_ACTIONS, "%s:%s" % [active_skill, active_action_id], 1.0)
	_damage_node()
	_post_action(data, mastery_time)
	var rewards: Dictionary = {"success": true, "xp": xp, "items": produced}
	if not SimulationMode.is_silent():
		EventBus.action_completed.emit(active_skill, active_action_id, rewards)
	# 4) Queue/target handling. A target occupies the same single activity slot; it does not
	#    create a parallel worker.
	if data.has("research_unlock") or bool(data.get("enchant_job", false)):
		stop_action(StopReason.TARGET_REACHED, "Research complete" if data.has("research_unlock") else "Enchantment work complete")
	elif repeat_target > 0 and total_action_count >= repeat_target:
		stop_action(StopReason.TARGET_REACHED, "%s ×%d complete" % [str(data.get("name", active_action_id)), repeat_target])
	return rewards

## Refuse an action whose output cannot be stored, rather than creating then deleting items.
func _check_output_space(data: Dictionary) -> Dictionary:
	for item_id in (data.get("output_items", {}) as Dictionary).keys():
		if not BankManager.items.has(str(item_id)) and BankManager.is_full():
			return {"ok": false, "reason": "storage",
				"detail": "Storage is full — no room for %s" % DataLoader.get_item(str(item_id)).get("name", item_id)}
	return {"ok": true, "reason": "", "detail": ""}

func _on_action_failure(data: Dictionary) -> Dictionary:
	var stun: float = float(data.get("stun_seconds", 0.0))
	if stun > 0.0:
		stun_timer = stun
	var dmg: float = float(data.get("fail_damage", 0.0))
	if dmg > 0.0:
		CombatManager.damage_player_out_of_combat(dmg, "Failed action")
	# A failed craft still used up its materials. Without this the failure branch returned before
	# _consume_inputs() and a burnt fish cost the player nothing, which made cooking failure free.
	_consume_inputs(data, true)
	var waste: Dictionary = _produce_failure_output(data)
	if not SimulationMode.is_silent():
		# Name what the failure left behind, so the player sees the loss rather than a bare
		# "Failed". A failure that quietly eats a fish reads as a bug, not as cooking.
		var note: String = "Failed: %s" % str(data.get("name", active_action_id))
		if not waste.is_empty():
			var names: Array[String] = []
			for item_id in waste.keys():
				if int(waste[item_id]) > 0:
					names.append("%s x%d" % [str(DataLoader.get_item(str(item_id)).get("name", item_id)),
						int(waste[item_id])])
			if not names.is_empty():
				note += " — %s" % ", ".join(names)
		EventBus.notification.emit(note, "warn")
	return waste

## What a failed action leaves behind. Cooked food comes out burnt; anything else that takes
## inputs (customcraft) yields nothing, so a failure there is a pure material loss.
## ponytail: one shared burnt item, not one per recipe. Add a per-recipe waste item if the
## fiction ever needs fish to burn differently from bread.
func _produce_failure_output(data: Dictionary) -> Dictionary:
	if str(data.get("fail_output_item", "")) == "":
		return {}
	var item_id: String = str(data["fail_output_item"])
	var qty: int = maxi(0, int(data.get("fail_output_qty", 1)))
	# Respect the same storage guard a success does: a full bank must not silently delete items.
	if not BankManager.items.has(item_id) and BankManager.is_full():
		return {}
	var stored: int = BankManager.add_item(item_id, qty)
	if stored > 0:
		SimulationMode.bump(SimulationMode.BUCKET_ITEMS_PRODUCED, item_id, float(stored))
	# Report it in the same shape as a success so the UI has nothing new to special-case.
	return {item_id: stored}

## Consume the action's inputs. `forced` means the attempt already failed: preservation refunds
## exist to reward good fortune on a craft that worked, and applying one to a failure would refund
## the fish AND hand over burnt food, turning a loss into a free item.
func _consume_inputs(data: Dictionary, forced: bool = false) -> void:
	var preserve: float = 0.0 if forced else ModifierManager.get_preservation_chance(active_skill)
	for item_id in (data.get("input_items", {}) as Dictionary).keys():
		var qty: int = int(data["input_items"][item_id])
		# Each unit independently has a preservation chance to be refunded.
		var consumed: int = 0
		for _i in range(qty):
			if _rng.randf() * 100.0 >= preserve:
				consumed += 1
		if consumed > 0:
			BankManager.remove_item(str(item_id), consumed)
			SimulationMode.bump(SimulationMode.BUCKET_ITEMS_CONSUMED, str(item_id), float(consumed))

func _produce_outputs(data: Dictionary) -> Dictionary:
	var produced: Dictionary = {}
	if active_skill == "inscription" and data.has("quality_product"):
		data = data.duplicate(true)
		data.output_items = InscriptionManager.quality_outputs(data)
	var doubling: float = 0.0 if bool(data.get("enchant_job", false)) else ModifierManager.get_doubling_chance(active_skill)
	var flat_bonus: int = 0 if bool(data.get("enchant_job", false)) else ModifierManager.get_resource_flat(active_skill)
	# The action records do not carry a category, so work at a station is identified by the
	# skill's own type. This is what makes "items you crafted yourself" counters fill at all.
	var is_artisan: bool = str(DataLoader.get_skill(active_skill).get("type", "")) == "artisan"
	for item_id in (data.get("output_items", {}) as Dictionary).keys():
		var qty: int = maxi(0, int(data["output_items"][item_id]) + flat_bonus)
		var total: int = 0
		for _i in range(qty):
			var n: int = 2 if _rng.randf() * 100.0 < doubling else 1
			total += n
		if total > 0:
			var stored: int = BankManager.add_item(str(item_id), total)
			if stored > 0:
				produced[str(item_id)] = stored
			if is_artisan:
				ProgressTracker.record_item_crafted(str(item_id), stored)
			SimulationMode.bump(SimulationMode.BUCKET_ITEMS_PRODUCED, str(item_id), float(stored))
	for sec in data.get("secondary_outputs", []):
		if typeof(sec) != TYPE_DICTIONARY:
			continue
		if _rng.randf() <= float(sec.get("chance", 0.0)):
			var lo: int = int(sec.get("min_qty", 1))
			var hi: int = int(sec.get("max_qty", lo))
			var q: int = _rng.randi_range(lo, maxi(lo, hi))
			var sec_id: String = str(sec.get("item_id", ""))
			var stored_sec: int = BankManager.add_item(sec_id, q)
			if stored_sec > 0:
				produced[sec_id] = int(produced.get(sec_id, 0)) + stored_sec
				SimulationMode.bump(SimulationMode.BUCKET_ITEMS_PRODUCED, sec_id, float(stored_sec))
				if float(sec.get("chance", 0.0)) <= SimulationMode.RARE_DROP_CHANCE_THRESHOLD:
					SimulationMode.bump(SimulationMode.BUCKET_RARE_DROPS, sec_id, float(stored_sec))
	return produced

## GP rewards, summoning marks/charges, pet rolls, archaeology tracking.
func _post_action(data: Dictionary, action_time: float) -> void:
	if active_skill == "inscription":
		InscriptionManager.finish_research(data)
	var gp: float = float(data.get("gp_reward", 0.0))
	if gp > 0.0:
		PlayerData.add_gp(gp * (1.0 + ModifierManager.get_modifier(ModifierKeys.GLOBAL_GP_PERCENT) / 100.0))
	SummoningManager.on_action(active_skill, action_time)
	PetManager.roll_for_skill(active_skill, current_interval)
	if active_skill == "archaeology":
		ArchaeologyManager.on_excavate(active_action_id)

	if active_skill == "farming":
		# The seed was paid through input_items; land it in the first free plot.
		FarmingManager.plant_first_free(FarmingManager.seed_id_for_action(active_action_id), false)

func _damage_node() -> void:
	if node_max_hp <= 0:
		return
	var preserve: float = ModifierManager.get_modifier(
		ModifierKeys.skill_key(active_skill, ModifierKeys.SUFFIX_NODE_PRESERVATION_PERCENT))
	if _rng.randf() * 100.0 < preserve:
		return   # mastery / potion prevented depletion this action
	node_hp -= 1
	if node_hp <= 0:
		node_hp = 0
		var data: Dictionary = get_action_data()
		node_respawn_timer = maxf(0.25, float(data.get("respawn_seconds", 3.0))
			* (1.0 - ModifierManager.get_modifier(ModifierKeys.RESPWAN_TIME_PERCENT) / 100.0))
		progress = 0.0
		if not SimulationMode.is_silent():
			EventBus.notification.emit("Node depleted — respawning", "info")

func is_node_based() -> bool:
	return node_max_hp > 0

# =========================================================================
#  Offline / bounded simulation
# =========================================================================

## Advance the running action by `elapsed` seconds using the SAME tick path as online play.
## Bounded by MAX_SIM_ACTIONS. Caller must set SimulationMode.begin() first.
## Returns {seconds_processed, actions, stopped, stop_reason}.
func simulate_elapsed(elapsed: float) -> Dictionary:
	var out: Dictionary = {"seconds_processed": 0.0, "actions": 0, "stopped": false, "stop_reason": ""}
	if not running or elapsed <= 0.0:
		return out
	var before_actions: int = last_action_count
	var remaining: float = elapsed
	var guard: int = 0
	# ponytail: cap the per-call slice by the interval so node depletion, respawn and stun timers
	# behave exactly as they do online. Wasting a whole slice on one 3s respawn is what made
	# offline mining/harvesting/thieving run at ~45% of online.
	var step_cap: float = maxf(1.0, minf(SIM_SLICE, current_interval))
	var max_steps: int = int(ceil(elapsed / step_cap)) + 2
	while remaining > 1e-6 and running and guard < max_steps:
		guard += 1
		if last_action_count - before_actions >= MAX_SIM_ACTIONS:
			stop_action(StopReason.OFFLINE_LIMIT)
			break
		var slice: float = minf(remaining, step_cap)
		tick(slice, false)
		remaining -= slice
	out["seconds_processed"] = elapsed - remaining
	out["actions"] = last_action_count - before_actions
	out["stopped"] = not running
	out["stop_reason"] = stop_reason_text()
	return out

# =========================================================================
#  Persistence
# =========================================================================

func serialize() -> Dictionary:
	return {
		"active_skill": active_skill, "active_action_id": active_action_id,
		"progress": progress, "running": running, "last_action_count": last_action_count,
		"total_action_count": total_action_count, "repeat_target": repeat_target,
		"node_hp": node_hp, "node_respawn_timer": node_respawn_timer, "stun_timer": stun_timer,
	}

func deserialize(d: Dictionary) -> void:
	active_skill = str(d.get("active_skill", ""))
	active_action_id = str(d.get("active_action_id", ""))
	progress = maxf(0.0, float(d.get("progress", 0.0)))
	running = bool(d.get("running", false))
	last_action_count = maxi(0, int(d.get("last_action_count", 0)))
	total_action_count = maxi(0, int(d.get("total_action_count", 0)))
	repeat_target = maxi(0, int(d.get("repeat_target", 0)))
	node_respawn_timer = maxf(0.0, float(d.get("node_respawn_timer", 0.0)))
	stun_timer = maxf(0.0, float(d.get("stun_timer", 0.0)))
	if active_skill == "" or DataLoader.get_action(active_skill, active_action_id).is_empty():
		running = false
		active_skill = ""
		active_action_id = ""
		return
	var data: Dictionary = DataLoader.get_action(active_skill, active_action_id)
	node_max_hp = int(data.get("node_hp", 0))
	node_hp = clampi(int(d.get("node_hp", node_max_hp)), 0, maxi(node_max_hp, 0))
	current_interval = _compute_interval()
	# A save taken mid-action with materials already gone should not silently resume producing.
	if running:
		var check: Dictionary = check_action(active_skill, active_action_id)
		if not bool(check["ok"]) and str(check["reason"]) == "materials":
			running = false
			stop_reason = StopReason.MISSING_MATERIALS
			stop_detail = "Stopped: %s" % str(check["detail"])
			return
		MasteryManager.update_item_mastery_source(active_skill, active_action_id)
	EventBus.activity_changed.emit()
