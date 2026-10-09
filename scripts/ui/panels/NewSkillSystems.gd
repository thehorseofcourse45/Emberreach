extends VBoxContainer
signal navigated(route: Dictionary)
const CaravanMap = preload("res://scripts/ui/CaravanJourneyMap.gd")
## Skill-specific controls use the same cards, sprites and progress bars as the rest of the UI.
var skill_id: String = ""
var _live_pens: Array = []
var _live_workers: Array = []
var _live_caravans: Array = []

# The caravan planner keeps its choices across the panel rebuilds a refresh causes.
static var _caravan_thumbnails: Dictionary = {}
static var _cv_route: String = ""
static var _cv_wagon: String = "handcart"
static var _cv_guard: String = "hired_hand"
static var _cv_cargo: Dictionary = {}

func set_skill(id: String) -> void:
	skill_id = id
	build()

func _button(parent: Control, text: String, callback: Callable, enabled: bool = true, hint: String = "") -> Button:
	var button := UIStyle.button(text, hint)
	button.disabled = not enabled
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _choice(parent: Control, ids: Array, names: Array, icons: Array = []) -> OptionButton:
	var select := OptionButton.new()
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.custom_minimum_size = Vector2(140, 36)
	select.clip_text = true
	select.fit_to_longest_item = false
	select.add_theme_constant_override("icon_max_width", 32)
	if ids.is_empty():
		select.add_item("Nothing available")
		select.disabled = true
	for i in range(ids.size()):
		if i < icons.size():
			select.add_icon_item(icons[i], str(names[i]))
		else:
			select.add_item(str(names[i]))
	parent.add_child(select)
	return select

func _card(title: String, body: String) -> VBoxContainer:
	var box := UIStyle.section(title, body)
	add_child(box)
	return box

func _flow() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UITokens.SP_3)
	row.add_theme_constant_override("v_separation", UITokens.SP_3)
	return row

func build() -> void:
	var task: String = skill_id + "_foundation"
	if not Quests.get_quest(task).is_empty() and not Quests.is_claimed(task):
		var guide := _card("First steps · " + skill_id.capitalize(), str(Quests.get_quest(task).description))
		_button(guide, "Track starter objective", func(): Goals.pin("quest", task))
	match skill_id:
		"ranching": _ranch()
		"inscription": _inscription()
		"engineering": _engineering()
		"enchanting": _enchanting()
		"dreamwalking": _dreams()
		"caravaneering": _caravans()

func _caravans() -> void:
	var cm = CaravaneeringManager
	_live_caravans.clear()
	var box := _card("Trade caravans", "%d of %d caravan slots in use. Choose a route, wagon, guard and cargo; the caravan sells at the destination and returns with its specialty goods, even while you are away." % [cm.caravans.size(), cm.slots()])
	for index in range(cm.caravans.size()):
		var c: Dictionary = cm.caravans[index]
		var r: Dictionary = cm.route(str(c.route))
		var panel := UIStyle.section(str(r.get("name", c.route)), "%s · %s wagon · %s" % [str(c.status), str(cm.wagon(str(c.wagon)).get("name", "")), str(cm.guard(str(c.guard)).get("name", ""))])
		box.add_child(panel)
		var bar := Widgets.progress_bar(float(c.total) - float(c.remaining), maxf(float(c.total), 1.0), UITokens.GOLD, "Trip progress", 18)
		panel.add_child(bar)
		var eta := UIStyle.label("", true, UITokens.FONT_SMALL)
		panel.add_child(eta)
		_live_caravans.append({"index": index, "bar": bar, "eta": eta})
		panel.add_child(Widgets.item_rewards(c.cargo))
		_button(panel, "Open journey map", func(): _open_caravan_map(str(c.route), c.get("journey", {})))
		var row := _flow()
		panel.add_child(row)
		var repeat := CheckBox.new()
		repeat.text = "Repeat these orders"
		repeat.button_pressed = bool(c.repeat)
		repeat.toggled.connect(func(on: bool): cm.set_repeat(index, on))
		row.add_child(repeat)
		if bool(c.get("idle", false)):
			_button(row, "Resume", func(): cm.resume(index), true, "Send it out again on the same orders (restock Storage and gold first)")
			_button(row, "Dismiss", func(): cm.dismiss(index), true, "Free this slot")
	var plan := _card("Plan a trip", "Prices drift daily; goods a destination wants pay 30-60% more. Each trip visits five reward stops. Inspect its journey map to choose cautious, balanced or bold orders before danger strikes; guards protect cargo, but weather and broken roads still carry risk.")
	var route_ids: Array = []
	var route_names: Array = []
	var route_icons: Array = []
	var level: int = PlayerData.get_level("caravaneering")
	for r in cm.routes():
		route_ids.append(str(r.id))
		var image_path: String = "res://assets/caravans/maps/%s.png" % str(r.id)
		if not _caravan_thumbnails.has(image_path) and ResourceLoader.exists(image_path):
			var source: Texture2D = load(image_path)
			var image: Image = source.get_image()
			if image.is_compressed(): image.decompress()
			image.resize(32, 21, Image.INTERPOLATE_LANCZOS)
			_caravan_thumbnails[image_path] = ImageTexture.create_from_image(image)
		route_icons.append(_caravan_thumbnails.get(image_path, AssetRegistry.icon("skills", "caravaneering")))
		var note: String = ""
		if level < int(r.level): note = " · unlocks at level %d" % int(r.level)
		route_names.append("%s · %.1fh%s" % [str(r.name), float(r.hours), note])
	var route_choice := _choice(plan, route_ids, route_names, route_icons)
	var destination := UIStyle.label("", true, UITokens.FONT_SMALL)
	destination.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plan.add_child(destination)
	_button(plan, "Preview destination map", func(): _open_caravan_map(_cv_route))
	var demand_box := UIStyle.vbox()
	plan.add_child(demand_box)
	var returns_box := UIStyle.vbox()
	plan.add_child(returns_box)
	# Locked routes remain inspectable; can_dispatch enforces level requirements.
	var wagon_ids: Array = []
	var wagon_names: Array = []
	for w in cm.wagons():
		if cm.owned_wagons.has(str(w.id)):
			wagon_ids.append(str(w.id))
			wagon_names.append("%s · carries %d" % [str(w.name), int(w.capacity)])
	var wagon_choice := _choice(plan, wagon_ids, wagon_names)
	var guard_ids: Array = []
	var guard_names: Array = []
	for g in cm.guards():
		guard_ids.append(str(g.id))
		guard_names.append("%s · power %d · %s GP/trip%s" % [str(g.name), int(g.power), UIStyle.fmt(float(g.wage)), "" if level >= int(g.level) else " · level %d" % int(g.level)])
	var guard_choice := _choice(plan, guard_ids, guard_names)
	for i in range(guard_ids.size()):
		guard_choice.set_item_disabled(i, level < int(cm.guard(str(guard_ids[i])).level))
	route_choice.selected = maxi(0, route_ids.find(_cv_route))
	wagon_choice.selected = maxi(0, wagon_ids.find(_cv_wagon))
	guard_choice.selected = maxi(0, guard_ids.find(_cv_guard))
	var goods: Array = []
	var good_names: Array = []
	for g in DataLoader.new_skill_systems.get("caravan_goods", []):
		var have: int = BankManager.get_count(str(g.item_id))
		if have > 0:
			goods.append(str(g.item_id))
			good_names.append("%s (%d in Storage)" % [str(DataLoader.get_item(str(g.item_id)).get("name", g.item_id)), have])
	var cargo_label := UIStyle.label("", true, UITokens.FONT_SMALL)
	cargo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var preview_label := UIStyle.label("", true, UITokens.FONT_SMALL)
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plan.add_child(UIStyle.label("Cargo from Storage", true, UITokens.FONT_SMALL))
	var good_choice := _choice(plan, goods, good_names, goods.map(func(id): return AssetRegistry.item_icon(str(id))))
	if goods.is_empty():
		good_choice.set_item_text(0, "No trade goods in Storage")
		good_choice.tooltip_text = "Gather or craft trade goods first. The wanted goods above show what this destination prefers."
	var qty := SpinBox.new()
	qty.min_value = 1
	qty.max_value = 100000
	qty.value = 10
	qty.editable = not goods.is_empty()
	plan.add_child(qty)
	var dispatch_buttons: Array[Button] = []
	var refresh := func():
		_cv_route = str(route_ids[route_choice.selected]) if not route_ids.is_empty() else ""
		_cv_wagon = str(wagon_ids[wagon_choice.selected]) if not wagon_ids.is_empty() else "handcart"
		_cv_guard = str(guard_ids[guard_choice.selected]) if not guard_ids.is_empty() else "hired_hand"
		var selected_route: Dictionary = cm.route(_cv_route)
		var required_level: int = int(selected_route.get("level", 1))
		destination.text = "%s · %s" % [str(selected_route.get("name", "Destination")), "Route unlocked" if level >= required_level else "Unlocks at Caravaneering %d" % required_level]
		for container in [demand_box, returns_box]:
			for child in container.get_children():
				container.remove_child(child)
				child.queue_free()
		demand_box.add_child(UIStyle.label("Wanted here · today's price per item", true, UITokens.FONT_SMALL))
		for id in selected_route.get("demand", []):
			var row := UIStyle.hbox()
			demand_box.add_child(row)
			row.add_child(Widgets.item_icon(str(id), 32))
			var label := UIStyle.label("%s · %.1f GP · %d in Storage" % [str(DataLoader.get_item(str(id)).get("name", id)), cm.unit_price(_cv_route, str(id), cm.today()), BankManager.get_count(str(id))], true, UITokens.FONT_SMALL)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
		returns_box.add_child(UIStyle.label("Specialty goods brought home", true, UITokens.FONT_SMALL))
		returns_box.add_child(Widgets.item_rewards(selected_route.get("specialty", {})))
		var capacity: int = cm.capacity(_cv_wagon)
		var parts: Array = []
		for id in _cv_cargo:
			parts.append("%d× %s" % [int(_cv_cargo[id]), str(DataLoader.get_item(str(id)).get("name", id))])
		cargo_label.text = "Cargo %d / %d: %s" % [cm.load_of(_cv_cargo), capacity, "empty" if parts.is_empty() else ", ".join(parts)]
		var p: Dictionary = cm.preview(_cv_route, _cv_wagon, _cv_guard, _cv_cargo)
		var why: String = cm.can_dispatch(_cv_route, _cv_wagon, _cv_guard, _cv_cargo)
		preview_label.text = "Balanced forecast (stop rewards extra): ≈ %s GP back for %s GP of goods and %s GP wages (profit ≈ %s), %.1f hours, %.0f%% unguarded risk, ≈ %s XP. Weather has at least 15%% risk before your approach; journey choices change the outcome.%s" % [UIStyle.fmt(float(p.expected_revenue)), UIStyle.fmt(float(p.base_value)), UIStyle.fmt(float(p.wages)), UIStyle.fmt(float(p.profit)), float(p.hours), float(p.loss_risk) * 100.0, UIStyle.fmt(float(p.xp)), "" if why == "" else "  Cannot dispatch yet: " + why]
		for button in dispatch_buttons:
			button.disabled = why != ""
			button.tooltip_text = why if why != "" else "Cargo and guard wages are paid on departure; rewards arrive on return."
	route_choice.item_selected.connect(func(_i): refresh.call())
	wagon_choice.item_selected.connect(func(_i): refresh.call())
	guard_choice.item_selected.connect(func(_i): refresh.call())
	var cargo_row := _flow()
	plan.add_child(cargo_row)
	_button(cargo_row, "Add cargo", func():
		if goods.is_empty(): return
		var id: String = str(goods[good_choice.selected])
		var room: int = cm.capacity(_cv_wagon) - cm.load_of(_cv_cargo)
		var add: int = mini(int(qty.value), mini(room, BankManager.get_count(id) - int(_cv_cargo.get(id, 0))))
		if add > 0: _cv_cargo[id] = int(_cv_cargo.get(id, 0)) + add
		refresh.call(), not goods.is_empty())
	_button(cargo_row, "Fill with wanted goods", func():
		_cv_cargo.clear()
		var room: int = cm.capacity(_cv_wagon)
		for id in cm.route(_cv_route).get("demand", []):
			var amount: int = mini(room, BankManager.get_count(str(id)))
			if amount > 0:
				_cv_cargo[str(id)] = amount
				room -= amount
		refresh.call(), not goods.is_empty())
	_button(cargo_row, "Remove selected good", func():
		if not goods.is_empty(): _cv_cargo.erase(str(goods[good_choice.selected]))
		refresh.call(), not goods.is_empty())
	_button(cargo_row, "Clear cargo", func():
		_cv_cargo.clear()
		refresh.call())
	plan.add_child(cargo_label)
	plan.add_child(preview_label)
	var go_row := _flow()
	plan.add_child(go_row)
	for repeat in [false, true]:
		var dispatch_button := _button(go_row, "Dispatch & repeat" if repeat else "Dispatch", func():
			var cargo: Dictionary = _cv_cargo.duplicate()
			_cv_cargo.clear()
			if not cm.dispatch(_cv_route, _cv_wagon, _cv_guard, cargo, repeat):
				_cv_cargo = cargo
				EventBus.notify(cm.can_dispatch(_cv_route, _cv_wagon, _cv_guard, _cv_cargo), "warn"), not route_ids.is_empty(), "Repeating caravans re-load the same cargo from Storage each time they return" if repeat else "")
		dispatch_buttons.append(dispatch_button)
	refresh.call()
	var shop := _card("Wagons", "Bigger wagons carry more. You keep a wagon once bought.")
	for w in cm.wagons():
		var owned: bool = cm.owned_wagons.has(str(w.id))
		_button(shop, "%s · carries %d · %s" % [str(w.name), int(w.capacity), "owned" if owned else "%s GP (level %d)" % [UIStyle.fmt(float(w.price)), int(w.level)]], func(): cm.buy_wagon(str(w.id)), not owned and level >= int(w.level) and PlayerData.gp >= float(w.price))
	if not cm.history.is_empty():
		var trips := _card("Recent trips", "")
		for h in cm.history:
			if not h.get("journey", {}).is_empty():
				_button(trips, "View journey · " + str(cm.route(str(h.route)).get("name", h.route)), func(): _open_caravan_map(str(h.route), h.journey))
			trips.add_child(Widgets.item_rewards(h.items))
			trips.add_child(UIStyle.label("%s: %s GP%s" % [str(cm.route(str(h.route)).get("name", h.route)), UIStyle.fmt(float(h.revenue)), "" if float(h.loss) <= 0.0 else " (cargo value lost %.0f%%)" % (float(h.loss) * 100.0)], true, UITokens.FONT_SMALL))

func _ranch() -> void:
	_live_pens.clear()
	var box := _card("Ranch estate", "Manage your livestock, improve each enclosure and specialize your herds. Produce and breeding progress continue while you are away.")
	var stats := _flow()
	box.add_child(stats)
	var animals: int = 0
	var ready: int = 0
	for p in RanchingManager.pens:
		animals += int(p.animals)
		ready += 1 if int(p.cycles) > 0 else 0
	stats.add_child(Widgets.stat_card("Pens", "%d / 6" % RanchingManager.pens.size(), UITokens.GOLD))
	stats.add_child(Widgets.stat_card("Animals", str(animals), UITokens.TEAL))
	stats.add_child(Widgets.stat_card("Ready to collect", str(ready), UITokens.GOLD))
	var upgrades := _flow()
	box.add_child(upgrades)
	for upgrade in RanchingManager.PEN_UPGRADES:
		var card := UIStyle.card()
		card.custom_minimum_size = Vector2(230, 0)
		var content := UIStyle.vbox(UITokens.SP_2)
		card.add_child(content)
		content.add_child(UIStyle.title(str(upgrade.name), UITokens.FONT_BODY))
		content.add_child(UIStyle.label("Lv %d · %s GP per pen" % [int(upgrade.level), UIStyle.fmt(float(upgrade.cost))], true, UITokens.FONT_SMALL))
		var hint := UIStyle.label(str(upgrade.hint), true, UITokens.FONT_SMALL)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(hint)
		upgrades.add_child(card)
	_button(box, "Build pen %d · Lv %d · %s GP" % [RanchingManager.pens.size() + 1, 1 + RanchingManager.pens.size() * 15, UIStyle.fmt(RanchingManager.pen_price())], func():
		if not RanchingManager.build_pen(): EventBus.notify("You need more GP or Ranching levels for another pen.", "warn"), RanchingManager.pens.size() < 6 and PlayerData.get_level("ranching") >= 1 + RanchingManager.pens.size() * 15 and PlayerData.gp >= RanchingManager.pen_price())
	var crops: Array = []
	var labels: Array = []
	for seed in DataLoader.items.values():
		if typeof(seed) == TYPE_DICTIONARY and seed.has("product_item") and BankManager.get_count(str(seed.product_item)) > 0:
			crops.append(str(seed.product_item))
			labels.append("%s ×%d" % [DataLoader.get_item(str(seed.product_item)).get("name", seed.product_item), BankManager.get_count(str(seed.product_item))])
	if not crops.is_empty():
		var feed_row := UIStyle.hbox(UITokens.SP_3)
		box.add_child(feed_row)
		var crop_choice := _choice(feed_row, crops, labels, crops.map(func(id): return AssetRegistry.item_icon(str(id))))
		_button(feed_row, "Make feed", func():
			RanchingManager.crop_feed(str(crops[crop_choice.selected]), 1)
			EventBus.state_refreshed.emit(), true, "One Farming crop makes ten feed.")
	var batch_row := _flow()
	box.add_child(batch_row)
	_button(batch_row, "Feed all · 100 each", func():
		for index in range(RanchingManager.pens.size()):
			if int(RanchingManager.pens[index].animals) > 0: RanchingManager.feed_pen(index, mini(100, BankManager.get_count("ranch_feed")))
		EventBus.state_refreshed.emit(), BankManager.get_count("ranch_feed") > 0)
	_button(batch_row, "Collect all", func():
		for index in range(RanchingManager.pens.size()): RanchingManager.collect(index)
		EventBus.state_refreshed.emit())
	box.add_child(Widgets.item_rewards({"ranch_feed": BankManager.get_count("ranch_feed")}))
	var pen_grid := _flow()
	box.add_child(pen_grid)
	for index in range(RanchingManager.pens.size()):
		var p: Dictionary = RanchingManager.pens[index]
		var def: Dictionary = RanchingManager.species(str(p.species))
		var panel := UIStyle.card(int(p.cycles) > 0)
		panel.custom_minimum_size = Vector2(320, 0)
		pen_grid.add_child(panel)
		var pen := UIStyle.vbox(UITokens.SP_3)
		panel.add_child(pen)
		var hero := UIStyle.hbox(UITokens.SP_3)
		pen.add_child(hero)
		var pen_icon := UIStyle.icon_texture("items", str(def.get("stock", "ranch_feed")))
		pen_icon.custom_minimum_size = Vector2(64, 64)
		pen_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		hero.add_child(pen_icon)
		var heading := UIStyle.vbox(UITokens.SP_2)
		hero.add_child(heading)
		heading.add_child(UIStyle.title("Pen %d · %s" % [index + 1, str(def.get("name", "Empty"))], UITokens.FONT_BODY))
		heading.add_child(UIStyle.label("%d / %d animals · %s" % [int(p.animals), RanchingManager.capacity(index), "Rare variant" if bool(p.variant) else "Ordinary stock"], true, UITokens.FONT_SMALL))
		var modes: Array = RanchingManager.MANAGEMENT.keys()
		var mode_labels: Array = modes.map(func(id): return "%s · Lv %d" % [str(RanchingManager.MANAGEMENT[id].name), int(RanchingManager.MANAGEMENT[id].level)])
		var choice_mode := _choice(pen, modes, mode_labels)
		choice_mode.select(modes.find(str(p.get("management", "balanced"))))
		for m in range(modes.size()):
			choice_mode.set_item_disabled(m, PlayerData.get_level("ranching") < int(RanchingManager.MANAGEMENT[modes[m]].level))
			choice_mode.get_popup().set_item_tooltip(m, str(RanchingManager.MANAGEMENT[modes[m]].hint))
		choice_mode.item_selected.connect(func(selected): RanchingManager.set_management(index, str(modes[selected])))
		var tier: int = int(p.get("upgrade", 0))
		pen.add_child(UIStyle.label("Basic enclosure" if tier == 0 else str(RanchingManager.PEN_UPGRADES[tier - 1].name), true, UITokens.FONT_SMALL))
		if tier < RanchingManager.PEN_UPGRADES.size():
			var upgrade: Dictionary = RanchingManager.PEN_UPGRADES[tier]
			_button(pen, "Upgrade · %s GP · Lv %d" % [UIStyle.fmt(float(upgrade.cost)), int(upgrade.level)], func(): RanchingManager.upgrade_pen(index), PlayerData.get_level("ranching") >= int(upgrade.level) and PlayerData.gp >= float(upgrade.cost), str(upgrade.hint))
		if not def.is_empty():
			var reserve := UIStyle.label("", true, UITokens.FONT_SMALL)
			pen.add_child(reserve)
			pen.add_child(Widgets.item_rewards({str(def.produce): int(p.pending.get(str(def.produce), 0)), "ranch_manure": int(p.pending.get("ranch_manure", 0))}))
			var bar_root := Widgets.progress_bar(float(p.progress), float(def.seconds), UITokens.TEAL, "Produce", 18)
			pen.add_child(bar_root)
			var mood := Widgets.progress_bar(float(p.happiness), 100.0, UITokens.GOLD, "Animal mood", 14)
			pen.add_child(mood)
			var breed_bar := Widgets.progress_bar(float(p.breed_seconds), 21600.0, UITokens.PURPLE, "Breeding", 14)
			pen.add_child(breed_bar)
			_live_pens.append({"index": index, "bar": bar_root, "mood": mood, "breed": breed_bar, "reserve": reserve})
		var actions := _flow()
		pen.add_child(actions)
		_button(actions, "Feed 100", func(): RanchingManager.feed_pen(index, mini(100, BankManager.get_count("ranch_feed"))), BankManager.get_count("ranch_feed") > 0)
		_button(actions, "Collect", func(): RanchingManager.collect(index), int(p.cycles) > 0)
		var breed_action := _button(actions, "Breed", func(): RanchingManager.breed(index), int(p.animals) >= 2 and float(p.breed_seconds) >= 21600.0 and float(p.happiness) >= 50.0)
		if not def.is_empty(): _live_pens[-1]["breed_button"] = breed_action
		_button(actions, "Retire one", func(): RanchingManager.retire(index), int(p.animals) > 0, "Collect pending produce, then exchange one animal for meat and hides.")
		if int(p.animals) < RanchingManager.capacity(index):
			var ids: Array = []
			var names: Array = []
			for animal in DataLoader.new_skill_systems.get("species", []):
				if PlayerData.get_level("ranching") >= int(animal.level) and (int(p.animals) == 0 or str(animal.id) == str(p.species)):
					ids.append(str(animal.id))
					names.append(str(animal.name))
			var row := _flow()
			pen.add_child(row)
			var choice := _choice(row, ids, names, ids.map(func(id): return AssetRegistry.item_icon(str(RanchingManager.species(str(id)).stock))))
			_button(row, "Buy stock", func():
				var animal: Dictionary = RanchingManager.species(str(ids[choice.selected]))
				ShopManager.buy_store("store_" + str(animal.stock))
				EventBus.state_refreshed.emit(), not ids.is_empty(), "Buy one animal at the Provisionier's current stock price.")
			_button(row, "Stock pair", func():
				for _animal in range(2): RanchingManager.stock(index, str(ids[choice.selected]))
				EventBus.state_refreshed.emit(), not ids.is_empty())
			_button(row, "Stock", func():
				if not RanchingManager.stock(index, str(ids[choice.selected])): EventBus.notify("Buy stock first; animals in a pen must match.", "warn"), not ids.is_empty())
			if BankManager.get_count("golden_hen_stock") > 0 or BankManager.get_count("mooncalf_stock") > 0:
				_button(row, "Rare stock", func():
					if not RanchingManager.stock(index, str(ids[choice.selected]), true): EventBus.notify("No matching rare stock, or this pen holds ordinary animals.", "warn"), not ids.is_empty())
	var catalogue := _card("Livestock catalogue", "A long-term progression from hens to celestial dragons. Matching animals share a pen; rare hens and mooncalves produce twice as much.")
	var catalogue_grid := _flow()
	catalogue.add_child(catalogue_grid)
	for animal in DataLoader.new_skill_systems.get("species", []):
		var unlocked: bool = PlayerData.get_level("ranching") >= int(animal.level)
		var card := UIStyle.card()
		card.custom_minimum_size = Vector2(230, 0)
		catalogue_grid.add_child(card)
		var content := UIStyle.vbox(UITokens.SP_3)
		card.add_child(content)
		var art := UIStyle.hbox(UITokens.SP_3)
		content.add_child(art)
		var animal_icon := UIStyle.icon_texture("items", str(animal.stock))
		animal_icon.custom_minimum_size = Vector2(64, 64)
		animal_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.add_child(animal_icon)
		var title := UIStyle.vbox(UITokens.SP_2)
		art.add_child(title)
		title.add_child(UIStyle.title(str(animal.name), UITokens.FONT_BODY))
		title.add_child(Widgets.badge("Available" if unlocked else "Lv %d" % int(animal.level), UITokens.TEAL if unlocked else UITokens.TEXT_DIM, ""))
		content.add_child(Widgets.item_rewards({str(animal.produce): 1}))
		content.add_child(UIStyle.label("%s cycle · %d feed/hour" % [UIStyle.fmt_duration(float(animal.seconds)), int(animal.feed)], true, UITokens.FONT_SMALL))
		_button(content, "Buy stock · owned %d" % BankManager.get_count(str(animal.stock)), func():
			if not ShopManager.buy_store("store_" + str(animal.stock)): EventBus.notify("You need more GP or storage space.", "warn")
			EventBus.state_refreshed.emit(), unlocked)
	var soil := _card("Ranch manure", "+25% crop survival and +10% yield for one crop. Apply before planting.")
	soil.add_child(UIStyle.icon_texture("items", "ranch_manure"))
	_button(soil, "Prepare all empty plots", func():
		for index in range(FarmingManager.plots.size()): FarmingManager.apply_manure(index)
		EventBus.state_refreshed.emit(), BankManager.get_count("ranch_manure") > 0)

func _inscription() -> void:
	var box := _card("The scriptorium", "Research each recipe once, then scribe Faded, Inked or Illuminated texts. Quality improves with recipe mastery.")
	box.add_child(Widgets.key_value("Recipes researched", str(InscriptionManager.researched.size())))
	var targets: Array = []
	var names: Array = []
	for id in DataLoader.get_skill_ids():
		targets.append(id)
		names.append(str(DataLoader.get_skill(id).name))
	var target := _choice(box, targets, names, targets.map(func(id): return AssetRegistry.skill_icon(str(id))))
	for item_id in BankManager.items.keys():
		var item: Dictionary = DataLoader.get_item(str(item_id))
		if not item.has("scribe_effect"):
			continue
		var preview_label := UIStyle.label(InscriptionManager.text_preview(str(item_id), str(targets[target.selected])), true, UITokens.FONT_MICRO)
		preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(preview_label)
		target.item_selected.connect(func(_i): preview_label.text = InscriptionManager.text_preview(str(item_id), str(targets[target.selected])))
		box.add_child(Widgets.item_row(str(item_id), BankManager.get_count(str(item_id)), "Use", func():
			if not InscriptionManager.use_text(str(item_id), str(targets[target.selected])): EventBus.notify("This text cannot be used right now.", "warn")))
	for id in InscriptionManager.buffs:
		box.add_child(Widgets.key_value(str(id).capitalize(), UIStyle.fmt_duration(float(InscriptionManager.buffs[id].remaining))))
	if not InscriptionManager.researched.size():
		box.add_child(UIStyle.label("Select a Research activity above to unlock your first recipe.", true, UITokens.FONT_SMALL))

func _engineering() -> void:
	var box := _card("Clockwork workshop", "%d device slots. Workers start at 40%% efficiency; their XP and output ignore your active skill bonuses. Fuel is prepaid one hour at a time." % EngineeringManager.slots())
	for index in range(EngineeringManager.installed.size()):
		var worker: Dictionary = EngineeringManager.installed[index]
		var def: Dictionary = EngineeringManager.device(str(worker.id))
		var panel := UIStyle.section(str(def.name), "%s · %s" % [str(worker.action), str(worker.status)])
		box.add_child(panel)
		var forecast: Dictionary = EngineeringManager.worker_preview(index)
		panel.add_child(UIStyle.label("Fuel %d/hour · fuel runway %.1fh · material runway %s · efficiency %.0f%%" % [int(forecast.fuel), float(forecast.fuel_hours), "unlimited" if is_inf(float(forecast.material_hours)) else "%.1fh" % float(forecast.material_hours), float(forecast.efficiency) * 100], true, UITokens.FONT_SMALL))
		if str(def.skill) == "farming": panel.add_child(UIStyle.label("Long-run crop estimate includes survival and average Farmhand polling delay; mixed crops and manure change actual output.", true, UITokens.FONT_MICRO))
		if str(def.skill) == "combat": panel.add_child(UIStyle.label("Output depends on your kills and overflow loot; no guaranteed hourly drops.", true, UITokens.FONT_MICRO))
		for id in forecast.outputs: panel.add_child(Widgets.key_value(str(DataLoader.get_item(str(id)).get("name", id)), "≈ %.1f / hour" % float(forecast.outputs[id])))
		panel.add_child(UIStyle.icon_texture("items", str(def.id)))
		panel.add_child(Widgets.item_rewards({str(def.fuel): int(def.fuel_cost)}))
		var bar := Widgets.progress_bar(float(worker.fuel_seconds), 3600.0, UITokens.GOLD, "Prepaid fuel remaining", 18)
		panel.add_child(bar)
		var status := UIStyle.label(str(worker.status), true, UITokens.FONT_SMALL)
		panel.add_child(status)
		_live_workers.append({"index": index, "bar": bar, "status": status})
		_button(panel, "Uninstall", func(): EngineeringManager.uninstall(index), true, "Return the device to Storage; remaining prepaid fuel is forfeited.")
	for def in EngineeringManager.devices():
		var id: String = str(def.id)
		if BankManager.get_count(id) <= 0:
			continue
		var panel := UIStyle.section(str(def.name), "Fuel: %d %s/hour" % [int(def.fuel_cost), DataLoader.get_item(str(def.fuel)).get("name", def.fuel)])
		box.add_child(panel)
		panel.add_child(UIStyle.icon_texture("items", id))
		var ids: Array = []
		var names: Array = []
		if str(def.skill) == "combat":
			ids = ["loot"]
			names = ["Recover waiting loot from Storage overflow"]
		else:
			for action in DataLoader.get_skill_actions(str(def.skill)):
				if PlayerData.get_level(str(def.skill)) >= int(action.level_required):
					ids.append(str(action.id))
					names.append(str(action.name))
		var choice := _choice(panel, ids, names)
		_button(panel, "Install worker", func(): EngineeringManager.install(id, str(ids[choice.selected])), not ids.is_empty() and EngineeringManager.installed.size() < EngineeringManager.slots())

func _enchanting() -> void:
	var box := _card("The enchanting bench", "Unequip a piece into Storage first. Disenchanting destroys one copy. Enchanting splits one copy from its stack; replacing its enchant leaves other pieces unchanged.")
	var ids: Array = []
	var names: Array = []
	for id in BankManager.items.keys():
		var item: Dictionary = DataLoader.get_item(str(id))
		if item.get("item_type", "") == "equipment":
			ids.append(str(id))
			names.append("%s ×%d" % [item.name, BankManager.get_count(str(id))])
	if ids.is_empty():
		box.add_child(UIStyle.label("Bring equipment from combat, crafting or Storage to begin recycling.", true, UITokens.FONT_SMALL))
		return
	var equipment := _choice(box, ids, names, ids.map(func(id): return AssetRegistry.item_icon(str(id))))
	var recipes: Array = []
	var labels: Array = []
	for recipe in EnchantingManager.recipes():
		recipes.append(str(recipe.id))
		labels.append("%s · %s · level %d" % [recipe.name, recipe.scope, int(recipe.level)])
	var enchant := _choice(box, recipes, labels, recipes.map(func(id): return AssetRegistry.icon("enchants", str(id))))
	var hint := UIStyle.label("", true, UITokens.FONT_SMALL)
	box.add_child(hint)
	var update := func(_index = 0):
		var def: Dictionary = EnchantingManager.recipe(str(recipes[enchant.selected]))
		var preview: Dictionary = EnchantingManager.preview(str(ids[equipment.selected]), str(def.id))
		var costs: Array[String] = []
		for id in preview.cost: costs.append("%d %s" % [int(preview.cost[id]), str(DataLoader.get_item(str(id)).get("name", id))])
		hint.text = "Cost: " + ", ".join(costs) + "\nBefore: " + UIStyle.describe_modifier_table(preview.before) + "\nAfter: " + UIStyle.describe_modifier_table(preview.after) + "\nReplaces: " + (", ".join(preview.replaced) if not preview.replaced.is_empty() else "none") + "\n" + str(preview.reason)
	equipment.item_selected.connect(update)
	enchant.item_selected.connect(update)
	update.call()
	var row := _flow()
	box.add_child(row)
	_button(row, "Disenchant one", func():
		if not EnchantingManager.begin_disenchant(str(ids[equipment.selected])): EventBus.notify("Check your Enchanting level and unprotect the item first.", "warn"))
	_button(row, "Enchant / replace", func(): EnchantingManager.begin_enchant(str(ids[equipment.selected]), str(recipes[enchant.selected])))
	_button(row, "Add second", func(): EnchantingManager.begin_enchant(str(ids[equipment.selected]), str(recipes[enchant.selected]), true), ModifierManager.get_modifier("enchanting_slots") >= 1)
	for essence in ["martial", "warding", "arcane", "verdant"]:
		box.add_child(Widgets.item_rewards({"enchant_" + essence + "_essence": BankManager.get_count("enchant_" + essence + "_essence")}))

func _dreams() -> void:
	var box := _card("Enter the Dreamlands", "Allocate offline time between your waking activity and dreams. Dreamwalking never earns XP while the game is open. Longer dreams gain depth; the existing offline cap still applies.")
	var ids: Array = []
	var names: Array = []
	var locked: Array = []
	for def in DataLoader.new_skill_systems.get("dreams", []):
		var open: bool = PlayerData.get_level("dreamwalking") >= int(def.level)
		ids.append(str(def.id))
		locked.append(not open)
		names.append(("%s · %s XP/hour" % [def.name, UIStyle.fmt(float(def.xp_hour))]) if open else ("%s · unlocks at level %d" % [def.name, int(def.level)]))
	var choice := _choice(box, ids, names, ids.map(func(id): return AssetRegistry.icon("dreams", str(id))))
	for i in range(ids.size()):
		if locked[i]:
			choice.set_item_disabled(i, true)
	choice.selected = maxi(0, ids.find(DreamwalkingManager.dreamscape))
	var dream_icon := UIStyle.icon_texture("dreams", str(ids[choice.selected]))
	box.add_child(dream_icon)
	var twist_label := UIStyle.label("", true, UITokens.FONT_SMALL)
	twist_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(twist_label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = DreamwalkingManager.share * 100.0
	slider.custom_minimum_size = Vector2(140, 32)
	box.add_child(slider)
	var label := UIStyle.label("", true, UITokens.FONT_SMALL)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var update := func(_value = 0):
		DreamwalkingManager.select(str(ids[choice.selected]), slider.value / 100.0)
		dream_icon.texture = AssetRegistry.icon("dreams", str(ids[choice.selected]))
		twist_label.text = "Twist · " + str(DreamwalkingManager.twist(str(ids[choice.selected])).get("text", "none"))
		var forecast: Dictionary = DreamwalkingManager.preview(8.0 * 3600.0)
		label.text = "%.0f%% dreams · %.0f%% waking. Eight-hour example: ≈ %s XP / %s Essence; waking output reduced by %s. Current modifiers held constant; future buffs may expire." % [slider.value, 100.0 - slider.value, UIStyle.fmt(float(forecast.xp)), UIStyle.fmt(float(forecast.essence)), UIStyle.fmt_duration(float(forecast.seconds))]
	slider.value_changed.connect(update)
	choice.item_selected.connect(update)
	update.call()
	if DreamwalkingManager.next_essence_bonus > 0:
		box.add_child(UIStyle.label("Lucid Draught ready: +15% Essence for your next dream.", true, UITokens.FONT_SMALL))
	build_events(self)
	var all_lands := _card("Every dreamland", "Each dreamland has its own twist. Locked ones show the level that opens them.")
	for def in DataLoader.new_skill_systems.get("dreams", []):
		var open: bool = PlayerData.get_level("dreamwalking") >= int(def.level)
		var line := UIStyle.label("%s (level %d): %s" % [def.name, int(def.level), str(DreamwalkingManager.twist(str(def.id)).get("text", ""))], true, UITokens.FONT_SMALL)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if not open:
			line.modulate = Color(1, 1, 1, 0.55)
		all_lands.add_child(line)
	var bazaar := _card("Dream Bazaar", "%d Dream Essence in Storage" % BankManager.get_count("dream_essence"))
	for offer in DataLoader.new_skill_systems.get("bazaar", []):
		var offer_icon: String = {"insight": "scribe_xp_tome_1_inked", "fortune": "scribe_doubling_inked", "town_tick": "dream_essence", "paper": "scribe_paper", "manure": "ranch_manure", "ore": "coal"}.get(str(offer.id), "dream_essence")
		var offer_button := _button(bazaar, "%s · %d Essence" % [offer.name, int(offer.cost)], func(): DreamwalkingManager.buy(str(offer.id)), BankManager.get_count("dream_essence") >= int(offer.cost))
		offer_button.icon = AssetRegistry.item_icon(offer_icon)
		offer_button.add_theme_constant_override("icon_max_width", 32)

static func build_events(parent: Control) -> void:
	for index in range(DreamwalkingManager.events.size()):
		var event: Dictionary = DreamwalkingManager.events[index]
		var terms: String = "Accept: pay %d Essence for 500 Dreamwalking XP." % floori(BankManager.get_count("dream_essence") * 0.1) if str(event.kind) == "shadow" else "Accept: receive 5 Ranch Manure, free."
		var box := UIStyle.section("A dream encounter", str(event.text) + " " + terms + " Decline: receive 10 Essence.")
		parent.add_child(box)
		var row := UIStyle.hbox(UITokens.SP_3)
		box.add_child(row)
		for accept in [true, false]:
			var button := UIStyle.button("Accept" if accept else "Decline · +10 Essence")
			button.pressed.connect(func():
				DreamwalkingManager.resolve_event(DreamwalkingManager.events.find(event), accept)
				box.queue_free())
			row.add_child(button)

func _process(_delta: float) -> void:
	for entry in _live_pens:
		if int(entry.index) >= RanchingManager.pens.size(): continue
		var pen: Dictionary = RanchingManager.pens[int(entry.index)]
		var rates: Dictionary = RanchingManager.pen_rates(int(entry.index))
		entry.bar.value = float(pen.progress)
		entry.mood.value = float(pen.happiness)
		entry.breed.value = float(pen.breed_seconds)
		entry.breed_button.disabled = int(pen.animals) < 2 or float(pen.breed_seconds) < 21600.0 or float(pen.happiness) < 50.0
		entry.reserve.text = "Feed %.0f · lasts %s · Mood %.0f%%" % [float(pen.feed), UIStyle.fmt_duration(float(pen.feed) / maxf(0.001, float(rates.feed_hour)) * 3600.0), float(pen.happiness)]
	for entry in _live_caravans:
		if int(entry.index) < CaravaneeringManager.caravans.size():
			var c: Dictionary = CaravaneeringManager.caravans[int(entry.index)]
			entry.bar.value = float(c.total) - float(c.remaining)
			entry.eta.text = "Parked · " + str(c.status) if bool(c.get("idle", false)) else "Returns in " + UIStyle.fmt_duration(float(c.remaining))
	for entry in _live_workers:
		if int(entry.index) < EngineeringManager.installed.size():
			var worker: Dictionary = EngineeringManager.installed[int(entry.index)]
			entry.bar.value = float(worker.fuel_seconds)
			entry.status.text = str(worker.status)

func _open_caravan_map(route_id: String, journey: Dictionary = {}) -> void:
	var view := CaravanMap.new()
	view.route_id = route_id
	view.trip_seed = int(journey.get("seed", 0))
	view.theme = UIStyle.build_theme()
	# The root owns the window so a skill-panel refresh cannot close an ongoing journey.
	get_tree().root.add_child(view)
	var available: Vector2i = Vector2i(get_viewport_rect().size) - Vector2i(48, 64)
	view.popup_centered(Vector2i(mini(1040, available.x), mini(840, available.y)))
