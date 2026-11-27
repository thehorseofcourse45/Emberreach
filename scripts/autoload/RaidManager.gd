extends Node
## Shattered Trail journeys and the legacy gauntlet save format share the existing shop.

const WAVE_ENEMY: String = "golbin"
const CATEGORY: String = "raid"
const RUN_CATEGORY: String = "raid_run"
const RELICS: Dictionary = {
    "iron_shell": {"name": "Iron Shell", "description": "+4% damage reduction per stack", "effect": {"damage_reduction_percent": 4.0}},
    "keen_eye": {"name": "Keen Eye", "description": "+8% accuracy per stack", "effect": {"global_accuracy_percent": 8.0}},
    "quick_hands": {"name": "Quick Hands", "description": "4% faster attacks per stack", "effect": {"attack_interval_percent": -4.0}},
    "field_rations": {"name": "Field Rations", "description": "+12% food healing per stack", "effect": {"food_healing_percent": 12.0}},
    "heavy_blows": {"name": "Heavy Blows", "description": "+8% melee max hit per stack", "effect": {"melee_max_hit_percent": 8.0}},
    "lucky_charm": {"name": "Lucky Charm", "description": "+5% double loot chance per stack", "effect": {"global_double_loot_percent": 5.0}},
}
const SUPPLIES: Dictionary = {
    "heal": {"name": "Campfire", "description": "Restore 35% of your maximum combat HP"},
    "coins": {"name": "Stolen Purse", "description": "Add 25% of this wave's coin reward to your bankable gauntlet purse"},
}
const ROUTES: Dictionary = {
    "skirmish": {"name": "Patrol", "description": "Standard enemy patrol; safest option", "risk": "Low", "reward": "1.0x coins", "hp_mult": 1.0, "coin_mult": 1.0, "extra": 0},
    "horde": {"name": "Swarm", "description": "Extra enemies, with a larger coin purse", "risk": "Medium", "reward": "1.4x coins", "hp_mult": 1.0, "coin_mult": 1.4, "extra": 2},
    "elite": {"name": "Elite Hunt", "description": "Tougher opponents with a high payout", "risk": "High", "reward": "1.7x coins", "hp_mult": 1.45, "coin_mult": 1.7, "extra": 0},
    "trail_patrol": {"name":"Patrol", "description":"Fight a patrol; no supplies required.", "risk":"Low", "reward":"Standard marks", "hp_mult":1.0, "coin_mult":1.0, "extra":0},
    "trail_cache": {"name":"Guarded Cache", "description":"Spend one supply to face a stronger patrol for extra marks.", "risk":"High", "reward":"2x marks", "hp_mult":1.35, "coin_mult":2.0, "extra":1},
    "trail_camp": {"name":"Sheltered Camp", "description":"Skip a fight, heal 35% HP and gain one supply. Two camps per journey.", "risk":"None", "reward":"Healing and supplies", "hp_mult":1.0, "coin_mult":0.0, "extra":0},
    "trail_boss": {"name":"Final guardian", "description":"Defeat the guardian to complete the journey and bank your marks.", "risk":"Boss", "reward":"Completion reward", "hp_mult":1.0, "coin_mult":2.0, "extra":0},
}
const TRAIL_STOPS := 5
const TRAIL_BOSSES := {"easy":"strawbound_warden", "normal":"golbin_chief", "hard":"rookwatch_captain", "mythic":"archive_boss"}
const TRAIL_REWARDS := {"easy":["shrimp", 10], "normal":["shark", 20], "hard":["potion_dr_3", 2], "mythic":["masterwork_seal", 1]}
const TRAIL_LANDMARKS := ["Ashen Road", "Broken Bridge", "Forgotten Camp", "Hollow Pass", "Ruined Watchtower"]

const ASTRAL_TRIALS := [
    {"id":"astral_vestibule", "name":"Astral Vestibule", "enemy":"astral_gatekeeper", "wave_enemies":["vestibule_starward", "vestibule_orbiter"], "marks":16000},
    {"id":"comet_forge", "name":"Comet Forge", "enemy":"comet_forgemaster", "wave_enemies":["comet_cinderling", "comet_anvilguard"], "marks":24000},
    {"id":"eclipse_oratory", "name":"Eclipse Oratory", "enemy":"eclipse_cantor", "wave_enemies":["eclipse_umbrawisp", "eclipse_hymnist"], "marks":32000},
    {"id":"constellation_throne", "name":"Constellation Throne", "enemy":"constellation_regent", "wave_enemies":["constellation_hound", "constellation_lancer"], "marks":40000},
    {"id":"horizon_nexus", "name":"Horizon Nexus", "enemy":"nexus_ascendant", "wave_enemies":["nexus_prismwing", "nexus_seraph"], "marks":50000},
    {"id":"celestial_observatory", "name":"Celestial Observatory", "enemy":"observatory_sentinel", "wave_enemies":["observatory_watcher", "observatory_starseer"], "marks":60000},
    {"id":"nebula_garden", "name":"Nebula Garden", "enemy":"nebula_matriarch", "wave_enemies":["nebula_bloom", "nebula_thornkeeper"], "marks":70000},
    {"id":"aurora_bastion", "name":"Aurora Bastion", "enemy":"aurora_paragon", "wave_enemies":["aurora_sentinel", "aurora_lancer"], "marks":80000},
    {"id":"voidstar_vault", "name":"Voidstar Vault", "enemy":"voidstar_archon", "wave_enemies":["voidstar_shade", "voidstar_herald"], "marks":90000},
    {"id":"eternity_crown", "name":"Eternity Crown", "enemy":"eternity_sovereign", "wave_enemies":["eternity_seraph", "eternity_justiciar"], "marks":110000},
]
var astral_encounter: String = ""
var astral_completions: Dictionary = {}

func astral_sequence(index: int) -> Array:
    if index < 0 or index >= ASTRAL_TRIALS.size(): return []
    var trial: Dictionary = ASTRAL_TRIALS[index]
    var sequence: Array = []
    for wave in range(8):
        for _enemy in range(3): sequence.append(str(trial.wave_enemies[wave % 2]))
    sequence.append(str(trial.enemy))
    return sequence

func astral_lock_reason(index: int) -> String:
    if index < 0 or index >= ASTRAL_TRIALS.size(): return "Unknown trial"
    if not PlayerData.completion_log.get("dungeons", {}).has("final_horizon"):
        return "Complete The Final Horizon expedition"
    if index > 0 and not astral_completions.has(str(ASTRAL_TRIALS[index - 1].id)):
        return "Complete %s" % str(ASTRAL_TRIALS[index - 1].name)
    return ""

func start_astral(index: int) -> bool:
    if active or CombatManager.state != CombatManager.State.IDLE or astral_lock_reason(index) != "": return false
    var trial: Dictionary = ASTRAL_TRIALS[index]
    if SkillManager.running: SkillManager.stop_action(SkillManager.StopReason.PLAYER, "Astral trial began")
    active = true
    trail_mode = false
    astral_encounter = str(trial.id)
    coins_this_raid = 0.0
    wave = index + 1
    difficulty = "normal"
    current_encounter = {"id": astral_encounter, "name": trial.name, "hp_mult": 1.0}
    run_stage = "combat"
    if not CombatManager.start_combat({"type":"raid", "id":astral_encounter, "monsters":astral_sequence(index), "endless":false, "raid":true}):
        active = false
        astral_encounter = ""
        current_encounter.clear()
        return false
    _save_trail_progress()
    return true

var active: bool = false
var wave: int = 0
var difficulty: String = "normal"
var coins_this_raid: float = 0.0
var pending_choices: Array = []
var purchased: Dictionary = {}     # upgrade_id -> count
var run_stage: String = "combat"   # combat -> reward -> route -> combat
var pending_routes: Array = []
var run_relics: Dictionary = {}
var current_encounter: Dictionary = {}
var best_wave: Dictionary = {}      # difficulty -> highest wave cleared
var run_history: Array = []         # last 12 wave summaries
var _next_route: String = "skirmish"
var _last_wave_coins: float = 0.0
var trail_mode: bool = false
var trail_supplies: int = 0
var trail_camps: int = 0
var trail_completions: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
    _rng.randomize()
    EventBus.game_loaded.connect(_reapply)

func difficulty_cfg() -> Dictionary:
    return DataLoader.raid_shop.get("difficulties", {}).get(difficulty, {})

func start_raid(diff: String = "normal") -> bool:
    if active or not DataLoader.raid_shop.get("difficulties", {}).has(diff) or CombatManager.state != CombatManager.State.IDLE:
        return false
    if locked_reason(diff) != "":
        EventBus.notification.emit("Trail locked: %s" % locked_reason(diff), "warn")
        return false
    difficulty = diff
    active = true
    coins_this_raid = 0.0
    pending_choices = []
    pending_routes = []
    run_relics.clear()
    ModifierManager.clear_category(RUN_CATEGORY)
    run_history.clear()
    current_encounter.clear()
    _next_route = "skirmish"
    run_stage = "combat"
    _last_wave_coins = 0.0
    trail_mode = true
    trail_supplies = 2 + maxi(0, int(ModifierManager.get_modifier(ModifierKeys.RAID_WAVE_SKIP)))
    trail_camps = 0
    wave = 0
    _offer_trail_routes()
    EventBus.state_refreshed.emit()
    _save_trail_progress()
    return true

## Why a difficulty cannot be started yet ("" when it can): its `requires` skill levels.
func locked_reason(diff: String) -> String:
    var reqs: Dictionary = DataLoader.raid_shop.get("difficulties", {}).get(diff, {}).get("requires", {})
    for skill_id in reqs:
        if PlayerData.get_level(str(skill_id)) < int(reqs[skill_id]):
            return "Reach %s %d" % [str(DataLoader.get_skill(str(skill_id)).get("name", skill_id)), int(reqs[skill_id])]
    return ""

func _offer_trail_routes() -> void:
    pending_routes.clear()
    var ids: Array = ["trail_boss"] if wave >= TRAIL_STOPS else ["trail_patrol", "trail_cache", "trail_camp"]
    for id in ids:
        var route: Dictionary = ROUTES[id].duplicate(true)
        route["id"] = id
        pending_routes.append(route)
    run_stage = "route"

func _save_trail_progress() -> void:
    if not OfflineProgression.is_running and not SimulationMode.is_silent():
        SaveManager._save_on_event()

func _start_trail_combat(route_id: String) -> bool:
    if not active or not ROUTES.has(route_id) or CombatManager.state != CombatManager.State.IDLE:
        return false
    var previous_wave := wave
    wave += 1
    var cfg: Dictionary = difficulty_cfg()
    var enemies: Array = []
    current_encounter = ROUTES[route_id].duplicate(true)
    current_encounter["id"] = route_id
    if route_id == "trail_boss":
        var boss: String = str(TRAIL_BOSSES.get(difficulty, "golbin_chief"))
        enemies.append(boss)
        current_encounter["name"] = "Guardian: %s" % str(DataLoader.get_monster(boss).get("name", boss))
    else:
        var variants: Array = cfg.get("enemy_pool", [])
        if variants.is_empty():
            variants = [str(cfg.get("enemy", WAVE_ENEMY)), "astral_sanctum_guardian_ranged", "storm_citadel_guardian_melee", "archive_guardian_melee"] if difficulty == "mythic" else [str(cfg.get("enemy", WAVE_ENEMY)), "golbin", "skeleton", "bandit"]
        for i in range(2 + int(route_id == "trail_cache")):
            var enemy: String = str(variants[(wave + i - 1) % variants.size()])
            if DataLoader.get_monster(enemy).is_empty(): enemy = WAVE_ENEMY
            enemies.append(enemy)
    run_stage = "combat"
    pending_routes.clear()
    if CombatManager.start_combat({"type":"raid", "id":"shattered_trail", "monsters":enemies, "endless":false, "raid":true}):
        return true
    wave = previous_wave
    current_encounter.clear()
    _offer_trail_routes()
    return false

func _complete_trail_encounter() -> void:
    var earned: float = 80.0 * float(maxi(1, wave)) * float(difficulty_cfg().get("coin_mult", 1.0)) * float(current_encounter.get("coin_mult", 1.0))
    coins_this_raid += earned
    run_history.append({"wave":wave, "encounter":str(current_encounter.get("name", "Patrol")), "coins":roundi(earned)})
    if run_history.size() > 12: run_history.pop_front()
    if str(current_encounter.get("id", "")) == "trail_boss":
        trail_completions[difficulty] = int(trail_completions.get(difficulty, 0)) + 1
        var reward: Array = TRAIL_REWARDS.get(difficulty, TRAIL_REWARDS.normal)
        # Commit the completed run before reward signals can trigger a save.
        end_raid(false)
        BankManager.add_item_guaranteed(str(reward[0]), int(reward[1]))
        if not SimulationMode.is_silent(): EventBus.notify("Trail complete! Guardian reward and earned Trail Marks are banked.", "success")
        _save_trail_progress()
        return
    _offer_trail_routes()
    if not SimulationMode.is_silent():
        EventBus.notify("Encounter cleared: +%d Trail Marks." % int(earned), "success")
        EventBus.state_refreshed.emit()
    _save_trail_progress()

func _wave_size(w: int) -> int:
    return int(floor(2.0 + float(w) / 4.0))

## Enemy hitpoint multiplier for this difficulty. Read by CombatManager at spawn, so hard mode
## really is a tougher fight instead of only a prettier label in the panel.
func enemy_hp_mult() -> float:
    return maxf(0.1, float(difficulty_cfg().get("hp_mult", 1.0))) \
        * (1.0 + float(maxi(0, wave - 1)) * 0.025) \
        * float(current_encounter.get("hp_mult", 1.0))

func _start_wave() -> void:
    if not active:
        return
    wave += 1
    var list: Array = []
    var cfg: Dictionary = difficulty_cfg()
    var boss_every: int = int(cfg.get("boss_every", 0))
    var bosses: Array = cfg.get("bosses", [])
    var boss_wave: bool = boss_every > 0 and wave % boss_every == 0 and not bosses.is_empty()
    var route: Dictionary = ROUTES.get(_next_route, ROUTES["skirmish"])
    current_encounter = route.duplicate(true)
    current_encounter["id"] = _next_route
    current_encounter["kind"] = "boss" if boss_wave else _next_route
    if boss_wave:
        # Boss waves: a single named boss, cycling through the configured roster.
        list.append(str(bosses[(floori(float(wave) / float(boss_every)) - 1) % bosses.size()]))
        current_encounter["name"] = "Boss: %s" % str(DataLoader.get_monster(str(list[0])).get("name", str(list[0])))
        current_encounter["description"] = "A champion blocks the route. The chosen path's risk and rewards still apply."
    else:
        var default_enemy: String = str(cfg.get("enemy", WAVE_ENEMY))
        var variants: Array = cfg.get("enemy_pool", [])
        if variants.is_empty() and difficulty != "mythic":
            variants = [default_enemy, "golbin", "skeleton", "bandit", "golbin_chief"]
        for _i in range(_wave_size(wave) + int(route.get("extra", 0))):
            var enemy_id: String = default_enemy
            if not variants.is_empty() and wave >= 3:
                enemy_id = str(variants[_rng.randi_range(0, mini(variants.size() - 1, 1 + wave / 5))])
            if DataLoader.get_monster(enemy_id).is_empty():
                enemy_id = default_enemy
            list.append(enemy_id)
    run_stage = "combat"
    pending_routes.clear()
    EventBus.notification.emit("Golbin Gauntlet — wave %d" % wave, "info")
    if not CombatManager.start_combat({"type": "raid", "id": "golbin_raid", "monsters": list,
        "endless": false, "raid": true}):
        # A failed combat start must never leave a run stuck in a phantom wave.
        active = false
        ModifierManager.clear_category(RUN_CATEGORY)

func _on_combat_ended(ctx: Dictionary) -> void:
    if active and astral_encounter != "" and ctx.get("type", "") == "raid":
        if ctx.get("reason", "") == "complete" and str(ctx.get("id", "")) == astral_encounter:
            for trial in ASTRAL_TRIALS:
                if str(trial.id) == astral_encounter:
                    astral_completions[astral_encounter] = int(astral_completions.get(astral_encounter, 0)) + 1
                    coins_this_raid += float(trial.marks) * (1.0 + 0.05 * maxf(0.0, ModifierManager.get_modifier(ModifierKeys.RAID_WAVE_SKIP)))
                    break
            end_raid(false)
            if not SimulationMode.is_silent(): EventBus.notify("Astral trial complete! Trial Marks banked.", "success")
            _save_trail_progress()
        else:
            end_raid()
        return
    if active and ctx.get("type", "") == "raid" and ctx.get("reason", "") != "complete":
        end_raid()
        return
    if not active or ctx.get("type", "") != "raid" or ctx.get("reason", "") != "complete" or run_stage != "combat":
        return
    if trail_mode:
        _complete_trail_encounter()
        return
    var mult: float = float(difficulty_cfg().get("coin_mult", 1.0))
    var earned: float = mult * float(current_encounter.get("coin_mult", 1.0)) * 3.6 \
        * float(wave) * float(_wave_size(wave)) * float(int(floor(1.0 + float(wave) / 15.0)))
    coins_this_raid += earned
    _last_wave_coins = earned
    best_wave[difficulty] = maxi(int(best_wave.get(difficulty, 0)), wave)
    run_history.append({"wave": wave, "encounter": str(current_encounter.get("name", "Patrol")), "coins": roundi(earned)})
    if run_history.size() > 12:
        run_history.pop_front()
    if not PlayerData.stats.get("raid_waves_cleared", {}).has(str(wave)): PlayerData.record_unlock("raid", str(wave), "First clear: Gauntlet wave %d (+%d coins)" % [wave, int(earned)])
    PlayerData.bump_stat("raid_waves_cleared", str(wave), 1)
    var seal_every: int = int(difficulty_cfg().get("seal_every", 0))
    if seal_every > 0 and wave % seal_every == 0:
        BankManager.add_item_guaranteed("masterwork_seal", 1)
        EventBus.notification.emit("Gauntlet milestone: +1 Masterwork Seal", "success")
    pending_choices = _roll_choices()
    run_stage = "reward"
    EventBus.notification.emit("Wave %d cleared (+%d gauntlet coins) — choose an upgrade" % [wave, int(earned)], "success")
    EventBus.state_refreshed.emit()

func _roll_choices() -> Array:
    var pool: Array = []
    for relic_id in RELICS:
        if int(run_relics.get(relic_id, 0)) < 3:
            pool.append("relic:%s" % relic_id)
    for supply_id in SUPPLIES:
        pool.append("supply:%s" % supply_id)
    var picks: Array = []
    for _i in range(mini(3, pool.size())):
        picks.append(pool.pop_at(_rng.randi_range(0, pool.size() - 1)))
    return picks

func relic_catalog() -> Dictionary:
    return RELICS

func choice_info(choice: String) -> Dictionary:
    if choice.begins_with("relic:"):
        return RELICS.get(choice.trim_prefix("relic:"), {})
    if choice.begins_with("supply:"):
        return SUPPLIES.get(choice.trim_prefix("supply:"), {})
    if DataLoader.raid_shop.get("alt_items", []).has(choice) or DataLoader.raid_shop.get("legacy_alt_items", []).has(choice):
        return DataLoader.get_item(choice)
    return DataLoader.raid_shop.get("upgrades", {}).get(choice, {})

## Pick one of the three offered rewards; advances to the next wave.
func choose(index: int) -> bool:
    if not active or run_stage != "reward" or index < 0 or index >= pending_choices.size():
        return false
    var choice: String = str(pending_choices[index])
    PlayerData.bump_total("raid_choices_taken", 1)
    if choice.begins_with("relic:"):
        var relic_id: String = choice.trim_prefix("relic:")
        if not RELICS.has(relic_id) or int(run_relics.get(relic_id, 0)) >= 3:
            return false
        run_relics[relic_id] = int(run_relics.get(relic_id, 0)) + 1
        _apply_run_relic(relic_id)
    elif choice == "supply:heal":
        CombatManager.player_hp = minf(CombatManager.player_max_hp, CombatManager.player_hp + CombatManager.player_max_hp * 0.35)
    elif choice == "supply:coins":
        coins_this_raid += ceilf(_last_wave_coins * 0.25)
    elif DataLoader.raid_shop.get("alt_items", []).has(choice) or DataLoader.raid_shop.get("legacy_alt_items", []).has(choice):
        # One-time compatibility for save files made midway through the old reward screen.
        BankManager.add_item(choice, 1)
    elif DataLoader.raid_shop.get("upgrades", {}).has(choice):
        # Old saves can finish an existing reward selection; new rolls never offer shop items.
        purchased[choice] = int(purchased.get(choice, 0)) + 1
        _apply_upgrade(choice)
        EventBus.shop_upgrade_purchased.emit(choice)
    else:
        return false
    pending_choices = []
    pending_routes = []
    for route_id in ["skirmish", "horde", "elite"]:
        var route: Dictionary = ROUTES[route_id].duplicate(true)
        route["id"] = route_id
        pending_routes.append(route)
    run_stage = "route"
    EventBus.state_refreshed.emit()
    return true

## Choose how to approach the NEXT wave. The current wave's coins were already earned.
func choose_route(index: int) -> bool:
    if not active or run_stage != "route" or index < 0 or index >= pending_routes.size():
        return false
    var route_id: String = str(pending_routes[index].get("id", ""))
    if not ROUTES.has(route_id):
        return false
    if trail_mode:
        if CombatManager.state != CombatManager.State.IDLE:
            EventBus.notify("Finish the current fight before continuing the trail.", "warn")
            return false
        if route_id == "trail_cache" and trail_supplies < 1: return false
        if route_id == "trail_camp" and trail_camps >= 2: return false
        if route_id not in ["trail_patrol", "trail_cache", "trail_camp", "trail_boss"]: return false
        if (route_id == "trail_boss") != (wave >= TRAIL_STOPS): return false
        if route_id == "trail_camp":
            wave += 1
            trail_camps += 1
            trail_supplies += 1
            CombatManager.player_hp = minf(CombatManager.player_max_hp, CombatManager.player_hp + CombatManager.player_max_hp * 0.35)
            run_history.append({"wave":wave, "encounter":"Sheltered Camp", "coins":0})
            _offer_trail_routes()
            EventBus.state_refreshed.emit()
            _save_trail_progress()
            return true
        if SkillManager.running: SkillManager.stop_action(SkillManager.StopReason.PLAYER, "Trail encounter began")
        if route_id == "trail_cache": trail_supplies -= 1
        var started := _start_trail_combat(route_id)
        if not started and route_id == "trail_cache": trail_supplies += 1
        EventBus.state_refreshed.emit()
        if started: _save_trail_progress()
        return started
    _next_route = route_id
    pending_routes.clear()
    _start_wave()
    EventBus.state_refreshed.emit()
    return active

func _apply_run_relic(relic_id: String) -> void:
    if not RELICS.has(relic_id):
        return
    var count: int = clampi(int(run_relics.get(relic_id, 0)), 0, 3)
    var scaled: Dictionary = {}
    for key in (RELICS[relic_id]["effect"] as Dictionary):
        scaled[key] = float(RELICS[relic_id]["effect"][key]) * float(count)
    if count > 0:
        ModifierManager.register("raid_run:%s" % relic_id, scaled, RUN_CATEGORY, str(RELICS[relic_id]["name"]))

func _apply_upgrade(upgrade_id: String) -> void:
    var eff: Dictionary = DataLoader.raid_shop.get("upgrades", {}).get(upgrade_id, {}).get("effect", {})
    if not eff.is_empty():
        var stacked: Dictionary = {}
        for key in eff:
            stacked[key] = float(eff[key]) * float(clampi(int(purchased.get(upgrade_id, 0)), 0, 5))
        ModifierManager.register("%s:%s" % [CATEGORY, upgrade_id], stacked, CATEGORY, upgrade_id)

func end_raid(save_change: bool = true) -> void:
    if not active:
        return
    active = false
    astral_encounter = ""
    pending_choices = []
    pending_routes = []
    if str(CombatManager.context.get("type", "")) == "raid":
        CombatManager.stop_combat()
    ModifierManager.clear_category(RUN_CATEGORY)
    run_relics.clear()
    current_encounter.clear()
    _next_route = "skirmish"
    run_stage = "combat"
    PlayerData.raid_coins += coins_this_raid
    PlayerData.bump_total("raid_coins_banked", coins_this_raid)
    if not SimulationMode.is_silent(): EventBus.notification.emit("Combat ended: +%d Trial Marks" % int(coins_this_raid), "success")
    coins_this_raid = 0.0
    trail_mode = false
    trail_supplies = 0
    trail_camps = 0
    if not SimulationMode.is_silent(): EventBus.state_refreshed.emit()
    if save_change: _save_trail_progress()

# ---------------- Raid Shop ----------------
func shop_lock_reason(item_id: String) -> String:
    var required := str(DataLoader.get_item(item_id).get("unlock_trial", ""))
    if required == "" or astral_completions.has(required): return ""
    for trial in ASTRAL_TRIALS:
        if str(trial.id) == required: return "Complete %s" % str(trial.name)
    return "Trial unavailable"

func shop_items() -> Array:
    var out: Array = []
    for item_id in DataLoader.raid_shop.get("alt_items", []):
        var d: Dictionary = DataLoader.get_item(item_id)
        if not d.is_empty():
            out.append({"item_id": item_id, "name": d.get("name", item_id), "cost": int(d.get("raid_cost", 0)), "lock_reason":shop_lock_reason(str(item_id))})
    for uid in DataLoader.raid_shop.get("upgrades", {}).keys():
        var u: Dictionary = DataLoader.raid_shop["upgrades"][uid]
        out.append({"item_id": uid, "name": u.get("name", uid), "description":u.get("description", ""), "cost": int(u.get("cost", 0)),
            "level": int(purchased.get(uid, 0)), "max_level": 5})
    return out

func buy(item_id: String) -> bool:
    if active:
        return false
    var cost: float = 0.0
    if DataLoader.raid_shop.get("alt_items", []).has(item_id) or DataLoader.raid_shop.get("legacy_alt_items", []).has(item_id):
        if shop_lock_reason(item_id) != "": return false
        cost = float(DataLoader.get_item(item_id).get("raid_cost", 0))
    elif DataLoader.raid_shop.get("upgrades", {}).has(item_id):
        if int(purchased.get(item_id, 0)) >= 5:
            return false
        cost = float(DataLoader.raid_shop["upgrades"][item_id].get("cost", 0))
    else:
        return false
    if PlayerData.raid_coins < cost:
        return false
    PlayerData.raid_coins -= cost
    if DataLoader.raid_shop.get("alt_items", []).has(item_id) or DataLoader.raid_shop.get("legacy_alt_items", []).has(item_id):
        BankManager.add_item_guaranteed(item_id, 1)
    else:
        purchased[item_id] = int(purchased.get(item_id, 0)) + 1
        _apply_upgrade(item_id)
    return true

func _reapply() -> void:
    ModifierManager.clear_category(CATEGORY)
    ModifierManager.clear_category(RUN_CATEGORY)
    for upgrade_id in purchased.keys():
        _apply_upgrade(upgrade_id)
    if active:
        for relic_id in run_relics.keys():
            _apply_run_relic(str(relic_id))

func serialize() -> Dictionary:
    return {"purchased": purchased, "active": active, "wave": wave, "difficulty": difficulty,
        "coins_this_raid": coins_this_raid, "pending_choices": pending_choices.duplicate(),
        "run_stage": run_stage, "pending_routes": pending_routes.duplicate(true),
        "run_relics": run_relics.duplicate(), "current_encounter": current_encounter.duplicate(true),
        "best_wave": best_wave.duplicate(), "run_history": run_history.duplicate(true),
        "next_route": _next_route, "last_wave_coins": _last_wave_coins,
        "trail_mode": trail_mode, "trail_supplies": trail_supplies, "trail_camps": trail_camps,
        "trail_completions": trail_completions.duplicate(),
        "astral_encounter": astral_encounter, "astral_completions": astral_completions.duplicate()}

func deserialize(d: Dictionary) -> void:
    purchased = d.get("purchased", {})
    active = bool(d.get("active", false))
    astral_completions = {}
    var saved_astral: Variant = d.get("astral_completions", {})
    if saved_astral is Dictionary:
        for trial in ASTRAL_TRIALS:
            var ident := str(trial.id)
            if saved_astral.has(ident) and int(saved_astral[ident]) > 0:
                astral_completions[ident] = clampi(int(saved_astral[ident]), 1, 100000)
    astral_encounter = str(d.get("astral_encounter", "")) if active else ""
    if not ASTRAL_TRIALS.any(func(trial): return str(trial.id) == astral_encounter): astral_encounter = ""
    # Older active gauntlet saves finish under their original rules.
    trail_mode = active and bool(d.get("trail_mode", false))
    trail_supplies = clampi(int(d.get("trail_supplies", 0)), 0, 20) if trail_mode else 0
    trail_camps = clampi(int(d.get("trail_camps", 0)), 0, 2) if trail_mode else 0
    trail_completions = {}
    var saved_completions: Variant = d.get("trail_completions", {})
    if saved_completions is Dictionary:
        for diff in saved_completions:
            if DataLoader.raid_shop.get("difficulties", {}).has(diff):
                trail_completions[diff] = clampi(int(saved_completions[diff]), 0, 100000)
    wave = int(d.get("wave", 0))
    difficulty = d.get("difficulty", "normal")
    coins_this_raid = maxf(0.0, float(d.get("coins_this_raid", 0.0)))
    if not is_finite(coins_this_raid): coins_this_raid = 0.0
    pending_choices = []
    var choices: Variant = d.get("pending_choices", [])
    if active and choices is Array:
        for choice in choices.slice(0, 3):
            if choice_info(str(choice)) != {}:
                pending_choices.append(str(choice))
    best_wave = {}
    var saved_best: Variant = d.get("best_wave", {})
    if saved_best is Dictionary:
        for diff in saved_best:
            if DataLoader.raid_shop.get("difficulties", {}).has(diff):
                best_wave[diff] = clampi(int(saved_best[diff]), 0, 100000)
    run_relics = {}
    var saved_relics: Variant = d.get("run_relics", {})
    if active and saved_relics is Dictionary:
        for relic_id in saved_relics:
            if RELICS.has(relic_id):
                run_relics[relic_id] = clampi(int(saved_relics[relic_id]), 0, 3)
    current_encounter = {}
    if active and d.get("current_encounter", null) is Dictionary:
        current_encounter = (d["current_encounter"] as Dictionary).duplicate(true)
    _next_route = str(d.get("next_route", "skirmish"))
    if not ROUTES.has(_next_route):
        _next_route = "skirmish"
    _last_wave_coins = maxf(0.0, float(d.get("last_wave_coins", 0.0)))
    if not is_finite(_last_wave_coins):
        _last_wave_coins = 0.0
    run_history = []
    var history: Variant = d.get("run_history", [])
    if active and history is Array:
        for entry in history.slice(-12):
            if entry is Dictionary:
                run_history.append(entry)
    pending_routes = []
    var saved_routes: Variant = d.get("pending_routes", [])
    if active and saved_routes is Array:
        for route in saved_routes.slice(0, 3):
            if route is Dictionary and ROUTES.has(str(route.get("id", ""))) and (str(route.get("id", "")).begins_with("trail_") == trail_mode):
                var valid_route: Dictionary = ROUTES[str(route["id"])].duplicate(true)
                valid_route["id"] = str(route["id"])
                pending_routes.append(valid_route)
    run_stage = str(d.get("run_stage", "reward" if not pending_choices.is_empty() else "combat")) if active else "combat"
    if not ["combat", "reward", "route"].has(run_stage):
        run_stage = "combat"
    wave = maxi(0, wave)
    if trail_mode:
        wave = mini(wave, TRAIL_STOPS + 1)
        if run_stage == "route":
            pending_routes = pending_routes.filter(func(route): return (str(route.id) == "trail_boss") == (wave >= TRAIL_STOPS))
    if run_stage == "route" and pending_routes.is_empty():
        if trail_mode:
            _offer_trail_routes()
        else:
            for route_id in ["skirmish", "horde", "elite"]:
                var valid_route: Dictionary = ROUTES[route_id].duplicate(true)
                valid_route["id"] = route_id
                pending_routes.append(valid_route)
    if run_stage == "combat" and not pending_choices.is_empty():
        run_stage = "reward" # legacy save compatibility
    if not DataLoader.raid_shop.get("difficulties", {}).has(difficulty): difficulty = "normal"
    _reapply()
