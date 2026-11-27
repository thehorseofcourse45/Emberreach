extends VBoxContainer

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

var _content: VBoxContainer
var _selected := "lantern_garden"

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(UIStyle.title("The Dream Realm", UITokens.FONT_DISPLAY))
	var intro := UIStyle.label("Explore dream regions, choose your path, and return with Lucid Fragments. Dream Essence comes from offline Dreamwalking; journeys wait for your choices when you leave.", true, UITokens.FONT_SMALL)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	_content = UIStyle.vbox(UITokens.SP_3)
	add_child(_content)
	EventBus.state_refreshed.connect(refresh)
	EventBus.skill_level_up.connect(func(_skill, _level): refresh())
	refresh()

func focus_route(route: Dictionary) -> void:
	var id := str(route.get("region_id", ""))
	if not DreamwalkingManager.realm.region(id).is_empty(): _selected = id
	refresh()

func detail_context() -> Dictionary:
	return {"kind":"text", "title":"The Dream Realm", "body":"Spend Dream Essence to enter a region. Each journey has three choices. Careful choices restore clarity and earn one fragment; bold choices cost one clarity and earn four, with a 25% chance to lose an extra clarity. Reaching zero clarity loses the unbanked fragments. Complete a region to unlock its relic and the next region. In the new regions, your first choice changes the story and return bonus. Rare discoveries grant five extra fragments when you return safely."}

func refresh() -> void:
	if _content == null: return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var realm = DreamwalkingManager.realm
	_content.add_child(Widgets.key_value("Dream Essence", UIStyle.fmt_exact(BankManager.get_count("dream_essence"))))
	_content.add_child(Widgets.key_value("Lucid Fragments", UIStyle.fmt_exact(BankManager.get_count("lucid_fragment"))))
	var open_dreamwalking := UIStyle.mini_button("Open Dreamwalking")
	open_dreamwalking.pressed.connect(func(): navigated.emit({"screen":Screens.SKILLS,"skill_id":"dreamwalking"}))
	_content.add_child(open_dreamwalking)
	if not realm.run.is_empty():
		_show_journey(realm)
	else:
		_show_regions(realm)
	_show_relics(realm)

func _show_regions(realm) -> void:
	var section := UIStyle.section("Dream regions", "Complete each region to open the next.")
	_content.add_child(section)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", UITokens.SP_2)
	buttons.add_theme_constant_override("v_separation", UITokens.SP_2)
	section.add_child(buttons)
	for entry in realm.regions():
		var choice := UIStyle.mini_button(str(entry.name))
		choice.disabled = _selected == str(entry.id)
		choice.pressed.connect(func(): _selected = str(entry.id); refresh())
		buttons.add_child(choice)
	var entry: Dictionary = realm.region(_selected)
	if entry.is_empty(): return
	var card := UIStyle.card()
	section.add_child(card)
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var header := UIStyle.hbox(UITokens.SP_3)
	var icon := UIStyle.icon_texture("dream_realm", str(entry.id))
	icon.custom_minimum_size = Vector2(64,64)
	header.add_child(icon)
	header.add_child(UIStyle.title(str(entry.name), UITokens.FONT_SUBHEAD))
	col.add_child(header)
	var description := UIStyle.label(str(entry.description), true, UITokens.FONT_SMALL)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(description)
	col.add_child(Widgets.key_value("Requirement", "Dreamwalking %d" % int(entry.level)))
	col.add_child(Widgets.key_value("Entry", "%d Dream Essence" % int(entry.cost)))
	col.add_child(Widgets.key_value("Safe return bonus", "%d Lucid Fragments" % int(entry.bonus)))
	var reason: String = realm.lock_reason(str(entry.id))
	if reason != "": col.add_child(UIStyle.colored_label("Locked — " + reason, UITokens.AMBER, UITokens.FONT_SMALL))
	var enter := UIStyle.primary_button("Enter dream" if reason == "" else reason)
	enter.disabled = reason != "" or not BankManager.has_item("dream_essence", int(entry.cost))
	enter.tooltip_text = "Requires %d Dream Essence; spent on entry." % int(entry.cost)
	enter.pressed.connect(func(): realm.start(str(entry.id)))
	col.add_child(enter)

func _show_journey(realm) -> void:
	var run: Dictionary = realm.run
	var entry: Dictionary = realm.region(str(run.region))
	var node: Dictionary = entry.nodes[int(run.step)]
	var section := UIStyle.section("Journey · %s" % str(entry.name), "Choice %d of %d" % [int(run.step)+1, entry.nodes.size()])
	_content.add_child(section)
	section.add_child(Widgets.key_value("Clarity", "%d / 3" % int(run.clarity)))
	section.add_child(Widgets.key_value("Unbanked fragments", str(int(run.fragments))))
	if bool(entry.get("branch", false)):
		var path := str(run.get("path", ""))
		if path != "": section.add_child(Widgets.key_value("Story path", "Memory (+2 on return)" if path == "safe" else "Unwritten (+4 on return)"))
		if bool(run.get("discovery", false)):
			var discovery := UIStyle.label("Rare discovery: %s (+5 fragments on return)" % str(entry.discovery), true, UITokens.FONT_SMALL)
			discovery.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			section.add_child(discovery)
	var story_text := str(node.text)
	if int(run.step) > 0 and bool(entry.get("branch", false)):
		story_text = str(node.get(str(run.get("path", "safe")) + "_text", story_text))
	var story := UIStyle.label(story_text, false, UITokens.FONT_BODY)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(story)
	var safe := UIStyle.button("%s · +1 fragment, +1 clarity%s" % [str(node.safe), "; memory path +2 on return" if bool(entry.get("branch", false)) and int(run.step) == 0 else ""])
	safe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	safe.pressed.connect(func(): realm.choose("safe"))
	section.add_child(safe)
	var bold := UIStyle.button("%s · +4 fragments, −1 clarity%s" % [str(node.bold), "; unwritten path +4 on return" if bool(entry.get("branch", false)) and int(run.step) == 0 else ""])
	bold.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bold.disabled = int(run.clarity) <= 1
	if bold.disabled: bold.tooltip_text = "At one clarity this choice would end the journey. Choose the careful path to recover."
	bold.pressed.connect(func(): realm.choose("bold"))
	section.add_child(bold)
	var warning := UIStyle.label("Bold choices have a 25% chance to cost an extra clarity. Clarity is capped at 3; reaching zero ends the journey and loses unbanked fragments. Entry Essence is spent.", true, UITokens.FONT_SMALL)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(warning)
	var abandon := UIStyle.danger_button("Abandon journey", "Lose unbanked fragments and return to the region list.")
	abandon.pressed.connect(func(): realm.abandon())
	section.add_child(abandon)

func _show_relics(realm) -> void:
	var section := UIStyle.section("Dream relics", "Complete a region to unlock its relic. Bonuses apply while equipped.")
	_content.add_child(section)
	for entry in realm.regions():
		var item: Dictionary = DataLoader.get_item(str(entry.item))
		var row := UIStyle.hbox(UITokens.SP_3)
		var icon := UIStyle.icon_texture("items", str(entry.item))
		icon.texture = AssetRegistry.item_icon(str(entry.item))
		icon.custom_minimum_size = Vector2(40,40)
		row.add_child(icon)
		var text := UIStyle.vbox(UITokens.SP_1)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(UIStyle.title(str(item.get("name", entry.item)), UITokens.FONT_BODY))
		var traits: Array[String] = []
		var labels := {"global_skill_xp_percent":"Skill XP", "dreamwalking_essence_percent":"Dream Essence", "global_mastery_xp_percent":"Mastery XP", "magic_evasion_percent":"Magic evasion", "stun_resistance_percent":"Stun resistance", "dreamwalking_depth_percent":"Dream depth", "magic_max_hit_percent":"Magic max hit", "rune_preservation_percent":"Rune preservation"}
		for key in item.get("passive_modifiers", {}): traits.append("+%s%% %s" % [UIStyle.fmt_exact(float(item.passive_modifiers[key])), labels.get(key, str(key).replace("_", " "))])
		var note := UIStyle.label(", ".join(traits), true, UITokens.FONT_SMALL)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(note)
		row.add_child(text)
		section.add_child(row)
		var buy := UIStyle.button("Exchange %d fragments" % int(entry.price) if realm.completed.has(str(entry.id)) else "Complete %s to unlock" % str(entry.name))
		buy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		buy.disabled = not realm.completed.has(str(entry.id)) or not BankManager.has_item("lucid_fragment", int(entry.price))
		buy.pressed.connect(func(): realm.purchase(str(entry.id)))
		section.add_child(buy)
