extends VBoxContainer
## ProvisionerPanel — the GP shop: permanent unlocks and conveniences.
##
## Every entry states its cost, its exact effect, and every prerequisite with current-versus-
## required values, so a purchase is a decision rather than a gamble. Nothing here is a repeatable
## currency printer: `max` caps stackable items, and the effect of each purchase is either a
## bounded modifier or a one-time flag the gameplay code actually reads.
##
## Expensive purchases route through one confirmation; ordinary ones commit in a single click.
##
## Bulk materials used to live at the bottom of this page. They moved to their own screen (see
## `GeneralStorePanel`) because a catalogue of one-off upgrades and a counter of repeatable stock
## are read differently — this page keeps a signpost, not a copy of the shelves.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

const CONFIRM_THRESHOLD: float = 1_000_000.0

var _list: VBoxContainer
var _summary: VBoxContainer
var _stall: VBoxContainer
var _store_hint: Label
var _filter: OptionButton
var _filter_keys: Array[String] = ["available", "owned", "locked", "all"]
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Provisioner", UITokens.FONT_DISPLAY))
	add_child(UIStyle.label(
		"Permanent improvements bought with gold. Each one is a one-off: the effect is applied through the modifier system, so it stacks with everything else and never needs re-buying after a reload.",
		true, UITokens.FONT_SMALL))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", UITokens.SP_4)
	bar.add_child(UIStyle.label("Show", true, UITokens.FONT_SMALL))
	_filter = Widgets.option_menu(["Available now", "Owned", "Locked", "Everything"],
		func(_i): _rebuild(), 0)
	_filter.tooltip_text = "Filter the catalogue by what you can act on right now"
	bar.add_child(_filter)
	add_child(bar)
	_summary = UIStyle.vbox(UITokens.SP_2)
	add_child(_summary)
	_list = UIStyle.vbox(UITokens.SP_4)
	add_child(_list)
	_stall = UIStyle.vbox(UITokens.SP_4)
	add_child(_stall)
	add_child(_store_signpost())
	EventBus.gp_changed.connect(func(_a, _t): _rebuild())
	EventBus.shop_upgrade_purchased.connect(func(_u): _rebuild())
	EventBus.state_refreshed.connect(_rebuild)
	# The mastery stall's "Owned" badge reads storage, so a bank change can change a row here.
	EventBus.bank_changed.connect(_rebuild)
	_rebuild()

func focus_route(_route: Dictionary) -> void:
	pass

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Provisioner",
		"body": "Purchases are permanent and applied as modifiers. The cost shown is the exact amount that will be deducted, and prerequisites are listed with your current standing."}

func _rebuild() -> void:
	if not _built:
		return
	_rebuild_summary()
	_rebuild_stall()
	_rebuild_store_hint()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var filter: String = _filter_keys[clampi(_filter.selected, 0, _filter_keys.size() - 1)]
	var shown: int = 0
	for upgrade_id in _sorted_ids():
		var state: String = _state_of(upgrade_id)
		if filter == "available" and state != "available":
			continue
		if filter == "owned" and state != "owned":
			continue
		if filter == "locked" and state != "locked":
			continue
		shown += 1
		_list.add_child(_upgrade_card(upgrade_id, state))
	if shown == 0:
		_list.add_child(Widgets.empty_state("Nothing in this filter",
			"Gold and prerequisites both gate the catalogue — keep adventuring and come back.",
			"Show everything", func():
				_filter.selected = 3
				_rebuild()))

func _sorted_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in DataLoader.shop.keys():
		if str(key).begins_with("_"):
			continue
		ids.append(str(key))
	ids.sort_custom(func(a, b):
		return float(DataLoader.shop[a].get("cost", 0)) < float(DataLoader.shop[b].get("cost", 0)))
	return ids

## available = buyable now; owned = at its cap; locked = prerequisites or gold missing.
func _state_of(upgrade_id: String) -> String:
	var u: Dictionary = DataLoader.shop[upgrade_id]
	var count: int = int(PlayerData.shop_upgrades.get(upgrade_id, 0))
	# An explicit `max` makes an entry stackable (bank slots); otherwise it is a one-off.
	var max_count: int = int(u.get("max", 0))
	if max_count > 0:
		if count >= max_count:
			return "owned"
	elif count > 0:
		return "owned"
	if not ShopManager.has_requirement(upgrade_id):
		return "locked"
	if PlayerData.gp < float(u.get("cost", 0)):
		return "locked"
	return "available"

## The mastery stall: skillcapes and the completion capes, bought rather than found. One row per
## cape keeps sixty of them scannable, and every row states the gate as current-versus-required.
func _rebuild_stall() -> void:
	for c in _stall.get_children():
		_stall.remove_child(c)
		c.queue_free()
	var offers: Array = ShopManager.stall_offers()
	var earned: int = 0
	for offer in offers:
		if bool((offer as Dictionary)["met"]):
			earned += 1
	var head := UIStyle.section("Mastery stall — %d of %d earned" % [earned, offers.size()])
	_stall.add_child(head)
	_stall.add_child(UIStyle.label(
		"Finishing a skill earns the right to buy its cape. Capes carry a permanent bonus to the skill they belong to.",
		true, UITokens.FONT_SMALL))
	var claimable: Array = []
	var rest: Array = []
	for offer in offers:
		if bool((offer as Dictionary)["met"]):
			claimable.append(offer)
		else:
			rest.append(offer)
	for offer in claimable + rest:
		_stall.add_child(_stall_row(offer))

func _stall_row(offer: Dictionary) -> Control:
	var item_id: String = str(offer["item_id"])
	var met: bool = bool(offer["met"])
	var row := UIStyle.card(met)
	var col := UIStyle.vbox(UITokens.SP_2)
	row.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITokens.SP_3)
	var name_label := UIStyle.title(str(offer["name"]), UITokens.FONT_BODY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	if bool(offer["owned"]):
		head.add_child(Widgets.badge("Owned", UITokens.GREEN, "You already hold this cape"))
	head.add_child(Widgets.badge("%s GP" % UIStyle.fmt(float(offer["cost"])), UITokens.GOLD,
		"Exact cost: %s GP" % UIStyle.fmt_exact(float(offer["cost"]))))
	col.add_child(head)
	col.add_child(Widgets.requirement_row(str(offer["label"]), float(offer["current"]),
		float(offer["required"]), met, str(offer["hint"])))
	var bonus := UIStyle.describe_modifier_table(_passive_modifiers(item_id))
	if bonus != "":
		col.add_child(UIStyle.colored_label("Bonus: " + bonus, UITokens.PURPLE, UITokens.FONT_SMALL))
	var button := UIStyle.primary_button("Buy")
	var check: Dictionary = ShopManager.can_buy_stall(item_id)
	button.disabled = not bool(check["ok"])
	button.tooltip_text = "Buy for %s GP" % UIStyle.fmt_exact(float(offer["cost"])) \
		if bool(check["ok"]) else str(check["reason"])
	button.pressed.connect(func():
		if ShopManager.buy_stall(item_id):
			_rebuild())
	col.add_child(button)
	return row

func _passive_modifiers(item_id: String) -> Dictionary:
	return DataLoader.get_item(item_id).get("passive_modifiers", {})

# =========================================================================
#  The general store's signpost
# =========================================================================

## The shelves are one screen over. The link stays live — it counts what is affordable right now —
## so a player who looked for the store here finds it, and finds it with a reason to click.
func _store_signpost() -> Control:
	var box := UIStyle.vbox(UITokens.SP_2)
	box.add_child(UIStyle.section("Elsewhere", "the store keeps its own counter now"))
	box.add_child(UIStyle.label(
		"Repeatable materials are sold from the General Store: searchable stock, bought in bundles, priced above what the item sells for.",
		true, UITokens.FONT_SMALL))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UITokens.SP_3)
	row.add_theme_constant_override("v_separation", UITokens.SP_2)
	var open := UIStyle.primary_button("Open the General Store")
	open.tooltip_text = "Go to the store's stock"
	open.pressed.connect(func(): navigated.emit({"screen": Screens.STORE}))
	row.add_child(open)
	_store_hint = UIStyle.label("", true, UITokens.FONT_MICRO)
	row.add_child(_store_hint)
	box.add_child(row)
	return box

func _rebuild_store_hint() -> void:
	var offers: Array = ShopManager.store_offers()
	var buyable: int = 0
	for offer in offers:
		if bool(ShopManager.can_buy_store(str((offer as Dictionary)["id"]))["ok"]):
			buyable += 1
	_store_hint.text = "%d of %d lines are affordable now" % [buyable, offers.size()]

func _rebuild_summary() -> void:
	for c in _summary.get_children():
		_summary.remove_child(c)
		c.queue_free()
	var owned: int = 0
	var total: int = 0
	for upgrade_id in DataLoader.shop.keys():
		if str(upgrade_id).begins_with("_"):
			continue
		total += 1
		if int(PlayerData.shop_upgrades.get(str(upgrade_id), 0)) > 0:
			owned += 1
	_summary.add_child(Widgets.progress_bar(float(owned), float(maxi(total, 1)), UITokens.BLUE,
		"%d / %d owned" % [owned, total], 14, "Provisioner purchases you have already made"))
	_summary.add_child(Widgets.key_value("Available gold", "%s GP" % UIStyle.fmt_exact(PlayerData.gp),
		UITokens.GOLD_BRIGHT, "Gold is earned by selling goods and completing expeditions"))

func _upgrade_card(upgrade_id: String, state: String) -> Control:
	var u: Dictionary = DataLoader.shop[upgrade_id]
	var cost: float = float(u.get("cost", 0))
	var card := UIStyle.card(state == "available")
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITokens.SP_4)
	var title := UIStyle.title(str(u.get("name", upgrade_id)), UITokens.FONT_SUBHEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(Widgets.badge("Owned" if state == "owned" else ("Locked" if state == "locked" else "Available"),
		UITokens.GREEN if state == "owned" else (UITokens.TEXT_MUTED if state == "locked" else UITokens.GOLD_BRIGHT),
		"Purchase state"))
	head.add_child(Widgets.badge("%s GP" % UIStyle.fmt(cost), UITokens.GOLD, "Exact cost: %s GP" % UIStyle.fmt_exact(cost)))
	var owned_count: int = int(PlayerData.shop_upgrades.get(upgrade_id, 0))
	if owned_count > 0:
		head.add_child(Widgets.badge("×%d" % owned_count, UITokens.BLUE, "How many of this upgrade you own"))
	col.add_child(head)

	if str(u.get("description", "")) != "":
		var d := UIStyle.label(str(u["description"]), true, UITokens.FONT_SMALL)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(d)

	# The effect is stated in the same vocabulary the rest of the UI uses.
	var effect: Dictionary = u.get("effect", {})
	if not effect.is_empty():
		col.add_child(UIStyle.colored_label("Effect: " + UIStyle.describe_modifier_table(effect),
			UITokens.PURPLE, UITokens.FONT_SMALL))
	if str(u.get("type", "")) == "auto_eat":
		var tier: int = int(u.get("tier", 0))
		var cfg: Dictionary = CombatManager.AUTO_EAT.get(tier, {})
		if not cfg.is_empty():
			col.add_child(UIStyle.colored_label(
				"Effect: auto-eat below %s%% HP, healing to %s%% at %s%% efficiency" % [
					UIStyle.fmt(float(cfg.get("threshold", 0.0))), UIStyle.fmt(float(cfg.get("heal_to", 0.0))),
					UIStyle.fmt(float(cfg.get("efficiency", 0.0)))],
				UITokens.PURPLE, UITokens.FONT_SMALL))
	elif str(u.get("type", "")) == "bank_tab":
		col.add_child(UIStyle.colored_label("Effect: one additional storage stack slot per purchase",
			UITokens.PURPLE, UITokens.FONT_SMALL))

	# Prerequisites, each with current versus required.
	var requirements: Array = _requirement_rows(upgrade_id)
	if not requirements.is_empty():
		col.add_child(UIStyle.section("Requirements"))
		for r in requirements:
			col.add_child(Widgets.requirement_row(str(r["label"]), float(r["current"]),
				float(r["required"]), bool(r["satisfied"]), str(r["hint"])))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", UITokens.SP_3)
	var button := UIStyle.primary_button("Purchase")
	var check: Dictionary = ShopManager.can_buy(upgrade_id)
	button.disabled = not bool(check["ok"])
	button.tooltip_text = "Buy for %s GP" % UIStyle.fmt_exact(cost) if bool(check["ok"]) else str(check["reason"])
	var uid: String = upgrade_id
	button.pressed.connect(func(): _buy(uid))
	buttons.add_child(button)
	if not bool(check["ok"]):
		buttons.add_child(UIStyle.colored_label(str(check["reason"]), UITokens.AMBER, UITokens.FONT_MICRO))
	col.add_child(buttons)
	return card

func _requirement_rows(upgrade_id: String) -> Array:
	var u: Dictionary = DataLoader.shop[upgrade_id]
	var out: Array = []
	for req in u.get("requires", []):
		var rid: String = str(req)
		var owned: bool = ShopManager.is_purchased(rid)
		out.append({"label": str(DataLoader.shop.get(rid, {}).get("name", rid)),
			"current": 1.0 if owned else 0.0, "required": 1.0, "satisfied": owned,
			"hint": "Prerequisite purchase"})
	for skill_id in (u.get("requires_skill", {}) as Dictionary).keys():
		var level: int = PlayerData.get_level(str(skill_id))
		var need: int = int(u["requires_skill"][skill_id])
		out.append({"label": "%s level" % DataLoader.get_skill(str(skill_id)).get("name", skill_id),
			"current": float(level), "required": float(need), "satisfied": level >= need,
			"hint": "Train this skill"})
	if bool(u.get("requires_all_skills_99", false)):
		var lowest: int = 999
		var lowest_id: String = ""
		for skill_id in DataLoader.get_skill_ids():
			var lv: int = PlayerData.get_level(skill_id)
			if lv < lowest:
				lowest = lv
				lowest_id = skill_id
		out.append({"label": "Every skill at 99", "current": float(lowest), "required": 99.0,
			"satisfied": lowest >= 99, "hint": "Lowest is %s" % DataLoader.get_skill(lowest_id).get("name", lowest_id)})
	var dungeon: String = str(u.get("requires_dungeon", ""))
	if dungeon != "":
		var cleared: bool = (PlayerData.completion_log.get("dungeons", {}) as Dictionary).has(dungeon)
		out.append({"label": "Clear %s" % DataLoader.get_dungeon(dungeon).get("name", dungeon),
			"current": 1.0 if cleared else 0.0, "required": 1.0, "satisfied": cleared,
			"hint": "Open Expeditions to attempt it"})
	return out

func _buy(upgrade_id: String) -> void:
	var u: Dictionary = DataLoader.shop[upgrade_id]
	var cost: float = float(u.get("cost", 0))
	var check: Dictionary = ShopManager.can_buy(upgrade_id)
	if not bool(check["ok"]):
		EventBus.notify("Cannot buy: %s" % str(check["reason"]), "warn")
		return
	var effect: Dictionary = u.get("effect", {})
	var body: String = "%s\n\nCost: %s GP\nYour gold after this purchase: %s GP" % [
		str(u.get("name", upgrade_id)), UIStyle.fmt_exact(cost), UIStyle.fmt_exact(PlayerData.gp - cost)]
	if not effect.is_empty():
		body += "\n\nEffect: %s" % UIStyle.describe_modifier_table(effect)
	if cost >= CONFIRM_THRESHOLD:
		ConfirmDialog.ask(self, "Confirm purchase", body, "Buy for %s GP" % UIStyle.fmt(cost),
			func():
				ShopManager.buy(upgrade_id)
				_rebuild())
		return
	if ShopManager.buy(upgrade_id):
		_rebuild()
