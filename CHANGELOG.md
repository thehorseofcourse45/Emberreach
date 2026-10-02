# CHANGELOG

## 2026-09-30 — ammunition, magic gear, the missing metal tiers, mid-game content, dead ends and a clean validator

### Fixed
- **`attack_cost_items` was implemented but authored on nothing.** `CombatManager._player_attack()`
  and the combat simulator both consume a weapon's `attack_cost_items` per swing, but no item ever
  declared one — so the three arrows were craftable and then consumed by nothing, the
  `ammo_preservation_percent` modifier on both Marksmanship skillcapes was inert, and Ranged and
  Magic attacks cost nothing at all.
- **Ammunition preservation now applies to the spend.** `CombatFormulas.ammo_cost()` rolls each unit
  of the cost independently against the modifier, so the Marksmanship skillcape refunds half the
  shots and the superior cape makes them free. Put in `CombatFormulas` so the live tick loop and the
  deterministic simulator charge the same amount for the same attack — the simulator previously
  deducted the raw cost while nothing gated on preservation.

### Added
- `attack_cost_items` on the eight bow tiers (bronze/iron/steel arrows by tier) and the four staves
  (their elemental rune), wiring the Fletching and Runecrafting supply chains into combat.
- `ContentValidator` now rejects an unknown item id or a non-positive amount inside
  `attack_cost_items`, matching how it already validates `upgrade_materials`.
- `_test_attack_costs` (34 checks): preservation maths at 0/50/100%, every ranged and magic weapon
  declaring a cost, and no craftable ammunition without a weapon that spends it.

### Added (the magic gear line)
- **Nine new staves**, one per remaining rune, at Magic 35/45/55/65/75/85/95/105/115 (Whisper,
  Astral, Rift, Thornwake, Judgment, Gravebind, Bloodtithe, Soulharvest, Umbral). With the original
  four, that is thirteen staves for thirteen runes, so every rune a player binds is now spent by a
  caster. Each is crafted in Glyphcraft from ten of its rune plus one log, stepping through every
  woodcutting tier from willow to voidwood.
- **A `spell_max_hit` weapon stat.** Magic damage is `spell * (1 + magic_damage%/100) *
  (1 + (level+1)/200)`, and `CombatManager` had no way to read the spell, so every staff in the game
  cast the same fixed base-10 spell — which is why the style could not progress past its first tier.
  The stat is read from the equipped weapon with a 10.0 default, so a weapon that declares nothing
  keeps its existing damage. The full ladder now runs from a 14 max hit at Magic 1 to 229 at Magic
  115, deliberately under the best bow's 280 because a staff pays runes rather than arrows and needs
  no offhand.
- **Sixteen robe pieces**: Apprentice, Adept, Archmage and Herald sets of hat, robe, legs and
  gloves, at Magic 30/60/90/115, made in Artifice from wool, glyph essence and gems. Offensive stats
  live only on weapons in this game, so robes follow the wyrmhide shape and carry magic_defence
  primarily with melee/ranged_defence behind it — the first magic armour the game has had.
- Icons for all 25 new items, recoloured from existing silhouettes into per-tier tints, imported and
  added to the asset manifest (985 of 986 assets on disk).
- `_test_magic_gear` (51 checks): a rising spell tier per tier, one rune per staff, a rising max hit
  across the ladder, all thirteen runes cast by a staff, robe tiers with four pieces each and rising
  ward, the staff line measured against the bow line, and a recipe for every new piece.

### Added (Stormsteel and Wyrmforged)
- **Twenty-two items in two metal tiers**, closing the armour hole the skill audit flagged:
  `runite_ore` (Mining 85) and `dragonite_bar` had no equipment consumer at all, and gear that gates
  on a Defence level ran 1 / 10 / 20 / 30 / 50 and then jumped straight to the god sets at 95 — a
  45-level stretch in which nothing could be worn. Each family carries sword, scimitar, dagger,
  battleaxe, two-hander, helmet, platebody, platelegs, boots, gloves and shield.
- **Stormsteel** (the runite family) at Attack/Defence 70, melee strength 48–58, and **Wyrmforged**
  (dragonite) at Attack/Defence 85, melee strength 56–66. Both sit under the godsword's 80 so the god
  sets stay the endgame, and the Defence ladder now reads 1 / 10 / 20 / 30 / 50 / 70 / 85 / 95 — no
  gap wider than the pre-existing 30 → 50 stretch. It also gives both dead bars a purpose: eleven
  recipes each instead of a dungeon drop with no sink.
- Twenty-two Smithing recipes (Stormsteel at Smithing 85, Wyrmforged at 95): weapons take a bar plus
  coal, armour takes bars alone, and the 2H sword and platebody sit at the top of the XP band so the
  tier is worth the bars.
- Twenty-two recoloured icons, imported and added to the manifest.
- `_test_gear_ladder_gap` (crafted weapons and armour fill 50–95 with no hole, both bars consumed,
  every new item has a recipe) and a rewritten `_test_melee_tier_ladder`, which now measures
  **crafted** weapons only on `melee_strength`. It previously counted raid rewards and read `slash`,
  so a reward-track weapon the player cannot smith was setting the tier it compared against. The
  crafted ladder reads 10 / 14 / 21 / 30 / 46 / 58 / 66 / 80 / 95 across its nine tiers.

### Added (mid-game combat content)
- **Five monsters between combat level 66 and 102.** The ladder had nothing between the level-85
  dungeon pair and the level-110 wisp line, so a player who finished the mid-game dungeons faced a
  25-level stretch with no fight to progress through. Brine Troll (66), Tidewrack Hag (76),
  Sunderhold Centurion (88), Ashwyrm Seer (96) and Sunderhold Ballistarius (102) fill it: a melee
  and a magic fight in the open world, a melee and a ranged pair in the Keep, and a caster in the
  Hollow.
- **Saltmarch Basin**, the fourteenth region, at level 58–88 — the troll and the hag behind a
  "Slick brine: −10% evasion" hazard. Sunderhold Keep's roster now reaches 104 and Ashwyrm Hollow
  gained the Seer, so the arrivals sit in existing regions as well as a new one.
- **A mid-game dungeon, `sunderhold_undercroft` ("Sunderhold Undercroft"), at 71–105.** The dungeon
  ladder had nothing between Frostfang Den (stops at 70) and the Observatory of Gales (opens at
  110) — a 40-level stretch with no expedition to run, and the largest structural gap the audit
  found. Three escalating encounters from the Keep's garrison (`rune_knight`, `sunderhold_centurion`,
  `sunderhold_ballistarius`), 120,000 GP plus binding shards on every clear, and two `dragonite_bar`
  on the first. It opens on Slayer 50 and is the last dungeon before the god line.
- `_test_dungeon_ladder`: every dungeon's range is ordered, every encounter names a real monster,
  every dungeon pays on a clear, and — walked in order — no stretch of levels is left with no
  dungeon to run. It reports a worst gap of twenty levels (before `throne_of_the_herald`) where the
  same walk measured forty before this.
- **Three special attacks that no monster could ever fire are now live.** `life_leach`, `ocean_song`
  and `cloudburst_magic_ray` were authored in `special_attacks.json` with no carrier, so the code
  behind them was unreachable. The arrivals carry them, and with `stun_bash` and `quick_strike` on
  the Keep pair, all fourteen attacks in the table are now carried by something.
- **Deeper slayer pools.** Elite went 3 → 5, master 1 → 2 and legendary 1 → 3, turning three tiers
  that were a single assignment back into choices. Every pool member has an encounter, which is what
  the new `thin_slayer_pool` rule below checks.
- Five recoloured 96×96 monster sprites plus a 64×64 icon for Saltmarch Basin, imported; the asset
  report is back to full coverage (740 / 740).
- **Three new `ContentValidator` warnings**: `unused_special_attack` (an attack no monster carries),
  `orphan_monster` (a monster in no area and no dungeon, so its loot and its slayer assignments are
  unreachable) and `thin_slayer_pool` (a tier offering fewer than two monsters).
- `_test_monster_ladder`: roster floor, a worst-case combat-level gap of twelve up to level 120, a
  monster in every ten-level band, every monster placed in an area or dungeon, every special attack
  carried, every slayer pool at two or more with each member placed, and the five arrivals pinned at
  their exact levels, health floors and carriers.

### Added (the Cookery ladder is whole again)
- **`cook_crab` (Cookery 60) and `cook_cave_fish` (75), with `crab` ("Mudcrab") and `cave_fish`
  ("Cavern Char").** Fishing landed `raw_crab` at 60 and `raw_cave_fish` at 75 and nothing consumed
  either, so two of its fifteen catches were dead ends — and Cookery's unlock ladder was broken at
  exactly those two levels: a twenty-level hole from 50 to 70 and a fifteen-level one from 70 to 85.
  Mudcrab heals 175 and Cavern Char 215, slotted between Bladefin (150) and Gale Shark (200) and
  between Gale Shark and Glidefin Manta (240).
- Two recoloured item icons, imported; the asset report is back to full coverage (743 / 743).
- `_test_raw_fish_are_consumed`: every raw fish Fishing lands is consumed by some recipe, the two
  new recipes sit at 60 and 75 and cook into food that actually heals, and the Cookery ladder never
  pays less for a higher level.

### Fixed (the Attunement study ramp was inverted)
- **`study_4` paid less than the action it replaced.** The six Attunement studies were identical in
  inputs, interval and output, and the XP ramp was not a ramp: `study_3` (60) paid exactly what
  `study_2` (30) paid, and `study_4` (90) paid **180** — less than both — so a player was strictly
  better off staying on the older action. The ramp is now **96 / 189 / 230 / 270 / 320 / 465**,
  rising at every step; only `study_3`, `study_4` and `study_5` moved.
- `_test_study_ramp_rises`: each of the six studies must beat the one below it.

### Added (the Runescribing ladder)
- **`superheat_adamantite` (65), `superheat_runite` (70), `enchanted_emerald` (42) and
  `enchanted_ruby` (60).** Runescribing's unlock ladder read 1 / 10 / 20 / 30 / **55** / 75 / 85 /
  100 / 110 — a twenty-five-level hole at 30 → 55 — and its Superheat line jumped from mithril
  straight to umbral with no step for adamantite or runite, even though both ores exist at Mining 70
  and 85. Emerald follows sapphire on a nature rune and ruby on a fire rune, so the gem line now
  reads sapphire → emerald → ruby → diamond instead of sapphire → diamond. The four arrivals take the
  skill's largest level gap from twenty-five to fifteen and lift it from nine actions to thirteen.

### Fixed (Inscription's XP ladder ran backwards)
- **Three recipes paid less for more.** `scribe_time` (75), `scribe_sage` (90) and `bind_tome_sage`
  (90) consume exactly what the level-40 recipes consume, at the same interval, and paid **188**,
  **186** and **297** against the level-40 **189** and **302** — the same job for less pay. Retuned
  to 200, 215 and 310.
- `_test_action_xp_ladders`: groups each skill's actions by identical inputs and interval, then
  requires the best payer at each level to beat the best payer below it. It found those three across
  the whole game — the audit's own list of seven suspected inversions turned out to be seven
  different jobs (a no-input listener against a chain step, a bar against a finished ring) and
  contained none of the real ones.

### Fixed (the validator can see how items are actually acquired)
- **`--validate` is clean: 0 errors, 0 warnings.** It carried 47 permanent `no_acquisition_path`
  warnings, which made the rule worthless — a genuinely unreachable item looked exactly like the
  forty-seven false ones. The three manager-owned routes are now modelled: Ranching (each species'
  stock, produce, hide and meat, plus feed, manure and the two rare breeding variants), Inscription
  (every recipe with a `quality_product` ships an inked, a faded and an illuminated form) and
  Enchanting (recycling equipment yields one essence per enchant family).
- **The provisioner's forty shelves were invisible.** Every store record names a single item under
  `item_id`, but the check read only `grants_items`, so no shelf was ever counted as a source.

### Fixed (mastery metadata is checked, not assumed)
- **Fourteen modifier keys were read by name but absent from `ModifierKeys`** — the registry whose
  stated purpose is "no module typos a key". Because they were missing, a typo in a mastery or pool
  checkpoint table would fail silently, and the registry check could not be written at all.
- `_test_mastery_metadata`: every skill with actions declares mastery unlocks; every authored
  modifier key is registered or follows the `<skill>_<suffix>` convention; pool checkpoints sit only
  on the four documented marks (10/25/50/95) and are never empty; and every authored
  `success_chance` is a real probability. The 509 actions that leave it out run at the guaranteed
  default, which is why Smithing and Crafting never burn materials — that is now an assertion rather
  than an assumption.

### Fixed (every dead output now has a consumer, or a declaration)

- **The balance report's "materials nothing consumes" list read three demand channels out of fourteen.**
  It counted a recipe input, an upgrade material and a trader cost, and nothing else — so most of the
  **126** items it printed were already being spent by code it could not see: ammunition a bow charges
  per shot, familiar tablets and the marks that craft them, ranch stock, farm compost and manure,
  engineering devices, inked scribe texts, enchant essences and the tier-4 catalyst, bones buried at
  the altar, artefacts donated to the museum, and the settlement crates.
  `BalanceReport.consumed_item_ids()` is now the single model of what spends an item — fifteen
  channels, 292 items — and `dead_outputs()` sorts every obtainable item into spent, declared
  terminal, or undeclared. `--balance` reads **0 undeclared, 12 declared terminal**.
- **The 126 triaged in full: 95 were already spent (channels above), 19 had no consumer at all and now
  do, and 12 are terminal on purpose.** The nineteen were closed additively — twelve new actions and
  six new items across five skills — so no existing recipe, price, drop or XP value changed:
  - Ranch produce had no consumer anywhere: `ranch_egg` → `ranch_omelette` (Cookery 15), `ranch_milk`
    → `ranch_cheese` (Cookery 35), `ranch_antler` → three bowstring (Fletching 60), `ranch_scale` →
    blue dragonhide (Crafting 85), `ranch_star_scale` → black dragonhide (Crafting 110), and
    `ranch_ember` → two martial essence (Herblore 90), which gives the martial enchant family a second
    source beside disenchanting.
  - `harvested_essence`, Prospecting's only output, refines into rune essence (Herblore 45).
  - `topaz`, the one gem with no consumer, becomes a ring (Crafting 18) or its enchanted alt_magic
    form (25).
  - `duskroot`, `herald_bloom` and `emberbloom` brew real potions at Herblore 100/110/115 — stealth,
    global mastery XP and crit chance — each priced and charged in line with the existing ladder.
  - The five settlement crates (`wood_box`, `bar_box`, `food_box`, `herb_box`, `bird_nest`) and the
    endgame `raid_pet_egg` are openable: the wrapper is spent and the contents arrive through the
    guaranteed path. The egg hatches **sunderling**, a new pet that skips a raid wave, and refuses to
    be spent a second time.
  - `craft_border_collie` and `craft_sandman` now spend the mark their familiar awards, exactly as
    the other 25 tablets already did.
- **Twelve items are terminal on purpose, and now say so in the data.** `terminal_reason` on the item
  record covers `ash` (a firemaking byproduct with eleven routes and a 1 GP price), `artefact_shard`
  (excavation scrap beside the graded artefacts) and `burnt_food` (Cookery's failure result), plus the
  nine sell-for-GP outputs of the newer skills — echo inscriptions, weathers, fees, herald goods and
  confluences. `--balance` prints the reason beside each one, so "dead on purpose" and "forgotten"
  stop looking identical.
- **A new dead output can no longer slip in unnoticed.** `ContentValidator._check_output_demand()`
  warns `dead_output` for every undeclared item, warns `stale_declaration` when a later recipe consumes
  something already marked terminal, and errors `dead_channel` if any of the fifteen channels stops
  matching content — the failure where a renamed field quietly excuses every item it used to catch.
  The validator also checks that `container_items` is an object of known, positive grants and that
  `container_pet` names a real pet.
- `_test_outputs_are_consumed` (55 checks): no undeclared output, every declaration explained and none
  stale, all fifteen channels live, demand covers 292 items, every farmed crop and every ranch produce
  is spent, both special familiars spend their mark, every container hands over real items, and a live
  round-trip opens a crate and hatches an egg through Storage.
- `_test_balance_report_builds` (5 checks): the report is built inside the suite now. A shape change in
  `_bottlenecks()` with no matching change in `format_text()` crashed the whole `--balance` run at
  runtime while the tests stayed green — nothing had ever built it. The test pins every section and
  the keys the printer reads.
- `BankManager.open_container()`, plus **Open** / **Open all** buttons in Storage for any item that
  declares a container. Six new item icons, imported and listed in the asset manifest (749 of 749
  assets on disk).
- The pass is reproducible: `tools/dead_end_consumers.py` writes the actions, items, crates and pet,
  and `tools/gen_deadend_icons.py` draws the six icons. Both are idempotent — re-running them leaves
  every file byte-identical, and `tools/dead_end_consumers.py` prints zeros when there is nothing to
  add.

### Fixed (concentration is measured, and then declared)

- **The report's supply model counted kinds of route, not sources.** "Crafted" was one route no matter
  how many recipes made a material, and every enemy that dropped it was the same route — so Raw Glyph
  Essence, made by three recipes across two skills, and the Enchantment Catalyst, dropped by twenty
  enemies, were both reported as "a single point of failure". A route is now a source: one per
  producing recipe, one per shop, one per enemy, one per quest, one per system that hands items over
  (farming, ranching, inscription, enchanting, the Dream Bazaar, dig sites, the museum). Raw Glyph
  Essence has 6 sources, the catalyst 20.
- **The risk list covers the whole economy, not the top eight.** A hub ranked ninth strands just as
  many recipes as one ranked first, and the warnings now scan every material. That is what surfaced
  the two false alarms above, and the phantom material below.
- **The report was inventing a material.** `consumed_item_ids()` read the settlement trader's `cost`
  as item demand, but `cost` is paid from the township store in settlement resources
  (`TownshipManager.ALL_RESOURCES`) — so "goods", a resource, appeared as a material that six recipes
  need and nothing supplies. A trader cost is now demand only when it names a real item, the `trader`
  channel is gone (the trader buys nothing from Storage), and `ContentValidator` errors with
  `phantom_demand` if any channel ever names something that is not an item again.
- **A single source can be a decision, so the data now says so.** `bottleneck_reason` on an item
  declares the concentration deliberate, exactly as `terminal_reason` declares a deliberate dead end.
  Two materials carry it: `scribe_blue_ink` (the level-25 azure press) and `ranch_wool` (the sheep pen
  the sixteen robe recipes exist to depend on). `--balance` prints the reason beside the item;
  `ContentValidator` warns `bottleneck_undeclared` for a hub without one and
  `stale_bottleneck_declaration` when a later change makes a declaration false — a second source, or
  demand below the line. Both modes are clean: `--validate` 0 errors / 0 warnings, `--balance`
  0 warnings and 2 declared. The reasons are written by `tools/declare_bottlenecks.py`, which is
  authoritative and idempotent: it removes a declaration that is no longer true.
- **The first declaration was wrong, and the new guard caught it.** `scribe_paper` was declared one
  source, and it is not: the Dream Bazaar sells fifty sheets for forty dream essence. The declaration
  only became visibly false once the report's source model was completed — the bazaar, quests,
  achievements, dig sites, raid rewards, the museum's curios, the mastery stall, familiar marks and
  failure outputs all hand over items and none of them was counted as a source. `--validate` reported
  `stale_bottleneck_declaration` the moment the bazaar was modelled, and the declaration is gone.
  Paper now reads two sources: Inscription's mill and the bazaar bundle.
- **The validator's own source list had a stale read.** The provisioner's forty shelves are in
  `shop_store.json`, but the coverage check read `DataLoader.shop` — the GP upgrade catalogue — so the
  shelves stayed invisible even after the `item_id` form was taught to it in the previous pass. That
  is fixed, and the museum's curios and the bazaar's item grants are counted as sources for the first
  time. Every acquisition path the validator knows is modelled in the report now, and the suite pins
  a representative item per path (mill + bazaar for paper, a curio, a dig site, a shelf, a stall
  cape, a familiar mark, a failed cook) so a path cannot quietly go invisible again.
- `_test_bottleneck_declarations` (19 checks): every flagged hub is declared and explained, a
  concentration really means one source, no declaration outlived its concentration, the deliberate
  hubs are pinned by name, the two false alarms stay fixed (3 and 20 sources), one acquisition path
  per probe stays visible, and the report prints every reason it relies on.

### Balance notes
- The five arrivals are sized **into** the enemy-health curve rather than above it. The balance
  report compares each non-boss with the one below it and warns on a dip, so the level-96 and
  level-102 pair sit under the level-110 Gale Wisp's 700 health and the level-66 troll under
  Frostfang Wolf's 260. Raising the wisp line to meet them instead would have cascaded through the
  drake and the three wisps above it, rebalancing content that was already internally consistent.
- The four original staves gained an explicit spell tier (14/20/26/33 from a flat 10), a modest buff
  that keeps the ladder readable; even the level-1 staff stays well under a level-1 bow's 24.
- The balance report flags `Wool` as "needed by 17 recipes and nothing supplies it" and glyph
  essence as a single-route material. Both are report blind spots rather than gaps: wool comes from
  the Ranching system and the report models only content recipes. It does mean magic gear puts real
  demand on Ranching, Mining and Harvesting, which is intended. (Both are modelled now — see the
  concentration notes above: the sheep pen is a source, and glyph essence has six of them.)
- The report's supply warnings are resolved rather than muted. Raw Glyph Essence was never
  single-route (three recipes across two skills are three sources), the catalyst has twenty dropping
  enemies, and the two genuine hubs — Azure Ink and Wool — are declared in the data with the reason
  each one is fine (Scribe Paper looked like a third until the Dream Bazaar turned out to sell it).
  Wool also stops being a blind spot: the report now models the systems that hand items over without
  an action naming them, which is where the sheep pen lives.
- What is left at the top of the risk table is the shape of the economy, not a defect: eight
  materials with 17+ recipes each, every one of them supplied by at least two sources or declared.
- The level-70 raid reward weapon (melee strength 70) still outclasses crafted Stormsteel (58) at the
  same attack level. That is deliberate: raid gear is a parallel reward track, and a raid drop that
  a shop-or-smith tier immediately obsoletes would be worth less than the dungeon it came from.

## 2026-09-27 — audio, mid-level content, thin-skill depth, screenshot gate

### Fixed
- **Enrage was applied to every monster.** `CombatManager._monster_attack()` and the
  `CombatSimulator` multiplied all monster damage by the enrage curve regardless of the
  `enrage` passive, so the control fight and the "enraged" fight were the same fight.
  Both engines now gate on `passives.has("enrage")`; the first real user is the new
  Slag Golem.
- Cartography hexes shipped with `"poi": null`, which `Dictionary.get(key, default)` does
  *not* default (the key exists) — 16 of 25 hexes raised a runtime script error whenever a
  survey reward was read. `DataLoader` normalises `poi` to `{}` on load.

### Added (audio)
- `data/audio.json` — 16 synthesized SFX recipes (click, levelup, pickup, crit, kill,
  victory, quest, rare, error …), 2 music tracks (explore/combat), 18 EventBus
  event → sound mappings with per-event throttles, plus music and notification routing.
- `AudioManager` autoload: renders `AudioStreamWAV` PCM at 22 050 Hz from the recipes
  (multi-tone sequencing, frequency sweeps, attack/release envelopes, noise), 8-voice SFX
  pool, separate Music/SFX buses, throttled `play_sfx` wired to EventBus snapshot-safe
  lambdas. Music synthesis is skipped in CLI modes; SFX play everywhere so tests cover it.
- Settings: new SOUND section with Music/SFX volume sliders (debounced save) and a
  "Test sound" button; `music_volume`/`sfx_volume` defaults in `SettingsDefaults`.
- Coverage: `ContentValidator._check_audio` (tones, chords, EventBus signal names, sound
  and track references) and `TestRunner._test_audio` (16 checks: synthesis, loop points,
  cache identity, throttling, bus muting).

### Added (mid-level content — the L43–L59 gap)
- **Greyharrow Quarry** (area, L43–60, dust-hazard −5 accuracy) with four new monsters:
  Greyharrow Husk L45, Shale Stalker L50 (venom bite), Quarry Echo L54 (guaranteed hit),
  Slag Golem L58 (thorns + enrage) — a strictly rising HP curve from Mossbound Colossus
  (L42) to Sunderhold Sentry (L60).
- **Greyharrow Deep** dungeon (L43–60, requires Slayer 40): six fights ending on the golem,
  35 000 GP + 2 Skyiron Bars per clear, first-clear Ghoststeel Shield.
- Slayer pools: hard gains the Husk/Stalker/Echo (2 → 5), elite gains the Golem (2 → 3).
- Art for all six new assets (4 monster sprites, area + dungeon icon) generated in the
  house noise-silhouette style, imported, manifest refreshed: 749 / 750 on disk.

### Added (thin-skill depth)
- Excavation 7 → 11 dig sites (Shallow 15, Weathered 45, Sunken 70, Reliquary 100 — each
  with a paired `archaeology_sites.json` entry, since `SkillManager` calls
  `on_excavate(action_id)`).
- Surveying 6 → 9 actions (Coast 15, Frontier 45, Storms 85); Wayfaring 7 → 10 runs
  (Hedge 10, Ridge 40, Cloudline 62); Blight 8 → 13 actions (Listen/Open the Veil/Steep
  in Shadow/Chain a Restless One/Shoulder the Dark).
- **Umbral Essence is no longer a dead resource.** It was produced by every Blight action
  and consumed by nothing; the Umbral Binding Shard refinement now takes it (5 per shard)
  instead of rune essence, closing the corruption → summoning loop.

### Added (verification)
- `tools/shot_gate.py` — screenshot-diff gate over the real-window `--shot` sweep: runs
  the sweep, compares all 49 PNGs against `tools/shot_baseline/` per-pixel (channel
  tolerance 8, 0.25 % changed-pixel budget — two runs of identical code drift at most
  0.06 % on the 8 screens with live digits), writes magenta heatmaps for regressions and
  exits 1 on any changed/missing/stale shot. `--update` re-baselines after an intentional
  UI change; `.shot_gate/` is ignored.

### Verified
- `--tests` **396/396**, `--validate` 0 errors / 0 warnings, `--selftest` 22/22,
  `--balance` clean (no inversions, no curve dips, essence off the dead-output list),
  `--smoke` ok (41 monsters, 16 dungeons), screenshot gate **PASS** (49 compared).

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
- **The project is a git repository** (`master`) — but not everything is necessarily committed:
  run `git status` before relying on history, and commit in small steps so there is something to
  bisect and roll back to beyond the save backups.
- **Visual review is automated but not continuous.** `--shot` captures the real window at each
  breakpoint, but nothing runs it automatically, so a future layout change can still regress
  between runs. A screenshot-diff gate in CI is the obvious next step.
- **Tier-5 god gear is a long endgame project by design** — each piece needs a Warden-dungeon shard
  plus refined tiers, so it is not reachable in a short session.
