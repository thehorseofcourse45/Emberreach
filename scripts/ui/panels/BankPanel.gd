extends VBoxContainer
## BankPanel — storage browsing and item operations.
##
## Requirements from the brief, implemented here: search, category filters, sorting, favourites,
## protection against accidental sale, quantity selection, bulk selling with a preview and an
## explicit confirmation, visible equipped / tracked / overflow status, item detail views, and
## quick navigation to recipes and acquisition sources.
##
## Favourites and protection are deliberately different things. A favourite pins an item to the top
## of storage and can be filtered for; protection is what actually stops a sale. Treating the
## bookmark as the lock would quietly make a harmless tap on "Favourite" a safety setting.
##
## Capacity is a manageable constraint: it limits how many DISTINCT stacks you keep. Nothing is
## ever destroyed — items that arrive with no room wait in a visible overflow ledger.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

const CATEGORY_LABELS: Dictionary = {
	"all": "All", "resource": "Materials", "equipment": "Equipment", "food": "Food",
	"potion": "Potions", "rune": "Runes", "ammo": "Ammunition", "bone": "Bones",
	"seed": "Seeds", "tablet": "Tablets", "consumable": "Consumables", "currency": "Tokens",
}

var _search: LineEdit
var _sort: OptionButton
var _category: OptionButton
var _ascending: bool = true
## Favourites are a view, not a safety rail: this toggle narrows the list to the pinned items and
## does nothing to prevent them being sold.
var _favorites_only: bool = false
var _list: VBoxContainer
var _capacity_box: VBoxContainer
var _overflow_box: VBoxContainer
var _filters_box: VBoxContainer
var _selected: String = ""
var _category_keys: Array[String] = ["all"]
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	EventBus.bank_changed.connect(refresh)
	EventBus.state_refreshed.connect(refresh)
	refresh()

func detail_context() -> Dictionary:
	if _selected != "":
		return {"kind": "item", "item_id": _selected}
	return {"kind": "text", "title": "Storage",
		"body": "Select an item to see where it comes from, what uses it, and to protect or track it."}

func _build() -> void:
	_built = true
	# Flow containers, not rows: on a narrow window the controls wrap onto a second line instead
	# of forcing the panel wider than the window.
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", UITokens.SP_4)
	bar.add_theme_constant_override("v_separation", UITokens.SP_2)
	_search = Widgets.search_bar("Search items…", func(_t): _rebuild_list())
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_search)
	_category = Widgets.option_menu(["All"], func(i):
		_rebuild_list(), 0)
	_category.tooltip_text = "Filter by item category"
	bar.add_child(_category)
	_sort = Widgets.option_menu(["Name", "Quantity", "Value", "Type"], func(i):
		_rebuild_list(), 0)
	_sort.tooltip_text = "Sort order"
	bar.add_child(_sort)
	var direction := UIStyle.mini_button("↑ Asc", "Toggle ascending / descending")
	direction.pressed.connect(func():
		_ascending = not _ascending
		direction.text = "↑ Asc" if _ascending else "↓ Desc"
		_rebuild_list())
	bar.add_child(direction)
	var fav_only := UIStyle.mini_button("☆ Favourites", "Show only the items you have pinned. Favouriting never protects an item from being sold.")
	fav_only.pressed.connect(func():
		_favorites_only = not _favorites_only
		fav_only.text = "★ Favourites" if _favorites_only else "☆ Favourites"
		_rebuild_list())
	bar.add_child(fav_only)
	add_child(bar)

	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", UITokens.SP_3)
	actions.add_theme_constant_override("v_separation", UITokens.SP_2)
	var sell_all := UIStyle.danger_button("Sell filtered…", "Preview and confirm selling every unprotected item in the current filter")
	sell_all.pressed.connect(_on_bulk_sell)
	actions.add_child(sell_all)
	var bury_all := UIStyle.primary_button("Bury all bones", "Consume every bone in the current filter for Prayer Points")
	bury_all.pressed.connect(_on_bulk_bury)
	actions.add_child(bury_all)
	var track_sel := UIStyle.mini_button("Track selection")
	track_sel.pressed.connect(func():
		if _selected != "":
			Goals.pin("item", _selected)
			EventBus.notify("Tracking %s." % DataLoader.get_item(_selected).get("name", _selected), "success"))
	actions.add_child(track_sel)
	var protect_sel := UIStyle.mini_button("Protect selection", "Protected items are never sold by bulk actions")
	protect_sel.pressed.connect(func():
		if _selected != "":
			var now: bool = BankManager.toggle_protected(_selected)
			EventBus.notify("%s %s." % [DataLoader.get_item(_selected).get("name", _selected),
				"protected" if now else "unprotected"], "info")
			refresh())
	actions.add_child(protect_sel)
	var fav_sel := UIStyle.mini_button("Favourite selection", "Pin the selected item to the top of storage. This does not protect it from being sold.")
	fav_sel.pressed.connect(func():
		if _selected != "":
			var now: bool = BankManager.toggle_favorite(_selected)
			EventBus.notify("%s %s." % [DataLoader.get_item(_selected).get("name", _selected),
				"favourited" if now else "unfavourited"], "info")
			refresh())
	actions.add_child(fav_sel)
	add_child(actions)

	_capacity_box = UIStyle.section("Storage")
	add_child(_capacity_box)
	_overflow_box = UIStyle.section("Overflow", "nothing here is lost")
	add_child(_overflow_box)
	_filters_box = UIStyle.section("Auto-sell rules", "rule-based tidy-up, armed only when you write a rule")
	add_child(_filters_box)
	_list = UIStyle.vbox(UITokens.SP_2)
	add_child(_list)

# =========================================================================
#  Refresh
# =========================================================================

func refresh() -> void:
	if not _built:
		return
	_rebuild_categories()
	_rebuild_capacity()
	_rebuild_overflow()
	_rebuild_filters()
	_rebuild_list()

func _rebuild_categories() -> void:
	var counts: Dictionary = BankManager.category_counts()
	var keys: Array[String] = ["all"]
	for key in counts.keys():
		if not keys.has(str(key)):
			keys.append(str(key))
	var changed: bool = keys != _category_keys
	_category_keys = keys
	if not changed:
		return
	var previous: int = _category.selected
	_category.clear()
	for key in _category_keys:
		var label: String = str(CATEGORY_LABELS.get(key, key.capitalize()))
		var n: int = BankManager.get_used_slots() if key == "all" else int(counts.get(key, 0))
		_category.add_item("%s (%d)" % [label, n])
	_category.selected = clampi(previous, 0, maxi(0, _category_keys.size() - 1))

# =========================================================================
#  Auto-sell rules (#17)
# =========================================================================

## Rules are written from the item currently selected in the list, so this section never needs a
## second item browser. Nothing is sold here: the buttons build and arm rules, and a separate
## "Apply now" is the only thing that liquidates the current bank.
func _rebuild_filters() -> void:
	_clear(_filters_box)
	var safety := HFlowContainer.new()
	safety.add_theme_constant_override("h_separation", UITokens.SP_3)
	safety.add_theme_constant_override("v_separation", UITokens.SP_2)
	_filters_box.add_child(safety)
	var special_toggle := CheckButton.new()
	special_toggle.text = "Never auto-sell items with a special attack"
	special_toggle.button_pressed = LootFilterManager.protect_special_items
	special_toggle.tooltip_text = "On by default. A weapon with a special attack is kept unless you turn this off."
	special_toggle.toggled.connect(func(on: bool):
		LootFilterManager.set_protect_special_items(on)
		refresh())
	safety.add_child(special_toggle)

	var armed: int = 0
	for rule in LootFilterManager.rules:
		if bool((rule as Dictionary).get("enabled", true)):
			armed += 1
	var status: String = "%d rule(s) armed" % armed if armed > 0 else "no rules armed — nothing is sold automatically"
	_filters_box.add_child(UIStyle.colored_label(status,
		UITokens.GOLD_BRIGHT if armed > 0 else UITokens.TEXT_MUTED, UITokens.FONT_MICRO))

	# The rule builder works from the selected item.
	if _selected == "":
		_filters_box.add_child(UIStyle.label(
			"Select an item above to write a rule for it.", true, UITokens.FONT_MICRO))
	else:
		_filters_box.add_child(_rule_builder(_selected))

	if LootFilterManager.rules.is_empty():
		return

	var apply_now := UIStyle.primary_button("Apply now",
		"Run every armed rule against the current bank and sell the excess")
	apply_now.pressed.connect(_on_apply_filters)
	_filters_box.add_child(apply_now)

	for i in range(LootFilterManager.rules.size()):
		_filters_box.add_child(_rule_row(i, LootFilterManager.rules[i]))

func _rule_builder(item_id: String) -> Control:
	var item: Dictionary = DataLoader.get_item(item_id)
	var col := UIStyle.vbox(UITokens.SP_2)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UITokens.SP_3)
	row.add_theme_constant_override("v_separation", UITokens.SP_2)
	col.add_child(row)
	row.add_child(UIStyle.label("New rule for %s" % str(item.get("name", item_id)), true, UITokens.FONT_SMALL))

	# Tier bounds, only offered when the item actually carries a tier.
	var tier_row := HFlowContainer.new()
	tier_row.add_theme_constant_override("h_separation", UITokens.SP_2)
	tier_row.add_theme_constant_override("v_separation", UITokens.SP_2)
	col.add_child(tier_row)
	var min_tier := OptionButton.new()
	min_tier.add_item("any tier", 0)
	min_tier.add_item("common (0)", 0)
	min_tier.add_item("large (1)", 1)
	min_tier.add_item("dragon (2)", 2)
	min_tier.tooltip_text = "Ignore items below this tier"
	var max_tier := OptionButton.new()
	max_tier.add_item("any tier", 0)
	max_tier.add_item("common (0)", 0)
	max_tier.add_item("large (1)", 1)
	max_tier.add_item("dragon (2)", 2)
	max_tier.tooltip_text = "Ignore items above this tier"
	tier_row.add_child(UIStyle.label("tier", true, UITokens.FONT_MICRO))
	tier_row.add_child(min_tier)
	tier_row.add_child(UIStyle.label("to", true, UITokens.FONT_MICRO))
	tier_row.add_child(max_tier)

	var keep := LineEdit.new()
	keep.placeholder_text = "Keep 0 = sell it all"
	keep.tooltip_text = "How many to keep. Everything above this is sold."
	keep.custom_minimum_size = Vector2(0, UITokens.H_HEADER)
	keep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(keep)

	var add := UIStyle.primary_button("Add rule",
		"Arm a rule that keeps the given count of this item and sells the rest")
	add.pressed.connect(func():
		_on_add_rule(item_id, min_tier, max_tier, keep))
	col.add_child(add)
	return col

func _on_add_rule(item_id: String, min_tier: OptionButton, max_tier: OptionButton, keep: LineEdit) -> void:
	# A picker index of 0 means "any tier", which is -1 in the rule model, not 0.
	var lo: int = _tier_value(min_tier.selected)
	var hi: int = _tier_value(max_tier.selected)
	var keep_count: int = maxi(0, int(keep.text.strip_edges()))
	var rule: Dictionary = LootFilterManager.add_rule([item_id], [], lo, hi, keep_count)
	if rule.is_empty():
		EventBus.notify("That rule is not valid: %s" % LootFilterManager.last_error, "warn")
		return
	keep.text = ""
	EventBus.notify("Rule armed: %s" % str(rule["label"]), "success")
	refresh()

func _tier_value(index: int) -> int:
	match index:
		1: return 0
		2: return 1
		3: return 2
	return -1

func _on_apply_filters() -> void:
	var plan: Array = LootFilterManager.preview()
	if plan.is_empty():
		EventBus.notify("No armed rule currently matches anything in the bank.", "info")
		return
	var total: int = 0
	for entry in plan:
		total += int(entry["quantity"])
	ConfirmDialog.ask(self, "Apply %d auto-sell rule(s)?" % LootFilterManager.rules.size(),
		"This will sell %d item(s) from the bank right now." % total,
		"Sell the excess", func():
			LootFilterManager.evaluate_now(true)
			refresh(), true)
	refresh()

func _rule_row(index: int, rule: Dictionary) -> Control:
	var enabled: bool = bool(rule.get("enabled", true))
	var card := UIStyle.card(index == 0 and enabled)
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", UITokens.SP_3)
	head.add_theme_constant_override("v_separation", UITokens.SP_2)
	col.add_child(head)
	head.add_child(UIStyle.label(str(rule.get("label", "rule")), not enabled, UITokens.FONT_SMALL))
	head.add_child(Widgets.badge("Armed" if enabled else "Off",
		UITokens.GREEN if enabled else UITokens.TEXT_MUTED))
	var toggle := UIStyle.mini_button("Disable" if enabled else "Enable",
		"Arm or disarm this rule without deleting it")
	toggle.pressed.connect(func():
		LootFilterManager.set_rule_enabled(str(rule.get("id", "")), not enabled)
		refresh())
	head.add_child(toggle)
	# Order matters: the first matching rule decides an item's fate.
	var up := UIStyle.mini_button("↑", "Higher priority")
	up.disabled = index == 0
	up.pressed.connect(func():
		LootFilterManager.move_rule(str(rule.get("id", "")), -1)
		refresh())
	head.add_child(up)
	var down := UIStyle.mini_button("↓", "Lower priority")
	down.disabled = index == LootFilterManager.rules.size() - 1
	down.pressed.connect(func():
		LootFilterManager.move_rule(str(rule.get("id", "")), 1)
		refresh())
	head.add_child(down)
	var del := UIStyle.mini_button("Delete", "Remove this rule")
	del.pressed.connect(func():
		LootFilterManager.remove_rule(str(rule.get("id", "")))
		refresh())
	head.add_child(del)
	return card

func _rebuild_capacity() -> void:
	_clear(_capacity_box)
	var used: int = BankManager.get_used_slots()
	var limit: int = BankManager.get_slot_limit()
	_capacity_box.add_child(Widgets.progress_bar(float(used), float(maxi(limit, 1)),
		UITokens.RED if used >= limit else UITokens.TEAL,
		"%d / %d stacks" % [used, limit], 16,
		"Capacity limits how many distinct stacks you keep, never how much of a stack you hold"))
	var price: float = BankManager.next_slot_price()
	var check: Dictionary = BankManager.can_buy_slot()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_4)
	var b := UIStyle.primary_button("Buy 1 stack slot — %s GP" % UIStyle.fmt(price),
		"Costs rise with each slot; the price is capped at the maximum listed in the curve")
	b.disabled = not bool(check["ok"])
	b.tooltip_text = str(check["reason"]) if not bool(check["ok"]) else "Expand storage by one stack slot"
	b.pressed.connect(func():
		if BankManager.buy_slot(1):
			refresh())
	row.add_child(b)
	var b10 := UIStyle.mini_button("Buy 10", "Buy the next ten slots at their individual prices")
	b10.disabled = PlayerData.gp < price
	b10.pressed.connect(func():
		if BankManager.buy_slot(10):
			refresh())
	row.add_child(b10)
	_capacity_box.add_child(row)

	if BankManager.is_full():
		_capacity_box.add_child(UIStyle.colored_label(
			"Storage is full. Gathering and crafting that would create a NEW stack will stop and tell you why; items from rewards and combat wait in overflow instead of being lost.",
			UITokens.AMBER, UITokens.FONT_SMALL))

func _rebuild_overflow() -> void:
	_clear(_overflow_box)
	if not BankManager.has_overflow():
		_overflow_box.add_child(UIStyle.label("Nothing waiting.", true, UITokens.FONT_SMALL))
		return
	_overflow_box.add_child(UIStyle.colored_label(
		"%d items are waiting in overflow because storage was full when they arrived. They were not discarded." % BankManager.overflow_count(),
		UITokens.AMBER, UITokens.FONT_SMALL))
	for item_id in BankManager.overflow.keys():
		_overflow_box.add_child(Widgets.item_row(str(item_id), int(BankManager.overflow[item_id]),
			"Withdraw", func(): BankManager.withdraw_overflow(str(item_id))))
	var all := UIStyle.mini_button("Withdraw everything possible")
	all.pressed.connect(func():
		BankManager.withdraw_overflow("")
		refresh())
	_overflow_box.add_child(all)

func _rebuild_list() -> void:
	_clear(_list)
	var sort_mode: int = [BankManager.SortMode.NAME, BankManager.SortMode.QUANTITY,
		BankManager.SortMode.VALUE, BankManager.SortMode.TYPE][_sort.selected]
	var category: String = _category_keys[clampi(_category.selected, 0, maxi(0, _category_keys.size() - 1))]
	var rows: Array = BankManager.sorted_list(_search.text, sort_mode, _ascending, category, _favorites_only)
	if rows.is_empty():
		if _favorites_only:
			_list.add_child(Widgets.empty_state("No favourites yet",
				"Favourite an item to pin it to the top of storage. Favourites are a bookmark, not a lock — protection is what stops an item being sold.",
				"Show everything", func():
					_favorites_only = false
					_rebuild_list()))
		else:
			_list.add_child(Widgets.empty_state("Nothing matches",
				"Adjust the search or filter, or go and gather something new.",
				"Open Skills", func(): navigated.emit({"screen": Screens.SKILLS})))
		return
	for r in rows:
		var item_id: String = str(r["item_id"])
		_list.add_child(_item_row(r))

func _item_row(r: Dictionary) -> Control:
	var item_id: String = str(r["item_id"])
	var item: Dictionary = r["data"]
	var card := UIStyle.card(item_id == _selected)
	var col := UIStyle.vbox(UITokens.SP_1)
	card.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_4)
	col.add_child(row)
	row.add_child(Widgets.item_icon(item_id))
	var text := UIStyle.vbox(UITokens.SP_1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A flow container, for the same reason the actions row below is one: an HBoxContainer
	# cannot wrap, so a long item name plus its badges set a floor wider than a narrow
	# window and push the whole panel sideways.
	var name_row := HFlowContainer.new()
	name_row.add_theme_constant_override("h_separation", UITokens.SP_3)
	name_row.add_theme_constant_override("v_separation", UITokens.SP_1)
	name_row.add_child(UIStyle.label(str(item.get("name", item_id)), false, UITokens.FONT_BODY))
	var rarity: Dictionary = UIStyle.item_rarity(item_id)
	name_row.add_child(Widgets.badge(str(rarity["label"]), rarity["color"],
		"Presentation rarity derived from tier and value"))
	if bool(r["protected"]):
		name_row.add_child(Widgets.badge("Protected", UITokens.GREEN, "Never sold by bulk actions"))
	if bool(r["favorite"]):
		name_row.add_child(Widgets.badge("Favourite", UITokens.GOLD, "Pinned to the top of storage"))
	if bool(r["equipped"]):
		name_row.add_child(Widgets.badge("Equipped", UITokens.GOLD_BRIGHT))
	if bool(r["tracked"]):
		name_row.add_child(Widgets.badge("Tracked", UITokens.GOLD))
	text.add_child(name_row)
	var subtitle: String = "%s · %s GP each" % [str(item.get("item_type", "item")).capitalize(),
		UIStyle.fmt(float(item.get("sell_price", 0)))]
	if int(r.get("in_overflow", 0)) > 0:
		subtitle += " · %s in overflow" % UIStyle.fmt_exact(float(r["in_overflow"]))
	text.add_child(UIStyle.label(subtitle, true, UITokens.FONT_MICRO))
	row.add_child(text)
	row.add_child(UIStyle.colored_label("×%s" % UIStyle.fmt_exact(float(r["quantity"])), UITokens.TEXT_STRONG, UITokens.FONT_SUBHEAD))
	row.add_child(Widgets.badge(str(r["category"]), UITokens.BLUE))
	# Actions sit on their own wrapping line: as one row they pushed the row wider than a narrow
	# window, and a wrapped line keeps every action visible and reachable.
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", UITokens.SP_3)
	actions.add_theme_constant_override("v_separation", UITokens.SP_2)
	col.add_child(actions)
	var select := UIStyle.mini_button("Details")
	select.pressed.connect(func():
		_selected = item_id
		context_changed.emit({"kind": "item", "item_id": item_id})
		_rebuild_list())
	actions.add_child(select)
	# Quantity selection, so a player never has to sell everything to sell some. A MenuButton is
	# used rather than an OptionButton so the same entry can be chosen repeatedly.
	actions.add_child(Widgets.quantity_menu([
		{"label": "Sell 1", "tooltip": "Sell one unit"},
		{"label": "Sell 10", "tooltip": "Sell up to ten units"},
		{"label": "Sell half", "tooltip": "Sell half of your stock"},
		{"label": "Sell all…", "tooltip": "Sell everything, with a confirmation"},
	], func(i): _sell(item_id, i), "Sell with an exact preview of the GP you will receive"))
	actions.add_child(_quick_button("Protect" if not bool(r["protected"]) else "Unprotect",
		func(): BankManager.toggle_protected(item_id)))
	actions.add_child(_quick_button("Unfavourite" if bool(r["favorite"]) else "Favourite",
		func(): BankManager.toggle_favorite(item_id)))
	actions.add_child(_quick_button("Track", func(): Goals.pin("item", item_id)))
	if str(item.get("item_type", "")) == "bone":
		actions.add_child(_quick_button("Bury", func():
			BankManager.bury_bone(item_id, 1)
			refresh()))
		actions.add_child(_quick_button("Bury all", func():
			BankManager.bury_bone(item_id, BankManager.get_count(item_id))
			refresh()))
	if str(item.get("item_type", "")) == "potion":
		actions.add_child(_quick_button("Drink", func():
			PotionManager.use_potion(item_id)
			refresh()))
	elif str(item.get("item_type", "")) == "food":
		var equip_food := Widgets.quantity_menu([
			{"label": "Food slot 1"}, {"label": "Food slot 2"}, {"label": "Food slot 3"},
		], func(slot):
			if not EquipmentManager.equip_food(slot, item_id):
				EventBus.notify("This food is already assigned to another slot.", "warn")
			refresh(), "Assign this Storage stack to a combat food slot")
		equip_food.text = "Equip food…"
		actions.add_child(equip_food)
		# The Eat button on the activity strip only ever picks the best food for you. This is how a
		# player chooses a specific meal, which is the whole point of cooking your own.
		var eat := _quick_button("Eat 1", func():
			CombatManager.consume_food(item_id, 100.0, "Ate")
			refresh())
		eat.tooltip_text = "Heal %d HP now" % int(item.get("heal_amount", 0))
		actions.add_child(eat)
		actions.add_child(_quick_button("Eat all", func():
			var n: int = BankManager.get_count(item_id)
			for _i in range(n):
				CombatManager.consume_food(item_id, 100.0, "Ate")
			refresh()))
	elif str(item.get("item_type", "")) == "equipment":
		actions.add_child(_quick_button("Equip", func():
			if not EquipmentManager.equip(item_id):
				EventBus.notify("Cannot equip %s — check requirements and storage space." % str(item.get("name", item_id)), "warn")
			refresh()))
	return card

func _quick_button(text: String, action: Callable) -> Button:
	var b := UIStyle.mini_button(text)
	b.pressed.connect(func():
		action.call()
		_refresh_list_only())
	return b

func _refresh_list_only() -> void:
	_rebuild_capacity()
	_rebuild_overflow()
	_rebuild_list()

func _sell(item_id: String, mode: int) -> void:
	var have: int = BankManager.get_count(item_id)
	var qty: int = 1
	match mode:
		1: qty = mini(10, have)
		2: qty = maxi(1, have / 2)
		3: qty = have
	if qty <= 0:
		return
	var preview: Dictionary = BankManager.sell_preview(item_id, qty)
	if bool(preview["protected"]):
		EventBus.notify("%s is protected — unprotect it first." % str(preview["name"]), "warn")
		return
	if mode == 3 and bool(PlayerData.settings.get("confirm_sell_all", true)):
		ConfirmDialog.ask(self, "Sell all %s?" % str(preview["name"]),
			"%s ×%s for %s GP.\n%d will remain." % [str(preview["name"]),
				UIStyle.fmt_exact(float(preview["quantity"])), UIStyle.fmt(float(preview["gp_gained"])),
				int(preview["remaining"])],
			"Sell all", func():
				BankManager.sell_item(item_id, qty)
				EventBus.notify("Sold %s ×%s for %s GP." % [str(preview["name"]),
					UIStyle.fmt_exact(float(preview["quantity"])), UIStyle.fmt(float(preview["gp_gained"]))], "success")
				refresh(), true)
		return
	if BankManager.sell_item(item_id, qty):
		EventBus.notify("Sold %s ×%s for %s GP." % [str(preview["name"]),
			UIStyle.fmt_exact(float(preview["quantity"])), UIStyle.fmt(float(preview["gp_gained"]))], "success")
	refresh()

func _on_bulk_bury() -> void:
	var sort_mode: int = [BankManager.SortMode.NAME, BankManager.SortMode.QUANTITY,
		BankManager.SortMode.VALUE, BankManager.SortMode.TYPE][_sort.selected]
	var category: String = _category_keys[clampi(_category.selected, 0, maxi(0, _category_keys.size() - 1))]
	var rows: Array = BankManager.sorted_list(_search.text, sort_mode, _ascending, category)
	var entries: Array = []
	for r in rows:
		if str((r["data"] as Dictionary).get("item_type", "")) != "bone":
			continue
		entries.append(str(r["item_id"]))
	if entries.is_empty():
		EventBus.notify("No bones in the current filter.", "info")
		return
	var total: int = 0
	for id in entries:
		total += BankManager.get_count(id)
	ConfirmDialog.ask(self, "Bury %d bone type(s)?" % entries.size(),
		"This will consume %s bone(s) for Prayer Points." % UIStyle.fmt_exact(float(total)),
		"Bury all", func():
			var buried: int = 0
			var points: float = 0.0
			for id in entries:
				var n: int = BankManager.bury_bone(id, BankManager.get_count(id))
				buried += n
			EventBus.notify("Buried %s bone(s)." % UIStyle.fmt_exact(float(buried)), "success")
			refresh(), true)
	refresh()

func _on_bulk_sell() -> void:
	var sort_mode: int = [BankManager.SortMode.NAME, BankManager.SortMode.QUANTITY,
		BankManager.SortMode.VALUE, BankManager.SortMode.TYPE][_sort.selected]
	var category: String = _category_keys[clampi(_category.selected, 0, maxi(0, _category_keys.size() - 1))]
	var rows: Array = BankManager.sorted_list(_search.text, sort_mode, _ascending, category)
	var entries: Array = []
	for r in rows:
		if bool(r["protected"]) or bool(r["equipped"]):
			continue
		entries.append(str(r["item_id"]))
	ConfirmDialog.ask_bulk_sale(self, entries, func():
		var result: Dictionary = BankManager.sell_many(entries)
		EventBus.notify("Sold %d item types for %s GP." % [int(result["items"]), UIStyle.fmt(float(result["gp"]))], "success")
		refresh())

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
