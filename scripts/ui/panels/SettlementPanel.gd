extends VBoxContainer
## Settlement overview, construction, wonders, trader and civic choices.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

const Art = preload("res://scripts/ui/panels/SettlementArt.gd")
const PAGES := {
	"town": ["Locations", "township_building_homes"],
	"stores": ["Stores", "township_building_storehouse"],
	"wonders": ["Wonders", "wonder_astral_observatory"],
	"trader": ["Trader", "township_building_storehouse"],
	"civic": ["Patron & Study", "civic_hall"],
}
const PATRON_ART := {
	"patron_gale": "air_rune", "patron_tide": "water_rune",
	"patron_stone": "earth_rune", "patron_ember": "fire_rune",
}

var _hero_art: TextureRect
var _hero_title: Label
var _hero_details: Label
var _hero_role: Label
var _tick_label: Label
var _tick_progress: ProgressBar
var _landscapes: Dictionary = {}
var _location := TownshipManager.DEFAULT_LOCATION
var _location_grid: GridContainer
var _location_buttons: Dictionary = {}
var _wonder_art: Texture2D
var _tabs: GridContainer
var _buttons: Dictionary = {}
var _pages: Dictionary = {}
var _grids: Dictionary = {}
var _resources: GridContainer
var _study: VBoxContainer
var _next_build: Label
var _page := ""


func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in TownshipManager.LOCATIONS:
		_landscapes[id] = Art.art(TownshipManager.LOCATIONS[id].art)
	_wonder_art = Art.art("wonders.webp")
	_build_hero()
	_build_navigation()

	var town: VBoxContainer = _pages["town"]
	var places := Art.section("Settlement locations", Art.structure_icon("civic_hall"))
	town.add_child(places)
	_location_grid = Art.grid()
	places.add_child(_location_grid)
	_build_location_buttons()
	var stores := Art.section("Shared stores", Art.resource_icon("goods"),
		"All locations produce into and build from these same stores.")
	_pages["stores"].add_child(stores)
	_resources = Art.grid()
	stores.add_child(_resources)
	_grids["structures"] = _section_grid(town, "Structures", "township_building_workshop")
	_next_build = Art.copy("", UITokens.GOLD_BRIGHT)
	_grids["structures"].get_parent().add_child(_next_build)
	_grids["structures"].get_parent().move_child(_next_build, 1)
	_grids["specializations"] = _section_grid(town, "Local specialization", "township_building_smelter",
		"Each location can specialize once. Its bonuses benefit the settlement network.")
	_grids["wonders"] = _section_grid(_pages["wonders"], "Wonder projects", "wonder_astral_observatory",
		"Complete three permanent stages to unlock legendary expeditions.")
	_grids["trades"] = _section_grid(_pages["trader"], "Trader offers", "township_building_storehouse")
	_grids["patrons"] = _section_grid(_pages["civic"], "Patrons", "township_building_temple",
		"Choose one patron. Each Shrine level deepens their blessing.")
	var study_section := Art.section("Schoolhouse", Art.structure_icon(TownshipManager.SCHOOL_ID))
	_pages["civic"].add_child(study_section)
	_study = Art.card(study_section)

	resized.connect(_update_grid_columns)
	EventBus.bank_changed.connect(_refresh_project_costs)
	_select_page("town")
	_update_grid_columns()

	var clock := Timer.new()
	clock.wait_time = 1.0
	clock.autostart = true
	clock.timeout.connect(_update_clock)
	add_child(clock)


func _build_hero() -> void:
	var frame := Art.hero()
	frame.custom_minimum_size.y = 220
	add_child(frame)
	_hero_art = Art.texture_rect(_landscapes[_location], Vector2.ZERO, false)
	_hero_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(_hero_art)
	var shade := Art.hero_shade()
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	frame.add_child(shade)

	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_left", UITokens.SP_6)
	inset.add_theme_constant_override("margin_right", UITokens.SP_5)
	inset.add_theme_constant_override("margin_top", UITokens.SP_5)
	inset.add_theme_constant_override("margin_bottom", UITokens.SP_5)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(inset)
	var content := UIStyle.vbox(UITokens.SP_3)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(content)

	_hero_title = UIStyle.title("Emberreach", UITokens.SP_8)
	_hero_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_hero_title)
	_hero_role = Art.copy("", UITokens.TEAL)
	content.add_child(_hero_role)
	_hero_details = Art.copy("", UITokens.TEXT_STRONG, UITokens.FONT_BODY)
	content.add_child(_hero_details)
	var clock_line := UIStyle.hbox(UITokens.SP_2)
	clock_line.add_child(Art.texture_rect(Art.icon("navigation", "action_queue"), Vector2(18, 18)))
	_tick_label = Art.copy("", UITokens.GOLD_BRIGHT)
	_tick_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_line.add_child(_tick_label)
	content.add_child(clock_line)
	var clock_width := UIStyle.hbox()
	_tick_progress = Widgets.progress_bar(0, TownshipManager.SECONDS_PER_TICK, UITokens.GOLD,
		"", 5, "Production continues while the game is closed.", false)
	_tick_progress.custom_minimum_size.x = 158
	clock_width.add_child(_tick_progress)
	content.add_child(clock_width)


func _build_navigation() -> void:
	_tabs = Art.grid()
	add_child(_tabs)
	var group := ButtonGroup.new()
	for key in PAGES:
		var page_id: String = key
		var info: Array = PAGES[key]
		var button := _navigation_button(info[0], info[1])
		button.button_group = group
		button.pressed.connect(func(): _select_page(page_id))
		_tabs.add_child(button)
		_buttons[key] = button
		var page := UIStyle.vbox(UITokens.SP_5)
		page.hide()
		add_child(page)
		_pages[key] = page


func _navigation_button(label: String, icon_id: String) -> Button:
	var button := UIStyle.button(label)
	button.icon = Art.structure_icon(icon_id)
	button.add_theme_constant_override("icon_max_width", 22)
	button.add_theme_color_override("font_color", UITokens.TEXT_MUTED)
	button.add_theme_color_override("font_pressed_color", UITokens.TEXT_STRONG)
	button.add_theme_color_override("font_hover_pressed_color", UITokens.TEXT_STRONG)
	var selected := UIStyle.flat_box("button", true)
	selected.bg_color = UITokens.SURFACE_3
	selected.border_color = UITokens.GOLD_BRIGHT
	selected.border_width_bottom = 2
	button.add_theme_stylebox_override("pressed", selected)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	return button


func _build_location_buttons() -> void:
	var group := ButtonGroup.new()
	for id: String in TownshipManager.LOCATIONS:
		var place: Dictionary = TownshipManager.LOCATIONS[id]
		var button := _navigation_button(place.name, place.icon)
		button.tooltip_text = place.role
		button.custom_minimum_size.y = 40
		button.button_group = group
		button.pressed.connect(func(): _select_location(id))
		_location_buttons[id] = button
		_location_grid.add_child(button)


func _select_location(id: String) -> void:
	if not TownshipManager.LOCATIONS.has(id):
		return
	_location = id
	_update_location_header()
	refresh()


func _update_location_header() -> void:
	for id in _location_buttons:
		_location_buttons[id].set_pressed_no_signal(id == _location)
	var using_location := _page == "town"
	_hero_role.visible = using_location
	_hero_role.text = TownshipManager.LOCATIONS[_location].role
	_hero_art.texture = _wonder_art if _page == "wonders" else (
		_landscapes[_location] if using_location else _landscapes[TownshipManager.DEFAULT_LOCATION])
	match _page:
		"town":
			_hero_title.text = TownshipManager.LOCATIONS[_location].name
		"wonders":
			_hero_title.text = "Settlement Wonders"
		"stores":
			_hero_title.text = "Shared Stores"
		"trader":
			_hero_title.text = "Emberreach Market"
		"civic":
			_hero_title.text = "Patron & Study"


func _section_grid(parent: VBoxContainer, title: String, art_id: String, hint := "") -> GridContainer:
	var section := Art.section(title, Art.structure_icon(art_id), hint)
	parent.add_child(section)
	var grid := Art.grid()
	section.add_child(grid)
	return grid


func _update_grid_columns() -> void:
	_tabs.columns = 5 if size.x >= 650 else (3 if size.x >= 480 else 2)
	_location_grid.columns = 3 if size.x >= 660 else 2
	_resources.columns = 5 if size.x >= 900 else (3 if size.x >= 600 else 2)
	for key in _grids:
		var grid: GridContainer = _grids[key]
		var desktop_columns: int = {"wonders": 2, "patrons": 4, "specializations": 1}.get(key, 3)
		grid.columns = desktop_columns if size.x >= 1040 else (2 if size.x >= 600 else 1)


func _select_page(id: String) -> void:
	if id == _page:
		return
	_page = id
	for key in _pages:
		_pages[key].visible = key == id
		_buttons[key].set_pressed_no_signal(key == id)
	_update_location_header()
	var scroll := get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0
	refresh()


func focus_route(route: Dictionary) -> void:
	var id := str(route.get("location", _location))
	var building: Dictionary = DataLoader.township_buildings.get(str(route.get("building_id", "")), {})
	if not building.is_empty():
		id = TownshipManager.location_of(building)
	if TownshipManager.LOCATIONS.has(id):
		_location = id
	var page := "wonders" if bool(route.get("wonders", false)) or bool(building.get("is_wonder", false)) else "town"
	if _page == page:
		_update_location_header()
		refresh()
	else:
		_select_page(page)


func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Settlement",
		"body": "One production tick per hour of real time. Offline catch-up applies the same ticks, so growth continues while the game is closed."}


func refresh() -> void:
	if _page == "" or Widgets.defer_offscreen_rebuild(self, refresh):
		return
	_hero_details.text = "Township Lv %d  ·  %d residents  ·  %s XP/h" % [
		PlayerData.get_level("township"), TownshipManager.productions_population(), UIStyle.fmt(TownshipManager.xp_per_hour())]
	_update_clock()
	match _page:
		"town":
			_rebuild_structures(false)
			_rebuild_specializations()
		"stores":
			_rebuild_stores()
		"wonders":
			_rebuild_structures(true)
		"trader":
			_rebuild_trader()
		"civic":
			_rebuild_civic()


func _update_clock() -> void:
	if not is_visible_in_tree():
		return
	var seconds: float = TownshipManager.seconds_to_next_tick()
	_tick_label.text = "Production in %s" % UIStyle.fmt_duration(ceilf(seconds))
	_tick_progress.value = TownshipManager.SECONDS_PER_TICK - seconds


func _refresh_project_costs() -> void:
	if _page == "wonders" and is_visible_in_tree():
		_rebuild_structures(true)


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _rebuild_stores() -> void:
	_clear(_resources)
	for id in TownshipManager.ALL_RESOURCES:
		var label: String = TownshipManager.resource_name(id)
		var amount: float = float(TownshipManager.resources.get(id, 0.0))
		var per_hour: float = TownshipManager.production_per_hour(id)
		var body := Art.card(_resources)
		var row := UIStyle.hbox(UITokens.SP_3)
		body.add_child(row)
		row.add_child(Art.texture_rect(Art.resource_icon(id), Vector2(30, 30)))
		var info := UIStyle.vbox(UITokens.SP_1)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(Art.copy(label, UITokens.TEXT))
		var amounts := UIStyle.hbox(UITokens.SP_3)
		info.add_child(amounts)
		amounts.add_child(Art.copy(UIStyle.fmt(amount), UITokens.TEXT_STRONG, UITokens.FONT_HEAD))
		var rate := Art.copy("+%s / h" % UIStyle.fmt(per_hour),
			UITokens.TEAL if per_hour > 0.0 else UITokens.TEXT_DIM, UITokens.FONT_MICRO)
		rate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rate.tooltip_text = "Production per hour"
		amounts.add_child(rate)
		body.add_child(Art.copy(TownshipManager.resource_role(id), UITokens.TEXT_MUTED, UITokens.FONT_MICRO))


func _rebuild_structures(wonders: bool) -> void:
	var grid: GridContainer = _grids["wonders" if wonders else "structures"]
	_clear(grid)
	var ids: Array[String] = []
	var forecasts: Dictionary = {}
	for id in DataLoader.township_buildings:
		var structure: Dictionary = DataLoader.township_buildings[id]
		if bool(structure.get("is_wonder", false)) == wonders and (wonders or TownshipManager.location_of(structure) == _location):
			ids.append(id)
			forecasts[id] = TownshipManager.build_preview(id)
	if not wonders:
		var ordered: Array[String] = ids.duplicate()
		ids.sort_custom(func(a: String, b: String) -> bool:
			var a_done: bool = TownshipManager.is_max_level(a)
			var b_done: bool = TownshipManager.is_max_level(b)
			if a_done != b_done:
				return not a_done
			var left: Dictionary = forecasts[a]
			var right: Dictionary = forecasts[b]
			if left.affordable != right.affordable:
				return left.affordable
			if left.wait_hours != right.wait_hours:
				return left.wait_hours < right.wait_hours
			return ordered.find(a) < ordered.find(b))
		_next_build.visible = not ids.is_empty()
		if not ids.is_empty():
			var first: String = ids[0]
			_next_build.text = "All structures complete" if TownshipManager.is_max_level(first) else (
				"Next structure · %s" % DataLoader.township_buildings[first].name)
	for id in ids:
		_structure_card(grid, id, DataLoader.township_buildings[id], forecasts[id], wonders)


func _structure_card(grid: GridContainer, id: String, data: Dictionary, forecast: Dictionary, wonder: bool) -> void:
	var level: int = TownshipManager.level_of(id)
	var max_level: int = TownshipManager.max_level_of(id)
	var complete: bool = level >= max_level
	var body := Art.card(grid, bool(forecast.affordable) or complete)
	body.get_parent().set_meta("structure_id", id)
	var caption := "%s %d / %d" % ["Stage" if wonder else "Level", level, max_level]
	var heading_caption := caption
	if wonder:
		heading_caption += "  ·  " + str(TownshipManager.LOCATIONS[TownshipManager.location_of(data)].name)
	body.add_child(Art.card_heading(str(data.get("name", id)), Art.structure_icon(id), heading_caption, true))
	body.add_child(Widgets.progress_bar(level, max_level, UITokens.TEAL, "", 4, caption, false))
	if wonder and not complete:
		var stages: Array = data.get("stage_names", [])
		if level < stages.size():
			body.add_child(Art.copy("Next stage · " + str(stages[level]), UITokens.GOLD_BRIGHT))

	body.add_child(Art.copy(str(data.get("description", ""))))
	var outputs := Art.chips()
	for res in data.get("production", {}):
		var amount := UIStyle.fmt(float(data.production[res]))
		var name: String = TownshipManager.resource_name(res)
		var rate := "+%s %s" % [amount, name] if res == "population" else "+%s %s / h" % [amount, name]
		outputs.add_child(Art.chip(Art.resource_icon(res), rate, UITokens.TEAL, "Output per level"))
	if outputs.get_child_count() > 0:
		body.add_child(outputs)
	else:
		outputs.free()
	if data.get("unlocks", "") != "":
		body.add_child(Art.copy("Unlocks · %s" % data.unlocks, UITokens.GOLD_BRIGHT, UITokens.FONT_MICRO))

	if complete:
		body.add_child(Art.copy("Fully built", UITokens.GREEN))
		return
	_add_build_action(body, id, data, forecast, wonder, level)


func _add_build_action(body: VBoxContainer, id: String, data: Dictionary, forecast: Dictionary, wonder: bool, level: int) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	body.add_child(HSeparator.new())
	body.add_child(Art.copy("Build cost", UITokens.TEXT_STRONG, UITokens.FONT_MICRO))
	Art.resource_costs(body, TownshipManager.scaled_cost(id))
	if wonder:
		for skill in data.get("requires", {}):
			var need: int = int(data.requires[skill])
			var have: int = PlayerData.get_level(skill)
			body.add_child(Art.requirement(Art.icon("skills", skill),
				str(DataLoader.get_skill(skill).get("name", skill)), have, need))
		var items: Dictionary = TownshipManager.project_item_cost(id)
		for item in items:
			var need: int = int(items[item])
			var have: int = BankManager.get_count(item)
			body.add_child(Art.requirement(Art.icon("items", item),
				str(DataLoader.get_item(item).get("name", item)), have, need))
		var gold: float = TownshipManager.project_gp_cost(id)
		if gold > 0.0:
			body.add_child(Art.requirement(Art.icon("currencies", "gp"), "Gold", PlayerData.gp, gold))

	var check: Dictionary = TownshipManager.can_build(id)
	var wait: float = forecast.wait_hours
	var payoff: float = forecast.payoff_hours
	var estimate := ""
	if wait > 0.0 and not is_inf(wait):
		estimate = "%s in %s" % [forecast.bottleneck, UIStyle.fmt_duration(wait * 3600.0)]
	if payoff > 0.0:
		estimate += ("  ·  " if estimate != "" else "") + "Payback %s" % UIStyle.fmt_duration(payoff * 3600.0)
	if estimate != "":
		body.add_child(Art.copy(estimate, UITokens.TEXT_MUTED, UITokens.FONT_MICRO))
	if not check.ok:
		body.add_child(Art.copy(str(check.reason), UITokens.AMBER, UITokens.FONT_MICRO))
	var action := "Build stage" if wonder else ("Upgrade" if level > 0 else "Build")
	var button := UIStyle.primary_button(action, "Construct the next level" if check.ok else str(check.reason))
	button.disabled = not check.ok
	button.pressed.connect(func(): TownshipManager.build(id))
	body.add_child(button)


func _rebuild_specializations() -> void:
	var grid: GridContainer = _grids["specializations"]
	_clear(grid)
	for id in DataLoader.settlement_specializations:
		var spec: Dictionary = DataLoader.settlement_specializations[id]
		if TownshipManager.location_of(spec) != _location:
			continue
		var selected: bool = TownshipManager.specialization_at(_location) == id
		var body := Art.card(grid, selected)
		body.get_parent().set_meta("specialization_id", id)
		body.add_child(Art.card_heading(str(spec.get("name", id)), Art.structure_icon(id), "", true))
		body.add_child(Art.copy(str(spec.get("description", ""))))
		var bonuses := Art.chips()
		for res in spec.get("production_bonus", {}):
			bonuses.add_child(Art.chip(Art.resource_icon(res), "+%s%% %s" % [
				UIStyle.fmt(float(spec.production_bonus[res])), TownshipManager.resource_name(res)], UITokens.TEAL))
		body.add_child(bonuses)
		body.add_child(Art.chip(Art.icon("currencies", "gp"), "%s GP" % UIStyle.fmt(float(spec.get("gp_cost", 0)))))
		Art.resource_costs(body, spec.get("store_cost", {}))
		var blocker: String = TownshipManager.specialization_blocker(id)
		var button := UIStyle.primary_button("Current specialization" if selected else "Specialize", blocker)
		button.disabled = selected or blocker != ""
		button.pressed.connect(func(): TownshipManager.choose_specialization(id))
		if blocker != "" and not selected:
			body.add_child(Art.copy(blocker, UITokens.AMBER, UITokens.FONT_MICRO))
		body.add_child(button)


func _rebuild_trader() -> void:
	var grid: GridContainer = _grids["trades"]
	_clear(grid)
	for offer in TownshipManager.offers():
		var id: String = str(offer.get("id", ""))
		var check: Dictionary = TownshipManager.can_trade(id)
		var body := Art.card(grid, bool(check.ok))
		var items: Dictionary = offer.get("grant_items", {})
		var currencies: Dictionary = offer.get("grant_currency", {})
		var required: String = str(offer.get("requires_building", ""))
		var image := Art.structure_icon(required)
		if not items.is_empty():
			image = Art.icon("items", items.keys()[0])
		elif not currencies.is_empty():
			image = Art.icon("currencies", currencies.keys()[0])
		body.add_child(Art.card_heading(str(offer.get("name", id)), image))
		body.add_child(Art.copy(TownshipManager.describe_offer(offer), UITokens.GOLD_BRIGHT))
		body.add_child(Art.copy(str(offer.get("description", ""))))
		Art.resource_costs(body, offer.get("cost", {}))
		if not check.ok:
			body.add_child(Art.copy(str(check.reason), UITokens.AMBER, UITokens.FONT_MICRO))
		var button := UIStyle.primary_button("Trade", "Exchange the listed stores" if check.ok else str(check.reason))
		button.disabled = not check.ok
		button.pressed.connect(func(): TownshipManager.trade_offer(id))
		body.add_child(button)
	if grid.get_child_count() == 0:
		grid.add_child(Art.copy("No offers available."))


func _rebuild_civic() -> void:
	var grid: GridContainer = _grids["patrons"]
	_clear(grid)
	_clear(_study)
	var shrine: int = TownshipManager.level_of("township_building_temple")
	for id in DataLoader.worship:
		var patron: Dictionary = DataLoader.worship[id]
		var active: bool = TownshipManager.worship == id
		var body := Art.card(grid, active)
		body.add_child(Art.card_heading(str(patron.get("name", id)), Art.icon("items", PATRON_ART.get(id, "air_rune"))))
		body.add_child(Art.copy(str(patron.get("description", ""))))
		var effects: PackedStringArray = []
		for key in patron.get("modifiers", {}):
			effects.append("+%s%% %s" % [UIStyle.fmt(float(patron.modifiers[key])),
				str(key).trim_suffix("_percent").replace("_", " ")])
		body.add_child(Art.copy("  ·  ".join(effects), UITokens.GOLD_BRIGHT, UITokens.FONT_MICRO))
		var button := UIStyle.primary_button("Current patron" if active else "Worship",
			"Build a Shrine first" if shrine <= 0 else "Switching is free")
		button.disabled = active or shrine <= 0
		button.pressed.connect(func(): TownshipManager.set_worship(id))
		if shrine <= 0:
			body.add_child(Art.copy("Requires a Shrine", UITokens.AMBER, UITokens.FONT_MICRO))
		body.add_child(button)

	var level: int = TownshipManager.level_of(TownshipManager.SCHOOL_ID)
	if level <= 0:
		_study.add_child(Art.copy("Build a Schoolhouse to choose a skill for residents to study."))
		return
	var ids: Array[String] = [""]
	ids.append_array(TownshipManager.study_options())
	var labels: Array[String] = []
	for id in ids:
		labels.append("Nothing" if id == "" else str(DataLoader.get_skill(id).get("name", id)))
	var menu := Widgets.option_menu(labels, func(i): TownshipManager.set_study(ids[i]), maxi(0, ids.find(TownshipManager.study)))
	menu.tooltip_text = "Skill studied each production tick. Switching is free."
	_study.add_child(Art.copy("Residents study", UITokens.TEXT_STRONG))
	_study.add_child(menu)
	var rate: float = TownshipManager.study_xp_per_hour()
	_study.add_child(Art.copy("+%s XP / hour · Schoolhouse Lv %d" % [UIStyle.fmt(rate), level] if rate > 0.0
		else "Nobody is studying.", UITokens.TEAL if rate > 0.0 else UITokens.TEXT_MUTED))

