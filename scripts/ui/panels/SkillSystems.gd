extends VBoxContainer
## SkillSystems — the per-skill system sections that sit under the activities grid.
##
## Several engines in this game are complete and self-tested but had no player-facing
## control at all: slayer task taking, familiar equipping, constellation stars, agility
## obstacles, hex travel/survey and museum donations. This node is the one place that
## reaches them, keyed by skill, so each system lives where a player already looks for it.
##
## It is deliberately rebuilt whole on refresh (like the panels around it): every rebuild
## re-reads state from the managers, so no row can show a stale affordability.

signal navigated(route: Dictionary)

const NewSystems = preload("res://scripts/ui/panels/NewSkillSystems.gd")

const HANDLED: Array[String] = [
	"ranching", "inscription", "engineering", "enchanting", "dreamwalking", "caravaneering",
	"slayer", "summoning", "astrology", "agility", "cartography", "archaeology",
	"alt_magic",
]

const RuneWards = preload("res://scripts/core/RuneWards.gd")

var _skill_id: String = ""
var _star_sort: int = 0

func set_skill(skill_id: String) -> void:
	_skill_id = skill_id
	visible = HANDLED.has(skill_id)

func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if not visible or _skill_id == "":
		return
	if _skill_id in ["ranching", "inscription", "engineering", "enchanting", "dreamwalking", "caravaneering"]:
		var systems := NewSystems.new()
		add_child(systems)
		systems.set_skill(_skill_id)
		return
	match _skill_id:
		"slayer": _build_slayer()
		"summoning": _build_summoning()
		"astrology": _build_astrology()
		"agility": _build_agility()
		"cartography": _build_cartography()
		"archaeology": _build_archaeology()
		"alt_magic": _build_runescribing()

# ==========================================================================
#  Runescribing (alt_magic): timed wards
# ==========================================================================

func _build_runescribing() -> void:
	var active: Array[String] = RuneWards.active_ids()
	var box := UIStyle.section("Wards",
		"Cast a ward to charge it. Each cast adds time up to its cap, and the charge keeps running while you train anything else or fight. %d wards can hold a charge at once." % RuneWards.MAX_ACTIVE)
	add_child(box)
	box.add_child(Widgets.key_value("Wards holding a charge", "%d / %d" % [active.size(), RuneWards.MAX_ACTIVE],
		UITokens.GREEN if active.size() < RuneWards.MAX_ACTIVE else UITokens.AMBER))
	var level: int = PlayerData.get_level(RuneWards.SKILL_ID)
	for action in RuneWards.ward_actions():
		var left: float = RuneWards.remaining(action)
		var effect: String = UIStyle.describe_modifier_table(action.ward.get("mods", {}))
		var value: String
		var color: Color = UITokens.TEXT_DIM
		if left > 0.0:
			value = "%s left of %s" % [UIStyle.fmt_duration(left), UIStyle.fmt_duration(RuneWards.max_seconds(action))]
			color = UITokens.GREEN
		elif level < int(action.get("level_required", 1)):
			value = "Lv %d" % int(action.get("level_required", 1))
			color = UITokens.DISABLED
		else:
			value = "not charged"
		box.add_child(Widgets.key_value("%s · %s" % [str(action.get("name", "")), effect], value, color))

# ==========================================================================
#  Huntsman (slayer): tasks, kill tracking, and the Slayer shop
# ==========================================================================

func _build_slayer() -> void:
	var box := UIStyle.section("Slayer tasks",
		"Take a task, then kill its monster anywhere on the frontier. Completion pays Slayer Coins.")
	add_child(box)
	box.add_child(Widgets.key_value("Slayer Coins", UIStyle.fmt(PlayerData.slayer_coins),
		UITokens.GOLD, "Earned from completed tasks; spent in the Slayer shop below"))
	if SlayerManager.has_task():
		box.add_child(_task_card())
	else:
		box.add_child(UIStyle.label("No active task. Take one from a tier below.", true, UITokens.FONT_SMALL))
	for tier_id in DataLoader.slayer_tasks.keys():
		if str(tier_id).begins_with("_"):
			continue
		var tier: Dictionary = DataLoader.slayer_tasks[tier_id]
		if typeof(tier) != TYPE_DICTIONARY:
			continue
		var level_needed: int = int(tier.get("level_required", 1))
		var have_level: bool = PlayerData.get_level("slayer") >= level_needed
		var busy: bool = SlayerManager.has_task()
		var row := UIStyle.hbox(UITokens.SP_4)
		var name_label := UIStyle.label(str(tier.get("name", tier_id)), false, UITokens.FONT_SMALL)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		# Name the real blocker. A tier gated past the Slayer cap can never be taken, and showing it
		# as an ordinary "Lv N" lock would tell the player to keep training a capped skill.
		var slayer_cap: int = PlayerData.get_level_cap("slayer")
		var beyond_cap: bool = level_needed > slayer_cap
		var gate_text: String = "Requires Slayer level %d" % level_needed
		var badge_hint: String = "Slayer level required"
		if beyond_cap:
			gate_text = "Slayer cannot exceed level %d" % slayer_cap
			badge_hint = "Slayer caps at %d in your game mode" % slayer_cap
		row.add_child(Widgets.badge("Lv %d" % level_needed,
			UITokens.GREEN if have_level else (UITokens.RED if beyond_cap else UITokens.TEXT_MUTED),
			badge_hint))
		var take := UIStyle.mini_button("Take task")
		take.disabled = busy or not have_level
		take.tooltip_text = "You are already on a task" if busy \
			else (gate_text if not have_level \
			else ("Assign a random monster or expedition from the %s tier" if DataLoader.slayer_tasks.get("_dungeons", {}).has(tier_id) \
			else "Assign a random monster from the %s tier") % str(tier.get("name", tier_id)))
		var tid: String = tier_id
		take.pressed.connect(func():
			SlayerManager.assign_task(tid)
			rebuild())
		row.add_child(take)
		box.add_child(row)
	_build_slayer_shop(box)

func _task_card() -> Control:
	var task: Dictionary = PlayerData.slayer_task
	var monster_id := str(task.get("monster_id", ""))
	var monster: Dictionary = DataLoader.get_monster(monster_id)
	var dungeon_task: bool = SlayerManager.is_dungeon_task()
	var dungeon_id := str(task.get("dungeon_id", ""))
	var card := UIStyle.card(true)
	var col := UIStyle.vbox(UITokens.SP_2)
	card.add_child(col)
	var head := UIStyle.hbox(UITokens.SP_4)
	var heading: String = str(DataLoader.get_dungeon(dungeon_id).get("name", dungeon_id)) if dungeon_task \
		else str(monster.get("name", monster_id))
	var title := UIStyle.title(heading, UITokens.FONT_SUBHEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(Widgets.badge("%s tier" % str(task.get("tier", "easy")).capitalize(),
		UITokens.RED, "Task tier"))
	col.add_child(head)
	var done := int(task.get("kills_done", 0))
	var required := maxi(1, int(task.get("kills_required", 1)))
	if dungeon_task:
		col.add_child(Widgets.progress_bar(float(done), float(required), UITokens.RED,
			"%d / %d clears" % [done, required], 16, "Each full clear of this expedition counts once"))
	else:
		col.add_child(Widgets.progress_bar(float(done), float(required), UITokens.RED,
			"%d / %d kills" % [done, required], 16, "Kills count anywhere the monster appears"))
	col.add_child(UIStyle.colored_label("Pays %s × %s Slayer Coins on completion" % [
		UIStyle.fmt(float(DataLoader.get_monster(monster_id).get("slayer_xp", 10))),
		"%.2f" % float(task.get("coin_multiplier", 1.0))], UITokens.TEAL, UITokens.FONT_MICRO))
	var actions := UIStyle.hbox(UITokens.SP_3)
	var area_id := dungeon_id if dungeon_task else _place_for_monster(monster_id)
	var place: Dictionary = DataLoader.get_dungeon(area_id) if DataLoader.dungeons.has(area_id) else DataLoader.areas.get(area_id, {})
	col.add_child(UIStyle.label("Location: " + str(place.get("name", "Unknown")), true, UITokens.FONT_SMALL))
	var track := UIStyle.button("Track")
	track.disabled = area_id == ""
	track.tooltip_text = "Open the place this monster lives" if area_id != "" else "This monster has no known area"
	track.pressed.connect(func():
		if area_id != "":
			navigated.emit({"screen": Screens.EXPEDITIONS if CombatManager.is_expedition(area_id) else Screens.COMBAT, "area_id": area_id}))
	actions.add_child(track)
	var reroll := UIStyle.button("Reroll")
	reroll.tooltip_text = "Swap this task for another monster of the same tier (keeps no progress)"
	reroll.pressed.connect(func():
		SlayerManager.reroll(0.0)
		rebuild())
	actions.add_child(reroll)
	col.add_child(actions)
	return card

## The first area or dungeon that contains this monster, so "Track" can route there.
func _place_for_monster(monster_id: String) -> String:
	for area_id in DataLoader.areas.keys():
		if str(monster_id) in ((DataLoader.areas[area_id] as Dictionary).get("monsters", []) as Array):
			return str(area_id)
	for dungeon_id in DataLoader.dungeons.keys():
		if str(monster_id) in ((DataLoader.dungeons[dungeon_id] as Dictionary).get("monsters", []) as Array):
			return str(dungeon_id)
	return ""

func _build_slayer_shop(parent: VBoxContainer) -> void:
	var shop := UIStyle.section("Slayer shop",
		"Huntsman armour and the keys that open the slayer areas.")
	parent.add_child(shop)
	for entry in SlayerManager.shop_items():
		var item_id := str(entry.get("item_id", ""))
		var cost := float(entry.get("cost", 0))
		var affordable: bool = PlayerData.slayer_coins >= cost
		var row := UIStyle.hbox(UITokens.SP_4)
		row.add_child(Widgets.item_icon(item_id))
		var name_label := UIStyle.label(str(entry.get("name", item_id)), false, UITokens.FONT_SMALL)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.tooltip_text = str(Widgets.item_tooltip(item_id))
		row.add_child(name_label)
		row.add_child(Widgets.badge("%s coins" % UIStyle.fmt(cost),
			UITokens.GOLD if affordable else UITokens.TEXT_MUTED, "Slayer Coin cost"))
		var buy := UIStyle.mini_button("Buy")
		buy.disabled = not affordable
		buy.tooltip_text = "Buy with Slayer Coins" if affordable else "Not enough Slayer Coins"
		var iid: String = item_id
		buy.pressed.connect(func():
			if SlayerManager.buy_slayer_item(iid):
				rebuild())
		row.add_child(buy)
		shop.add_child(row)

# ==========================================================================
#  Beastbinding (summoning): marks, equipping, charges
# ==========================================================================

func _build_summoning() -> void:
	var box := UIStyle.section("Familiars",
		"Raise a familiar's mark by training its skill. Equip up to two; charges drain while their skill runs.")
	add_child(box)
	box.add_child(Widgets.key_value("Equipped", "%d / %d" % [
		SummoningManager.equipped.size(), SummoningManager.MAX_EQUIPPED], UITokens.TEAL,
		"Each equipped familiar registers its effect and any synergy with the other"))
	for fid in DataLoader.familiars.keys():
		var familiar: Dictionary = DataLoader.familiars[fid]
		if typeof(familiar) != TYPE_DICTIONARY:
			continue
		var is_equipped: bool = SummoningManager.equipped.has(fid)
		var mark_level: int = SummoningManager.get_mark_level(fid)
		var card := UIStyle.card(is_equipped)
		var col := UIStyle.vbox(UITokens.SP_2)
		card.add_child(col)
		var head := UIStyle.hbox(UITokens.SP_4)
		var title := UIStyle.title(str(familiar.get("name", fid)), UITokens.FONT_SUBHEAD)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		head.add_child(Widgets.badge("Tier %d" % int(familiar.get("tier", 1)),
			UITokens.BLUE, "Mark difficulty tier"))
		head.add_child(Widgets.badge("Mark %d / 6" % mark_level,
			UITokens.PURPLE if mark_level >= 6 else (UITokens.GREEN if mark_level > 0 else UITokens.TEXT_MUTED),
			"Mark level — higher marks unlock stronger effects"))
		col.add_child(head)
		var effect_text := UIStyle.describe_modifier_table(familiar.get("effect", {}))
		if effect_text != "":
			col.add_child(UIStyle.colored_label(effect_text, UITokens.TEAL, UITokens.FONT_MICRO))
		var train_skill := str(familiar.get("mark_skill", ""))
		var button_row := UIStyle.hbox(UITokens.SP_3)
		if is_equipped:
			var off := UIStyle.button("Unequip")
			off.pressed.connect(func():
				SummoningManager.unequip_familiar(fid)
				rebuild())
			button_row.add_child(off)
			button_row.add_child(Widgets.badge("%d charges" % int(SummoningManager.charges.get(fid, 0)),
				UITokens.GOLD, "Actions this familiar still backs"))
		else:
			var on := UIStyle.button("Equip")
			var reason := ""
			if mark_level < 1:
				reason = "Train %s to discover the first mark" % str(DataLoader.get_skill(train_skill).get("name", train_skill))
			elif SummoningManager.equipped.size() >= SummoningManager.MAX_EQUIPPED:
				reason = "Both familiar slots are filled"
			elif int(SummoningManager.charges.get(fid, 0)) <= 0 and BankManager.get_count(str(familiar.get("tablet_item", ""))) <= 0:
				reason = "Craft %s tablets first" % str(familiar.get("name", fid))
			on.disabled = reason != ""
			on.tooltip_text = "Equip this familiar" if reason == "" else reason
			on.pressed.connect(func():
				if SummoningManager.equip_familiar(fid):
					rebuild())
			button_row.add_child(on)
			if train_skill != "":
				button_row.add_child(Widgets.badge(str(DataLoader.get_skill(train_skill).get("name", train_skill)),
					UITokens.TEXT_MUTED, "Train this skill to raise the mark"))
		var interval: float = float(CombatManager.player_combat_summary().attack_interval) if train_skill in PlayerData.COMBAT_SKILLS else (SkillManager.current_interval if SkillManager.running and SkillManager.active_skill == train_skill else 4.0)
		col.add_child(UIStyle.label("Charge runway ≈ %s at %.2fs per action" % [UIStyle.fmt_duration(int(SummoningManager.charges.get(fid, 0)) * interval), interval], true, UITokens.FONT_MICRO))
		for synergy in familiar.get("synergies", []):
			col.add_child(UIStyle.label("Synergy with %s: mark %d required · %s" % [str(synergy.get("with", "")), int(synergy.get("mark_level", 1)), UIStyle.describe_modifier_table(synergy.get("effect", {}))], true, UITokens.FONT_MICRO))
		var refill := UIStyle.mini_button("Refill from Storage (%d)" % BankManager.get_count(str(familiar.get("tablet_item", ""))))
		refill.disabled = mark_level < 1 or BankManager.get_count(str(familiar.get("tablet_item", ""))) <= 0
		refill.pressed.connect(func(): SummoningManager.refill(str(fid)); rebuild())
		button_row.add_child(refill)
		col.add_child(button_row)
		box.add_child(card)

# ==========================================================================
#  Starreading (astrology): constellation stars bought with Stardust
# ==========================================================================

func _build_astrology() -> void:
	_build_star_comparison()
	var box := UIStyle.section("Constellations",
		"Studying yields Stardust; spent stars are permanent bonuses. Every star is a modifier source.")
	add_child(box)
	box.add_child(Widgets.key_value("Stardust", UIStyle.fmt(float(BankManager.get_count("stardust"))),
		UITokens.PURPLE, "Banked Stardust available to spend"))
	for cid in DataLoader.constellations.keys():
		var constellation: Dictionary = DataLoader.constellations[cid]
		if typeof(constellation) != TYPE_DICTIONARY:
			continue
		var level_needed: int = int(constellation.get("level_required", 1))
		var have_level: bool = PlayerData.get_level("astrology") >= level_needed
		var stardust: int = BankManager.get_count("stardust")
		var card := UIStyle.card()
		var col := UIStyle.vbox(UITokens.SP_2)
		card.add_child(col)
		var head := UIStyle.hbox(UITokens.SP_4)
		var title := UIStyle.title(str(constellation.get("name", cid)), UITokens.FONT_SUBHEAD)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var focus := str(constellation.get("skill_focus", ""))
		if focus != "":
			head.add_child(Widgets.badge(str(DataLoader.get_skill(focus).get("name", focus)),
				UITokens.TEAL, "Constellation focus"))
		head.add_child(Widgets.badge("Lv %d" % level_needed,
			UITokens.GREEN if have_level else UITokens.TEXT_MUTED, "Astrology level required"))
		col.add_child(head)
		if not have_level:
			col.add_child(UIStyle.colored_label("Requires Astrology level %d" % level_needed,
				UITokens.AMBER, UITokens.FONT_MICRO))
		var stars := UIStyle.hbox(UITokens.SP_3)
		var star_list: Variant = constellation.get("stars", [])
		if typeof(star_list) == TYPE_ARRAY:
			var index := 1
			for star in (star_list as Array):
				if typeof(star) != TYPE_DICTIONARY:
					continue
				var star_id := str((star as Dictionary).get("id", ""))
				var cost := int((star as Dictionary).get("cost", 0))
				if AstrologyManager.is_purchased(star_id):
					stars.add_child(Widgets.badge("★ %d ✓" % index, UITokens.PURPLE, "Star purchased — permanent"))
				else:
					var buy := UIStyle.mini_button("★ %d · %d" % [index, cost])
					var affordable: bool = have_level and stardust >= cost
					buy.disabled = not affordable
					buy.tooltip_text = "Buy this star" if affordable else \
						("Requires Astrology level %d" % level_needed if not have_level \
						else "Need %d Stardust (%d)" % [cost, stardust])
					var cid_copy: String = cid
					var sid_copy: String = star_id
					buy.pressed.connect(func():
						if AstrologyManager.buy_star(cid_copy, sid_copy):
							rebuild())
					stars.add_child(buy)
				index += 1
		col.add_child(stars)
		box.add_child(card)

# ==========================================================================
#  Wayfaring (agility): obstacle slots and pillars
# ==========================================================================

func _build_agility() -> void:
	var box := UIStyle.section("Course",
		"A slot only contributes once every earlier slot is filled. Rebuilding an obstacle cuts its cost by 4% (max 40%).")
	add_child(box)
	box.add_child(UIStyle.label("Active course: " + UIStyle.describe_modifier_table(AgilityManager.course_effects(AgilityManager.built)), true, UITokens.FONT_SMALL))
	var save := UIStyle.button("Save course blueprint")
	save.pressed.connect(func(): AgilityManager.save_blueprint("Course %d" % (AgilityManager.blueprints.size() + 1)); rebuild())
	box.add_child(save)
	for index in range(AgilityManager.blueprints.size()):
		var plan: Dictionary = AgilityManager.blueprint_preview(index)
		var load_button := UIStyle.button("%s · %s GP" % [AgilityManager.blueprints[index].name, UIStyle.fmt(float(plan.get("gp", 0)))])
		load_button.tooltip_text = str(plan.reason) + " " + UIStyle.describe_modifier_table(plan.get("effects", {}))
		load_button.disabled = not bool(plan.ok)
		load_button.pressed.connect(func(): AgilityManager.load_blueprint(index); rebuild())
		box.add_child(load_button)
	for slot in range(1, AgilityManager.SLOTS + 1):
		var row := HFlowContainer.new()
		var slot_label := UIStyle.label("Slot %d" % slot, false, UITokens.FONT_SMALL)
		slot_label.custom_minimum_size = Vector2(64, 0)
		row.add_child(slot_label)
		if AgilityManager.built.has(slot):
			var oid := str(AgilityManager.built[slot])
			var obstacle: Dictionary = AgilityManager.get_obstacle(oid)
			var built_label := UIStyle.label(str(obstacle.get("name", oid)), true, UITokens.FONT_SMALL)
			built_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			built_label.tooltip_text = UIStyle.describe_modifier_table(obstacle.get("effect", {}))
			row.add_child(built_label)
			var clear := UIStyle.mini_button("Clear")
			clear.tooltip_text = "Remove this obstacle (the cost of building is not refunded)"
			clear.pressed.connect(func():
				AgilityManager.clear_slot(slot)
				rebuild())
			row.add_child(clear)
		else:
			for option in AgilityManager.obstacles_for_slot(slot):
				if typeof(option) != TYPE_DICTIONARY:
					continue
				var opt_id := str((option as Dictionary).get("id", ""))
				var cost: Dictionary = AgilityManager.cost_for(opt_id)
				var gp_cost := float(cost.get("gp", 0))
				var level_ok: bool = PlayerData.get_level("agility") >= int((option as Dictionary).get("level_required", 1))
				var gp_ok: bool = PlayerData.gp >= gp_cost
				var build := UIStyle.mini_button("%s · %s" % [
					str((option as Dictionary).get("name", opt_id)), UIStyle.fmt(gp_cost)])
				build.disabled = not (level_ok and gp_ok)
				build.tooltip_text = UIStyle.describe_modifier_table((option as Dictionary).get("effect", {})) \
					if build.disabled == false else \
					("Requires Agility level %d" % int((option as Dictionary).get("level_required", 1)) if not level_ok \
					else "Need %s GP" % UIStyle.fmt(gp_cost))
				var target_id: String = opt_id
				var proposed: Dictionary = AgilityManager.built.duplicate()
				proposed[slot] = opt_id
				build.tooltip_text += "\nComplete proposed course: " + UIStyle.describe_modifier_table(AgilityManager.course_effects(proposed))
				build.disabled = build.disabled or not BankManager.can_afford(cost.items)
				build.pressed.connect(func():
					if AgilityManager.build(slot, target_id):
						rebuild())
				row.add_child(build)
		box.add_child(row)
	box.add_child(UIStyle.label(
		"Later slots stay dark until the slots before them are filled — the course is a chain, not a checklist.",
		true, UITokens.FONT_MICRO))
	_build_pillars(box)

func _build_pillars(parent: VBoxContainer) -> void:
	var pillars := UIStyle.section("Pillars",
		"One-off permanent bonuses. Buying a new pillar of the same kind replaces the old one.")
	parent.add_child(pillars)
	for oid in DataLoader.obstacles.keys():
		var p: Dictionary = DataLoader.obstacles[oid]
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var ptype := str((p as Dictionary).get("type", ""))
		if ptype == "":
			continue
		var owned: bool = (AgilityManager.pillar == oid) if ptype != "elite_pillar" \
			else (AgilityManager.elite_pillar == oid)
		var level_needed := int((p as Dictionary).get("level_required", 99))
		var have_level: bool = PlayerData.get_level("agility") >= level_needed
		var gp_cost := float((p as Dictionary).get("cost_gp", 0))
		var row := HFlowContainer.new()
		var name_label := UIStyle.label(str((p as Dictionary).get("name", oid)), false, UITokens.FONT_SMALL)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.tooltip_text = UIStyle.describe_modifier_table((p as Dictionary).get("effect", {}))
		row.add_child(name_label)
		row.add_child(Widgets.badge("Lv %d" % level_needed,
			UITokens.GREEN if have_level else UITokens.TEXT_MUTED, "Agility level required"))
		if owned:
			row.add_child(Widgets.badge("Built ✓", UITokens.GOLD, "This pillar is active"))
		else:
			var buy := UIStyle.mini_button("Build · %s" % UIStyle.fmt(gp_cost))
			buy.disabled = not have_level or PlayerData.gp < gp_cost
			buy.tooltip_text = "Permanent bonus until replaced" if not buy.disabled \
				else ("Requires Agility level %d" % level_needed if not have_level else "Need %s GP" % UIStyle.fmt(gp_cost))
			var pid: String = oid
			buy.pressed.connect(func():
				if AgilityManager.build_pillar(pid):
					rebuild())
			row.add_child(buy)
		pillars.add_child(row)

# ==========================================================================
#  Surveying (cartography): ships and hex travel
# ==========================================================================

func _build_cartography() -> void:
	var ships_box := UIStyle.section("Ships",
		"Each hull lowers the GP cost of hex travel; buy them in order.")
	add_child(ships_box)
	for ship_entry in CartographyManager.ships():
		if typeof(ship_entry) != TYPE_DICTIONARY:
			continue
		var sid := str((ship_entry as Dictionary).get("id", ""))
		var owned: bool = CartographyManager.ships_owned.has(sid)
		var active: bool = CartographyManager.ship == sid
		var row := UIStyle.hbox(UITokens.SP_4)
		var name_label := UIStyle.label(str((ship_entry as Dictionary).get("name", sid)), false, UITokens.FONT_SMALL)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.tooltip_text = str((ship_entry as Dictionary).get("description", ""))
		row.add_child(name_label)
		var pct := int((ship_entry as Dictionary).get("travel_cost_percent", 100))
		row.add_child(Widgets.badge("travel at %d%%" % pct,
			UITokens.TEAL if active else UITokens.TEXT_MUTED, "Percent of base travel cost"))
		if active:
			row.add_child(Widgets.badge("Sailing ✓", UITokens.GOLD, "Currently under the player"))
		elif owned:
			var sail := UIStyle.mini_button("Sail")
			sail.tooltip_text = "Make this hull the active one"
			var sid_owned: String = sid
			sail.pressed.connect(func():
				CartographyManager.set_ship(sid_owned)
				rebuild())
			row.add_child(sail)
		else:
			var cost := float((ship_entry as Dictionary).get("cost", 0))
			var check: Dictionary = CartographyManager.can_buy_ship(sid)
			var buy := UIStyle.mini_button("Buy · %s" % UIStyle.fmt(cost))
			buy.disabled = not bool(check["ok"])
			buy.tooltip_text = "Buy this hull" if bool(check["ok"]) else str(check["reason"])
			var sid_buy: String = sid
			buy.pressed.connect(func():
				if CartographyManager.buy_ship(sid_buy):
					rebuild())
			row.add_child(buy)
		ships_box.add_child(row)

	var routes := UIStyle.section("Frontier hexes",
		"Travel pays discovery XP once; timed Surveying activities pay training XP. Survey a revealed hex afterwards to claim its Point of Interest once.")
	add_child(routes)
	for hex_id in DataLoader.cartography_hexes.keys():
		var hex: Dictionary = DataLoader.cartography_hexes[hex_id]
		if typeof(hex) != TYPE_DICTIONARY:
			continue
		var is_discovered: bool = CartographyManager.is_discovered(hex_id)
		var is_surveyed: bool = CartographyManager.surveyed.has(hex_id)
		var raw_poi: Variant = hex.get("poi", {})
		var poi: Dictionary = raw_poi if raw_poi is Dictionary else {}
		var base_cost := float((hex as Dictionary).get("travel_cost", 0))
		var cost := base_cost * CartographyManager.travel_percent() / 100.0
		var row := UIStyle.hbox(UITokens.SP_4)
		var where := UIStyle.label("Hex (%s, %s)" % [
			str((hex as Dictionary).get("q", "?")), str((hex as Dictionary).get("r", "?"))],
			false, UITokens.FONT_SMALL)
		where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		where.tooltip_text = str(hex.get("id", hex_id))
		if not poi.is_empty():
			var reward: Dictionary = poi.get("reward", {})
			where.text += " · " + ("Supplies" if not reward.get("items", {}).is_empty() else "Treasure" if reward.has("gp") else "Permanent bonus")
			where.tooltip_text += " " + UIStyle.describe_modifier_table(poi.get("effect", {}))
		row.add_child(where)
		if is_surveyed:
			row.add_child(Widgets.badge("✓ %s" % str(poi.get("name", "Surveyed")), UITokens.GREEN,
				"Point of Interest claimed"))
		elif is_discovered and not poi.is_empty():
			var survey := UIStyle.mini_button("Survey")
			survey.tooltip_text = "Claim this Point of Interest and its permanent effect"
			var hid_survey: String = hex_id
			survey.pressed.connect(func():
				CartographyManager.survey(hid_survey)
				rebuild())
			row.add_child(survey)
		elif is_discovered:
			row.add_child(Widgets.badge("Visited", UITokens.TEXT_MUTED, "Revealed — nothing to survey here"))
		else:
			var afford: bool = PlayerData.gp >= cost
			var travel := UIStyle.mini_button("Travel · %s" % UIStyle.fmt(cost))
			travel.disabled = not afford
			travel.tooltip_text = "Reveal this hex" if afford else "Need %s GP (%s)" % [
				UIStyle.fmt(cost), UIStyle.fmt(PlayerData.gp)]
			var hid_travel: String = hex_id
			travel.pressed.connect(func():
				if CartographyManager.travel(hid_travel):
					rebuild())
			row.add_child(travel)
		routes.add_child(row)

# ==========================================================================
#  Excavation (archaeology): the museum — donations, tokens, stock
# ==========================================================================

func _build_archaeology() -> void:
	var box := UIStyle.section("Museum",
		"Donate catalogued artefacts for GP and Museum Tokens; tokens buy the museum's stock below.")
	add_child(box)
	box.add_child(Widgets.key_value("Museum Tokens", UIStyle.fmt(float(ArchaeologyManager.tokens)),
		UITokens.GOLD, "Earned per donation, spent on the museum's stock"))
	var unique: int = 0
	for id in ArchaeologyManager.DONATE_GP:
		if PlayerData.completion_log.get("items", {}).has(id): unique += 1
	box.add_child(Widgets.key_value("Unique artefact rarities discovered", "%d / %d" % [unique, ArchaeologyManager.DONATE_GP.size()]))
	box.add_child(Widgets.key_value("Duplicate donations", str(maxi(0, ArchaeologyManager.total_donated() - ArchaeologyManager.donated.size()))))
	box.add_child(Widgets.key_value("Donated", str(ArchaeologyManager.total_donated()),
		UITokens.TEAL, "Artefacts handed to the museum so far"))
	for artefact_id in ArchaeologyManager.DONATE_GP.keys():
		var item: Dictionary = DataLoader.get_item(artefact_id)
		var have := BankManager.get_count(artefact_id)
		var row := HFlowContainer.new()
		row.add_child(Widgets.item_icon(artefact_id))
		var name_label := UIStyle.label(str(item.get("name", artefact_id)), false, UITokens.FONT_SMALL)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.tooltip_text = str(Widgets.item_tooltip(artefact_id))
		row.add_child(name_label)
		row.add_child(Widgets.badge("in bank: %d" % have,
			UITokens.GREEN if have > 0 else UITokens.TEXT_MUTED, "Held artefacts of this rarity"))
		row.add_child(Widgets.badge("+%d GP · +%d tokens" % [
			int(ArchaeologyManager.DONATE_GP[artefact_id]),
			int(ArchaeologyManager.DONATE_TOKENS.get(artefact_id, 0))],
			UITokens.GOLD, "Donation reward"))
		var donate := UIStyle.mini_button("Donate")
		donate.disabled = have < 1
		donate.tooltip_text = "Donate one artefact" if have > 1 or have == 1 else "You hold none of these"
		var aid: String = artefact_id
		donate.pressed.connect(func():
			if ArchaeologyManager.donate(aid):
				rebuild())
		row.add_child(donate)
		box.add_child(row)

	var stock := UIStyle.section("Museum stock",
		"Everything here costs Museum Tokens — the slow currency of patient digging.")
	box.add_child(stock)
	for entry in ArchaeologyManager.museum_stock():
		var eid := str(entry.get("id", ""))
		var cost := int(entry.get("cost", 0))
		var affordable: bool = ArchaeologyManager.tokens >= cost
		var row := HFlowContainer.new()
		var name_label := UIStyle.label(str(entry.get("name", eid)), false, UITokens.FONT_SMALL)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.tooltip_text = str(entry.get("description", ""))
		row.add_child(name_label)
		row.add_child(Widgets.badge(_museum_grants(entry), UITokens.TEAL, "What this purchase gives"))
		row.add_child(Widgets.badge("%d tokens" % cost,
			UITokens.GOLD if affordable else UITokens.TEXT_MUTED, "Museum Token cost"))
		var buy := UIStyle.mini_button("Buy")
		buy.disabled = not affordable
		buy.tooltip_text = "Buy with Museum Tokens" if affordable else "Need %d Museum Tokens (%d)" % [
			cost, ArchaeologyManager.tokens]
		var eid_buy: String = eid
		buy.pressed.connect(func():
			if ArchaeologyManager.buy_museum(eid_buy):
				rebuild())
		row.add_child(buy)
		stock.add_child(row)

func _museum_grants(entry: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id in (entry.get("grant_items", {}) as Dictionary).keys():
		var qty := int((entry.get("grant_items", {}) as Dictionary)[item_id])
		parts.append("%d × %s" % [qty, str(DataLoader.get_item(str(item_id)).get("name", item_id))])
	if float(entry.get("gp", 0)) > 0.0:
		parts.append("%s GP" % UIStyle.fmt(float(entry["gp"])))
	return " · ".join(parts)

func _build_star_comparison() -> void:
	var box := UIStyle.section("Affordable stars · compare")
	add_child(box)
	box.add_child(Widgets.option_menu(["Lowest cost", "Constellation name"], func(i): _star_sort = i; rebuild(), _star_sort))
	var stars: Array = []
	for cid in DataLoader.constellations:
		for star in DataLoader.constellations[cid].get("stars", []):
			if bool(AstrologyManager.can_buy(str(cid), str(star.id)).ok): stars.append({"cid": str(cid), "star": star})
	stars.sort_custom(func(a, b): return int(a.star.cost) < int(b.star.cost) if _star_sort == 0 else str(a.cid) < str(b.cid))
	for entry in stars:
		var star: Dictionary = entry.star
		var effect: Dictionary = star.get("effect", {})
		var text: String = "%s · %d dust · %s" % [DataLoader.constellations[entry.cid].get("name", entry.cid), int(star.cost), UIStyle.describe_modifier_table(effect)]
		var downstream: Array[String] = []
		for sid in DataLoader.get_skill_ids():
			var best: Dictionary = {}
			var best_id: String = ""
			for action in DataLoader.get_skill_actions(str(sid)):
				if int(action.get("level_required", 1)) <= PlayerData.get_level(str(sid)):
					var rate: Dictionary = ActionEstimates.for_action(str(sid), str(action.id))
					if best.is_empty() or float(rate.xp_per_hour) > float(best.xp_per_hour): best = rate; best_id = str(action.id)
			if not best.is_empty():
				var after: Dictionary = ActionEstimates.for_action(str(sid), best_id, effect)
				if not is_equal_approx(float(after.xp_per_hour), float(best.xp_per_hour)) or not is_equal_approx(float(after.output_per_hour), float(best.output_per_hour)):
					downstream.append("%s: XP/h %.0f → %.0f; output/h %.0f → %.0f" % [str(DataLoader.get_skill(str(sid)).name), float(best.xp_per_hour), float(after.xp_per_hour), float(best.output_per_hour), float(after.output_per_hour)])
		var button := UIStyle.button("%s · %d dust" % [DataLoader.constellations[entry.cid].get("name", entry.cid), int(star.cost)], text + "\n" + "\n".join(downstream))
		button.pressed.connect(func(): AstrologyManager.buy_star(str(entry.cid), str(star.id)); rebuild())
		box.add_child(button)
	if stars.is_empty(): box.add_child(UIStyle.label("No affordable stars. Train Starreading or gather more Stardust.", true, UITokens.FONT_SMALL))
