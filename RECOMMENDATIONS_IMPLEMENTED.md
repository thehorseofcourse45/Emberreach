# Audit recommendations implemented

30 September 2026. Applies the recommendations in SYSTEMS_AUDIT.md using existing managers, panels, assets, and goal routes.

## Confirmed bugs fixed

- Two-handed weapons return displaced shields to Storage or overflow.
- Equipment sets validate ownership and requirements before transferring gear; reloading an unchanged set cannot duplicate it. Equipment returns and overflow withdrawals cannot inflate lifetime item progress.
- Raid completion uses one authoritative transition online and offline. Only completed waves award coins and choices; ending or losing a run banks previously earned coins once. Pending choices, coins, the current enemy, attack timers, and combat statuses survive saves.
- Cartography discovery XP is paid once; repeat travel is not an XP source. Surveying null POIs is safe.
- Settlement obeys Pause and uses real seconds for passive production. Accelerated active training does not multiply its passive clock or recorded playtime.
- Trader grants have one item-progress recording path.

Additional fixes found while implementing: Auto Eat previously divided healing efficiency by 100 twice; Farmhand could leave failed crops permanently blocking its plots; rebuilding Agility could leave stale pillar modifiers. These paths now have regression coverage or are exercised by the existing system tests.

## Recommendation checklist

| System | Completed change |
|---|---|
| Combat skills | Combined accuracy, expected normal damage, prayer runway, food quantities and modifier-adjusted healing. Gear candidates show stat changes; complete sets show before/after gear totals and support selections. |
| Encounters | Region/dungeon/Expedition reward sprites and first-defeat/first-clear progress. Raid reward identity and persistent clear/choice/bank checklist. |
| Prayers | Offensive, defensive, protection and utility groups; points per minute and depletion estimate. |
| Slayer / Huntsman | Assigned target location, reward and direct combat/Expedition route. |
| Corruption | Selected-action benefit, material cost and actual combat consequences explained. |
| Gathering | Activity cards show effective interval and XP/hour. Tooltips/details show output/hour, node downtime, failure downtime and next-unlock ETA. Selected-action mastery is projected without changing live modifiers. |
| Artisan skills | Quantity previews include expected attempts, inputs, preservation, doubling, success, outputs, total time and material bottleneck. |
| Farming / Husbandry | Plot-category explanation matches existing herb-only content. Survival, compost/manure, growth time and yield preview before planting; harvest-and-replant control. |
| Thieving | Success, expected failure stun and GP/hour projections include downtime. |
| Agility | Combined active/proposed course effects and blueprint cost previews. Rebuilds validate GP and authored materials before spending; pillars also validate material costs. |
| Summoning / Beastbinding | Charge runway, synergy requirements and explicit owned-tablet refill. |
| Astrology | Affordable stars sorted by cost or constellation; tooltip comparison includes downstream XP/hour and output/hour changes with current stacking rules. |
| Archaeology | Unique artefact discoveries separated from duplicate donations; affordable museum purchases highlighted. |
| Cartography | One-time travel discovery distinguished from timed training/POI surveying; reward categories and null-POI handling. |
| Echo Keeping, Wayfolding, Fermentation, Customcraft, Lostfinding | Existing chains and downstream consumers displayed. Reward and ingredient goal buttons support choosing a useful support item, planning a route chain, comparing batch success/losses and working backwards from a case reward. |
| Ranching | Feed hours, next produce, breeding readiness, ordinary/rare identification, stock-pair, feed-all and collect-all controls. |
| Inscription | Research prerequisite and quality odds; before-use effect, duration, expiry and replaced-buff description. Target selection updates the preview. Instant XP/time texts are distinguished from lasting buffs. |
| Engineering | Worker fuel/output/material runway and stalled reason. Farmhand uses logical harvest times across offline slices, clears failed mature crops and estimates actual crop output. |
| Enchanting | Actual discounted cost, before/after passive bonuses and replacement preview; appended enchants use the same potency calculation as the resulting item. |
| Dreamwalking | Eight-hour split preview shows XP, Essence and lost waking time. Event choices show their actual current Essence price and reward. |
| Mastery and progression | Next activity/pool checkpoint and keeping-versus-spending consequences. Skills without authored pool bonuses explicitly say so. Leveling estimates recomputed with recursive supply preparation and bonus scenarios. |
| Pets / collection | Skill pet chance scales with elapsed training time; splitting the same duration preserves its probability. Persistent bounded unlock/discovery history. |
| Settlement | Next affordable structure, resource bottleneck, wait estimate and resource payoff time. Clock/counter corrections above. |
| Storage / equipment / food / shops / loot filters | Existing quantity and protection controls retained. Set ownership validation extends to food, prayers and familiar charges/tablets. Legacy gear sets remain readable. |
| Action Queue | Each step previews inputs, expected output and blocker/stop condition. Offline quantity targets explicitly disclose the possible one-slice overshoot. |
| Combat Simulator | Assumptions visible beside controls; finite equipped-food quantities, prayer balance and authored attack-material costs. Shared live stat derivation, triangle calculations, specials, protection and enchanted status handling; finite exhaustion and status regression cases. |
| Tasks / milestones / goals / tutorial | Five starter objectives and contextual first-step cards connect to existing 10/50/99 task chains. Source hints include scribe variants/research, stock/breeding, disenchanting/enchanted items and Dreamwalking/Bazaar rewards. |
| Prestige | Gate says this run's XP; reset/retained-state preview. |
| Saves / offline / modes / settings | Atomic saves and offline markers retained. Full mid-raid and enchanted-loadout JSON round trips, passive timing parity and explicit mode rules. Optional new fields load safely from older saves. |
| UI / assets / audio / notifications | Existing sprites, progress bars and tooltip patterns reused. History persists after level popups; audio respects muted celebration categories, SFX volume and silent simulation. Reduced-motion popup behavior retained. Narrow layouts corrected for populated inventories. |
| Data / events / modifiers / validation | Every new-system record group receives ID/reference/numeric/modifier validation, with injected-invalid-record checks. Preview modifier replacement uses existing stacking rules. Seven original reproductions are now fix-specific checks. |

## Verification

- Main regression suite: **1,768 checks passed**.
- Isolated audit scene: **553 checks passed**, including all 528 action projections, the seven original regressions, ownership/save boundaries, three-hour Farmhand batch-versus-slices parity, pet probability partitioning, and simulator special/status/finite-supply cases.
- Five new skills: **527 checks passed**, with save files restored byte-for-byte.
- Populated-inventory layouts: **90 checks passed**, every skill plus six affected panels at 420px and 1440px. Rendered examples inspected.
- Level popup: **128 checks passed**; 420px and 1440px rendering, real-time duration and reduced-motion behavior preserved.

Run from the project:

```text
Godot --headless --path . -- --tests
Godot --headless --path . res://tools/systems_audit/check.tscn
Godot --headless --path . res://tools/new_skills_check/check.tscn
Godot --headless --path . res://tools/systems_audit/ui_check.tscn
python tools/systems_audit/leveling_pace.py
```

The main suite still reports its existing UI/resource cleanup warnings at process exit. Passing assertions do not claim every possible content combination has been exhaustively tested.

## Planning limits stated in the UI

- Combat weapons without authored attack costs currently consume no ammo/runes in live gameplay. The finite simulator mirrors this rather than inventing expenditure; authored cost bundles are checked against owned stock. Prayer depletion ends a finite trial conservatively; it does not project continued fighting after prayers switch off.
- Simulator bonuses are held constant: future level-ups, potion expiry, familiars and loot replenishment can change the real result. Every trial starts at full HP; it is not an unlimited unattended-survival promise.
- Active forecasts assume uninterrupted supplies; Engineering estimates assume continued fuel and materials; Farmhand output is a long-run expectation rather than the next crop's guaranteed yield.
- Queue offline quantity targets may overshoot by one 30-second simulation slice, as disclosed beside the queue.
- Discovery history begins recording with this update and keeps the latest 300 entries. Older discoveries stay in the existing collection log.
- LEVELING_PACE_WITH_SUPPLIES.md is a reproducible scenario report. It identifies excluded sources and unknown routes; conservative recursive preparation totals are not exact calendar completion predictions. Existing XP balance values are preserved.
