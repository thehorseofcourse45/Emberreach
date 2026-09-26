extends Node
## EventBus — global signal hub for decoupled communication (autoload singleton).
## Systems emit and listen here instead of holding direct references to each other.
## Registered FIRST in the autoload order so every other singleton can connect safely.
##
## The "declared but never explicitly used" warning is meaningless on a signal hub: a signal is
## emitted here and consumed by listeners in other files, so the declaring class never references
## it. Fifty-eight identical warnings bury the ones worth reading, so the project setting
## gdscript/warnings/unused_signal is off (project.godot, [debug]).

# --- Skill & progression ---
signal skill_xp_gained(skill_id: String, amount: float, new_total: float)
signal skill_level_up(skill_id: String, new_level: int)
signal mastery_xp_gained(skill_id: String, action_id: String, amount: float)
signal mastery_level_up(skill_id: String, action_id: String, new_level: int)
signal mastery_pool_changed(skill_id: String, pool_xp: float)
signal mastery_pool_checkpoint(skill_id: String, percent: float, reached: bool)

# --- Items, currencies, inventory ---
signal item_obtained(item_id: String, quantity: int)
signal item_lost(item_id: String, quantity: int)
signal gp_changed(amount: float, new_total: float)
signal slayer_coins_changed(amount: float, new_total: float)
signal prayer_points_changed(new_total: float)
signal prayer_activated(prayer_id: String)
signal prayer_deactivated(prayer_id: String)
signal item_equipped(slot: int, item_id: String)
signal item_unequipped(slot: int, item_id: String)
signal bank_changed()

# --- Skill actions ---
signal action_started(skill_id: String, action_id: String)
signal action_stopped(skill_id: String, action_id: String)
signal action_tick(skill_id: String, action_id: String, progress: float)
signal action_completed(skill_id: String, action_id: String, rewards: Dictionary)

# --- Combat ---
signal combat_started(context: Dictionary)
signal combat_ended(context: Dictionary)
signal monster_spawned(monster_id: String, hp: int)
signal monster_killed(monster_id: String)
signal player_attacked(damage: int, is_crit: bool)
signal monster_attacked(damage: int)
signal player_died(context: Dictionary)
signal dungeon_completed(dungeon_id: String)
signal status_effect_applied(target: String, effect_id: String)
signal status_effect_expired(target: String, effect_id: String)
signal player_special_attack(sa_id: String)
signal monster_special_attack(sa_id: String)
signal ability_triggered(ability_id: String)

# --- Unlocks & completion ---
signal pet_unlocked(pet_id: String)
signal item_discovered(item_id: String)
signal monster_discovered(monster_id: String)
signal dungeon_discovered(dungeon_id: String)
signal completion_updated(percent: float)
signal shop_upgrade_purchased(upgrade_id: String)

# --- Global / lifecycle ---
signal modifiers_changed()
signal game_saved()
signal game_loaded()
signal offline_progress_summary(summary: Dictionary)
signal notification(text: String, kind: String)

# --- Save health (Stage 1 hardening) ---
## kind is one of: "ok", "saving", "error", "blocked", "recovered".
signal save_status(kind: String, message: String)
signal save_blocked(reason: String)
signal save_recovered(detail: String)

# --- Offline catch-up scheduling ---
signal offline_catchup_started(total_seconds: float)
signal offline_catchup_progress(fraction: float, note: String)
signal offline_catchup_finished(summary: Dictionary)

# --- Goals, quests, achievements ---
signal goal_changed()
signal quest_objective_progress(quest_id: String, index: int, current: float, required: float)
signal quest_completed(quest_id: String)
signal quest_reward_claimed(quest_id: String)
signal achievement_unlocked(achievement_id: String)

# --- Shell / activity strip ---
signal activity_changed()
signal bank_capacity_changed()
signal content_validation_report(issues: Array)
signal unlock_available(kind: String, id: String, label: String)

# --- Shell refresh ---
## Emitted after a bulk state change (offline catch-up, save import, migration). Panels that
## normally rely on granular signals can refresh once here instead of tracking every event.
signal state_refreshed()

func notify(text: String, kind: String = "info") -> void:
    notification.emit(text, kind)
