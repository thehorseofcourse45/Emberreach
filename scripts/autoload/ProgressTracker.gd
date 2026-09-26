extends Node
## ProgressTracker — the one place that turns gameplay events into lifetime progress.
##
## Why this exists: quests and achievements must never be counted by ad-hoc code scattered
## across the simulation. Every mutation point in the game calls exactly one `record_*`
## method here, and these methods are also called by the offline simulator (which runs with
## UI signals suppressed). That is what makes "quests update from actual game events" and
## "offline progress advances quests" the same statement.
##
## Evaluation is debounced: recording sets a dirty flag, and _process evaluates at most a
## few times a second. That keeps a 24-hour offline catch-up from doing hundreds of thousands
## of objective evaluations.

const EVAL_MIN_INTERVAL: float = 0.25

var _dirty: bool = true
var _cooldown: float = 0.0
var _last_satisfied: Dictionary = {}   # quest_id -> satisfied count (change detection)
var _evaluations: int = 0

func _ready() -> void:
	EventBus.game_loaded.connect(func(): mark_dirty(true))
	EventBus.skill_level_up.connect(func(_s, _l): mark_dirty())

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if _dirty and _cooldown <= 0.0:
		evaluate_now()

func mark_dirty(immediate: bool = false) -> void:
	_dirty = true
	if immediate:
		_cooldown = 0.0

# =========================================================================
#  Recording API — called by the authoritative simulation only
# =========================================================================

func record_item_gained(item_id: String, quantity: int) -> void:
	if item_id == "" or quantity <= 0:
		return
	PlayerData.bump_stat("items_gained", item_id, float(quantity))
	mark_dirty()

func record_item_crafted(item_id: String, quantity: int) -> void:
	if item_id == "" or quantity <= 0:
		return
	PlayerData.bump_stat("items_crafted", item_id, float(quantity))
	mark_dirty()

func record_item_sold(item_id: String, quantity: int) -> void:
	if item_id == "" or quantity <= 0:
		return
	PlayerData.bump_stat("items_sold", item_id, float(quantity))
	mark_dirty()

func record_kill(monster_id: String) -> void:
	if monster_id == "":
		return
	PlayerData.bump_stat("monsters_killed", monster_id, 1.0)
	mark_dirty()

func record_dungeon_clear(dungeon_id: String) -> void:
	if dungeon_id == "":
		return
	PlayerData.bump_stat("dungeons_cleared", dungeon_id, 1.0)
	mark_dirty()

func record_action(skill_id: String, action_id: String) -> void:
	if skill_id == "" or action_id == "":
		return
	PlayerData.bump_stat("actions", "%s:%s" % [skill_id, action_id], 1.0)
	mark_dirty()

func record_region_visit(area_id: String) -> void:
	if area_id == "":
		return
	PlayerData.stats["region_visits"][area_id] = true
	mark_dirty()

func record_building(building_id: String) -> void:
	if building_id == "":
		return
	mark_dirty()

func record_death() -> void:
	PlayerData.bump_total("deaths", 1.0)
	mark_dirty()

# =========================================================================
#  Evaluation
# =========================================================================

## Evaluate quests and achievements against current state. Idempotent.
func evaluate_now() -> void:
	_dirty = false
	_cooldown = EVAL_MIN_INTERVAL
	_evaluations += 1
	_emit_quest_progress()
	Achievements.evaluate_all()

func _emit_quest_progress() -> void:
	for quest_id in Quests.accepted_ids():
		var p: Dictionary = Quests.progress(quest_id)
		var satisfied: int = int(p["satisfied"])
		if int(_last_satisfied.get(quest_id, -1)) == satisfied:
			continue
		_last_satisfied[quest_id] = satisfied
		var total: int = int(p["total"])
		EventBus.quest_objective_progress.emit(quest_id, satisfied, float(satisfied), float(total))
		if total > 0 and satisfied == total and not Quests.is_claimed(quest_id):
			EventBus.notify("Task ready to claim: %s" % str(Quests.get_quest(quest_id).get("name", quest_id)), "success")

func evaluation_count() -> int:
	return _evaluations
