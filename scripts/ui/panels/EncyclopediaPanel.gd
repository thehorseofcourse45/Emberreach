extends VBoxContainer
## A practical guide backed by the live content catalogue.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

const CATEGORIES: Array[String] = ["Skills", "Activities", "Items", "Monsters", "Regions", "Expeditions", "Tasks", "Milestones", "Prayers", "Pets", "Familiars", "Town buildings", "Upgrades", "Constellations", "Obstacles", "Archaeology", "Caravan routes", "Factions", "Special attacks", "Abilities", "Game modes", "Deities", "Settlement specializations", "Animals", "Devices", "Enchantments", "Dreams", "Dream Realm", "Caravan wagons", "Caravan guards", "World map"]
const GUIDE_GROUPS: Array[String] = ["All topics", "Getting started", "Combat", "Planning", "Progression", "Passive systems", "Arcane", "Skills", "Using this guide"]
const PAGE_SIZE: int = 20
var _category: OptionButton
var _guide_group: OptionButton
var _search: LineEdit
var _list: VBoxContainer
var _page: int = 0
var _mode: String = "home"
var _article_id: String = ""
var _reference_skill_id: String = ""
var _articles: Array = []
var _skill_tips: Dictionary = {}
var _tabs: HFlowContainer

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(UIStyle.title("Encyclopedia & Tutorial", UITokens.FONT_DISPLAY))
	var intro := UIStyle.label("Learn the basics, look up a system, or search the game reference.", true, UITokens.FONT_SMALL)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", UITokens.SP_3)
	_tabs.add_theme_constant_override("v_separation", UITokens.SP_2)
	add_child(_tabs)
	for tab in [["Home", "home"], ["First steps", "tutorial"], ["Guides", "guides"], ["Reference", "reference"]]:
		var mode: String = tab[1]
		var button := UIStyle.button(str(tab[0]))
		button.pressed.connect(func(): _set_mode(mode))
		_tabs.add_child(button)
	_guide_group = Widgets.option_menu(GUIDE_GROUPS, func(_i): _page = 0; _rebuild(), 0)
	_guide_group.tooltip_text = "Filter guides by topic"
	add_child(_guide_group)
	_category = Widgets.option_menu(CATEGORIES, func(_i): _page = 0; _rebuild(), 0)
	_category.tooltip_text = "Choose a reference category"
	add_child(_category)
	_search = Widgets.search_bar("Search guides, names and IDs", func(_text): _page = 0; _rebuild())
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_search)
	_list = UIStyle.vbox(UITokens.SP_3)
	add_child(_list)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/guide_articles.json"))
	_articles = parsed if parsed is Array else []
	var tips: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/skill_guide_tips.json"))
	_skill_tips = tips if tips is Dictionary else {}
	_rebuild()

func focus_route(route: Dictionary) -> void:
	var section: String = str(route.get("section", ""))
	if section in ["home", "tutorial", "guides", "reference"]:
		_set_mode(section)
	else:
		_rebuild()

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Encyclopedia", "body": "Use First steps for guided objectives, Guides for explanations, and Reference to look up game content."}

func _set_mode(mode: String) -> void:
	_mode = mode
	_article_id = ""
	_reference_skill_id = ""
	_page = 0
	_search.text = ""
	_rebuild()

func _open_article(id: String) -> void:
	_mode = "guides"
	_article_id = id
	_rebuild()

func _rebuild() -> void:
	if _list == null: return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_category.visible = _mode == "reference"
	_guide_group.visible = _mode == "guides" and _article_id == ""
	_search.visible = _mode in ["guides", "reference"] and _article_id == ""
	if _mode == "home":
		_show_home()
	elif _mode == "tutorial":
		_show_tutorial()
	elif _mode == "guides":
		if _article_id == "": _show_guides()
		else: _show_article(_article_id)
	else:
		_show_reference()

func _paragraph(parent: Node, value: String) -> void:
	var label := UIStyle.label(value, true, UITokens.FONT_SMALL)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func _link(parent: Node, text: String, handler: Callable) -> void:
	var button := UIStyle.button(text)
	button.pressed.connect(handler)
	parent.add_child(button)

func _show_home() -> void:
	var start := UIStyle.section("Where would you like to start?", "Choose a path; your progress is kept automatically.")
	_list.add_child(start)
	_paragraph(start, "New to Emberreach? Follow the first steps for specific objectives, or read Your first hour for a complete walkthrough. Experienced players can browse the guides and live reference.")
	var links := HFlowContainer.new()
	links.add_theme_constant_override("h_separation", UITokens.SP_3)
	links.add_theme_constant_override("v_separation", UITokens.SP_2)
	start.add_child(links)
	_link(links, "Continue first steps", func(): _set_mode("tutorial"))
	_link(links, "Read your first hour", func(): _open_article("first_hour"))
	_link(links, "Browse all guides", func(): _set_mode("guides"))
	_link(links, "Search the reference", func(): _set_mode("reference"))
	var useful := UIStyle.section("Popular questions", "Short explanations with links to the relevant screens.")
	_list.add_child(useful)
	for article_id in ["activities", "combat", "materials", "goals", "offline", "combat_content"]:
		var article := _find_article(article_id)
		if article.is_empty(): continue
		var id: String = article_id
		_link(useful, str(article.title), func(): _open_article(id))
		_paragraph(useful, str(article.summary))

func _all_guides() -> Array:
	var out: Array = _articles.duplicate()
	for sid in DataLoader.get_skill_ids():
		var skill: Dictionary = DataLoader.get_skill(str(sid))
		out.append({"id": "skill:" + str(sid), "title": str(skill.get("name", sid)), "group": "Skills", "summary": str(skill.get("description", "")), "sections": [str(_skill_tips.get(str(sid), ""))]})
	return out

func _find_article(id: String) -> Dictionary:
	for article in _articles:
		if article is Dictionary and str(article.get("id", "")) == id: return article
	return {}

func _show_guides() -> void:
	_list.add_child(UIStyle.section("Guides", "Choose a topic or search for the system you want to understand."))
	var query := _search.text.strip_edges().to_lower().replace("_", " ")
	var group: String = GUIDE_GROUPS[_guide_group.selected]
	var rows: Array = []
	for article in _all_guides():
		if group != "All topics" and str(article.get("group", "")) != group: continue
		var haystack: String = (str(article.get("title", "")) + " " + str(article.get("summary", "")) + " " + str(article.get("sections", []))).to_lower().replace("_", " ")
		if query != "" and not haystack.contains(query): continue
		rows.append(article)
	rows.sort_custom(func(a, b): return str(a.title).to_lower() < str(b.title).to_lower())
	_paginate(rows.size())
	for article in rows.slice(_page * PAGE_SIZE, mini(rows.size(), (_page + 1) * PAGE_SIZE)):
		var card := UIStyle.card()
		var col := UIStyle.vbox(UITokens.SP_2)
		card.add_child(col)
		_list.add_child(card)
		col.add_child(UIStyle.title(str(article.title), UITokens.FONT_SUBHEAD))
		_paragraph(col, str(article.summary))
		var id: String = str(article.id)
		_link(col, "Read guide", func(): _open_article(id))
	if rows.is_empty(): _paragraph(_list, "No guides match. Try another phrase or choose All topics.")

func _show_article(id: String) -> void:
	_link(_list, "← Back to guides", func(): _article_id = ""; _rebuild())
	if id.begins_with("skill:"):
		_show_skill_guide(id.trim_prefix("skill:"))
		return
	var article := _find_article(id)
	if article.is_empty():
		_paragraph(_list, "This guide could not be found.")
		return
	_list.add_child(UIStyle.title(str(article.title), UITokens.FONT_DISPLAY))
	_paragraph(_list, str(article.summary))
	for section in article.get("sections", []):
		if not section is Array or section.size() < 2: continue
		var box := UIStyle.section(str(section[0]))
		_list.add_child(box)
		_paragraph(box, str(section[1]))
	var route: Dictionary = article.get("route", {})
	if not route.is_empty(): _link(_list, str(article.get("route_label", "Open screen")), func(): navigated.emit(route))

func _show_skill_guide(id: String) -> void:
	var skill: Dictionary = DataLoader.get_skill(id)
	if skill.is_empty():
		_paragraph(_list, "This skill is unavailable.")
		return
	_list.add_child(UIStyle.title(str(skill.get("name", id)), UITokens.FONT_DISPLAY))
	_paragraph(_list, str(skill.get("description", "")))
	var box := UIStyle.section("How to use this skill")
	_list.add_child(box)
	var tip: String = str(_skill_tips.get(id, ""))
	if tip != "": _paragraph(box, tip)
	var actions: Array = DataLoader.get_skill_actions(id)
	if not actions.is_empty():
		_paragraph(box, "Open this skill, select an unlocked activity and read its requirements, materials, rewards and estimated rates. Press Start to train it; activity mastery and skill level are tracked separately.")
		var first: Dictionary = actions[0]
		_paragraph(box, "Example activity: %s (level %d). Open its details to see its inputs, outputs and requirements." % [str(first.get("name", first.get("id", ""))), int(first.get("level_required", 1))])
		var example_id: String = str(first.get("id", ""))
		_link(box, "Inspect example activity", func(): context_changed.emit({"kind": "recipe", "skill_id": id, "action_id": example_id}))
		_link(box, "Browse activities for this skill", func():
			_mode = "reference"
			_article_id = ""
			_reference_skill_id = id
			_category.select(CATEGORIES.find("Activities"))
			_search.text = ""
			_page = 0
			_rebuild())
	else:
		_paragraph(box, "Open the skill or its associated system to see its own controls and requirements. Some skills advance through combat, passive production or their dedicated panel rather than a standard activity list.")
	var status := UIStyle.section("Your progress")
	_list.add_child(status)
	_paragraph(status, "Current level: %d · Listed activities: %d" % [PlayerData.get_level(id), actions.size()])
	var route: Dictionary = {"screen": "skills", "skill_id": id}
	if id in ["attack", "strength", "defence", "hitpoints", "ranged", "magic", "slayer"]:
		route = {"screen": "combat"}
	_link(_list, "Open " + str(skill.get("name", id)), func(): navigated.emit(route))

func _paginate(count: int) -> void:
	var pages: int = maxi(1, ceili(float(count) / PAGE_SIZE))
	_page = clampi(_page, 0, pages - 1)
	_list.add_child(UIStyle.label("%d results · page %d of %d" % [count, _page + 1, pages], true, UITokens.FONT_SMALL))
	if pages <= 1: return
	var controls := HFlowContainer.new()
	_list.add_child(controls)
	var previous := UIStyle.mini_button("Previous")
	previous.disabled = _page == 0
	previous.pressed.connect(func(): _page -= 1; _rebuild())
	controls.add_child(previous)
	var next := UIStyle.mini_button("Next")
	next.disabled = _page + 1 >= pages
	next.pressed.connect(func(): _page += 1; _rebuild())
	controls.add_child(next)

func _show_reference() -> void:
	var category: String = CATEGORIES[_category.selected]
	if category != "Activities": _reference_skill_id = ""
	var rows: Array = _records(category)
	if _reference_skill_id != "":
		rows = rows.filter(func(row): return str(row.get("skill_id", "")) == _reference_skill_id)
		_paragraph(_list, "Activities for %s" % str(DataLoader.get_skill(_reference_skill_id).get("name", _reference_skill_id)))
		_link(_list, "Show activities from all skills", func(): _reference_skill_id = ""; _page = 0; _rebuild())
	var query: String = _search.text.strip_edges().to_lower().replace("_", " ")
	if query != "":
		rows = rows.filter(func(row): return (str(row.name) + " " + str(row.id)).to_lower().replace("_", " ").contains(query))
	for row in rows: row["sort_name"] = str(row.name).to_lower()
	rows.sort_custom(func(a, b): return str(a.sort_name) < str(b.sort_name))
	_paginate(rows.size())
	for row in rows.slice(_page * PAGE_SIZE, mini(rows.size(), (_page + 1) * PAGE_SIZE)):
		_add_record(row)
	if rows.is_empty(): _paragraph(_list, "No matching entries in this category. Try a different name or category.")


func _records(category: String) -> Array:
	var rows: Array = []
	if category == "Activities":
		for skill_id in DataLoader.get_skill_ids():
			for action in DataLoader.get_skill_actions(skill_id):
				if action is Dictionary:
					rows.append({"id": str(action.get("id", "")), "name": str(action.get("name", action.get("id", ""))), "skill_id": skill_id, "data": action, "category": category})
		return rows
	var data: Dictionary = {}
	match category:
		"Skills": data = DataLoader.skills
		"Items": data = DataLoader.items
		"Monsters": data = DataLoader.monsters
		"Regions": data = DataLoader.areas
		"Expeditions": data = DataLoader.dungeons
		"Prayers": data = DataLoader.prayers
		"Pets": data = DataLoader.pets
		"Familiars": data = DataLoader.familiars
		"Town buildings": data = DataLoader.township_buildings
		"Upgrades": data = DataLoader.shop
		"Constellations": data = DataLoader.constellations
		"Obstacles": data = DataLoader.obstacles
		"Archaeology": data = DataLoader.archaeology_sites
		"Special attacks": data = DataLoader.special_attacks
		"Abilities": data = DataLoader.abilities
		"Game modes": data = DataLoader.game_modes
		"Deities": data = DataLoader.worship
		"Settlement specializations": data = DataLoader.settlement_specializations
		"World map": data = DataLoader.cartography_hexes
		"Factions":
			for id in FactionManager.all_faction_ids(): data[id] = FactionManager.get_faction(id)
		"Dream Realm":
			for dream_region in DreamwalkingManager.realm.regions(): data[str(dream_region.id)] = dream_region
		"Animals", "Devices", "Enchantments", "Dreams", "Caravan wagons", "Caravan guards":
			var group: Dictionary = {"Animals": "species", "Devices": "devices", "Enchantments": "enchants", "Dreams": "dreams", "Caravan wagons": "caravan_wagons", "Caravan guards": "caravan_guards"}
			for record in DataLoader.new_skill_systems.get(group[category], []):
				if record is Dictionary: data[str(record.get("id", record.get("stock", "")))] = record
		"Tasks":
			for id in Quests.all_quest_ids(): data[id] = Quests.get_quest(id)
		"Milestones":
			for id in Achievements.all_ids(): data[id] = Achievements.get_record(id)
		"Caravan routes":
			for route in CaravaneeringManager.routes(): data[str(route.get("id", ""))] = route
	for id in data:
		if data[id] is Dictionary:
			var record: Dictionary = data[id]
			rows.append({"id": str(id), "name": str(record.get("name", id)), "data": record, "category": category})
	return rows

func _add_record(entry: Dictionary) -> void:
	var card := UIStyle.card()
	_list.add_child(card)
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var title := UIStyle.title(str(entry.name), UITokens.FONT_SUBHEAD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var info: String = _describe(entry)
	var description := UIStyle.label(info, true, UITokens.FONT_SMALL)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(description)
	var inspect := UIStyle.mini_button("Details")
	inspect.pressed.connect(func(): _inspect(entry, info))
	col.add_child(inspect)
	if str(entry.category) == "Monsters":
		var monster_id: String = str(entry.id)
		_link(col, "Find encounter", func(): navigated.emit(Goals._route_for_monster(monster_id)))

func _describe(entry: Dictionary) -> String:
	var data: Dictionary = entry.data
	var lines: Array[String] = []
	var flavour: String = str(data.get("description", data.get("flavour", "")))
	if flavour != "": lines.append(flavour)
	if entry.category == "Activities":
		lines.append("%s · level %d · %.1f seconds" % [DataLoader.get_skill(str(entry.skill_id)).get("name", entry.skill_id), int(data.get("level_required", 1)), float(data.get("base_interval", 0.0))])
		if not (data.get("input_items", {}) as Dictionary).is_empty(): lines.append("Consumes: " + Goals._input_summary(data.input_items))
		if not (data.get("output_items", {}) as Dictionary).is_empty(): lines.append("Produces: " + Goals._input_summary(data.output_items))
		if data.has("success_chance"): lines.append("Base success chance: %.0f%%" % (float(data.success_chance) * 100.0))
	if entry.category == "Monsters":
		lines.append("Combat %s · HP %d · max hit %d · %s" % [UIStyle.fmt_exact(float(data.get("combat_level", 0))), int(data.get("hitpoints", 0)), int(data.get("max_hit", 0)), str(data.get("attack_type", ""))])
		var drops: Array[String] = []
		for drop in data.get("loot_table", []):
			if drop is Dictionary and drop.has("item_id"): drops.append("%s (%.1f%%)" % [str(DataLoader.get_item(str(drop.item_id)).get("name", drop.item_id)), float(drop.get("chance", 1.0)) * 100.0])
		if not drops.is_empty(): lines.append("Possible drops: " + ", ".join(drops))
	if entry.category in ["Regions", "Expeditions"]:
		var counts: Dictionary = {}
		for id in data.get("monsters", []): counts[str(id)] = int(counts.get(str(id), 0)) + 1
		var enemies: Array[String] = []
		for id in counts:
			var label: String = str(DataLoader.get_monster(str(id)).get("name", id))
			if int(counts[id]) > 1: label += " ×%d" % int(counts[id])
			enemies.append(label)
		if not enemies.is_empty(): lines.append("Enemies: " + ", ".join(enemies))
	if entry.category == "Prayers": lines.append("Prayer level %d · %s points per action" % [int(data.get("level", 1)), str(data.get("prayer_point_cost", 0))])
	if entry.category == "Caravan routes": lines.append("Caravaneering level %d · %.1f hours · risk %s" % [int(data.get("level", 1)), float(data.get("hours", 0.0)), str(data.get("risk", 0))])
	if entry.category == "Items":
		lines.append("Type: " + str(data.get("item_type", "item")).capitalize())
		if data.has("heal_amount"): lines.append("Restores %s health" % str(data.heal_amount))
		if data.has("sell_price"): lines.append("Sell value: %s GP" % UIStyle.fmt(float(data.sell_price)))
		if data.has("attack_speed"): lines.append("Attack interval: %.1f seconds" % float(data.attack_speed))
		for field in ["equipment_stats", "level_requirements"]:
			var values: Dictionary = data.get(field, {})
			var parts: Array[String] = []
			for key in values: parts.append("%s %s" % [str(key).replace("_", " ").capitalize(), str(values[key])])
			if not parts.is_empty(): lines.append(("Equipment bonuses: " if field == "equipment_stats" else "Requirements: ") + ", ".join(parts))
	if entry.category == "Dream Realm": lines.append("Entry: %d Dream Essence · relic: %s (%d Lucid Fragments). Three choices; bold choices have a 25%% chance to cost extra clarity. Reaching zero clarity loses unbanked fragments." % [int(data.cost), str(DataLoader.get_item(str(data.item)).get("name", data.item)), int(data.price)])
	if entry.category == "Skills": lines.append("%d activities · current level %d" % [DataLoader.get_action_count(str(entry.id)), PlayerData.get_level(str(entry.id))])
	if data.has("level_required") and entry.category != "Activities": lines.append("Level required: " + str(data.level_required))
	if data.has("level") and entry.category not in ["Prayers", "Caravan routes"]: lines.append("Level: " + str(data.level))
	for key in ["price", "capacity", "wage", "power", "fuel_cost", "xp_hour", "essence_hour"]:
		if data.has(key): lines.append("%s: %s" % [key.replace("_", " ").capitalize(), str(data[key])])
	for key in ["effect", "mods", "modifiers", "requires", "requirements", "cost"]:
		var value: Variant = data.get(key, null)
		if value is Dictionary and not (value as Dictionary).is_empty():
			var parts: Array[String] = []
			for stat in value:
				if value[stat] is float or value[stat] is int or value[stat] is String:
					parts.append("%s: %s" % [str(stat).replace("_", " ").capitalize(), str(value[stat])])
			if not parts.is_empty(): lines.append(key.capitalize() + ": " + ", ".join(parts))
	if lines.is_empty(): lines.append("Select Details for more information.")
	return "\n".join(lines)

func _inspect(entry: Dictionary, info: String) -> void:
	match str(entry.category):
		"Items": context_changed.emit({"kind": "item", "item_id": entry.id})
		"Activities": context_changed.emit({"kind": "recipe", "skill_id": entry.skill_id, "action_id": entry.id})
		"Regions", "Expeditions": context_changed.emit({"kind": "region", "area_id": entry.id})
		"Tasks": context_changed.emit({"kind": "goal", "goal": {"kind": "quest", "id": entry.id}})
		"Skills": _open_article("skill:" + str(entry.id))
		"Dream Realm": navigated.emit({"screen": "dream_realm", "region_id": entry.id})
		_: context_changed.emit({"kind": "text", "title": entry.name, "body": info})


func _show_tutorial() -> void:
	_list.add_child(UIStyle.section("First steps", "These objectives advance automatically as you play. Revisit any step without resetting progress."))
	var total: int = TutorialManager.step_count()
	var progress: int = clampi(PlayerData.tutorial_step, 0, total)
	_paragraph(_list, "%d of %d steps completed" % [progress, total])
	_link(_list, "Read the first-hour walkthrough", func(): _open_article("first_hour"))
	for i in range(total):
		var step: Dictionary = TutorialManager.describe(i)
		if step.is_empty(): continue
		var done: bool = i < progress
		var current: bool = i == progress and not TutorialManager.is_finished()
		var status: String = "Completed" if done else ("Current objective" if current else "Coming up")
		var card := UIStyle.card(current)
		_list.add_child(card)
		var col := UIStyle.vbox(UITokens.SP_2)
		card.add_child(col)
		var title := UIStyle.title("%d. %s · %s" % [i + 1, str(step.title), status], UITokens.FONT_SUBHEAD)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(title)
		_paragraph(col, str(step.body))
		var condition: Dictionary = step.get("condition", {})
		if not done and not condition.is_empty():
			_paragraph(col, "%s: %s / %s" % [str(condition.get("label", "Progress")), UIStyle.fmt(float(condition.get("current", 0))), UIStyle.fmt(float(condition.get("required", 1)))])
		var route: Dictionary = step.get("route", {})
		if not route.is_empty(): _link(col, "Take me there", func(): navigated.emit(route))
