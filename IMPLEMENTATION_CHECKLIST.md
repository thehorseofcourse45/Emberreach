# Emberreach — Overhaul Implementation Checklist

Living document. Status is reported honestly: `[x]` done and verified, `[~]` partially
done, `[ ]` not started, `[-]` deliberately deferred with a reason.

Run commands (Godot 4.7.2 binary used during development):

```
/c/Godot/Godot_v4.7.2-stable_win64_console.exe --path .                     # play
/c/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --tests      # unit tests
/c/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --validate   # content validation
/c/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --smoke      # load + formula smoke
/c/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --selftest   # end-to-end progression
/c/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --balance    # writes BALANCE_REPORT.md
/c/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --offline 3600  # offline probe
/c/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --assetreport   # asset coverage
/c/Godot/Godot_v4.7.2-stable_win64_console.exe --path . -- --shot res://shots     # REAL window PNGs (no --headless)
```

`--shot` is the one mode that must **not** be run headless: it opens the real window, renders the
6 busiest screens at 420 / 900 / 1440 px and writes PNGs to `shots/`. It exists because every defect
below was invisible to the headless suite.

---

## Stage 1 — Audit and protect

- [x] Audited framework (Godot 4.7.2, GDScript, JSON content, no package manager, no git repo),
      entry point (`scenes/main.tscn` -> `scripts/ui/MainUI.gd`), 29 autoload singletons,
      4,771 lines of GDScript, 293 KB of JSON, 379 item icons / 29 monster sprites.
- [x] Identified the architecture split (content / state / simulation / persistence / UI) and
      recorded which parts were sound and which were fragile.
- [x] Save system hardened: versioned saves, schema validation, atomic write + rotating backups,
      migration chain, malformed saves preserved (never silently replaced), export/import,
      explicit save status surfaced in the UI.
- [x] Content validation catches duplicate IDs, missing item/skill/monster references,
      invalid recipes, unreachable unlocks, circular dependencies, bad drop weights,
      negative durations and negative numeric values.
- [x] Critical simulation defects found during the audit are fixed (see Stage 2).

## Stage 2 — Vertical slice: gather -> refine -> craft -> equip -> fight -> save -> offline

- [x] Crafting/materials are consumed atomically; running out of inputs stops the activity
      with an explained stop condition. Free-output exploit removed.
- [x] Bank capacity is a manageable constraint (generous base, explicit expand affordance,
      no silent loot loss; a full bank never eats a rare drop).
- [x] Offline progression rewritten as a bounded, batched, signal-silent simulation that
      uses the same formulas and stop conditions as online play, and is applied exactly once
      per save transition (consumption flag persisted immediately).
- [x] Offline summary reports time processed, time excluded by the cap, XP, levels, items
      gained, materials consumed, combat results, rare drops and why progress stopped.
- [x] Design tokens (colour, type, spacing, radius, border, shadow, motion, layering, sizes).
- [x] Reusable components: resource chips, item icons + rarity treatment, progress bars,
      skill rows, activity cards, recipe rows, tooltips, tabs, search/filter, confirm dialog,
      toasts, empty/loading/error states.
- [x] New application shell: compact sidebar navigation, top status bar, main workspace,
      contextual detail panel, persistent current-activity strip.
- [x] Responsive behaviour: sidebar collapses to a nav drawer/compact bar on narrow viewports;
      panels stack without horizontal overflow; the activity strip never covers controls.
- [x] Overview dashboard: current activity, skill highlights, loadout readiness, tracked goals,
      newly available unlocks, recent events, suggested next steps derived from real state.

## Stage 3 — Connected medium-term progression

- [x] Goal tracker: pin an item/recipe/skill unlock/quest/building; shows requirements,
      progress, missing materials, prerequisite recipes, where materials come from and a
      direct route to the relevant activity. Circular dependencies detected.
- [x] Quests: authored, data-driven, objectives driven by real game events, exact-once rewards,
      lifetime vs. held-item counters distinguished, navigation to the relevant screen.
- [x] Achievements: skill / discovery / crafting / combat / collection / optional challenge,
      modest rewards only.
- [x] Collection log surfaced in the UI (items, monsters, dungeons, pets) using the existing
      `completion_log` state.
- [x] Settlement progression UI: buildings with costs, limited upgrade path, visible effects
      and links to the systems they improve.
- [x] Automation unlocks gated behind understanding (auto-repeat is earned, not default).

## Content identity pass

- [x] Project title, window title and premable replaced with the original setting
      ("Emberreach"), removing all Melvor Idle naming from the running game.
- [x] Original names + flavour text for all 29 skills, 12 regions, 11 dungeons and 29 enemies.
- [x] Original names for the visible equipment/resource spine (tiered gear, ores, bars,
      logs, fish, foods, potions).
- [~] Long-tail item display names (the remaining ~250 items). IDs are stable, so this is a
      rename-only pass with no save or icon impact. The three Melvor-specific offenders
      (`golbin*`, `alt_magic`, `Melvor` in text) are done.

## Stage 4 — Balance, polish, tests

- [x] Automated tests for XP/level maths, multi-level grants, recipe consumption,
      affordability boundaries, equipment modifiers, exactly-once quest/achievement rewards,
      save round-trip, old-save migration, malformed-save recovery, offline cap,
      negative elapsed time, online/offline consistency, resource exhaustion, combat
      defeat/retreat, duplicate action submission and content-reference validation.
- [x] End-to-end progression check (new game -> gather -> craft -> equip -> fight -> quest ->
      settlement upgrade -> save/reload -> offline).
- [x] Balance targets validated instrumentally (unlock timing, production/consumption,
      equipment efficiency, enemy difficulty, drop EV) — `scripts/core/BalanceReport.gd`, run with
      `--balance`, writes `res://BALANCE_REPORT.md`. The report is content-only (no modifiers), so
      it compares content to content rather than predicting a session. It currently reports
      **0 progression inversions** and **0 enemy-curve warnings**; the remaining notices are the
      intentional shared-bottleneck materials (Verdant Binding Shard, Prismatic Essence,
      Wyrmsteel Bar) and a low source:sink GP ratio, both of which are design choices.
- [x] Reconciled `ContentValidator` with the balance report: the validator had treated *being an
      ingredient* as a way to obtain an item, which hid real orphans. Removed that rule, modelled
      the familiar-mark source it was missing, and closed every gap it then exposed (see below).
      `--validate` is now honestly clean: **0 errors, 0 warnings, 9 notes**.
- [x] Narrow/wide layout sweep on real hardware. `--shot` renders the real window at each
      breakpoint and writes PNGs for review. Doing this found five defects the headless suite
      could not see (see "Real-window pass" below); the suite now asserts the assembled shell
      fits, not just individual panels, so they cannot come back.
- [-] Prestige/ascension. Deliberately deferred: the first journey is not yet long enough to
      make a reset interesting, and the brief forbids prestige without that justification.
- [-] Expanding regions 13+ until the Stage 3 loops are played. The data model supports it;
      it is a content-authoring task, not an engineering one.

## Real-window pass — defects only the running game showed

Every item here was invisible to `--tests`, `--smoke` and `--validate` because those run headless
with the shell never laid out. All are fixed and covered.

- [x] **Cached screens were destroyed on navigation.** `_clear_workspace()` queue-freed the scroll
      holding the panel you were leaving, which took the cached panel with it and left `_panels`
      holding a dead node. `_clear_workspace` now detaches cached panels first and drops dead ones,
      so the cache heals itself.
- [x] **The bounded event log was being destroyed on every rebuild.** `_clear()` frees every child
      of a box, and both the Overview and Combat panels re-add a persistent `_log["root"]` widget
      they hold a reference to. New `Widgets.detach()` lifts it out first.
- [x] **The responsive breakpoints never fired.** `window/stretch/mode="canvas_items"` pins the
      canvas to a 1280px base and *scales*, so `size.x` was never below 1280 whatever the window
      width — the sidebar never collapsed. Set to `disabled` (1 canvas unit = 1 pixel). The project
      already declared `min_width=420`, so this was always the intent.
- [x] **Autowrapping labels collapsed to one character per line.** `UIStyle.label()` only set
      `EXPAND_FILL` above 48 characters, so a short label given `autowrap_mode` by a caller had a
      minimum width of ~1px and wrapped vertically. Labels now always fill.
- [x] **The whole shell was 602px wide inside a 420px window.** The status bar (one long HBox) and
      the activity strip (a hard 200px minimum on the estimate label) set the floor, while the
      Overview and Combat panels fit individually. Both are now `HFlowContainer`s and the estimate
      label wraps; the suggestion and goal rows wrap too. Shell minimum is now 404px.

## Brief coverage — all 21 sections

Audited against the original brief, section by section. "Partial" means the requirement is met in
spirit but not to the letter of the brief.

| # | Section | Status |
|---|---------|--------|
| 1 | Creative direction | Done — Emberreach premise; every system tied to rebuilding the frontier; no monetization, energy or login gating |
| 2 | Inspect first | Done — framework, entry points, loop, save format, UI, tests and dev commands all recorded; architecture preserved, not rebuilt |
| 3 | Cohesive game loop | Done — gather → refine → craft → loadout → fight → unlock → settlement; goals show requirements, missing materials, prerequisites, sources and a route |
| 4 | Visual / interaction overhaul | Done, after the real-window pass — dark-fantasy tokens, shell, drawer, stacking, wrapping rows, focus rings, `reduced_motion`, no icon-only controls, scroll preservation |
| 5 | Overview and goals | Done — activity, skills, readiness, goals, unlocks, events, suggestions; a sub-tab per skill with a compact level/mastery/estimate card; pinning with full dependency chains and circular-dependency detection |
| 6 | Skills and mastery | Done — 29 skills, level vs mastery separated, estimates show XP/action, XP/h, output/h, time to next level, supply exhaustion and every modifier with its source |
| 7 | Items, inventory, economy | Done — search, filters, sorting, favourites, protection, quantity select, bulk sell with preview, transaction guards. Favourites and protection are separate features with separate jobs |
| 8 | Crafting and production | Done — one / chosen quantity / maximum, repeat until stopped, atomic consumption, explained stop conditions, goal-aware |
| 9 | Combat overhaul | Done — automated, style/loadout/food/rites preparation, win-chance from the real model, saved loadouts, retreat, stops on defeat, never destroys rare gear |
| 10 | World and regions | Done — 12 regions with flavour, monsters, unique materials, quests and dungeons; unlocked by skill, gear, quests and settlement |
| 11 | Quests, achievements, collections | Done — 27 quests, 33 achievements, collection log; lifetime vs held-item counters distinguished; exactly-once rewards |
| 12 | Settlement progression | Done — buildings with transparent costs, visible effects and links to the systems they improve |
| 13 | Specialization / late game | Deferred by the brief's own condition — prestige is not implemented; depth went into the mastery stall (58 capes + 2 completion capes) and god-tier gear. No respecialisation mechanic |
| 14 | Offline and time simulation | Done — shared authoritative model, bounded chunked catch-up, exactly-once per save transition, configurable cap, full summary. Clock changes and tab throttling are handled by clamping, not by separate systems |
| 15 | Save system | Done — v2, validation, migration, legacy adoption, pre-migration backup, atomic write, rotating backups, export/import, quarantine, session lock, never silently replaced |
| 16 | Balance and content targets | Done — stretch targets exceeded on every axis; `--balance` checks unlock rates, bottlenecks, curve and economy, and labels itself content-only |
| 17 | Engineering | Done — content/state/simulation/derived/persistence/UI separated; bounded logs; batched offline; validation catches duplicate IDs, missing refs, bad recipes, unreachable unlocks, cycles, bad weights, negative values |
| 18 | Testing and verification | Done — 189 checks, 10-step end-to-end trace, real-window layout sweep, actual results reported |
| 19 | Implementation order | Done — staged 1–5; stage 6 optional depth deliberately not started |
| 20 | Definition of done | Done — every feature runs in the game, persists, is tested, and nothing is hidden behind a misleading label |
| 21 | Final handoff | Done — `CHANGELOG.md`, including migration details and deferred work |

Outstanding, honestly: the long-tail item display names (identity work) and the §13
respecialisation mechanic, which is deferred along with prestige.

## Favourites and protection are two different things

The brief lists "favourites" and "protection against accidental sale" as separate inventory features.
Only protection existed, and the bank panel's header comment described favourites *as* protection —
which is the wrong model. A bookmark is not a lock: conflating them means tapping "Favourite" on a
high-value item would silently turn it into a safety setting the player never asked for.

- [x] `PlayerData.favorite_items`, persisted under `player.favorite_items` alongside
      `protected_items`, and sanitised on load so a stale id cannot resurrect a row with no data.
- [x] `BankManager.set_favorite` / `is_favorite` / `toggle_favorite` / `favorite_count`.
- [x] Favourites lead every sort order, **including descending** — pinning an item exists to keep
      it findable when storage is long, so obeying the sort direction would defeat the point.
- [x] "☆ Favourites" filter toggle, per-row Favourite/Unfavourite, a Favourite badge, a
      "Favourite selection" action, and a distinct empty state explaining the bookmark/lock
      difference.
- [x] Covered by tests: toggling, favourites-first in both directions, the filter, surviving a real
      JSON save round trip, and the one that matters most — a favourited item is still sellable.

## Final content pass — closing real acquisition gaps

Found by making `--validate` stop trusting "is an ingredient" as a source, then verified with
`--balance`. Every fix is applied by an idempotent script and is re-runnable without side effects.

- [x] `summoning_shard_green` had **no source at all**, which made the entire Beastbinding tree
      unreachable: 25 summoning-tablet recipes and the first shard refinement all consume it, and
      nothing produced or dropped it. All 29 enemies now drop it (scaled by combat level, bosses
      pay more) via `tools/content_fixups.py` — combat feeds tablet binding, as it should.
- [x] Unreachable equipment sub-trees: `sapphire`/`emerald`/`ruby`/`diamond` (mining secondary
      outputs), `bronze`/`iron`/`steel_arrowtips` (smithing secondary outputs), and the four
      wyrmhides (drops from a tier-appropriate beast, with the wyrm itself the richest source of
      its own hide). This makes the gem rings and all 16 d'hide recipes reachable.
- [x] One real non-boss enemy-curve inversion (Fen Spinner L15 had less health than Barrowbones
      L12) fixed; the boss-spike false positives in `BalanceReport` were corrected so a boss is no
      longer compared against the non-bosses it is meant to overshadow.
- [x] `--smoke` now enumerates all **11** screens (the Recovery screen was omitted).
- [x] Regression guard added to `--tests`: every previously-orphaned material must have a real
      source, and the failure message names the missing ids.
- [x] Layout guards strengthened: `--tests` now loads **every screen into the real shell at 420px**
      and asserts the assembled minimum width, which is the check that was previously blind.
- [x] **Scroll positions are actually preserved.** The workspace tagged its scroll with the screen
      name and a comment claimed the offset was kept, but nothing ever read it back — leaving a long
      list and returning reset you to the top. Offsets are now captured on navigation and restored
      a frame later, once the rebuilt content has a height. Locked by a test.
- [x] **Favourites implemented as a real feature**, separate from protection (§7).
- [x] **Post-overhaul layout changes:** Storage moved to the top of the sidebar, the contextual
      detail pane narrowed from 320 to 260 px, and Overview rebuilt as a hub with a wrapping sub-tab
      per skill (Dashboard + 29 skills, each labelled with its live level) showing a compact skill
      card that hands off to the full Skills screen. The strip uses a new `Widgets.tab_flow`
      (`HFlowContainer`) because the existing fixed `tab_strip` would put thirty tab minimums into
      one row and reintroduce the horizontal-overflow bug.
      `--tests` is now **218 checks, 0 failed**.
- [x] **The general store is its own screen** (`Screens.STORE`, `GeneralStorePanel`), directly
      under the Provisioner. It was that screen's third section, and the two are read differently:
      upgrades are a catalogue you exhaust, stock is a counter you return to.
- [x] The new screen adds what the embedded section had no room for — search, an
      `Everything`/`Affordable`/`Locked` filter, an affordability bar and a per-row Track action —
      and defaults to **Everything** so a fresh character with no gold still sees the catalogue
      rather than an empty shelf. `Affordable` is a filter over a shelf that is always shown in
      full, never the initial state.
- [x] The Provisioner keeps a live signpost (`Open the General Store`, with the current affordable
      count) instead of a second copy of the rows, which is the density problem the split fixes.
- [x] `Goals.sources_for_item` now lists the store for every item it stocks, gated by the same skill
      level, routing to the new screen: goal tracking can finally answer "where do I get this?"
      with "gold".
- [x] Covered by 17 tests, including the half that is easy to forget — the Provisioner must **not**
      still render the shelves — plus each filter, search, the empty state, and every blocked row
      stating its own reason. The store test runs after the layout suite, since that suite is what
      assembles the shell the screen tests share.
      `--tests` is now **307 checks, 0 failed**; `--selftest` **22 passed**; `--shot` **46 PNGs**, 0
      script errors.

## Stage 5 — Deferred / known limitations

See the "Known limitations and deferred work" section of `CHANGELOG.md`.
