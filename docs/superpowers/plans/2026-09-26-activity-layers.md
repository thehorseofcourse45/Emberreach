# Activity Layers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add seeded, offline-replayable decision layers to skill loops — bonus spawns, choice cards with auto-decide policies, and one global momentum-streak XP rule.

**Architecture:** `data/events.json` loaded by `DataLoader`; one new `EventDirector` autoload called from `SkillManager._post_action()` on the existing `_rng` stream; offline/timeout resolution calls the same resolve function with the stored policy. Empty pools = no behavior change.

**Tech Stack:** Godot 4.7 GDScript.

**Spec:** `docs/superpowers/specs/2026-09-26-ui-combat-activities-overhaul-design.md` (§5, §6)

## Global Constraints

- No new RNG sources: all rolls on `SkillManager._rng` in action-completion order, so `simulate_elapsed` and offline catch-up replay exactly.
- Signals only fire when `not SimulationMode.is_silent()` (existing pattern).
- Skills with empty event pools behave byte-identically to today.
- Save keys (`event_policies`, `momentum`) already defaulted by the combat plan's `_migrate_2_to_3`; this plan only reads/writes them.
- Verification after every task: `--validate` and `--tests` green.
- Frequent commits, one per task.

## Review Focus

- A `card` must never deadlock the loop if the player walks away — timeout always applies the policy — pinned in Task 3 tests.
- Offline resolution must equal online-with-default-policy resolution for the same seed — pinned in Task 4 tests.
- Momentum must reset on failure and never exceed its cap — pinned in Task 5 tests.
- Switching to a `spawn` must not duplicate inputs/outputs or double-consume charges — pinned in Task 3 tests.
- Unknown event kinds must fail validation, not crash the loop — pinned in Task 2 tests.

---

### Carry-in constraints from the combat-decisions plan (MUST be honoured)

1. **`event_policies` and `momentum` are NOT reliably present in a v3 save.** The combat plan's
   `_migrate_2_to_3` writes defaults for both, but `PlayerData.serialize()` has no field for either,
   so the write-back drops them before the save persists — and the save is already stamped v3, so the
   migration chain never runs again. Verified end to end: `load_game()` → `save_game()` →
   `build_save_data()` → `PlayerData.serialize()`.
   **Therefore: this plan must default both on ABSENCE in `deserialize`, unconditionally, for every
   save including one this build just wrote.** Do not assume the migration seeded them.
2. `ContentValidator.check_strategy_record` returns `Array[{code, message}]`, not bare strings.
3. `CombatManager.set_loadout` enforces `req_levels` via `PlayerData.get_level` and clamps to the
   slot cap `mini(4, 1 + int(defence/25))`. A preset may legitimately name a valid-but-locked ability;
   the UI should show the EFFECTIVE loadout, not the preset's nominal one.
4. `CombatManager.strategy_for()` returns a deep copy. `CombatManager.active_loadout` does NOT — it
   is handed out by reference, so do not mutate what it returns.
5. The full suite takes ~30 seconds, not minutes. The top-level check count is blind to assertion
   count for the simulator sub-suite (`_report_suite` folds a sub-suite into one check) — judge new
   pins by mutation evidence, not by the total.
6. Probe Godot 4.7 APIs live. Known traps in this repo: `StyleBoxTexture` uses `content_margin_*`;
   `Object.CONNECT_ONE_SHOT`; GDScript lambdas capture locals **by value** (use an object for
   callbacks that must read live state); a `frames`-counted wait is machine-speed dependent.
7. PREREQUISITE: this plan's Task 5 (momentum) must add a `PlayerData` field for `momentum` and Task 3
   one for `event_policies`, or neither key survives a save/load cycle.

## Task 1: events.json exemplar content + DataLoader

**Files:**
- Create: `data/events.json` (pools for woodcutting, fishing, mining, cooking; 2–3 events each: 1 spawn + 1–2 cards)
- Modify: `scripts/autoload/DataLoader.gd` (load + `get_skill_events()`)
- Test: `scripts/tests/TestRunner.gd` (`test_events_load`)

**Interfaces:**
- Consumes: `DataLoader._load_file()` existing pattern
- Produces: `DataLoader.events: Dictionary`, `DataLoader.get_skill_events(skill_id: String) -> Array` ([] when absent)

- [ ] **Step 1: Write the failing test**

```gdscript
func test_events_load() -> void:
	var evs: Array = DataLoader.get_skill_events("woodcutting")
	assert_false(evs.is_empty(), "woodcutting pool must exist")
	assert_eq(DataLoader.get_skill_events("thieving"), [], "skills without pools get []")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -- --tests`
Expected: FAIL (`get_skill_events` not defined)

- [ ] **Step 3: Write data + loader**

Spawn shape: `{id, weight, min_level, kind: "spawn", target_action, duration_actions: 20, bonus: {xp_percent: 50.0, success_penalty: 10.0}}`.
Card shape: `{id, weight, min_level, kind: "card", title, text, choices: [{label: "Play safe", policy: "safe", effect: {xp_percent: 10.0}}, {label: "Push luck", policy: "greedy", effect: {xp_percent: 40.0, fail_chance: 25.0}}]}`.
Choices carry their `policy` tag so offline resolution can match them. In `DataLoader.gd`
add `events = _load_file("events.json")` and:

```gdscript
func get_skill_events(skill_id: String) -> Array:
	var pool: Variant = events.get(skill_id, [])
	return pool if typeof(pool) == TYPE_ARRAY else []
```

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add data/events.json scripts/autoload/DataLoader.gd scripts/tests/TestRunner.gd
git commit -m "feat(activities): events.json exemplars + DataLoader getter"
```

### Task 2: Event validation

**Files:**
- Modify: `scripts/core/ContentValidator.gd` (`check_event_record`)
- Test: `scripts/tests/TestRunner.gd` (`test_event_validation_rejects`)

**Interfaces:**
- Consumes: existing `_err(...)` pattern
- Produces: `ContentValidator.check_event_record(ev: Dictionary) -> Array`, wired into `--validate` for every pool

- [ ] **Step 1: Write the failing test**

```gdscript
func test_event_validation_rejects() -> void:
	var errs: Array = ContentValidator.check_event_record({"id": "x", "kind": "mystery"})
	assert_false(errs.is_empty(), "unknown kind must error")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -- --tests`
Expected: FAIL

- [ ] **Step 3: Implement validator**

`check_event_record` returns error strings: id non-empty; `kind` ∈ spawn/card;
`weight > 0`; `min_level >= 1` int; referenced `target_action` must exist in that
skill's `actions`; card needs exactly 2 choices each with `label`, `policy` ∈
safe/greedy, numeric `effect`; spawn needs `duration_actions >= 1` int and numeric
`bonus`. Wire per-skill pools into the existing validation loop.

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS, 0 errors

- [ ] **Step 5: Commit**

```bash
git add scripts/core/ContentValidator.gd scripts/tests/TestRunner.gd
git commit -m "feat(activities): events.json validation"
```

### Task 3: EventDirector (rolls, spawns, cards, policies)

**Files:**
- Create: `scripts/autoload/EventDirector.gd`
- Modify: `project.godot` (register autoload after `SkillManager`)
- Modify: `scripts/autoload/SkillManager.gd` (one call at end of `_post_action`)
- Modify: `scripts/autoload/EventBus.gd` (add `event_offered`, `event_resolved` signals)
- Test: `scripts/tests/TestRunner.gd` (`test_card_timeout_applies_policy`, `test_spawn_switch_no_double_consume`)

**Interfaces:**
- Consumes: `DataLoader.get_skill_events()`, `SkillManager` active action state, `PlayerData.event_policies`
- Produces: `EventDirector.roll_post_action(skill_id, action_id, rng: RandomNumberGenerator) -> Dictionary`; `EventDirector.resolve(event_id: String, choice_policy: String) -> Dictionary`; `EventDirector.accept_spawn() -> void`; `EventDirector.active_spawn: Dictionary`; test helper `EventDirector.offer_spawn_for_test(skill_id: String, action_id: String, duration: int) -> void`; `EventBus.event_offered(event: Dictionary)`, `EventBus.event_resolved(event_id: String, choice_policy: String)`

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_card_timeout_applies_policy() -> void:
	var ev := {"id": "c1", "kind": "card", "choices": [{"label": "S", "policy": "safe", "effect": {}}, {"label": "G", "policy": "greedy", "effect": {}}]}
	var res: Dictionary = EventDirector.resolve(ev, "TIMEOUT")
	assert_eq(res["choice_policy"], "safe", "timeout falls back to stored policy")

func test_spawn_switch_no_double_consume() -> void:
	SkillManager.start_action("woodcutting", "ACTION_A")
	EventDirector.offer_spawn_for_test("woodcutting", "ACTION_B", 5)
	EventDirector.accept_spawn()
	assert_eq(SkillManager.active_action_id, "ACTION_B", "accept switches target action")
	SkillManager.stop_action()
```
(ACTION_A/B are two real woodcutting action ids from `data/skills.json` — look them up first.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . -- --tests`
Expected: FAIL (`EventDirector` not defined)

- [ ] **Step 3: Implement EventDirector**

`roll_post_action`: pool = `DataLoader.get_skill_events(skill_id)`; empty → return {}.
Weighted roll on the passed `rng` (one `randf` per completed action — fixed stream cost).
On hit: `spawn` sets `active_spawn` (target action + actions-left) and emits
`event_offered` unless silent; `card` pauses via `SkillManager` pause flag if online
and manual policy, else resolves immediately. `resolve(ev, choice)`: `"TIMEOUT"` maps to
`PlayerData.event_policies[category]`; applies the matching choice effect through the
same function in all paths; emits `event_resolved` unless silent. `accept_spawn` switches
`SkillManager.active_action_id` to the spawn target (same single-slot mechanics, no extra
consumption — the next normal `perform_action` handles costs). Card effects apply as
one-shot modifiers to the next action only (xp_percent bonus or fail_chance), stored in
`_pending_card_effect`, consumed by `roll_post_action`'s caller. `SkillManager._post_action`
gains one trailing line: `EventDirector.roll_post_action(active_skill, active_action_id, _rng)`.

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/autoload/EventDirector.gd project.godot scripts/autoload/SkillManager.gd scripts/autoload/EventBus.gd scripts/tests/TestRunner.gd
git commit -m "feat(activities): EventDirector with spawns, cards, policies"
```

### Task 4: Offline equivalence test

**Files:**
- Test: `scripts/tests/TestRunner.gd` (`test_events_offline_equivalence`)

**Interfaces:**
- Consumes: `SkillManager.simulate_elapsed`, `EventDirector.resolve`
- Produces: proof that seeded offline replay matches online-with-default-policy

- [ ] **Step 1: Write the failing test**

```gdscript
func test_events_offline_equivalence() -> void:
	TestSupport.backup_save_files()
	PlayerData.event_policies = {"risk": "safe", "bonus": "safe"}
	SkillManager.seed_rng(99)
	SkillManager.start_action("woodcutting", "ACTION_A")
	var xp0: float = PlayerData.get_xp("woodcutting")
	var online: Dictionary = SkillManager.simulate_elapsed(600.0)
	var dxp_online: float = PlayerData.get_xp("woodcutting") - xp0
	TestSupport.restore_snapshot()
	SkillManager.seed_rng(99)
	SkillManager.start_action("woodcutting", "ACTION_A")
	var xp1: float = PlayerData.get_xp("woodcutting")
	var offline: Dictionary = SkillManager.simulate_elapsed(600.0)
	var dxp_offline: float = PlayerData.get_xp("woodcutting") - xp1
	SkillManager.stop_action()
	TestSupport.restore_snapshot()
	assert_eq(online["actions"], offline["actions"], "same seed, same action count")
	assert_eq(dxp_online, dxp_offline, "same seed, same xp")
```
(ACTION_A is a real woodcutting action id from `data/skills.json` — look it up first.
`simulate_elapsed` returns `{"actions": ..., ...}` and `TestSupport.backup_save_files` /
`restore_snapshot` both exist in `scripts/tests/TestSupport.gd`.)

- [ ] **Step 2: Run test to verify it fails or passes for the wrong reason**

Run: `godot --headless --path . -- --tests`
Expected: FAIL (no events wired yet — counts/XP diverge or the pool is empty)

- [ ] **Step 3: Fix determinism gaps**

If the counts/XP diverge, the cause is RNG-stream skew (a roll consumed in one path
but not the other) or wall-clock use. Fix by construction: every event roll consumes
exactly one `rng.randf()` per completed action in both paths; card timeouts resolve
through `resolve()` with the stored policy, never a separate code path. No new branches
that touch RNG in only one mode.

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/TestRunner.gd scripts/autoload/EventDirector.gd scripts/autoload/SkillManager.gd
git commit -m "test(activities): offline event equivalence pinned"
```

### Task 5: Momentum streak

**Files:**
- Modify: `scripts/autoload/SkillManager.gd` (streak counter, XP scaling)
- Test: `scripts/tests/TestRunner.gd` (`test_momentum_caps_and_resets`)

**Interfaces:**
- Consumes: success/failure outcome already computed in `perform_action`
- Produces: `SkillManager.momentum_streak: int`, `MOMENTUM_CAP_ACTIONS = 20`, `MOMENTUM_XP_PER_STEP = 0.5` (percent)

- [ ] **Step 1: Write the failing test**

```gdscript
func test_momentum_caps_and_resets() -> void:
	SkillManager.momentum_streak = 0
	for i in 30:
		SkillManager._apply_momentum_for_test(true)
	assert_eq(SkillManager.momentum_streak, 20, "streak caps at 20")
	SkillManager._apply_momentum_for_test(false)
	assert_eq(SkillManager.momentum_streak, 0, "failure resets streak")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -- --tests`
Expected: FAIL

- [ ] **Step 3: Implement one global rule**

In `perform_action`, on the success path increment `momentum_streak` (cap 20); on the
`_on_action_failure` path reset to 0. XP grant multiplies by
`1.0 + min(streak, 20) * 0.005`. Persist `momentum_streak` per skill in
`PlayerData.momentum` (keyed `skill_id`) in `serialize`/`deserialize`, following the
existing pattern — streaks survive reloads. Offline `simulate_elapsed` flows through
`perform_action`, so parity is automatic (covered by Task 4's test shape).

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/autoload/SkillManager.gd scripts/autoload/PlayerData.gd scripts/tests/TestRunner.gd
git commit -m "feat(activities): momentum streak XP rule"
```

### Task 6: Activity UI (strip offer, card dialog, policy row) + phase gate

**Files:**
- Modify: `scripts/ui/ActivityStrip.gd` (spawn offer display + switch button)
- Modify: `scripts/ui/ConfirmDialog.gd` (reuse for cards: title/text/2 buttons + timeout bar)
- Modify: `scripts/ui/panels/SkillsPanel.gd` (`_refresh_selected`: policy row)
- Test: none new (suite + manual screenshot)

- [ ] **Step 1: Build the UI from existing widgets**

`ActivityStrip.refresh`: if `EventDirector.active_spawn` non-empty, show
"Bonus: <name> (<n> left)" + `UIStyle.mini_button("Switch")` → `EventDirector.accept_spawn()`.
Cards: reuse `ConfirmDialog` with the event title/text and two buttons mapping to the
choices' policies; a 15s timeout calls `EventDirector.resolve(ev, "TIMEOUT")` and closes.
`SkillsPanel._refresh_selected`: one `HBoxContainer` row — "Events:" + `OptionButton`
(safe/greedy/manual) per category, writing `PlayerData.event_policies`.

- [ ] **Step 2: Run full verification**

Run: `godot --headless --path . -- --tests`, `--validate`, `--smoke`, `--selftest`
Expected: all PASS

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/ActivityStrip.gd scripts/ui/ConfirmDialog.gd scripts/ui/panels/SkillsPanel.gd
git commit -m "feat(ui): event offers, card dialog, policy row"
```
