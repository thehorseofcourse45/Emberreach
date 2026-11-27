extends VBoxContainer
## The Shattered Trail and any still-active legacy gauntlet journey.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _body: VBoxContainer
var _summary: Label
var _built: bool = false
var _selected_trial: int = 0

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Astral Trial Chamber", UITokens.FONT_DISPLAY))
	add_child(UIStyle.label("Beyond the Final Horizon, ten celestial champions guard the chamber. Defeat each to unlock the next and earn Trial Marks.", true))
	_summary = UIStyle.label("", true, UITokens.FONT_SMALL)
	add_child(_summary)
	_body = UIStyle.vbox(UITokens.SP_4)
	add_child(_body)
	EventBus.state_refreshed.connect(_rebuild)
	EventBus.combat_ended.connect(func(_c): _rebuild())
	EventBus.monster_spawned.connect(func(_id, _hp):
		if RaidManager.active and RaidManager.astral_encounter != "": _rebuild())
	EventBus.shop_upgrade_purchased.connect(func(_i): _rebuild())
	_rebuild()

func focus_route(route: Dictionary) -> void:
	var id := str(route.get("trial_id", route.get("area_id", "")))
	for i in range(RaidManager.ASTRAL_TRIALS.size()):
		if str(RaidManager.ASTRAL_TRIALS[i].id) == id:
			_selected_trial = i
			if _built: _rebuild()
			return

func detail_context() -> Dictionary:
	return {"kind":"region", "area_id":str(RaidManager.ASTRAL_TRIALS[_selected_trial].id)}

func _rebuild() -> void:
	if not _built: return
	_summary.text = "Trial Marks: %s · Trials cleared: %d / %d" % [UIStyle.fmt(PlayerData.raid_coins), RaidManager.astral_completions.size(), RaidManager.ASTRAL_TRIALS.size()]
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if RaidManager.active:
		if RaidManager.astral_encounter != "": _body.add_child(_active_astral())
		elif RaidManager.trail_mode: _body.add_child(_active_trail())
		else: _body.add_child(_active_run())
	else:
		_body.add_child(_astral_trials())
	_body.add_child(UIStyle.section("Astral Armory", "Earn Trial Marks and defeat champions to unlock celestial equipment."))
	var goods := RaidManager.shop_items()
	for entry in goods:
		if DataLoader.items.has(str(entry.get("item_id", ""))): _body.add_child(_shop_row(entry))
	_body.add_child(UIStyle.section("Celestial Blessings", "Permanent ranks and marks carry over from the previous outfitter."))
	for entry in goods:
		if not DataLoader.items.has(str(entry.get("item_id", ""))): _body.add_child(_shop_row(entry))

func _astral_trials() -> Control:
	var box := UIStyle.vbox(UITokens.SP_3)
	box.add_child(UIStyle.section("Astral trials"))
	var list := ItemList.new()
	list.name = "AstralTrialList"
	list.custom_minimum_size = Vector2(0, 220)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.max_columns = 1
	list.fixed_icon_size = Vector2i(36, 36)
	for i in range(RaidManager.ASTRAL_TRIALS.size()):
		var trial: Dictionary = RaidManager.ASTRAL_TRIALS[i]
		list.add_item("Trial · %s" % str(trial.name), AssetRegistry.icon("dungeons", str(trial.id)))
	list.select(_selected_trial)
	list.item_selected.connect(func(i):
		_selected_trial = i
		context_changed.emit(detail_context())
		_rebuild())
	box.add_child(list)
	var trial: Dictionary = RaidManager.ASTRAL_TRIALS[_selected_trial]
	var enemy: Dictionary = DataLoader.get_monster(str(trial.enemy))
	var lock := RaidManager.astral_lock_reason(_selected_trial)
	var button := UIStyle.primary_button("Begin trial")
	button.disabled = lock != ""
	button.tooltip_text = lock
	button.pressed.connect(func():
		if CombatManager.state != CombatManager.State.IDLE: CombatManager.stop_combat("retreat")
		if not RaidManager.start_astral(_selected_trial): EventBus.notify("Could not start the trial", "warn")
		_rebuild())
	var actions := UIStyle.hbox(UITokens.SP_3)
	actions.add_child(button)
	box.add_child(actions)
	var card := UIStyle.card()
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var header := UIStyle.hbox(UITokens.SP_3)
	var icon := UIStyle.icon_texture("dungeons", str(trial.id))
	icon.custom_minimum_size = Vector2(64, 64)
	header.add_child(icon)
	header.add_child(UIStyle.title(str(trial.name), UITokens.FONT_SUBHEAD))
	col.add_child(header)
	var sequence := RaidManager.astral_sequence(_selected_trial)
	var lowest := int(enemy.get("combat_level", 0))
	for id in sequence: lowest = mini(lowest, int(DataLoader.get_monster(str(id)).get("combat_level", lowest)))
	col.add_child(Widgets.key_value("Enemy levels", "%s – %s" % [UIStyle.fmt_exact(float(lowest)), UIStyle.fmt_exact(float(enemy.get("combat_level", 0)))]))
	col.add_child(Widgets.key_value("Encounters", str(sequence.size())))
	col.add_child(Widgets.key_value("Final boss", str(enemy.get("name", trial.enemy))))
	col.add_child(Widgets.key_value("Base Trial Marks per clear", UIStyle.fmt(float(trial.marks))))
	var loot: Dictionary = {}
	for mid in sequence:
		for drop in DataLoader.get_monster(str(mid)).get("loot_table", []):
			var id := str(drop.get("item_id", ""))
			if id != "": loot[id] = 1
	if not loot.is_empty():
		col.add_child(UIStyle.label("Encounter rewards", true, UITokens.FONT_MICRO))
		col.add_child(Widgets.item_rewards(loot))
	var clears := int(RaidManager.astral_completions.get(str(trial.id), 0))
	col.add_child(Widgets.requirement_row("First clear recorded", 1 if clears > 0 else 0, 1, clears > 0))
	col.add_child(Widgets.key_value("Total clears", str(clears)))
	col.add_child(UIStyle.section("Unlock requirements"))
	var horizon: bool = PlayerData.completion_log.get("dungeons", {}).has("final_horizon")
	col.add_child(Widgets.requirement_row("Clear The Final Horizon", 1 if horizon else 0, 1, horizon))
	if _selected_trial > 0:
		var previous: Dictionary = RaidManager.ASTRAL_TRIALS[_selected_trial - 1]
		var done := RaidManager.astral_completions.has(str(previous.id))
		col.add_child(Widgets.requirement_row("Clear %s" % str(previous.name), 1 if done else 0, 1, done))
	if lock != "": col.add_child(UIStyle.colored_label("Locked — %s" % lock, UITokens.AMBER, UITokens.FONT_SMALL))
	box.add_child(card)
	return box

func _active_astral() -> Control:
	var box := UIStyle.vbox(UITokens.SP_3)
	box.add_child(UIStyle.label("Active trial: %s" % str(RaidManager.current_encounter.get("name", "Astral trial")), false, UITokens.FONT_BODY))
	var sequence: Array = CombatManager.context.get("monsters", [])
	if not sequence.is_empty():
		box.add_child(Widgets.key_value("Encounter", "%d / %d" % [mini(int(CombatManager.context.get("index", 0)) + 1, sequence.size()), sequence.size()]))
		box.add_child(UIStyle.label("Current enemy: %s" % str(DataLoader.get_monster(CombatManager.current_monster_id).get("name", CombatManager.current_monster_id)), true, UITokens.FONT_SMALL))
	var view := UIStyle.mini_button("View combat")
	view.pressed.connect(func(): navigated.emit({"screen":Screens.COMBAT}))
	box.add_child(view)
	var retreat := UIStyle.danger_button("Leave trial", "Retreat from this encounter.")
	retreat.pressed.connect(func(): RaidManager.end_raid(); _rebuild())
	box.add_child(retreat)
	return box

func _active_trail() -> Control:
	var box := UIStyle.vbox(UITokens.SP_3)
	box.add_child(UIStyle.title("Journey · %s" % RaidManager.difficulty.capitalize(), UITokens.FONT_SUBHEAD))
	box.add_child(Widgets.key_value("Stops completed", "%d / %d" % [mini(RaidManager.wave if RaidManager.run_stage == "route" else RaidManager.wave - 1, RaidManager.TRAIL_STOPS), RaidManager.TRAIL_STOPS]))
	box.add_child(Widgets.key_value("Supplies", str(RaidManager.trail_supplies)))
	box.add_child(Widgets.key_value("Camps used", "%d / 2" % RaidManager.trail_camps))
	box.add_child(Widgets.key_value("Unbanked marks", UIStyle.fmt(RaidManager.coins_this_raid)))
	var map_label := UIStyle.label(" → ".join(RaidManager.TRAIL_LANDMARKS) + " → Guardian", true, UITokens.FONT_SMALL)
	map_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(map_label)
	if RaidManager.run_stage == "combat":
		box.add_child(UIStyle.label(str(RaidManager.current_encounter.get("name", "Encounter")), false, UITokens.FONT_BODY))
		box.add_child(UIStyle.label("Defeat the current enemies to continue.", true, UITokens.FONT_SMALL))
		var view := UIStyle.mini_button("View combat")
		view.pressed.connect(func(): navigated.emit({"screen":Screens.COMBAT}))
		box.add_child(view)
	elif RaidManager.run_stage == "route":
		var next_stop: String = "Guardian" if RaidManager.wave >= RaidManager.TRAIL_STOPS else str(RaidManager.TRAIL_LANDMARKS[RaidManager.wave])
		box.add_child(UIStyle.label("Choose your route · %s" % next_stop, false, UITokens.FONT_BODY))
		for i in range(RaidManager.pending_routes.size()):
			var route: Dictionary = RaidManager.pending_routes[i]
			var label := UIStyle.label("%s · %s · %s" % [route.name, route.reward, route.description], true, UITokens.FONT_SMALL)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(label)
			var enter := UIStyle.button("Choose %s" % str(route.name))
			enter.disabled = (str(route.id) == "trail_cache" and RaidManager.trail_supplies < 1) or (str(route.id) == "trail_camp" and RaidManager.trail_camps >= 2)
			enter.pressed.connect(func(): RaidManager.choose_route(i); _rebuild())
			box.add_child(enter)
	if not RaidManager.run_history.is_empty():
		box.add_child(UIStyle.label("Recent stops", false, UITokens.FONT_BODY))
		for entry in RaidManager.run_history.slice(-4):
			box.add_child(UIStyle.label("Stop %d · %s · +%d marks" % [int(entry.get("wave", 0)), str(entry.get("encounter", "Patrol")), int(entry.get("coins", 0))], true, UITokens.FONT_SMALL))
	var retreat := UIStyle.danger_button("End journey and bank marks", "Retreat and keep the marks earned so far.")
	retreat.pressed.connect(func(): RaidManager.end_raid(); _rebuild())
	box.add_child(retreat)
	return box

func _active_run() -> Control:
	var box := UIStyle.vbox(UITokens.SP_3)
	box.add_child(UIStyle.label("Previous gauntlet run — finish or retreat to enter the Astral Trial Chamber.", true, UITokens.FONT_SMALL))
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
			if DataLoader.raid_shop.get("alt_items", []).has(choice) or DataLoader.raid_shop.get("legacy_alt_items", []).has(choice):
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
	var end := UIStyle.danger_button("End gauntlet and bank coins", "Retreat and keep the coins earned so far")
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
		row.add_child(Widgets.item_icon(item_id, 48))
	else:
		var blessing_icon := UIStyle.icon_texture("navigation", item_id)
		blessing_icon.custom_minimum_size = Vector2(48, 48)
		row.add_child(blessing_icon)
	var text := UIStyle.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(UIStyle.label(str(entry.get("name", item_id)), false, UITokens.FONT_BODY))
	text.add_child(UIStyle.label("%s Trial Marks" % UIStyle.fmt(cost), true, UITokens.FONT_SMALL))
	if DataLoader.items.has(item_id):
		var item: Dictionary = DataLoader.get_item(item_id)
		var stats: Array[String] = []
		for key in item.get("equipment_stats", {}): stats.append("%s +%s" % [str(key).replace("_", " ").capitalize(), str(item.equipment_stats[key])])
		if not stats.is_empty(): text.add_child(UIStyle.label(" · ".join(stats), true, UITokens.FONT_SMALL))
		var passives: Dictionary = item.get("passive_modifiers", {})
		if not passives.is_empty(): text.add_child(UIStyle.label(UIStyle.describe_modifier_table(passives).replace(" percent", ""), true, UITokens.FONT_SMALL))
	else:
		text.add_child(UIStyle.label(str(entry.get("description", "")), true, UITokens.FONT_SMALL))
	var lock := str(entry.get("lock_reason", ""))
	if lock != "": text.add_child(UIStyle.label(lock, true, UITokens.FONT_SMALL))
	var affordable: bool = PlayerData.raid_coins >= cost and not RaidManager.active and lock == ""
	if int(entry.get("max_level", 0)) > 0:
		text.add_child(UIStyle.label("Permanent rank %d/%d" % [int(entry.get("level", 0)), int(entry.get("max_level", 0))], true, UITokens.FONT_SMALL))
		affordable = affordable and int(entry.get("level", 0)) < int(entry.get("max_level", 0))
	# Stat and blessing lines sit just under UIStyle's wrap threshold and set a 420px window's width.
	for line in text.get_children():
		if line is Label:
			(line as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var buy := UIStyle.mini_button("Buy")
	buy.disabled = not affordable
	if affordable:
		buy.pressed.connect(func():
			RaidManager.buy(item_id)
			_rebuild())
	else:
		buy.tooltip_text = lock if lock != "" else "Finish the active trial, earn enough marks, and check the upgrade rank."
	row.add_child(buy)
	return card
