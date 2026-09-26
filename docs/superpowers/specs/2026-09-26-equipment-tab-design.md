# Equipment tab — design

## Intent
- Add an Equipment tab as the 4th pinned row under Combat (Shop, Provisioner,
  Combat, Equipment, same style).
- The tab shows everything equipment: current loadout, combat stats,
  equippable bank items, and saved equipment sets.
- Scope is approach A only: new screen + panel reusing `EquipmentManager`.
  BankPanel equipping stays as-is. No new items, no stat-formula changes.

## §1 — Routing/nav (approved)
- `scripts/ui/Screens.gd`: `EQUIPMENT := "equipment"`, `LABELS` entry
  `Equipment`, `ICONS` entry reusing kind `items`, `ORDER` entry placed
  directly after `COMBAT`.
- `scripts/ui/MainUI.gd`: `PINNED_SCREENS` becomes
  `[STORE, PROVISIONER, COMBAT, EQUIPMENT]`; the existing `_add_pinned_nav`
  loop renders sidebar and drawer with no further nav code. `_icon_kind_for`
  / `_icon_id_for` gain an `EQUIPMENT` branch (items kind).
- `MainUI.PANEL_SCRIPTS`: `EQUIPMENT → EquipmentPanel`.
- Success: pressing Equipment opens the new screen with gold highlight;
  sidebar and drawer mirror it; no duplicate entry under GAME.

## §2 — Panel (approved)
- New `scripts/ui/panels/EquipmentPanel.gd` (`extends VBoxContainer`) with
  `navigated` / `context_changed` signals, `refresh()` subscribed to
  `state_refreshed`, `bank_changed`, and `item_equipped`. Four
  `UIStyle.section`s:
- **Loadout:** one row per slot from `EquipmentManager.get_equipped()`:
  item name + slot name + Unequip button (`EquipmentManager.unequip(slot)`).
  Empty slots render muted so the 15-slot shape stays visible.
- **Stats:** read-only labels from `get_attack_bonus()`,
  `get_strength_bonus()`, `get_defence_bonus()`,
  `get_weapon_attack_speed()`, `get_weapon_special_attack()`.
- **Equippable:** bank items with `item_type == "equipment"`, grouped by
  `equipment_slot`, each with an Equip button calling
  `EquipmentManager.equip(item_id)` — same requirement/storage guards and
  warn toast as BankPanel's quick button. Equipped items show an
  `Equipped` badge instead of a second button.
- **Sets:** saved sets via `add_set` / `save_current_to_set` / `load_set`
  with Save-current and per-set Load buttons; invalid loads toast and
  refresh without touching the current loadout.

## Error handling
- Equip/load failures toast (`warn`) and refresh; the panel never blanks.
- Two-handed weapons keep `EquipmentManager` shield-slot behavior unchanged.
- Unmet requirements reuse the existing "Requirements not met" notice path.

## Testing
- `--validate`: 0 errors. `--tests`: full suite passes.
- Manual: equip/unequip round-trip from the tab, stat labels move with the
  loadout, set save/load restores, drawer entry opens the same screen.

## Deferred
- In-Combat quick-swap, set auto-switch per area, equipment comparison
  tooltips: separate specs when wanted.
