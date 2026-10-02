extends Node
## PrestigeManager — the Ascendancy: reset your journey for Ascendancy Points, spent on a
## permanent node tree.
##
## Why it exists: with 39 skills and no reset layer, a finished skill line has nowhere to go.
## Ascendancy gives a spent run a use, and a fresh start a reason to exist.
##
## Design:
##   * The gate is a single lifetime-XP threshold, checked in the live simulation. No
##     prerequisites list, no partial credit, no second currency to earn first.
##   * Each ascension grants ONE Ascendancy Point. Points are spent on ranked nodes defined
##     in data/ascendancy.json — long-term goals the player chooses between, rather than one
##     fixed bonus. A node can require other nodes, giving the tree real shape.
##   * The reward is still ONE registered ModifierManager source ("prestige"): the SUM of every
##     purchased node rank's modifiers. The simulation never special-cases prestige, exactly as
##     before — only where the numbers come from changed (bought nodes, not the raw count).
##   * Ascending reuses GameManager.start_new_game(), the one audited reset path. Points and
##     purchased nodes survive the reset (that is the whole point) and live in PlayerData.prestige.

## Total this run's XP across every skill decides whether Ascendancy is offered. One number so
## the gate is legible: a player either has the run behind them or does not.
const GATE_XP: float = 50_000_000.0
## Points granted per ascension. One, so the node tree is the only place the economy lives.
const POINTS_PER_ASCENSION: int = 1

func _ready() -> void:
	EventBus.game_loaded.connect(_reapply)

# ---------------------------------------------------------------------------
#  State
# ---------------------------------------------------------------------------

func ascensions() -> int:
	return int(PlayerData.prestige.get("ascensions", 0))

func total_ascendancies() -> int:
	return int(PlayerData.prestige.get("total", 0))

## Unspent Ascendancy Points available to spend on nodes.
func points() -> int:
	return int(PlayerData.prestige.get("points", 0))

## Ascendancy Points earned over the character's lifetime (spent + unspent).
func points_earned() -> int:
	return int(PlayerData.prestige.get("points_earned", 0))

## {node_id: rank} of purchased nodes.
func purchased() -> Dictionary:
	var p: Variant = PlayerData.prestige.get("nodes", {})
	return p if p is Dictionary else {}

func node_rank(node_id: String) -> int:
	return int(purchased().get(node_id, 0))

## Points sunk into the tree so far (sum of rank * cost).
func points_spent() -> int:
	var total: int = 0
	for node_id in purchased().keys():
		var node: Dictionary = DataLoader.ascendancy.get(str(node_id), {})
		total += int(node.get("cost", 0)) * int(purchased()[node_id])
	return total

## Lifetime XP across all skills, read from the same XP values the game awards.
func lifetime_xp() -> float:
	var total: float = 0.0
	for skill_id in DataLoader.get_skill_ids():
		total += PlayerData.get_xp(skill_id)
	return total

## Why the player cannot ascend yet, or "" when they can. One sentence, never a percentage
## with no meaning: the gap in absolute XP is the actionable number.
func blocker() -> String:
	if can_ascend():
		return ""
	var shortfall: float = maxf(0.0, GATE_XP - lifetime_xp())
	return "Reach %s this run’s XP (%s to go)" % [UIStyle.fmt(GATE_XP), UIStyle.fmt(shortfall)]

func can_ascend() -> bool:
	return lifetime_xp() >= GATE_XP

## What the next ascension pays, so the screen can state it before the player commits.
func next_reward() -> Dictionary:
	var nxt: int = ascensions() + 1
	return {
		"ascension": nxt,
		"points": POINTS_PER_ASCENSION,
	}

# ---------------------------------------------------------------------------
#  Node tree — query, spend, refund
# ---------------------------------------------------------------------------

## A node's full state for the UI: current rank, whether its prerequisites are met, whether the
## next rank is affordable, and the reason it cannot be bought (or "").
func node_state(node_id: String) -> Dictionary:
	var node: Dictionary = DataLoader.ascendancy.get(node_id, {})
	if node.is_empty():
		return {"ok": false, "reason": "Unknown node"}
	var rank: int = node_rank(node_id)
	var max_rank: int = int(node.get("max_rank", 1))
	var cost: int = int(node.get("cost", 1))
	var blocker: String = _node_blocker(node_id)
	return {
		"ok": true,
		"id": node_id,
		"name": str(node.get("name", node_id)),
		"description": str(node.get("description", "")),
		"rank": rank,
		"max_rank": max_rank,
		"cost": cost,
		"maxed": rank >= max_rank,
		"can_buy": blocker == "",
		"blocker": blocker,
	}

## Why the next rank of a node cannot be bought, or "" when it can.
func _node_blocker(node_id: String) -> String:
	var node: Dictionary = DataLoader.ascendancy.get(node_id, {})
	if node.is_empty():
		return "Unknown node"
	if node_rank(node_id) >= int(node.get("max_rank", 1)):
		return "Already at maximum rank"
	for req in node.get("requires", []):
		if node_rank(str(req)) <= 0:
			var req_name: String = str(DataLoader.ascendancy.get(str(req), {}).get("name", req))
			return "Requires %s" % req_name
	if points() < int(node.get("cost", 1)):
		return "Needs %d point%s" % [int(node.get("cost", 1)), "" if int(node.get("cost", 1)) == 1 else "s"]
	return ""

## Buy one rank of a node. Returns {ok, reason}.
func spend(node_id: String) -> Dictionary:
	var blocker: String = _node_blocker(node_id)
	if blocker != "":
		return {"ok": false, "reason": blocker}
	var node: Dictionary = DataLoader.ascendancy.get(node_id, {})
	var cost: int = int(node.get("cost", 1))
	var nodes: Dictionary = purchased().duplicate(true)
	nodes[node_id] = int(nodes.get(node_id, 0)) + 1
	PlayerData.prestige["nodes"] = nodes
	PlayerData.prestige["points"] = points() - cost
	_reapply()
	SaveManager.save_game(true)
	EventBus.state_refreshed.emit()
	EventBus.notify("Ascendancy: %s rank %d" % [str(node.get("name", node_id)), int(nodes[node_id])], "success")
	return {"ok": true, "reason": ""}

## Refund one rank of a node, returning its point. A node another node still depends on cannot
## be dropped below rank 1, so the tree never contradicts itself.
func refund_node(node_id: String) -> Dictionary:
	var rank: int = node_rank(node_id)
	if rank <= 0:
		return {"ok": false, "reason": "Nothing to refund"}
	var node: Dictionary = DataLoader.ascendancy.get(node_id, {})
	if rank == 1:
		for other_id in DataLoader.ascendancy.keys():
			if str(other_id) == "_comment":
				continue
			if node_rank(str(other_id)) > 0 and (DataLoader.ascendancy[other_id].get("requires", []) as Array).has(node_id):
				return {"ok": false, "reason": "%s still depends on it" % str(DataLoader.ascendancy[other_id].get("name", other_id))}
	var cost: int = int(node.get("cost", 1))
	var nodes: Dictionary = purchased().duplicate(true)
	nodes[node_id] = rank - 1
	if int(nodes[node_id]) <= 0:
		nodes.erase(node_id)
	PlayerData.prestige["nodes"] = nodes
	PlayerData.prestige["points"] = points() + cost
	_reapply()
	SaveManager.save_game(true)
	EventBus.state_refreshed.emit()
	EventBus.notify("Ascendancy: refunded %s" % str(node.get("name", node_id)), "info")
	return {"ok": true, "reason": ""}

## Full tree refund — hands every spent point back and clears all nodes. The one escape hatch so
## a player is never permanently stuck behind a bad early choice.
func respec() -> Dictionary:
	PlayerData.prestige["points"] = points() + points_spent()
	PlayerData.prestige["nodes"] = {}
	_reapply()
	SaveManager.save_game(true)
	EventBus.state_refreshed.emit()
	EventBus.notify("Ascendancy respec: all points returned", "info")
	return {"ok": true, "reason": ""}

# ---------------------------------------------------------------------------
#  Bonuses
# ---------------------------------------------------------------------------

## Register the prestige bonus: the SUM of every purchased node rank's modifiers. This is the
## ONLY place prestige touches the simulation — everything downstream reads ModifierManager.
func _reapply() -> void:
	var combined: Dictionary = {}
	for node_id in purchased().keys():
		var node: Dictionary = DataLoader.ascendancy.get(str(node_id), {})
		var rank: int = int(purchased()[node_id])
		if node.is_empty() or rank <= 0:
			continue
		for key in node.get("modifiers", {}).keys():
			combined[key] = float(combined.get(key, 0.0)) + float(node["modifiers"][key]) * float(rank)
	if combined.is_empty():
		ModifierManager.unregister("prestige")
		return
	ModifierManager.register("prestige", combined, "prestige", "Ascendancy")

func bonus_summary() -> String:
	var combined: Dictionary = {}
	for node_id in purchased().keys():
		var node: Dictionary = DataLoader.ascendancy.get(str(node_id), {})
		var rank: int = int(purchased()[node_id])
		if node.is_empty() or rank <= 0:
			continue
		for key in node.get("modifiers", {}).keys():
			combined[key] = float(combined.get(key, 0.0)) + float(node["modifiers"][key]) * float(rank)
	if combined.is_empty():
		return "No nodes bought yet"
	return UIStyle.describe_modifier_table(combined)

# ---------------------------------------------------------------------------
#  Ascend
# ---------------------------------------------------------------------------

## Reset the run and bank an Ascendancy Point. Returns {ok, reason}.
##
## Points and purchased nodes outlive the reset by hand, alongside the lifetime counters:
## PlayerData.initialize_new_game() clears stats and the completion log, and a prestige that
## wiped its own history would leave the player with no way to earn the next ascension.
func ascend() -> Dictionary:
	if not can_ascend():
		return {"ok": false, "reason": blocker()}
	var n: int = ascensions() + 1
	# Snapshot everything that must outlive the reset.
	var kept_stats: Dictionary = _keepable_stats()
	var kept_log: Dictionary = PlayerData.completion_log.duplicate(true)
	var kept_nodes: Dictionary = purchased().duplicate(true)
	var kept_points: int = points() + POINTS_PER_ASCENSION
	var kept_earned: int = points_earned() + POINTS_PER_ASCENSION
	GameManager.start_new_game(str(PlayerData.game_mode))
	PlayerData.prestige = {
		"ascensions": n,
		"total": total_ascendancies() + 1,
		"points": kept_points,
		"points_earned": kept_earned,
		"nodes": kept_nodes,
		"history": kept_log,
		"lifetime_stats": kept_stats,
	}
	# The collection log is the player's record of the whole run, not of this one.
	for item_id in (kept_log.get("items", {}) as Dictionary).keys():
		PlayerData.discover_item(str(item_id))
	for monster_id in (kept_log.get("monsters", {}) as Dictionary).keys():
		PlayerData.discover_monster(str(monster_id))
	for dungeon_id in (kept_log.get("dungeons", {}) as Dictionary).keys():
		PlayerData.discover_dungeon(str(dungeon_id))
	# Lifetime counters are restored AFTER the reset, which is what clears them.
	PlayerData.stats = kept_stats
	_reapply()
	SaveManager.save_game(true)
	EventBus.state_refreshed.emit()
	EventBus.notify("Ascendancy %d — +%d Ascendancy Point" % [n, POINTS_PER_ASCENSION], "success")
	return {"ok": true, "reason": ""}

## The lifetime counters worth carrying across an ascension. Progress towards the gate and
## towards milestones should not reset; the player is not re-earning the same numbers.
func _keepable_stats() -> Dictionary:
	var kept: Dictionary = PlayerData.default_stats()
	for bucket in ["items_gained", "items_crafted", "items_sold", "monsters_killed",
			"dungeons_cleared", "actions", "region_visits"]:
		if PlayerData.stats.has(bucket):
			kept[bucket] = (PlayerData.stats[bucket] as Variant).duplicate(true)
	for bucket in ["deaths", "gp_earned", "gp_spent", "quests_completed",
			"offline_seconds_processed"]:
		if PlayerData.stats.has(bucket):
			kept[bucket] = PlayerData.stats[bucket]
	return kept

# ---------------------------------------------------------------------------
#  Persistence
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {"prestige": PlayerData.prestige}

func deserialize(d: Dictionary) -> void:
	PlayerData.prestige = d.get("prestige", {})
	_reapply()
