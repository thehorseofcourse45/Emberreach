# Skill content audit — 30 September 2026

Scope: all **39 skills** (9 combat, 30 non-combat), **528 actions**, **574 items**, 41 monsters, 13 areas, 16 dungeons, 60 prayers, 14 special attacks, 27 enchants, 9 ranch species, 9 engineering devices, 9 dreamscapes.

Method: the shipped data was cross-referenced for reachability — every item an action consumes was checked against every producer (skill outputs, secondary outputs, monster loot, shops, grants, crops), and every item a skill produces was checked for a consumer. Findings below are evidence-backed; counts are from the current working tree.

Combat skills carry **13 actions** (all on `corruption`); the other eight level from fighting, so their content is measured in monsters, areas, dungeons and gear rather than actions.

**Status 2026-09-30:** **all twelve findings are closed, and the balance report's 126 "materials nothing consumes" entries have been triaged** (95 were already spent by channels the report could not read, 19 were genuinely dead and now have consumers, 12 are terminal by design and say so in the data — see the triage section at the end). The tree now holds **593 actions**, **629 items**, **38 companions**, **46 monsters**, **14 areas** and **17 dungeons**, `--validate` reports **0 errors and 0 warnings** (30 notes), `--balance` reads **0 undeclared / 12 declared terminal** and **0 supply warnings / 2 declared hubs** (see the concentration section at the end), and the test suite runs **2646 checks, 0 failed**. Each finding below carries its own outcome: `FIXED` where content or code changed, `RESOLVED` where the right answer was that the flagged thing was not a defect.

---

## Fix these first

### 1. Magic has no gear past level 30 — the whole style dead-ends — **FIXED 2026-09-30**

Only **four items in the game** set `magic_attack` / `magic_damage_percent`: `air_staff` (Magic 1), `water_staff` (10), `earth_staff` (20), `fire_staff` (30). For comparison, **16** items set `ranged_attack` and **36** set `melee_strength`.

So after level 30 a Magic user had no weapon upgrade, no magic armour, and nothing to work toward for the remaining **90 levels** of a 120-level skill. There was also no way for a staff to cast a stronger spell: damage is `spell * (1 + magic_damage%/100) * (1 + (level+1)/200)` and `CombatManager` hardcoded the spell at 10, so magic's ceiling was ~17 max hit while a bow reached ~280.

**Done:** 13 staves (one per rune, Magic 1→115), a `spell_max_hit` weapon stat read with a 10.0 default, and 16 robe pieces in four tiers — taking magic from a 14 max hit to 229. Recipes in Glyphcraft and Artifice, icons authored, covered by `_test_magic_gear`.

### 2. `attack_cost_items` is implemented but authored on zero items — **FIXED 2026-09-30**

[CombatManager.gd:504](scripts/autoload/CombatManager.gd#L504) consumes `attack_cost_items` from the equipped weapon at the start of **every** attack, and [CombatSimulator.gd:349](scripts/combat/CombatSimulator.gd#L349) models it. **No item in `items.json` defined the field.** Consequences:

- `bronze_arrow`, `iron_arrow`, `steel_arrow` were crafted by Bowyering and consumed by nothing.
- 7 of the 13 runes — `mind`, `chaos`, `nature`, `law`, `death`, `blood`, `umbral` — were crafted and consumed by nothing.
- The `ammo_preservation_percent` modifier on both Marksmanship skillcapes ([ModifierKeys.gd:54](scripts/resources/ModifierKeys.gd#L54)) could never do anything.
- Ranged and Magic attacks were free, so the combat styles had no supply loop at all.
- The `QUIVER` equipment slot ([ItemData.gd:8](scripts/resources/ItemData.gd#L8)) holds zero items.

**Done:** `attack_cost_items` is now authored on the eight bow tiers (bronze/iron/steel arrows by tier) and the four staves (their elemental rune); `CombatFormulas.ammo_cost()` applies ammo preservation and is shared by the live loop and the simulator; [ContentValidator.gd](scripts/core/ContentValidator.gd) rejects unknown ids and non-positive amounts; `_test_attack_costs` covers it. **Resolved:** the 7 spell-tier runes now have staves to spend them — see finding #1.

### 3. Runite is a dead tier, leaving a 45-level armour hole — **FIXED 2026-09-30**

`runite_ore` (Mining 85) → `runite_bar` (Smithing 85, also a dungeon reward) → **no consumer anywhere**. No `runite_sword`, `runite_platebody`, or any runite item exists. Meanwhile equipment that requires a `defence` level goes 1 / 10 / 20 / 30 / 50 and then jumps straight to **95** (the god sets) — a 45-level gap with nothing to wear.

`dragonite_bar` is used only as a god-armour ingredient, so it has no gear tier of its own either.

**Add:** a runite gear family (~Smithing 70–85) and a dragonite family (~90–95) in [skills.json](data/skills.json) + [items.json](data/items.json). This closes the armour hole, gives two dead bars a purpose, and balances the smithing table.

**Done:** twenty-two items in two families — **Stormsteel** (runite) at Attack/Defence 70 and **Wyrmforged** (dragonite) at 85, each with sword, scimitar, dagger, battleaxe, two-hander, helmet, platebody, platelegs, boots, gloves and shield — plus twenty-two Smithing recipes (85 and 95) and icons. Both bars feed eleven recipes each, and the Defence ladder now reads 1 / 10 / 20 / 30 / 50 / 70 / 85 / 95, so no gap is wider than the pre-existing 30 → 50 stretch. Covered by `_test_gear_ladder_gap` and a rewritten `_test_melee_tier_ladder` that measures crafted weapons only, on `melee_strength`.

### 4. No monster between combat level 86 and 104 — **FIXED 2026-09-30**

Monster population by combat level, after the fix:

| Band | Count | Monsters |
|---|---:|---|
| 0–9 | 5 | chicken, cow, golbin, zombie_hand, cinderkin_scout |
| 10–19 | 3 | skeleton, spider, golbin_chief |
| 20–29 | 2 | bandit, drowned_wayfarer |
| 30–39 | 3 | broodweb_hunter, barrow_wraith, rook_marksman |
| 40–49 | 2 | moss_giant, greyharrow_husk |
| 50–59 | 3 | shale_stalker, quarry_echo, slag_golem |
| 60–69 | **2** | guard (60), **brine_troll (66)** |
| 70–79 | **2** | frostfang_wolf (70), **tidewrack_hag (76)** |
| 80–89 | 3 | mist_wraith (85), rune_knight (85), **sunderhold_centurion (88)** |
| 90–99 | **1** | **ashwyrm_seer (96)** |
| 100–109 | **2** | **sunderhold_ballistarius (102)**, green_dragon (105) |
| 110–119 | 2 | air_elemental (110), ash_drake (115) |
| 120+ | 16 | water_elemental (120) through the_herald (300) |

Skills `attack`, `strength`, `defence`, `ranged` and `magic` all stop earning meaningful content for ~20 levels around 88–104, and 60–79 is served by one monster per band. `castle_of_kings` (12–101) and `dragon_valley` (79–120) are the only home for that stretch.

**Add:** 3–5 monsters at combat levels ~62, ~74, ~88, ~96, ~102 with matching areas or an extension of `icy_hills` / `castle_of_kings`.

**Done:** five monsters — Brine Troll (66, melee), Tidewrack Hag (76, magic), Sunderhold Centurion (88, melee), Ashwyrm Seer (96, magic) and Sunderhold Ballistarius (102, ranged). The first two live in the new **Saltmarch Basin** (58–88, the fourteenth region, behind a "Slick brine: −10% evasion" hazard); the other three extend `castle_of_kings` (now 12–104) and `dragon_valley`. Every band from 1 to 120 now holds at least one monster and the worst combat-level gap is twelve levels, pinned by `_test_monster_ladder`. Each arrival carries a special attack, which brings three previously orphaned attacks (`life_leach`, `ocean_song`, `cloudburst_magic_ray`) into play — all fourteen are now reachable. The new health values were sized into the existing curve rather than above it, so `--balance` reports no new dip.

### 5. No dungeon between level 70 and 110 — **FIXED 2026-09-30**

| Dungeon | Level range |
|---|---|
| chicken_coop | 1–10 |
| cinderkin_forge | 4–18 |
| undead_graveyard | 10–45 |
| drowned_causeway | 20–35 |
| rook_viaduct | 23–60 |
| spider_forest | 25–65 |
| frostfang_den | 42–70 |
| greyharrow_deep | 43–60 |
| **sunderhold_undercroft** | **71–105** |
| air_god_dungeon | 110–160 |
| … four god dungeons, into_the_mist, impending_darkness, underwater_city, throne_of_the_herald | 110–310 |

A dungeon's first-clear reward is the only guaranteed unique payout at a tier, and the mid-game had no expedition to run at all across this stretch.

(**Correction, 2026-09-30:** the original draft also blamed this gap for Enchanting progression, on the grounds that dungeons supply `enchant_catalyst`. They do not — every catalyst in the game comes from monster loot — so that part of the finding was wrong.)

**Add:** one mid-game dungeon at roughly 75–105 (2–3 encounters, first-clear reward).

**Done:** `sunderhold_undercroft` — "Sunderhold Undercroft", 71–105, three escalating encounters (`rune_knight`, `sunderhold_centurion`, `sunderhold_ballistarius`), 120,000 GP plus binding shards on every clear, and two `dragonite_bar` on the first. It opens on Slayer 50, starts exactly where Frostfang Den stops (70) and runs to within five levels of the Observatory of Gales (110). An icon was authored and imported. `_test_dungeon_ladder` walks the ladder in order, measuring the hole between each dungeon and the highest one already open: it reports a worst gap of twenty levels, where the same walk measured forty before this.

### 6. Two fish are caught but can never be cooked — **FIXED 2026-09-30**

`raw_crab` (Fishing 60) and `raw_cave_fish` (Fishing 75) have **no Cookery recipe** — and Cookery's +20/+15 level holes sit at exactly 50→70 and 70→85. (`raw_squid` is fine: Inscription's `squid_ink` consumes it.)

**Add:** `cook_crab` (60) and `cook_cave_fish` (75) plus the cooked item entries. This fills the unlock gaps and the two dead fish at once.

**Done:** `cook_crab` (60) turns `raw_crab` into `crab` ("Mudcrab", heals 175, sells 30) and `cook_cave_fish` (75) turns `raw_cave_fish` into `cave_fish` ("Cavern Char", heals 215, sells 50) — both slotted between their neighbours on the heal ladder, at 233 and 357 XP against Bladefin's 177 and Gale Shark's 289. Icons authored, and the balance report's dead-material list dropped from 128 to 126 with both fish off it. `_test_raw_fish_are_consumed` now asserts that **every** raw fish Fishing lands has a consumer, so a new Fishing action cannot reintroduce the same dead end.

### 7. `enchanting.study_4` is a regression at level 90 — **FIXED 2026-09-30**

The six Attunement studies are identical in inputs, interval and output, and the XP ramp is not monotonic:

| Action | Level | Before | Now |
|---|---:|---:|---:|
| study_1 | 1 | 96 | 96 |
| study_2 | 30 | 189 | 189 |
| study_3 | 60 | 189 | **230** |
| **study_4** | **90** | **180** | **270** |
| study_5 | 105 | 300 | **320** |
| study_6 | 115 | 465 | 465 |

Level 60 and level 90 pay the same, and level 90 pays **less** than level 60 — a player is strictly better off staying on the older action. **Fix:** smooth the ramp (e.g. 96 / 189 / 230 / 270 / 320 / 465).

**Done:** the ramp is now exactly the shape this finding proposed — 96 / 189 / 230 / 270 / 320 / 465, rising at every step, with only `study_3`, `study_4` and `study_5` moved. `_test_study_ramp_rises` compares each study with the one below it, so the inversion cannot come back.

---

## Worth doing next

### 8. Slayer tier pools collapse in the middle — **FIXED 2026-09-30**

| Tier | Level | Before | Now |
|---|---:|---|---|
| easy / normal / hard | 1 / 20 / 40 | 3 / 4 / 5 | unchanged |
| elite | 60 | 3 | **5** |
| master | 80 | **rune_knight only** | **2** (rune_knight, sunderhold_centurion) |
| legendary | 95 | **green_dragon only** | **3** (green_dragon, ashwyrm_seer, sunderhold_ballistarius) |
| mythical / abyssal / godslayer / herald | 110 / 114 / 117 / 120 | 3 / 3 / 4 / 7 | unchanged |

Master and Legendary each offer a single assignment. The fix in #4 (new 85–105 monsters) should also feed these pools in [slayer_tasks.json](data/slayer_tasks.json).

**Done:** elite went 3 → 5 (adding brine_troll and tidewrack_hag), master 1 → 2 (adding sunderhold_centurion) and legendary 1 → 3 (adding ashwyrm_seer and sunderhold_ballistarius), so no tier is a single assignment any more. `ContentValidator` gained a `thin_slayer_pool` warning for anything under two, and `_test_monster_ladder` asserts every pool holds at least two members and that each member has an encounter.

### 9. `alt_magic` is the thinnest real skill (9 actions, one 25-level hole) — **FIXED 2026-09-30**

Unlock ladder: 1, 10, 20, 30, **55**, 75, 85, 100, 110. Two concrete omissions:

- Superheat covers `mithril` (55) then jumps to `umbral` (75) — no adamantite or runite step, even though both ores exist (Mining 70 / 85).
- Enchanted gems go `sapphire` (30) → `diamond` (85), skipping emerald, ruby and dragonstone.

Both map onto existing items, so this is pure data authoring.

**Done:** four actions, taking the skill from 9 to 13. `superheat_adamantite` (65) and `superheat_runite` (70) fill the ore ladder between mithril and umbral, at 48 and 54 XP on 3 and 4 fire runes. `enchanted_emerald` (42) and `enchanted_ruby` (60) close the 30 → 55 hole and turn the gem line into sapphire → emerald → ruby → diamond, at 33 and 51 XP on a nature rune and a fire rune. Every new step produces an item that already existed, so no icons or economy were needed. The ladder's largest gap falls from twenty-five levels to fifteen. **Correction:** dragonstone is not a gem in this game — there is no such item — so the third omission in this finding did not exist.

### 10. Higher-level actions that pay less than lower-level ones — **RESOLVED 2026-09-30**

Beyond `study_4`, these pairs are in the same product family and invert. Each is a one-line tuning decision:

| Skill | Higher level | XP | Lower level | XP |
|---|---|---:|---|---:|
| lostfinding | inspect_cargo_records (25) | 78 | recover_object (20) | 155 |
| echo_keeping | listen_dock (15) | 34 | replay_rack (10) | 69 |
| customcraft | pair_custom (50) | 231 | establish_custom (40) | 262 |
| lostfinding | echo_lens (65) | 259 | return_heirloom (55) | 298 |
| herblore | potion_dr_3 (41) | 27 | brew_dreamwalking (35) | 30 |
| crafting | craft_green_dhide_body (40) | 23 | craft_ruby_ring (34) | 27 |
| crafting | craft_blue_dhide_body (50) | 31 | craft_diamond_ring (43) | 39 |

Some of these are intentional (a bar pays less than a finished weapon; `pure_essence` is deliberately slow). The four new-system skills are the least likely to be deliberate.

**Resolution:** the table above is a heuristic, and every row of it is a false positive. Each pair trades *different inputs*, so the two actions are not the same job and paying differently for them is design, not drift:

| Pair | Why it is not the same work |
|---|---|
| `inspect_cargo_records` vs `recover_object` | One eats a free `case_file`, the other a `witness_timeline` that cost two of them |
| `listen_dock` vs `replay_rack` | The listener has no inputs at all; the rack eats two items and yields three charges |
| `pair_custom` vs `establish_custom` | Different inputs, and `establish_custom` produces the ingredient `pair_custom` consumes |
| `echo_lens` vs `return_heirloom` | Different inputs and different outputs |
| `potion_dr_3` vs `brew_dreamwalking` | Three herbs against two herbs plus two essence |
| both `craft_*_dhide_body` vs `craft_*_ring` | Dragonhide against a bar and a gem |

The real rule — *the same inputs and interval must not pay less at a higher level* — was then applied across all 39 skills. It found **three genuine regressions, none of them on this list**, all in Inscription: `scribe_time` (75) paid 188 and `scribe_sage` (90) paid 186 against the level-40 recipe's 189, and `bind_tome_sage` (90) paid 297 against the level-40's 302. They now pay 200, 215 and 310. `_test_action_xp_ladders` enforces the rule, so a repeat fails the suite.

### 11. `--validate` currently reports 47 `no_acquisition_path` warnings — **FIXED 2026-09-30**

A fresh `--validate` run writes **0 errors, 47 warnings, 29 notes** into the gitignored [VALIDATION_REPORT.md](VALIDATION_REPORT.md). The 47 are all one rule: an item exists but the validator cannot see how to obtain it. The categories are:

| Items | Real source (not modelled by the validator) |
|---|---|
| `ranch_egg`, `ranch_milk`, `ranch_wool`, `ranch_tusk`, `ranch_antler`, `ranch_plume`, `ranch_scale`, `ranch_ember`, `ranch_star_scale`, `ranch_feed`, `ranch_manure`, `ranch_meat` | Ranching collection, driven by the `species` records in [new_skill_systems.json](data/new_skill_systems.json) |
| `golden_hen_stock`, `mooncalf_stock` | Ranching breeding variants |
| 24 `scribe_*_faded` / `_illuminated` and `equipped_tome_*` variants | Quality rolls in [InscriptionManager.gd](scripts/autoload/InscriptionManager.gd) |
| `enchant_martial_essence`, `enchant_warding_essence`, `enchant_verdant_essence` | Disenchant yields in [EnchantingManager.gd:91](scripts/autoload/EnchantingManager.gd#L91) |

These are **validator blind spots, not missing content** — every one of them is granted by a manager rather than by an action's `output_items`. The fix is to teach [ContentValidator.gd](scripts/core/ContentValidator.gd) the three manager-owned acquisition paths so the warning list returns to zero and stays meaningful; right now 47 permanent warnings make it easy to miss a genuinely unreachable item. (The `0 warnings` figure in the older note on file predates the five new systems and does not reflect the current tree.)

**Done:** `--validate` now reports **0 errors, 0 warnings, 28 notes**. All three paths are modelled in [ContentValidator.gd](scripts/core/ContentValidator.gd): Ranching from the `species` table (stock, produce, hide, meat, plus feed, manure and the two breeding variants), Inscription from every action carrying a `quality_product` (inked, faded and illuminated forms), and Enchanting from the `essence` field on each enchant definition (disenchant yields). A fourth bug fell out of the work: **every one of the forty provisioner shelves was invisible**, because each store record names its item under `item_id` while the check read only `grants_items`. The warning is now a real signal — the one genuinely unreachable item would be the only thing in the list.

### 12. Consistency gaps (low priority, no gameplay impact) — **RESOLVED 2026-09-30**

- `mastery_unlocks` is present on 30 skills; the 9 combat skills and `township` lack it.
- `pool_checkpoints` exists only on the five newest skills (ranching, engineering, enchanting, dreamwalking, customcraft) — the other 34 skills have mastery pools with no checkpoint rewards or "next checkpoint" hint in [MasteryManager.gd:216](scripts/autoload/MasteryManager.gd#L216).
- `success_chance` is authored on 28 of 30 non-combat skills but absent on `smithing` (all 90 actions) and `crafting`/`summoning`/`inscription`/`herblore`. The default of 1.0 makes this harmless today, but the failure path (inputs are still consumed, [SkillManager.gd:334](scripts/autoload/SkillManager.gd#L334)) is untested for those skills.

**Resolution:** checked rather than changed, and one real defect found along the way.

- **Combat skills are correct to have no `mastery_unlocks`.** Mastery XP is granted by [SkillManager.gd](scripts/autoload/SkillManager.gd) and the four system managers; nothing in combat ever calls `MasteryManager.add_mastery_xp`, so the eight action-less combat skills and `township` accumulate no mastery and a table for them would be dead data that *looks* like content. (`corruption`, the one combat skill with actions, has the table and is the exception the finding missed.) `_test_mastery_metadata` now asserts the real invariant instead: every skill **with actions** declares mastery unlocks.
- **Pool checkpoints on 34 skills is a scope boundary, not a defect.** `_evaluate_checkpoints` and `next_checkpoint` read the table with a `{}` default, so a skill without one simply has no checkpoint rewards and no hint — that is a deliberate difference between the five newest systems and the rest, and adding them means authoring 136 permanent modifier grants, which is a balance project rather than a consistency fix. The test pins the shape instead: checkpoints may sit only on the four documented marks (10 / 25 / 50 / 95) and may never be empty.
- **The `success_chance` gap is harmless and now proven so.** All 72 authored values sit in (0, 1]; the 509 actions without one run at the guaranteed default, so Smithing and Crafting cannot burn materials. `_test_mastery_metadata` asserts both halves.
- **The defect the finding implied:** fourteen modifier keys were read by name across the new systems (`ranching_feed_reduction_percent`, `thieving_stealth`, `inscription_quality_percent`, and eleven more) but were absent from [ModifierKeys.gd](scripts/resources/ModifierKeys.gd) — the registry whose stated purpose is "no module typos a key". They are registered now, and the test checks every authored key against the registry, so a typo in any mastery or checkpoint table fails the suite.

---

## Dead ends — the 126-item triage (2026-09-30)

The balance report's `materials nothing consumes` line printed **126 items**. The rule behind it was
sound but short-sighted: it counted a recipe input, an upgrade material and a trader cost as demand and
read nothing else, so it could not see ammunition, familiars, ranching, farming, engineering,
inscription, enchanting, prayer, archaeology or the crates. The triage in full:

| Bucket | Count | What it was |
| --- | --- | --- |
| Already spent, channel not modelled | **95** | 27 familiar tablets, 33 inked/faded/illuminated scribe texts, 11 ranch stock, 9 engineering devices, 4 enchant essences + catalyst, 4 museum artefacts, 3 arrows, 2 bones, 2 farm inputs (compost, manure) |
| Genuinely dead, now consumed | **19** | 11 materials + 6 containers/egg + 2 familiar marks |
| Terminal on purpose, now declared | **12** | `ash`, `artefact_shard`, `burnt_food` + the nine sell-for-GP outputs of the newer skills |

**The nineteen** were closed with additive content only, so no existing recipe, price, drop or XP value
moved. Twelve new actions (Cookery 15/35, Fletching 60, Crafting 18/85/110, Herblore 45/90/100/110/115,
alt_magic 25) and six new items (`topaz_ring`, `ranch_omelette`, `ranch_cheese`, `potion_hushroot`,
`potion_herald_bloom`, `potion_emberbloom`) give demand to `ranch_egg`, `ranch_milk`, `ranch_antler`,
`ranch_scale`, `ranch_ember`, `ranch_star_scale`, `harvested_essence`, `topaz`, `duskroot`,
`herald_bloom` and `emberbloom`. The five settlement crates and `raid_pet_egg` gained
`container_items` / `container_pet` and are opened from Storage, and `craft_border_collie` /
`craft_sandman` gained the mark their familiar awards as an input, like the other 25 tablets.

The nine sell-for-GP outputs are deliberately terminal: those skills' product *is* gold, so inventing a
reagent consumer for them would invent a use the skill was not designed around. `ash`, `artefact_shard`
and `burnt_food` are byproducts of a process, not materials. Each carries `terminal_reason`, which
`--balance` prints beside the id so "dead on purpose" and "forgotten" cannot look alike.

**The guard is two-sided.** `ContentValidator._check_output_demand()` warns `dead_output` for any
obtainable item with no consumer, warns `stale_declaration` when a later recipe makes a declaration
false, and errors `dead_channel` when one of the fifteen demand channels stops matching content — the
failure where a renamed field would silently excuse every item it used to catch. The `outputs are
consumed` suite (55 checks) asserts the same against the live data, plus the shape of the crates and a
real open/hatch round-trip; `_test_balance_report_builds` (5 checks) builds the report itself, because
nothing had ever run it and a shape mismatch had silently killed the whole `--balance` output.

**Proof:** `--balance` reads **0 undeclared, 12 declared terminal**, `--validate` is **0 errors,
0 warnings** (the `coverage` note counts the declarations), and `--tests` is **2646 checks, 0 failed**.

---

## Supply concentration — measured, then declared (2026-09-30)

The report's other warning class is supply, not demand: "X is needed by 26 recipes from a single
route". It had two faults and no way to record a decision.

- **It counted kinds of route, not sources.** All crafting was one route and every enemy that dropped
a material was the same route, so `rune_essence` (three recipes across two skills) and
`enchant_catalyst` (dropped by twenty enemies) were each reported as a single point of failure. A
route is now a source: one per producing recipe, one per shop, one per enemy, one per system that
hands items over (farming, ranching, inscription, enchanting).
- **It only looked at the top eight materials by demand**, so a hub ranked ninth was never warned
about — which is where both false alarms and a phantom material were hiding.
- **It invented a material.** The settlement trader's `cost` is paid from the township store in
settlement resources, but the demand model read it as items, so `goods` appeared as a material that six
recipes need and nothing supplies. A cost now counts only when it names a real item, the `trader`
channel is gone, and `phantom_demand` is an error if any channel ever names a non-item again.

With the measurement fixed, two materials are genuine single-source hubs, and both are deliberate, so
the data says so with `bottleneck_reason` — the same pattern as `terminal_reason`:

| Material | Demand | Only source | Why it stays one source |
| --- | --- | --- | --- |
| `scribe_blue_ink` | 19 recipes | Inscription 25 | the azure press; crude ink below it already has two sources |
| `ranch_wool` | 17 recipes | the sheep pen | the sixteen robe recipes are Ranching's intended demand |

`--balance` prints each reason beside the item, and `--validate` warns `bottleneck_undeclared` for a
hub without one and `stale_bottleneck_declaration` when a declaration is outgrown — a second source,
or demand below the line — so deleting a reason puts the warning back.

**The mechanism caught its own first mistake.** `scribe_paper` was the first item declared, and the
declaration was wrong: the Dream Bazaar sells fifty sheets for forty dream essence. That only became
visible when the report's source model was completed, because nine acquisition paths handed items over
and none of them was counted as a source: the bazaar, quests, achievements, dig sites, raid rewards,
the museum's curios, the mastery stall, familiar marks and failure outputs. The moment the bazaar was
modelled, `--validate` reported `stale_bottleneck_declaration` and the declaration went. Two further
holes on the validator's side fell out of the same pass: the provisioner's forty shelves live in
`shop_store.json` while the coverage check read `DataLoader.shop` (the GP upgrade catalogue), so the
shelves were invisible even after the `item_id` form was taught to it, and the museum's curios and the
bazaar's grants were not sources at all. Both are fixed, and the `bottleneck declarations` suite (19
checks) pins one representative item per acquisition path — a shelf, a stall cape, a curio, a dig site,
a familiar mark, a failed cook, dream essence, a bazaar bundle — so a path cannot quietly go invisible
again, alongside the two false alarms staying fixed at 3 and 20 sources.

**Proof:** `--validate` is **0 errors, 0 warnings, 30 notes** and `--balance` is **0 warnings,
2 declared hubs**.

---

## Suggested order

1. ~~`attack_cost_items` on staves and bows + validator rule (#2)~~ — done 2026-09-30 (arrows and the four elemental runes; the 7 spell-tier runes wait on #1).
2. ~~Runite/dragonite gear tiers (#3)~~ — done 2026-09-30 (Stormsteel at 70, Wyrmforged at 85; the Defence ladder is 1/10/20/30/50/70/85/95).
3. ~~Magic gear line (#1)~~ — done 2026-09-30 (13 staves, 16 robe pieces, `spell_max_hit`).
4. ~~Monsters at 62/74/88/96/102 + slayer pools (#4, #8)~~ — done 2026-09-30 (five monsters, Saltmarch Basin, elite/master/legendary pools deepened, three orphaned attacks wired up).
5. ~~Mid-game dungeon 75–105 (#5)~~ — done 2026-09-30 (`sunderhold_undercroft`, 71–105, three encounters, `dragonite_bar` on the first clear).
6. ~~Cook crab and cave fish (#6) and the `study_4` XP fix (#7)~~ — done 2026-09-30 (Mudcrab at 60, Cavern Char at 75, and the study ramp re-cut to 96/189/230/270/320/465).
7. ~~alt_magic superheat/enchant steps (#9)~~ — done 2026-09-30 (adamantite 65, runite 70, emerald 42, ruby 60; 9 actions → 13, worst gap 25 → 15 levels).
8. ~~Teach the validator the three manager-owned acquisition paths so `--validate` is clean again (#11)~~ — done 2026-09-30 (47 warnings → 0; also fixed the provisioner shelves, which `item_id` had hidden from the check entirely).
