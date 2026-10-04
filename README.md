# Emberreach — Godot 4 (GDScript)

A data-driven, offline-capable idle RPG. All content lives in `res://data/*.json`; the code is
generic and never hardcodes items, monsters, recipes, or skills.

> **Engine:** Godot 4.7 (GDScript 2.0) — `project.godot` declares
> `config/features=PackedStringArray("4.7")`. Validated end-to-end with the local Godot 4.7.2
> headless build; the project imports and runs with **zero script errors**.

---

## 1. Quick start

```bash
# Open the folder in the Godot 4.x editor and press F5, or run headless checks:
godot --headless --path . -- --smoke       # formula / data verification
godot --headless --path . -- --tests       # full test suite (prints its own check count)
godot --headless --path . -- --selftest    # end-to-end gameplay self-test
godot --headless --path . -- --docs        # README fact-block drift check (--fix rewrites it)
```

## 2. Project layout

```
Emberreach/
├── project.godot              # game autoloads + settings
├── data/                      # ALL content (JSON) — the "mod" surface
│   ├── skills.json            # every skill has authored actions + a working system
│   ├── new_skill_systems.json # species / devices / enchants / dreams / bazaar
│   ├── items.json  monsters.json  dungeons.json  areas.json  game_modes.json
│   ├── quests.json  rotating_tasks.json  achievements.json  tutorial.json
│   ├── trader.json  raid_shop.json  shop.json  shop_store.json  shop_township.json
│   ├── shop_museum.json  prayers.json  special_attacks.json  constellations.json
│   ├── obstacles.json  familiars.json  pets.json  slayer_tasks.json  audio.json
│   └── cartography_hexes.json  cartography_ships.json  archaeology_sites.json
│       harvesting_veins.json
├── scripts/
│   ├── autoload/              # singleton managers (see §4)
│   ├── combat/                # CombatFormulas.gd, StatusEffect.gd, CombatSimulator.gd
│   ├── core/                  # ContentValidator, BalanceReport, tests helpers
│   ├── resources/             # typed Resource classes (ItemData, MonsterData, ...)
│   ├── tests/                 # TestRunner (--tests)
│   └── ui/                    # MainUI shell, SidebarNav, StatusBar, DetailPanel,
│                              #   Widgets, UIStyle/UITokens, ui/panels/* panel scripts
├── scenes/main.tscn           # entry scene
└── assets/icons/icon.svg
```

## 3. Architecture in one paragraph

Content JSON is read once by **DataLoader**. **PlayerData** holds all persistent state.
Every bonus source (equipment, prayers, potions, pets, agility, astrology, mastery checkpoints,
shop upgrades…) registers a **ModifierSource** with **ModifierManager**, which caches the combined
value of every modifier key. Simulation loops (**SkillManager**, **CombatManager**,
**FarmingManager**, **TownshipManager**) only *ask* ModifierManager and *write* to
PlayerData/BankManager. **EventBus** decouples everything — the UI never touches game logic
directly, it listens to signals. **SaveManager** serialises to JSON, and **OfflineProgression**
replays elapsed time through the *same* code paths.


## 4. Autoload singletons

| Singleton | Responsibility |
|---|---|
| `EventBus` | Global signal hub. |
| `XPTable` | Level 1–120 XP table + lookups. |
| `DataLoader` | Loads `data/*.json`; typed getters. |
| `SaveManager` | JSON save/load; autosave 60 s + on events. |
| `PlayerData` | Skills, GP, currencies, unlocks, completion log. |
| `ModifierManager` | **Heart.** Aggregates all bonuses; stacking + cache. |
| `MasteryManager` | Per-action mastery, pools, 10/25/50/95% checkpoints. |
| `BankManager` | Stacking storage, search/sort/sell, slot-cost curve. |
| `EquipmentManager` | 14 slots, saved sets, stat aggregation. |
| `ShopManager` | Purchases; owns the `shop` modifier category. |
| `PrayerManager` | ≤2 active prayers; registers prayer modifiers; point drain. |
| `PotionManager` | Active potion; registers its effect; charge-based consumption. |
| `FarmingManager` | Timestamp crop growth. |
| `TownshipManager` | Hourly passive production. |
| `RanchingManager` | Pens, stock, feed, breeding, produce and manure. |
| `InscriptionManager` | Research, scribing quality texts, equippable tomes, active glyphs. |
| `EngineeringManager` | Device slots, installed workers, hourly fuel and prepaid time. |
| `EnchantingManager` | Disenchant to typed essence; enchant individual gear pieces. |
| `DreamwalkingManager` | Offline dream allocation, dream depth, events and the Dream Bazaar. |
| `CombatManager` | Tick combat, endless areas, dungeons, loot, death, auto-eat. |
| `SkillManager` | Generic action loop for all non-combat skills. |
| `GameManager` | Main loop, pause/speed, new game, load → offline. |
| `OfflineProgression` | ≤24 h replay; seeded RNG. |
| `SlayerManager` | Tasks, kill tracking, rewards, Slayer Shop. |
| `AgilityManager` | 15 obstacle slots, pillars, blueprints. |
| `SummoningManager` | Marks, tablets, 2 familiars, charges, synergies. |
| `AstrologyManager` | Constellation stars purchased with Stardust. |
| `PetManager` | Rare passive pet unlocks. |
| `CartographyManager` | Hex travel, survey, Points of Interest. |
| `ArchaeologyManager` | Excavation tracking + museum donations. |
| `RaidManager` | Raid: waves, 3-choice picks, Raid Shop. |
| `Goals` | Goal tracker: pinned items/recipes/unlocks with dependency chains. |
| `Quests` | Data-driven tasks with event-driven objectives and exactly-once rewards. |
| `Achievements` | Milestones with modest, exactly-once rewards. |
| `ProgressTracker` | Lifetime counters feeding quests, milestones and the collection log. |
| `PrestigeManager` | Ascendancy: the lifetime-XP gate, reset, and its additive bonuses. |
| `TutorialManager` | Data-driven onboarding steps from `tutorial.json`. |
| `ActionQueueManager` | Queued skill actions; policy and persistence for the queue screen. |
| `LootFilterManager` | Loot filter policy for the combat simulator. |
| `CombatSimulatorManager` | Win-chance simulation for an area/dungeon using the real formulas. |
| `AudioManager` | Synthesized SFX + music from `data/audio.json`; Music/SFX volume buses. |
| `AssetRegistry` | Art system: loads textures by convention, generates placeholders. |

## 5. Playable UI

The shell has one screen per sidebar route in `Screens.ORDER`, plus Save recovery, which takes
over only when a save cannot load. The sidebar and the compact nav drawer read that same route
table, so reachability is one list; it also lists every skill.

![Playable UI loop](assets/ui_flow.png)

| Screen | What it does |
|---|---|
| **Overview** | Dashboard: current activity, skill highlights, loadout readiness, goals, unlocks, events, suggestions — plus a sub-tab per skill. |
| **Skills** | Pick any skill → action list (locked actions greyed), details, Start/Stop, live progress, mastery pool %, ≈ XP/hour, per-action mastery levels. |
| **Combat / Expeditions** | Choose area (endless) or dungeon, attack style + sub-style, Start/ **Flee**, live HP bars, DR/attack-speed/crit readout, prayer toggles, area hazard readout. |
| **Prayers** | The 60 prayers grouped by role, with points/minute and time until depletion. |
| **Raid** | Wave-by-wave raid run, 3-choice wave rewards, banked coins and the Raid Shop. |
| **Storage** | Search, sort, filters, favourites, protection, inspect, Sell 1 / Sell All / Equip / Bury / **Use**. |
| **Provisioner / General Store** | Shelves you return to vs. a searchable catalogue of upgrades you exhaust. |
| **Tasks / Milestones / Collection** | Quests with live objective progress, achievements, and the completion log. |
| **Stats** | The lifetime record: counters that feed quests, milestones and the collection log. |
| **Settlement** | Buildings with costs, upgrade path, and links to the systems they improve. |
| **Farm** | Husbandry plots that grow in real time, planted and harvested by hand. |
| **Equipment** | 14 slots, saved sets with ownership checks, aggregated stats. |
| **Action Queue / Simulator** | Queued skill actions with policy and persistence; win-chance simulation on the real formulas. |
| **Ascendancy** | The reset layer: lifetime-XP gate, what resets and what survives, additive bonuses. |
| **Settings / Recovery** | Preferences and sound; Recovery takes over when a save cannot load. |
| Right panel | Contextual detail pane: equipment by slot, stats, goal routing, screen help. |
| Top bar | Currencies, combat level, Pause, Save, action/activity strip. |
| Welcome-back | Offline-progression summary modal on load. |

## 6. Data format

### Skill + action (`data/skills.json`)

```json
"woodcutting": {
  "id": "woodcutting", "name": "Woodcutting",
  "category": "non_combat", "type": "gathering", "max_level": 120,
  "actions": [
    { "id": "normal_tree", "name": "Normal Tree", "level_required": 1,
      "base_interval": 3.0, "base_xp": 10, "output_items": { "normal_log": 1 },
      "secondary_outputs": [ { "item_id": "bird_nest", "chance": 0.005 } ],
      "mastery_action_time": 3.0 }
  ]
}
```

Cooking adds `"success_chance"` and `input_items`; artisan skills use a fixed
`mastery_action_time` (Smithing 1.7, Fletching 1.3, Crafting 1.65, Runecrafting 1.7,
Herblore 1.7, Summoning 4.85 s). Gathering nodes add `"node_hp"` and `"respawn_seconds"`:
each completed action depletes the node by 1 (a `node_preservation_percent` roll can prevent it);
at 0 HP the node respawns after its timer.

### Item (`data/items.json`)

```json
"bronze_platebody": {
  "id": "bronze_platebody", "name": "Bronze Platebody", "item_type": "equipment",
  "sell_price": 30, "equipment_slot": 1,
  "equipment_stats": { "melee_defence": 8, "ranged_defence": -2, "magic_defence": -4 },
  "level_requirements": { "defence": 1 },
  "upgrade_path": "bronze_platebody_s", "upgrade_materials": { "silver_bar": 1 }
}
```

`equipment_slot` indexes match `ItemData.EquipmentSlot` (8 = weapon, 9 = shield, 7 = ring).

### Monster (`data/monsters.json`)
```json
"skeleton": {
  "id": "skeleton", "name": "Skeleton", "combat_level": 12, "hitpoints": 30,
  "attack_type": "melee", "attack_speed": 2.4, "max_hit": 5, "accuracy_rating": 30,
  "melee_evasion": 12, "ranged_evasion": 12, "magic_evasion": 12, "damage_reduction": 5,
  "loot_table": [ { "item_id": "bones", "quantity": 1, "chance": 1.0 } ],
  "bone_type": "bones", "slayer_xp": 20, "is_boss": false, "respawn_time": 3.0,
  "can_be_stunned": true, "is_immune_to_effects": false
}
```

### Special attack (`data/special_attacks.json`)

```json
"stun_bash": {
  "id": "stun_bash", "name": "Stun Bash", "trigger_chance": 15.0,
  "effect": "stun", "damage_multiplier": 1.0,
  "applies_status": "stun", "status_chance": 100.0, "status_duration": 3.0
}
```

Weapons reference a special attack by id (`"special_attack": "life_leach"`); monsters list ids
in `"special_attacks": [ "dragonfire" ]`. A trigger replaces the normal attack and can apply a
status effect (stun/slow/burn/poison…).

### Modifier keys

`<scope>_<stat>`, e.g. `global_skill_xp_percent`, `woodcutting_interval_percent`,
`melee_max_hit_percent`, `damage_reduction_percent`. Read via `ModifierManager.get_modifier(key)`
or the named helpers. Registry: `scripts/resources/ModifierKeys.gd`.

## 7. Verification

### 7.1 `--smoke` (formulas + data)

| Check | Expected | Status |
|---|---|---|
| XP to level 99 / 120 | 13,034,431 / 104,273,167 | ✅ exact |
| Hit chance at equal ratings | 50 % | ✅ |
| Fresh-character combat level | 1 | ✅ |
| Save version | 2 | ✅ |

Loaded content. This block is generated from the live singletons — do not hand-edit it; run
`--docs --fix` to rewrite it and `--docs` to fail when it has drifted:

<!-- doc-facts:start -->
| Check | Value |
|---|---|
| Skills | 39 (9 combat / 30 non-combat) |
| Skill actions | 593 |
| Items | 629 |
| Monsters | 46 |
| Areas | 14 |
| Dungeons | 17 |
| Prayers | 60 |
| Autoload singletons | 42 |
| Screens | 21 |
<!-- doc-facts:end -->

Formula depth beyond these (hit-chance curves, DR combination, level lookups, panel
construction) is covered by `--tests`, which prints its own check count. `--docs` additionally
fails when any autoload singleton or screen is missing from the tables above, since a systems
list rots by omission long before its numbers do.

### 7.2 `--selftest` (end-to-end gameplay)

`--selftest` runs the closed gear loop end to end and prints its own check count. Progression
trace observed:

```
  1. New journey started; gold 0, woodcutting level 1
  2. Gathered 40 × normal_log from woodcutting
  3. Crafted bronze_helmet ×1 in smithing
  4. Equipped bronze_helmet: yes
  5. Expedition in farmlands: 182 victory(ies)
  6. Task 'hands_that_build' claimed (300 GP, 2 objectives)
  7. Built township_building_apothecary to level 1
  8. Saved and reloaded: XP 664 -> 664, 2 buildings
  9. Offline: 1h 00m processed, 1245 actions, 1 levels
 10. Totals: total levels 316, tasks claimed 2, milestones 7, items discovered 10
```

The gather → craft → equip → fight steps are the closed **gear loop**: logs gathered,
a bronze helmet smithed and equipped, then 182 expedition victories.

## 7b. Art system & asset pipeline

Textures are loaded **by filename convention** from `res://assets/`, with a generated coloured
placeholder when a file is missing — so the game looks intentional before any art exists.

```
assets/icons/items/<item_id>.png          32x32
assets/icons/skills/<skill_id>.png        32x32
assets/sprites/monsters/<monster_id>.png  96x96
assets/icons/{areas,dungeons,prayers,pets,familiars,obstacles,currencies,slots,status}/<id>.png
assets/ui/<name>.png                      (panel_9slice, button_9slice, progress_bg, ...)
```

Add files, then check what's still missing:

```bash
godot --headless --path . --import    # import the new textures
```

A missing file is not an error: `AssetRegistry` falls back to a generated coloured placeholder, so
the game runs before any art exists.

## 8. Extending the game

- **Add a skill:** add an entry to `skills.json` with an `actions` array. No code changes — as
  long as the skill reuses the shared action loop. A skill with its own system (Ranching,
  Engineering, Dreamwalking…) also needs a manager, a panel in `Screens.PANEL_SCRIPTS`, and the
  sidebar icon cases; the `--docs` check will fail until the new manager and screen are at least
  named in the tables above.
- **Add an item/monster/dungeon:** add JSON; DataLoader picks it up.
- **Add a bonus source:** `ModifierManager.register("<id>", {"<key>": value}, "<category>")`.
- **Add a shop upgrade / prayer / potion:** add to `shop.json` / `prayers.json` / `items.json`
  (`item_type: "potion"`); the manager registers its `effect` / `potion_effect` automatically.
- **Add a special attack:** add to `special_attacks.json`, then reference it from a weapon or monster.

## 9. Known gaps

- All 39 skills, the Phase 9 endgame (God Dungeons, Raid, Abyssal) and the dark-fantasy UI
  overhaul are implemented; area hazards **are** applied during combat (`_active_hazard()`).
- Depth still light in places: Township tasks/education, and Summoning tablet quantity scaling.
  Cartography ship upgrades and the Archaeology museum shop were implemented after this list was
  first written — `cartography_ships.json` and `shop_museum.json` each have a live manager
  consumer now.
- `data/harvesting_veins.json` is loaded and validated but read by **no** manager: harvesting node
  stats come from `skills.json` actions (`node_hp` / `respawn_seconds`). Vestigial data, kept only
  because `ContentValidator` still checks it.
- Monsters now differ mechanically, not only statistically: elemental affinities (`weak_to` /
  `resists`, x1.25 / x0.75 on the attacker's style), the `venomous`, `lifedrain` and `armored`
  passives, boss phases (HP-threshold stat/attack-type changes and phase statuses, saved mid-fight)
  and status resistance on gear. Authoring caveat: `armored` removes a flat 8 % of the monster's max
  HP per landed hit, so it is only appropriate on monsters under ~300 HP.
- Long-tail item display names were renamed by `tools/long_tail_rename.py` (idempotent, re-runnable,
  display names only — item ids are stable, so saves and icons are untouched). The verbatim-Melvor
  names it targeted are gone from `items.json`; see `CHANGELOG.md` for the pass.
- Audio is fully synthesized (no recorded assets): two generative music tracks and 16 SFX
  recipes rendered to PCM at load.
- Ascendancy (prestige) is implemented — a lifetime-XP gate granting +5 % XP and +5 % gold per
  ascension, additive and capped. Single-node refunds and a full-tree `PrestigeManager.respec()`
  exist, so a bad early choice is never permanent.
- The palette is not colourblind-safe: `GREEN` and `RED` are near-identical under deuteranopia.
  Three rows that once conveyed state by colour alone now carry a glyph, but a palette variant is
  the real fix and is not done.
