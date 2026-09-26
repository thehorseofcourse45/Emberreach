# Settlement tab + build-XP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated Settlement sidebar tab and grant Settlement XP on every successful structure build.

**Architecture:** Two one-spot edits following existing patterns: a `_add_settlement_nav()` helper in `MainUI.gd` mirroring `_add_pinned_nav()`, and one `PlayerData.add_xp()` line in `TownshipManager.build()` mirroring `CartographyManager.survey()`. No data-shape or economy changes.

**Tech Stack:** Godot 4.7 GDScript; headless verification via `--validate` and `--tests`.

**Spec:** `docs/superpowers/specs/2026-09-26-settlement-tab-xp-design.md`

## Global Constraints

- Godot 4.7 GDScript only; no new scenes, autoloads, or dependencies.
- `Screens.ORDER` stays untouched; skip `Screens.SETTLEMENT` in the GAME loop.
- XP only on successful manual builds: failed, unaffordable, and max-level builds grant nothing; `produce_tick()` and `advance_offline()` grant nothing.
- XP formula verbatim: `25.0 × new_level × ModifierManager.get_skill_xp_multiplier("township")`.
- `data/skills.json` township stays passive with zero actions.

## Review Focus

- Drawer layout at 420px omits the Settlement tab while the sidebar shows it; builder expects parity between the two.
- Pressing the Settlement tab highlights nothing because the button was never registered in `_nav_buttons`; builder expects gold highlight like every other tab.
- A second Settlement row still appears under GAME because the GAME loop was not told to skip it; builder expects exactly one entry.
- A failed build (insufficient stores) still grants XP because the XP line runs before the `can_build` guard; builder expects zero XP on failure.
- An offline catch-up tick grants XP because XP was added to `produce_tick` instead of `build`; builder expects ticks to grant nothing.

---

### Task 1: Settlement sidebar tab

**Files:**
- Modify: `C:\Godot\melvor-clone-godot\scripts\ui\MainUI.gd:141-161` (`_build_sidebar` list assembly + GAME loop)
- Modify: `C:\Godot\melvor-clone-godot\scripts\ui\MainUI.gd:470-498` (`_populate_drawer`)
- Test: headless `--tests` combat-navigation suite + manual wide/narrow check

**Interfaces:**
- Consumes: `Screens.SETTLEMENT`, `Screens.label_for()`, `_icon_kind_for()`, `_icon_id_for()`, `_show_screen()`, `_nav_buttons`, `_drawer`
- Produces: `_add_settlement_nav(container, drawer)` used by both `_build_sidebar()` and `_populate_drawer()`

- [ ] **Step 1: Add the `_add_settlement_nav` helper after `_add_pinned_nav` (ends line 197)**

```gdscript
func _add_settlement_nav(container: VBoxContainer, drawer: bool = false) -> void:
	container.add_child(UIStyle.label("SETTLEMENT", true, UITokens.FONT_MICRO))
	var b := Button.new()
	b.text = Screens.label_for(Screens.SETTLEMENT)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, UITokens.H_HEADER)
	b.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
	b.icon = AssetRegistry.icon(_icon_kind_for(Screens.SETTLEMENT), _icon_id_for(Screens.SETTLEMENT))
	b.add_theme_constant_override("icon_max_width", UITokens.ICON_SM)
	b.tooltip_text = Screens.label_for(Screens.SETTLEMENT)
	b.pressed.connect(func():
		if drawer:
			_drawer.visible = false
		_show_screen(Screens.SETTLEMENT, {}))
	container.add_child(b)
	if not drawer:
		_nav_buttons[Screens.SETTLEMENT] = b
```

- [ ] **Step 2: Call it between skill links and GAME in `_build_sidebar`**

```gdscript
	_add_skill_links(_sidebar_list)
	_sidebar_list.add_child(HSeparator.new())
	_add_settlement_nav(_sidebar_list)
	_sidebar_list.add_child(HSeparator.new())
	_sidebar_list.add_child(UIStyle.label("GAME", true, UITokens.FONT_MICRO))
```

- [ ] **Step 3: Skip SETTLEMENT in both GAME loops so it appears exactly once**

```gdscript
		if screen == Screens.SKILLS or screen in PINNED_SCREENS or screen == Screens.SETTLEMENT:
			continue
```

Apply in `_build_sidebar()` (line 148) and `_populate_drawer()` (line 488).

- [ ] **Step 4: Mirror in `_populate_drawer` after `_add_skill_links(col, true)`**

```gdscript
	_add_skill_links(col, true)
	col.add_child(HSeparator.new())
	_add_settlement_nav(col, true)
	col.add_child(HSeparator.new())
	col.add_child(UIStyle.label("GAME", true, UITokens.FONT_MICRO))
```

- [ ] **Step 5: Parse-check the edited script**

Run: `& "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Godot\melvor-clone-godot" -- --validate 2>&1 | Select-Object -First 5`
Expected: `=== content validation: 0 errors, 0 warnings` (plus INFO notes)

### Task 2: Settlement XP on build

**Files:**
- Modify: `C:\Godot\melvor-clone-godot\scripts\autoload\TownshipManager.gd:184-191` (`build()`, after level increment)
- Test: headless `--tests` full suite

**Interfaces:**
- Consumes: `PlayerData.add_xp(skill_id: String, amount: float)`, `ModifierManager.get_skill_xp_multiplier(skill_id: String)`, `level_of()`
- Produces: township XP via the existing `add_xp` → level-up → `state_refreshed` path (no new surface)

- [ ] **Step 1: Grant XP after the level increment in `build()`**

```gdscript
	buildings[building_id] = level_of(building_id) + 1
	PlayerData.add_xp("township", 25.0 * float(level_of(building_id)) * ModifierManager.get_skill_xp_multiplier("township"))
	population = int(productions_population())
```

The line sits after the increment (so `level_of()` is the new level) and before `_reregister_modifiers()`; all failure returns above (lines 171, 175, 180) exit before it.

- [ ] **Step 2: Confirm no other function grants township XP**

Run: `Select-String -Path "C:\Godot\melvor-clone-godot\scripts\autoload\TownshipManager.gd" -Pattern "add_xp"`
Expected: exactly one hit, inside `func build(`.

- [ ] **Step 3: Run validation**

Run: `& "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Godot\melvor-clone-godot" -- --validate 2>&1 | Select-Object -First 5`
Expected: 0 errors.

### Task 3: Verify tab placement and XP behavior

**Files:**
- Test: headless `--tests` (combat-navigation + general-store suites cover sidebar invariants)

**Interfaces:**
- Consumes: Tasks 1 and 2
- Produces: green verification

- [ ] **Step 1: Run the full test suite**

Run: `& "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Godot\melvor-clone-godot" -- --tests 2>&1 | Select-String -Pattern "checks passed|checks failed|ALL TESTS" | Select-Object -Last 5`
Expected:
```
checks passed: 307
checks failed: 0
ALL TESTS PASSED (307 checks)
```

- [ ] **Step 2: Manual spot check (needs a display, not `--headless`)**

Open the project, confirm: one Settlement tab between NON-COMBAT SKILLS and GAME; pressing it opens the Settlement screen with gold highlight; building Lumber Yard L1 adds ~25 township XP; a failed build adds 0 XP.
