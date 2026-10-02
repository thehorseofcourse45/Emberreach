# Emberreach systems audit — 30 September 2026

## Implementation update

The user authorized the complete recommendation set. All recommendations below are now addressed; the original findings remain as audit history. See [RECOMMENDATIONS_IMPLEMENTED.md](RECOMMENDATIONS_IMPLEMENTED.md) for the implementation checklist, regression evidence and stated planning limits, and [LEVELING_PACE_WITH_SUPPLIES.md](LEVELING_PACE_WITH_SUPPLIES.md) for recalculated scenarios.

## Original audit result

Implemented a gold skill level-up popup with the skill's sprite and new level. It uses the existing notification UI, lasts five real seconds even at accelerated game speed, respects reduced motion, and permits clicks through it. Offline level gains remain in the existing return summary rather than flooding the screen during simulation.

Reviewed the 39 skill definitions (528 actions), their shared execution paths, the 42 autoload managers, and the surrounding UI, economy, persistence, and automation systems. This is a source audit with targeted runtime reproductions, not a claim that every possible combination has been exhaustively tested.

Verification: **128 popup checks and 1,753 existing regression checks passed**. Popup renders checked at 420px and 1440px. Seven additional audit issues were reproduced with saving disabled. These are recommendations for subsequent fixes; only the requested popup was changed in gameplay code.

## Fix these first

| Priority | Confirmed issue | Reproduction and recommended fix |
|---|---|---|
| P1 | A two-handed weapon deletes an equipped shield. | Equip a bronze shield, then a bronze two-handed sword: the shield is absent from equipment, Storage, and overflow. Return the shield through the normal unequip operation before occupying both hands. [EquipmentManager.gd](C:/Godot/melvor-clone-godot/scripts/autoload/EquipmentManager.gd:18). |
| P1 | Loading an equipment set duplicates gear. | Save a set containing one equipped sword and reload it: one sword is now equipped and another is in Storage. Sets should reference owned pieces and transfer them atomically, with requirement and two-handed checks. [EquipmentManager.gd](C:/Godot/melvor-clone-godot/scripts/autoload/EquipmentManager.gd:189). |
| P1 | Completed raid waves do not award choices or coins through the live event path. | Combat emits only `{reason: "complete"}`; RaidManager requires `type == "raid"`, so it ignores the event. Include the completed combat context, and award a wave only for successful completion. Use the same authoritative transition offline. [CombatManager.gd](C:/Godot/melvor-clone-godot/scripts/autoload/CombatManager.gd:100), [RaidManager.gd](C:/Godot/melvor-clone-godot/scripts/autoload/RaidManager.gd:57). |
| P1 | Reloading loses unbanked raid coins and pending upgrade choices. | A JSON round trip drops 123 pending coins and an offered choice because neither field is serialized. Persist both, normalize them on load, and test reopening between waves. [RaidManager.gd](C:/Godot/melvor-clone-godot/scripts/autoload/RaidManager.gd:140). |
| P2 | Free repeat travel grants unlimited Cartography XP without training time. | Two visits to `hex_0_0` cost no GP and award 40 XP. Pay exploration XP once per discovery, or make repeat surveying a timed action. [CartographyManager.gd](C:/Godot/melvor-clone-godot/scripts/autoload/CartographyManager.gd:19). |
| P2 | Settlement production ignores Pause. | With the game paused, `_process(3600)` still produces resources. Its online timer also uses scaled engine seconds while other passive producers use real seconds. Give passive systems the same pause, catch-up, and elapsed-time contract. [TownshipManager.gd](C:/Godot/melvor-clone-godot/scripts/autoload/TownshipManager.gd:65). |
| P2 | Settlement trades double lifetime item progress. | A trade granting one wood box records two lifetime gains. BankManager already records the gain; remove the second record in the trader. This can complete item objectives prematurely. [TownshipManager.gd](C:/Godot/melvor-clone-godot/scripts/autoload/TownshipManager.gd:264). |

Runnable reproductions: `Godot --headless --path . res://tools/systems_audit/check.tscn`. The scene now asserts the corrected behavior and exits nonzero on a failure. It disables saves and uses isolated in-memory state.

## Best improvements to the existing systems

| System / skills covered | Recommended improvement | Why it helps |
|---|---|---|
| Attack, Strength, Defence, Vitality, Ranged, Magic | Show accuracy, expected damage, healing per food, and supplies remaining together; compare a candidate loadout before equipping. | Players can understand why a fight is slow or dangerous. |
| Combat regions, dungeons, Expeditions, Raid | Give each existing encounter a visible reward identity and first-clear checklist. Fix raid transitions before expanding it. | Makes encounter choice meaningful without adding another mode. |
| Prayers | Group the 60 prayers by offensive, defensive, protection, and utility roles; show projected points/minute and time until depletion. | Sixty individual descriptions are difficult to compare. |
| Slayer / Huntsman | Show the assigned monster's location and reward prominently, with a direct route to its encounter. | Reduces searching between task assignment and combat. |
| Corruption | Preview its benefit, cost, and any combat consequence alongside the selected action. | Makes the progression tradeoff visible. |
| Woodcutting, Fishing, Mining, Harvesting | Add effective XP/hour, output/hour, respawn overhead, and ETA to the next unlock to existing activity cards. | Rates reflect actual downtime rather than raw recipe XP. |
| Firemaking, Cooking, Smithing, Fletching, Crafting, Runecrafting, Herblore, Alt Magic | Add a craft-quantity preview: inputs, expected preservation/doubling, success rate, total time, and material bottleneck. | Players can plan a useful batch before spending supplies. |
| Farming / Husbandry | Enforce or clearly explain plot categories; expose survival and compost/manure effects before planting; support harvest-and-replant with the selected crop. | Reduces repetitive clicks and confusing failed crops. |
| Thieving | Show success chance, expected stun time, and sustainable GP/hour next to targets. | Headline rewards currently conceal failure costs. |
| Agility | Show the complete course's combined bonuses and penalties before rebuilding or loading a blueprint. Validate material costs if authored later: build currently spends GP only. | Avoids buying an obstacle that weakens the intended build. |
| Summoning / Beastbinding | Show familiar charge runway and synergy requirements; offer an explicit refill from owned tablets. | Prevents a build quietly losing its support bonus. |
| Astrology | Offer a sortable comparison of affordable stars, their bonuses, and their downstream rate changes. | Makes permanent upgrades easier to evaluate. |
| Archaeology | Show unique discoveries separately from duplicate donations and highlight affordable museum purchases. | Gives excavation a clearer short-term goal. |
| Cartography | Fix repeat XP, distinguish travel from surveying, and give POIs recognizable reward categories. Verify surveying empty hexes: 16 records contain `poi: null`, while survey expects a Dictionary. | Strengthens exploration and removes misleading or invalid interactions. |
| Echo Keeping, Wayfolding, Fermentation, Customcraft, Lostfinding | Surface their current input/output chains and give each a distinct decision using existing systems: target a useful support item, compare failure/quality choices, or select a supply chain. | Their definitions largely use the shared recipe engine; distinct decisions will give them identity beyond another XP bar. |
| Ranching | Show feed hours remaining, next produce, breeding readiness, and ordinary/rare stock distinctly; allow stocking and feeding in batches. | Makes six pens manageable and the rare-animal progression legible. |
| Inscription | Display research prerequisites, quality odds, replacement effects, and buff expiry before using a text. | Prevents accidentally replacing a stronger buff or researching an unneeded recipe. |
| Engineering | Show hourly outputs, fuel cost, material runway, and stalled reason per worker. Test Farmhand production over equal online/offline windows. | Players can judge whether automation saves resources; coarse offline slices deserve explicit parity checks. |
| Enchanting | Show the actual mastery-adjusted cost and before/after item stats, including exactly which enchant will be replaced. | The current hint uses nominal tier costs even when discounts change the real cost. |
| Dreamwalking | Preview the selected offline split, expected XP/Essence, and lost waking output; show the actual price/reward of an event before acceptance. | Clarifies the cost of allocating time and accepting the shadow's offer. |
| Mastery, skillcapes, progression | Explain each next mastery checkpoint and show the benefit of keeping versus spending pool XP. Recompute leveling estimates with realistic supply chains and bonuses. | Preserves long progression while exposing useful near-term milestones. |
| Pets / collection | Make passive pet rolls scale with elapsed training time or equivalent completed cycles. Keep a readable discovery history. | Fast skills roll per action, Ranching per collection, and Dreamwalking once per offline session. The current 0.4% per-roll chance means very different waits depending on collection/login habits. [PetManager.gd](C:/Godot/melvor-clone-godot/scripts/autoload/PetManager.gd:18). |
| Settlement / trader / worship | Fix clocks and counters; then show the next affordable structure, resource bottleneck, and payoff time. | Builds connect the settlement to useful main-game supplies. |
| Storage, equipment, food, shops, loot filters | Fix gear integrity first. Keep quantity controls and supply protection visible; extend set previews to food, prayers, and familiars with explicit ownership checks. | Loadouts become trustworthy and consumables easier to manage. |
| Action Queue | Add an upfront preview of each step's inputs, expected outputs, and stop condition; explain unmet research and material requirements. | A long queue becomes reviewable before it starts. Offline quantity targets can currently overshoot by one 30-second slice. |
| Combat Simulator | Show assumptions beside the survival estimate and add finite-supply mode using equipped foods, remaining prayer points, ammo, and runes. Add parity cases for special attacks and enchanted statuses. | The existing simulator assumes unlimited owned food and prayer points, so its results should not be mistaken for sustainable unattended combat. |
| Tasks, milestones, goals, tutorial | Chain existing tasks into visible short objectives and teach the five new systems when relevant. Extend item-source hints to variants, disenchanting, breeding, and Dream Bazaar rewards. | These sources are not all covered by the generic recipe/drop/shop resolver. [Goals.gd](C:/Godot/melvor-clone-godot/scripts/autoload/Goals.gd:412). |
| Prestige / Ascendancy | Rename the gate's “lifetime XP” to “this run's XP,” or track true lifetime XP; preview what resets and what survives. | The gate sums current skill XP, which is reset on ascension. |
| Saves, offline, modes, settings | Keep atomic saves, backup recovery, and exactly-once offline markers. Add mid-raid and enchanted-loadout save round trips, consistent passive clocks, and explicit mode-rule summaries. | These are the boundaries most likely to lose or duplicate progress. |
| UI, assets, audio, notifications | Keep sprites, bars, and context-specific tooltips; show new unlocks in a persistent history after the popup expires. Match audio feedback to reduced-motion and sound preferences. | Celebrations should remain useful after their five-second appearance. |
| DataLoader, EventBus, modifiers, validators, tests | Extend validation to every new skill-system record and use the seven reproductions as fix-specific regression checks. Maintain one authoritative reward/stat-recording path. | Existing tests passing did not cover the gear, raid, and trader boundaries found here. |

## Recommended order

1. Gear integrity and raid completion/persistence.
2. Cartography XP and settlement clocks/progress counters.
3. Rates, ETAs, and supply-runway displays across skills and combat.
4. Enchanting previews, trustworthy loadouts, and passive pet-rate consistency.
5. Connected task chains and more distinctive choices within the existing skills.

These changes improve the systems already present. No further leveling rebalance or gameplay redesign was applied in this audit.
