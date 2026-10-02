extends VBoxContainer
## CombatPanel — expedition preparation and the live fight.
##
## The design pillar is "combat rewards preparation rather than frantic clicking": there is no
## input during a fight. This screen is therefore built as a preparation sheet (style, loadout,
## supplies, rules) plus a live readout. Retreat is one button and costs nothing.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _place_list: ItemList
var _places: Array = []
var _style_menu: OptionButton
var _melee_menu: OptionButton
var _area_menu: OptionButton
var _fight_button: Button
var _fight_box: VBoxContainer
var _food_box: VBoxContainer
var _food_controls: Array[Dictionary] = []
var _prep_box: VBoxContainer
var _places_box: VBoxContainer
var _log: Dictionary = Widgets.event_log(40)
var _selected_area: String = ""
var _built: bool = false
var _enemy_bar: ProgressBar = null
var _enemy_text: Label = null
var _player_bar: ProgressBar = null
var _player_text: Label = null
## Live meter rows (DPS etc). Polled in _process like the HP bars, so the numbers can never
## disagree with the fight that produced them.
var _meter_box: VBoxContainer = null
var _meter_labels: Dictionary = {}
var expeditions_only: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	EventBus.combat_started.connect(func(_c): _log["push"].call("Fight begun."); refresh())
	EventBus.combat_ended.connect(func(c): _log["push"].call("Fight ended (%s)." % str(c.get("reason", ""))); refresh())
	EventBus.monster_killed.connect(func(m): _log["push"].call("Defeated %s." % str(DataLoader.get_monster(m).get("name", m))))
	EventBus.monster_attacked.connect(func(d): if d > 0: _log["push"].call("You take %d damage." % d))
	EventBus.player_attacked.connect(func(d, crit): _log["push"].call("You hit for %d%s." % [d, " (critical)" if crit else ""]))
	EventBus.player_died.connect(func(c): _log["push"].call("Defeated by %s." % str(c.get("killer", "an enemy"))))
	EventBus.dungeon_completed.connect(func(d): _log["push"].call("%s cleared." % str(DataLoader.get_dungeon(d).get("name", d))))
	EventBus.state_refreshed.connect(refresh)
	EventBus.activity_changed.connect(_refresh_fight)
	EventBus.bank_changed.connect(_update_food_controls)
	refresh()

func _process(_delta: float) -> void:
	# Bars are polled from the live simulation (same contract as the activity strip): the
	# readout must never disagree with the fight that grants rewards.
	if not _built:
		return
	if CombatManager.state == CombatManager.State.FIGHTING:
		_live_bar(_enemy_bar, _enemy_text, CombatManager.monster_hp, maxf(1.0, float(CombatManager.monster_max_hp)),
			"%s / %s" % [UIStyle.fmt(CombatManager.monster_hp), UIStyle.fmt(CombatManager.monster_max_hp)])
		_live_bar(_player_bar, _player_text, CombatManager.player_hp, maxf(1.0, CombatManager._compute_max_hp()),
			"Your HP %s / %s" % [UIStyle.fmt(CombatManager.player_hp), UIStyle.fmt(CombatManager._compute_max_hp())])
	_update_food_controls()
	_refresh_meters()

## Damage-per-second and session tallies. Reuses CombatManager.session_readout() so the
## rolling window is computed once, in the simulation, not re-derived per frame per widget.
func _refresh_meters() -> void:
	if _meter_box == null or not is_instance_valid(_meter_box):
		return
	var r: Dictionary = CombatManager.session_readout()
	var values: Dictionary = {
		"dps": "%.1f/s" % float(r["dps"]),
		"fight_dps": "%.1f/s" % float(r["fight_dps"]),
		"damage_dealt": UIStyle.fmt(float(r["damage_dealt"])),
		"damage_taken": UIStyle.fmt(float(r["damage_taken"])),
		"gp_earned": UIStyle.fmt(float(r["gp_earned"])),
		"kills": "%d" % int(r["kills"]),
		"deaths": "%d" % int(r["deaths"]),
		"fight_time": UIStyle.fmt_duration(float(r["fight_time"])),
	}
	for key in _meter_labels.keys():
		var node: Variant = _meter_labels[key]
		if node is Label and is_instance_valid(node):
			(node as Label).text = str(values.get(str(key), "—"))

func _live_bar(bar: ProgressBar, text_node: Label, value: float, maximum: float, text: String) -> void:
	if bar != null and is_instance_valid(bar):
		bar.max_value = maximum
		bar.value = value
	if text_node != null and is_instance_valid(text_node):
		text_node.text = text

func focus_route(route: Dictionary) -> void:
	var area_id: String = str(route.get("area_id", ""))
	if area_id != "":
		_selected_area = area_id
		_rebuild_places()
		context_changed.emit({"kind": "region", "area_id": area_id})

func detail_context() -> Dictionary:
	if CombatManager.current_monster_id != "":
		return {"kind": "region", "area_id": str(CombatManager.context.get("id", _selected_area))}
	if _selected_area != "":
		return {"kind": "region", "area_id": _selected_area}
	return {}

func _build() -> void:
	_built = true
	add_child(UIStyle.title("Expeditions" if expeditions_only else "Combat", UITokens.FONT_DISPLAY))
	var food_card := UIStyle.panel()
	add_child(food_card)
	_food_box = UIStyle.vbox(UITokens.SP_4)
	food_card.add_child(_food_box)
	var prep_card := UIStyle.panel()
	add_child(prep_card)
	_prep_box = UIStyle.vbox(UITokens.SP_4)
	prep_card.add_child(_prep_box)
	var fight_card := UIStyle.panel()
	add_child(fight_card)
	_fight_box = UIStyle.vbox(UITokens.SP_4)
	fight_card.add_child(_fight_box)
	var places_card := UIStyle.panel()
	add_child(places_card)
	_places_box = UIStyle.vbox(UITokens.SP_4)
	places_card.add_child(_places_box)

# =========================================================================
#  Refresh
# =========================================================================

func refresh() -> void:
	if not _built:
		return
	_rebuild_food()
	_rebuild_prep()
	_refresh_fight()
	_rebuild_places()

func _rebuild_prep() -> void:
	_clear(_prep_box)
	_prep_box.add_child(UIStyle.section("Preparation", "Set your style and check supplies before you begin."))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UITokens.SP_4)
	row.add_theme_constant_override("v_separation", UITokens.SP_3)
	row.add_child(UIStyle.label("Style", true, UITokens.FONT_SMALL))
	_style_menu = Widgets.option_menu(["Melee", "Ranged", "Magic"], func(i):
		CombatManager.attack_style = ["melee", "ranged", "magic"][i]
		_refresh_fight(), _style_index())
	_style_menu.tooltip_text = "Combat triangle: melee beats ranged, ranged beats magic, magic beats melee"
	row.add_child(_style_menu)
	_melee_menu = Widgets.option_menu(["Stab (Bladework)", "Slash (Might)", "Block (Warding)"], func(i):
		CombatManager.melee_style = ["stab", "slash", "block"][i]
		_refresh_fight(), 0)
	_melee_menu.tooltip_text = "Which melee skill trains while you fight"
	row.add_child(_melee_menu)
	_prep_box.add_child(row)

	# Supplies and rules, stated explicitly.
	var summary: Dictionary = CombatManager.player_combat_summary()
	_prep_box.add_child(Widgets.key_value("Max hit / accuracy",
		"%s / %s" % [UIStyle.fmt(float(summary["max_hit"])), UIStyle.fmt(float(summary["accuracy"]))], UITokens.RED))
	var evasion: Dictionary = summary["evasion"]
	_prep_box.add_child(Widgets.key_value("Evasion vs melee / ranged / magic",
		"%s / %s / %s" % [UIStyle.fmt(float(evasion["melee"])), UIStyle.fmt(float(evasion["ranged"])), UIStyle.fmt(float(evasion["magic"]))]))
	_prep_box.add_child(Widgets.key_value("Damage reduction", UIStyle.fmt_percent(float(summary["damage_reduction"]) / 100.0), UITokens.TEAL))
	var forecast: Dictionary = PrayerManager.runway()
	_prep_box.add_child(Widgets.key_value("Prayer supply", "%.0f points · %.1f/min · %s" % [PlayerData.prayer_points, float(forecast.per_minute), "no drain" if is_inf(float(forecast.seconds)) else UIStyle.fmt_duration(float(forecast.seconds))]))
	for id in EquipmentManager.food_slots:
		if id != "": _prep_box.add_child(Widgets.key_value(str(DataLoader.get_item(id).get("name", id)), "%d portions · %d HP each (manual)" % [BankManager.get_count(id), int(float(DataLoader.get_item(id).get("heal_amount", 0)) * (1.0 + ModifierManager.get_modifier(ModifierKeys.FOOD_HEALING_PERCENT) / 100.0))]))
	var target: String = CombatManager.current_monster_id
	if target == "" and _selected_area != "":
		var place: Dictionary = DataLoader.get_dungeon(_selected_area) if DataLoader.dungeons.has(_selected_area) else DataLoader.areas.get(_selected_area, {})
		if not place.get("monsters", []).is_empty(): target = str(place.monsters[0])
	if target != "":
		var enemy: Dictionary = DataLoader.get_monster(target)
		var evasion_key: String = str(summary.style) + "_evasion"
		var tri: Dictionary = CombatFormulas.triangle(str(summary.style), str(enemy.get("attack_type", "melee")), DataLoader.game_modes.get(PlayerData.game_mode, {}))
		var chance: float = clampf(CombatFormulas.chance_to_hit(float(summary.accuracy), float(enemy.get(evasion_key, 10))) + float(tri.accuracy_percent) + float(CombatManager._active_hazard().get("player_accuracy_percent", 0)), 0, 100)
		var mh: int = maxi(1, floori(float(summary.max_hit) * (1.0 + float(tri.damage_percent) / 100.0)))
		var mn: int = CombatFormulas.min_hit(mh, ModifierManager.get_modifier(ModifierKeys.MIN_HIT_PERCENT_OF_MAX) / 100.0, ModifierManager.get_modifier(ModifierKeys.MIN_HIT_FLAT))
		_prep_box.add_child(Widgets.key_value("Expected normal hit vs " + str(enemy.get("name", target)), "≈ %.1f damage · %.1f%% hit chance" % [float(mn + mh) * 0.5 * chance / 100.0 * (1.0 - float(enemy.get("damage_reduction", 0)) / 100.0), chance], UITokens.RED))
	var food: int = _food_count()
	# A count of 0 is not self-evidently a problem, so the glyph states it, not just the red.
	_prep_box.add_child(Widgets.key_value("Food in storage", "%s %s" % [
			UIStyle.fmt_exact(float(food)), "✓" if food > 0 else "✗ none"],
		UITokens.GREEN if food > 0 else UITokens.RED,
		"Auto-eat: tier %d (threshold %s%%, efficiency %s%%)" % [
			int(PlayerData.settings.get("auto_eat_tier", 0)),
			UIStyle.fmt(float(CombatManager.AUTO_EAT.get(int(PlayerData.settings.get("auto_eat_tier", 0)), {}).get("threshold", 0.0))),
			UIStyle.fmt(float(CombatManager.AUTO_EAT.get(int(PlayerData.settings.get("auto_eat_tier", 0)), {}).get("efficiency", 0.0)))]))
	if food <= 0:
		_prep_box.add_child(UIStyle.colored_label(
			"No food. A defeat ends the fight and, offline, ends the whole session — bring supplies or train Vitality first.",
			UITokens.AMBER, UITokens.FONT_SMALL))

	# The auto-eat rule is derived from the tier the player owns; it is stated, not guessed at.
	var tier: int = int(PlayerData.settings.get("auto_eat_tier", 0))
	var rule: String = "not purchased"
	if tier > 0 and CombatManager.AUTO_EAT.has(tier):
		var cfg: Dictionary = CombatManager.AUTO_EAT[tier]
		rule = "eats below %s%% HP, heals to %s%% at %s%% efficiency" % [
			UIStyle.fmt(float(cfg["threshold"])), UIStyle.fmt(float(cfg["heal_to"])), UIStyle.fmt(float(cfg["efficiency"]))]
	_prep_box.add_child(Widgets.key_value("Auto-eat rule", rule,
		UITokens.GREEN if tier > 0 else UITokens.AMBER))
	_prep_box.add_child(UIStyle.colored_label(
		"Combat always stops on defeat, and offline combat stops permanently at the first defeat. Endless automatic deaths are impossible.",
		UITokens.TEXT_MUTED, UITokens.FONT_MICRO))
	_prep_box.add_child(Widgets.key_value("Offline combat",
		"enabled — stops on defeat" if bool(PlayerData.settings.get("offline_combat_enabled", true)) else "disabled",
		UITokens.TEXT_MUTED, "Change this in Settings → Offline"))

func _style_index() -> int:
	match CombatManager.attack_style:
		"ranged": return 1
		"magic": return 2
	return 0

func _refresh_fight() -> void:
	# The log is cached across rebuilds, so lift it out before the clear frees the box's children.
	Widgets.detach(_log["root"])
	_clear(_fight_box)
	_enemy_bar = null
	_enemy_text = null
	_player_bar = null
	_player_text = null
	_meter_box = null
	_meter_labels = {}
	_fight_box.add_child(UIStyle.section("Current expedition" if expeditions_only else "Current fight"))
	var fighting: bool = CombatManager.state != CombatManager.State.IDLE
	if not fighting:
		_fight_box.add_child(UIStyle.label("No fight in progress. Choose an encounter below and check your preparation.",
			true, UITokens.FONT_SMALL))
		# Session meters outlive the fight: "what did that run earn" is the question asked
		# immediately after retreating, and an empty panel would answer nothing.
		_build_meters()
		_fight_box.add_child(_log["root"])
		return
	var cmp: Dictionary = CombatManager.target_comparison()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITokens.SP_5)
	var sprite := TextureRect.new()
	sprite.texture = AssetRegistry.monster_sprite(CombatManager.current_monster_id)
	sprite.custom_minimum_size = Vector2(88, 88)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(sprite)
	var col := UIStyle.vbox(UITokens.SP_2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not cmp.is_empty():
		col.add_child(UIStyle.title("%s — level %d" % [str(cmp["monster_name"]), int(cmp["monster_level"])], UITokens.FONT_SUBHEAD))
		_enemy_bar = Widgets.progress_bar(float(CombatManager.monster_hp),
			maxf(1.0, float(CombatManager.monster_max_hp)), UITokens.RED,
			"%s / %s" % [UIStyle.fmt(CombatManager.monster_hp), UIStyle.fmt(CombatManager.monster_max_hp)], 14,
			"Enemy health")
		_enemy_text = (_enemy_bar.get_child(0) as Label) if _enemy_bar.get_child_count() > 0 else null
		col.add_child(_enemy_bar)
		col.add_child(Widgets.key_value("Damage type", str(cmp["monster_damage_type"]).capitalize()))
		col.add_child(Widgets.key_value("Their max hit", str(int(cmp["monster_max_hit"])), UITokens.RED))
		col.add_child(Widgets.key_value("Their damage reduction", UIStyle.fmt_percent(float(cmp["monster_damage_reduction"]) / 100.0)))
		col.add_child(Widgets.key_value("Your hit chance", UIStyle.fmt_percent(float(cmp["your_hit_chance_percent"]) / 100.0), UITokens.TEAL,
			"Derived from the live combat model, not a separate estimate"))
		col.add_child(Widgets.key_value("Their hit chance", UIStyle.fmt_percent(float(cmp["their_hit_chance_percent"]) / 100.0), UITokens.AMBER))
		var passives: Array = DataLoader.get_monster(str(CombatManager.current_monster_id)).get("passives", [])
		if not passives.is_empty():
			var passive_row := UIStyle.hbox(UITokens.SP_3)
			for passive_id in passives:
				var pid := str(passive_id)
				passive_row.add_child(Widgets.badge(pid.capitalize(), _passive_color(pid), _passive_tip(pid)))
			col.add_child(passive_row)
	head.add_child(col)
	_fight_box.add_child(head)
	var maxhp: float = CombatManager._compute_max_hp()
	_player_bar = Widgets.progress_bar(CombatManager.player_hp, maxhp, UITokens.GREEN,
		"Your HP %s / %s" % [UIStyle.fmt(CombatManager.player_hp), UIStyle.fmt(maxhp)], 16)
	_player_text = (_player_bar.get_child(0) as Label) if _player_bar.get_child_count() > 0 else null
	_fight_box.add_child(_player_bar)
	if not CombatManager.player_effects.is_empty():
		var effects: Array[String] = []
		for e in CombatManager.player_effects:
			effects.append("%s (%.1fs)" % [str(e.id).replace("_", " "), float(e.duration)])
		_fight_box.add_child(Widgets.key_value("Active effects on you", ", ".join(effects), UITokens.PURPLE))
	if not CombatManager.monster_effects.is_empty():
		var meffects: Array[String] = []
		for e in CombatManager.monster_effects:
			meffects.append("%s (%.1fs)" % [str(e.id).replace("_", " "), float(e.duration)])
		_fight_box.add_child(Widgets.key_value("Active effects on the enemy", ", ".join(meffects), UITokens.PURPLE))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", UITokens.SP_3)
	var retreat := UIStyle.danger_button("Retreat now", "End the fight immediately. Nothing is lost.")
	retreat.pressed.connect(func():
		CombatManager.stop_combat("retreat")
		refresh())
	buttons.add_child(retreat)
	var kill_switch := UIStyle.mini_button("Stop after this enemy", "Retreat once the current enemy is defeated or the fight ends")
	kill_switch.pressed.connect(func():
		CombatManager.combat_enabled = false
		EventBus.notify("Combat auto-repeat paused. Press 'Resume combat' to continue.", "info"))
	buttons.add_child(kill_switch)
	if not CombatManager.combat_enabled:
		var resume := UIStyle.mini_button("Resume combat")
		resume.pressed.connect(func(): CombatManager.combat_enabled = true)
		buttons.add_child(resume)
	_fight_box.add_child(buttons)
	_build_meters()
	_fight_box.add_child(_log["root"])

## A rolling DPS window and session tallies. The combat log above already narrates each
## exchange; these answer the question the log cannot — is the fight going faster than the
## last one, and what has the session actually earned.
func _build_meters() -> void:
	_meter_labels = {}
	_meter_box = UIStyle.vbox(UITokens.SP_2)
	_meter_box.add_child(UIStyle.label("Meters", true, UITokens.FONT_MICRO))
	var rows: Array = [
		["dps", "DPS (60s window)"],
		["fight_dps", "DPS (this fight)"],
		["fight_time", "Fight time"],
		["damage_dealt", "Damage dealt"],
		["damage_taken", "Damage taken"],
		["gp_earned", "Gold from combat"],
		["kills", "Kills this session"],
		["deaths", "Deaths this session"],
	]
	var r: Dictionary = CombatManager.session_readout()
	for row in rows:
		var key: String = str(row[0])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", UITokens.SP_3)
		var name_label := UIStyle.label(str(row[1]), true, UITokens.FONT_SMALL)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var value_label := UIStyle.label("—", false, UITokens.FONT_SMALL)
		line.add_child(value_label)
		_meter_labels[key] = value_label
		_meter_box.add_child(line)
	_fight_box.add_child(_meter_box)
	_refresh_meters()

func _rebuild_places() -> void:
	_clear(_places_box)
	_places_box.add_child(UIStyle.section("High-tier expeditions" if expeditions_only else "Regions and encounters"))
	if expeditions_only:
		var unlock_reason: String = CombatManager.expedition_unlock_reason()
		if unlock_reason != "":
			_places_box.add_child(UIStyle.colored_label("Locked — %s. Complete the Expedition Charter task to enter." % unlock_reason,
				UITokens.AMBER, UITokens.FONT_SMALL))
	var selector := HFlowContainer.new()
	selector.add_theme_constant_override("h_separation", UITokens.SP_4)
	selector.add_theme_constant_override("v_separation", UITokens.SP_3)
	_place_list = ItemList.new()
	_place_list.custom_minimum_size = Vector2(0, 220)
	_place_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_list.max_columns = 1
	_place_list.fixed_icon_size = Vector2i(36, 36)
	_places.clear()
	if not expeditions_only:
		for area_id in DataLoader.areas.keys():
			var area: Dictionary = DataLoader.areas[area_id]
			if str(area.get("type", "area")) == "slayer_area":
				continue
			_places.append({"type": "area", "id": area_id,
				"level": int((area.get("level_range", [0]) as Array)[0])})
	for dungeon_id in DataLoader.dungeons.keys():
		if CombatManager.is_expedition(str(dungeon_id)) != expeditions_only:
			continue
		var dungeon: Dictionary = DataLoader.dungeons[dungeon_id]
		_places.append({"type": "dungeon", "id": dungeon_id,
			"level": int((dungeon.get("level_range", [0]) as Array)[0])})
	_places.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
	for place in _places:
		var id: String = str(place["id"])
		if str(place["type"]) == "area":
			_place_list.add_item("Region · %s" % str(DataLoader.areas[id].get("name", id)),
				AssetRegistry.icon("areas", id))
		else:
			_place_list.add_item(("Expedition · " if expeditions_only else "Dungeon · ")
				+ str(DataLoader.dungeons[id].get("name", id)), AssetRegistry.icon("dungeons", id))
	if _selected_area == "" and not _places.is_empty():
		_selected_area = str(_places[0]["id"])
	var initial: int = 0
	for i in range(_places.size()):
		if str(_places[i]["id"]) == _selected_area:
			initial = i
	_place_list.select(initial)
	_place_list.item_selected.connect(func(i):
		_selected_area = str(_places[i]["id"])
		context_changed.emit({"kind": "region", "area_id": _selected_area})
		_rebuild_places())
	_places_box.add_child(_place_list)
	_place_list.call_deferred("ensure_current_is_visible")
	_fight_button = UIStyle.primary_button(("Begin expedition" if expeditions_only else "Start fight") if CombatManager.state == CombatManager.State.IDLE else "Change target (retreats)")
	_fight_button.pressed.connect(_on_fight)
	_fight_button.disabled = expeditions_only and CombatManager.expedition_unlock_reason() != ""
	selector.add_child(_fight_button)
	_places_box.add_child(selector)

	if _selected_area == "":
		return
	var is_dungeon: bool = DataLoader.dungeons.has(_selected_area)
	var place: Dictionary = DataLoader.get_dungeon(_selected_area) if is_dungeon else DataLoader.areas.get(_selected_area, {})
	var card := UIStyle.card()
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UITokens.SP_3)
	var icon := UIStyle.icon_texture("dungeons" if is_dungeon else "areas", _selected_area)
	icon.custom_minimum_size = Vector2(64, 64)
	header.add_child(icon)
	header.add_child(UIStyle.title(str(place.get("name", _selected_area)), UITokens.FONT_SUBHEAD))
	col.add_child(header)
	if str(place.get("flavour", "")) != "":
		var f := UIStyle.label(str(place["flavour"]), true, UITokens.FONT_SMALL)
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(f)
	var levels: Array = place.get("level_range", [])
	if levels.size() == 2:
		col.add_child(Widgets.key_value("Enemy levels", "%d – %d" % [int(levels[0]), int(levels[1])]))
	var identity: Dictionary = {}
	for monster_id in place.get("monsters", []):
		for drop in DataLoader.get_monster(str(monster_id)).get("loot_table", []):
			var id: String = str(drop.get("item_id", ""))
			if id != "": identity[id] = 1
	if not identity.is_empty():
		col.add_child(UIStyle.label("Encounter rewards", true, UITokens.FONT_MICRO))
		col.add_child(Widgets.item_rewards(identity))
	if is_dungeon:
		var cleared: bool = PlayerData.completion_log.get("dungeons", {}).has(_selected_area)
		col.add_child(Widgets.requirement_row("First clear recorded", 1.0 if cleared else 0.0, 1.0, cleared))
	if not is_dungeon:
		var defeated: int = 0
		for id in place.get("monsters", []):
			if PlayerData.completion_log.get("monsters", {}).has(str(id)): defeated += 1
		col.add_child(Widgets.requirement_row("First defeat checklist", defeated, place.get("monsters", []).size(), defeated == place.get("monsters", []).size()))
	col.add_child(Widgets.key_value("Enemies in this zone", str((place.get("monsters", []) as Array).size())))
	if not is_dungeon and typeof(place.get("hazard", {})) == TYPE_DICTIONARY and not (place.get("hazard", {}) as Dictionary).is_empty():
		col.add_child(UIStyle.colored_label("Hazard — %s" % str((place["hazard"] as Dictionary).get("label", "hostile ground")),
			UITokens.AMBER, UITokens.FONT_SMALL))
	if is_dungeon:
		var reqs: Variant = place.get("requires", {})
		var prev: String = str(place.get("requires_dungeon", ""))
		var locked: bool = false
		if (typeof(reqs) == TYPE_DICTIONARY and not (reqs as Dictionary).is_empty()) or prev != "":
			col.add_child(UIStyle.section("Unlock requirements"))
			for skill_id in (reqs as Dictionary).keys():
				var level: int = PlayerData.get_level(str(skill_id))
				var needed: int = int(reqs[skill_id])
				if level < needed:
					locked = true
				col.add_child(Widgets.requirement_row(
					"%s %d" % [str(DataLoader.get_skill(str(skill_id)).get("name", skill_id)), needed],
					float(level), float(needed), level >= needed))
			if prev != "":
				var cleared: bool = (PlayerData.completion_log.get("dungeons", {}) as Dictionary).has(prev)
				if not cleared:
					locked = true
				col.add_child(Widgets.requirement_row(
					"Clear %s" % str(DataLoader.get_dungeon(prev).get("name", prev)),
					1.0 if cleared else 0.0, 1.0, cleared, "Open Expeditions to attempt it"))
		if bool(place.get("equipment_locked", false)):
			col.add_child(UIStyle.colored_label("Equipment cannot be changed during this expedition.",
				UITokens.AMBER, UITokens.FONT_SMALL))
		if locked:
			col.add_child(UIStyle.colored_label("Locked — %s" % CombatManager.dungeon_lock_reason(_selected_area),
				UITokens.AMBER, UITokens.FONT_SMALL))
		_fight_button.disabled = locked or (expeditions_only and CombatManager.expedition_unlock_reason() != "")
		var reward: Dictionary = place.get("rewards_first_clear", {})
		if not reward.is_empty():
			var parts: Array[String] = []
			if reward.has("gp"):
				parts.append("%s GP" % UIStyle.fmt(float(reward["gp"])))
			for item_id in (reward.get("items", {}) as Dictionary).keys():
				parts.append("%s ×%s" % [str(DataLoader.get_item(str(item_id)).get("name", item_id)),
					UIStyle.fmt_exact(float(reward["items"][item_id]))])
			col.add_child(Widgets.key_value("First clear", " · ".join(parts), UITokens.GOLD_BRIGHT))
		col.add_child(UIStyle.colored_label("Dungeons run their encounter list in order and stop at the end.",
			UITokens.TEXT_MUTED, UITokens.FONT_MICRO))
	else:
		col.add_child(UIStyle.colored_label("Regions spawn endlessly from their enemy pool until you retreat.",
			UITokens.TEXT_MUTED, UITokens.FONT_MICRO))
	_places_box.add_child(card)

func _on_fight() -> void:
	if _selected_area == "":
		return
	if expeditions_only and CombatManager.expedition_unlock_reason() != "":
		EventBus.notify("Expedition locked: %s" % CombatManager.expedition_unlock_reason(), "warn")
		return
	if CombatManager.state != CombatManager.State.IDLE:
		CombatManager.stop_combat("retreat")
		return
	var is_dungeon: bool = DataLoader.dungeons.has(_selected_area)
	var place: Dictionary = DataLoader.get_dungeon(_selected_area) if is_dungeon else DataLoader.areas.get(_selected_area, {})
	GameManager.request_combat({
		"type": "dungeon" if is_dungeon else "area",
		"id": _selected_area,
		"monsters": place.get("monsters", []),
		"endless": not is_dungeon,
		"attack_style": CombatManager.attack_style,
		"melee_style": CombatManager.melee_style,
	})
	refresh()

func _food_count() -> int:
	var n: int = 0
	for item_id in BankManager.items.keys():
		if str(DataLoader.get_item(item_id).get("item_type", "")) == "food":
			n += int(BankManager.items[item_id])
	return n

## Passive tooltips: a mechanic the player cannot see is a mechanic that feels like a bug.
func _passive_tip(passive_id: String) -> String:
	match passive_id:
		"regeneration": return "Heals 2% of its maximum health after every attack it makes."
		"thorns": return "Reflects 10% of the damage it takes back at you while it stands."
		"enrage": return "Hits 50% harder once it is at or below 25% health."
	return passive_id.capitalize()

func _passive_color(passive_id: String) -> Color:
	match passive_id:
		"regeneration": return UITokens.GREEN
		"thorns": return UITokens.AMBER
		"enrage": return UITokens.RED
	return UITokens.PURPLE

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _rebuild_food() -> void:
	_clear(_food_box)
	_food_controls.clear()
	_food_box.add_child(UIStyle.section("Combat food", "Equip up to three foods from Storage. Eating uses one from its stack."))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", UITokens.SP_4)
	flow.add_theme_constant_override("v_separation", UITokens.SP_4)
	_food_box.add_child(flow)
	for slot in range(EquipmentManager.FOOD_SLOT_COUNT):
		var item_id: String = EquipmentManager.food_slots[slot]
		var card := UIStyle.card()
		card.custom_minimum_size.x = 180
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_child(card)
		var col := UIStyle.vbox(UITokens.SP_3)
		card.add_child(col)
		col.add_child(UIStyle.label("Food slot %d" % (slot + 1), true, UITokens.FONT_MICRO))
		if item_id == "":
			col.add_child(UIStyle.label("Empty", true))
			var assign := UIStyle.button("Equip from Storage")
			assign.pressed.connect(func(): navigated.emit({"screen": Screens.BANK}))
			col.add_child(assign)
			continue
		var item: Dictionary = DataLoader.get_item(item_id)
		var header := UIStyle.hbox()
		header.add_child(Widgets.item_icon(item_id, 40))
		var name_label := UIStyle.label(str(item.get("name", item_id)))
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.add_child(name_label)
		col.add_child(header)
		var count := UIStyle.label("", true, UITokens.FONT_SMALL)
		col.add_child(count)
		var buttons := UIStyle.hbox()
		col.add_child(buttons)
		var eat := UIStyle.primary_button("Eat")
		var index: int = slot
		eat.pressed.connect(func():
			EquipmentManager.eat_food_slot(index)
			_update_food_controls())
		buttons.add_child(eat)
		var clear := UIStyle.mini_button("Clear", "Remove the assignment; food stays in Storage")
		clear.pressed.connect(func(): EquipmentManager.equip_food(index, ""))
		buttons.add_child(clear)
		_food_controls.append({"item_id": item_id, "count": count, "eat": eat})
	_update_food_controls()

func _update_food_controls() -> void:
	for entry in _food_controls:
		var count: Label = entry["count"]
		var eat: Button = entry["eat"]
		if not is_instance_valid(count) or not is_instance_valid(eat):
			continue
		var item_id: String = str(entry["item_id"])
		var quantity: int = BankManager.get_count(item_id)
		var heal: float = float(DataLoader.get_item(item_id).get("heal_amount", 0)) * (1.0 + ModifierManager.get_modifier(ModifierKeys.FOOD_HEALING_PERCENT) / 100.0)
		count.text = "%s left · +%s HP" % [UIStyle.fmt_exact(quantity), UIStyle.fmt(heal)]
		var full: bool = CombatManager.player_hp >= CombatManager._compute_max_hp()
		eat.disabled = quantity <= 0 or full
		eat.text = "Out of food" if quantity <= 0 else ("Full health" if full else "Eat")
		eat.tooltip_text = "Eat one to restore up to %s HP" % UIStyle.fmt(heal)
