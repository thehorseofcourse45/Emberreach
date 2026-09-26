extends RefCounted
## SidebarNav — the left sidebar and its narrow-layout navigation drawer.
## Deliberately no class_name: MainUI loads it via preload, which keeps the
## global class table untouched and headless runs deterministic.
##
## Extracted from MainUI: every button routes through the host shell
## (`host.call("_show_screen", target, {})` / `host.call("navigate", route)`),
## so MainUI owns screens, badges and highlighting while this file owns layout.
## MainUI keeps the returned nodes and button dicts (the tests read them off
## the shell: `_sidebar_list`, `_nav_buttons`, `_skill_nav_buttons`).
## A null drawer means "sidebar mode" (register buttons); a drawer node means
## "drawer mode" (hide the drawer on press, skip registration).

## Pinned to the top of the sidebar (and drawer), in order.
const PINNED_SCREENS: Array[String] = [Screens.STORE, Screens.PROVISIONER, Screens.COMBAT, Screens.EQUIPMENT]

## Build the sidebar column into `sidebar_wrap` and the hidden drawer into
## `host`. Returns {list, scroll, drawer, nav_button, nav_buttons, skill_buttons}.
static func build(host: Control, sidebar_wrap: PanelContainer) -> Dictionary:
	var col := UIStyle.vbox(UITokens.SP_4)
	sidebar_wrap.add_child(col)
	var brand := UIStyle.vbox(UITokens.SP_1)
	brand.add_child(UIStyle.title("EMBERREACH", UITokens.FONT_SUBHEAD))
	brand.add_child(UIStyle.label("The Riven Frontier", true, UITokens.FONT_MICRO))
	col.add_child(brand)
	col.add_child(HSeparator.new())

	var scroll := UIStyle.scroll()
	col.add_child(scroll)
	var nav_buttons: Dictionary = {}
	var skill_buttons: Dictionary = {}
	var list := UIStyle.vbox(UITokens.SP_2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_add_pinned_nav(host, list, nav_buttons, null)
	list.add_child(HSeparator.new())
	_add_skill_links(host, list, nav_buttons, skill_buttons, null)
	list.add_child(HSeparator.new())
	_add_settlement_nav(host, list, nav_buttons, null)
	list.add_child(HSeparator.new())
	list.add_child(UIStyle.label("GAME", true, UITokens.FONT_MICRO))

	for screen in Screens.ORDER:
		if screen == Screens.SKILLS or screen in PINNED_SCREENS or screen == Screens.SETTLEMENT:
			continue
		var b := Button.new()
		b.text = Screens.label_for(screen)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, UITokens.H_HEADER)
		b.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
		b.icon = AssetRegistry.icon(_icon_kind_for(screen), _icon_id_for(screen))
		b.add_theme_constant_override("icon_max_width", UITokens.ICON_SM)
		b.tooltip_text = Screens.label_for(screen)
		var target: String = screen
		b.pressed.connect(func(): host.call("_show_screen", target, {}))
		list.add_child(b)
		nav_buttons[screen] = b

	col.add_child(HSeparator.new())
	var nav_button := UIStyle.button("Navigation", "Open navigation")
	nav_button.visible = false
	col.add_child(nav_button)

	var drawer := PanelContainer.new()
	drawer.visible = false
	drawer.add_theme_stylebox_override("panel", UIStyle.surface_box("panel"))
	drawer.set_anchors_preset(Control.PRESET_TOP_LEFT)
	drawer.offset_left = UITokens.SP_5
	drawer.offset_top = 96
	drawer.anchor_bottom = 1.0
	drawer.offset_bottom = -UITokens.H_HEADER - UITokens.SP_7
	drawer.custom_minimum_size = Vector2(220, 0)
	host.add_child(drawer)
	nav_button.pressed.connect(func(): toggle_drawer(host, drawer))
	return {"list": list, "scroll": scroll, "drawer": drawer, "nav_button": nav_button,
		"nav_buttons": nav_buttons, "skill_buttons": skill_buttons}

static func toggle_drawer(host: Control, drawer: PanelContainer) -> void:
	drawer.visible = not drawer.visible
	if drawer.visible:
		populate_drawer(host, drawer)

static func populate_drawer(host: Control, drawer: PanelContainer) -> void:
	for c in drawer.get_children():
		drawer.remove_child(c)
		c.queue_free()
	var scroll := UIStyle.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drawer.add_child(scroll)
	var col := UIStyle.vbox(UITokens.SP_2)
	col.custom_minimum_size = Vector2(190, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	col.add_child(UIStyle.title("Navigate", UITokens.FONT_SUBHEAD))
	_add_pinned_nav(host, col, {}, drawer)
	col.add_child(HSeparator.new())
	_add_skill_links(host, col, {}, {}, drawer)
	col.add_child(HSeparator.new())
	_add_settlement_nav(host, col, {}, drawer)
	col.add_child(HSeparator.new())
	col.add_child(UIStyle.label("GAME", true, UITokens.FONT_MICRO))
	for screen in Screens.ORDER:
		if screen == Screens.SKILLS or screen in PINNED_SCREENS or screen == Screens.SETTLEMENT:
			continue
		var b := UIStyle.button(Screens.label_for(screen))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var target: String = screen
		b.pressed.connect(func():
			drawer.visible = false
			host.call("_show_screen", target, {}))
		col.add_child(b)

static func _add_pinned_nav(host: Control, container: VBoxContainer, nav_buttons: Dictionary, drawer: PanelContainer = null) -> void:
	for screen in PINNED_SCREENS:
		var b := Button.new()
		b.text = Screens.label_for(screen)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, UITokens.H_HEADER)
		b.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
		b.icon = AssetRegistry.icon(_icon_kind_for(screen), _icon_id_for(screen))
		b.add_theme_constant_override("icon_max_width", UITokens.ICON_SM)
		b.tooltip_text = Screens.label_for(screen)
		var target: String = screen
		b.pressed.connect(func():
			if drawer != null:
				drawer.visible = false
			host.call("_show_screen", target, {}))
		container.add_child(b)
		if drawer == null:
			nav_buttons[screen] = b

static func _add_settlement_nav(host: Control, container: VBoxContainer, nav_buttons: Dictionary, drawer: PanelContainer = null) -> void:
	container.add_child(UIStyle.label("SETTLEMENT", true, UITokens.FONT_MICRO))
	var b := Button.new()
	b.text = Screens.label_for(Screens.SETTLEMENT)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, UITokens.H_HEADER)
	b.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
	b.icon = AssetRegistry.icon(_icon_kind_for(Screens.SETTLEMENT), _icon_id_for(Screens.SETTLEMENT))
	b.add_theme_constant_override("icon_max_width", UITokens.ICON_SM)
	b.tooltip_text = Screens.label_for(Screens.SETTLEMENT)
	b.pressed.connect(func():
		if drawer != null:
			drawer.visible = false
		host.call("_show_screen", Screens.SETTLEMENT, {}))
	container.add_child(b)
	if drawer == null:
		nav_buttons[Screens.SETTLEMENT] = b

static func _add_skill_links(host: Control, container: VBoxContainer, nav_buttons: Dictionary, skill_buttons: Dictionary, drawer: PanelContainer = null) -> void:
	for category in ["combat", "non_combat"]:
		container.add_child(UIStyle.label("COMBAT SKILLS" if category == "combat" else "NON-COMBAT SKILLS",
			true, UITokens.FONT_MICRO))
		for skill_id in DataLoader.get_skill_ids():
			var skill: Dictionary = DataLoader.get_skill(skill_id)
			if str(skill.get("category", "")) != category:
				continue
			var button := Button.new()
			button.text = str(skill.get("name", skill_id))
			button.icon = AssetRegistry.skill_icon(skill_id)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.clip_text = true
			button.custom_minimum_size = Vector2(0, 30)
			button.add_theme_font_size_override("font_size", UITokens.FONT_SMALL)
			button.add_theme_constant_override("icon_max_width", UITokens.ICON_SM)
			button.tooltip_text = "%s · Level %d" % [button.text, PlayerData.get_level(skill_id)]
			var target_skill: String = skill_id
			button.pressed.connect(func():
				if drawer != null:
					drawer.visible = false
				host.call("navigate", {"screen": Screens.SKILLS, "skill_id": target_skill}))
			container.add_child(button)
			if drawer == null:
				skill_buttons[skill_id] = button

static func _icon_kind_for(screen: String) -> String:
	match screen:
		Screens.COMBAT: return "areas"
		Screens.EXPEDITIONS: return "dungeons"
		Screens.BANK, Screens.COLLECTION: return "items"
		Screens.QUESTS, Screens.PROVISIONER: return "currencies"
		# Gold for materials is the whole point of the store, but Tasks already owns the coin
		# icon: a second identical glyph in the sidebar would read as a duplicate, not a counter.
		Screens.STORE: return "items"
		Screens.EQUIPMENT: return "items"
		Screens.ACHIEVEMENTS: return "pets"
		Screens.SETTLEMENT: return "obstacles"
		Screens.SKILLS, Screens.OVERVIEW: return "skills"
	return "status"

static func _icon_id_for(screen: String) -> String:
	match screen:
		Screens.COMBAT: return "farmlands"
		Screens.EXPEDITIONS: return "air_god_dungeon"
		Screens.SKILLS: return "woodcutting"
		Screens.OVERVIEW: return "mining"
		Screens.QUESTS: return "gp"
		Screens.BANK: return "normal_log"
		Screens.COLLECTION: return "bones"
		Screens.SETTLEMENT: return "obstacle_1_0"
		Screens.ACHIEVEMENTS: return "pyro"
		Screens.PROVISIONER: return "slayer_coins"
		Screens.STORE: return "iron_bar"
		Screens.EQUIPMENT: return "iron_platebody"
	return "idle"
