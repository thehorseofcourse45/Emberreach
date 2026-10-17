extends VBoxContainer
## RaidPanel — start a Golbin Raid, take the between-wave upgrade choice, and spend raid coins.
##
## RaidManager was complete (3 difficulties, waves, upgrade shop, 5 alt-weapons) with no caller in
## the UI, which left the strongest melee weapons in the game unobtainable. This is the missing
## entry point; the loop itself lives in RaidManager.
##
## A raid is a roguelike run: waves of golbins, a 3-choice upgrade after each, and the coins only
## bank when you end the run. Retreat is deliberate — leaving early keeps what you earned.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _body: VBoxContainer
var _summary: Label
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Golbin Raid", UITokens.FONT_DISPLAY))
	add_child(UIStyle.label("Rewards: Raid Coins, permanent combat upgrades and ALT equipment. First clear: complete wave 1, choose an upgrade, then bank your coins.", true))
	add_child(Widgets.item_rewards(Dictionary(DataLoader.raid_shop.get("alt_items", []).reduce(func(out, id): out[id] = 1; return out, {}))))
	_summary = UIStyle.label("", true, UITokens.FONT_SMALL)
	add_child(_summary)
	add_child(UIStyle.label(
		"Clear waves of golbins to earn raid coins. After each wave you take one of three "
		+ "upgrades. Coins are only banked when you end the run, so retreating keeps what you have.",
		true, UITokens.FONT_SMALL))
	_body = UIStyle.vbox(UITokens.SP_4)
	add_child(_body)
	EventBus.state_refreshed.connect(_rebuild)
	EventBus.combat_ended.connect(func(_c): _rebuild())
	EventBus.shop_upgrade_purchased.connect(func(_i): _rebuild())
	_rebuild()

func focus_route(_route: Dictionary) -> void:
	pass

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Golbin Raid",
		"body": "A roguelike run with escalating waves. Alt-weapons won here are the strongest "
			+ "in the game and are the intended way to reach the late game."}

func _rebuild() -> void:
	if not _built:
		return
	for existing in get_children():
		if existing is Control and existing.get_meta("raid_checklist", false): remove_child(existing); existing.queue_free()
	for entry in [["Clear wave 1", PlayerData.stats.get("raid_waves_cleared", {}).has("1")], ["Choose an upgrade", int(PlayerData.stats.get("raid_choices_taken", 0)) > 0], ["Bank earned coins", float(PlayerData.stats.get("raid_coins_banked", 0)) > 0]]:
		var row := Widgets.requirement_row(str(entry[0]), 1 if bool(entry[1]) else 0, 1, bool(entry[1]))
		row.set_meta("raid_checklist", true)
		add_child(row)
	_summary.text = "Raid coins: %s · %s" % [UIStyle.fmt(PlayerData.raid_coins),
		("in progress — wave %d (%s)" % [RaidManager.wave, RaidManager.difficulty]) if RaidManager.active
			else "not started"]
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if RaidManager.active:
		_body.add_child(_active_run())
	else:
		_body.add_child(_start_section())
	_body.add_child(UIStyle.section("Raid Shop", "Spend coins between runs"))
	var any: bool = false
	for entry in RaidManager.shop_items():
		any = true
		_body.add_child(_shop_row(entry))
	if not any:
		_body.add_child(Widgets.empty_state("Nothing for sale yet", "Clear a raid wave to earn coins."))

func _start_section() -> Control:
	var box := UIStyle.vbox(UITokens.SP_3)
	box.add_child(UIStyle.label("Choose a difficulty", false, UITokens.FONT_BODY))
	var diffs: Array = DataLoader.raid_shop.get("difficulties", {}).keys()
	diffs.sort()
	for d in diffs:
		var cfg: Dictionary = DataLoader.raid_shop["difficulties"][d]
		var row := UIStyle.hbox(UITokens.SP_3)
		var text := UIStyle.vbox(0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		text.add_child(UIStyle.label(str(d).capitalize(), false, UITokens.FONT_BODY))
		text.add_child(UIStyle.label("coins ×%.1f · enemy HP ×%.1f" % [
			float(cfg.get("coin_mult", 1.0)), float(cfg.get("hp_mult", 1.0))], true, UITokens.FONT_SMALL))
		var lock: String = RaidManager.locked_reason(str(d))
		var start := UIStyle.button("Begin raid" if lock == "" else lock, "Fight waves of golbins" if lock == "" else "Locked: " + lock)
		start.disabled = lock != ""
		start.pressed.connect(func():
			# The single activity slot: a raid takes the slot, so clear whatever holds it.
			if CombatManager.state != CombatManager.State.IDLE:
				CombatManager.stop_combat("retreat")
			if SkillManager.running:
				SkillManager.stop_action(SkillManager.StopReason.PLAYER, "Raid began")
			if not RaidManager.start_raid(str(d)):
				EventBus.notify("Could not start the raid", "warn")
			else:
				_rebuild())
		row.add_child(start)
		box.add_child(row)
	return box

func _active_run() -> Control:
	var box := UIStyle.vbox(UITokens.SP_3)
	box.add_child(UIStyle.label("Wave %d · %s" % [RaidManager.wave, RaidManager.run_stage.capitalize()], false, UITokens.FONT_BODY))
	box.add_child(UIStyle.label("Unbanked coins: %s · Best %s: wave %d" % [UIStyle.fmt(RaidManager.coins_this_raid), RaidManager.difficulty.capitalize(), int(RaidManager.best_wave.get(RaidManager.difficulty, 0))], true, UITokens.FONT_SMALL))
	if RaidManager.run_stage == "combat":
		var encounter: Dictionary = RaidManager.current_encounter
		box.add_child(UIStyle.label(str(encounter.get("name", "Patrol")), false, UITokens.FONT_BODY))
		box.add_child(UIStyle.label(str(encounter.get("description", "Defeat the enemies to continue.")), true, UITokens.FONT_SMALL))
	if RaidManager.run_stage == "reward":
		box.add_child(UIStyle.label("Wave cleared — select a relic or supply:", false, UITokens.FONT_BODY))
		for i in range(RaidManager.pending_choices.size()):
			var choice: String = str(RaidManager.pending_choices[i])
			var row := UIStyle.hbox(UITokens.SP_3)
			var info: Dictionary = RaidManager.choice_info(choice)
			var label: String = str(info.get("name", choice))
			if DataLoader.raid_shop.get("alt_items", []).has(choice):
				row.add_child(UIStyle.icon_texture("items", choice))
			var description: String = str(info.get("description", ""))
			var name_label := UIStyle.label(label + (" · " + description if description != "" else ""), true, UITokens.FONT_SMALL)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			var take := UIStyle.mini_button("Take")
			take.pressed.connect(func():
				RaidManager.choose(i)
				_rebuild())
			row.add_child(take)
			box.add_child(row)
	elif RaidManager.run_stage == "route":
		box.add_child(UIStyle.label("Choose your next encounter", false, UITokens.FONT_BODY))
		for i in range(RaidManager.pending_routes.size()):
			var route: Dictionary = RaidManager.pending_routes[i]
			var row := UIStyle.hbox(UITokens.SP_3)
			var info := UIStyle.label("%s · %s risk · %s. %s" % [str(route.get("name", "Route")), str(route.get("risk", "Low")), str(route.get("reward", "")), str(route.get("description", ""))], true, UITokens.FONT_SMALL)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var enter := UIStyle.mini_button("Enter")
			enter.pressed.connect(func():
				RaidManager.choose_route(i)
				_rebuild())
			row.add_child(enter)
			box.add_child(row)
	elif RaidManager.run_stage == "combat":
		box.add_child(UIStyle.label("Fight the current wave to continue.", true, UITokens.FONT_SMALL))
	if not RaidManager.run_relics.is_empty():
		box.add_child(UIStyle.label("Run relics", false, UITokens.FONT_BODY))
		for relic_id in RaidManager.run_relics:
			var relic: Dictionary = RaidManager.relic_catalog().get(relic_id, {})
			box.add_child(UIStyle.label("%s ×%d · %s" % [str(relic.get("name", relic_id)), int(RaidManager.run_relics[relic_id]), str(relic.get("description", ""))], true, UITokens.FONT_SMALL))
	if not RaidManager.run_history.is_empty():
		box.add_child(UIStyle.label("Recent clears", false, UITokens.FONT_BODY))
		for entry in RaidManager.run_history.slice(-4):
			box.add_child(UIStyle.label("Wave %d · %s · +%d coins" % [int(entry.get("wave", 0)), str(entry.get("encounter", "Patrol")), int(entry.get("coins", 0))], true, UITokens.FONT_SMALL))
	var end := UIStyle.danger_button("End raid and bank coins", "Retreat and keep the coins earned so far")
	end.pressed.connect(func():
		RaidManager.end_raid()
		_rebuild())
	box.add_child(end)
	return box

func _shop_row(entry: Dictionary) -> Control:
	var item_id: String = str(entry.get("item_id", ""))
	var cost: int = int(entry.get("cost", 0))
	var card := UIStyle.card()
	var row := UIStyle.hbox(UITokens.SP_4)
	card.add_child(row)
	if DataLoader.items.has(item_id):
		row.add_child(Widgets.item_icon(item_id))
	var text := UIStyle.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(UIStyle.label(str(entry.get("name", item_id)), false, UITokens.FONT_BODY))
	text.add_child(UIStyle.label("%s raid coins" % UIStyle.fmt(cost), true, UITokens.FONT_SMALL))
	var affordable: bool = PlayerData.raid_coins >= cost and not RaidManager.active
	if int(entry.get("max_level", 0)) > 0:
		text.add_child(UIStyle.label("Permanent rank %d/%d" % [int(entry.get("level", 0)), int(entry.get("max_level", 0))], true, UITokens.FONT_SMALL))
		affordable = affordable and int(entry.get("level", 0)) < int(entry.get("max_level", 0))
	var buy := UIStyle.mini_button("Buy")
	buy.disabled = not affordable
	if affordable:
		buy.pressed.connect(func():
			RaidManager.buy(item_id)
			_rebuild())
	else:
		buy.tooltip_text = "Finish the active raid, reach the required coins, and check upgrade rank"
	row.add_child(buy)
	return card
