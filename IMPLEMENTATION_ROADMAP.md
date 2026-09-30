# Implementation Roadmap — from empty repo to playable game

> Priority (from the brief): *"Start with the core architecture and the most fundamental
> systems (XP/levels, modifier manager, skill action framework, save system), then build
> outward. Prioritize a playable vertical slice with Woodcutting, Fishing, Cooking, basic
> Combat, and the Bank before expanding to all 29 skills."*

Each phase is shippable and has an explicit **acceptance test**. Phases 0–9 (including the
playable UI, all 34 skills and the endgame) are implemented in this repository.

---

## Phase 0 — Foundations ✅
Project boots, loads content, persists. `project.godot` + 17 autoloads; `XPTable`, `EventBus`,
`DataLoader`, `SaveManager`.
**Acceptance:** `-- --smoke` prints `XP lvl 99: 13034431` / `120: 104273167`; save→quit→relaunch restores.

## Phase 1 — The modifier hub ✅
`ModifierManager` + `ModifierSource` + `ModifierKeys`. Additive per category; multiplicative keys;
DR = 1 − Π(1 − dᵢ/100).
**Acceptance:** two sources 5+10 → 15; DR 10/15/20 → 38.8.

## Phase 2 — Skill action framework ✅
`SkillManager` + `SkillActionData`. `final_interval = base·(1 − red%/100) − flat`, floor 0.25 s.
Success/preservation/doubling/secondary drops; XP + mastery; auto-repeat.
**Acceptance:** Woodcutting logs accumulate; +50 % interval modifier ~halves the bar time.

## Phase 3 — Vertical slice: WC / Fishing / Cooking + Bank ✅
Complete skill data; `BankManager` (stacking/search/sort/sell/bury/slot curve).

## Phase 3.5 — Playable UI ✅  *(this increment)*
`MainUI` shell + `TopBar`, `SkillList`, `SkillPanel`, `CombatPanel`, `BankPanel`, `ShopPanel`,
`RightPanel`, `WelcomeBackModal`, `UIStyle`; `ShopManager` + `PrayerManager`.
**Acceptance:** `-- --selftest` → buys Auto Eat I, trains 20 woodcutting actions (20 logs/200 XP),
toggles a prayer (evasion 0→5), wins 3 fights in an endless area, saves and reloads.

## Phase 4 — Combat engine ✅ core / ⬜ polish
`CombatFormulas` (all §3.2 formulas), `CombatManager` (timers, damage, loot, respawn, auto-eat,
death, endless areas, dungeons, **weapon & monster special attacks with status application**),
`StatusEffect`.
**Acceptance:** HP XP = 0.133/dmg, style XP = 0.4/dmg; death empties a slot; Auto Eat I at 20 %.
**TODO:** per-monster passive abilities. (Done since: area hazards apply in both combat engines;
god-dungeon shard drops are paid on every kill.)

## Phase 5 — Mastery ✅ core / ✅ item unlocks
`MasteryManager`: MXP formula, 25 %/50 % pool split, 500 k×items cap, checkpoints, tokens, 1:1 spend,
and **per-item unlock thresholds (1/10/25/50/95/99) applied through ModifierManager**.
**Acceptance:** training an action past threshold 1 registers its `mastery_item:<skill>` source.

## Phase 5.5 — Potions ✅
`PotionManager`: `potion` modifier category, charge-based consumption per action/attack,
auto-clear, load re-apply; BankPanel **Use** button.

## Phase 5.6 — Dungeon rewards ✅
`CombatManager._grant_reward()` pays the dungeon's `completion_reward` (and `rewards_first_clear`).

## Phase 6 — Equipment ✅
`EquipmentManager` (14 slots, two-handed rule, sets, stat aggregation) + `ItemData` chains.

## Phase 7 — Offline progression ✅ core / ⬜ UI polish
`OfflineProgression` (≤24 h, same paths, seeded RNG, opt-in), `FarmingManager`, `TownshipManager`,
`WelcomeBackModal`.
**Acceptance:** a simulated 1-hour gap matches an equivalent online run within RNG tolerance.

## Phase 8 — Content breadth ✅ complete
Every skill now has content and a working system.
**8.1 Mining → Smithing ✅** — ores with node HP + respawn, smelts, 44 smith actions
(bronze/iron/steel/mithril × 11 pieces).
**8.2 Artisan block ✅** — Firemaking, Fletching, Crafting, Runecrafting, Herblore, Farming herbs.
**8.3 Support/exploration block ✅** — Prayer (25 prayers), Slayer (tasks + shop), Agility (15 slots),
Summoning (marks/tablets/synergies), Astrology (15 constellations), Thieving (16 NPCs, stealth/stun),
Alt. Magic, Township (buildings/worship/trader), Cartography (25 hexes + POIs), Archaeology (4 sites +
museum), Harvesting (3 veins), Pets (32) and the Skillcape/Completion set.

## Phase 9 — Endgame ✅
- **God Dungeons ✅** — Air/Water/Earth/Fire with god minions + bosses, a **shard drop on every kill**
  (`shard_item` on the dungeon), completion rewards and first-clear god-armour drops; God Upgrades
  gate on dungeon completion.
- **Endgame chain ✅** — Into the Mist → Impending Darkness → Underwater City → Throne of the Herald.
- **Golbin Raid ✅** — `RaidManager`: waves of golbins (size `floor(2 + wave/4)`), a 3-choice
  upgrade/ALT-item pick after each wave, Raid Coins `mult · 3.6 · wave · size · floor(1 + wave/15)`,
  Raid Shop, 2× attack speed and forced Auto Eat Tier II inside the raid.
- **Abyssal / Corruption ✅** — abyssal areas + monsters, Abyssal Whip/Essence, Corruption skill
  actions and an Abyssal Corruption status.

Remaining polish (data + UI, no new engine work): Township tasks/education, Cartography ship
upgrades, Archaeology museum shop, Summoning tablet quantity scaling, and per-dungeon UI flows.

## Addendum — 2026-09-27: audio, mid-level content, thin-skill depth, visual gate

- **Audio ✅** — `data/audio.json` + `AudioManager` (synthesised SFX/music, Music/SFX buses,
  Settings volume controls, validator + test coverage). The largest system still untouched.
- **Mid-level content ✅** — Greyharrow Quarry (area) + Greyharrow Deep (dungeon) + 4 monsters
  fill the L43–L59 hole, the widest gap on the level curve; slayer pools refilled, art supplied.
- **Thin-skill depth ✅** — Excavation 7→11, Surveying 6→9, Wayfaring 7→10, Blight 8→13;
  Umbral Essence now feeds the summoning shard chain instead of dead-ending.
- **Screenshot gate ✅** — `tools/shot_gate.py` diffs the real-window `--shot` sweep against
  `tools/shot_baseline/` and exits 1 on visual regressions (needs a display; `--update`
  re-baselines after an intentional UI change).
- Also: the enrage passive was being applied to every monster in both combat engines — fixed.

---

## Engineering guardrails (apply to every phase)
1. **No hardcoded content.** If it can be data, it is data.
2. **All stat math via ModifierManager.** Never add a bonus inline.
3. **Offline parity.** Any new loop must be replayable by `OfflineProgression`, same functions + seed.
4. **64-bit numbers.** GP/XP get large; keep `int`/`float`.
5. **Autosave** every 60 s and after any major event.
6. **Keep the truth source green.** Extend `_run_smoke_checks()` / `_run_self_test()` with every
   new formula and system so `-- --smoke` / `-- --selftest` stay fast regression checks.
