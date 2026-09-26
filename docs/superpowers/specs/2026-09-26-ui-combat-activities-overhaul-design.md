# Emberreach overhaul: UI identity, combat decisions, activity layers

Date: 2026-09-26 | Approach: A (identity-first vertical phases) | Status: approved brief

## 1. Intent

Emberreach works but feels like a dev dashboard: flat panels, auto-only combat
with no loadout choices, and click-wait-repeat skill loops. This overhaul keeps
the idle core (offline parity is non-negotiable) and adds: a distinctive
dark-fantasy identity, preparation-depth combat, and decision layers on skill
loops. Layout shell (top bar + sidebar + workspace + activity strip) stays.

Assumptions confirmed with owner: idle combat ("idle with real decisions"),
no-reflex activity decisions, code-only UI restyle (owner supplies art later
by filename), old saves migrate (no wipe).

## 2. Constraints (hard)

- Data-driven: new content is JSON (`abilities.json`, `events.json`). No hardcoded content.
- All stat math via `ModifierManager`. New effect keys reuse the existing vocabulary.
- Offline parity: every new roll uses the existing seeded `_rng` streams and the
  same tick functions, so `simulate_elapsed` / `OfflineProgression` replay exactly.
- Dual-engine parity: `CombatManager` and `CombatSimulator` stay in lockstep;
  new state travels via the snapshot pattern (as hazards did).
- Saves migrate: v2 -> v3 with defaults (`_migrate_2_to_3`); old saves load.
- Green stays green: `--validate`, `--smoke`, `--selftest`, full test suite pass
  at the end of each phase.

## 3. Phase 1 — UI identity (no logic changes)

- `UITokens.gd`: swap values to ember/charcoal/parchment ramp; token names unchanged.
- Two OFL TTFs into `assets/fonts/`; registered in `UIStyle.build_theme()`.
- `UIStyle.surface_box()`: art-aware — `assets/ui/<kind>_9slice.png` via
  `StyleBoxTexture` when present (margins in UITokens), else current StyleBoxFlat.
- New `scripts/ui/Motion.gd`: tweened progress bars, HP pulse < 25%, pooled
  damage/heal/crit floaters, `_show_screen` fade+rise, toast slide-in, sidebar
  accent slide, shared button hover/press micro-effect, monster hit-flash,
  death shake.
- Verify: `_run_screenshot_sweep` before/after; all checks green.

## 4. Phase 2 — Combat decisions

- `data/abilities.json`: `{id, style, req_levels, unlock, effect, trigger_chance,
  cooldown}`. Effects limited to: `max_hit_percent`, `interval_percent`,
  `crit_chance`, `apply_status`, `heal_on_hit_fraction`.
- Loadout: `N = 1 + floor(Defence/25)`, cap 4; stored per strategy.
- Rolls inside `_player_attack()` on `CombatManager._rng`; mirrored in simulator
  snapshot. Strategies: `{name, ability_loadout, food_threshold, special_bias,
  protection_prayer_auto}`, one assigned per area/dungeon. `food_threshold` is
  an HP fraction overriding the auto-eat tier threshold (0 = tier default).
  `special_bias` multiplies the weapon special proc chance
  (`eager` x2 capped at 100% / `normal` x1 / `hold` x0) — specials today are pure
  chance procs with no energy meter, so a multiplier is the full policy surface.
- Monster passives (whitelist + validator + parity tests): `rage` (dmg scales as
  monster HP falls), `veil` (flat evasion), `leech` (heals fraction dealt).
- UI: strategy bar + loadout picker + trigger feed in `CombatPanel`.
- New signals: `ability_triggered`, `strategy_changed`.
- Verify: live-vs-sim parity tests for abilities + 3 passives; smoke/selftest extended.

## 5. Phase 3 — Activity decision layers

- `data/events.json`, per-skill pools: `{id, weight, min_level, kind}`.
  Kinds: `spawn` (bonus target, N actions, 1-click switch, auto-expires, shown in
  `ActivityStrip`) and `card` (2-button safe/greedy choice; pauses loop online,
  timeout applies policy).
- New `EventDirector` autoload hooks `SkillManager._post_action`; rolls on the
  same `_rng` stream; offline/timeouts resolve via policy through the same function.
- Policies per category (`risk`/`bonus`): `safe` (default) / `greedy` / `manual`.
  One policy row in skill detail panel.
- Momentum streak (single global rule): consecutive successes build +XP% to a cap;
  failure resets. XP only.
- Exemplar data for woodcutting, fishing, mining, cooking; all other pools ship
  empty (no behavior change). New signals: `event_offered`, `event_resolved`.
- Verify: offline-vs-online action-count/XP equivalence tests with seeded RNG;
  validator covers `events.json`.

## 6. Migration + rollout

- `_migrate_2_to_3`: empty loadouts, one default strategy, all policies `safe`.
- Order: phase 1 -> verify -> phase 2 -> verify -> phase 3 -> verify. Each phase
  independently shippable. Art swap by the owner later touches zero code.

## 7. Out of scope

Active/twitch combat, skill minigames with reflexes, new activity systems
(arena/market), map-based hub navigation, save wipe.
