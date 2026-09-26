# Settlement tab + build-XP — design

## Intent
- Give Settlement its own sidebar tab between the non-combat skill list and GAME.
- Make Settlement feel like building: constructing/upgrading structures grants
  Settlement XP through the existing level-up flow.
- Scope is approach A only: XP on manual build. No hourly trickle (B deferred),
  no SkillManager-action rebuild (C dropped), no new items.

## §1 — Settlement tab (approved)
- `scripts/ui/MainUI.gd`, `_build_sidebar()` + `_populate_drawer()`: insert a
  `SETTLEMENT` section (header label + one button opening `Screens.SETTLEMENT`)
  after `_add_skill_links()`, before the `GAME` label.
- Reuse pinned-tab wiring: `Screens.label_for()`, `AssetRegistry.icon()` via
  `_icon_kind_for/_icon_id_for`, `_show_screen()`; register in `_nav_buttons`
  so highlighting/badges work; drawer variant closes the drawer on press.
- Skip `Screens.SETTLEMENT` in the `GAME` loop to avoid a duplicate entry.
- No change to `Screens.ORDER`, panels, or icons.
- Success: exactly one Settlement entry, positioned after non-combat skills in
  sidebar and drawer.

## §2 — XP on build (approved)
- `scripts/autoload/TownshipManager.gd`, `build()`: after a successful upgrade
  (past `can_build` + max-level guards), grant
  `PlayerData.add_xp("township", 25.0 × new_level × ModifierManager.get_skill_xp_multiplier("township"))`.
- Failed, unaffordable, and max-level builds grant nothing. Hourly
  `produce_tick()` and offline `advance_offline()` grant nothing (manual
  building only — no idle-XP inflation).
- `data/skills.json` township stays passive with zero actions; XP flows through
  the existing `add_xp` → level-up → `state_refreshed` path, so sidebar levels
  and toasts update with no UI changes.
- Example: Lumber Yard → L1 grants ~25 XP (× multiplier); → L5 grants ~125 XP.

## Error handling
- Unknown building, failed validation, and max-level paths return before any
  XP line runs; no partial-XP states. XP uses the same guarded `add_xp` every
  other skill uses.

## Testing
- `--validate`: 0 errors (no data-shape changes beyond code).
- `--tests`: full suite passes.
- Manual: build Lumber Yard L1 → ~25 township XP + level-up toast path;
  failed build (insufficient stores) → 0 XP; sidebar shows one Settlement tab
  between non-combat skills and GAME in wide and drawer layouts.

## Deferred
- B (hourly/population trickle) and panel-stage visuals: separate specs when
  wanted. New-item buildings (Phase C pattern): separate spec per skill.
