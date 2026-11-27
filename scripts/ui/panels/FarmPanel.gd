extends VBoxContainer
## FarmPanel — the Cultivation plots: plant seeds, dress with compost, harvest.
##
## The plot engine (FarmingManager) grew crops by wall-clock time, but nothing in the game
## could reach it: no screen planted, no action planted, so the whole skill paid nothing.
## This screen is the missing entry point. The skill's plant_* actions bridge the other way —
## each action spends one seed (input_items) and fills the first free plot — so both doors
## open onto the same fifteen plots, and harvesting is where the XP comes from.

signal navigated(route: Dictionary)

const Art = preload("res://scripts/ui/panels/FarmArt.gd")
## Plot groups in display order.
const PLOT_SECTIONS: Array = [
	["allotment", "Allotments", "Allotment"], ["herb", "Herb Beds", "Herb Bed"], ["tree", "Orchard", "Orchard Plot"],
]

var _summary: Label
var _stats: HFlowContainer
var _guide: VBoxContainer
var _filters: Dictionary = {}
var _filter := ""
var _grids: Array[GridContainer] = []
var _seed_route: Button
var _harvest_button: Button
var _sections: VBoxContainer
var _tiles: Array = []              # {index, state_label, bar}
var _last_categories: Array = []
var _built: bool = false
var _tick: float = 0.0
var _dirty: bool = true

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_header()
	_build_filters()
	_sections = UIStyle.vbox(UITokens.SP_6)
	add_child(_sections)
	resized.connect(_reflow)
	FarmingManager.plots_changed.connect(_mark_dirty)
	EventBus.bank_changed.connect(_mark_dirty)
	EventBus.gp_changed.connect(func(_amount, _total): _mark_dirty())
	EventBus.skill_level_up.connect(func(_skill_id, _level): _mark_dirty())
	EventBus.state_refreshed.connect(_mark_dirty)
	_built = true
	_rebuild()


func _build_header() -> void:
	var heading := UIStyle.vbox(UITokens.SP_3)
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_child(UIStyle.title("The Farmstead", UITokens.SP_8))
	_summary = Art.label("", UITokens.TEXT_STRONG, UITokens.FONT_BODY)
	heading.add_child(_summary)
	add_child(Art.banner(heading))

	var toolbar := UIStyle.card()
	add_child(toolbar)
	var toolbar_body := UIStyle.vbox(UITokens.SP_3)
	toolbar.add_child(toolbar_body)
	_stats = Widgets.chip_row([])
	toolbar_body.add_child(_stats)

	var controls := Widgets.chip_row([])
	_harvest_button = UIStyle.primary_button("Harvest all ready")
	Art.button_icon(_harvest_button, "skills", "farming")
	_harvest_button.pressed.connect(_harvest_all)
	controls.add_child(_harvest_button)

	_seed_route = UIStyle.button("Find seeds", "Open Thieving to see sources for seeds")
	Art.button_icon(_seed_route, "skills", "thieving")
	_seed_route.pressed.connect(func(): navigated.emit({"screen": Screens.SKILLS, "skill_id": "thieving"}))
	controls.add_child(_seed_route)

	var guide_button := UIStyle.button("Growing guide")
	guide_button.toggle_mode = true
	guide_button.toggled.connect(func(show_guide): _guide.visible = show_guide)
	controls.add_child(guide_button)
	toolbar_body.add_child(controls)

	_guide = UIStyle.vbox(UITokens.SP_3)
	_guide.hide()
	toolbar_body.add_child(_guide)
	_guide.add_child(Art.label("Rotate crops after a successful harvest for +10% survival and +15% yield. Crops continue growing offline."))
	_guide.add_child(Art.label("Balanced uses normal growth. Careful adds 20% survival and takes 15% longer. Intensive adds 35% yield, lowers survival by 15%, and takes 20% longer. XP per harvest is the same."))
	_guide.add_child(Art.label("Compost adds 10% survival per dose, up to five doses. Manure adds 25% survival and 10% yield. Upgrade empty plots at levels 20, 50 and 90. Each tier adds 5% survival, 10% yield and 5% faster growth."))


func _build_filters() -> void:
	var filters := Widgets.chip_row([])
	var group := ButtonGroup.new()
	for entry in [["", "All plots"]] + PLOT_SECTIONS:
		var key: String = entry[0]
		var button := UIStyle.button(entry[1])
		button.toggle_mode = true
		button.button_group = group
		button.add_theme_stylebox_override("pressed", Art.selected_tab())
		button.set_pressed_no_signal(key == _filter)
		var icon: Texture2D = AssetRegistry.skill_icon("farming") if key == "" else Art.texture(key + "_ready.png")
		button.icon = icon
		button.add_theme_constant_override("icon_max_width", UITokens.ICON_SM)
		button.pressed.connect(func(): _select_filter(key))
		filters.add_child(button)
		_filters[key] = button
	add_child(filters)


func _select_filter(key: String) -> void:
	_filter = key
	for id in _filters:
		_filters[id].set_pressed_no_signal(id == key)
	_rebuild()


func _reflow() -> void:
	for grid in _grids:
		grid.columns = 3 if size.x >= 900 else (2 if size.x >= 570 else 1)

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
	if not _built or not is_visible_in_tree():
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
	var in_use := 0
	var ready_by_type := {}
	for i in range(total):
		var plot: Dictionary = FarmingManager.plots[i]
		if str(plot["seed_id"]) != "":
			in_use += 1
		if FarmingManager.is_ready(i):
			var kind: String = plot["type"]
			ready_by_type[kind] = int(ready_by_type.get(kind, 0)) + 1
	var ready: int = FarmingManager.ready_count()
	_summary.text = "Cultivation Lv %d" % PlayerData.get_level("farming")
	_harvest_button.text = "Harvest all ready (%d)" % ready
	_harvest_button.disabled = ready == 0
	_seed_route.visible = _stored_seed_kinds() == 0
	_rebuild_stats(in_use, total, ready)
	for section in PLOT_SECTIONS:
		var filter_button: Button = _filters[section[0]]
		var section_ready: int = ready_by_type.get(section[0], 0)
		filter_button.text = "%s (%d ready)" % [section[1], section_ready] if section_ready > 0 else section[1]

	_grids.clear()
	for child in _sections.get_children():
		_sections.remove_child(child)
		child.queue_free()
	_tiles.clear()
	for section in PLOT_SECTIONS:
		var kind: String = section[0]
		if _filter != "" and kind != _filter:
			continue
		var grid := GridContainer.new()
		grid.add_theme_constant_override("h_separation", UITokens.SP_4)
		grid.add_theme_constant_override("v_separation", UITokens.SP_4)
		var plot_number := 0
		for i in range(total):
			if str(FarmingManager.plots[i]["type"]) == kind:
				plot_number += 1
				grid.add_child(_plot_card(i, "%s %d" % [section[2], plot_number]))
		if plot_number == 0:
			grid.free()
			continue
		var group := UIStyle.section("%s · %d plots" % [section[1], plot_number])
		group.add_child(grid)
		_sections.add_child(group)
		_grids.append(grid)
	_reflow()
	_last_categories = _categories()


func _rebuild_stats(in_use: int, total: int, ready: int) -> void:
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	_stats.add_child(Widgets.stat_chip("skills", "farming", "%d / %d occupied" % [in_use, total], "Plots with a planted crop"))
	_stats.add_child(Widgets.stat_chip("skills", "woodcutting", "%d ready" % ready,
		"Ready to harvest across the whole farm", UITokens.GOLD_BRIGHT if ready > 0 else UITokens.TEXT_MUTED))
	_stats.add_child(Widgets.stat_chip("items", "compost", "Compost ×%d" % BankManager.get_count("compost"),
		"Use in empty plots to improve survival"))
	_stats.add_child(Widgets.stat_chip("items", "ranch_manure", "Manure ×%d" % BankManager.get_count("ranch_manure"),
		"Use in empty plots to improve survival and yield"))

func _plot_card(index: int, name_text: String) -> Control:
	var state: String = _state_for(index)
	var plot: Dictionary = FarmingManager.plots[index]
	var seed: String = plot["seed_id"]
	var tier: int = plot.get("upgrade", 0)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UIStyle.surface_box("card", state == "ready"))
	card.set_meta("plot_index", index)
	card.set_meta("plot_state", state)
	var col := UIStyle.vbox(UITokens.SP_3)
	card.add_child(col)

	var identity := UIStyle.hbox(UITokens.SP_3)
	var name_label := Art.label(name_text, UITokens.TEXT_STRONG, UITokens.FONT_BODY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(name_label)
	identity.add_child(Widgets.badge(_badge_text(state), _badge_color(state), "Plot status"))
	col.add_child(identity)

	var scene := UIStyle.hbox(UITokens.SP_4)
	scene.add_child(Art.plot_picture(plot["type"], state))
	var details := UIStyle.vbox(UITokens.SP_2)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.alignment = BoxContainer.ALIGNMENT_CENTER
	scene.add_child(details)
	var crop_row := UIStyle.hbox(UITokens.SP_2)
	if seed != "":
		crop_row.add_child(Art.picture(AssetRegistry.icon("farming", FarmingManager.action_id_for_seed(seed)), Vector2(20, 20)))
	var soil_name: String = "Basic soil" if tier == 0 else str(FarmingManager.UPGRADES[tier - 1].name)
	var title := Art.label(soil_name if seed == "" else _crop_name(seed), _badge_color(state), UITokens.FONT_BODY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crop_row.add_child(title)
	details.add_child(crop_row)
	var state_label := Art.label(_state_text(index, state))
	details.add_child(state_label)
	var bar: ProgressBar = null
	if state in ["growing", "ready"]:
		bar = Widgets.progress_bar(_progress_value(index), maxf(1.0, _progress_max(index)), _badge_color(state),
			"", 5, "Crop growth", false)
		details.add_child(bar)
	col.add_child(scene)

	if seed != "" and plot.has("crop_survival"):
		col.add_child(Art.label("%s · %s · %.0f%% survival · +%d%% yield" % [
			soil_name, FarmingManager.METHODS[str(plot.get("method", "balanced"))].name,
			float(plot.crop_survival) * 100.0, int(plot.get("crop_yield_bonus", 0))], UITokens.TEXT_MUTED, UITokens.FONT_MICRO))
	if str(plot.get("last_seed", "")) != "":
		col.add_child(Art.label("Last harvest · " + _crop_name(str(plot.last_seed)), UITokens.TEXT_MUTED, UITokens.FONT_MICRO))
	if state == "empty":
		_build_soil_controls(col, index, plot, tier)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var buttons := UIStyle.vbox(UITokens.SP_2)
	col.add_child(buttons)
	_build_buttons(buttons, index, state)
	_tiles.append({"index": index, "state_label": state_label, "bar": bar})
	return card


func _build_soil_controls(col: VBoxContainer, index: int, plot: Dictionary, tier: int) -> void:
	var keys: Array = FarmingManager.METHODS.keys()
	var names: Array[String] = []
	for key in keys:
		names.append(str(FarmingManager.METHODS[key].name))
	var choice := Widgets.option_menu(names, func(i): FarmingManager.set_method(index, str(keys[i])),
		maxi(0, keys.find(str(plot.get("method", "balanced")))))
	choice.tooltip_text = "Growing method for the next crop. See Growing guide for the effects."
	col.add_child(choice)
	if tier >= FarmingManager.UPGRADES.size():
		return
	var next: Dictionary = FarmingManager.UPGRADES[tier]
	var upgrade := UIStyle.mini_button("Upgrade soil · Lv %d · %s GP" % [int(next.level), UIStyle.fmt(float(next.cost))])
	upgrade.tooltip_text = str(next.name) + ": +5% survival, +10% yield, 5% faster growth. Permanent; applies to future plantings."
	upgrade.disabled = PlayerData.get_level("farming") < int(next.level) or PlayerData.gp < float(next.cost)
	upgrade.pressed.connect(func(): FarmingManager.upgrade_plot(index))
	col.add_child(upgrade)

func _build_buttons(buttons: VBoxContainer, index: int, state: String) -> void:
	match state:
		"empty":
			var plant := MenuButton.new()
			plant.text = "Plant seed…"
			plant.add_theme_font_size_override("font_size", UITokens.FONT_SMALL)
			plant.custom_minimum_size = Vector2(0, UITokens.H_CONTROL)
			Art.button_icon(plant, "skills", "farming")
			plant.add_theme_stylebox_override("normal", Art.selected_tab())
			plant.add_theme_stylebox_override("hover", UIStyle.surface_box("raised", true))
			plant.get_popup().about_to_popup.connect(func(): _fill_planter(plant, index))
			plant.get_popup().id_pressed.connect(func(id: int):
				var popup := plant.get_popup()
				_plant(index, str(popup.get_item_metadata(popup.get_item_index(id)))))
			buttons.add_child(plant)
			if BankManager.get_count("compost") > 0 and int(FarmingManager.plots[index].compost) < 5:
				var compost := UIStyle.mini_button("Compost ×%d" % BankManager.get_count("compost"),
					"+10% survival when this plot is planted")
				Art.button_icon(compost, "items", "compost")
				compost.pressed.connect(func(): _compost(index))
				buttons.add_child(compost)
			if BankManager.has_item("ranch_manure", 1) and not bool(FarmingManager.plots[index].get("manure", false)):
				var manure := UIStyle.mini_button("Apply manure", "+25% survival and +10% yield for the next crop")
				Art.button_icon(manure, "items", "ranch_manure")
				manure.pressed.connect(func(): FarmingManager.apply_manure(index))
				buttons.add_child(manure)
		"ready":
			var harvest := UIStyle.primary_button("Harvest")
			Art.button_icon(harvest, "skills", "farming")
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
	var plot: Dictionary = FarmingManager.plots[index]
	match state:
		"empty":
			var prepared: PackedStringArray = []
			if int(plot["compost"]) > 0:
				prepared.append("Compost %d / 5" % int(plot["compost"]))
			if bool(plot.get("manure", false)):
				prepared.append("Manure applied")
			return "Ready to plant" if prepared.is_empty() else " · ".join(prepared)
		"dead":
			return "Clear this plot to plant again"
		"ready":
			return "Ready to harvest"
	var remaining: float = maxf(0.0, float(plot["planted_unix"]) + float(plot["grow_seconds"]) - Time.get_unix_time_from_system())
	var pct := int(round(_progress_value(index) / maxf(1.0, _progress_max(index)) * 100.0))
	return "%s left · %d%%" % [UIStyle.fmt_duration(ceilf(remaining)), pct]

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
	for o in _seed_options():
		var index: int = popup.item_count
		var label: String = "%s ×%d — Lv %d" % [str(o["name"]), int(o["count"]), int(o["level"])]
		if not bool(o["unlocked"]):
			label = "%s — locked until Lv %d" % [str(o["name"]), int(o["level"])]
		elif int(o["count"]) <= 0:
			label = "%s — none in storage" % str(o["name"])
		var fits: bool = FarmingManager.accepts(plot_index, str(o["id"]))
		if not fits:
			label = "%s — %s plots only" % [str(o["name"]), FarmingManager.seed_plot_type(str(o["id"])).capitalize()]
		var preview: Dictionary = FarmingManager.planting_preview(plot_index, str(o.id))
		var details := "%.0f%% survival · +%d%% yield · %s" % [float(preview.survival) * 100,
			int(preview.yield_bonus), UIStyle.fmt_duration(float(preview.seconds))]
		if bool(preview.rotated):
			details += " · Rotation bonus"
		popup.add_icon_item(AssetRegistry.icon("farming", FarmingManager.action_id_for_seed(str(o.id))), label, index)
		popup.set_item_disabled(index, not bool(o["unlocked"]) or int(o["count"]) <= 0 or not fits)
		popup.set_item_metadata(index, str(o["id"]))
		popup.set_item_tooltip(index, details)

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
