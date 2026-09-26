# Equipment tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pinned Equipment tab under Combat showing loadout, stats, equippable bank gear, and saved sets.

**Architecture:** New `Screens.EQUIPMENT` route plus one new `panels/EquipmentPanel.gd` built from existing pieces only: `EquipmentManager` for equip/unequip/stats/sets, `BankManager.sorted_list(..., "equipment")` rows for the browser, `UIStyle.section` cards like `SettlementPanel`. No stat-formula or economy changes.

**Tech Stack:** Godot 4.7 GDScript; headless verification via `--validate` and `--tests`.

**Spec:** `docs/superpowers/specs/2026-09-26-equipment-tab-design.md`

## Global Constraints

- Godot 4.7 GDScript only; no new autoloads, scenes, items, or stat formulas.
- New route string verbatim: `"equipment"` (`EQUIPMENT := "equipment"`, label `Equipment`).
- `PINNED_SCREENS` becomes `[STORE, PROVISIONER, COMBAT, EQUIPMENT]` verbatim, in that order.
- Equip/unequip/set calls go through `EquipmentManager` only; never mutate `slots`/`sets` directly.
- Bonus getters take arguments: `get_attack_bonus("stab"|"slash"|"block")`, `get_strength_bonus("melee"|"ranged"|"magic")`, `get_defence_bonus("melee"|"ranged"|"magic")`.

## Review Focus

- Drawer at 420px omits Equipment while the sidebar shows it; builder expects both from the shared `_add_pinned_nav` loop.
- Equipment appears twice (pinned + GAME) because the GAME loop was not told to skip it; builder expects exactly one entry.
- The panel opens blank on a fresh character because empty slots add nothing; builder expects muted empty-slot rows.
- An equipped item shows both an Equip button and an Equipped badge because the row ignores `r["equipped"]`; builder expects badge-only.
- Loading an out-of-range set silently does nothing because `load_set` false is unhandled; builder expects a warn toast and a refresh.

---

### Task 1: Equipment route and pinned nav

**Files:**
- Modify: `C:\Godot\melvor-clone-godot\scripts\ui\Screens.gd` (const + LABELS + ICONS + ORDER)
- Modify: `C:\Godot\melvor-clone-godot\scripts\ui\MainUI.gd` (PINNED_SCREENS, `_icon_kind_for`, `_icon_id_for`, PANEL_SCRIPTS)
- Test: headless `--validate`

**Interfaces:**
- Consumes: nothing new
- Produces: `Screens.EQUIPMENT` (`"equipment"`), `EquipmentPanel` script path for Task 2

- [ ] **Step 1: Add the route const after `STORE` in `Screens.gd`**

```gdscript
const STORE := "store"
const EQUIPMENT := "equipment"
```

- [ ] **Step 2: Add LABELS, ICONS, ORDER entries**

```gdscript
	STORE: "General Store",
	EQUIPMENT: "Equipment",
```

```gdscript
	STORE: "items",
	EQUIPMENT: "items",
```

```gdscript
const ORDER: Array[String] = [BANK, OVERVIEW, SKILLS, COMBAT, EQUIPMENT, EXPEDITIONS,
	QUESTS, ACHIEVEMENTS, COLLECTION, SETTLEMENT, PROVISIONER, STORE, ACTION_QUEUE,
	COMBAT_SIMULATOR, SETTINGS]
```

- [ ] **Step 3: Pin it fourth in `MainUI.gd` line 20**

```gdscript
const PINNED_SCREENS: Array[String] = [Screens.STORE, Screens.PROVISIONER, Screens.COMBAT, Screens.EQUIPMENT]
```

(No GAME-loop edit needed: both loops already `continue` on `screen in PINNED_SCREENS`, so Equipment is excluded from GAME automatically — Task 3 Step 1 proves it.)

- [ ] **Step 4: Add icon branches**

```gdscript
		Screens.STORE: return "items"
		Screens.EQUIPMENT: return "items"
```

```gdscript
		Screens.STORE: return "iron_bar"
		Screens.EQUIPMENT: return "iron_platebody"
```

(`iron_platebody` is approximate on purpose: any missing icon falls back inside `AssetRegistry.icon`; Step 5 proves the parse, Task 3 proves pixels.)

- [ ] **Step 5: Register the panel script in PANEL_SCRIPTS**

```gdscript
	Screens.STORE: "GeneralStorePanel",
	Screens.EQUIPMENT: "EquipmentPanel",
```

- [ ] **Step 6: Run validation to prove the route parses**

Run: `& "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Godot\melvor-clone-godot" -- --validate 2>&1 | Select-Object -First 5`
Expected: `=== content validation: 0 errors, 0 warnings` (plus INFO notes). The panel file does not exist yet; `_panel_for` loads it lazily via `ResourceLoader.exists`, so a missing file is a null panel, not a parse error.

### Task 2: EquipmentPanel with loadout, stats, browser, sets

**Files:**
- Create: `C:\Godot\melvor-clone-godot\scripts\ui\panels\EquipmentPanel.gd`
- Test: headless `--validate` + `--tests`

**Interfaces:**
- Consumes: `Screens.EQUIPMENT` from Task 1; `EquipmentManager` (`get_equipped(slot)`, `equip(item_id)`, `unequip(slot)`, `get_attack_bonus(key)`, `get_strength_bonus(style)`, `get_defence_bonus(style)`, `get_weapon_attack_speed()`, `get_weapon_special_attack()`, `sets`, `active_set`, `save_current_to_set(i)`, `load_set(i)`, `add_set()`); `BankManager.sorted_list(query, mode, ascending, category_filter)` rows (`item_id`, `data`, `equipped`); `ItemData.EquipmentSlot` consts; `EventBus` signals `state_refreshed`, `bank_changed`, `item_equipped`, `item_unequipped`
- Produces: working Equipment screen for Task 3 verification

- [ ] **Step 1: Write the panel file**

```gdscript
extends VBoxContainer
## EquipmentPanel — loadout, combat stats, equippable bank gear, saved sets.
## All mutations go through EquipmentManager; failures toast and refresh.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

const SLOT_NAMES: Dictionary = {
	0: "Helmet", 1: "Platebody", 2: "Platelegs", 3: "Boots", 4: "Gloves",
	5: "Cape", 6: "Amulet", 7: "Ring", 8: "Weapon", 9: "Shield", 10: "Quiver",
	11: "Summon 1", 12: "Summon 2", 13: "Passive", 14: "Consumable",
}

var _loadout_box: VBoxContainer
var _stats_box: VBoxContainer
var _browser_box: VBoxContainer
var _sets_box: VBoxContainer
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Equipment", UITokens.FONT_DISPLAY))
	add_child(UIStyle.label("What you wear, what it gives, and what the bank can offer.",
		true, UITokens.FONT_SMALL))
	_loadout_box = UIStyle.section("Loadout", "currently equipped")
	add_child(_loadout_box)
	_stats_box = UIStyle.section("Stats", "attack, strength, defence")
	add_child(_stats_box)
	_browser_box = UIStyle.section("Equippable", "bank gear you can wear")
	add_child(_browser_box)
	_sets_box = UIStyle.section("Sets", "saved loadouts")
	add_child(_sets_box)
	EventBus.state_refreshed.connect(refresh)
	EventBus.bank_changed.connect(refresh)
	EventBus.item_equipped.connect(func(_s, _i): refresh())
	EventBus.item_unequipped.connect(func(_s, _i): refresh())
	refresh()

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Equipment",
		"body": "Equip from the bank, unequip back to it, and keep named sets for different fights."}

func refresh() -> void:
	if not _built:
		return
	_rebuild_loadout()
	_rebuild_stats()
	_rebuild_browser()
	_rebuild_sets()

func _clear(box: VBoxContainer) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _slot_name(slot: int) -> String:
	return str(SLOT_NAMES.get(slot, "Slot %d" % slot))

func _item_name(item_id: String) -> String:
	return str(DataLoader.get_item(item_id).get("name", item_id))

func _rebuild_loadout() -> void:
	_clear(_loadout_box)
	for slot in range(EquipmentManager.SLOT_COUNT):
		var equipped: String = EquipmentManager.get_equipped(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITokens.SP_4)
		_loadout_box.add_child(row)
		var label := UIStyle.label(
			"%s — %s" % [_slot_name(slot), _item_name(equipped)] if equipped != "" else "%s — (empty)" % _slot_name(slot),
			false, UITokens.FONT_SMALL)
		if equipped == "":
			label.add_theme_color_override("font_color", UITokens.TEXT_MUTED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if equipped != "":
			var slot_idx: int = slot
			var b := UIStyle.button("Unequip", "Return to bank")
			b.pressed.connect(func():
				EquipmentManager.unequip(slot_idx)
				refresh())
			row.add_child(b)

func _rebuild_stats() -> void:
	_clear(_stats_box)
	var lines: Array[String] = [
		"Attack (stab/slash/block): %d / %d / %d" % [
			EquipmentManager.get_attack_bonus("stab"),
			EquipmentManager.get_attack_bonus("slash"),
			EquipmentManager.get_attack_bonus("block")],
		"Strength (melee/ranged/magic): %d / %d / %d" % [
			EquipmentManager.get_strength_bonus("melee"),
			EquipmentManager.get_strength_bonus("ranged"),
			EquipmentManager.get_strength_bonus("magic")],
		"Defence (melee/ranged/magic): %d / %d / %d" % [
			EquipmentManager.get_defence_bonus("melee"),
			EquipmentManager.get_defence_bonus("ranged"),
			EquipmentManager.get_defence_bonus("magic")],
		"Attack speed: %.1fs" % EquipmentManager.get_weapon_attack_speed(),
	]
	var sa: Dictionary = EquipmentManager.get_weapon_special_attack()
	lines.append("Special: %s" % str(sa.get("name", "none")))
	for line in lines:
		_stats_box.add_child(UIStyle.label(line, false, UITokens.FONT_SMALL))

func _rebuild_browser() -> void:
	_clear(_browser_box)
	var rows: Array = BankManager.sorted_list("", BankManager.SortMode.NAME, true, "equipment")
	if rows.is_empty():
		_browser_box.add_child(UIStyle.label("No equippable gear in the bank.",
			true, UITokens.FONT_SMALL))
		return
	var by_slot: Dictionary = {}
	for r in rows:
		var slot: int = int((r["data"] as Dictionary).get("equipment_slot", -1))
		if slot < 0:
			continue
		if not by_slot.has(slot):
			by_slot[slot] = []
		(by_slot[slot] as Array).append(r)
	for slot in by_slot.keys():
		_browser_box.add_child(UIStyle.label(_slot_name(int(slot)), true, UITokens.FONT_MICRO))
		for r in (by_slot[slot] as Array):
			var item_id: String = str(r["item_id"])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", UITokens.SP_4)
			_browser_box.add_child(row)
			row.add_child(Widgets.item_icon(item_id))
			var label := UIStyle.label("%s ×%d" % [_item_name(item_id), int(r["quantity"])],
				false, UITokens.FONT_SMALL)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			if bool(r["equipped"]):
				row.add_child(Widgets.badge("Equipped", UITokens.GOLD_BRIGHT))
			else:
				var target: String = item_id
				var b := UIStyle.button("Equip", "Equip %s" % _item_name(item_id))
				b.pressed.connect(func():
					if not EquipmentManager.equip(target):
						EventBus.notify("Cannot equip %s — check requirements and storage space." % _item_name(target), "warn")
					refresh())
				row.add_child(b)

func _rebuild_sets() -> void:
	_clear(_sets_box)
	var sets: Array = EquipmentManager.sets
	for i in range(sets.size()):
		var idx: int = i
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITokens.SP_4)
		_sets_box.add_child(row)
		var label := UIStyle.label("Set %d%s" % [idx + 1, " (active)" if idx == EquipmentManager.active_set else ""],
			false, UITokens.FONT_SMALL)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var load_b := UIStyle.button("Load", "Equip set %d" % [idx + 1])
		load_b.pressed.connect(func():
			if not EquipmentManager.load_set(idx):
				EventBus.notify("Could not load set %d." % [idx + 1], "warn")
			refresh())
		row.add_child(load_b)
	var save_b := UIStyle.button("Save current", "Save the worn loadout as a set")
	save_b.pressed.connect(func():
		var index: int = EquipmentManager.active_set if not sets.is_empty() else EquipmentManager.add_set()
		EquipmentManager.save_current_to_set(index)
		EventBus.notify("Set %d saved." % [index + 1], "success")
		refresh())
	_sets_box.add_child(save_b)
```

- [ ] **Step 2: Run validation to prove the panel parses**

Run: `& "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Godot\melvor-clone-godot" -- --validate 2>&1 | Select-Object -First 5`
Expected: `=== content validation: 0 errors, 0 warnings` (plus INFO notes)

- [ ] **Step 3: Run the full test suite**

Run: `& "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Godot\melvor-clone-godot" -- --tests 2>&1 | Select-String -Pattern "checks passed|checks failed|ALL TESTS" | Select-Object -Last 5`
Expected:
```
checks passed: 307
checks failed: 0
ALL TESTS PASSED (307 checks)
```

### Task 3: Verify the tab end to end

**Files:**
- Test: headless `--tests` (sidebar suites cover nav invariants)

**Interfaces:**
- Consumes: Tasks 1 and 2
- Produces: green verification

- [ ] **Step 1: Confirm the pinned order and single entry**

Run: `Select-String -Path "C:\Godot\melvor-clone-godot\scripts\ui\MainUI.gd" -Pattern "PINNED_SCREENS.*=" | Select-Object -ExpandProperty Line`
Expected: `const PINNED_SCREENS: Array[String] = [Screens.STORE, Screens.PROVISIONER, Screens.COMBAT, Screens.EQUIPMENT]`

- [ ] **Step 2: Manual spot check (needs a display, not `--headless`)**

Open the project, confirm: pinned rows read Shop, Provisioner, Combat, Equipment; Equipment opens loadout + stats + browser + sets; equip/unequip round-trips and stat labels move; set save/load restores; drawer entry opens the same screen.
