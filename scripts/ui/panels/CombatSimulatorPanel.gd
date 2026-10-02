extends VBoxContainer
## CombatSimulatorPanel — the built-in "what if I fought that?" screen.
##
## The panel does one thing: take a snapshot of the character as it is, ask the background worker to
## run 10,000 fights against a chosen target, and show the report. It never equips gear or edits a
## stat, because the snapshot is meant to be a read of the real loadout — a simulator that could
## change the character would be answering a different question than the one the player asked.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _place_picker: OptionButton
var _style_picker: OptionButton
var _melee_picker: OptionButton
var _seed_field: LineEdit
var _run_button: Button
var _finite: CheckBox
var _gear_box: VBoxContainer
var _result_box: VBoxContainer
var _places: Array[Dictionary] = []
var _selected: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	CombatSimulatorManager.run_started.connect(_on_run_started)
	CombatSimulatorManager.run_finished.connect(_on_run_finished)
	CombatSimulatorManager.run_failed.connect(_on_run_failed)
	refresh()

func focus_route(route: Dictionary) -> void:
	refresh()

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Combat simulator",
		"body": "A background estimate of how your current gear performs against a chosen target."}

# =========================================================================
#  Build
# =========================================================================

func _build() -> void:
	var intro := UIStyle.card()
	add_child(intro)
	var intro_col := UIStyle.vbox(UITokens.SP_2)
	intro.add_child(intro_col)
	intro_col.add_child(UIStyle.title("COMBAT SIMULATOR", UITokens.FONT_SUBHEAD))
	var blurb := UIStyle.label(
		"Simulate 10,000 fights in the background against your current gear, without touching your character.",
		true, UITokens.FONT_SMALL)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_col.add_child(blurb)

	var target_row := _flow()
	add_child(target_row)
	target_row.add_child(UIStyle.label("Target", true, UITokens.FONT_SMALL))
	_place_picker = OptionButton.new()
	_place_picker.custom_minimum_size = Vector2(0, UITokens.H_HEADER + 8)
	_place_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_picker.clip_text = true
	_place_picker.fit_to_longest_item = false
	_place_picker.item_selected.connect(func(_i): _on_target_changed())
	target_row.add_child(_place_picker)

	var style_row := _flow()
	add_child(style_row)
	style_row.add_child(UIStyle.label("Attack", true, UITokens.FONT_SMALL))
	_style_picker = OptionButton.new()
	_style_picker.add_item("Melee")
	_style_picker.add_item("Ranged")
	_style_picker.add_item("Magic")
	_style_picker.item_selected.connect(func(_i): _on_style_changed())
	style_row.add_child(_style_picker)
	_melee_picker = OptionButton.new()
	_melee_picker.add_item("Stab")
	_melee_picker.add_item("Slash")
	_melee_picker.add_item("Block")
	_melee_picker.item_selected.connect(func(_i): _on_style_changed())
	style_row.add_child(_melee_picker)
	style_row.add_child(UIStyle.label("Seed", true, UITokens.FONT_SMALL))
	_seed_field = LineEdit.new()
	_seed_field.placeholder_text = "blank = random"
	_seed_field.tooltip_text = "The same seed and gear give the same report. Leave blank for a fresh run."
	_seed_field.custom_minimum_size = Vector2(120, UITokens.H_HEADER + 8)
	style_row.add_child(_seed_field)

	_finite = CheckBox.new()
	_finite.text = "Finite supplies"
	_finite.tooltip_text = "Equipped foods, remaining prayer points and authored weapon ammo/rune costs. Stops at prayer or attack-material exhaustion."
	_finite.button_pressed = true
	add_child(_finite)
	add_child(UIStyle.label("Every trial starts with your current supplies and full HP. Finite mode ends at prayer/attack-material depletion; attacks without authored costs remain free. Level-ups, potion expiry and drops are excluded.", true, UITokens.FONT_SMALL))
	_run_button = UIStyle.primary_button("Run 10,000 fights",
		"Simulate in the background. The game keeps running while this works.")
	_run_button.pressed.connect(_on_run)
	add_child(_run_button)

	_gear_box = UIStyle.section("Your loadout", "read-only — change your real gear, then simulate again")
	add_child(_gear_box)
	_result_box = UIStyle.section("Report")
	add_child(_result_box)
	_fill_places()
	refresh()

func _flow() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UITokens.SP_3)
	row.add_theme_constant_override("v_separation", UITokens.SP_2)
	return row

func _fill_places() -> void:
	_places.clear()
	_place_picker.clear()
	var area_ids: Array = DataLoader.areas.keys()
	area_ids.sort_custom(func(a, b):
		return int((DataLoader.areas[a].get("level_range", [0]) as Array)[0]) \
			< int((DataLoader.areas[b].get("level_range", [0]) as Array)[0]))
	for area_id in area_ids:
		if str(DataLoader.areas[area_id].get("type", "area")) == "slayer_area":
			continue
		_places.append({"type": "area", "id": str(area_id)})
		_place_picker.add_item("Region · %s" % str(DataLoader.areas[area_id].get("name", area_id)))
	var dungeon_ids: Array = DataLoader.dungeons.keys()
	dungeon_ids.sort()
	for dungeon_id in dungeon_ids:
		_places.append({"type": "dungeon", "id": str(dungeon_id)})
		_place_picker.add_item("Expedition · %s" % str(DataLoader.dungeons[dungeon_id].get("name", dungeon_id)))
	if _place_picker.item_count > 0:
		_place_picker.select(0)
		_on_target_changed()

func _current_place() -> Dictionary:
	if _place_picker.selected < 0 or _place_picker.selected >= _places.size():
		return {}
	return _places[_place_picker.selected]

func _attack_style() -> String:
	match _style_picker.selected:
		1: return "ranged"
		2: return "magic"
	return "melee"

func _on_style_changed() -> void:
	_melee_picker.visible = _attack_style() == "melee"
	refresh()

func _on_target_changed() -> void:
	var place: Dictionary = _current_place()
	if place.is_empty():
		return
	var is_dungeon: bool = str(place["type"]) == "dungeon"
	var source: Dictionary = DataLoader.get_dungeon(str(place["id"])) if is_dungeon \
		else DataLoader.areas.get(str(place["id"]), {})
	_selected = source
	refresh()

# =========================================================================
#  Refresh
# =========================================================================

func refresh() -> void:
	if not is_inside_tree():
		return
	_refresh_gear()
	_refresh_results()
	_refresh_button()

func _refresh_button() -> void:
	var busy: bool = CombatSimulatorManager.is_running()
	_run_button.disabled = busy
	_run_button.text = "Simulating 10,000 fights…" if busy else "Run 10,000 fights"
	_place_picker.disabled = busy
	_style_picker.disabled = busy
	_melee_picker.disabled = busy
	_seed_field.editable = not busy

func _refresh_gear() -> void:
	_clear(_gear_box)
	var summary: Dictionary = CombatManager.player_combat_summary()
	var style: String = _attack_style()
	var hp: float = maxf(10.0, float(summary.get("max_hp", summary.get("hp", 0.0))))
	_gear_box.add_child(Widgets.key_value("Attack style",
		"%s%s" % [style.capitalize(), " · %s" % _melee_picker.get_item_text(_melee_picker.selected)
			if style == "melee" else ""]))
	_gear_box.add_child(Widgets.key_value("Hit points", UIStyle.fmt(hp)))
	_gear_box.add_child(Widgets.key_value("Accuracy", UIStyle.fmt_exact(float(summary.get("accuracy", 0)))))
	_gear_box.add_child(Widgets.key_value("Max hit", UIStyle.fmt_exact(float(summary.get("max_hit", 0)))))
	var evasion: Dictionary = summary.get("evasion", {})
	_gear_box.add_child(Widgets.key_value("Evasion",
		UIStyle.fmt_exact(float(evasion.get(style, 0.0)))))
	_gear_box.add_child(Widgets.key_value("Attack speed",
		"%ss" % UIStyle.fmt(float(summary.get("attack_interval", 0.0)))))
	_gear_box.add_child(Widgets.key_value("Damage reduction",
		"%s%%" % UIStyle.fmt(float(summary.get("damage_reduction", 0.0)))))
	_gear_box.add_child(Widgets.key_value("Auto Eat tier",
		str(int(PlayerData.settings.get("auto_eat_tier", 0)))))
	var food_types: int = 0
	for item_id in BankManager.items.keys():
		if str(DataLoader.get_item(str(item_id)).get("item_type", "")) == "food":
			food_types += 1
	_gear_box.add_child(Widgets.key_value("Food types owned", str(food_types),
		UITokens.TEXT,
		"Finite mode uses the three equipped food slots; unlimited mode uses every owned food."))
	var weapons: Array[String] = []
	for slot in EquipmentManager.slots.keys():
		var item_id: String = str(EquipmentManager.slots[slot])
		if item_id == "":
			continue
		if str(DataLoader.get_item(item_id).get("special_attack", "")) != "":
			weapons.append(str(DataLoader.get_item(item_id).get("name", item_id)))
	if not weapons.is_empty():
		_gear_box.add_child(Widgets.key_value("Special attacks", ", ".join(weapons), UITokens.GOLD_BRIGHT))
	# The comparison the player actually wants: what this target does back.
	var place: Dictionary = _current_place()
	if not place.is_empty() and str(place["type"]) == "area":
		var area: Dictionary = DataLoader.areas.get(str(place["id"]), {})
		var monsters: Array = area.get("monsters", [])
		if not monsters.is_empty():
			_gear_box.add_child(Widgets.key_value("Enemy pool", str(monsters.size())))
			var levels: Array = area.get("level_range", [])
			if not levels.is_empty():
				_gear_box.add_child(Widgets.key_value("Enemy levels",
					"%d–%d" % [int(levels[0]), int(levels[levels.size() - 1])]))

func _refresh_results() -> void:
	_clear(_result_box)
	if CombatSimulatorManager.is_running():
		_result_box.add_child(UIStyle.colored_label("Running 10,000 fights in the background…",
			UITokens.GOLD_BRIGHT, UITokens.FONT_SMALL))
		return
	var report: Dictionary = CombatSimulatorManager.last_report
	if report.is_empty():
		if CombatSimulatorManager.last_error != "":
			_result_box.add_child(UIStyle.colored_label(CombatSimulatorManager.last_error,
				UITokens.RED, UITokens.FONT_SMALL))
		else:
			_result_box.add_child(UIStyle.label(
				"No report yet. Pick a target and press Run.", true, UITokens.FONT_SMALL))
		return
	_result_box.add_child(UIStyle.title(str(CombatSimulatorManager.target_label), UITokens.FONT_SUBHEAD))
	for line in CombatSimulatorManager.format_report(report):
		_result_box.add_child(UIStyle.label(line, false, UITokens.FONT_SMALL))
	var assumptions: Array = report.get("assumptions", [])
	if not assumptions.is_empty():
		_result_box.add_child(UIStyle.section("Assumptions"))
		for note in assumptions:
			var l := UIStyle.label("· %s" % str(note), true, UITokens.FONT_MICRO)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_result_box.add_child(l)

# =========================================================================
#  Commands
# =========================================================================

func _on_run() -> void:
	var place: Dictionary = _current_place()
	if place.is_empty():
		EventBus.notify("Pick a target first.", "warn")
		return
	var seed_value: int = int(_seed_field.text.strip_edges())
	var ok: bool = CombatSimulatorManager.start(str(place["type"]), str(place["id"]),
		_attack_style(), _melee_picker.get_item_text(_melee_picker.selected),
		CombatSimulatorManager.PRODUCTION_TRIALS, seed_value, _finite.button_pressed)
	if not ok:
		EventBus.notify(CombatSimulatorManager.last_error, "warn")
	refresh()

func _on_run_started(target_name: String) -> void:
	_clear(_result_box)
	_result_box.add_child(UIStyle.colored_label("Simulating %s — 10,000 fights in the background…" % target_name,
		UITokens.GOLD_BRIGHT, UITokens.FONT_SMALL))
	refresh()

func _on_run_finished(_report: Dictionary) -> void:
	EventBus.notify("Simulation complete: %s" % CombatSimulatorManager.target_label, "success")
	refresh()

func _on_run_failed(reason: String) -> void:
	EventBus.notify(reason, "warn")
	refresh()

func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
