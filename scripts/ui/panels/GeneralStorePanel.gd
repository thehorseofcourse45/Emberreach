extends VBoxContainer
## GeneralStorePanel — the general store: the one counter where gold turns directly into materials.
##
## Stock is repeatable and sold in bundles, unlike the upgrades one screen over, so this is a table
## of compact rows rather than a wall of cards: thirty-one offers as cards would be all scrolling and
## no scanning. Each row states what the bundle contains and what it costs, and a line gated behind
## a skill level shows your level beside the required one instead of hiding.
##
## Nothing here is a shortcut past a skill. Every price sits above what the item sells for (the test
## suite asserts that margin per line), so buying unblocks a queue — it never replaces the furnace.
##
## This screen was the Provisioner's third section. Upgrades are a catalogue you exhaust and read
## once, stock is a counter you come back to, and the two densities fought each other on one page.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

## Everything first: a fresh character has no gold, and opening the store onto an empty shelf hides
## the whole catalogue from exactly the player who has never seen it. The filter narrows a shelf
## that is always shown in full by default, which is also how the store behaved before the split.
const FILTERS: Array[String] = ["Everything", "Affordable", "Locked"]
const FILTER_KEYS: Array[String] = ["all", "affordable", "locked"]

var _search: LineEdit
var _filter: OptionButton
var _summary: VBoxContainer
var _list: VBoxContainer
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("General Store", UITokens.FONT_DISPLAY))
	add_child(UIStyle.label(
		"Materials bought outright with gold, for when you need one now and would rather not wait for it. Every price sits well above what the item sells for, so making it yourself is always the better deal — this counter removes a wait, not a skill.",
		true, UITokens.FONT_SMALL))

	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", UITokens.SP_4)
	bar.add_theme_constant_override("v_separation", UITokens.SP_2)
	_search = Widgets.search_bar("Search stock…", func(_t): _rebuild(), 200)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_search)
	_filter = Widgets.option_menu(FILTERS, func(_i): _rebuild(), 0)
	_filter.tooltip_text = "Narrow the shelves: everything in stock, what you can afford now, or what is still locked"
	bar.add_child(_filter)
	add_child(bar)

	_summary = UIStyle.vbox(UITokens.SP_2)
	add_child(_summary)
	_list = UIStyle.vbox(UITokens.SP_3)
	add_child(_list)

	# Affordability is gold against a level gate, so those are the only two things that can change
	# the state of a row. Listening to the bank would rebuild thirty-one rows on every ore mined.
	EventBus.gp_changed.connect(func(_a, _t): _rebuild())
	EventBus.skill_level_up.connect(func(_s, _l): _rebuild())
	EventBus.state_refreshed.connect(_rebuild)
	_rebuild()

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "General Store",
		"body": "Repeatable stock, priced above what the item sells for: buying unblocks a queue rather than skipping a skill. Costlier lines stay shut until you have trained the skill that makes the item."}

func _rebuild() -> void:
	if not _built:
		return
	_rebuild_summary()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var offers: Array = _filtered_offers()
	if offers.is_empty():
		# An empty shelf always says which filter emptied it and offers the way out of it.
		_list.add_child(Widgets.empty_state("Nothing on this shelf",
			"No line matches that search and filter. Locked lines open as your skills rise.",
			"Show everything", func():
				_search.text = ""
				_filter.selected = FILTER_KEYS.find("all")
				_rebuild()))
		return
	for offer in offers:
		_list.add_child(_offer_row(offer as Dictionary))

func _filtered_offers() -> Array:
	var needle: String = _search.text.strip_edges().to_lower()
	var key: String = FILTER_KEYS[clampi(_filter.selected, 0, FILTER_KEYS.size() - 1)]
	var out: Array = []
	for offer in ShopManager.store_offers():
		var o: Dictionary = offer as Dictionary
		var state: String = _state_of(o)
		if key == "affordable" and state != "affordable":
			continue
		if key == "locked" and state != "locked":
			continue
		if needle != "" and not _matches(o, needle):
			continue
		out.append(o)
	return out

func _matches(offer: Dictionary, needle: String) -> bool:
	for field in ["name", "subtitle", "description", "item_id"]:
		if str(offer.get(field, "")).to_lower().contains(needle):
			return true
	return str(DataLoader.get_item(str(offer.get("item_id", ""))).get("name", "")).to_lower().contains(needle)

## affordable = buyable now; locked = a skill gate or the price is out of reach.
func _state_of(offer: Dictionary) -> String:
	return "affordable" if bool(ShopManager.can_buy_store(str(offer.get("id", "")))["ok"]) else "locked"

func _rebuild_summary() -> void:
	for c in _summary.get_children():
		_summary.remove_child(c)
		c.queue_free()
	var offers: Array = ShopManager.store_offers()
	if offers.is_empty():
		return
	var buyable: int = 0
	var gated: int = 0
	for offer in offers:
		var o: Dictionary = offer as Dictionary
		if bool(ShopManager.can_buy_store(str(o["id"]))["ok"]):
			buyable += 1
		elif str(ShopManager.store_requirement(o)["skill"]) != "":
			gated += 1
	_summary.add_child(Widgets.progress_bar(float(buyable), float(offers.size()), UITokens.GOLD,
		"%d of %d lines affordable now" % [buyable, offers.size()], 14,
		"Stock you can buy with the gold you are holding"))
	_summary.add_child(Widgets.key_value("Available gold", "%s GP" % UIStyle.fmt_exact(PlayerData.gp),
		UITokens.GOLD_BRIGHT, "Gold is earned by selling goods and completing expeditions"))
	if gated > 0:
		_summary.add_child(UIStyle.colored_label(
			"%d line%s stay shut until you have trained the skill that makes the item" % [gated, "" if gated == 1 else "s"],
			UITokens.TEXT_MUTED, UITokens.FONT_MICRO))

## One row per bundle. The name and price wrap into a flow container so a narrow window reflows
## instead of forcing the screen wider than itself.
func _offer_row(offer: Dictionary) -> Control:
	var offer_id: String = str(offer.get("id", ""))
	var item_id: String = str(offer.get("item_id", ""))
	var cost: float = float(offer.get("cost", 0))
	var qty: int = maxi(1, int(offer.get("quantity", 1)))
	var check: Dictionary = ShopManager.can_buy_store(offer_id)
	var card := UIStyle.card(bool(check["ok"]))
	# A card is a PanelContainer, which sizes its ONE child to the full rect. Two children would
	# both fill it and land on top of each other, so everything goes into a single column first.
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", UITokens.SP_3)
	head.add_theme_constant_override("v_separation", UITokens.SP_2)
	col.add_child(head)
	# The requirement is its own line, above the row: as a sibling of the flow row it would share
	# the line with the item name and the two would overlap.
	var need: Dictionary = ShopManager.store_requirement(offer)
	var skill_id: String = str(need["skill"])
	if skill_id != "":
		col.add_child(Widgets.requirement_row(
			"%s level" % str(DataLoader.get_skill(skill_id).get("name", skill_id)),
			float(PlayerData.get_level(skill_id)), float(int(need["level"])),
			PlayerData.get_level(skill_id) >= int(need["level"]),
			"Train the skill to unlock this line"))
	head.add_child(Widgets.item_icon(item_id))
	var text := UIStyle.vbox(UITokens.SP_1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := HFlowContainer.new()
	name_row.add_theme_constant_override("h_separation", UITokens.SP_3)
	var title := UIStyle.label(str(offer.get("name", item_id)), false, UITokens.FONT_BODY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(title)
	name_row.add_child(Widgets.badge("×%d" % qty, UITokens.BLUE, "How many you receive per purchase"))
	name_row.add_child(Widgets.badge("%s GP" % UIStyle.fmt(cost), UITokens.GOLD,
		"Exact cost: %s GP, or %s each" % [UIStyle.fmt_exact(cost), UIStyle.fmt_exact(cost / float(qty))]))
	text.add_child(name_row)
	text.add_child(UIStyle.label(str(offer.get("subtitle", "")), true, UITokens.FONT_MICRO))
	head.add_child(text)
	var buy := UIStyle.primary_button("Buy")
	buy.disabled = not bool(check["ok"])
	buy.tooltip_text = "Buy %s ×%d for %s GP" % [str(offer.get("name", item_id)), qty,
		UIStyle.fmt_exact(cost)] if bool(check["ok"]) else str(check["reason"])
	buy.pressed.connect(func():
		if ShopManager.buy_store(offer_id):
			_rebuild())
	head.add_child(buy)
	# Pinning the item is what makes this screen reachable from the goal system: the store then
	# shows up as a real source on the item's detail pane, with a route straight back here.
	var track := UIStyle.mini_button("Track", "Track %s as a goal. Its detail pane then lists this store as a source." % str(offer.get("name", item_id)))
	track.pressed.connect(func():
		Goals.pin("item", item_id)
		EventBus.notify("Tracking %s." % str(DataLoader.get_item(item_id).get("name", item_id)), "success"))
	head.add_child(track)
	if not bool(check["ok"]):
		head.add_child(UIStyle.colored_label(str(check["reason"]), UITokens.AMBER, UITokens.FONT_MICRO))
	return card
