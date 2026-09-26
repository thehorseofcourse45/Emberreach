extends VBoxContainer
## CombatPanel — expedition preparation and the live fight.
##
## The design pillar is "combat rewards preparation rather than frantic clicking": there is no
## input during a fight. This screen is therefore built as a preparation sheet (style, loadout,
## supplies, rules) plus a live readout. Retreat is one button and costs nothing.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _place_menu: OptionButton
var _places: Array = []
var _style_menu: OptionButton
var _melee_menu: OptionButton
var _area_menu: OptionButton
var _fight_button: Button
var _fight_box: VBoxContainer
var _prep_box: VBoxContainer
var _places_box: VBoxContainer
var _log: Dictionary = Widgets.event_log(40)
var _selected_area: String = ""
var _built: bool = false
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
	refresh()

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
	var food: int = _food_count()
	_prep_box.add_child(Widgets.key_value("Food in storage", UIStyle.fmt_exact(float(food)),
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
	_fight_box.add_child(UIStyle.section("Current expedition" if expeditions_only else "Current fight"))
	var fighting: bool = CombatManager.state != CombatManager.State.IDLE
	if not fighting:
		_fight_box.add_child(UIStyle.label("No fight in progress. Choose an encounter below and check your preparation.",
			true, UITokens.FONT_SMALL))
		_fight_box.add_child(_log["root"])
		return
	var cmp: Dictionary = CombatManager.target_comparison()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITokens.SP_5)
	var sprite := TextureRect.new()
	sprite.texture = AssetRegistry.monster_sprite(CombatManager.current_monster_id)
	sprite.custom_minimum_size = Vector2(UITokens.ICON_XL, UITokens.ICON_XL)
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(sprite)
	var col := UIStyle.vbox(UITokens.SP_2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not cmp.is_empty():
		col.add_child(UIStyle.title("%s — level %d" % [str(cmp["monster_name"]), int(cmp["monster_level"])], UITokens.FONT_SUBHEAD))
		col.add_child(Widgets.progress_bar(float(CombatManager.monster_hp),
			maxf(1.0, float(CombatManager.monster_max_hp)), UITokens.RED,
			"%s / %s" % [UIStyle.fmt(CombatManager.monster_hp), UIStyle.fmt(CombatManager.monster_max_hp)], 14,
			"Enemy health"))
		col.add_child(Widgets.key_value("Damage type", str(cmp["monster_damage_type"]).capitalize()))
		col.add_child(Widgets.key_value("Their max hit", str(int(cmp["monster_max_hit"])), UITokens.RED))
		col.add_child(Widgets.key_value("Their damage reduction", UIStyle.fmt_percent(float(cmp["monster_damage_reduction"]) / 100.0)))
		col.add_child(Widgets.key_value("Your hit chance", UIStyle.fmt_percent(float(cmp["your_hit_chance_percent"]) / 100.0), UITokens.TEAL,
			"Derived from the live combat model, not a separate estimate"))
		col.add_child(Widgets.key_value("Their hit chance", UIStyle.fmt_percent(float(cmp["their_hit_chance_percent"]) / 100.0), UITokens.AMBER))
	head.add_child(col)
	_fight_box.add_child(head)
	var maxhp: float = CombatManager._compute_max_hp()
	_fight_box.add_child(Widgets.progress_bar(CombatManager.player_hp, maxhp, UITokens.GREEN,
		"Your HP %s / %s" % [UIStyle.fmt(CombatManager.player_hp), UIStyle.fmt(maxhp)], 16))
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
	_fight_box.add_child(_log["root"])

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
	_place_menu = OptionButton.new()
	# "Region · <long name>" must be able to shrink and clip on a narrow window.
	_place_menu.custom_minimum_size = Vector2(Widgets.MIN_CONTROL_W, UITokens.H_CONTROL)
	_place_menu.clip_text = true
	_place_menu.fit_to_longest_item = false
	_places.clear()
	var areas: Array = DataLoader.areas.keys()
	areas.sort_custom(func(a, b):
		return int((DataLoader.areas[a].get("level_range", [0]) as Array)[0]) < int((DataLoader.areas[b].get("level_range", [0]) as Array)[0]))
	if not expeditions_only:
		for area_id in areas:
			if str(DataLoader.areas[area_id].get("type", "area")) == "slayer_area":
				continue
			_places.append({"type": "area", "id": area_id})
			_place_menu.add_item("Region · %s" % str(DataLoader.areas[area_id].get("name", area_id)))
	for dungeon_id in DataLoader.dungeons.keys():
		if CombatManager.is_expedition(str(dungeon_id)) != expeditions_only:
			continue
		_places.append({"type": "dungeon", "id": dungeon_id})
		_place_menu.add_item(("Expedition · " if expeditions_only else "Dungeon · ") + str(DataLoader.dungeons[dungeon_id].get("name", dungeon_id)))
	if _selected_area == "" and not _places.is_empty():
		_selected_area = str(_places[0]["id"])
	var initial: int = 0
	for i in range(_places.size()):
		if str(_places[i]["id"]) == _selected_area:
			initial = i
	_place_menu.selected = initial
	_place_menu.item_selected.connect(func(i):
		_selected_area = str(_places[i]["id"])
		context_changed.emit({"kind": "region", "area_id": _selected_area})
		_rebuild_places())
	selector.add_child(_place_menu)
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
	col.add_child(UIStyle.title(str(place.get("name", _selected_area)), UITokens.FONT_SUBHEAD))
	if str(place.get("flavour", "")) != "":
		var f := UIStyle.label(str(place["flavour"]), true, UITokens.FONT_SMALL)
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(f)
	var levels: Array = place.get("level_range", [])
	if levels.size() == 2:
		col.add_child(Widgets.key_value("Enemy levels", "%d – %d" % [int(levels[0]), int(levels[1])]))
	col.add_child(Widgets.key_value("Enemies in this zone", str((place.get("monsters", []) as Array).size())))
	if is_dungeon:
		var reqs: Variant = place.get("requires", {})
		var locked: bool = false
		if typeof(reqs) == TYPE_DICTIONARY and not (reqs as Dictionary).is_empty():
			col.add_child(UIStyle.section("Unlock requirements"))
			for skill_id in (reqs as Dictionary).keys():
				var level: int = PlayerData.get_level(str(skill_id))
				var needed: int = int(reqs[skill_id])
				if level < needed:
					locked = true
				col.add_child(Widgets.requirement_row(
					"%s %d" % [str(DataLoader.get_skill(str(skill_id)).get("name", skill_id)), needed],
					float(level), float(needed), level >= needed))
		if bool(place.get("equipment_locked", false)):
			col.add_child(UIStyle.colored_label("Equipment cannot be changed during this expedition.",
				UITokens.AMBER, UITokens.FONT_SMALL))
		if locked:
			col.add_child(UIStyle.colored_label("Locked — train the skills above to unlock this expedition.",
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

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
