extends VBoxContainer
## SettlementPanel — Emberreach's structures.
##
## Favour unlocks and decisions over endless percentages: every structure states what it produces,
## what it costs, and which system it feeds. Production runs on real elapsed time, so it advances
## fully while the player is away and the panel says so plainly.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _resources_box: VBoxContainer
var _buildings_box: VBoxContainer
var _trader_box: VBoxContainer
var _worship_box: VBoxContainer
var _study_box: VBoxContainer
var _ticks: Label
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Emberreach", UITokens.FONT_DISPLAY))
	add_child(UIStyle.label(
		"A settlement produces on the hour, online or offline, from real elapsed time. Structures unlock systems as well as rates.",
		true, UITokens.FONT_SMALL))
	_ticks = UIStyle.label("", true, UITokens.FONT_MICRO)
	add_child(_ticks)
	_resources_box = UIStyle.section("Stores", "produced every hour")
	add_child(_resources_box)
	_buildings_box = UIStyle.section("Structures", "cost, effect and what it feeds")
	add_child(_buildings_box)
	_trader_box = UIStyle.section("Trader", "spend stores on what the frontier cannot make")
	add_child(_trader_box)
	_worship_box = UIStyle.section("Patron", "one blessing at a time, deepened by the Shrine")
	add_child(_worship_box)
	_study_box = UIStyle.section("Schoolhouse", "residents study one skill")
	add_child(_study_box)
	EventBus.state_refreshed.connect(refresh)
	EventBus.bank_changed.connect(_refresh_costs)
	refresh()

func focus_route(_route: Dictionary) -> void:
	pass

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Settlement",
		"body": "One production tick per hour of real time. Offline catch-up applies the same ticks, so growth continues while the game is closed."}

func refresh() -> void:
	if not _built:
		return
	_rebuild_resources()
	_rebuild_buildings()
	_rebuild_trader()
	_rebuild_worship()
	_rebuild_study()

func _rebuild_resources() -> void:
	for c in _resources_box.get_children():
		_resources_box.remove_child(c)
		c.queue_free()
	var total: float = 0.0
	for res_id in TownshipManager.ALL_RESOURCES:
		var amount: float = float(TownshipManager.resources.get(res_id, 0.0))
		total += amount
		var per_hour: float = TownshipManager.production_per_hour(res_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITokens.SP_4)
		var l := UIStyle.label(TownshipManager.resource_name(res_id), true, UITokens.FONT_SMALL)
		l.custom_minimum_size = Vector2(110, 0)
		row.add_child(l)
		row.add_child(UIStyle.colored_label(UIStyle.fmt(amount), UITokens.TEXT_STRONG, UITokens.FONT_SUBHEAD))
		row.add_child(UIStyle.colored_label("+%s / hour" % UIStyle.fmt(per_hour),
			UITokens.TEAL if per_hour > 0.0 else UITokens.TEXT_DIM, UITokens.FONT_MICRO))
		row.add_child(Widgets.badge(TownshipManager.resource_role(res_id), UITokens.BLUE,
			"What this resource is for"))
		_resources_box.add_child(row)
	_resources_box.add_child(Widgets.key_value("Residents", str(TownshipManager.productions_population()), UITokens.TEXT_MUTED,
		"Homes raise the settlement's population; population gates larger structures"))
	_resources_box.add_child(Widgets.key_value("Settlement XP / hour", UIStyle.fmt(TownshipManager.xp_per_hour()), UITokens.GOLD, "Earned each production tick from residents, online or offline"))
	_ticks.text = "Next production tick in %s  ·  total stored %s" % [
		UIStyle.fmt_duration(TownshipManager.seconds_to_next_tick()), UIStyle.fmt(total)]

func _rebuild_buildings() -> void:
	for c in _buildings_box.get_children():
		_buildings_box.remove_child(c)
		c.queue_free()
	var candidates: Array = DataLoader.township_buildings.keys()
	candidates.sort_custom(func(a, b): return float(TownshipManager.build_preview(str(a)).wait_hours) < float(TownshipManager.build_preview(str(b)).wait_hours))
	var next_id: String = ""
	for candidate in candidates:
		if not TownshipManager.is_max_level(str(candidate)): next_id = str(candidate); break
	if next_id != "": _buildings_box.add_child(UIStyle.label("Next structure: " + str(DataLoader.township_buildings[next_id].name), true, UITokens.FONT_SMALL))
	for building_id in candidates:
		var b: Dictionary = DataLoader.township_buildings[building_id]
		var level: int = int(TownshipManager.buildings.get(building_id, 0))
		var max_level: int = int(b.get("max_level", 5))
		var card := UIStyle.card(level >= max_level)
		var col := UIStyle.vbox(UITokens.SP_2)
		card.add_child(col)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", UITokens.SP_4)
		var title := UIStyle.title(str(b.get("name", building_id)), UITokens.FONT_SUBHEAD)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		head.add_child(Widgets.badge("Level %d / %d" % [level, max_level],
			UITokens.GREEN if level > 0 else UITokens.TEXT_MUTED, "Structure level"))
		col.add_child(head)
		if str(b.get("description", "")) != "":
			var d := UIStyle.label(str(b["description"]), true, UITokens.FONT_SMALL)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(d)
		var effects: Array[String] = []
		for res_id in (b.get("production", {}) as Dictionary).keys():
			effects.append("+%s %s / hour per level" % [UIStyle.fmt(float(b["production"][res_id])),
				TownshipManager.resource_name(str(res_id))])
		if not effects.is_empty():
			col.add_child(UIStyle.colored_label("Produces: " + "; ".join(effects), UITokens.TEAL, UITokens.FONT_MICRO))
		if str(b.get("unlocks", "")) != "":
			col.add_child(UIStyle.colored_label("Unlocks: %s" % str(b["unlocks"]), UITokens.GOLD_BRIGHT, UITokens.FONT_MICRO))

		if level < max_level:
			var forecast: Dictionary = TownshipManager.build_preview(str(building_id))
			col.add_child(UIStyle.label("Bottleneck: %s · ready %s · own-resource payback %s" % [forecast.bottleneck, "now" if bool(forecast.affordable) else "needs another producer" if is_inf(float(forecast.wait_hours)) else UIStyle.fmt_duration(float(forecast.wait_hours) * 3600), UIStyle.fmt_duration(float(forecast.payoff_hours) * 3600) if float(forecast.payoff_hours) > 0 else "support / unlock structure"], true, UITokens.FONT_SMALL))
			var cost: Dictionary = TownshipManager.scaled_cost(building_id)
			col.add_child(UIStyle.section("Cost to build level %d" % (level + 1)))
			var affordable: bool = true
			for res_id in cost.keys():
				var have: float = float(TownshipManager.resources.get(res_id, 0.0))
				var need: float = float(cost[res_id])
				if have < need:
					affordable = false
				col.add_child(Widgets.requirement_row(TownshipManager.resource_name(str(res_id)),
					have, need, have >= need, "produced every hour"))
			var build := UIStyle.primary_button("Build")
			build.disabled = not affordable
			build.tooltip_text = "Construct the next level of this structure" if affordable else "Not enough stored resources yet"
			var bid: String = building_id
			build.pressed.connect(func():
				if TownshipManager.build(bid):
					refresh())
			col.add_child(build)
		else:
			col.add_child(UIStyle.colored_label("Fully built.", UITokens.GREEN, UITokens.FONT_MICRO))
		_buildings_box.add_child(card)

## Stores in, useful items out. Without this the settlement's resources would only ever feed
## more construction, which is exactly the disconnected-currency trap to avoid.
func _rebuild_trader() -> void:
	for c in _trader_box.get_children():
		_trader_box.remove_child(c)
		c.queue_free()
	var offers: Array = TownshipManager.offers()
	if offers.is_empty():
		_trader_box.add_child(UIStyle.label("No trader offers are defined in this build.", true, UITokens.FONT_SMALL))
		return
	for offer in offers:
		var offer_id: String = str(offer.get("id", ""))
		var check: Dictionary = TownshipManager.can_trade(offer_id)
		var card := UIStyle.card(bool(check["ok"]))
		var col := UIStyle.vbox(UITokens.SP_2)
		card.add_child(col)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", UITokens.SP_4)
		var title := UIStyle.label(str(offer.get("name", offer_id)), false, UITokens.FONT_BODY)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		head.add_child(Widgets.badge("Gives: %s" % TownshipManager.describe_offer(offer),
			UITokens.GOLD_BRIGHT, "Exactly what this trade delivers"))
		col.add_child(head)
		if str(offer.get("description", "")) != "":
			var d := UIStyle.label(str(offer["description"]), true, UITokens.FONT_SMALL)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(d)
		var required: String = str(offer.get("requires_building", ""))
		if required != "":
			col.add_child(Widgets.requirement_row(
				str(TownshipManager.buildings_data().get(required, {}).get("name", required)),
				float(TownshipManager.level_of(required)), 1.0, TownshipManager.level_of(required) > 0,
				"Built in this settlement" if TownshipManager.level_of(required) > 0 else "Build it first"))
		for res_id in (offer.get("cost", {}) as Dictionary).keys():
			var have: float = float(TownshipManager.resources.get(res_id, 0.0))
			var need: float = float(offer["cost"][res_id])
			col.add_child(Widgets.requirement_row(TownshipManager.resource_name(str(res_id)),
				have, need, have >= need, "produced every hour"))
		var button := UIStyle.primary_button("Trade")
		button.disabled = not bool(check["ok"])
		button.tooltip_text = "Exchange the stores listed above" if bool(check["ok"]) else str(check["reason"])
		var oid: String = offer_id
		button.pressed.connect(func():
			TownshipManager.trade_offer(oid)
			refresh())
		col.add_child(button)
		if not bool(check["ok"]):
			col.add_child(UIStyle.colored_label(str(check["reason"]), UITokens.AMBER, UITokens.FONT_MICRO))
		_trader_box.add_child(card)

## Patrons from data/worship.json. The blessing scales with the Shrine, so without one the
## choice is shown but locked. set_worship() emits state_refreshed, which rebuilds this list.
func _rebuild_worship() -> void:
	for c in _worship_box.get_children():
		_worship_box.remove_child(c)
		c.queue_free()
	var shrine: int = TownshipManager.level_of("township_building_temple")
	if shrine <= 0:
		_worship_box.add_child(UIStyle.label("Build a Shrine to choose a patron. Each Shrine level deepens the blessing.", true, UITokens.FONT_SMALL))
	for patron_id in DataLoader.worship.keys():
		var p: Dictionary = DataLoader.worship[patron_id]
		var pid: String = str(patron_id)
		var active: bool = TownshipManager.worship == pid
		var card := UIStyle.card(active)
		var col := UIStyle.vbox(UITokens.SP_2)
		card.add_child(col)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", UITokens.SP_4)
		var title := UIStyle.label(str(p.get("name", pid)), false, UITokens.FONT_BODY)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var effects: Array[String] = []
		for key in (p.get("modifiers", {}) as Dictionary).keys():
			effects.append("+%s%% %s" % [UIStyle.fmt(float(p["modifiers"][key])),
				str(key).trim_suffix("_percent").replace("_", " ")])
		head.add_child(Widgets.badge("; ".join(effects) + " per Shrine level", UITokens.GOLD_BRIGHT, "Granted once per Shrine level"))
		col.add_child(head)
		if str(p.get("description", "")) != "":
			var d := UIStyle.label(str(p["description"]), true, UITokens.FONT_SMALL)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(d)
		var button := UIStyle.primary_button("✓ Current patron" if active else "Worship")
		button.disabled = active or shrine <= 0
		button.tooltip_text = "Already your patron" if active else ("Build a Shrine first" if shrine <= 0 else "Switch your patron; switching is free")
		button.pressed.connect(func(): TownshipManager.set_worship(pid))
		col.add_child(button)
		_worship_box.add_child(card)

## The Schoolhouse: pick the one skill the residents study. Choosing emits state_refreshed, which rebuilds this box.
func _rebuild_study() -> void:
	for c in _study_box.get_children():
		_study_box.remove_child(c)
		c.queue_free()
	var level: int = TownshipManager.level_of(TownshipManager.SCHOOL_ID)
	if level <= 0:
		_study_box.add_child(UIStyle.label("Build a Schoolhouse to set the residents studying a skill. Each level adds XP every hour.", true, UITokens.FONT_SMALL))
		return
	var ids: Array[String] = [""]
	ids.append_array(TownshipManager.study_options())
	var labels: Array[String] = []
	for id in ids:
		labels.append("Nothing" if id == "" else str(DataLoader.get_skill(id).get("name", id)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_4)
	row.add_child(UIStyle.label("Residents study", true, UITokens.FONT_SMALL))
	var menu := Widgets.option_menu(labels, func(i): TownshipManager.set_study(ids[clampi(i, 0, ids.size() - 1)]), maxi(0, ids.find(TownshipManager.study)))
	menu.tooltip_text = "Switching is free. Studying pays the skill XP every settlement tick."
	row.add_child(menu)
	_study_box.add_child(row)
	var rate: float = TownshipManager.study_xp_per_hour()
	_study_box.add_child(UIStyle.colored_label("+%s XP / hour (Schoolhouse level %d)" % [UIStyle.fmt(rate), level] if rate > 0.0 else "Nobody is studying.", UITokens.TEAL if rate > 0.0 else UITokens.TEXT_DIM, UITokens.FONT_MICRO))

func _refresh_costs() -> void:
	if _built:
		_rebuild_buildings()
