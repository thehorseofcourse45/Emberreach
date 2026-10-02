# Leveling pace with supplies and bonuses

Reproduce: `python tools/systems_audit/leveling_pace.py`. Planning scenarios, not exact completion promises. No XP values were changed.

Stocked: best unlocked recipe at each level, includes failures, stuns and node respawns. Supply chain: also pays recursive gathering/crafting time for inputs, with other supplying skills already at level 99. Cycles and items without a deterministic recipe source are excluded; unavailable means this model cannot sustain level 1 onward. Shared inputs are charged per item (conservative; coproducts are not credited). Supplier leveling, rare drops, shop purchases, travel, setup costs and player downtime are excluded.

Bonus scenario: constant +20% XP, 10% shorter active intervals, 10% preservation and doubling. These are explicit planning assumptions, not a claim that a fresh save has them. Selected-action mastery and real equipped bonuses are applied by the live UI forecasts.

Passive scenarios: Husbandry has 15 replanted plots, 90% survival and stocked seeds; Ranching uses two ordinary animals per unlocked pen, full feed, immediate collection, and mastery 50 in the bonus scenario; Dreamwalking uses repeated eight-hour windows, 50% offline allocation and average depth 1.25. Passive hours overlap active play and are not added to a serial total. Feed/seed acquisition is excluded from passive estimates.

| Skill | Stocked 1–99 | With supply chains | Bonus + supply chains |
|---|---:|---:|---:|
| Blight | 96 h (4.0 days) | 96 h (4.0 days) | 72 h (3.0 days) |
| Timbercraft | 144 h (6.0 days) | 144 h (6.0 days) | 108 h (4.5 days) |
| Angling | 120 h (5.0 days) | 120 h (5.0 days) | 90 h (3.7 days) |
| Delving | 120 h (5.0 days) | 120 h (5.0 days) | 91 h (3.8 days) |
| Husbandry | 213 h (8.9 days) | 213 h (8.9 days) | 178 h (7.4 days) |
| Kilncraft | 84 h (3.5 days) | 601 h (25.1 days) | 380 h (15.9 days) |
| Cookery | 96 h (4.0 days) | 207 h (8.6 days) | 142 h (5.9 days) |
| Forgecraft | 72 h (3.0 days) | 3,346 h (139.4 days) | 2,175 h (90.6 days) |
| Bowyering | 72 h (3.0 days) | 15,569 h (648.7 days) | 10,195 h (424.8 days) |
| Artifice | 84 h (3.5 days) | scenario unavailable | scenario unavailable |
| Glyphcraft | 108 h (4.5 days) | 363 h (15.1 days) | 242 h (10.1 days) |
| Apothecary | 96 h (4.0 days) | scenario unavailable | scenario unavailable |
| Larceny | 120 h (5.0 days) | 120 h (5.0 days) | 95 h (4.0 days) |
| Wayfaring | 96 h (4.0 days) | 96 h (4.0 days) | 72 h (3.0 days) |
| Beastbinding | 108 h (4.5 days) | scenario unavailable | scenario unavailable |
| Starreading | 120 h (5.0 days) | 120 h (5.0 days) | 90 h (3.8 days) |
| Runescribing | 96 h (4.0 days) | 1,942 h (80.9 days) | 1,146 h (47.7 days) |
| Settlement | scenario unavailable | scenario unavailable | scenario unavailable |
| Surveying | 120 h (5.0 days) | 120 h (5.0 days) | 90 h (3.8 days) |
| Excavation | 120 h (5.0 days) | 120 h (5.0 days) | 90 h (3.7 days) |
| Prospecting | 120 h (5.0 days) | 120 h (5.0 days) | 91 h (3.8 days) |
| Echo Keeping | 144 h (6.0 days) | 345 h (14.4 days) | 259 h (10.8 days) |
| Wayfolding | 144 h (6.0 days) | 247 h (10.3 days) | 185 h (7.7 days) |
| Fermentation | 120 h (5.0 days) | 334 h (13.9 days) | 212 h (8.8 days) |
| Customcraft | 144 h (6.0 days) | 230 h (9.6 days) | 172 h (7.2 days) |
| Lostfinding | 144 h (6.0 days) | 278 h (11.6 days) | 209 h (8.7 days) |
| Ranching | 216 h (9.0 days) | 216 h (9.0 days) | 91 h (3.8 days) |
| Inscription | 96 h (4.0 days) | 233 h (9.7 days) | 153 h (6.4 days) |
| Engineering | 120 h (5.0 days) | 321 h (13.4 days) | 198 h (8.3 days) |
| Enchanting | 96 h (4.0 days) | 144 h (6.0 days) | 102 h (4.2 days) |
| Dreamwalking | 230 h (9.6 days) | 230 h (9.6 days) | 192 h (8.0 days) |

## Combat and non-repeatable systems

Combat skill time depends on actual damage per second, selected style, deaths, target HP, respawns and supplies. Use the simulator for your current loadout. For illustration, at sustained 20 damage/second: a focused Attack/Strength/Defence/Ranged/Magic skill earns 28,800 XP/hour and needs about 453 hours to 99; Vitality earns 9,576 XP/hour and needs about 1,361 hours. These are conditional damage scenarios, not beginner rates. Prayer earns DPS × prayer cost/attack ÷ 30 XP/second; Huntsman earns 10% target HP per task kill plus 5% in Slayer areas. Finite simulation supplies stop the scenario at food depletion/death or prayer/attack-material exhaustion.

Settlement construction and first-discovery Cartography do not provide an unlimited repeated training loop. Their totals must not be extrapolated as if free repeat clicks granted XP. Timed skill actions remain the repeatable Cartography route.

The supply-chain column can be substantially slower than stocked crafting. Train suppliers and build reserves before committing to a long batch; use worker production and parallel passive time to reduce active preparation. Level 120 remains much longer than 99 because of the XP curve. The current live previews show near-term unlocks, material bottlenecks and runway rather than promising an exact calendar completion date.
