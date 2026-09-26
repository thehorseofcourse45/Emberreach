# Action Queue, Auto-Sell, and Combat Simulator Design

**Date:** 2026-09-25  
**Status:** Approved design, pending written-spec review  
**Target:** Godot 4.7 project at `C:\Godot\melvor-clone-godot`

## Intent

Ship the requested quality-of-life progression slice in this order:

1. persisted action queue;
2. rule-based auto-selling;
3. built-in combat simulator.

The milestone must preserve Emberreach's existing single activity slot, data-driven content, online/offline simulation parity, atomic inventory transactions, and versioned save behavior.

## Confirmed decisions

- Build #16–18 only. The other outlined systems remain future work.
- The queue still uses the existing single activity slot; it never creates a second worker.
- A queue step is a skill action with an item-count stop condition or a combat target.
- Skill targets are absolute bank targets: `1,000 logs` means stop once the named item is at least 1,000; `0` means “all,” stopping when the bank reaches zero.
- Open-ended combat may be queued, but it intentionally waits at the head of the queue. The player chooses **Continue** or **Skip** because no combat exit rule exists in this release.
- Auto-sell rules are opt-in and start empty.
- Combat simulation runs 10,000 trials in a background thread and never mutates the live character.

## Approaches considered

### 1. Add everything to the existing managers

This would avoid new files, but `SkillManager`, `BankManager`, and `CombatManager` would become owners of unrelated policy. Queue transitions, sale policy, and simulation snapshots would obscure the authoritative gameplay paths.

Rejected.

### 2. Independent policy managers over existing gameplay services

Add one manager for each requested system while keeping `SkillManager`, `BankManager`, and `CombatManager` authoritative for action execution, inventory mutation, and combat state.

Chosen. It gives each feature one responsibility and leaves the existing simulation paths intact.

### 3. Generic data-driven workflow engine

Represent every step, condition, and side effect as a schema interpreted at runtime.

Rejected for this milestone. The three requested systems do not justify a general workflow VM.

## Architecture

The milestone adds three independent units:

- `ActionQueueManager`: owns ordered steps, the current index, pause/resume state, target evaluation, and persistence.
- `LootFilterManager`: owns ordered auto-sell rules and the special-attack safety toggle; it delegates every transaction to `BankManager`.
- `CombatSimulatorManager`: snapshots live combat inputs on the main thread, runs pure deterministic simulation on a worker thread, and publishes the report.

Existing managers remain authoritative:

- `SkillManager.start_action()`, `stop_action()`, and `BankManager` are used for skill execution.
- `CombatManager.start_combat()` and `stop_combat()` are used for combat execution.
- `BankManager.add_item()` is the single insertion hook and `BankManager.sell_item()` remains the only sale path used by automation.
- `SaveManager` persists the two durable managers. Simulation results are transient and are not saved.

A future combat-exit condition can extend combat-step schema without changing the queue's FIFO model.

## 1. Action Queue Planner

### Data model

A queue is an ordered array of normalized dictionaries.

Skill step:

```gdscript
{
    "kind": "skill",
    "skill_id": "woodcutting",
    "action_id": "yew_tree",
    "target_item_id": "yew_log",
    "target_quantity": 1000
}
```

Combat step:

```gdscript
{
    "kind": "combat",
    "context": {
        "type": "area",
        "id": "some_area",
        "monsters": ["some_monster"]
    }
}
```

The persisted manager state contains `steps`, `current_index`, and `enabled`. The current step remains in the array until completion or an explicit skip, so save/load cannot lose queued work.

### Validation and transition rules

- Skill steps require an existing action and an existing target item.
- Target quantity is clamped to a non-negative integer; zero means “all.”
- Combat steps require a known area or dungeon and at least one known monster.
- Starting the queue replaces any current manual activity, because the player explicitly pressed Start.
- Starting a manual skill or combat activity pauses an enabled queue, preventing automation from fighting the player for the activity slot.
- If a skill target is already satisfied, the queue skips that step without consuming materials.
- Reaching a skill target stops `SkillManager` with `TARGET_REACHED`, marks the step complete, and starts the next step.
- Missing materials, storage failure, lost levels/tools, or another non-target stop pauses the queue and displays the manager's reason. It does not silently discard later steps.
- **Continue/Skip** stops the current activity if needed, marks the current combat step complete, and starts the next step.
- Reordering affects pending and current steps. Removing the current step stops its activity before advancing.
- Clear stops queue-owned activity and empties the queue.

### Online and offline flow

Online evaluation listens to bank changes and completed skill actions, then defers the stop/advance transition until the current action call returns.

Offline catch-up calls one queue hook after each bounded simulation slice. This avoids depending on UI signals that `SimulationMode` suppresses while still processing every slice at the same cadence.

On load, the queue reconciles with the restored `SkillManager` or `CombatManager` state. A matching active activity continues; an enabled queue with no matching activity resumes on the next frame; a blocked or combat-waiting queue remains paused until player action.

### UI

Add an **Action Queue** screen with:

- skill, action, relevant target-item, and quantity controls;
- area/dungeon combat-step controls;
- add, remove, move up, and move down controls;
- start/pause, continue/skip, and clear controls;
- current-step status and the explicit note that combat waits for Continue/Skip.

The target-item list is the selected action's inputs and outputs, which covers the requested gather/craft/burn flows without a searchable database browser.

## 2. Loot Filters and Auto-Sell Rules

### Rule model

A rule is normalized and sanitized on add and load:

```gdscript
{
    "id": "local_uuid",
    "enabled": true,
    "label": "Sell common and large bones",
    "item_ids": [],
    "item_types": ["bone"],
    "min_tier": -1,
    "max_tier": 1,
    "keep_count": 0
}
```

Rules are evaluated top to bottom. The first enabled matching rule sets the protected bank floor. `keep_count = 0` means sell the whole matching bank stack above zero.

The existing bones receive explicit tiers so “under Dragon tier” is data-driven:

- `bones`: `common` (0)
- `big_bones`: `large` (1)
- `dragon_bones`: `dragon` (2)

Items without a tier do not match a tier-bounded rule. This is conservative: missing metadata never causes an accidental sale.

### Safety rules

- Auto-sell is disabled until the player creates a rule.
- `protect_special_items` is a separate, on-by-default safety toggle. It overrides all rules for items with a non-empty `special_attack`.
- Normal `BankManager` item protection also overrides automation.
- Items with `sell_price <= 0` are never auto-sold in this release. A future “free stack” action can handle them explicitly.
- Automation never sells equipped items because equipped items are removed from the bank.
- A sale is atomic: it calls `BankManager.sell_item()` once for the computed excess quantity.
- Rule processing is non-recursive. Selling an item never re-enters the filter evaluator.
- The evaluator runs after a successful `BankManager.add_item()` mutation. Guaranteed rewards that are still in overflow are processed when they later enter the bank.

### Current-count reconciliation

Creating or editing a rule does not silently liquidate the existing bank. Each rule has **Apply now**, which runs the same evaluator against current item stacks and reports the quantity sold and GP gained. Future inserts apply automatically.

This keeps rule creation safe while still providing an immediate path for “keep exactly 5,000 arrows.”

### Persistence and UI

`LootFilterManager` persists rules, display labels, and the special-item safety toggle. Missing sections in older saves deserialize to an empty rule list and `protect_special_items = true`; no save-version migration is required because all new sections are optional and sanitized.

Add an Auto-Sell section to the existing Storage screen. It uses the currently selected bank item to create a rule, exposes keep count and tier bounds, and lists existing rules with enable, reorder, apply-now, and delete controls. This avoids a second item browser.

## 3. Built-In Combat Simulator

### Snapshot boundary

Pressing **Run 10,000 fights** performs all live-state reads on the main thread. `CombatManager` supplies a derived snapshot using its existing accuracy, max-hit, evasion, attack-speed, and combat-summary paths. The snapshot also includes:

- attack and melee styles;
- HP, damage reduction, crit, and life steal;
- current weapon special attack;
- active prayers and prayer points;
- Auto Eat tier and the heal amount of each food type currently in the bank;
- game-mode combat-triangle values;
- the selected monster or fixed dungeon sequence.

The worker receives only this plain dictionary and a local seed. It does not access autoloads, the scene tree, saves, signals, or live inventory.

### Simulation model

The pure calculator reuses `CombatFormulas` for hit chance, damage rolls, crits, min/max hit, and combat-triangle modifiers. It also models the live combat loop's player-first simultaneous attack ordering, Auto Eat, special attacks, stuns, damage-over-time effects, monster respawn delays, and defeat.

- A monster trial is one fight.
- A dungeon trial is its full fixed monster sequence.
- Each trial starts at full HP so 10,000 repeated dungeon trials remain meaningful.
- Food is projected as unlimited portions of the food types currently owned. Reported food/hour is consumption under that assumption.
- Prayer spending and prayer XP use the same formulas and active-prayer set as live combat.
- XP includes damage-based HP/style/prayer XP and slayer XP for each defeated monster.
- Kills/hour includes all monsters defeated in won trials.
- A hard fight-duration ceiling prevents a stalemate from hanging the worker. The ceiling is reported as an assumption and treated as a loss for rate calculations.

The default is 10,000 trials with a deterministic seed. The pure calculator accepts a smaller count for tests, but the production UI always runs 10,000.

### Background lifecycle and result

`CombatSimulatorManager` starts one `Thread` at a time. `_process()` joins a finished thread and publishes:

- trials, wins, deaths, and death chance;
- kills/hour and trials/hour;
- food/hour;
- total XP/hour and XP/hour by skill;
- average fight duration;
- seed and stated assumptions.

Starting a second run while one is active is refused. A new game or save load invalidates the result generation so stale worker output cannot appear in the new character.

### UI

Add a **Combat Simulator** screen with:

- target selection for any monster or dungeon;
- attack and melee style controls;
- a read-only current gear/stat summary;
- a seed field;
- Run 10,000 Fights; the button is disabled while that one job runs;
- the result table and assumptions.

The simulator does not equip gear or edit stats. The player changes their real loadout, then the simulator snapshots it; this avoids a second inventory/stat editor.

## Failure handling

- Unknown or malformed queue steps are dropped on load and reported in the queue UI.
- Invalid auto-sell rules are rejected at the API boundary and sanitized on load.
- Failed auto-sales leave the bank and GP unchanged.
- Simulator input with no valid target is refused before starting a thread.
- Worker exceptions or invalid results produce an error report and do not touch live state.
- Older saves without the new sections load with empty/default values.
- Manual activity always wins over automation by pausing the queue.

## Testing

Extend the existing `TestRunner`; do not add a new test framework.

### Action queue

- malformed steps are rejected/sanitized;
- a target already reached is skipped without starting the action;
- gathering to a target stops and advances exactly once;
- “all” stops when the input reaches zero;
- missing materials pause rather than discard later steps;
- manual activity pauses the queue;
- Continue/Skip advances a combat step;
- queue state survives serialize/deserialize;
- a bounded offline slice advances the queue using the same transitions.

### Auto-sell

- matching item ID, type, and tier rules sell the correct excess;
- `keep_count = 5,000` leaves exactly 5,000;
- unmatched items are unchanged;
- special-attack protection overrides a matching sale rule;
- normal item protection overrides automation;
- zero-value items are retained;
- sale failure is atomic;
- overflow is not deleted and is filtered only after entering the bank;
- rules survive save/load and malformed rules are sanitized;
- Apply now uses the same code path as automatic filtering.

### Combat simulator

- the same snapshot, seed, and trial count produce identical reports;
- different seeds can produce different outcomes without becoming invalid;
- the 10,000-trial production path completes in the background;
- the live save data is byte-for-byte unchanged before and after simulation;
- a dungeon trial includes its full fixed sequence;
- death chance, kills/hour, food/hour, and XP/hour are finite and non-negative;
- worker results are rejected after a reset/generation change.

Run the existing full suite after each vertical slice, then the end-to-end self-test and a real-window screenshot sweep at 420, 900, and 1440 pixels.

## Out of scope

- automatic combat exit conditions;
- multiple simultaneous queue workers;
- regex or nested rule expressions;
- auto-selling zero-value items;
- editing inventory/gear from the simulator;
- simulating live food depletion, potion charge depletion, or live XP level changes;
- persisting simulation reports;
- systems #1–15 and #19–20.

## Acceptance criteria

The milestone is accepted when:

1. A player can queue, reorder, pause, resume, skip, clear, save, reload, and run skill steps offline using item-count conditions.
2. Combat steps are valid, persist, and visibly wait for an explicit Continue/Skip decision.
3. Auto-sell rules sell only matching excess, respect keep counts and safety overrides, and never delete overflow or zero-value items.
4. The simulator runs 10,000 monster or dungeon trials in the background and reports the requested rates without mutating the character.
5. Existing tests, end-to-end progression, content validation, and responsive UI checks pass.
