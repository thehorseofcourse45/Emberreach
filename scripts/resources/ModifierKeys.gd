class_name ModifierKeys
extends RefCounted
## Central registry of modifier key strings so no module typos a key.
## Convention:  "<scope>_<stat>" where scope is global | <skill_id> | melee | ranged | magic.
## All *_percent values are percentages (e.g. 15.0 means +15%).

# ---- Global / per-skill XP & mastery ----
const GLOBAL_SKILL_XP_PERCENT := "global_skill_xp_percent"
const GLOBAL_MASTERY_XP_PERCENT := "global_mastery_xp_percent"
const GLOBAL_GP_PERCENT := "global_gp_percent"
const GLOBAL_SLAYER_COINS_PERCENT := "global_slayer_coins_percent"
const GLOBAL_DOUBLE_LOOT_PERCENT := "global_double_loot_percent"
const BANK_SPACE_FLAT := "bank_space_flat"
const AUTO_EAT_THRESHOLD_PERCENT := "auto_eat_threshold_percent"
const AUTO_EAT_EFFICIENCY_PERCENT := "auto_eat_efficiency_percent"
const BLESSED_BONE_OFFERING_FLAT := "blessed_bone_offering_flat"

# Per-skill suffixes appended to "<skill_id>_"
const SUFFIX_SKILL_XP_PERCENT := "skill_xp_percent"
const SUFFIX_MASTERY_XP_PERCENT := "mastery_xp_percent"
const SUFFIX_INTERVAL_PERCENT := "interval_percent"        # reduction
const SUFFIX_INTERVAL_FLAT := "interval_flat"              # flat seconds removed
const SUFFIX_DOUBLING_PERCENT := "doubling_percent"
const SUFFIX_PRESERVATION_PERCENT := "preservation_percent"
const SUFFIX_RESOURCE_FLAT := "resource_flat"              # +n base quantity
const SUFFIX_NODE_PRESERVATION_PERCENT := "node_preservation_percent"  # chance a mining node takes no damage
const SUFFIX_HIDDEN_LEVELS := "hidden_levels"              # +n effective skill levels

# ---- Combat ----
const MELEE_ACCURACY_PERCENT := "melee_accuracy_percent"
const RANGED_ACCURACY_PERCENT := "ranged_accuracy_percent"
const MAGIC_ACCURACY_PERCENT := "magic_accuracy_percent"
const GLOBAL_ACCURACY_PERCENT := "global_accuracy_percent"
const MELEE_EVASION_PERCENT := "melee_evasion_percent"
const RANGED_EVASION_PERCENT := "ranged_evasion_percent"
const MAGIC_EVASION_PERCENT := "magic_evasion_percent"
const MELEE_MAX_HIT_PERCENT := "melee_max_hit_percent"
const RANGED_MAX_HIT_PERCENT := "ranged_max_hit_percent"
const MAGIC_MAX_HIT_PERCENT := "magic_max_hit_percent"
const MELEE_MAX_HIT_FLAT := "melee_max_hit_flat"
const RANGED_MAX_HIT_FLAT := "ranged_max_hit_flat"
const MAGIC_MAX_HIT_FLAT := "magic_max_hit_flat"
const MIN_HIT_PERCENT_OF_MAX := "min_hit_percent_of_max"
const MIN_HIT_FLAT := "min_hit_flat"
const DAMAGE_REDUCTION_PERCENT := "damage_reduction_percent"
const ATTACK_INTERVAL_PERCENT := "attack_interval_percent"
const ATTACK_INTERVAL_FLAT := "attack_interval_flat"
const RESPWAN_TIME_PERCENT := "respawn_time_percent"
const CRIT_CHANCE_PERCENT := "crit_chance_percent"
const CRIT_MULTIPLIER_PERCENT := "crit_multiplier_percent"
const LIFE_STEAL_PERCENT := "life_steal_percent"
const SLAYER_AREA_NEGATION_PERCENT := "slayer_area_negation_percent"
const PRAYER_COST_REDUCTION_PERCENT := "prayer_cost_reduction_percent"
const AMMO_PRESERVATION_PERCENT := "ammo_preservation_percent"
const RUNE_PRESERVATION_PERCENT := "rune_preservation_percent"
const FOOD_HEALING_PERCENT := "food_healing_percent"
const HITPOINTS_REGEN_FLAT := "hitpoints_regen_flat"

# ---- Raid ----
## Raid-only keys. These are NOT passive stats: RaidManager reads them directly to shape the
## run (a run starts this many waves in). Registering them here means one authority on the
## spelling, and a shop upgrade whose key nothing reads is a bug the test suite can catch.
const RAID_WAVE_SKIP := "raid_wave_skip"

# ---- Keys the five new systems and Thieving read directly ----
## None of these is a SUFFIX key (they are read by name rather than composed from a skill id), so
## without an entry here this file's promise — "no module typos a key" — did not hold for them, and
## a typo in a modifier table would fail silently instead of being caught by the registry check.
const THIEVING_STEALTH := "thieving_stealth"
const RANCHING_FEED_REDUCTION_PERCENT := "ranching_feed_reduction_percent"
const RANCHING_VARIANT_PERCENT := "ranching_variant_percent"
const INSCRIPTION_QUALITY_PERCENT := "inscription_quality_percent"
const INSCRIPTION_RESEARCH_XP_PERCENT := "inscription_research_xp_percent"
const ENGINEERING_FUEL_REDUCTION_PERCENT := "engineering_fuel_reduction_percent"
const ENGINEERING_DEVICE_SLOTS := "engineering_device_slots"
const ENGINEERING_EFFICIENCY_PERCENT := "engineering_efficiency_percent"
const ENCHANTING_ESSENCE_PERCENT := "enchanting_essence_percent"
const ENCHANTING_RUNE_REDUCTION_PERCENT := "enchanting_rune_reduction_percent"
const ENCHANTING_POTENCY_PERCENT := "enchanting_potency_percent"
const DREAMWALKING_ESSENCE_PERCENT := "dreamwalking_essence_percent"
const DREAMWALKING_NIGHTMARE_IMMUNITY := "dreamwalking_nightmare_immunity"
const DREAMWALKING_EVENT_GUARANTEE := "dreamwalking_event_guarantee"

## Build a per-skill key, e.g. skill_key("woodcutting", ModifierKeys.SUFFIX_INTERVAL_PERCENT).
static func skill_key(skill_id: String, suffix: String) -> String:
    return "%s_%s" % [skill_id, suffix]
