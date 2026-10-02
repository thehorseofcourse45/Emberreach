extends VBoxContainer
## FarmPanel — the Husbandry plots: plant seeds, dress with compost, harvest.
##
## The plot engine (FarmingManager) grew crops by wall-clock time, but nothing in the game
## could reach it: no screen planted, no action planted, so the whole skill paid nothing.
## This screen is the missing entry point. The skill's plant_* actions bridge the other way —
## each action spends one seed (input_items) and fills the first free plot — so both doors
## open onto the same fifteen plots, and harvesting is where the XP comes from.

signal navigated(route: Dictionary)

## Plot rows in display order, with their section titles.
const PLOT_SECTIONS: Array = [["allotment", "Allotment"], ["herb", "Herb"], ["tree", "Tree"]]

var _summary: Label
var _hint: Label
var _seed_route: Button
var _harvest_button: Button
var _sections: VBoxContainer
var _tiles: Array = []              # {index, state_label, bar}
var _last_categories: Array = []
var _popup_seeds: Array = []
var _built: bool = false
var _tick: float = 0.0
var _dirty: bool = true

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(UIStyle.title("Farm", UITokens.FONT_DISPLAY))
	_summary = UIStyle.label("", true, UITokens.FONT_SMALL)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	_hint = UIStyle.label("Seeds are stolen: thieving targets drop them from level 1 to 115. "
		+ "Compost (+10% survival per dressing) comes from the settlement trader. Crops grow in "
		+ "real time — harvesting pays the experience.", true, UITokens.FONT_SMALL)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)
	add_child(UIStyle.label("All fifteen plots accept any current seed. Allotment / Herb / Tree are visual sections; current crops are herbs. Manure gives +25% survival and +10% yield; compost gives +10% survival per dressing. Apply both before planting.", true, UITokens.FONT_SMALL))
	var controls := UIStyle.hbox(UITokens.SP_4)
	_harvest_button = UIStyle.primary_button("Harvest all ready")
	_harvest_button.pressed.connect(_harvest_all)
	controls.add_child(_harvest_button)
	_seed_route = UIStyle.mini_button("Where are seeds?")
	_seed_route.tooltip_text = "Opens the thieving skill, where every seed drops"
	_seed_route.pressed.connect(func(): navigated.emit({"screen": Screens.SKILLS, "skill_id": "thieving"}))
	controls.add_child(_seed_route)
	controls.add_child(UIStyle.spacer())
	add_child(controls)
	_sections = UIStyle.vbox(UITokens.SP_6)
	add_child(_sections)
	if not FarmingManager.plots_changed.is_connected(_mark_dirty):
		FarmingManager.plots_changed.connect(_mark_dirty)
	EventBus.bank_changed.connect(_mark_dirty)
	EventBus.skill_level_up.connect(func(_skill_id, _level): _mark_dirty())
	EventBus.state_refreshed.connect(_mark_dirty)
	_built = true
	set_process(true)
	_rebuild()

func focus_route(_route: Dictionary) -> void:
	pass

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Farm",
		"body": "Plots grow crops in real time, even while away. Dress the soil, plant a seed, "
			+ "with compost, and harvest when the timer runs out — harvesting pays the XP. "
			+ "Thieving targets are where every seed comes from."}

func _mark_dirty() -> void:
	_dirty = true

func _process(delta: float) -> void:
	if not _built:
		return
	_tick += delta
	if _tick < 0.5:
		return
	_tick = 0.0
	var categories: Array = _categories()
	if _dirty or categories != _last_categories:
		_rebuild()
	else:
		_update_live()

# =========================================================================
#  Rendering
# =========================================================================

func _rebuild() -> void:
	_dirty = false
	var total: int = FarmingManager.plots.size()
	var in_use: int = 0
	for p in FarmingManager.plots:
		if str(p["seed_id"]) != "":
			in_use += 1
	var ready: int = FarmingManager.ready_count()
	_summary.text = "Husbandry Lv %d · %d of %d plots in use · %d ready · Compost ×%d" % [
		PlayerData.get_level("farming"), in_use, total, ready, BankManager.get_count("compost")]
	_harvest_button.text = "Harvest all ready (%d)" % ready
	_harvest_button.disabled = ready == 0
	_seed_route.visible = _stored_seed_kinds() == 0
	for c in _sections.get_children():
		_sections.remove_child(c)
		c.queue_free()
	_tiles.clear()
	for section in PLOT_SECTIONS:
		var type_id: String = str(section[0])
		var indices: Array = []
		for i in range(total):
			if str(FarmingManager.plots[i]["type"]) == type_id:
				indices.append(i)
		if indices.is_empty():
			continue
		var sec: VBoxContainer = UIStyle.section("%s — %d plots" % [str(section[1]), indices.size()])
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", UITokens.SP_4)
		flow.add_theme_constant_override("v_separation", UITokens.SP_4)
		sec.add_child(flow)
		var n: int = 0
		for i in indices:
			n += 1
			flow.add_child(_plot_card(int(i), "%s %d" % [str(section[1]), n]))
		_sections.add_child(sec)
	_last_categories = _categories()

func _plot_card(index: int, name_text: String) -> Control:
	var state: String = _state_for(index)
	var card: PanelContainer = UIStyle.card(state == "ready")
	card.custom_minimum_size = Vector2(216, 0)
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var top := UIStyle.hbox(UITokens.SP_2)
	col.add_child(top)
	var name_label := UIStyle.label(name_text, false, UITokens.FONT_BODY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	top.add_child(Widgets.badge(_badge_text(state), _badge_color(state), ""))
	var state_label := UIStyle.label("", true, UITokens.FONT_SMALL)
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state_label.text = _state_text(index, state)
	col.add_child(state_label)
	var bar: ProgressBar = null
	if state == "growing" or state == "ready":
		bar = Widgets.progress_bar(_progress_value(index), maxf(1.0, _progress_max(index)), UITokens.TEAL)
		col.add_child(bar)
	var buttons := UIStyle.hbox(UITokens.SP_2)
	col.add_child(buttons)
	_build_buttons(buttons, index, state)
	_tiles.append({"index": index, "state_label": state_label, "bar": bar})
	return card

func _build_buttons(buttons: HBoxContainer, index: int, state: String) -> void:
	match state:
		"empty":
			var plant := MenuButton.new()
			plant.text = "Plant seed…"
			plant.add_theme_font_size_override("font_size", UITokens.FONT_SMALL)
			plant.custom_minimum_size = Vector2(0, UITokens.H_CONTROL - 6)
			plant.get_popup().about_to_popup.connect(func(): _fill_planter(plant, index))
			plant.get_popup().id_pressed.connect(func(id: int): _plant(index, str(_popup_seeds[id])))
			buttons.add_child(plant)
			if BankManager.get_count("compost") > 0:
				var compost := UIStyle.mini_button("Compost ×%d" % BankManager.get_count("compost"),
					"+10% survival when this plot is planted")
				compost.pressed.connect(func(): _compost(index))
				buttons.add_child(compost)
		"ready":
			var harvest := UIStyle.mini_button("Harvest")
			harvest.pressed.connect(func(): _harvest(index))
			buttons.add_child(harvest)
			var replant := UIStyle.mini_button("Harvest & replant")
			replant.disabled = not BankManager.has_item(str(FarmingManager.plots[index].seed_id), 1)
			replant.pressed.connect(func():
				FarmingManager.harvest_replant(index)
				_rebuild())
			buttons.add_child(replant)
		"dead":
			var clear := UIStyle.mini_button("Clear")
			clear.tooltip_text = "Remove the failed crop so the plot can be replanted"
			clear.pressed.connect(func(): _clear(index))
			buttons.add_child(clear)

func _update_live() -> void:
	for tile in _tiles:
		var index: int = int(tile["index"])
		var state: String = _state_for(index)
		var label: Label = tile["state_label"]
		var text: String = _state_text(index, state)
		if label.text != text:
			label.text = text
		var bar: ProgressBar = tile["bar"]
		if bar != null and is_instance_valid(bar):
			bar.value = clampf(_progress_value(index), 0.0, maxf(1.0, _progress_max(index)))

# =========================================================================
#  State
# =========================================================================

func _categories() -> Array:
	var out: Array = []
	for i in range(FarmingManager.plots.size()):
		out.append(_state_for(i))
	return out

func _state_for(index: int) -> String:
	var p: Dictionary = FarmingManager.plots[index]
	if str(p["seed_id"]) == "":
		return "empty"
	if not bool(p["alive"]):
		return "dead"
	if FarmingManager.is_ready(index):
		return "ready"
	return "growing"

func _state_text(index: int, state: String) -> String:
	var p: Dictionary = FarmingManager.plots[index]
	match state:
		"empty":
			var c: int = int(p["compost"])
			if c > 0:
				return "Empty. Dressed with compost ×%d (+%d%% survival when planted)." % [c, c * 10]
			return "Empty. Plant a seed, or dress it with compost first."
		"dead":
			return "The %s failed to take. Clear the plot to replant." % _crop_name(str(p["seed_id"]))
		"ready":
			return "%s is ready to harvest." % _crop_name(str(p["seed_id"]))
	var remaining: float = maxf(0.0, float(p["planted_unix"]) + float(p["grow_seconds"]) - float(Time.get_unix_time_from_system()))
	var pct: int = int(round(_progress_value(index) / maxf(1.0, _progress_max(index)) * 100.0))
	return "Growing %s — ready in %s (%d%%)." % [_crop_name(str(p["seed_id"])), UIStyle.fmt_duration(remaining), pct]

func _crop_name(seed_id: String) -> String:
	return str(DataLoader.get_item(seed_id).get("name", seed_id)).trim_suffix(" Seed")

func _progress_value(index: int) -> float:
	var p: Dictionary = FarmingManager.plots[index]
	return clampf(float(Time.get_unix_time_from_system()) - float(p["planted_unix"]), 0.0, maxf(1.0, float(p["grow_seconds"])))

func _progress_max(index: int) -> float:
	return float(FarmingManager.plots[index]["grow_seconds"])

func _badge_text(state: String) -> String:
	match state:
		"empty": return "Empty"
		"growing": return "Growing"
		"ready": return "Ready"
	return "Failed"

func _badge_color(state: String) -> Color:
	match state:
		"growing": return UITokens.TEAL
		"ready": return UITokens.GOLD
		"dead": return UITokens.RED
	return UITokens.TEXT_DIM

# =========================================================================
#  Interactions
# =========================================================================

## The picker lists every crop so the screen doubles as a shopping list: locked crops and
## crops with none in storage show why they cannot go in.
func _seed_options() -> Array:
	var out: Array = []
	var actions: Array = (DataLoader.get_skill("farming").get("actions", []) as Array).duplicate()
	actions.sort_custom(func(a, b):
		return int((a as Dictionary).get("level_required", 1)) < int((b as Dictionary).get("level_required", 1)))
	for a in actions:
		var seed_id: String = FarmingManager.seed_id_for_action(str((a as Dictionary).get("id", "")))
		if seed_id == "":
			continue
		var level: int = int((a as Dictionary).get("level_required", 1))
		out.append({"id": seed_id, "name": str(DataLoader.get_item(seed_id).get("name", seed_id)),
			"count": BankManager.get_count(seed_id), "level": level,
			"unlocked": PlayerData.get_level("farming") >= level})
	return out

func _stored_seed_kinds() -> int:
	var n: int = 0
	for o in _seed_options():
		if int(o["count"]) > 0:
			n += 1
	return n

func _fill_planter(button: MenuButton, plot_index: int = 0) -> void:
	var popup: PopupMenu = button.get_popup()
	popup.clear()
	_popup_seeds.clear()
	for o in _seed_options():
		var index: int = popup.item_count
		var label: String = "%s ×%d — Lv %d" % [str(o["name"]), int(o["count"]), int(o["level"])]
		if not bool(o["unlocked"]):
			label = "%s — locked until Lv %d" % [str(o["name"]), int(o["level"])]
		elif int(o["count"]) <= 0:
			label = "%s — none in storage" % str(o["name"])
		var preview: Dictionary = FarmingManager.planting_preview(plot_index, str(o.id))
		label += " · %.0f%% survival · +%d%% yield · %s" % [float(preview.survival) * 100, int(preview.yield_bonus), UIStyle.fmt_duration(float(preview.seconds))]
		popup.add_item(label, index)
		popup.set_item_disabled(index, not bool(o["unlocked"]) or int(o["count"]) <= 0)
		_popup_seeds.append(str(o["id"]))

func _plant(index: int, seed_id: String) -> void:
	if not FarmingManager.plant(index, seed_id):
		EventBus.notify("That seed cannot be planted there", "warn")
	_rebuild()

func _compost(index: int) -> void:
	FarmingManager.apply_compost(index)
	_rebuild()

func _harvest(index: int) -> void:
	FarmingManager.harvest(index)
	_rebuild()

func _harvest_all() -> void:
	var res: Dictionary = FarmingManager.harvest_all()
	if int(res.get("plots", 0)) > 0:
		EventBus.notify("Harvested %d crops." % int(res["plots"]), "success")
	_rebuild()

func _clear(index: int) -> void:
	FarmingManager.clear_plot(index)
	_rebuild()

# =========================================================================
#  Test hooks
# =========================================================================

func _plot_count() -> int:
	return _tiles.size()
