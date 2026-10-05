extends Node
## PlayerData — the single source of truth for all persistent player state.
## Everything is data-driven: skills come from DataLoader, not hardcoded lists.

# skill_id -> { "xp": float, "level": int }
var skills: Dictionary = {}
var gp: float = 0.0
var slayer_coins: float = 0.0
var prayer_points: float = 0.0
var abyssal_coins: float = 0.0
var raid_coins: float = 0.0

var game_mode: String = "standard"
var username: String = "Adventurer"

# Equipment: slot_index -> item_id ("" when empty)
var equipment: Dictionary = {}
var equipment_sets: Array = []          # Array[Dictionary] of slot->item_id
var active_set: int = 0

var active_prayers: Array[String] = []
var active_potion: String = ""          # item_id of the equipped potion
var potion_charges: int = 0

var shop_upgrades: Dictionary = {}      # upgrade_id -> count
var unlocked_pets: Array[String] = []
var completion_log: Dictionary = {
    "items": {}, "monsters": {}, "dungeons": {}, "pets": {},
}
var slayer_task: Dictionary = {}
var settings: Dictionary = SettingsDefaults.DEFAULTS.duplicate(true)
var playtime_seconds: float = 0.0

## Wall-clock time up to which offline progress has already been simulated. Offline gains are
## measured from this marker, so they are applied exactly once per save transition regardless
## of how the process exits. Persisted (see serialize()).
var last_offline_unix: int = 0

## Lifetime counters. These are the ONLY place quests/achievements read "have I ever done X",
## which keeps objective evaluation a pure function of persisted state.
var stats: Dictionary = {}

## Ascendancy state: {ascensions, total, history, lifetime_stats}. Kept on PlayerData (not in a
## manager) because it is character state that must survive a save round-trip, and every other
## persisted field already lives here.
var prestige: Dictionary = {"ascensions": 0, "total": 0, "history": {}, "lifetime_stats": {}}

## Onboarding: the index of the first tutorial step that is not yet satisfied. It is an INDEX
## rather than a set of per-step flags on purpose — a step retires when its condition is true
## against live state, so the only thing worth persisting is "how far along the list this player
## is". A save that never saw the tutorial lands on 0 and simply re-derives from the start.
var tutorial_step: int = 0
var unlock_history: Array = []

## Equipped-item protection: item ids the player marked "do not sell / do not drop".
var protected_items: Dictionary = {}

## Favourites: item ids the player pinned for quick access in the bank. Deliberately NOT the same
## thing as protection — a favourite is an organisation aid, so favouriting an item never stops it
## being sold. Protection is the safety rail; this is the bookmark.
var favorite_items: Dictionary = {}

const COMBAT_SKILLS: Array[String] = ["attack", "strength", "defence", "hitpoints",
    "ranged", "magic", "prayer", "slayer", "corruption"]

func _ready() -> void:
    if skills.is_empty():
        initialize_new_game()

## Fresh lifetime-counter record. Keys are stable so saves stay comparable.
static func default_stats() -> Dictionary:
    return {
        "items_gained": {},          # item_id -> lifetime quantity obtained
        "items_crafted": {},         # item_id -> lifetime quantity produced by artisan actions
        "items_sold": {},            # item_id -> lifetime quantity sold
        "monsters_killed": {},       # monster_id -> lifetime kills
        "raid_waves_cleared": {},
        "raid_choices_taken": 0,
        "raid_coins_banked": 0.0,
        "dungeons_cleared": {},      # dungeon_id -> lifetime clears
        "actions": {},               # "skill:action" -> lifetime completions
        "region_visits": {},         # area/dungeon id -> visited flag
        "gp_earned": 0.0,
        "gp_spent": 0.0,
        "quests_completed": 0,
        "deaths": 0,
        "offline_seconds_processed": 0.0,
    }

func reset_stats() -> void:
    stats = default_stats()

## Increment a nested counter, e.g. bump_stat("items_gained", "normal_log", 3).
func bump_stat(bucket: String, key: String, amount: float = 1.0) -> void:
    if not stats.has(bucket) or typeof(stats[bucket]) != TYPE_DICTIONARY:
        stats[bucket] = {}
    var table: Dictionary = stats[bucket]
    table[key] = float(table.get(key, 0.0)) + amount

func bump_total(bucket: String, amount: float = 1.0) -> void:
    stats[bucket] = float(stats.get(bucket, 0.0)) + amount

func get_stat(bucket: String, key: String = "", default: float = 0.0) -> float:
    if not stats.has(bucket):
        return default
    if key == "":
        var v: Variant = stats[bucket]
        return float(v) if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT else default
    var table: Variant = stats[bucket]
    if typeof(table) != TYPE_DICTIONARY:
        return default
    return float((table as Dictionary).get(key, default))

## Wipe every piece of PROGRESS to its starting value. Preferences (settings) are deliberately
## preserved, because they describe how the player wants the game to behave, not what they
## have achieved. Used by both a brand-new game and a confirmed reset, so a reset can never
## leave gold, shop upgrades or collection flags behind.
func initialize_new_game() -> void:
    skills.clear()
    unlock_history.clear()
    for skill_id in DataLoader.get_skill_ids():
        var start_level: int = 1
        skills[skill_id] = {"xp": float(XPTable.xp_for_level(start_level)), "level": start_level}
    gp = 0.0
    slayer_coins = 0.0
    prayer_points = 0.0
    abyssal_coins = 0.0
    raid_coins = 0.0
    equipment.clear()
    equipment_sets.clear()
    active_set = 0
    active_prayers.clear()
    active_potion = ""
    potion_charges = 0
    shop_upgrades.clear()
    unlocked_pets.clear()
    completion_log = {"items": {}, "monsters": {}, "dungeons": {}, "pets": {}}
    slayer_task.clear()
    playtime_seconds = 0.0
    reset_stats()
    # Onboarding restarts with the run. A character that has just been reset is, by definition,
    # back at level 1 with empty stores, and the steps re-derive from live state — so a veteran
    # ascending sails through the ones they have already done instead of being re-taught them.
    tutorial_step = 0
    last_offline_unix = int(Time.get_unix_time_from_system())
    protected_items.clear()
    favorite_items.clear()

# ---------------- Skill state ----------------
func get_level(skill_id: String) -> int:
    var s: Dictionary = skills.get(skill_id, {})
    return int(s.get("level", 1))

func get_xp(skill_id: String) -> float:
    var s: Dictionary = skills.get(skill_id, {})
    return float(s.get("xp", 0.0))

func get_level_cap(skill_id: String) -> int:
    ## Game-mode skill caps, read from data/game_modes.json rather than hardcoded, so tuning a
    ## mode is a data edit. Two rules the game actually honours: a flat `skill_level_cap` (Ancient
    ## Relics), and `non_combat_level_capped_by_combat_level` (Adventure).
    var mode: Dictionary = DataLoader.game_modes.get(game_mode, {})
    var flat_cap: int = int(mode.get("skill_level_cap", XPTable.MAX_LEVEL))
    if bool(mode.get("non_combat_level_capped_by_combat_level", false)) and not COMBAT_SKILLS.has(skill_id):
        return maxi(mini(get_combat_level(), XPTable.MAX_LEVEL), 1)
    return flat_cap

## Add raw XP (caller already applied XP multipliers). Handles level-ups, including
## multiple levels from a single grant, and never banks XP past the level cap.
func add_xp(skill_id: String, amount: float) -> void:
    if amount <= 0.0 or not skills.has(skill_id):
        return
    var cap: int = get_level_cap(skill_id)
    var s: Dictionary = skills[skill_id]
    var old_level: int = int(s["level"])
    if old_level >= cap:
        return
    var cap_xp: float = float(XPTable.xp_for_level(cap))
    var old_xp: float = float(s["xp"])
    var new_xp: float = minf(old_xp + amount, cap_xp)
    s["xp"] = new_xp
    var new_level: int = mini(XPTable.level_for_xp(new_xp), cap)
    s["level"] = new_level
    if new_xp > old_xp:
        EventBus.skill_xp_gained.emit(skill_id, new_xp - old_xp, new_xp)
    if new_level > old_level:
        var unlocks: Array[String] = []
        for action in DataLoader.get_skill_actions(skill_id):
            if int(action.get("level_required", 1)) > old_level and int(action.get("level_required", 1)) <= new_level: unlocks.append(str(action.get("name", action.id)))
        record_unlock("skill", skill_id, "%s reached level %d%s" % [str(DataLoader.get_skill(skill_id).get("name", skill_id)), new_level, " · " + ", ".join(unlocks) if not unlocks.is_empty() else ""])
        EventBus.skill_level_up.emit(skill_id, new_level)

func set_level(skill_id: String, level: int) -> void:
    if not skills.has(skill_id):
        skills[skill_id] = {}
    skills[skill_id]["level"] = level
    skills[skill_id]["xp"] = float(XPTable.xp_for_level(level))

# ---------------- Combat level (spec 3.2) ----------------
func get_combat_level() -> int:
    var defence: int = get_level("defence")
    var hp: int = get_level("hitpoints")
    var prayer: int = get_level("prayer")
    var base: float = 0.25 * float(defence + hp + int(floor(0.5 * float(prayer))))
    var melee_off: int = get_level("attack") + get_level("strength")
    var ranged_off: int = int(floor(1.5 * float(get_level("ranged"))))
    var magic_off: int = int(floor(1.5 * float(get_level("magic"))))
    var best: int = maxi(melee_off, maxi(ranged_off, magic_off))
    return int(floor(base + 0.325 * float(best)))

# ---------------- Currencies ----------------
func add_gp(amount: float) -> void:
    if not is_finite(amount):
        push_warning("PlayerData.add_gp called with a non-finite amount")
        return
    if amount < 0.0:
        # Never allow a negative-balance grant; callers must use spend_gp().
        push_warning("PlayerData.add_gp called with a negative amount (%f)" % amount)
        return
    gp += amount
    if amount > 0.0:
        bump_total("gp_earned", amount)
    EventBus.gp_changed.emit(amount, gp)

func spend_gp(amount: float) -> bool:
    if amount < 0.0:
        return false
    if gp < amount:
        return false
    gp -= amount
    bump_total("gp_spent", amount)
    EventBus.gp_changed.emit(-amount, gp)
    return true

func add_slayer_coins(amount: float) -> void:
    slayer_coins += amount
    EventBus.slayer_coins_changed.emit(amount, slayer_coins)

func add_abyssal_coins(amount: float) -> void:
    abyssal_coins += amount
    EventBus.abyssal_coins_changed.emit(amount, abyssal_coins)

func spend_abyssal_coins(amount: float) -> bool:
    if amount < 0.0 or abyssal_coins < amount:
        return false
    abyssal_coins -= amount
    EventBus.abyssal_coins_changed.emit(-amount, abyssal_coins)
    return true

func add_prayer_points(amount: float) -> void:
    prayer_points += amount
    EventBus.prayer_points_changed.emit(prayer_points)

# ---------------- Progression flags ----------------
func discover_item(item_id: String) -> void:
    if not completion_log["items"].has(item_id):
        completion_log["items"][item_id] = true
        record_unlock("items", item_id, "Discovered " + item_id.replace("_", " ").capitalize())
        EventBus.item_discovered.emit(item_id)
        _recalc_completion()

func discover_monster(monster_id: String) -> void:
    if not completion_log["monsters"].has(monster_id):
        completion_log["monsters"][monster_id] = true
        record_unlock("monsters", monster_id, "Discovered " + monster_id.replace("_", " ").capitalize())
        EventBus.monster_discovered.emit(monster_id)
        _recalc_completion()

func discover_dungeon(dungeon_id: String) -> void:
    if not completion_log["dungeons"].has(dungeon_id):
        completion_log["dungeons"][dungeon_id] = true
        record_unlock("dungeons", dungeon_id, "Discovered " + dungeon_id.replace("_", " ").capitalize())
        EventBus.dungeon_discovered.emit(dungeon_id)
        _recalc_completion()

func unlock_pet(pet_id: String) -> void:
    if not unlocked_pets.has(pet_id):
        unlocked_pets.append(pet_id)
        completion_log["pets"][pet_id] = true
        record_unlock("pets", pet_id, "Discovered " + pet_id.replace("_", " ").capitalize())
        EventBus.pet_unlocked.emit(pet_id)
        _recalc_completion()

func _recalc_completion() -> void:
    var got: int = completion_log["items"].size() + completion_log["monsters"].size() \
        + completion_log["dungeons"].size() + completion_log["pets"].size()
    var total: int = DataLoader.items.size() + DataLoader.monsters.size() \
        + DataLoader.dungeons.size() + DataLoader.pets.size()
    var pct: float = 0.0 if total == 0 else float(got) / float(total) * 100.0
    EventBus.completion_updated.emit(pct)

# ---------------- Persistence ----------------
func serialize() -> Dictionary:
    return {
        "username": username, "game_mode": game_mode, "skills": skills,
        "gp": gp, "slayer_coins": slayer_coins, "prayer_points": prayer_points,
        "abyssal_coins": abyssal_coins, "raid_coins": raid_coins,
        "equipment": equipment, "equipment_sets": equipment_sets, "active_set": active_set,
        "active_prayers": active_prayers, "active_potion": active_potion,
        "potion_charges": potion_charges, "shop_upgrades": shop_upgrades,
        "unlocked_pets": unlocked_pets, "completion_log": completion_log,
        "slayer_task": slayer_task, "settings": settings, "playtime_seconds": playtime_seconds,
        "last_offline_unix": last_offline_unix, "stats": stats,
        "protected_items": protected_items,
        "favorite_items": favorite_items,
        "prestige": prestige,
        "tutorial_step": tutorial_step,
        "unlock_history": unlock_history.duplicate(true),
    }

func deserialize(d: Dictionary) -> void:
    unlock_history = []
    var journal: Variant = d.get("unlock_history", [])
    if journal is Array:
        for entry in journal.slice(-300):
            if entry is Dictionary and entry.get("text", "") is String:
                var stamp: Variant = entry.get("unix", 0)
                if not (stamp is int or stamp is float) or not is_finite(float(stamp)): continue
                unlock_history.append({"kind": str(entry.get("kind", "")), "id": str(entry.get("id", "")), "text": str(entry.text), "unix": maxi(0, int(stamp))})
    username = d.get("username", "Adventurer")
    game_mode = d.get("game_mode", "standard")
    skills = d.get("skills", {})
    gp = maxf(0.0, float(d.get("gp", 0.0)))
    slayer_coins = maxf(0.0, float(d.get("slayer_coins", 0.0)))
    prayer_points = maxf(0.0, float(d.get("prayer_points", 0.0)))
    abyssal_coins = maxf(0.0, float(d.get("abyssal_coins", 0.0)))
    raid_coins = maxf(0.0, float(d.get("raid_coins", 0.0)))
    equipment = d.get("equipment", {})
    equipment_sets = d.get("equipment_sets", [])
    active_set = int(d.get("active_set", 0))
    active_prayers = _to_string_array(d.get("active_prayers", []))
    active_potion = d.get("active_potion", "")
    potion_charges = maxi(0, int(d.get("potion_charges", 0)))
    shop_upgrades = d.get("shop_upgrades", {})
    unlocked_pets = _to_string_array(d.get("unlocked_pets", []))
    completion_log = _merge_completion_log(d.get("completion_log", {}))
    slayer_task = d.get("slayer_task", {})
    settings = SettingsDefaults.with_defaults(d.get("settings", {}))
    playtime_seconds = maxf(0.0, float(d.get("playtime_seconds", 0.0)))
    last_offline_unix = int(d.get("last_offline_unix", 0))
    stats = _merge_stats(d.get("stats", {}))
    protected_items = d.get("protected_items", {})
    favorite_items = _sanitize_item_flags(d.get("favorite_items", {}))
    prestige = _sanitize_prestige(d.get("prestige", {}))
    tutorial_step = sanitize_tutorial_step(d.get("tutorial_step", 0))
    _sanitize_skills()

## An older save has no tutorial_step key, and a hand-edited one can hold a string or a negative.
## Normalise to a non-negative index; the upper bound belongs to TutorialManager, which owns the
## step list and already clamps against it (an index past the end would hide the guide for good).
static func sanitize_tutorial_step(source: Variant) -> int:
    if typeof(source) != TYPE_INT and typeof(source) != TYPE_FLOAT:
        return 0
    return maxi(0, int(source))

## An older save has no prestige key, and a hand-edited one can hold nonsense. Normalise to
## the full shape so no caller has to guard against a missing field.
func _sanitize_prestige(source: Variant) -> Dictionary:
    var out: Dictionary = {"ascensions": 0, "total": 0, "history": {}, "lifetime_stats": {}}
    if typeof(source) != TYPE_DICTIONARY:
        return out
    var d: Dictionary = source
    out["ascensions"] = maxi(0, int(d.get("ascensions", 0)))
    out["total"] = maxi(0, int(d.get("total", 0)))
    var history: Variant = d.get("history", {})
    if typeof(history) == TYPE_DICTIONARY:
        out["history"] = _merge_completion_log(history)
    var lifetime: Variant = d.get("lifetime_stats", {})
    if typeof(lifetime) == TYPE_DICTIONARY:
        out["lifetime_stats"] = _merge_stats(lifetime)
    return out

## Keep only ids that still exist in the item table. A save can be hand-edited or written by an
## older build, and a stale flag would otherwise resurrect a row with no data behind it.
func _sanitize_item_flags(source: Variant) -> Dictionary:
    var out: Dictionary = {}
    if typeof(source) != TYPE_DICTIONARY:
        return out
    for item_id in (source as Dictionary).keys():
        if DataLoader.items.has(str(item_id)):
            out[str(item_id)] = true
    return out

## A save written by an older build may lack counters added since; start them at zero.
func _merge_stats(source: Variant) -> Dictionary:
    var out: Dictionary = default_stats()
    if typeof(source) != TYPE_DICTIONARY:
        return out
    for key in (source as Dictionary).keys():
        var v: Variant = source[key]
        if typeof(out.get(key)) == TYPE_DICTIONARY and typeof(v) == TYPE_DICTIONARY:
            out[key] = v
        elif typeof(out.get(key)) != TYPE_DICTIONARY:
            out[key] = v
    return out

func _merge_completion_log(source: Variant) -> Dictionary:
    var out: Dictionary = {"items": {}, "monsters": {}, "dungeons": {}, "pets": {}}
    if typeof(source) != TYPE_DICTIONARY:
        return out
    for key in out.keys():
        var v: Variant = (source as Dictionary).get(key, {})
        out[key] = v if typeof(v) == TYPE_DICTIONARY else {}
    return out

## Guarantee every data-defined skill exists and every value is a valid number, so a
## hand-edited or partially-written save can never produce a negative or NaN skill state.
func _sanitize_skills() -> void:
    for skill_id in DataLoader.get_skill_ids():
        var entry: Variant = skills.get(skill_id)
        if typeof(entry) != TYPE_DICTIONARY:
            var start_level: int = 1
            skills[skill_id] = {"xp": float(XPTable.xp_for_level(start_level)), "level": start_level}
            continue
        var e: Dictionary = entry
        var xp: float = float(e.get("xp", 0.0))
        if not is_finite(xp) or xp < 0.0:
            xp = 0.0
        var level: int = clampi(int(e.get("level", 1)), 1, XPTable.MAX_LEVEL)
        if XPTable.level_for_xp(xp) > level:
            level = XPTable.level_for_xp(xp)
        e["xp"] = xp
        e["level"] = level
        skills[skill_id] = e

## JSON gives untyped arrays; convert to the typed form this class declares.
func _to_string_array(value: Variant) -> Array[String]:
    var out: Array[String] = []
    if typeof(value) == TYPE_ARRAY:
        for v in value:
            out.append(str(v))
    return out

func record_unlock(kind: String, id: String, text: String) -> void:
    unlock_history.append({"kind": kind, "id": id, "text": text, "unix": int(Time.get_unix_time_from_system())})
    if unlock_history.size() > 300: unlock_history.pop_front()
