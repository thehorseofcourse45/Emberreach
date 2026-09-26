# Combat Decisions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give idle combat preparation depth — slottable abilities, per-area strategy presets, three new monster passives — mirrored exactly in the simulator and offline paths.

**Architecture:** `data/abilities.json` loaded by `DataLoader` like `special_attacks.json`; ability rolls inside `CombatManager._player_attack()` on the existing `_rng`; loadout/strategy state packed into `CombatSimulatorManager.build_snapshot()` and honored by the pure `CombatSimulator` model. Passives follow the `regeneration` pattern in both engines.

**Tech Stack:** Godot 4.7 GDScript.

**Spec:** `docs/superpowers/specs/2026-09-26-ui-combat-activities-overhaul-design.md` (§4, §6)

## Global Constraints

- Every new roll uses the existing seeded `_rng` streams; no new RNG sources.
- All stat math via `ModifierManager`; new effect keys reuse the existing vocabulary (`melee_max_hit_percent`, `attack_interval_percent`, `crit_chance_percent`, status application, life-steal-style heal).
- Live engine and `CombatSimulator` stay in lockstep; new tests pin parity.
- Save bump 2→3 happens here (`_migrate_2_to_3`), including inert event-policy defaults for the activities plan.
- Verification after every task: `--validate` and `--tests` green.
- Frequent commits, one per task.

## Review Focus

- An ability on cooldown must never fire twice on the same attack — pinned in Task 3 tests.
- `hold` bias must fully suppress weapon specials (×0), `eager` must never exceed 100% — pinned in Task 4 tests.
- `leech` must not overheal past monster max HP; `rage` at full HP must equal base damage — pinned in Task 5 tests.
- Unknown ability effect keys and unknown passive ids must fail validation, not silently pass — pinned in Task 2/5 tests.
- A v2 save with no combat keys must load with empty loadout + one default strategy + `safe` policies — pinned in Task 6 tests.

---

### Task 1: abilities.json content + DataLoader

**Files:**
- Create: `data/abilities.json` (8 abilities: 3 melee, 2 ranged, 2 magic, 1 styleless)
- Modify: `scripts/autoload/DataLoader.gd` (load + `get_ability()`)
- Test: `scripts/tests/TestRunner.gd` (`test_abilities_load`)

**Interfaces:**
- Consumes: `DataLoader._load_file()` existing pattern
- Produces: `DataLoader.abilities: Dictionary`, `DataLoader.get_ability(id: String) -> Dictionary` (empty Dictionary for unknown id, mirroring `get_special_attack`)

- [ ] **Step 1: Write the failing test**

```gdscript
func test_abilities_load() -> void:
	var ab: Dictionary = DataLoader.get_ability("power_strike")
	assert_false(ab.is_empty(), "power_strike must exist")
	assert_eq(DataLoader.get_ability("no_such_ability"), {}, "unknown id returns {}")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -- --tests`
Expected: FAIL (`get_ability` not defined)

- [ ] **Step 3: Write data + loader**

`data/abilities.json` entries shaped `{id, style, req_levels: {attack: 10}, unlock: "", effect: {max_hit_percent: 15.0}, trigger_chance: 25.0, cooldown_attacks: 4}`. Effect keys restricted to the five spec'd ones. In `DataLoader.gd` add `abilities = _load_file("abilities.json")` beside `special_attacks` (line ~56) and:

```gdscript
func get_ability(ability_id: String) -> Dictionary:
	return abilities.get(ability_id, {})
```

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS (validator has no ability checks yet — added Task 2)

- [ ] **Step 5: Commit**

```bash
git add data/abilities.json scripts/autoload/DataLoader.gd scripts/tests/TestRunner.gd
git commit -m "feat(combat): abilities.json content + DataLoader getter"
```

### Task 2: Ability + strategy validation

**Files:**
- Modify: `scripts/core/ContentValidator.gd` (`_check_ability`, strategy-shape check)
- Test: `scripts/tests/TestRunner.gd` (`test_ability_validation_rejects`)

**Interfaces:**
- Consumes: `DataLoader.abilities`, existing `_err("invalid_record" | "missing_reference", ...)` pattern
- Produces: `--validate` fails on unknown effect keys, out-of-range chances/cooldowns, bad `req_levels`

- [ ] **Step 1: Write the failing test**

```gdscript
func test_ability_validation_rejects() -> void:
	var errs: Array = ContentValidator.check_ability_record({"id": "bad", "effect": {"nope": 1.0}, "trigger_chance": 150.0, "cooldown_attacks": -1})
	assert_false(errs.is_empty(), "unknown effect + bad ranges must error")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -- --tests`
Expected: FAIL (`check_ability_record` not defined)

- [ ] **Step 3: Implement validator**

Add `static func check_ability_record(ab: Dictionary) -> Array` returning error strings
(empty = valid): id non-empty; `effect` keys ⊆ the five spec'd keys with numeric values;
`0 < trigger_chance <= 100`; `cooldown_attacks >= 0` int; `req_levels` values are ints ≥ 1;
`style` ∈ melee/ranged/magic/any. Wire into the existing per-file validation loop for
`abilities.json` so `--validate` covers it. Strategy shape (`ability_loadout` ids must
exist in `DataLoader.abilities`, `special_bias` ∈ eager/normal/hold, `food_threshold` ∈ 0..1)
checked by `check_strategy_record(strategy: Dictionary) -> Array` in the same file.

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS, 0 errors

- [ ] **Step 5: Commit**

```bash
git add scripts/core/ContentValidator.gd scripts/tests/TestRunner.gd
git commit -m "feat(combat): ability + strategy validation"
```

### Task 3: Ability rolls in the live engine

**Files:**
- Modify: `scripts/autoload/CombatManager.gd` (`_player_attack()` ability block, cooldown state, `KNOWN_ABILITY_EFFECTS`)
- Modify: `scripts/autoload/EventBus.gd` (add `ability_triggered` signal)
- Modify: `scripts/autoload/PlayerData.gd` (loadout storage + serialize, follow existing pattern)
- Test: `scripts/tests/TestRunner.gd` (`test_ability_cooldown_respected`, `test_ability_heal_caps`)

**Interfaces:**
- Consumes: `DataLoader.get_ability()`, `ModifierManager` getters, `PlayerData` combat section
- Produces: `CombatManager.active_loadout: Array[String]` (max `1 + floor(Defence/25)`, cap 4, enforced on set); `CombatManager.set_loadout(ids: Array) -> void` (checks unlock levels + slot cap via `PlayerData.get_level("defence")` — confirm the Defence skill id in `data/skills.json`, adjust if named differently); `CombatManager._apply_ability_heal(amount: float) -> void` (heals `min(max_hp, hp + amount)`); `EventBus.ability_triggered(ability_id: String)`; test hooks `CombatManager._roll_abilities_for_test() -> void` and `CombatManager._last_ability_fired: String`

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_ability_cooldown_respected() -> void:
	CombatManager.seed_rng(7)
	CombatManager.set_loadout(["power_strike"])  # cooldown_attacks = 4
	var fires: int = 0
	for i in 8:
		CombatManager._roll_abilities_for_test()
		if CombatManager._last_ability_fired != "":
			fires += 1
	assert_true(fires <= 2, "cooldown 4 over 8 attacks fires at most twice")

func test_ability_heal_caps() -> void:
	CombatManager.player_hp = 1.0
	CombatManager._apply_ability_heal(99999.0)
	assert_true(CombatManager.player_hp <= CombatManager._compute_max_hp(), "heal never overheals")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . -- --tests`
Expected: FAIL (no ability funcs)

- [ ] **Step 3: Implement minimal ability engine**

In `_player_attack()`, immediately after the hit-chance miss check (so abilities only
roll on hits, consuming the same `_rng` stream order every attack): iterate
`active_loadout`, skip entries on cooldown (`_ability_cooldowns` Dictionary id→attacks-left,
decremented each player attack), roll `_rng.randf() * 100.0 <= trigger_chance`, apply the
single effect via existing paths (`max_hit_percent` scales `mh`, `interval_percent`
scales `player_attack_interval` for the next swing, `crit_chance` adds to the crit roll,
`apply_status` calls `_apply_special_status({"status": ...}, "monster")`,
`heal_on_hit_fraction` routes through `_apply_ability_heal(dmg * fraction)`), set cooldown,
emit `EventBus.ability_triggered`. First firing ability wins per attack (one ability per
attack keeps the RNG stream trivially reproducible). `set_loadout(ids)` enforces unlock
levels + slot cap `mini(4, 1 + int(defence_level / 25))`, persists to `PlayerData`.

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/autoload/CombatManager.gd scripts/autoload/EventBus.gd scripts/autoload/PlayerData.gd scripts/tests/TestRunner.gd
git commit -m "feat(combat): slottable abilities in live engine"
```

### Task 4: Strategies (food threshold, special bias, prayer) in live engine

**Files:**
- Modify: `scripts/autoload/CombatManager.gd` (strategy active record, `_auto_eat` override, special-bias multiplier, area assignment)
- Modify: `scripts/autoload/EventBus.gd` (add `strategy_changed` signal)
- Test: `scripts/tests/TestRunner.gd` (`test_special_bias_hold`, `test_special_bias_eager_caps`)

**Interfaces:**
- Consumes: `check_strategy_record` from Task 2, existing `_auto_eat()` and `_roll_special_attack()`
- Produces: `CombatManager.set_strategy(s: Dictionary)`, `CombatManager.strategy_for(area_id: String)`, `CombatManager._biased_special_chance(base: float, bias: String) -> float`, `EventBus.strategy_changed(name: String)`

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_special_bias_hold() -> void:
	CombatManager.seed_rng(3)
	var s := {"name": "t", "ability_loadout": [], "food_threshold": 0.0, "special_bias": "hold", "protection_prayer_auto": ""}
	CombatManager.set_strategy(s)
	var fired := false
	for i in 50:
		if not CombatManager._roll_special_attack({"id": "s", "chance": 100.0}).is_empty():
			fired = true
	assert_false(fired, "hold must suppress all specials")

func test_special_bias_eager_caps() -> void:
	var chance: float = CombatManager._biased_special_chance(80.0, "eager")
	assert_true(chance <= 100.0, "eager caps at 100")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . -- --tests`
Expected: FAIL

- [ ] **Step 3: Implement strategies**

`set_strategy` validates via `check_strategy_record` (reject invalid, keep old).
`food_threshold > 0` overrides the tier threshold inside `_auto_eat()`; 0 keeps tier
behavior. `_roll_special_attack` multiplies its chance by bias (`eager` 2.0 capped 100,
`normal` 1.0, `hold` 0.0) — implement as `_biased_special_chance(base, bias)` called at
the top of the existing roll. `protection_prayer_auto` ("" or a prayer id) activates that
prayer on combat start if requirements met, via existing `PrayerManager` activation.
Area assignment stored in `PlayerData.combat_strategies_by_area: Dictionary`.

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/autoload/CombatManager.gd scripts/autoload/EventBus.gd scripts/tests/TestRunner.gd
git commit -m "feat(combat): strategy presets in live engine"
```

### Task 5: Passives rage/veil/leech + simulator mirror of everything

**Files:**
- Modify: `scripts/autoload/CombatManager.gd` (`KNOWN_MONSTER_PASSIVES` + live behavior)
- Modify: `scripts/combat/CombatSimulator.gd` (abilities, bias, food threshold, 3 passives in `_run_fight`)
- Modify: `scripts/autoload/CombatSimulatorManager.gd` (`build_snapshot()` gains `loadout`, `strategy`, `monster_passives`)
- Modify: `scripts/core/ContentValidator.gd` (whitelist already via `KNOWN_MONSTER_PASSIVES` — no change needed beyond the const)
- Test: `scripts/tests/TestRunner.gd` (`test_passive_parity_rage`, `test_passive_parity_leech`, `test_ability_parity`)

**Interfaces:**
- Consumes: snapshot Dictionary shape (extend, never rename existing keys)
- Produces: identical outcomes for seeded live-vs-sim runs; test helper `CombatSimulatorManager.build_snapshot_for_test(monster_id: String, loadout: Array, bias: String) -> Dictionary` (assembles a minimal valid snapshot without touching live state)

- [ ] **Step 1: Write the failing parity tests**

```gdscript
func test_ability_parity() -> void:
	var snap: Dictionary = CombatSimulatorManager.build_snapshot_for_test("rage_horror", ["power_strike"], "eager")
	var a: Dictionary = CombatSimulator.simulate(snap, 200, 1234)
	var b: Dictionary = CombatSimulator.simulate(snap, 200, 1234)
	assert_eq(a["player_wins"], b["player_wins"], "same seed must agree with itself")
	assert_true(a.has("ability_fires"), "report must include ability fires")
```

(Plus `test_passive_parity_rage` / `test_passive_parity_leech` asserting sim honors the
passive flags in the snapshot: rage raises monster damage as its HP falls, leech heals
capped at max, veil lowers player hit chance — each vs a no-passive control snapshot.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . -- --tests`
Expected: FAIL

- [ ] **Step 3: Implement passives + sim mirror**

Live: extend `KNOWN_MONSTER_PASSIVES` to `["regeneration", "rage", "veil", "leech"]`.
`rage`: in `_monster_attack`, scale `raw` by `1.0 + 0.5 * (1.0 - monster_hp/monster_max_hp)`.
`veil`: in `_monster_evasion_for`, add flat `+15` when present. `leech`: after dealing
`dmg`, heal monster `min(max_hp, hp + dmg * 0.25)`. Simulator: same three rules in
`_run_fight` (mirror the exact constants), ability loop identical to Task 3 (one per
attack, same cooldown rule), biased special chance, strategy food threshold in `_auto_eat`.
Snapshot gains `loadout: Array`, `strategy: Dictionary`, monster record already carries
`passives` (verify — if not, add it in `build_snapshot`).

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/autoload/CombatManager.gd scripts/combat/CombatSimulator.gd scripts/autoload/CombatSimulatorManager.gd scripts/tests/TestRunner.gd
git commit -m "feat(combat): rage/veil/leech + full simulator mirror"
```

### Task 6: Save v2→v3 migration

**Files:**
- Modify: `scripts/autoload/SaveManager.gd` (`SAVE_VERSION = 3`, `_migrate_2_to_3`, chain in `migrate_save`)
- Test: `scripts/tests/TestRunner.gd` (`test_migrate_2_to_3_defaults`)

**Interfaces:**
- Consumes: existing `migrate_save` chain + `SettingsDefaults` pattern
- Produces: old saves load with `combat_strategies: [default]`, empty loadouts, all event policies `safe`

- [ ] **Step 1: Write the failing test**

```gdscript
func test_migrate_2_to_3_defaults() -> void:
	var out: Dictionary = SaveManager.migrate_save({"save_version": 2, "player": {}}, 2)
	assert_eq(out["save_version"], 3, "version bumps to 3")
	assert_true(out["player"].has("combat_strategies"), "strategies key exists")
	assert_eq(out["player"]["event_policies"], {"risk": "safe", "bonus": "safe"}, "policies default safe")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -- --tests`
Expected: FAIL

- [ ] **Step 3: Implement migration**

```gdscript
const SAVE_VERSION: int = 3
# in migrate_save, after the v<2 branch:
if v < 3:
	out = _migrate_2_to_3(out)
	v = 3

func _migrate_2_to_3(data: Dictionary) -> Dictionary:
	var player: Dictionary = data.get("player", {})
	if not player.has("combat_strategies"):
		player["combat_strategies"] = [{"name": "Default", "ability_loadout": [], "food_threshold": 0.0, "special_bias": "normal", "protection_prayer_auto": ""}]
	if not player.has("combat_strategies_by_area"):
		player["combat_strategies_by_area"] = {}
	if not player.has("event_policies"):
		player["event_policies"] = {"risk": "safe", "bonus": "safe"}
	if not player.has("momentum"):
		player["momentum"] = {}
	player["save_format_history"] = _append_format_history(player.get("save_format_history", []), 2)
	data["player"] = player
	return data
```

- [ ] **Step 4: Run tests to verify green**

Run: `godot --headless --path . -- --tests` then `--validate`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/autoload/SaveManager.gd scripts/tests/TestRunner.gd
git commit -m "feat(save): v2 to v3 migration with combat + policy defaults"
```

### Task 7: CombatPanel strategy UI + phase gate

**Files:**
- Modify: `scripts/ui/panels/CombatPanel.gd` (strategy bar, loadout picker, trigger feed)
- Test: none new (suite + manual screenshot); run full gates

- [ ] **Step 1: Build the UI from existing widgets**

Strategy bar: `UIStyle.section("Strategy")` + `OptionButton` listing
`PlayerData.combat_strategies` names; on select call `CombatManager.set_strategy`.
Loadout picker: up to N `OptionButton`s (N from slot-cap formula) listing unlocked
abilities (`req_levels` met); writes via `CombatManager.set_loadout`. Trigger feed:
append-only `RichTextLabel` (cap 30 lines) fed by `ability_triggered` +
`player_special_attack` signals the panel already subscribes to.

- [ ] **Step 2: Run full verification**

Run: `godot --headless --path . -- --tests`, `--validate`, `--smoke`, `--selftest`
Expected: all PASS

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/panels/CombatPanel.gd
git commit -m "feat(ui): combat strategy bar + loadout picker + trigger feed"
```
