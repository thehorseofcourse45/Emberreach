class_name SettingsDefaults
extends RefCounted
## Central registry of player settings and their defaults.
## Anything the gameplay code reads via PlayerData.settings.get(...) MUST be listed here so
## that migrating or importing an old save can guarantee the key exists.

const DEFAULTS: Dictionary = {
	## Idle conveniences (earned, not default-on).
	"auto_repeat": true,               ## repeat the current skill action until stopped
	"auto_eat_tier": 0,                ## 0 = off; 1..3 = Auto Eat tiers bought in the shop
	"auto_reuse_potion": true,
	"auto_equip_upgrades": false,
	## Offline behaviour.
	"offline_combat_enabled": true,     ## may combat continue while away?
	"offline_combat_stops_on_defeat": true,  ## conservative default: a defeat ends offline combat
	"offline_thieving_enabled": false,
	"offline_cap_hours": 24.0,          ## configurable offline cap
	"offline_auto_repeat": true,
	## Presentation.
	"reduced_motion": false,
	"ui_scale": 1.0,
	"compact_rows": false,
	"confirm_sell_all": true,
	"confirm_reset": true,
	"tooltip_delay": 0.25,
	## Which mode the NEXT new journey uses (does not affect the current character).
	"new_game_mode": "",
	## Diagnostics.
	"show_estimates_detail": true,
}

## Keys that a brand new game should NOT inherit from a save (reserved for future use).
const SESSION_ONLY: Array[String] = []

static func with_defaults(source: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	for key in source.keys():
		out[key] = source[key]
	return out

static func get_default(key: String, fallback: Variant = null) -> Variant:
	return DEFAULTS.get(key, fallback)
