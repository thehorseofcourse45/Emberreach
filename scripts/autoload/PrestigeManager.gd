extends Node
## PrestigeManager — the Ascendancy: reset your journey for permanent, compounding bonuses.
##
## Why it exists: with 34 skills and no reset layer, a finished skill line has nowhere to go.
## Ascendancy gives a spent run a use, and a fresh start a reason to exist.
##
## Design, deliberately small:
##   * The gate is a single lifetime-XP threshold, checked in the live simulation. No
##     prerequisites list, no partial credit, no second currency to earn first.
##   * The reward is one flat global bonus per ascension, registered through ModifierManager
##     like every other source. The simulation never special-cases prestige.
##   * Ascending reuses GameManager.start_new_game(), which is already the one audited path
##     that wipes every subsystem. A prestige that hand-rolled its own reset would be a second
##     source of truth for "what a fresh character looks like", and the two would drift.
##
## The counters survive the reset (that is the whole point) and live in PlayerData.prestige,
## which is saved with the rest of the character.

## Total lifetime XP across every skill decides whether Ascendancy is offered. One number so
## the gate is legible: a player either has the run behind them or does not.
const GATE_XP: float = 50_000_000.0
## Flat bonus per ascension, on both the global XP and global GP keys. Additive within the
## category, so two ascensions stack to 20/20 rather than compounding to 44.
const XP_PER_ASCENSION: float = 5.0
const GP_PER_ASCENSION: float = 5.0
## Ascensions past this stop giving bonuses, so the loop still has a ceiling.
const MAX_ASCENSIONS: int = 100

func _ready() -> void:
	EventBus.game_loaded.connect(_reapply)

# ---------------------------------------------------------------------------
#  State
# ---------------------------------------------------------------------------

func ascensions() -> int:
	return int(PlayerData.prestige.get("ascensions", 0))

func total_ascendancies() -> int:
	return int(PlayerData.prestige.get("total", 0))

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
	if ascensions() >= MAX_ASCENSIONS:
		return "Ascendancy is at its cap"
	var shortfall: float = maxf(0.0, GATE_XP - lifetime_xp())
	return "Reach %s lifetime XP (%s to go)" % [UIStyle.fmt(GATE_XP), UIStyle.fmt(shortfall)]

func can_ascend() -> bool:
	if ascensions() >= MAX_ASCENSIONS:
		return false
	return lifetime_xp() >= GATE_XP

## What the next ascension pays, so the screen can state it before the player commits.
func next_reward() -> Dictionary:
	var nxt: int = ascensions() + 1
	return {
		"ascension": nxt,
		"xp_percent": XP_PER_ASCENSION * float(nxt),
		"gp_percent": GP_PER_ASCENSION * float(nxt),
		"capped": nxt > MAX_ASCENSIONS,
	}

# ---------------------------------------------------------------------------
#  Bonuses
# ---------------------------------------------------------------------------

## Register the prestige bonus. This is the ONLY place prestige touches the simulation —
## everything downstream reads ModifierManager like any other source.
func _reapply() -> void:
	var n: int = ascensions()
	if n <= 0:
		ModifierManager.unregister("prestige")
		return
	ModifierManager.register("prestige", {
		ModifierKeys.GLOBAL_SKILL_XP_PERCENT: XP_PER_ASCENSION * float(n),
		ModifierKeys.GLOBAL_GP_PERCENT: GP_PER_ASCENSION * float(n),
	}, "prestige", "Ascendancy %d" % n)

func bonus_summary() -> String:
	var n: int = ascensions()
	if n <= 0:
		return "No bonuses yet"
	return "+%d%% XP, +%d%% gold" % [
		int(XP_PER_ASCENSION * float(n)), int(GP_PER_ASCENSION * float(n))]

# ---------------------------------------------------------------------------
#  Ascend
# ---------------------------------------------------------------------------

## Reset the run and bank the permanent bonus. Returns {ok, reason}.
##
## The lifetime counters are carried across the reset by hand: PlayerData.initialize_new_game()
## clears stats and the completion log, and a prestige that wiped its own history would leave
## the player with no way to earn the next one.
func ascend() -> Dictionary:
	if not can_ascend():
		return {"ok": false, "reason": blocker() if ascensions() < MAX_ASCENSIONS else "Ascendancy is at its cap"}
	var n: int = ascensions() + 1
	# Snapshot everything that must outlive the reset.
	var kept_stats: Dictionary = _keepable_stats()
	var kept_log: Dictionary = PlayerData.completion_log.duplicate(true)
	GameManager.start_new_game(str(PlayerData.game_mode))
	PlayerData.prestige = {
		"ascensions": n,
		"total": total_ascendancies() + 1,
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
	EventBus.notify("Ascendancy %d — %s" % [n, bonus_summary()], "success")
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
