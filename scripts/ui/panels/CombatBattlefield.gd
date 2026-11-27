extends VBoxContainer
## Compact preview and live rendering for ordinary encounters.

const HEARTHFALL_ART := "res://assets/combat/hearthfall.webp"
const ATTACK_ICON := {"melee": "attack", "ranged": "ranged", "magic": "magic"}

var _body: VBoxContainer
var _recap: VBoxContainer
var _recap_title: Label
var _recap_encounter: Label
var _run_labels: Array[Label] = []
var _loot_box: VBoxContainer
var _shown_loot: Dictionary = {}
var _selected := ""
var _view := ""
var _seen_run_revision := -1
var _hp: Array[ProgressBar] = []
var _swings: Array[ProgressBar] = []
var _effects: Array[Label] = []
var _sprite: TextureRect
var _enemy_fx: Control
var _player_fx: Control
var _cue: Label
var _cue_until := 0


func build(actions: Control) -> void:
	add_theme_constant_override("separation", UITokens.SP_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body = UIStyle.vbox(UITokens.SP_3)
	add_child(_body)
	add_child(actions)
	var card := UIStyle.card()
	add_child(card)
	_recap = UIStyle.vbox(UITokens.SP_3)
	card.add_child(_recap)
	_recap_title = UIStyle.title("This run", UITokens.FONT_SUBHEAD)
	_recap.add_child(_recap_title)
	_recap_encounter = _label("")
	_recap.add_child(_recap_encounter)
	var tallies := Widgets.chip_row([])
	for id in ["slayer", "attack", "cooking"]:
		var row := UIStyle.hbox(UITokens.SP_2)
		row.add_child(_picture(AssetRegistry.skill_icon(id), Vector2(18, 18)))
		var amount := UIStyle.label("", false, UITokens.FONT_SMALL)
		_run_labels.append(amount)
		row.add_child(amount)
		tallies.add_child(row)
	_recap.add_child(tallies)
	_loot_box = UIStyle.vbox(UITokens.SP_2)
	_recap.add_child(_loot_box)
	card.hide()


func select(id: String) -> void:
	_selected = id
	refresh()


func refresh() -> void:
	var active: bool = CombatManager.state != CombatManager.State.IDLE
	var area: String = str(CombatManager.context.get("id", _selected)) if active else _selected
	var step: int = int(CombatManager.context.get("index", 0))
	var floor_index: int = int(CombatManager.context.get("floor", 0))
	var key := "%s:%s:%s:%d:%d" % [area, CombatManager.state, CombatManager.current_monster_id if active else "", step, floor_index]
	if key == _view:
		return
	_view = key
	_clear(_body)
	_hp.clear()
	_swings.clear()
	_effects.clear()
	_sprite = null
	_enemy_fx = null
	_player_fx = null
	_cue = null
	var dungeon: bool = DataLoader.dungeons.has(area)
	var encounter: Dictionary = DataLoader.get_dungeon(area) if dungeon else DataLoader.areas.get(area, {})
	var banner_body := UIStyle.vbox(UITokens.SP_3)
	var caption := _encounter_caption(encounter, area, dungeon, active, step, floor_index)
	var heading := UIStyle.hbox(UITokens.SP_3)
	if not encounter.is_empty():
		var icon := UIStyle.icon_texture("dungeons" if dungeon else "areas", area)
		icon.custom_minimum_size = Vector2(42, 42)
		heading.add_child(icon)
	var titles := UIStyle.vbox(UITokens.SP_1)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(_label(caption, UITokens.TEAL, UITokens.FONT_SMALL))
	var title := UIStyle.title(str(encounter.get("name", "Battlefield")), UITokens.SP_8)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(title)
	heading.add_child(titles)
	banner_body.add_child(heading)
	_body.add_child(_scene(area, banner_body, active))
	if active:
		_build_live(banner_body)
	else:
		_build_preview(encounter, dungeon)
	tick()


func _encounter_caption(data: Dictionary, id: String, dungeon: bool, active: bool, step: int, floor_index: int) -> String:
	if not dungeon:
		return "Region"
	var raid: bool = bool(data.get("raid", false))
	var stronghold: bool = bool(data.get("stronghold", false))
	var kind: String = "Raid" if raid else ("Stronghold" if stronghold else (
		"Expedition" if CombatManager.is_expedition(id) else "Dungeon"))
	if not active:
		return kind
	if floor_index > 0:
		return "%s · Floor %d" % [kind, floor_index]
	var stages: Array = data.get("stages", [])
	if stronghold and step >= 0 and step < stages.size():
		return "Stage %d / %d · %s" % [step + 1, stages.size(), stages[step].get("name", "Stronghold")]
	return "%s · Encounter %d / %d" % [kind, step + 1, maxi(1, data.get("monsters", []).size())]


func _scene(area: String, content: Control, active: bool) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.clip_contents = true
	frame.custom_minimum_size.y = 248 if active else 210
	frame.add_theme_stylebox_override("panel", UIStyle.flat_box("panel", true))
	var art_path := HEARTHFALL_ART if area == "farmlands" else "res://assets/combat/%s.webp" % area
	if DataLoader.dungeons.has(area):
		art_path = "res://assets/combat/dungeons/%s.webp" % area
	if ResourceLoader.exists(art_path):
		var landscape := _picture(load(art_path), Vector2.ZERO)
		landscape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(landscape)
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(0.023, 0.049, 0.079, 0.91), Color(0.023, 0.049, 0.079, 0.20)])
		var shader := GradientTexture2D.new()
		shader.gradient = gradient
		shader.width = 256
		shader.height = 4
		var shade := _picture(shader, Vector2.ZERO)
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		frame.add_child(shade)
	var margin := MarginContainer.new()
	for side in ["top", "bottom", "left", "right"]:
		margin.add_theme_constant_override("margin_" + side, UITokens.SP_4)
	margin.add_child(content)
	frame.add_child(margin)
	return frame


func _build_preview(data: Dictionary, dungeon: bool) -> void:
	if data.is_empty():
		_body.add_child(_label("Choose a region or dungeon."))
		return
	var levels: Array = data.get("level_range", [])
	var line := "Enemy levels %s–%s" % [UIStyle.fmt_exact(float(levels[0])), UIStyle.fmt_exact(float(levels[1]))] if levels.size() >= 2 else "Enemies"
	var pool: Array = data.get("monsters", [])
	var unique: Dictionary = {}
	var defeated := 0
	var drops: Dictionary = {}
	for id in pool:
		if unique.has(id):
			continue
		unique[id] = true
		if PlayerData.completion_log.get("monsters", {}).has(str(id)):
			defeated += 1
		for drop in DataLoader.get_monster(str(id)).get("loot_table", []):
			var item_id := str(drop.get("item_id", ""))
			if item_id != "" and not bool(drop.get("is_currency", false)):
				drops[item_id] = 1
	if dungeon:
		line += ("  ·  %d stages" if bool(data.get("stronghold", false)) else "  ·  %d encounters") % pool.size()
	else:
		line += "  ·  First defeats %d / %d" % [defeated, unique.size()]
	_body.add_child(_label(line, UITokens.GOLD_BRIGHT))
	var lineup := Widgets.chip_row([])
	for id in unique.keys().slice(0, 5):
		var tile := UIStyle.hbox(UITokens.SP_1)
		tile.add_child(_picture(AssetRegistry.monster_sprite(id), Vector2(30, 30)))
		var name := str(DataLoader.get_monster(id).get("name", id))
		tile.add_child(UIStyle.label(name, false, UITokens.FONT_SMALL))
		lineup.add_child(tile)
	if unique.size() > 5:
		lineup.add_child(UIStyle.label("+%d more" % (unique.size() - 5), true, UITokens.FONT_MICRO))
	_body.add_child(lineup)
	if not drops.is_empty():
		var icons := Widgets.chip_row([])
		var label := UIStyle.label("Possible loot", true, UITokens.FONT_MICRO)
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		icons.add_child(label)
		for id in drops.keys().slice(0, 8):
			var icon := UIStyle.icon_texture("items", id)
			icon.custom_minimum_size = Vector2(24, 24)
			icon.tooltip_text = str(DataLoader.get_item(id).get("name", id))
			icons.add_child(icon)
		_body.add_child(icons)


func _build_live(banner: VBoxContainer) -> void:
	var monster: Dictionary = CombatManager.current_monster()
	var enemy := str(monster.get("name", "Next enemy"))
	var display := Control.new()
	display.custom_minimum_size = Vector2(0, 132)
	banner.add_child(display)
	_sprite = _picture(AssetRegistry.monster_sprite(CombatManager.current_monster_id), Vector2.ZERO)
	_sprite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.add_child(_sprite)
	_enemy_fx = _overlay(display)
	_cue = _label("", UITokens.GOLD_BRIGHT)
	_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(_cue)

	var vitals := UIStyle.hbox(UITokens.SP_4)
	_body.add_child(vitals)
	_build_vitals(vitals, "You", AssetRegistry.skill_icon("hitpoints"), "hp")
	var style := str(monster.get("attack_type", "melee"))
	_build_vitals(vitals, enemy, AssetRegistry.skill_icon(ATTACK_ICON.get(style, "attack")), "enemy_hp")


func _build_vitals(parent: HBoxContainer, name: String, texture: Texture2D, kind: String) -> void:
	var frame := UIStyle.card()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	var body := UIStyle.vbox(UITokens.SP_2)
	frame.add_child(body)
	var row := UIStyle.hbox(UITokens.SP_2)
	row.add_child(_picture(texture, Vector2(20, 20)))
	var title := _label(name, UITokens.TEXT_STRONG)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	body.add_child(row)
	var hp := Widgets.meter(0, 1, kind, "HP", 17, false)
	body.add_child(hp)
	_hp.append(hp)
	if kind == "hp":
		_player_fx = _overlay(hp)
	var swing := Widgets.progress_bar(0, 1, UITokens.BLUE, "", 5, "Time until the next attack", false)
	body.add_child(swing)
	_swings.append(swing)
	var status := UIStyle.hbox(UITokens.SP_2)
	status.add_child(_picture(AssetRegistry.icon("status", "warning"), Vector2(15, 15)))
	var effects := _label("", UITokens.PURPLE, UITokens.FONT_MICRO)
	effects.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(effects)
	status.hide()
	body.add_child(status)
	_effects.append(effects)


func _overlay(parent: Control) -> Control:
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(overlay)
	return overlay


func tick() -> void:
	if _seen_run_revision != CombatManager.run_revision:
		_seen_run_revision = CombatManager.run_revision
		_show_recap()
	if _hp.size() != 2:
		return
	_update_hp(_hp[0], CombatManager.player_hp, CombatManager._compute_max_hp())
	_update_hp(_hp[1], CombatManager.monster_hp, CombatManager.monster_max_hp)
	_update_bar(_swings[0], CombatManager.player_attack_timer, CombatManager.player_attack_interval)
	_update_bar(_swings[1], CombatManager.monster_attack_timer, CombatManager.monster_attack_interval)
	_update_effects(_effects[0], CombatManager.player_effects)
	_update_effects(_effects[1], CombatManager.monster_effects)
	if Time.get_ticks_msec() >= _cue_until:
		var status := "Waiting for the next enemy" if CombatManager.state == CombatManager.State.RESPAWNING else "Combat in progress"
		if _cue.text != status:
			_cue.text = status


func _update_bar(bar: ProgressBar, value: float, maximum: float) -> void:
	bar.max_value = maxf(0.01, maximum)
	bar.value = clampf(value, 0.0, bar.max_value)


func _update_hp(bar: ProgressBar, hp: float, maximum: float) -> void:
	_update_bar(bar, hp, maximum)
	var caption: Label = bar.get_child(0)
	var text := "%s / %s HP" % [UIStyle.fmt(hp), UIStyle.fmt(maximum)]
	if caption.text != text:
		caption.text = text


func _update_effects(label: Label, effects: Array) -> void:
	var names: PackedStringArray = []
	for effect in effects:
		names.append("%s %ds" % [str(effect.id).replace("_", " ").capitalize(), ceili(float(effect.duration))])
	var text := " · ".join(names)
	if label.text != text:
		label.text = text
	(label.get_parent() as Control).visible = not names.is_empty()


func cue(text: String) -> void:
	if is_instance_valid(_cue):
		_cue.text = text
		_cue_until = Time.get_ticks_msec() + 1800


func hit(enemy_hit: bool, damage: int, critical := false) -> void:
	if Motion.reduced() or not is_visible_in_tree() or damage <= 0:
		return
	var overlay := _enemy_fx if enemy_hit else _player_fx
	if is_instance_valid(overlay):
		Motion.spawn_floater(overlay, "−%d" % damage,
			(UITokens.GOLD_BRIGHT if critical else UITokens.TEXT_STRONG) if enemy_hit else UITokens.RED)
	if enemy_hit and is_instance_valid(_sprite):
		_sprite.modulate = Color(1.65, 1.65, 1.65)
		_sprite.create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.09)


func _show_recap() -> void:
	var run: Dictionary = CombatManager.run_readout()
	(_recap.get_parent() as Control).visible = not run.is_empty()
	if run.is_empty():
		return
	var reason: String = run.reason
	_recap_title.text = "This run" if reason == "" else ({
		"retreat": "Run recap · Retreated", "complete": "Run recap · Cleared", "defeat": "Run recap · Defeated",
		"supplies exhausted": "Run recap · Supplies exhausted"
	}).get(reason, "Run recap · " + reason.capitalize())
	var encounter: String = str(DataLoader.areas.get(run.encounter, DataLoader.get_dungeon(run.encounter)).get("name", ""))
	_recap_encounter.visible = reason != "" and encounter != ""
	_recap_encounter.text = encounter
	var kills: int = int(run.kills)
	_run_labels[0].text = "%d %s" % [kills, "kill" if kills == 1 else "kills"]
	_run_labels[1].text = "%s XP" % UIStyle.fmt(float(run.xp))
	_run_labels[2].text = "%d food used" % int(run.food)
	var loot: Dictionary = run.loot
	if loot != _shown_loot:
		_shown_loot = loot
		_clear(_loot_box)
		if not loot.is_empty():
			_loot_box.add_child(_label("Loot collected", UITokens.GOLD_BRIGHT, UITokens.FONT_MICRO))
			_loot_box.add_child(Widgets.item_rewards(loot))


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _picture(texture: Texture2D, minimum: Vector2) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = minimum
	picture.mouse_filter = Control.MOUSE_FILTER_PASS
	return picture


func _label(text: String, color := UITokens.TEXT_MUTED, size := UITokens.FONT_SMALL) -> Label:
	var label := UIStyle.colored_label(text, color, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

