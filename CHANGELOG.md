# CHANGELOG

## 2026-09-26 — overhaul: repo hygiene, warnings, content depth, combat polish, decomposition

### Removed
- `scripts/ui/BankPanel.gd`, `scripts/ui/CombatPanel.gd` (stale duplicates of the
  `panels/` versions, zero references), `archive/` (~932 KB unreferenced manifests),
  5 orphan UI files (`ShopPanel`, `SkillList`, `SkillPanel`, `RightPanel`,
  `WelcomeBackModal` — self-mentions only). `shots/` (93 PNGs) moved out of tree.
- `git init` + `.gitignore` (`.godot/`, `.superpowers/`, `shots/`); work committed per phase.

### Fixed
- All 50 editor script warnings: `name`/`tr`/`wrap`/`label`/`sign`/`seed`/`ready`/`title`/
  `shell` shadowing renames, explicit `floori()`/`>>` integer division, unused params
  prefixed, `Goals._fmt` made non-static (7 static-via-instance calls), redundant
  preload consts dropped where headless-safe (kept where the global class cache
  cannot see them headless). 6 same-name preload warnings remain by necessity.

### Added (content)
- Slayer: `abyssal` (125), `godslayer` (160), `herald` (210) tiers; high-tier pools
  refilled with elementals, gods and abyssals (29-monster roster now fully covered).
- Corruption: 1 → 6 actions (commune → become_herald), existing `abyssal_essence` only.
- Mastery backfill (woodcutting pattern): cartography, archaeology, alt_magic,
  farming, harvesting, astrology.

### Added (combat)
- `regeneration` passive honored in `CombatManager` (2% max HP per own attack) and
  mirrored in `CombatSimulator`; unknown passive ids fail validation.
- Area `hazard` (`enemy_damage_percent`, `player_accuracy_percent`,
  `player_evasion_percent`, label) in both engines via snapshot; hazards on
  Frostbound Reach, Ashwyrm Hollow, Broodweb Fen (replaces dead `area_effect`),
  Umbral Deep, Riftmouth; shown on the Combat panel; validator range-checked.

### Refactored
- `SidebarNav` extracted from `MainUI` (sidebar/drawer/nav buttons); `TestSupport`
  (`backup_save_files`, `restore_snapshot`, `widest_descendant`) extracted from
  `TestRunner`. No behavior changes.

### Verified
- `--validate`: 0 errors. `--tests`: 310/310 pass (incl. new regen/hazard parity checks).

## 2026-09-17 — stardust added (currencies complete)
### Added
- `assets/icons/currencies/stardust.png` — sliced from the supplied single-icon sheet:
  white keyed, detached sparkles kept, 2-pass de-fringe, 64×64 transparent.

### Clarification
- `stardust` was already listed in the manifest all along — as **both** `icons/items/stardust.png`
  and `icons/currencies/stardust.png` (see the Items and Currencies sections of
  `assets/manifest/ASSET_MANIFEST.html`). It only showed the grey placeholder tile because the art
  was missing; now it renders the real icon.

### Verified
- `--assetreport`: `icons/currencies: 7 / 7`; overall **63 / 641**. `--import` 0 errors/warnings;
  `--smoke` passes.

## 2026-09-17 — Currency icons (6 of 7)
### Added
- `assets/icons/currencies/*.png` sliced from the supplied sheet at 64×64, transparent:
  `gp`, `slayer_coins`, `prayer_points`, `golden_stardust`, `raid_coins`, `abyssal_coins`.
  The TopBar picks these up automatically via `AssetRegistry.icon("currencies", id)`.

### Note / gap
- The sheet contains **6** icons; **`stardust`** is not present, so that slot still shows a placeholder.
- Mapping was verified by rendering each icon with its intended label underneath and having the
  recognizer confirm the picture matches the label — **0 mismatches**
  (gp = coin stack, slayer_coins = red skull token, prayer_points = blue token with gold star,
  golden_stardust = gold dust with sparkles, raid_coins = purple horned token,
  abyssal_coins = dark purple spiral).

### Verified
- `--assetreport`: currencies 6/7, skills 29/29, slots 15/15, ui 12/12 → **62 / 641** overall.
  `--import` 0 errors/warnings; `--smoke` passes.

## 2026-09-17 — Alpha fix: skill + slot icons re-sliced (missing elements restored)
### Fixed
- The skill and slot icons were losing small detached elements (sparkles, particles, thin lines)
  and light details. All **44 icons** (29 skills + 15 slots) re-sliced with a corrected pipeline:
  - white-key threshold 236 → **250** (only near-pure white is background, so light elements survive),
  - removed the small-component filter (now `MIN_AREA = 6`, was 200) so detached parts are kept,
  - each component is assigned to the **nearest cell centre** (was centroid bucketing), so a part
    drifting over a cell edge still belongs to its icon,
  - a **2-pass de-fringe** removes the anti-aliased halo the higher threshold leaves behind.
- The UI kit was already correct and is untouched.

### Verified
- Re-read contact sheets with image recognition: small sparkles/particles confirmed present on the
  prayer star, skull, corruption orb, astrology moon and runecrafting rune. Overall verdict:
  "all 8 icons appear complete, including their small sparkles/particles… cleanly cut out", and for
  the full non-combat set "no icon appears to be missing a major element".
- `--assetreport`: skills 29/29, slots 15/15, ui 12/12. `--import` 0 errors/warnings; smoke + selftest pass.

## 2026-09-17 — Equipment slot icons + UI kit theme
### Added
- `assets/icons/slots/*.png` — 15 equipment slot icons, sliced from the supplied 3×5 sheet in
  canonical order (helmet, platebody, platelegs, boots, gloves, cape, amulet, ring, weapon, shield,
  quiver, summon_1, summon_2, passive, consumable), 128×128 transparent.
- The 12 supplied UI kit files were detected in `assets/ui/` (panel/button 9-slice, hover, progress
  track/fill, player/enemy HP fills, tabs, toast, scrollbar) plus `assets/icons/icon.png`.

### Changed
- `UIStyle.build_theme()` — builds a real Godot `Theme` from the kit: 9-slice `PanelContainer` /
  `Panel` / `ItemList` / `PopupMenu`, button normal+hover states, **tiled progress bars**, tab
  styles, scrollbar grabbers and `LineEdit`. Anything missing falls back to the previous flat style,
  so the game looks correct with partial art.
- `MainUI` applies the theme to the whole UI tree, drops the old hand-rolled panel overrides, and
  shows `ui/logo.png` in the nav bar.
- `CombatPanel` HP bars now use `hp_fill_player.png` / `hp_fill_enemy.png`.
- `--assetreport` now also tracks `icons/slots`, `icons/currencies` and the `ui` kit.

### Verified
- Slots re-read from a contact sheet: all 15 correct and complete, none clipped/broken/empty.
- `--assetreport`: skills 29/29, slots 15/15, ui 12/12 → **56 / 641** overall.
- `--import`: 0 errors, 0 warnings. `--smoke` + `--selftest` pass with the theme applied.

## 2026-09-17 — Skill icons re-sliced from white-background sheets (cleaner)
### Changed
- All 29 skill icons re-sliced from the new **white-background** sheets (combat 2×5 with one empty
  cell; non-combat 4×5). Same filenames and order; PNGs replaced.
- Pipeline (v3): border flood-fill on the white background (preserves interior whites like the shield
  and heart highlight), global connected-component labelling, then each component is **assigned to a
  grid cell by its centroid** and the cell's components are unioned. That keeps detached parts
  (sparkles, steam, fishing line) with their icon, never clips at a cell boundary, and never merges
  two neighbouring icons — the problem with the first per-cell crop and with naive clustering.
- Stray-component cells are dropped; the sheet yields exactly 9 and 20 icons.

### Verified
- Contact-sheet re-read of all 29: correct content and order, and explicitly "no flat cut-offs at the
  edges, no missing pieces, no extra fragments from neighbouring cells".
- `--assetreport`: `icons/skills: 29 / 29 present`. `--import`: 0 errors, 0 warnings. `--smoke` passes.

## 2026-09-17 — Art: 20 non-combat skill icons (all 29 skills complete)
### Added
- `assets/icons/skills/*.png` for the 20 non-combat skills, sliced from the supplied 4×5 sheet in
  manifest order: woodcutting, fishing, mining, farming, firemaking, cooking, smithing, fletching,
  crafting, runecrafting, herblore, thieving, agility, summoning, astrology, alt_magic, township,
  cartography, archaeology, harvesting (128×128, transparent).
- Slicing pipeline (v2): this sheet's background is **dark texture**, not a flat colour, so instead of
  a threshold key it estimates the background per cell from the cell's outer ring, builds a soft
  alpha matte from RGB distance (ramp 34→72), removes isolated specks with a summed-area density
  filter, then trims to the main blob.
- Verified by re-reading a 5×4 contact sheet: all 20 correct and in order, none clipped or empty.

### Verified
- `--assetreport`: `icons/skills: 29 / 29 present` (29 / 607 total). `--import`: 0 errors, 0 warnings.
- `--smoke` passes. The skill sidebar now shows real icons for all 29 skills.

## 2026-09-17 — First art delivered: 9 combat skill icons
### Added
- `assets/icons/skills/*.png` for the 9 combat skills, sliced from the supplied sheet
  (128×128, transparent): `attack`, `strength`, `defence`, `hitpoints`, `ranged`, `magic`, `prayer`,
  `slayer`, `corruption`.
- Slicing pipeline: border flood-fill background removal (the sheet's background is near-black), regular
  grid split per row (5 + 4), per-icon content trim, square canvas, LANCZOS resize.
- Verified by re-reading the sliced contact sheet with image recognition: Sword, Bicep, Shield, Heart,
  Bow, Wizard hat, Star, Skull, Purple orb — correct content and order.

### Verified
- `--assetreport`: `icons/skills: 9 / 29 present` (9 / 607 total). `--import`: 0 errors, 0 warnings.
- `--smoke` still passes. Skill sidebar now renders the real combat icons.

## 2026-09-17 — Asset manifest as an interactive HTML checklist
### Changed
- The manifest is now `assets/manifest/ASSET_MANIFEST.html` (was Markdown): a self-contained page with
  one **card per asset in a responsive column grid**, each showing the file path, the human-readable
  **name** taken from the game data, size, priority and a **live preview** that fills in as art arrives.
- Adds search (by file or name), P0/P1/P2 filters, a "hide completed" toggle, and click-to-tick-off
  persisted in `localStorage`.
- `asset_manifest.csv` now carries a `name` column; the Markdown manifest is retired.
- README §7b and the art brief updated to point at the HTML checklist.

### Verified
- Regenerated: 652 assets (450 P0 / 97 P1 / 105 P2). `--import`: 0 errors, 0 warnings.

## 2026-09-17 — Skill list grouped by category
### Changed
- `data/skills.json` now carries an explicit `order` field (1–9 combat, 10–29 non-combat) and the
  file itself is written combat-first. Canonical order from the brief.
- `SkillList` renders **two headed sections** — `Combat (9)` and `Non-Combat (20)` — sorted by
  `order` instead of alphabetically. The filter still narrows within both groups, and an empty group
  hides its header.
- The asset manifest lists skill icons combat-first too, so art production follows the same grouping.

### Verified
- `--import`: 0 errors, 0 warnings. `--smoke` / `--selftest` still pass. skills.json key order
  starts attack, strength, defence, hitpoints, ranged, magic, prayer, slayer, corruption, woodcutting…

## 2026-09-17 — Art system + asset pipeline
### Added
- `AssetRegistry` autoload (27th) — convention-based texture loading with generated
  placeholder tiles, so partial art works at every stage.
- `--assetreport` mode: scans every data id, prints present/total per group, writes
  `res://assets/ASSET_STATUS.md`.
- `assets/manifest/ASSET_MANIFEST.md` + `asset_manifest.csv` — the full 650-asset demand list
  (449 P0 / 96 P1 / 105 P2), generated from the actual game data. The folder carries a
  `.gdignore` so Godot does not import the CSV as translations.
- `melvor_clone_art_brief.html` (in DELIVERY) — the art brief: conventions, requirements, the UI
  kit, per-category tables, delivery order and the polish backlog.

### Changed
- UI now renders art: skill icons (SkillList), item icons (BankPanel), monster sprite
  (CombatPanel), currency icons (TopBar), equipment-slot icons (RightPanel).
- Autoloads 26 → 27.

### Verified
- Fresh `--import`: 0 errors, 0 warnings.
- `--assetreport`: 0 / 607 authored files present (placeholders fill in), report written.
- `--smoke` and `--selftest` still pass.

## 2026-09-16 — Phase 9: endgame
God Dungeons, the endgame dungeon chain, the Golbin Raid minigame and Abyssal/Corruption content.

### Added
- `RaidManager` (26th autoload) — Golbin Raid waves, 3-choice reward picks, Raid Shop, Raid Coins.
- `data/raid_shop.json` — raid upgrades, ALT items, difficulty table.
- 4 **God Dungeons** (Air/Water/Earth/Fire) with god minions + bosses; each drops its **shard after
  every kill** and has completion + first-clear rewards.
- Endgame dungeons: Into the Mist, Impending Darkness, Underwater City, Throne of the Herald.
- 19 new monsters (god minions/bosses, Mist/Darkness/Underwater/Herald, abyssal trio) → 29 total.
- God armour sets (Aeris/Glacia/Terran/Ragnar), 4 godswords, 4 shards, Abyssal Whip/Essence,
  5 raid ALT weapons + a raid pet egg. Items 344 → **380**.
- Abyssal areas/monsters, a Corruption skill action, 6 new special attacks (14 total).

### Changed
- `CombatManager` — shard drops from `context.shard_item`; 2× player attack speed inside a raid;
  forced Auto Eat Tier II in a raid; combat pet rolls on kill.
- `DataLoader` loads `raid_shop.json`; `SaveManager` persists `RaidManager`.

### Verified
- Fresh `--import`: 0 errors, 0 warnings.
- `--selftest`: `god shard drop=1`; `raid waves=4 raid_coins=43`; all earlier checks still pass.

## 2026-09-16 — Phase 8 complete: all 29 skills have content + a system
Finished the remaining skills: Prayer depth, Slayer, Agility, Summoning, Astrology, Thieving,
Alt. Magic, Township, Cartography, Archaeology, Harvesting, Pets/Completion.

### Added (managers — 25 autoloads now)
- `SlayerManager` — task assign/reroll/extend, kill tracking, Slayer Shop.
- `AgilityManager` — 15 obstacle slots, consecutive-slot rule, pillars, blueprints.
- `SummoningManager` — mark discovery, tablet equipping, charge consumption, synergies.
- `AstrologyManager` — stardust star purchases.
- `PetManager` — rare passive pet rolls (skill + combat).
- `CartographyManager` — hex travel, survey, POI rewards/effects.
- `ArchaeologyManager` — excavation tracking + museum donations.
- `TownshipManager` rewritten — buildings, production, worship, trader.

### Added (data)
- Thieving: 16 NPCs with perception/stealth, stun + fail damage, GP rewards.
- Agility: 45 obstacles (15 slots × 3) + 3 pillars + 3 elite pillars; 25 constellations;
  25 familiars + marks/tablets/shards; 25 hexes with POIs; 4 dig sites + artefacts; 3 veins;
  16 Alt. Magic spells; township buildings; 32 pets; 29 skillcapes + superior + max + completion cape.
- Items: **344** total (up from 208).

### Changed
- `SkillManager` — thieving stealth vs perception, stun/fail-damage on a failed action,
  `gp_reward` handling, and post-action hooks (summoning marks/charges, pet rolls, archaeology).
- `DataLoader` — loads the four new content files; `SaveManager` — persists the seven new managers.

### Verified
- Fresh `--import`: 0 errors, 0 warnings.
- `--selftest`: slayer task assigned; agility obstacle built (+2% skill XP); astrology star bought
  (+3% attack XP); summoning tablets crafted, familiar equipped (+5% woodcutting interval);
  cartography POI found; thieving earned GP; save→load ok.

### Fix
- `SummoningManager.deserialize` typed-array conversion (same class of bug as PlayerData earlier).

## 2026-09-16 — Phase 8 (content breadth): the economy block
Mining, Smithing, Firemaking, Fletching, Crafting, Runecrafting and Herblore are now fully
specified, closing the gear loop (mine → smelt → smith → equip).

### Added
- `data/skills.json` — complete action lists: Mining (12 rocks, incl. Rune/Pure Essence, with node HP),
  Smithing (9 smelts + 44 smith actions across bronze/iron/steel/mithril × 11 gear pieces),
  Firemaking (9 logs), Fletching (shafts + 3 arrow tiers + 6 bows), Crafting (leather, 4 d'hide sets,
  jewelry), Runecrafting (11 runes + 4 staves), Herblore (4 potion families × 4 tiers), Farming (7 herbs).
- `data/items.json` — ~135 new items (ores, bars, full metal gear, arrowtips/bows, d'hide, gems,
  jewelry, runes, staves, herbs, seeds, potions) → **208 items**.
- Node HP mechanic in `SkillManager` (`node_hp` / `respawn_seconds`; depletion + respawn;
  `node_preservation_percent` roll) and `ModifierKeys.SUFFIX_NODE_PRESERVATION_PERCENT`.
- SkillPanel shows live **Node HP** for node-based actions.

### Changed
- `data/skills.json` gained `mastery_unlocks` tables for mining/smithing/firemaking/fletching/
  crafting/runecrafting/herblore.
- `--selftest` now exercises the mineral loop (mine → smelt → smith → equip).

### Verified
- Fresh `--import`: 0 errors, 0 warnings. `--smoke` clean (items 208, special attacks 8).
- `--selftest`: `mining copper=20 node_hp=6`; `smithing bars=35 scimitars=16 slash 0->7`.

### Fix
- Renamed `SkillManager.has_node()` → `is_node_based()` (it shadowed the built-in `Node.has_node()`).

## 2026-09-16 — Combat depth & systems completion
The remaining explicit engine items from the brief: special attacks, status-effect application,
per-item mastery unlocks, potion charges, and dungeon completion rewards.

### Added
- `data/special_attacks.json` — 8 special attacks (`life_leach`, `quick_strike`, `stun_bash`,
  `dragonfire`, `venom_bite`, `guaranteed_hit`, `ocean_song`, `cloudburst_magic_ray`).
- `scripts/autoload/PotionManager.gd` — the active potion as a `potion`-category modifier source;
  charge-based consumption per completed action / attack; auto-clears at 0; re-applies on load.
- `MasteryManager.update_item_mastery_source()` — per-item mastery unlock thresholds
  (1/10/25/50/95/99) register a cumulative modifier source for the active action.
- `data/skills.json` — `mastery_unlocks` tables for woodcutting, fishing, cooking, mining,
  smithing and firemaking.
- `EventBus` signals `player_special_attack` / `monster_special_attack`.
- BankPanel **Use** button (drinks the selected potion).

### Changed
- `scripts/autoload/DataLoader.gd` — loads `special_attacks.json`; adds `get_special_attack()`.
- `scripts/autoload/EquipmentManager.gd` — `get_weapon_special_attack()` now resolves the real
  special-attack definition instead of a placeholder.
- `scripts/autoload/CombatManager.gd` — weapon & monster special-attack rolls (with damage
  multiplier, lifesteal and status application) and dungeon completion rewards via `_grant_reward()`.
- `scripts/autoload/SkillManager.gd` — registers/unregisters the active action's item-mastery source.
- `project.godot` — 18 autoloads (added `PotionManager`).

### Verified
- `--smoke`: adds `special attacks loaded: 8`.
- `--selftest`: potion activates (10 charges, DR 0 → 2); 4 special attacks trigger in ~2 min of
  combat; `mastery_src=true`; save→load round trip ok.
- Fresh `--import`: 0 errors, 0 warnings.

## 2026-09-16 — Playable UI increment
Continues the initial scaffold. The engine was already verified; this increment closes the
"UI shell only" gap and adds the two glue systems the screens needed.

### Added
- `scripts/ui/UIStyle.gd` — shared lightweight styling helper.
- `scripts/ui/TopBar.gd` — live GP / Slayer Coins / Prayer Points / combat level + Pause + Save.
- `scripts/ui/SkillList.gd` — left sidebar: 29 skills, filter box, level labels.
- `scripts/ui/SkillPanel.gd` — action list (locked actions greyed), selected-action details,
  Start/Stop, live progress, mastery pool %, per-action mastery levels, ≈ XP/hour.
- `scripts/ui/CombatPanel.gd` — area/dungeon picker, attack style + melee sub-style, Start/Flee,
  monster & player HP bars, DR/attack-speed/crit readout, prayer toggles.
- `scripts/ui/BankPanel.gd` — search + sort (name/qty/value/type), inspect, Sell 1 / Sell All /
  Equip / Bury.
- `scripts/ui/ShopPanel.gd` — buy upgrades with affordability/requirement feedback.
- `scripts/ui/RightPanel.gd` — equipment by slot + headline combat stats.
- `scripts/ui/WelcomeBackModal.gd` — offline-progression summary dialog.
- `scripts/autoload/ShopManager.gd` — purchases; owns the `shop` modifier category.
- `scripts/autoload/PrayerManager.gd` — ≤2 active prayers; registers prayer modifiers; per-attack
  point drain with auto-deactivation.

### Changed
- `scripts/ui/MainUI.gd` — rewritten from a static shell into a real shell: composes the five
  regions, swaps the centre panel between Skill/Combat/Bank/Shop, wires notifications, and adds a
  `--selftest` end-to-end mode alongside `--smoke`.
- `project.godot` — registered `ShopManager` and `PrayerManager` autoloads.
- `scripts/autoload/PlayerData.gd` — fixed: JSON round-trips of typed `Array[String]` fields
  (`active_prayers`, `unlocked_pets`) threw at load; now converted explicitly.
- `README.md`, `IMPLEMENTATION_ROADMAP.md` — updated for 17 singletons and the playable UI.

### Review-driven fixes (from an independent static review pass)
- `scripts/autoload/EventBus.gd` — added `prayer_activated` / `prayer_deactivated` signals.
- `scripts/autoload/PrayerManager.gd` — re-registers active prayers on `game_loaded`; emits the new
  prayer signals on toggle/deactivate.
- `scripts/autoload/ShopManager.gd` — defensive `completion_log.get("dungeons", {})` (a save missing
  that subkey no longer raises).
- `scripts/resources/ModifierKeys.gd` + `scripts/autoload/BankManager.gd` — added and used the
  `BLESSED_BONE_OFFERING_FLAT` key constant instead of a raw string literal.
- `scripts/autoload/PlayerData.gd` + `CombatManager.gd` — added `add_abyssal_coins()` so abyssal
  coins go through an owning API like the other currencies.

### Changed (combat)
- `scripts/autoload/CombatManager.gd` — endless open-area spawning; active prayers now spend
  prayer points per player attack.

### Verified
- `--smoke`: all formula/data checks pass; 8 UI panels construct with no errors.
- `--selftest`: shop purchase → auto-eat tier 1; 20 woodcutting actions → 20 logs, 200 XP,
  27 mastery XP; prayer toggle registers a modifier (melee evasion 0 → 5); 3 combat kills in an
  endless area; save + load round trip succeeds.
- Fresh `--import`: 0 errors, 0 warnings.

## 2026-09-25 — Emberreach: identity, save safety, endgame content, balance tooling

The repository is now its own game. Everything Melvor-specific that reached the running screen is
gone; the systems underneath were hardened rather than rewritten.

### Identity
- Project/window/app name is **Emberreach** — rebuild a forgotten frontier settlement on an
  ash-choked frontier. Original names + flavour for **all 29 skills, 12 regions, 11 dungeons and
  29 enemies**, plus the visible equipment/resource spine (tiered gear, ores, bars, logs, fish,
  foods, potions). Item IDs are unchanged, so saves and icons are unaffected.

### Save safety
- `SAVE_VERSION` is now **2**, with an explicit migration chain.
- **Legacy adoption**: on first run the game copies a pre-rename save out of the old
  `app_userdata/Melvor Idle Clone/` directory (`LEGACY_APP_NAMES`) into `Emberreach`, and adopts
  the old `.backup` file too. It **copies, never moves** — the original is left alone. Verified
  against the author's real save: 29/29 skills preserved identically, gp, equipment and mastery
  intact; all skills, bank, equipment and achievement keys carried over.
- A **pre-migration backup** (`save_game.premigration_<unix>.json`) is written before any
  migration touches a save. Malformed saves are **quarantined, never silently replaced**.
- Atomic write + rotating backups, export/import, and a session lock remain.

### Simulation correctness
- Crafting consumes inputs atomically; running out of inputs stops the activity with a reason.
- `add_gp` rejects negative/non-finite values; potion charges are consumed explicitly.
- Offline progression is bounded and applied **exactly once** per save transition (the
  consumption flag is persisted immediately); it uses the same formulas as online play.
- Death never destroys a weapon or a protected item; `_find_food` is deterministic; bank
  notifications are batched instead of one per item.

### UI shell and accessibility
- New shell: compact sidebar + nav drawer, top status bar, workspace, contextual detail panel,
  persistent activity strip, toasts, confirm dialog, offline summary dialog.
- **11 screens**: Overview, Skills, Combat, Bank, Quests, Achievements, Collection, Settlement,
  Provisioner, Settings, Recovery (load/blocked states get their own screen).
- Responsive layout is real and tested: `apply_layout_for_width()` at 420 / 900 / 1440 px, with a
  test asserting **every** panel's combined minimum width fits a 420 px window and naming the
  offending control when it does not.

### Progression and endgame content
- **Mastery stall** (`ShopManager`): the only acquisition path for **58 skill capes + 2 completion
  capes**. `EquipmentManager` now enforces the cape `requires_level` gate.
- **24 god-tier Forgecraft recipes** and a **5-step shard refinement chain**, all consuming the
  Warden dungeons' signature shards — so every dungeon clear matters past the first.
- `Goals.sources_for_item()` and `ContentValidator` acquisition coverage extended to know about
  dungeon shards, mastery-stall offers, upgrade paths and the township trader.

### Balance tooling and the final content pass
- New `scripts/core/BalanceReport.gd`, run with `--balance`, writes `res://BALANCE_REPORT.md`:
  raw XP/h per skill (first vs last unlock), most-demanded materials, enemy curve, currency
  sources vs sinks, and materials nothing consumes. Content-only, no modifiers.
- The validator had a latent false negative: it counted *being an ingredient* as a way to obtain
  an item, which hid real orphans. That rule is gone, and the familiar-mark source it was missing
  is modelled. The clean report it then produced exposed genuine dead ends, all now closed:
  - **`summoning_shard_green` had no source at all** — it gates 25 summoning-tablet recipes and the
    first shard refinement, so the entire Beastbinding tree was unreachable. All 29 enemies now drop
    it (scaled by combat level; bosses pay more). Combat feeds tablet binding.
  - Unreachable crafting: **gems** (sapphire/emerald/ruby/diamond) now come out of the ore they are
    found in, **arrowtips** from drawing the matching bar, and the four **wyrmhides** from
    tier-appropriate beasts (the wyrm is the richest source of its own hide).
  - One real enemy-curve inversion fixed, and the boss-spike false positives in the curve check
    corrected.
- All content fixes are applied by idempotent scripts (`tools/content_fixups.py`,
  `tools/endgame_content.py`) and are safe to re-run.

### Real-window pass — five defects the headless suite could not see

Everything above was verified headless. Opening the real window found bugs that no amount of
headless testing would have: the shell was never laid out, and `_process` (which triggers the boot
screen) never runs in a CLI mode.

- **Cached screens were destroyed on navigation.** `_clear_workspace()` queue-freed the scroll that
  held the panel you were leaving, which freed the cached panel too and left `_panels` pointing at a
  dead node. This broke the Overview on *every* launch (`Can't add child ... already has a parent`).
  Cached panels are now detached first, and dead cache entries are dropped so the cache self-heals.
- **The bounded event log was freed on every rebuild.** `_clear()` frees every child of a box, and
  the Overview and Combat panels re-add a persistent `_log["root"]` widget they hold a reference to
  (`Trying to return a previously freed instance`). Added `Widgets.detach()` and used it at both sites.
- **The responsive breakpoints never fired.** With `window/stretch/mode="canvas_items"` the canvas
  stays pinned to the 1280px base and merely *scales*, so `size.x` was never below 1280 at any
  window size — the sidebar never collapsed to the nav drawer. The project already declared
  `min_width=420`, so scaling contradicted the stated design. Now `disabled` (1 canvas unit = 1 pixel).
- **Autowrapping labels collapsed to one character per line.** `UIStyle.label()` only set
  `EXPAND_FILL` above 48 characters, so any short label that a caller then made autowrap had a
  minimum width of ~1px and rendered vertically. Labels now always fill.
- **The assembled shell was 602px wide inside a 420px window** while every panel passed its own
  width check. The status bar (one long HBox) and the activity strip (a hard 200px minimum on its
  estimate label) set the floor. Both are now `HFlowContainer`s, the estimate label wraps, and the
  Overview suggestion/goal rows wrap too. Shell minimum is now **404px**.

New `--shot <dir>` mode renders the real window at 420 / 900 / 1440 px across the six busiest
screens and writes PNGs, so this pass is repeatable instead of a one-off. It is the one mode that
must not be run with `--headless`.

### Brief audit — scroll positions were claimed but never implemented

Reviewing the original brief section by section (§4, "Preserve scroll positions where sensible")
turned up a comment that lied: `_work_area()` tagged the workspace scroll with its screen name and
stated the position was preserved, but no code ever read the tag back. Leaving a long list and
returning sent you to the top.

Offsets are now captured per screen as you navigate away and restored a frame later, once the
rebuilt content has a height to clamp against. Covered by a new test.

Two other brief requirements were checked and found already satisfied rather than fixed: there are
no icon-only controls (every resource chip pairs its icon with a text value, and there are no
`TextureButton`s anywhere), and `state_refreshed` fires on discrete state changes rather than on
each simulation tick, so the full-panel refresh is not a per-event rerender.

### Favourites are a bookmark, not a lock

The brief lists "favourites" and "protection against accidental sale" as separate inventory features.
Only protection existed, and the bank panel described favourites *as* protection — the wrong model.
Conflating them means tapping "Favourite" on a high-value item would quietly turn it into a safety
setting the player never asked for.

- `PlayerData.favorite_items`, persisted under `player.favorite_items` and sanitised on load so a
  stale or hand-edited id cannot resurrect a row with no data behind it.
- `BankManager.set_favorite` / `is_favorite` / `toggle_favorite` / `favorite_count`.
- Favourites lead every sort order **including descending**: pinning an item exists to keep it
  findable when storage is long, so obeying the sort direction would defeat the point.
- A "☆ Favourites" filter toggle, a per-row Favourite/Unfavourite action, a Favourite badge, a
  "Favourite selection" bulk action, and a distinct empty state that explains the bookmark/lock
  difference instead of leaving the player to guess.
- Covered by 17 tests, including the one that matters most: **a favourited item is still sellable**,
  and selling it does not silently drop the favourite.

### Navigation and layout changes requested after the overhaul

- **Storage is now the first screen in the sidebar**, above the brand's usual Overview. The bank is
  where a player returns between everything else, so it no longer sits fourth.
- **The contextual detail pane is narrower** (`W_DETAIL` 320 -> 260). It was wide enough to compete
  with the workspace for attention, and the workspace is where the game is actually played.
- **Overview is now a hub with a sub-tab per skill.** A wrapping strip above the dashboard offers
  `Dashboard` plus one tab per skill, each labelled with its live level so the strip doubles as a
  progress readout. A skill tab shows a compact card — level, XP to next, activities
  unlocked, mastery pool, total mastery levels, the best activity you can currently run with its
  rate and output estimates and how long your stock lasts — then hands off to the full Skills screen
  via "Open full skill", with "Track level goal" alongside.

  The card is deliberately compact rather than a second copy of the skills panel: duplicating the
  full recipe UI would guarantee the two views drift apart. The tab strip is a **wrapping**
  `HFlowContainer` (`Widgets.tab_flow`) rather than the existing fixed `tab_strip` HBox, because
  thirty tabs in one row sum their minimum widths into the panel minimum and hand the player a
  horizontal scrollbar at every window size.

### General Store moved to its own screen

- **`Screens.STORE` is a screen of its own**, directly under the Provisioner in the sidebar. The
  store's 31 stock lines used to be the third section of the Provisioner, which is a catalogue of
  one-off upgrades: the two are read differently (browse once vs come back to), and one page could
  not hold both densities without the stock becoming a wall of scrolling.
- **New `GeneralStorePanel`** carries the stock, plus what the old section lacked: a **search
  field**, a state filter (`Everything` / `Affordable` / `Locked`), an affordability bar
  ("N of 31 lines affordable now"), the gold you are holding, a count of how many lines are still
  shut behind a skill, and a **Track** action per row that pins the item as a goal.
- **The default filter is `Everything`, not `Affordable`.** A fresh character has no gold, and
  defaulting to an affordable-only shelf would open onto an empty page for the one player who has
  never seen the catalogue. The filter narrows a shelf that is always shown in full first — which
  is also exactly how the store behaved before the split, so no line became harder to find.
- **The Provisioner keeps a signpost, not a copy.** A live "Open the General Store" link (with the
  current affordable count) sits where the shelves used to be, so a player who looks for the store
  where it was finds it with a reason to click. Duplicating the rows would reintroduce the density
  problem the split fixes.
- **The store is now a real source in the goal system.** `Goals.sources_for_item` lists it for any
  item it stocks ("General store · 25× Ghoststeel Bar", "3125 GP per bundle · 125 each"), gated by
  the same skill level the store uses and routing to the new screen. Before this it was invisible:
  "where do I get this?" never answered "gold".
- The panel listens to `gp_changed` and `skill_level_up` rather than `bank_changed` — the two facts
  that can actually change a row's state — so mining an ore no longer rebuilds 31 rows.

### Verified (this build)
- `--tests`: **307 passed, 0 failed** (including checks that load every screen into the real shell at
  420px, for scroll preservation, favourites, the Overview skill sub-tabs, and 17 for the store's
  own screen: catalogue order, each filter, search, the empty state, every blocked row stating its
  own reason, and that the Provisioner no longer renders the shelves).
  `--selftest`: **22 passed, 0 failed**
  (10-step trace: gather → craft → equip → 182 victories → quest 131.5K GP → settlement build →
  save/reload XP 540→540 → offline 1h 1244 actions). `--validate`: **0 errors, 0 warnings, 9 notes**.
  `--smoke`: all formula checks. `--assetreport`: **499 / 499 assets present**.
  `--balance`: 0 inversions, 0 enemy-curve warnings. `--shot`: **46 PNGs**, 0 script errors.

## Known limitations and deferred work
- **Prestige / ascension — deferred on purpose.** The first journey is not yet long enough for a
  reset to be interesting, and the brief forbids prestige without that justification.
- **Regions 13+** are not authored. The data model supports them; it is a content task.
- **Long-tail item display names** (the remaining ~250 items) are still Melvor-derived. IDs are
  stable, so this is a rename-only pass with no save or icon impact.
- **Favourites now exist** as a feature separate from protection, so §7 is complete. What remains
  open is the long-tail item display names and the §13 respecialisation mechanic.
- **No git repository exists** in this project, so none of this work is committed — it lives in the
  working tree. There is no history to bisect and no rollback beyond the save backups.
- **Visual review is automated but not continuous.** `--shot` captures the real window at each
  breakpoint, but nothing runs it automatically, so a future layout change can still regress
  between runs. A screenshot-diff gate in CI is the obvious next step.
- **Tier-5 god gear is a long endgame project by design** — each piece needs a Warden-dungeon shard
  plus refined tiers, so it is not reachable in a short session.
