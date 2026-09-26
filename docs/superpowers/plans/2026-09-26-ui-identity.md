# UI Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle Emberreach into a distinctive ember-and-charcoal dark-fantasy UI with code-driven motion, without changing any game logic.

**Architecture:** Token-value swap in `UITokens.gd` (names unchanged), art-aware `StyleBoxTexture` fallback in `UIStyle.surface_box()`, one new `Motion.gd` tween helper consumed by existing widgets. All hooks respect `UITokens_motion_reduced()`.

**Tech Stack:** Godot 4.7 GDScript, StyleBoxFlat/StyleBoxTexture, Tween.

**Spec:** `docs/superpowers/specs/2026-09-26-ui-combat-activities-overhaul-design.md` (§3)

## Global Constraints

- No game-logic changes in this plan. Signals, formulas, save format untouched.
- Token names in `UITokens.gd` stay unchanged; only values change.
- Every animation checks the existing motion-reduced setting first.
- Verification after every task: `godot --headless --path . -- --validate` and `godot --headless --path . -- --tests` stay green.
- Frequent commits, one per task.

## Review Focus

- Motion-reduced ON must equal today's static UI pixel-for-pixel — pinned in Task 4 tests.
- Missing font file must fall back to the default font, never crash — pinned in Task 2 tests.
- Missing `_9slice.png` must fall back to StyleBoxFlat, never crash — pinned in Task 3 tests.
- Floater pool must not leak Labels over a 10-minute combat session — pinned in Task 4 tests.
- 420px minimum window width must not clip the sidebar accent or toasts — pinned in Task 5 tests.

---

### Task 1: Baseline screenshots

**Files:**
- Modify: none (run only)

**Interfaces:**
- Consumes: `MainUI._run_screenshot_sweep()` (existing)
- Produces: `shots/baseline/` reference images for Task 6 comparison

- [ ] **Step 1: Run the baseline sweep**

Run: `godot --path . -- --shot shots/baseline` (renders the real window, so this
needs a display — not headless-only CI; the flag is what `MainUI._handle_cli` maps to `_run_screenshot_sweep`)
Expected: exit 0, PNGs written under `shots/baseline/`

- [ ] **Step 2: Commit the baseline**

```bash
git add shots/baseline
git commit -m "chore: baseline UI screenshots pre-identity-pass"
```

### Task 2: Ember token palette + fonts

**Files:**
- Modify: `scripts/ui/UITokens.gd` (color const values only)
- Modify: `scripts/ui/UIStyle.gd` (`build_theme()` font registration only)
- Create: `assets/fonts/ember_display.ttf`, `assets/fonts/ember_text.ttf` (OFL-licensed)
- Test: `scripts/tests/TestRunner.gd` (new `test_identity_theme_builds`)

**Interfaces:**
- Consumes: `UIStyle.build_theme()` existing signature
- Produces: same `Theme` with new colors/fonts; no caller changes

- [ ] **Step 1: Write the failing test**

```gdscript
func test_identity_theme_builds() -> void:
	var theme: Theme = UIStyle.build_theme()
	assert_not_null(theme, "build_theme must return a Theme")
	assert_true(theme.has_font("display", ""), "display font registered")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -- --tests`
Expected: FAIL (`has_font("display", "")` false)

- [ ] **Step 3: Swap palette values + register fonts with fallback**

In `UITokens.gd`, replace only the `Color(...)` values: background ramp to warm
charcoal (`#141010` deep → `#1e1611` workspace), surfaces warm umber, text
parchment `#e8dcc3` / muted `#9a8c72`, accent ember-orange `#e2622b`, gold stays
for rarity-tier highlights, teal/amber/red state colors desaturated one step.
In `UIStyle.build_theme()`, load the two TTFs with `load()` guarded by
`ResourceLoader.exists()`; on missing file keep the default font:

```gdscript
if ResourceLoader.exists("res://assets/fonts/ember_display.ttf"):
	theme.set_font("display", "", load("res://assets/fonts/ember_display.ttf"))
```

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS, 0 errors

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/UITokens.gd scripts/ui/UIStyle.gd assets/fonts scripts/tests/TestRunner.gd
git commit -m "feat(ui): ember palette + display/text fonts with fallback"
```

### Task 3: Art-aware surfaces with StyleBoxFlat fallback

**Files:**
- Modify: `scripts/ui/UIStyle.gd` (`surface_box()`, add `NINE_SLICE_MARGINS` lookup in `UITokens.gd`)
- Test: `scripts/tests/TestRunner.gd` (new `test_surface_box_falls_back`)

**Interfaces:**
- Consumes: `UIStyle.surface_box(kind, accent)` existing signature
- Produces: `StyleBoxTexture` when `res://assets/ui/<kind>_9slice.png` exists, else identical `StyleBoxFlat` as today

- [ ] **Step 1: Write the failing test**

```gdscript
func test_surface_box_falls_back() -> void:
	var sb: StyleBox = UIStyle.surface_box("nonexistent_kind_xyz")
	assert_true(sb is StyleBoxFlat, "missing art must fall back to StyleBoxFlat")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -- --tests`
Expected: FAIL (no fallback branch yet — or passes trivially; if it passes, keep it as a pin test and continue)

- [ ] **Step 3: Implement art-aware branch**

```gdscript
static func surface_box(kind: String = "panel", accent: bool = false) -> StyleBox:
	var path: String = "res://assets/ui/%s_9slice.png" % kind
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		var m: int = UITokens.NINE_SLICE_MARGINS.get(kind, 12)
		sb.margin_left = m; sb.margin_right = m; sb.margin_top = m; sb.margin_bottom = m
		sb.expand_margin_left = m; sb.expand_margin_right = m
		sb.expand_margin_top = m; sb.expand_margin_bottom = m
		return sb
	return _flat_fallback(kind, accent)  # today's StyleBoxFlat body, moved verbatim
```

Add `const NINE_SLICE_MARGINS := {"panel": 12, "button": 8, "chip": 6}` to `UITokens.gd`.

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS, 0 errors

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/UIStyle.gd scripts/ui/UITokens.gd scripts/tests/TestRunner.gd
git commit -m "feat(ui): art-aware surfaces with StyleBoxFlat fallback"
```

### Task 4: Motion.gd helper (tweens, floaters, pulses)

**Files:**
- Create: `scripts/ui/Motion.gd` (`class_name Motion extends RefCounted`, static funcs)
- Test: `scripts/tests/TestRunner.gd` (`test_motion_reduced_disables`, `test_floater_pool_bounded`)

**Interfaces:**
- Consumes: `ToastStack.UITokens_motion_reduced()` pattern (motion-reduced check)
- Produces: `Motion.tween_bar(bar, to_value)`, `Motion.spawn_floater(parent, text, color)`, `Motion.pulse(control)`, `Motion.fade_rise(control)` — all no-ops when motion is reduced

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_motion_reduced_disables() -> void:
	Motion.force_reduced = true
	var c := Control.new()
	Motion.fade_rise(c)
	assert_equal(c.modulate.a, 1.0, "reduced motion must leave alpha untouched")
	Motion.force_reduced = false
	c.free()

func test_floater_pool_bounded() -> void:
	var parent := Control.new()
	for i in 40:
		Motion.spawn_floater(parent, "1", Color.WHITE)
	assert_true(parent.get_child_count() <= 12, "floater pool must stay bounded")
	parent.free()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . -- --tests`
Expected: FAIL (`Motion` not defined)

- [ ] **Step 3: Implement Motion.gd**

`class_name Motion extends RefCounted`, `static var force_reduced := false` (test hook).
Every func returns immediately if `force_reduced` or the reduced-motion setting is on.
`spawn_floater` keeps a per-parent pool: reuse a hidden Label if one exists, else
create; cap 12 children; tween up 28px + fade over 0.7s then hide (never `queue_free`
during iteration — hide and reuse). `tween_bar` tweens `ProgressBar.value` 0.25s.
`pulse` loops scale 1.0↔1.04 (kill tween first via stored meta). `fade_rise` sets
`modulate.a = 0`, `position.y += 6`, tweens back over 0.18s.

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS, 0 errors

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/Motion.gd scripts/tests/TestRunner.gd
git commit -m "feat(ui): Motion tween/floater helper with reduced-motion no-ops"
```

### Task 5: Hook motion into widgets and shell

**Files:**
- Modify: `scripts/ui/Widgets.gd` (`progress_bar` → `Motion.tween_bar` on value set)
- Modify: `scripts/ui/panels/CombatPanel.gd` (floaters on `player_attacked`/`monster_attacked`, HP pulse < 25%, monster hit-flash)
- Modify: `scripts/ui/MainUI.gd` (`_show_screen` → `Motion.fade_rise` on workspace)
- Modify: `scripts/ui/ToastStack.gd` (`_build` → slide-in via `Motion.fade_rise`)
- Modify: `scripts/ui/SidebarNav.gd` (accent bar slide on selection change)

**Interfaces:**
- Consumes: `Motion.*` from Task 4, existing signal subscriptions in each file
- Produces: no signature changes; visual behavior only

- [ ] **Step 1: Wire each hook (no new tests — covered by suite + screenshots)**

`Widgets.progress_bar`: after setting `bar.value`, call `Motion.tween_bar(bar, value)`.
`CombatPanel`: in existing `player_attacked`/`monster_attacked` handlers, call
`Motion.spawn_floater(avatar_parent, text, color)` (crit = gold, bigger via `add_theme_font_size_override` before spawn — keep one line); HP bar `Motion.pulse` when fraction < 0.25; monster `TextureRect.modulate` flash white 0.08s on hit.
`MainUI._show_screen`: after `_work_area(panel)` returns, `Motion.fade_rise(work)`.
`ToastStack._build`: `Motion.fade_rise(entry)` on creation.
`SidebarNav`: tween the existing accent bar's `position.y` to the selected button.

- [ ] **Step 2: Run full verification**

Run: `godot --headless --path . -- --tests`, then `--validate`, then `--smoke`
Expected: all PASS

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/Widgets.gd scripts/ui/panels/CombatPanel.gd scripts/ui/MainUI.gd scripts/ui/ToastStack.gd scripts/ui/SidebarNav.gd
git commit -m "feat(ui): motion hooks in bars, combat, transitions, toasts, nav"
```

### Task 6: After screenshots + phase gate

**Files:**
- Modify: none (run only)

- [ ] **Step 1: Run after-sweep and all gates**

Run: `godot --path . -- --shot shots/after-phase1`
Expected: exit 0
Run: `godot --headless --path . -- --tests`, `--validate`, `--smoke`, `--selftest`
Expected: all PASS (tests count ≥ pre-phase count)

- [ ] **Step 2: Commit screenshots**

```bash
git add shots/after-phase1
git commit -m "chore: post-identity UI screenshots"
```
