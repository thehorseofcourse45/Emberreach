# Progression Quality Systems #16–#18 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the requested persisted action queue, rule-based loot automation, and background 10,000-fight combat simulator to Emberreach.

**Architecture:** Keep `SkillManager`, `CombatManager`, `BankManager`, and `SaveManager` authoritative. Add three focused autoload managers over those services: `ActionQueueManager` owns FIFO queue state and transitions, `LootFilterManager` owns sanitized sale policy and delegates every sale, and `CombatSimulatorManager` owns main-thread snapshots plus a pure deterministic worker calculator. UI panels remain thin and use existing container/style helpers.

**Tech Stack:** Godot 4.7.2, GDScript, JSON content tables, existing `TestRunner.gd`, existing autoload singletons, existing `EventBus` and UI helpers.

**Spec:** `docs/superpowers/specs/2026-09-25-progression-quality-systems-design.md`

## Global Constraints

- Build only #16–18; systems #1–15 and #19–20 remain future work.
- Use the existing single activity slot; never add a second worker.
- Persist the queue as FIFO data with `steps`, `current_index`, and `enabled`.
- Skill targets are absolute bank counts; `0` means “all” and stops when the target reaches zero.
- Combat steps are valid anywhere but remain blocked until the player chooses Continue or Skip; no automatic combat exit is added.
- Auto-sell starts empty, is opt-in, respects item protection, and never sells zero-value items.
- Tier-bounded rules use explicit item metadata: `bones=0`, `big_bones=1`, `dragon_bones=2`; missing tier never matches.
- Special-attack protection is on by default and overrides all auto-sell rules.
- Filter processing is atomic through `BankManager.sell_item()` and is non-recursive; overflow is processed only after it enters the bank.
- The simulator snapshots all live inputs on the main thread, runs one worker at a time, and never mutates live state.
- The production simulator run is 10,000 trials with a deterministic seed; the Run button is disabled while that job runs.
- Simulator food is an unlimited projection of food types currently owned, not live stock depletion.
- Existing save sections remain compatible; new manager sections are optional and sanitized.
- Test command: `'/c/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -- --tests`.
- Do not create Git commits: this directory is not a Git repository.

## Review Focus

- A queue target already satisfied must be skipped without starting an action or consuming inputs.
- A missing material/storage/tool/level stop must pause rather than silently discard the remaining FIFO.
- A combat step must not advance itself on retreat, dungeon completion, defeat, or reload without an explicit decision.
- A keep-count rule must leave exactly the requested count and must not touch overflow or protected items.
- A simulator worker result from an old generation must never be published after reset or load.

---

### Task 1: Queue policy and state machine

**Files:**
- Create: `scripts/autoload/ActionQueueManager.gd`
- Modify: `project.godot`
- Modify: `scripts/tests/TestRunner.gd`

**Interfaces:**
- Consumes: `DataLoader.get_action()`, `DataLoader.get_item()`, `DataLoader.areas`, `DataLoader.dungeons`, `BankManager.get_count()`, `SkillManager.start_action()/stop_action()`, `CombatManager.start_combat()/stop_combat()`.
- Produces: `steps: Array[Dictionary]`, `current_index: int`, `enabled: bool`, `status: String`; `add_skill_step()`, `add_combat_step()`, `start()`, `pause()`, `continue_queue()`, `skip_current()`, `clear()`, `serialize()`, `deserialize()`, `after_simulation_slice()`.

- [ ] **Step 1: Write failing pure/manager tests**

Add a test section to `TestRunner.gd` that constructs a queue state through the public API and asserts:

```gdscript
# Expected after the first implementation exists:
# queue.add_skill_step("woodcutting", "yew_tree", "yew_log", 1000)
# queue.add_skill_step("firemaking", "burn_yew_log", "yew_log", 0)
# queue.add_combat_step("area", "farmlands", ["chicken"])
# queue.serialize() must preserve all normalized dictionaries and FIFO order.
```

Also cover malformed step dictionaries, already-satisfied targets, a missing-material pause, and `Continue`/`Skip` for combat.

- [ ] **Step 2: Run the focused/full test command and verify RED**

Run:

```text
'/c/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -- --tests
```

Expected: the new assertions fail because the queue manager/API is absent or the integration is not wired.

- [ ] **Step 3: Implement the minimal state machine**

Implement a `Node` autoload with normalized step dictionaries. Keep `_transition_pending` and use `call_deferred("_advance_if_ready")` from signal callbacks so a signal emitted during `perform_action()` cannot re-enter the action call. Add `_process(delta)` only for a safe next-frame reconciliation; do not duplicate simulation time.

Use this exact transition contract:

```gdscript
if enabled and current_index < steps.size() and not _transition_pending:
    if current step target is already satisfied:
        current_index += 1
    elif current step is skill and SkillManager.running:
        if target_quantity > 0 and BankManager.get_count(target_item_id) >= target_quantity:
            SkillManager.stop_action(SkillManager.StopReason.TARGET_REACHED)
            current_index += 1
        elif target_quantity == 0 and BankManager.get_count(target_item_id) <= 0:
            SkillManager.stop_action(SkillManager.StopReason.TARGET_REACHED)
            current_index += 1
    elif current step is skill and not SkillManager.running:
        if SkillManager.stop_reason == SkillManager.StopReason.TARGET_REACHED:
            current_index += 1
        elif SkillManager.stop_reason != SkillManager.StopReason.NONE:
            enabled = false
            status = "Paused: " + SkillManager.stop_reason_text()
    elif current step is combat:
        # start once, then wait for explicit continue/skip; never infer completion.
```

- [ ] **Step 4: Run the full suite and verify GREEN**

Run the full test command again. Expected: all existing checks and the new queue checks pass.

- [ ] **Step 5: Refactor only after green**

Keep validation/sanitization helpers separate from transition code, remove duplicated normalization, and preserve FIFO order without changing the public behavior.

---

### Task 2: Queue integration, save/offline parity, and UI

**Files:**
- Modify: `scripts/autoload/ActionQueueManager.gd`
- Modify: `scripts/autoload/GameManager.gd`
- Modify: `scripts/autoload/OfflineProgression.gd`
- Modify: `scripts/autoload/SaveManager.gd`
- Modify: `scripts/autoload/EventBus.gd`
- Create: `scripts/ui/panels/ActionQueuePanel.gd`
- Modify: `scripts/ui/Screens.gd`
- Modify: `scripts/ui/MainUI.gd`
- Modify: `scripts/tests/TestRunner.gd`

**Interfaces:**
- Consumes: Task 1's queue API and serialized shape.
- Produces: `ActionQueueManager.serialize()/deserialize()`, `after_simulation_slice()`, `queue_changed` UI refresh signal, and `Screens.ACTION_QUEUE` navigation.

- [ ] **Step 1: Add failing integration tests**

Test that `SaveManager.build_save_data()` contains `action_queue`, a serialized queue survives `deserialize()` and a save-shaped round trip, manual `GameManager.request_skill_action()` pauses an enabled queue, and an offline `SkillManager.simulate_elapsed()` slice calls the queue transition exactly once.

- [ ] **Step 2: Run the test command and verify RED**

Expected: the new save/integration assertions fail.

- [ ] **Step 3: Wire durable state and activity ownership**

Register the autoload after `SkillManager` and `CombatManager`. Add the optional save section in both `build_save_data()` and `_apply()`. On new game, call `ActionQueueManager.deserialize({})` and clear queue-owned activity. Add a boolean parameter to `GameManager.request_skill_action()`/`request_combat()` (default `manual = true`) so queue-owned calls can avoid pausing themselves. In `OfflineProgression._step_chunk()`, after each `SkillManager.simulate_elapsed()` or `CombatManager.simulate_elapsed()` call, invoke `ActionQueueManager.after_simulation_slice()` before checking the next activity.

- [ ] **Step 4: Add the Action Queue screen**

Add a narrow container-based panel with skill/action/target/quantity controls, combat target controls, row reorder buttons, Start/Pause, Continue/Skip, and Clear. Use `DataLoader` content for choices and disable destructive controls while an activity is owned by the queue. Connect to `EventBus.action_started`, `action_stopped`, `action_completed`, `combat_started`, `combat_ended`, `state_refreshed`, and a new `queue_changed` signal.

- [ ] **Step 5: Run tests and add screen smoke assertions**

Run the full suite. Add a headless assertion that the Action Queue screen builds, contains FIFO rows, and exposes a disabled state when combat is waiting. Expected: green.

- [ ] **Step 6: Refactor only after green**

Remove duplicate queue state from UI, ensure all labels identify normalized IDs through `DataLoader`, and retain the existing single activity slot invariant.

---

### Task 3: Loot filter policy and atomic auto-sell

**Files:**
- Create: `scripts/autoload/LootFilterManager.gd`
- Modify: `project.godot`
- Modify: `data/items.json`
- Modify: `scripts/tests/TestRunner.gd`

**Interfaces:**
- Consumes: `BankManager.items`, `BankManager.sell_item()`, `BankManager.is_protected()`, `DataLoader.get_item()`.
- Produces: `rules: Array[Dictionary]`, `protect_special_items: bool`, `add_rule()`, `update_rule()`, `remove_rule()`, `move_rule()`, `apply_now()`, `process_item_obtained()`, `evaluate()`, `serialize()`, `deserialize()`.

- [ ] **Step 1: Write failing tests for the pure evaluator**

Create tests that seed controlled bank stacks and assert:

```gdscript
# A bone type rule with max_tier=1 and keep_count=0 sells bones and big_bones,
# but not dragon_bones or a bone without a tier.
# A rule for bronze_arrow with keep_count=5000 leaves exactly 5000.
# A non-empty special_attack on an otherwise matching item blocks the sale.
# A protected item, zero-sell-price item, and overflow-only item remain untouched.
# apply_now() and automatic item-obtained filtering use the same evaluator.
```

- [ ] **Step 2: Run the test command and verify RED**

Expected: new filter tests fail because the manager and evaluator are absent.

- [ ] **Step 3: Implement sanitization and the evaluator**

Normalize every rule to:

```gdscript
{
    "id": "local_uuid",
    "enabled": true,
    "label": "Sell common and large bones",
    "item_ids": [],
    "item_types": ["bone"],
    "min_tier": -1,
    "max_tier": 1,
    "keep_count": 0,
}
```

Implement matching as: explicit IDs OR types; tier bounds only apply when the item has an integer `tier`; `keep_count = 0` sells all above zero, otherwise sells `max(0, count - keep_count)`. Refuse invalid IDs, negative keep counts, malformed arrays, and unknown items at the API boundary. Evaluate each bank stack once, set `_processing = true`, call `BankManager.sell_item(item_id, excess)` once, then clear the guard. Return `{sold_items, sold_quantity, gp, skipped}`.

- [ ] **Step 4: Add explicit tier metadata and integration hooks**

Add `tier` fields only to `bones`, `big_bones`, and `dragon_bones` as specified. Connect the manager to `EventBus.item_obtained`; process only quantities actually inserted into the bank. Keep overflow out of the evaluator. Add a `BankManager.flush_notifications()`-compatible public hook if needed so the signal is not delayed in tests, but do not bypass `add_item()` as the mutation path.

- [ ] **Step 5: Run the full suite and verify GREEN**

Expected: all queue and filter tests pass, with existing bank capacity/protection tests unchanged.

---

### Task 4: Auto-sell persistence and Storage UI

**Files:**
- Modify: `scripts/autoload/LootFilterManager.gd`
- Modify: `scripts/autoload/SaveManager.gd`
- Modify: `scripts/autoload/GameManager.gd`
- Modify: `scripts/ui/panels/BankPanel.gd`
- Modify: `scripts/autoload/EventBus.gd`
- Modify: `scripts/tests/TestRunner.gd`

**Interfaces:**
- Consumes: Task 3's `rules` and `evaluate()`.
- Produces: optional `loot_filters` save section and a rules section inside `BankPanel`.

- [ ] **Step 1: Add failing persistence/UI tests**

Test missing save sections produce empty/default state, malformed rules are removed, valid rules survive `serialize()/deserialize()`, and `BankPanel` builds a rules section with Add, Apply now, enable, move, and delete controls.

- [ ] **Step 2: Run the test command and verify RED**

Expected: new persistence/UI assertions fail.

- [ ] **Step 3: Wire persistence and UI**

Add `loot_filters` to `build_save_data()` and `_apply()`. Reset the manager in `GameManager.start_new_game()`. Add a compact section to `BankPanel` that uses `_selected` to create an item-ID rule, exposes keep count and optional tier bounds, and renders the rule list without a second full item browser. Call `LootFilterManager.apply_now()` only from the explicit button.

- [ ] **Step 4: Run the full suite and verify GREEN**

Expected: all tests pass and the existing Storage screen remains responsive.

- [ ] **Step 5: Refactor only after green**

Keep UI formatting in the panel, rule semantics in the manager, and transaction semantics in `BankManager`.

---

### Task 5: Pure combat simulator and background lifecycle

**Files:**
- Create: `scripts/combat/CombatSimulator.gd`
- Create: `scripts/autoload/CombatSimulatorManager.gd`
- Modify: `project.godot`
- Modify: `scripts/combat/CombatFormulas.gd` only if a small reusable formula is missing
- Modify: `scripts/tests/TestRunner.gd`

**Interfaces:**
- Consumes: plain dictionaries from `CombatManager.player_combat_summary()`, equipment/monster/dungeon/mode data, current prayers, food definitions, and a local seed.
- Produces: `CombatSimulator.simulate(snapshot: Dictionary, trials: int, seed_value: int) -> Dictionary` and manager methods `start_run()`, `is_running()`, `cancel()`, `get_result()`.

- [ ] **Step 1: Write failing deterministic tests**

Build small hand-authored snapshots and assert:

```gdscript
# report1 = CombatSimulator.simulate(snapshot, 32, 12345)
# report2 = CombatSimulator.simulate(snapshot, 32, 12345)
# report1 == report2
# A dungeon snapshot's fixed sequence is represented in its assumptions/result.
# rates are finite and non-negative; no autoload/live state is touched.
```

Also test that a different seed is accepted without invalid output and that a zero/negative trial count is rejected.

- [ ] **Step 2: Run the test command and verify RED**

Expected: the calculator tests fail because the class does not exist.

- [ ] **Step 3: Implement the pure calculator**

Use `CombatFormulas.chance_to_hit()`, `roll_damage()`, `min_hit()`, and `triangle()` with deterministic `RandomNumberGenerator`. Model player-first attack ordering, monster attacks, Auto Eat healing, protection prayers, special attacks/stuns when represented in the snapshot, and a hard duration ceiling. Return:

```gdscript
{
    "trials": trials,
    "wins": wins,
    "deaths": deaths,
    "death_chance": deaths / trials,
    "kills": kills,
    "kills_per_hour": kills / hours,
    "trials_per_hour": trials / hours,
    "food_per_hour": food / hours,
    "xp_per_hour": total_xp / hours,
    "xp_by_skill": {...},
    "average_fight_seconds": total_seconds / trials,
    "seed": seed_value,
    "assumptions": [...],
}
```

Use the same formulas and style/mode values as live combat, but keep every resource read out of the worker.

- [ ] **Step 4: Implement the background manager**

Snapshot on the main thread in `start_run()`, increment a generation counter, start exactly one `Thread`, and refuse a second active job. In `_process()`, use `is_alive()` and `wait_to_finish()` on the main thread, then publish only when the generation still matches. Clear the report on `EventBus.game_loaded` and new-game reset. Never call autoloads from the worker callable.

- [ ] **Step 5: Run the full suite and verify GREEN**

Expected: deterministic, finite-rate, dungeon, and lifecycle tests pass.

---

### Task 6: Combat Simulator UI and final integration

**Files:**
- Create: `scripts/ui/panels/CombatSimulatorPanel.gd`
- Modify: `scripts/ui/Screens.gd`
- Modify: `scripts/ui/MainUI.gd`
- Modify: `scripts/ui/panels/CombatPanel.gd` (only shared target picker if needed)
- Modify: `scripts/tests/TestRunner.gd`
- Modify: `.unlazy/queue-filters-simulator/GATES.md`

**Interfaces:**
- Consumes: Task 5's manager and calculator.
- Produces: `Screens.COMBAT_SIMULATOR`, a screen with target/style/seed controls, a disabled Run button during a job, report rows, and stated assumptions.

- [ ] **Step 1: Add failing UI/lifecycle tests**

Assert the screen builds with target options, a read-only summary, a 10,000-trial button, and a disabled button after `start_run()`. Assert a report is not published after a generation change.

- [ ] **Step 2: Run the test command and verify RED**

Expected: new UI/lifecycle assertions fail.

- [ ] **Step 3: Build the thin UI**

Add the screen route and panel. Populate targets from monsters/areas/dungeons, use `CombatManager.attack_style` and `melee_style` as defaults, copy the summary into read-only rows, and call `start_run()` only after a valid target. Never expose a gear editor.

- [ ] **Step 4: Run the full verification matrix**

Run:

```text
'/c/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -- --tests
'/c/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -- --selftest
'/c/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -- --smoke
```

Expected: each command exits 0, tests report zero failed checks, and no new parse/runtime errors appear. Existing RID-leak shutdown warnings are baseline noise unless this change adds a new error class.

- [ ] **Step 5: Run the gate ledger and independent review**

Lint and execute the approved commands in `.unlazy/queue-filters-simulator/GATES.md`, then inspect the complete changed-file set for secrets, unsafe dynamic execution, placeholder code, and requirement gaps. Fix any concrete issue and rerun the affected tests before reporting completion.

- [ ] **Step 6: Final audit against the spec**

Re-read the original request and this plan. Confirm every acceptance criterion has a real test or a documented manual UI check; report any unmet item rather than claiming the milestone is complete.
