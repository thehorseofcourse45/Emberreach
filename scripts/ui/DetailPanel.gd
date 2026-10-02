extends VBoxContainer
class_name DetailPanel
## DetailPanel — the contextual pane on the right (desktop) or under the workspace (narrow).
##
## It answers the questions every screen must answer, for whatever the player last touched:
##   What do I need? · What am I missing? · Where do I get it? · What unlocks it? · Why bother?
##
## It renders three shapes:
##   * a resolved GOAL     (requirements, missing materials, prerequisite recipes, sources, routes)
##   * an ITEM             (stats, acquisition sources, recipes that use it, goal pinning)
##   * a RECIPE / ACTIVITY (materials, outputs, projections, modifiers that apply)
##
## Every "Route" produced here is a real navigation entry (Screens.go), so the panel never
## presents advice it cannot take the player to.

signal navigated(route: Dictionary)

var _title: Label
var _subtitle: Label
var _body: VBoxContainer
var _pin_button: Button
var _current_kind: String = ""
var _current_payload: Variant = null

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_4)
	_title = UIStyle.title("Details", UITokens.FONT_SUBHEAD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)
	_subtitle = UIStyle.label("Select anything to see its details here.", true, UITokens.FONT_MICRO)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_subtitle)
	var pin_row := HBoxContainer.new()
	_pin_button = UIStyle.mini_button("Track this goal", "Pin so the overview explains what it needs")
	_pin_button.pressed.connect(_on_pin)
	_pin_button.visible = false
	pin_row.add_child(_pin_button)
	add_child(pin_row)
	add_child(HSeparator.new())
	var scroll := UIStyle.scroll()
	add_child(scroll)
	_body = UIStyle.vbox(UITokens.SP_4)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	EventBus.goal_changed.connect(_refresh_if_goal)
	EventBus.bank_changed.connect(_refresh_if_goal)
	EventBus.skill_level_up.connect(func(_s, _l): _refresh_if_goal())
	EventBus.state_refreshed.connect(_refresh_if_goal)

## The panel is told which screen is showing; screens may also push richer context.
func set_context(panel: Control, route: Dictionary) -> void:
	if route.has("item_id") or str(route.get("screen", "")) == Screens.BANK:
		show_item(str(route.get("item_id", "")))
		return
	if route.has("quest_id"):
		show_goal({"kind": "quest", "id": str(route["quest_id"])})
		return
	if route.has("area_id"):
		show_region(str(route["area_id"]))
		return
	if panel != null and panel.has_method("detail_context"):
		var context: Variant = panel.call("detail_context")
		if typeof(context) == TYPE_DICTIONARY and not (context as Dictionary).is_empty():
			set_inline_context(context)
			return
	show_screen_help(str(route.get("screen", "")))

## Screens push their own context dictionary when the player selects something.
func set_inline_context(ctx: Variant) -> void:
	if typeof(ctx) != TYPE_DICTIONARY or (ctx as Dictionary).is_empty():
		return
	var d: Dictionary = ctx
	match str(d.get("kind", "")):
		"goal": show_goal(d.get("goal", {}))
		"item": show_item(str(d.get("item_id", "")))
		"recipe": show_recipe(str(d.get("skill_id", "")), str(d.get("action_id", "")))
		"region": show_region(str(d.get("area_id", "")))
		"text":
			_render_text(str(d.get("title", "Details")), str(d.get("body", "")))

# =========================================================================
#  Renderers
# =========================================================================

func show_goal(goal: Dictionary) -> void:
	if goal.is_empty():
		return
	_current_kind = "goal"
	_current_payload = goal
	var resolved: Dictionary = Goals.resolve(goal)
	_clear()
	if not bool(resolved.get("ok", false)):
		_title.text = "Unavailable"
		_subtitle.text = str(resolved.get("problem", "That goal could not be resolved."))
		return
	_title.text = str(resolved.get("label", "Goal"))
	_subtitle.text = "%s goal  ·  %s" % [str(resolved.get("kind", "")).capitalize(),
		"complete" if bool(resolved.get("complete", false)) else "in progress"]
	_pin_button.visible = true
	_pin_button.text = "Untrack" if Goals.is_pinned(str(goal["kind"]), str(goal["id"])) else "Track this goal"

	if str(resolved.get("description", "")) != "":
		var desc := UIStyle.label(str(resolved["description"]), true, UITokens.FONT_SMALL)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(desc)

	_body.add_child(Widgets.progress_bar(float(resolved.get("progress_current", 0)),
		maxf(1.0, float(resolved.get("progress_required", 1))),
		UITokens.GOLD if bool(resolved.get("complete", false)) else UITokens.TEAL,
		"%s / %s" % [UIStyle.fmt(float(resolved.get("progress_current", 0))),
			UIStyle.fmt(float(resolved.get("progress_required", 1)))], 16))

	if resolved.has("reward_description"):
		_body.add_child(Widgets.key_value("Reward", str(resolved["reward_description"]), UITokens.GOLD_BRIGHT))

	var problem: String = str(resolved.get("problem", ""))
	if problem != "" and bool(resolved.get("ok", false)):
		var p := UIStyle.colored_label(problem, UITokens.RED, UITokens.FONT_SMALL)
		p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(p)

	var unlock_reason: String = str(resolved.get("lock_reason", ""))
	if unlock_reason != "":
		var l := UIStyle.colored_label("Locked — %s" % unlock_reason, UITokens.AMBER, UITokens.FONT_SMALL)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(l)

	# --- Requirements ---------------------------------------------------
	var requirements: Array = resolved.get("requirements", [])
	if not requirements.is_empty():
		_body.add_child(UIStyle.section("Requirements",
			"%d of %d met" % [_count_satisfied(requirements), requirements.size()]))
		for req in requirements:
			_body.add_child(Widgets.requirement_row(str(req.get("label", "")), float(req.get("current", 0)),
				float(req.get("required", 1)), bool(req.get("satisfied", false)), str(req.get("hint", ""))))

	# --- Where materials come from --------------------------------------
	var missing: Array = resolved.get("missing", [])
	var sources: Array = resolved.get("sources", [])
	if not missing.is_empty() and sources.is_empty():
		# Say so rather than silently dropping the section: a goal card with no "where from"
		# answer reads as a broken card, not as an honest dead end.
		_body.add_child(UIStyle.section("Where to get them"))
		_body.add_child(UIStyle.colored_label(
			"No acquisition path is recorded for this yet — it may be unfinished content.",
			UITokens.AMBER, UITokens.FONT_SMALL))
	if not missing.is_empty() and not sources.is_empty():
		_body.add_child(UIStyle.section("Where to get them"))
		for src in sources:
			_body.add_child(_source_row(src))
			var route: Dictionary = src.get("route", {})
			if not route.is_empty():
				var go := UIStyle.mini_button("Go to this")
				go.pressed.connect(func(): navigated.emit(route))
				_body.add_child(go)

	# --- Prerequisite recipes (the dependency chain) --------------------
	var recipes: Array = resolved.get("prerequisite_recipes", [])
	if not recipes.is_empty():
		_body.add_child(UIStyle.section("Recipes you need first",
			"counts assume nothing else changes"))
		for r in recipes:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", UITokens.SP_4)
			row.add_child(Widgets.badge("Lv %d" % int(r.get("level_required", 1)),
				UITokens.GREEN if bool(r.get("unlocked", true)) else UITokens.AMBER,
				"Level requirement for this recipe"))
			# A byproduct route needs its roll stated, or "×3334" reads as a typo instead of the
			# honest consequence of a three per cent drop.
			var sublabel: String = str(r.get("label", ""))
			if bool(r.get("byproduct", false)):
				sublabel += "  ·  %s side drop" % UIStyle.fmt_percent(float(r.get("chance", 0.0)))
			var l := UIStyle.label(sublabel, false, UITokens.FONT_SMALL)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# Recipe names plus a run count plus a roll are wider than the pane: wrapping them is
			# what keeps the "Open" button beside them on screen.
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(l)
			var go2 := UIStyle.mini_button("Open")
			var route2: Dictionary = {"screen": Screens.SKILLS, "skill_id": str(r.get("skill_id", "")),
				"action_id": str(r.get("id", "")).split(":")[-1] if str(r.get("id", "")).contains(":") else ""}
			go2.pressed.connect(func(): navigated.emit(route2))
			row.add_child(go2)
			_body.add_child(row)

	# --- Materials roll-up ---------------------------------------------
	var materials: Array = resolved.get("materials", [])
	if not materials.is_empty():
		_body.add_child(UIStyle.section("Materials to gather",
			"totals for the whole chain"))
		for m in materials:
			var short: int = int(m.get("short", 0))
			_body.add_child(Widgets.requirement_row(str(m.get("name", "")),
				float(m.get("have", 0)), float(m.get("need", 0)), short <= 0,
				"need %s more for this goal" % UIStyle.fmt(float(short)) if short > 0 else "covered"))

	# --- Navigation ----------------------------------------------------
	var routes: Array = resolved.get("routes", [])
	if not routes.is_empty():
		_body.add_child(UIStyle.section("Go there"))
		for route in routes:
			var b := UIStyle.button(str(route.get("label", "Open")))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			# These labels carry a whole activity name ("Go to Verdigris Sword at Forgecraft"), and a
			# button that cannot wrap sets the width of the entire card.
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var r: Dictionary = route
			b.pressed.connect(func(): navigated.emit(r))
			_body.add_child(b)

func show_item(item_id: String) -> void:
	if item_id == "" or not DataLoader.items.has(item_id):
		show_screen_help(Screens.BANK)
		return
	_current_kind = "item"
	_current_payload = item_id
	var item: Dictionary = DataLoader.get_item(item_id)
	_clear()
	_title.text = str(item.get("name", item_id))
	var rarity: Dictionary = UIStyle.item_rarity(item_id)
	_subtitle.text = "%s · %s" % [str(rarity["label"]), str(item.get("item_type", "item")).capitalize()]
	_pin_button.visible = true
	_pin_button.text = "Untrack" if Goals.is_pinned("item", item_id) else "Track this goal"

	var held: int = BankManager.get_count(item_id)
	# The face and the flavour text share a row; the numbers go underneath it at full width. Beside a
	# 64px icon, the 132px key column of key_value() left the value column one pixel wide, which is
	# how "500 GP" came to render as a ladder of single letters down the edge of the pane.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITokens.SP_5)
	head.add_child(Widgets.item_icon(item_id, UITokens.ICON_XL))
	var col := UIStyle.vbox(UITokens.SP_2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if str(item.get("description", "")) != "":
		var d := UIStyle.label(str(item["description"]), true, UITokens.FONT_SMALL)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(d)
	if BankManager.is_protected(item_id):
		col.add_child(UIStyle.colored_label("Protected — cannot be sold", UITokens.GREEN, UITokens.FONT_SMALL))
	if EquipmentManager.is_equipped(item_id):
		col.add_child(UIStyle.colored_label("Equipped", UITokens.GOLD_BRIGHT, UITokens.FONT_SMALL))
	if col.get_child_count() > 0:
		head.add_child(col)
	_body.add_child(head)
	_body.add_child(Widgets.key_value("In storage", UIStyle.fmt_exact(float(held)), UITokens.TEXT_STRONG))
	if int(item.get("sell_price", 0)) > 0:
		_body.add_child(Widgets.key_value("Sell value",
			"%s GP" % UIStyle.fmt_exact(float(item["sell_price"]))))
	if int(item.get("heal_amount", 0)) > 0:
		_body.add_child(Widgets.key_value("Heals", "%d HP" % int(item["heal_amount"]), UITokens.TEAL))
	var stats: Dictionary = item.get("equipment_stats", {})
	if not stats.is_empty():
		_body.add_child(UIStyle.section("Equipment stats"))
		for key in stats.keys():
			_body.add_child(Widgets.key_value(str(key).replace("_", " ").capitalize(),
				UIStyle.fmt_signed(float(stats[key])), UITokens.TEAL if float(stats[key]) >= 0.0 else UITokens.RED))
	if not (item.get("passive_modifiers", {}) as Dictionary).is_empty():
		_body.add_child(UIStyle.section("Passive effects"))
		for key in (item["passive_modifiers"] as Dictionary).keys():
			_body.add_child(Widgets.key_value(str(key).replace("_", " ").capitalize(),
				UIStyle.describe_modifier(str(key), float(item["passive_modifiers"][key])), UITokens.PURPLE))
	for skill_id in (item.get("level_requirements", {}) as Dictionary).keys():
		_body.add_child(Widgets.key_value("Requires",
			"%s %d" % [DataLoader.get_skill(str(skill_id)).get("name", skill_id), int(item["level_requirements"][skill_id])],
			UITokens.TEXT))

	var sources: Array = Goals.sources_for_item(item_id)
	if not sources.is_empty():
		_body.add_child(UIStyle.section("How to obtain"))
		for s in sources:
			_body.add_child(_source_row(s))
			var route: Dictionary = s.get("route", {})
			if not route.is_empty():
				var go := UIStyle.mini_button("Go")
				var r: Dictionary = route
				go.pressed.connect(func(): navigated.emit(r))
				_body.add_child(go)
	else:
		_body.add_child(UIStyle.colored_label("No known acquisition path — likely unfinished content.",
			UITokens.AMBER, UITokens.FONT_SMALL))

	var uses: Array = _recipes_using(item_id)
	if not uses.is_empty():
		_body.add_child(UIStyle.section("Used by"))
		for u in uses:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", UITokens.SP_4)
			var l := UIStyle.label(str(u["label"]), false, UITokens.FONT_SMALL)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# "Assemble Celestial Angler (Engineering)" is a 38-character label in a 260px pane.
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(l)
			var go2 := UIStyle.mini_button("Open")
			var route2: Dictionary = {"screen": Screens.SKILLS, "skill_id": str(u["skill_id"]), "action_id": str(u["action_id"])}
			go2.pressed.connect(func(): navigated.emit(route2))
			row.add_child(go2)
			_body.add_child(row)

	if held > 0:
		var sell := UIStyle.mini_button("Sell 1", "Sell a single unit at its listed price")
		sell.pressed.connect(func():
			var preview: Dictionary = BankManager.sell_preview(item_id, 1)
			BankManager.sell_item(item_id, 1)
			EventBus.notify("Sold %s for %s GP" % [str(preview["name"]), UIStyle.fmt(float(preview["gp_gained"]))], "success"))
		_body.add_child(sell)

func show_recipe(skill_id: String, action_id: String) -> void:
	if skill_id == "" or action_id == "":
		return
	var action: Dictionary = DataLoader.get_action(skill_id, action_id)
	if action.is_empty():
		# Never leave the previous card standing behind a failed lookup: a pane that still shows
		# the last activity's numbers is worse than one that admits it has nothing to show.
		_current_kind = ""
		_current_payload = null
		_clear()
		_title.text = "Unavailable"
		_subtitle.text = "No activity '%s' exists on %s." % [action_id, str(DataLoader.get_skill(skill_id).get("name", skill_id))]
		_pin_button.visible = false
		return
	_current_kind = "recipe"
	_current_payload = {"skill_id": skill_id, "action_id": action_id}
	_clear()
	_title.text = str(action.get("name", action_id))
	_subtitle.text = "%s · recipe" % DataLoader.get_skill(skill_id).get("name", skill_id)
	_pin_button.visible = true
	_pin_button.text = "Untrack" if Goals.is_pinned("recipe", "%s:%s" % [skill_id, action_id]) else "Track this goal"

	var check: Dictionary = SkillManager.check_action(skill_id, action_id)
	var status_color: Color = UITokens.GREEN if bool(check["ok"]) else UITokens.AMBER
	_body.add_child(Widgets.key_value("Can start now", "yes" if bool(check["ok"]) else str(check["detail"]), status_color))

	var est: Dictionary = ActionEstimates.for_action(skill_id, action_id)
	if not est.is_empty():
		_body.add_child(UIStyle.section("Projection", str(est["assumptions"])))
		_body.add_child(Widgets.key_value("Action time", "%.2fs" % float(est["interval"])))
		_body.add_child(Widgets.key_value("XP per action", UIStyle.fmt(float(est["xp_per_action"])), UITokens.BLUE))
		_body.add_child(Widgets.key_value("XP per hour (≈)", UIStyle.fmt(float(est["xp_per_hour"])), UITokens.BLUE))
		_body.add_child(Widgets.key_value("Success chance", UIStyle.fmt_percent(float(est["success_chance"]))))
		if float(est.get("output_per_hour", 0.0)) > 0.0:
			_body.add_child(Widgets.key_value("Output per hour (≈)",
				"%s %s" % [UIStyle.fmt(float(est["output_per_hour"])), str(est["output_name"])], UITokens.TEAL))
		if float(est["xp_to_next"]) > 0.0 and float(est["xp_per_hour"]) > 0.0:
			_body.add_child(Widgets.key_value("Next level in (≈)",
				UIStyle.fmt_duration(float(est["xp_to_next"]) / maxf(1.0, float(est["xp_per_hour"])) * 3600.0), UITokens.GOLD))
		if float(est.get("supply_hours", -1.0)) >= 0.0:
			_body.add_child(Widgets.key_value("Current stock lasts (≈)",
				UIStyle.fmt_duration(float(est["supply_hours"])), UITokens.AMBER))

	var inputs: Dictionary = action.get("input_items", {})
	if not inputs.is_empty():
		_body.add_child(UIStyle.section("Consumes per action"))
		for item_id in inputs.keys():
			var have: int = BankManager.get_count(str(item_id))
			var need: int = int(inputs[item_id])
			# "What am I missing, and where do I get it?" is the question this pane exists to
			# answer, so a row the player cannot fill carries its first real source and a route.
			var hint: String = "you have %s" % UIStyle.fmt_exact(float(have))
			var route: Dictionary = {}
			if have < need:
				var sources: Array = Goals.sources_for_item(str(item_id))
				if not sources.is_empty():
					var first: Dictionary = sources[0]
					hint = "from %s — %s" % [str(first.get("label", "")), str(first.get("detail", ""))]
					route = first.get("route", {})
				else:
					hint = "no known acquisition path yet"
			_body.add_child(Widgets.requirement_row(str(DataLoader.get_item(str(item_id)).get("name", item_id)),
				float(have), float(need), have >= need, hint, route))
	var outputs: Dictionary = action.get("output_items", {})
	if not outputs.is_empty():
		_body.add_child(UIStyle.section("Produces per action"))
		for item_id in outputs.keys():
			_body.add_child(Widgets.item_row(str(item_id), int(outputs[item_id])))
	var mods: Array[String] = []
	var doubling: float = ModifierManager.get_doubling_chance(skill_id)
	if doubling > 0.0:
		mods.append("Doubling chance %s" % UIStyle.fmt_percent(doubling / 100.0))
	var preserve: float = ModifierManager.get_preservation_chance(skill_id)
	if preserve > 0.0:
		mods.append("Material preservation %s" % UIStyle.fmt_percent(preserve / 100.0))
	var flat: int = ModifierManager.get_resource_flat(skill_id)
	if flat > 0:
		mods.append("Flat output +%d per action" % flat)
	if not mods.is_empty():
		_body.add_child(UIStyle.section("Modifiers applying here"))
		for m in mods:
			_body.add_child(UIStyle.colored_label("· " + m, UITokens.PURPLE, UITokens.FONT_SMALL))
	_body.add_child(UIStyle.colored_label(
		"The full modifier breakdown is available on the skill screen.", UITokens.TEXT_MUTED, UITokens.FONT_MICRO))

func show_region(area_id: String) -> void:
	if area_id == "":
		return
	var is_dungeon: bool = DataLoader.dungeons.has(area_id)
	var row: Dictionary = DataLoader.get_dungeon(area_id) if is_dungeon else DataLoader.areas.get(area_id, {})
	if row.is_empty():
		return
	_current_kind = "region"
	_current_payload = area_id
	_clear()
	_title.text = str(row.get("name", area_id))
	_subtitle.text = "Expedition" if is_dungeon else "Region"
	_pin_button.visible = false
	if str(row.get("flavour", "")) != "":
		var f := UIStyle.label(str(row["flavour"]), true, UITokens.FONT_SMALL)
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(f)
	var levels: Array = row.get("level_range", [])
	if levels.size() == 2:
		_body.add_child(Widgets.key_value("Enemy level range", "%d – %d" % [int(levels[0]), int(levels[1])]))
	_body.add_child(UIStyle.section("Encounters"))
	for monster_id in row.get("monsters", []):
		var m: Dictionary = DataLoader.get_monster(str(monster_id))
		if m.is_empty():
			continue
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", UITokens.SP_4)
		var sprite := TextureRect.new()
		sprite.texture = AssetRegistry.monster_sprite(str(monster_id))
		sprite.custom_minimum_size = Vector2(UITokens.ICON_MD, UITokens.ICON_MD)
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if PlayerData.completion_log.get("monsters", {}).has(str(monster_id)):
			sprite.modulate = Color(1, 1, 1, 1.0)
			sprite.tooltip_text = "%s — defeated" % str(m.get("name", monster_id))
		else:
			sprite.modulate = Color(1, 1, 1, 0.35)
			sprite.tooltip_text = "%s — not yet defeated" % str(m.get("name", monster_id))
		head.add_child(sprite)
		var col := UIStyle.vbox(UITokens.SP_1)
		col.add_child(UIStyle.label("%s  (Lv %d)" % [str(m.get("name", monster_id)), int(m.get("combat_level", 1))], false, UITokens.FONT_SMALL))
		col.add_child(UIStyle.label("%d HP · %s · max hit %d" % [int(m.get("hitpoints", 0)),
			str(m.get("attack_type", "melee")), int(m.get("max_hit", 0))], true, UITokens.FONT_MICRO))
		head.add_child(col)
		_body.add_child(head)
		if str(m.get("flavour", "")) != "":
			var fl := UIStyle.label("    " + str(m["flavour"]), true, UITokens.FONT_MICRO)
			fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_body.add_child(fl)
		if not PlayerData.completion_log.get("monsters", {}).has(str(monster_id)):
			_body.add_child(Widgets.badge("Undiscovered", UITokens.TEXT_MUTED, "Not yet defeated"))
		var drops: Array = m.get("loot_table", [])
		if not drops.is_empty():
			var parts: Array[String] = []
			for drop in drops:
				if typeof(drop) != TYPE_DICTIONARY or bool(drop.get("is_currency", false)):
					continue
				parts.append("%s (%.1f%%)" % [str(DataLoader.get_item(str(drop.get("item_id", ""))).get("name", "?")),
					float(drop.get("chance", 0.0)) * 100.0])
			if not parts.is_empty():
				var l := UIStyle.label("    Drops: " + ", ".join(parts), true, UITokens.FONT_MICRO)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_body.add_child(l)
	if is_dungeon:
		var reqs: Variant = row.get("requires", {})
		var prev: String = str(row.get("requires_dungeon", ""))
		if (typeof(reqs) == TYPE_DICTIONARY and not (reqs as Dictionary).is_empty()) or prev != "":
			_body.add_child(UIStyle.section("Unlock requirements"))
			for skill_id in (reqs as Dictionary).keys():
				var level: int = PlayerData.get_level(str(skill_id))
				_body.add_child(Widgets.requirement_row(
					"%s %d" % [str(DataLoader.get_skill(str(skill_id)).get("name", skill_id)), int(reqs[skill_id])],
					float(level), float(reqs[skill_id]), level >= int(reqs[skill_id])))
			if prev != "":
				var cleared: bool = (PlayerData.completion_log.get("dungeons", {}) as Dictionary).has(prev)
				_body.add_child(Widgets.requirement_row(
					"Clear %s" % str(DataLoader.get_dungeon(prev).get("name", prev)),
					1.0 if cleared else 0.0, 1.0, cleared, "Open Expeditions to attempt it"))
		var reward: Dictionary = row.get("rewards_first_clear", {})
		if not reward.is_empty():
			_body.add_child(UIStyle.section("First-clear reward"))
			_body.add_child(UIStyle.label(_describe_reward(reward), false, UITokens.FONT_SMALL))
	var expedition: bool = is_dungeon and CombatManager.is_expedition(area_id)
	var go := UIStyle.button("Open in Expeditions" if expedition else "Open in Combat")
	go.pressed.connect(func(): navigated.emit({"screen": Screens.EXPEDITIONS if expedition else Screens.COMBAT, "area_id": area_id}))
	_body.add_child(go)

## A source is two stacked, wrapping lines rather than a key/value row: these names are the longest
## text in the pane ("Assemble Celestial Angler at Engineering"), and a single-line row wide enough
## for one pushes the card past the 260px pane and clips the value beside it.
func _source_row(src: Dictionary) -> Control:
	var box := UIStyle.vbox(UITokens.SP_1)
	var head := UIStyle.label(_source_label(src), false, UITokens.FONT_SMALL)
	head.add_theme_color_override("font_color",
		UITokens.TEAL if bool(src.get("unlocked", true)) else UITokens.TEXT_MUTED)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	var detail := UIStyle.label(_source_detail(src), true, UITokens.FONT_MICRO)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	return box

## A source row for a goal with several missing materials names the material it resolves, so five
## ore routes for one diamond cannot read as five separate answer.
func _source_label(src: Dictionary) -> String:
	var label: String = str(src.get("label", ""))
	var for_item: String = str(src.get("for", ""))
	return "%s · %s" % [for_item, label] if for_item != "" else label

## The detail line, plus the reason a greyed-out route is greyed out: "locked" without the level
## it needs is not an answer the player can act on.
func _source_detail(src: Dictionary) -> String:
	var detail: String = str(src.get("detail", ""))
	if bool(src.get("unlocked", true)):
		return detail
	var skill_id: String = str((src.get("route", {}) as Dictionary).get("skill_id", ""))
	var level: int = int(src.get("level_required", 0))
	if skill_id != "" and level > 1:
		detail += " · locked until %s %d" % [str(DataLoader.get_skill(skill_id).get("name", skill_id)), level]
	return detail

func _describe_reward(reward: Dictionary) -> String:
	var parts: Array[String] = []
	if reward.has("gp"):
		parts.append("%s GP" % UIStyle.fmt(float(reward["gp"])))
	for item_id in (reward.get("items", {}) as Dictionary).keys():
		parts.append("%s ×%s" % [DataLoader.get_item(str(item_id)).get("name", item_id),
			UIStyle.fmt_exact(float(reward["items"][item_id]))])
	return " · ".join(parts) if not parts.is_empty() else "None listed"

func show_screen_help(screen: String) -> void:
	_pin_button.visible = false
	var help: Dictionary = SCREEN_HELP.get(screen, {})
	_render_text(str(help.get("title", Screens.label_for(screen))), str(help.get("body", "")))

func _render_text(title_text: String, body_text: String) -> void:
	_clear()
	_current_kind = ""
	_current_payload = null
	_title.text = title_text
	_subtitle.text = ""
	_pin_button.visible = false
	var l := UIStyle.label(body_text, true, UITokens.FONT_SMALL)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)

const SCREEN_HELP: Dictionary = {
	Screens.OVERVIEW: {"title": "Overview",
		"body": "What you are doing, what it earns, what just unlocked, and what to do next. Pin anything here to see its full dependency chain."},
	Screens.SKILLS: {"title": "Skills",
		"body": "Pick an activity and start it. Gathering feeds crafting; crafting feeds expeditions. Mastery is per activity, not per skill."},
	Screens.COMBAT: {"title": "Combat",
		"body": "Combat is automated. You prepare: style, loadout, food and rites. Retreat is always available and costs nothing."},
	Screens.EXPEDITIONS: {"title": "Expeditions",
		"body": "High-tier dungeon runs unlock after combat level 60 and the Expedition Charter task."},
	Screens.BANK: {"title": "Storage",
		"body": "Search, filter and sort your stores. Protect anything you do not want to sell by accident, or track it as a goal."},
	Screens.QUESTS: {"title": "Tasks",
		"body": "Authored objectives that walk you through the whole loop. Rewards are granted exactly once, on claim."},
	Screens.ACHIEVEMENTS: {"title": "Milestones",
		"body": "Long-term recognition with deliberately modest rewards. Progress is measured from your lifetime record."},
	Screens.COLLECTION: {"title": "Collection",
		"body": "Everything you have discovered: items, enemies and expeditions. Undiscovered entries stay visible but unnamed."},
	Screens.SETTLEMENT: {"title": "Settlement",
		"body": "Emberreach produces resources on the hour, whether you are watching or not. Structures unlock systems as well as percentages."},
	Screens.PROVISIONER: {"title": "Provisioner",
		"body": "Spend GP on unlocks and conveniences. Costs and requirements are stated before you commit."},
	Screens.STORE: {"title": "General Store",
		"body": "Repeatable stock bought in bundles. Every price sits above what the item sells for, so crafting stays the cheaper route: buy to unblock a queue, not to skip a skill."},
	Screens.SETTINGS: {"title": "Settings",
		"body": "Offline behaviour, automation thresholds, accessibility and save management."},
	Screens.RECOVERY: {"title": "Save recovery",
		"body": "Your save could not be loaded. Nothing has been overwritten — choose how to proceed below."},
}

# =========================================================================
#  Helpers
# =========================================================================

func _clear() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()

func _count_satisfied(requirements: Array) -> int:
	var n: int = 0
	for r in requirements:
		if bool(r.get("satisfied", false)):
			n += 1
	return n

func _recipes_using(item_id: String) -> Array:
	var out: Array = []
	for skill_id in DataLoader.skills.keys():
		for a in DataLoader.get_skill_actions(skill_id):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if (a.get("input_items", {}) as Dictionary).has(item_id):
				out.append({"label": "%s (%s)" % [str(a.get("name", "")), str(DataLoader.get_skill(skill_id).get("name", skill_id))],
					"skill_id": skill_id, "action_id": str(a.get("id", ""))})
	if out.size() > 8:
		out = out.slice(0, 8)
	return out

func _on_pin() -> void:
	match _current_kind:
		"goal":
			var goal: Dictionary = _current_payload
			Goals.toggle(str(goal.get("kind", "")), str(goal.get("id", "")), int(goal.get("level", 0)))
		"item":
			Goals.toggle("item", str(_current_payload))
		"recipe":
			var payload: Dictionary = _current_payload
			Goals.toggle("recipe", "%s:%s" % [str(payload.get("skill_id", "")), str(payload.get("action_id", ""))])
	_refresh_if_goal()

func _refresh_if_goal() -> void:
	if _current_kind == "goal" and typeof(_current_payload) == TYPE_DICTIONARY:
		var goal: Dictionary = _current_payload
		if not Goals.is_pinned(str(goal.get("kind", "")), str(goal.get("id", ""))):
			# Keep showing the resolution even after untracking: the panel is a lens, not a list.
			pass
		show_goal(goal)
