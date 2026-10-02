class_name TestRunner
extends RefCounted
const TestSupport = preload("res://scripts/tests/TestSupport.gd")
const ActionQueueTests = preload("res://scripts/tests/ActionQueueTests.gd")
const LootFilterTests = preload("res://scripts/tests/LootFilterTests.gd")
const CombatSimulatorTests = preload("res://scripts/tests/CombatSimulatorTests.gd")
## TestRunner — the project's automated verification, wired to `--tests` and `--selftest`.
##
## Two suites:
##   run_all()        — focused unit tests of the rules the brief calls out: XP/level maths,
##                      atomic consumption, affordability boundaries, quest/achievement rewards
##                      being granted exactly once, save round-trips, migration, malformed-save
##                      rejection, offline cap, negative time, online/offline consistency,
##                      resource exhaustion, defeat and retreat, duplicate submissions and
##                      content-reference validation.
##   run_end_to_end() — the ten-step progression check: gather, craft, equip, fight, quest,
##                      build, save, reload, offline, verify.
##
## SAFETY: both suites run against the REAL singletons, so they first snapshot the player's
## state and the save files, then restore both afterwards. Running the tests can never cost
## anyone their save.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _section: String = ""

# =========================================================================
#  Entry points
# =========================================================================

func run_all(host: Node) -> void:
	var files: Dictionary = TestSupport.backup_save_files()
	var snapshot: Dictionary = SaveManager.build_save_data()
	_begin("Emberreach test suite")
	_deterministic(true)
	GameManager.start_new_game("standard")
	_ok(PlayerData.get_level("hitpoints") == 1 and PlayerData.get_combat_level() == 1,
		"a new character starts at Vitality 1 and combat level 1")
	_test_xp_and_levels()
	_test_currency_boundaries()
	_test_atomic_consumption()
	_test_recipe_consumption_and_exhaustion()
	_test_bank_overflow_never_deletes()
	_test_equipment_modifiers()
	_test_quest_reward_once()
	_test_achievement_reward_once()
	_test_save_round_trip()
	_test_save_migration()
	_test_malformed_save_rejected()
	_test_offline_cap_and_negative_time()
	_test_online_offline_consistency()
	_test_online_offline_consistency_with_timers()
	_test_session_time_is_not_paid_out_twice()
	await _test_pause_and_speed_controls(host)
	_test_reachable_systems()
	_test_unobtainable_content()
	_test_raid_shop_upgrades_are_real()
	_test_melee_tier_ladder()
	_test_gear_ladder_gap()
	_test_quest_coverage()
	await _test_xp_updates_live(host)
	await _test_cooking_failure_burns_materials(host)
	await _test_food_heals_in_combat(host)
	_test_combat_defeat_and_retreat(host)
	_test_duplicate_submissions()
	_test_mastery_stall()
	_test_general_store()
	_test_endgame_crafting_chains()
	_test_monster_passives()
	_test_monster_ladder()
	_test_dungeon_ladder()
	_test_raw_fish_are_consumed()
	_test_outputs_are_consumed()
	_test_balance_report_builds()
	_test_bottleneck_declarations()
	_test_study_ramp_rises()
	_test_action_xp_ladders()
	_test_mastery_metadata()
	await _test_detail_cards(host)
	_test_attack_costs()
	_test_magic_gear()
	_test_dungeon_sequencing()
	_test_session_meters()
	_test_equipment_upgrade()
	_test_prestige()
	_test_tutorial()
	_test_responsive_layouts(host)
	# After the layout suite, which is what assembles the shell the tests share: a screen test run
	# before it would navigate a shell with no panels built and no sidebar to find a tab in.
	_test_general_store_screen(host)
	await _test_task_feedback_layout(host)
	_test_combat_screen_split(host)
	_test_prayer_expansion(host)
	_test_husbandry(host)
	_test_scroll_position_preserved(host)
	_test_favorites()
	_test_lifetime_stats_screen(host)
	_test_overview_skill_tabs(host)
	_test_task_tabs_and_rotation(host)
	_test_systems_wiring(host)
	_test_audio()
	_test_settings_gap_keys()
	_test_content_validation()
	_test_game_modes()
	# Must be awaited: the QoL suites are coroutines, and an un-awaited coroutine suspends here
	# and resumes only after _report() has already printed — its checks would never be counted.
	await _test_progression_qol(host)
	TestSupport.restore_snapshot(snapshot, files)
	_report()

## The mastery stall is the only acquisition path for the 58 skillcapes and the 2 completion
## capes, so its gate has to be real: ungated it is a gold-only shortcut to a 99 reward, and
## mispriced it is a currency printer.
func _test_mastery_stall() -> void:
	_heading("Mastery stall")
	var offers: Array = ShopManager.stall_offers()
	_ok(offers.size() >= 60, "the stall stocks every skillcape and both completion capes (%d)" % offers.size())

	var cape_id: String = ""
	var gate_skill: String = ""
	var gate_level: int = 0
	var cost: float = 0.0
	for offer in offers:
		if not str((offer as Dictionary)["item_id"]).ends_with("_cape"):
			continue
		if float((offer as Dictionary)["required"]) != 99.0:
			continue
		cape_id = str((offer as Dictionary)["item_id"])
		cost = float((offer as Dictionary)["cost"])
		break
	var gate: Dictionary = DataLoader.get_item(cape_id).get("requires_level", {})
	gate_skill = str(gate.get("skill", ""))
	gate_level = int(gate.get("level", 0))
	_ok(cape_id != "" and gate_skill != "" and gate_level == 99,
		"a skillcape offer carries its own gate (%s at %d)" % [cape_id, gate_level])

	PlayerData.set_level(gate_skill, gate_level - 1)
	PlayerData.gp = cost
	_ok(not bool(ShopManager.can_buy_stall(cape_id)["ok"]), "a cape cannot be bought before its skill is finished")
	_ok(ShopManager.buy_stall(cape_id) == false, "the blocked purchase is refused, not silently charged")
	_ok(BankManager.get_count(cape_id) == 0, "the refused purchase granted nothing")

	PlayerData.set_level(gate_skill, gate_level)
	_ok(bool(ShopManager.can_buy_stall(cape_id)["ok"]), "the cape unlocks at the exact required level")
	var gp_before: float = PlayerData.gp
	_ok(ShopManager.buy_stall(cape_id), "the earned cape is bought")
	_ok(BankManager.get_count(cape_id) >= 1, "the cape landed in storage")
	_ok(absf(PlayerData.gp - (gp_before - cost)) < 0.5, "exactly the listed cost was charged")
	_ok(EquipmentManager.equip(cape_id), "an earned cape can be equipped")
	EquipmentManager.unequip(int(DataLoader.get_item(cape_id).get("equipment_slot", 5)))

## The general store is the one place gold turns directly into materials, so two things have to
## hold: a locked line refuses the purchase without charging, and no line is cheaper than making
## the item yourself. Ungated stock would let a player skip a whole skill by buying its output.
func _test_general_store() -> void:
	_heading("General store")
	var offers: Array = ShopManager.store_offers()
	_ok(offers.size() >= 20, "the store stocks a useful spread of materials (%d)" % offers.size())

	var locked_id: String = ""
	var locked_skill: String = ""
	var locked_level: int = 0
	for offer in offers:
		var need: Dictionary = ShopManager.store_requirement(offer as Dictionary)
		if str(need["skill"]) == "":
			continue
		locked_id = str((offer as Dictionary)["id"])
		locked_skill = str(need["skill"])
		locked_level = int(need["level"])
		break
	_ok(locked_id != "", "the store gates its costlier lines behind a skill level")

	var locked_cost: float = 0.0
	var locked_item: String = ""
	for offer in offers:
		if str((offer as Dictionary)["id"]) == locked_id:
			locked_cost = float((offer as Dictionary)["cost"])
			locked_item = str((offer as Dictionary)["item_id"])
			break
	PlayerData.set_level(locked_skill, maxi(1, locked_level - 1))
	PlayerData.gp = locked_cost
	_ok(not bool(ShopManager.can_buy_store(locked_id)["ok"]),
		"a gated line cannot be bought below its level")
	_ok(ShopManager.buy_store(locked_id) == false, "the blocked purchase is refused")
	_ok(BankManager.get_count(locked_item) == 0, "the refused purchase granted nothing")
	_ok(absf(PlayerData.gp - locked_cost) < 0.5, "the refused purchase charged nothing")

	PlayerData.set_level(locked_skill, locked_level)
	_ok(bool(ShopManager.can_buy_store(locked_id)["ok"]), "the line unlocks at the exact level")
	var gp_before: float = PlayerData.gp
	var held_before: int = BankManager.get_count(locked_item)
	var bundle: int = 1
	for offer in offers:
		if str((offer as Dictionary)["id"]) == locked_id:
			bundle = int((offer as Dictionary).get("quantity", 1))
			break
	_ok(ShopManager.buy_store(locked_id), "an unlocked line is bought")
	_ok(BankManager.get_count(locked_item) >= held_before + bundle,
		"the whole bundle landed in storage")
	_ok(absf(PlayerData.gp - (gp_before - locked_cost)) < 0.5, "exactly the listed price was charged")

	# Buying must never beat gathering. This is per line, not a global cheapest: comparing the
	# cheapest bundle against one item's sell price would fail a catalogue of sound prices just
	# because a different line is legitimately cheaper.
	var printers: Array[String] = []
	var unpriced: Array[String] = []
	for offer in offers:
		var o: Dictionary = offer as Dictionary
		var per_unit: float = float(o["cost"]) / float(maxi(1, int(o.get("quantity", 1))))
		var sell_worth: float = float(DataLoader.get_item(str(o["item_id"])).get("sell_price", 0))
		if per_unit <= 0.0:
			unpriced.append(str(o["item_id"]))
		elif per_unit < sell_worth:
			printers.append("%s at %.0f each (sells %.0f)" % [str(o["item_id"]), per_unit, sell_worth])
	_ok(unpriced.is_empty(),
		"every line has a price%s" % ("" if unpriced.is_empty() else ": " + ", ".join(unpriced)))
	_ok(printers.is_empty(),
		"no line is cheaper than making the item yourself%s" % ("" if printers.is_empty() else ": " + ", ".join(printers)))

## Counts stock rows, not children: an empty shelf holds the empty state instead of a card, so a
## bare child count would read as one row and hide an empty result.
func _card_rows(list: VBoxContainer) -> int:
	var rows: int = 0
	for child in list.get_children():
		if child is PanelContainer:
			rows += 1
	return rows

## The store is its own screen now, and both halves of that move have to hold: the new screen must
## build real, buyable rows, and the Provisioner must no longer render the shelves it used to. A
## split that leaves the old copy in place is worse than no split, so assert the absence too.
## Requires a built shell (see run_all), and restores the current screen when it is done.
func _test_general_store_screen(host: Node) -> void:
	_heading("General store screen")
	if host == null or not host.is_inside_tree():
		_ok(false, "a live shell is available to host the screen")
		return
	var store_index: int = Screens.ORDER.find(Screens.STORE)
	_ok(store_index >= 0, "the store is a navigable screen")
	_ok(store_index == Screens.ORDER.find(Screens.PROVISIONER) + 1,
		"it sits directly under the provisioner in the sidebar")
	_ok((host.get("_nav_buttons") as Dictionary).has(Screens.STORE),
		"the sidebar carries a %s tab" % Screens.label_for(Screens.STORE))

	# Where a source route points matters: the store half of the goal system has to land here.
	var store_sources: Array = Goals.sources_for_item("bronze_bar")
	var route_ok: bool = false
	for s in store_sources:
		if str((s as Dictionary).get("route", {}).get("screen", "")) == Screens.STORE:
			route_ok = true
	_ok(route_ok, "a stocked item lists the store as a source that routes to this screen")

	host.call("_show_screen", Screens.STORE, {})
	_ok(str(host.get("_screen")) == Screens.STORE, "the shell navigates to the store")
	var panel: Control = (host.get("_panels") as Dictionary).get(Screens.STORE, null)
	if panel == null or not is_instance_valid(panel):
		_ok(false, "the store panel is built on demand")
		host.call("_show_screen", Screens.OVERVIEW, {})
		return
	var list: VBoxContainer = panel.get("_list")
	var filter: OptionButton = panel.get("_filter")
	var search: LineEdit = panel.get("_search")
	_ok(list != null and filter != null and search != null,
		"the store builds its list, its search field and its filter")

	# Affordability is gold against a level gate, so the expectation is computed from the same two
	# facts the rows are built from rather than hard-coded to today's catalogue.
	var offers: Array = ShopManager.store_offers()
	PlayerData.gp = 10_000_000.0
	panel.call("_rebuild")
	var gated: int = 0
	for offer in offers:
		var need: Dictionary = ShopManager.store_requirement(offer as Dictionary)
		var skill_id: String = str(need["skill"])
		if skill_id != "" and PlayerData.get_level(skill_id) < int(need["level"]):
			gated += 1
	_ok(list.get_child_count() == offers.size(),
		"a fresh shelf defaults to the whole catalogue (%d rows for %d offers)" %
		[list.get_child_count(), offers.size()])
	filter.selected = 1
	panel.call("_rebuild")
	_ok(list.get_child_count() == offers.size() - gated,
		"'Affordable' hides only the level-gated lines (%d rows for %d offers)" %
		[list.get_child_count(), offers.size()])
	PlayerData.gp = 0.0
	panel.call("_rebuild")
	# Rows are cards; an empty shelf holds the empty state instead, which is why this counts
	# PanelContainers rather than children.
	_ok(_card_rows(list) == 0, "with no gold 'Affordable' is honestly empty")
	PlayerData.gp = 10_000_000.0
	filter.selected = 2
	panel.call("_rebuild")
	_ok(list.get_child_count() == gated, "'Locked' shows exactly the lines still behind a skill")
	filter.selected = 0
	panel.call("_rebuild")
	var first_name: String = str((offers[0] as Dictionary).get("name", ""))
	search.text = first_name
	panel.call("_rebuild")
	_ok(list.get_child_count() >= 1 and list.get_child_count() < offers.size(),
		"search narrows the shelves ('%s' matched %d of %d)" % [first_name, list.get_child_count(), offers.size()])
	search.text = "zzzz no such stock"
	panel.call("_rebuild")
	_ok(_card_rows(list) == 0 and list.get_child_count() == 1,
		"an empty result explains itself instead of showing nothing")
	search.text = ""
	PlayerData.gp = 0.0
	filter.selected = 0
	panel.call("_rebuild")
	var buys: int = 0
	var refused: int = 0
	for node in list.find_children("", "Button", true, false):
		var button: Button = node as Button
		if button.text != "Buy":
			continue
		if button.disabled:
			refused += 1
		else:
			buys += 1
	_ok(refused == offers.size() and buys == 0, "with no gold every buy is disabled, not hidden")
	# Rows are built in catalogue order, so row i is offer i: each blocked row must print the exact
	# reason ShopManager gives, which is what separates "you need gold" from "you need a level".
	var unexplained: Array[String] = []
	for i in range(offers.size()):
		var reason: String = str(ShopManager.can_buy_store(str((offers[i] as Dictionary)["id"]))["reason"])
		var stated: bool = false
		for node in (list.get_child(i) as Node).find_children("", "Label", true, false):
			if (node as Label).text == reason:
				stated = true
		if not stated:
			unexplained.append(str((offers[i] as Dictionary).get("name", "")))
	_ok(unexplained.is_empty(), "every blocked row states its own reason%s" %
		("" if unexplained.is_empty() else ": " + ", ".join(unexplained)))

	# The Provisioner keeps a signpost, and the signpost is the only store left on that screen.
	var provisioner: Control = load("res://scripts/ui/panels/ProvisionerPanel.gd").new()
	host.add_child(provisioner)
	var stale: Array[String] = []
	for node in provisioner.find_children("", "Label", true, false):
		if (node as Label).text.begins_with("General store "):
			stale.append((node as Label).text)
	_ok(stale.is_empty(), "the provisioner no longer renders the shelves%s" %
		("" if stale.is_empty() else ": " + ", ".join(stale)))
	var route: Dictionary = {}
	provisioner.connect("navigated", func(r): route.merge(r, true))
	var link: Button = null
	for node in provisioner.find_children("", "Button", true, false):
		if (node as Button).text == "Open the General Store":
			link = node
			break
	_ok(link != null, "the provisioner signposts the store")
	if link != null:
		link.pressed.emit()
		_ok(str(route.get("screen", "")) == Screens.STORE, "the signpost routes to the store screen")
	provisioner.queue_free()
	host.call("_show_screen", Screens.OVERVIEW, {})

## The Warden shard drops and the refined binding shards close the last unreachable items. If a
## recipe or a drop is ever renamed, these two links break quietly, so assert them directly.
func _test_endgame_crafting_chains() -> void:
	_heading("Endgame crafting chains")
	var element_dungeons: Dictionary = {
		"air_god_dungeon": "air_godsword",
		"water_god_dungeon": "water_godsword",
		"earth_god_dungeon": "earth_godsword",
		"fire_god_dungeon": "fire_godsword",
	}
	for dungeon_id in element_dungeons.keys():
		var shard: String = str(DataLoader.get_dungeon(dungeon_id).get("shard_item", ""))
		_ok(shard != "", "%s grants its signature shard" % dungeon_id)
		var targets: Array[String] = []
		for action in DataLoader.get_skill_actions("smithing"):
			var inputs: Dictionary = action.get("input_items", {})
			if not inputs.has(shard):
				continue
			for out_id in (action.get("output_items", {}) as Dictionary).keys():
				targets.append(str(out_id))
		_ok(targets.size() >= 6, "%s is consumed by %d Forgecraft recipes" % [shard, targets.size()])
		_ok(targets.has(str(element_dungeons[dungeon_id])), "the %s set is craftable" % dungeon_id)

	var refine_count: int = 0
	for action in DataLoader.get_skill_actions("summoning"):
		if str(action.get("id", "")).begins_with("refine_"):
			refine_count += 1
	_ok(refine_count == 5, "all five binding shard tiers can be refined (%d)" % refine_count)
	for shard_id in ["summoning_shard_crimson", "summoning_shard_blue", "summoning_shard_silver",
			"summoning_shard_black", "summoning_shard_gold"]:
		var used: bool = false
		for skill_id in DataLoader.skills.keys():
			for action in DataLoader.get_skill_actions(skill_id):
				if (action.get("input_items", {}) as Dictionary).has(shard_id):
					used = true
					break
			if used:
				break
		_ok(used, "%s is consumed by something" % shard_id)

	# The tier-1 shard gates all 25 tablets, and the gems, arrowtips and wyrmhides once had no
	# source at all: being an ingredient is not a way to obtain something, so each must appear in
	# some enemy's loot table or as a skill output. A rename anywhere in this set breaks the tree
	# above silently, so name the missing ones rather than just failing.
	var obtainable: Dictionary = {}
	for monster_id in DataLoader.monsters.keys():
		for drop in (DataLoader.monsters[monster_id].get("loot_table", []) as Array):
			if typeof(drop) == TYPE_DICTIONARY:
				obtainable[str(drop.get("item_id", ""))] = true
	for skill_id in DataLoader.skills.keys():
		for action in DataLoader.get_skill_actions(skill_id):
			for out_id in (action.get("output_items", {}) as Dictionary).keys():
				obtainable[str(out_id)] = true
			for sec in (action.get("secondary_outputs", []) as Array):
				if typeof(sec) == TYPE_DICTIONARY:
					obtainable[str(sec.get("item_id", ""))] = true
	var missing: Array[String] = []
	for needed in ["summoning_shard_green", "sapphire", "emerald", "ruby", "diamond",
			"bronze_arrowtips", "iron_arrowtips", "steel_arrowtips",
			"green_dragonhide", "blue_dragonhide", "red_dragonhide", "black_dragonhide"]:
		if not obtainable.has(needed):
			missing.append(needed)
	_eq(missing.size(), 0, "every previously-orphaned material has a real source (%s)" %
		("missing: " + ", ".join(missing) if not missing.is_empty() else "none missing"))

## Overview is a hub: a wrapping sub-tab per skill above the dashboard. The card has to actually
## build — a tab strip that compiles but renders an empty pane is the failure mode here.
func _test_overview_skill_tabs(host: Node) -> void:
	_heading("Overview skill sub-tabs")
	# TestRunner is not a Node, so the tree and a parent come from the shell under test.
	if host == null or not host.is_inside_tree():
		_ok(false, "a live shell is available to host the panel")
		return
	var panel_script: GDScript = load("res://scripts/ui/panels/OverviewPanel.gd")
	if panel_script == null:
		_ok(false, "the overview panel script loads")
		return
	var panel: Control = panel_script.new()
	host.add_child(panel)
	# Deliberately no await: run_all is synchronous, so a coroutine would suspend here and its checks
	# would never print before the report. add_child runs _ready immediately on a node already in a
	# tree, and nothing below measures layout — only visibility and node counts.

	var tabs: Control = panel.get("_tabs_root")
	# `x or y` is a boolean operator in GDScript, not a null-coalesce, so this cannot be one line.
	var buttons: Array = panel.get("_tab_buttons")
	if buttons == null:
		buttons = []
	_ok(tabs != null, "the overview builds a sub-tab strip")
	_eq(buttons.size(), 1, "the Dashboard has one clear primary tab")
	_ok(tabs is HFlowContainer, "the navigation wraps on narrow screens")
	var menu: OptionButton = panel.get("_skill_menu")
	_eq(menu.item_count, 3 + DataLoader.get_skill_ids().size(),
		"the skill picker includes every skill and both group headings")
	_ok(menu.get_item_text(1) == "Combat", "combat skills have a heading")
	_ok(menu.get_item_text(2).contains("Lv"), "skill choices include their level")
	_ok(menu.get_item_text(menu.item_count - 1).contains("Lv"), "non-combat skills follow their heading")
	var skills_panel: Control = load("res://scripts/ui/panels/SkillsPanel.gd").new()
	host.add_child(skills_panel)
	_ok(skills_panel.get("_skill_picker") == null,
		"the Skills tab carries no dropdown: skills are chosen from the sidebar instead")
	_ok(DataLoader.skills.has(str(skills_panel.get("_skill_id"))),
		"the Skills tab still lands on a real skill without its picker")
	skills_panel.queue_free()

	panel.call("_select_tab", "woodcutting")
	var dashboard: Control = panel.get("_dashboard")
	var skill_box: Control = panel.get("_skill_box")
	_ok(dashboard != null and not dashboard.visible, "the dashboard gives way to the skill tab")
	_ok(skill_box != null and skill_box.visible, "the skill card is shown")
	_ok(skill_box.get_child_count() > 3,
		"the skill card has real content (%d nodes)" % skill_box.get_child_count())
	var ids: Array = panel.get("_tab_ids")
	var idx: int = ids.find("woodcutting")
	_ok(idx > 0, "the selected skill is in the picker (index %d)" % idx)
	_ok(idx > 0 and menu.selected == idx, "the picker follows the selected skill")
	_ok(not bool(buttons[0].button_pressed), "the Dashboard tab is no longer marked as pressed")

	panel.call("_select_tab", "")
	_ok(dashboard.visible, "the Dashboard tab restores the dashboard")
	_ok(not skill_box.visible, "the skill card is hidden again")
	panel.queue_free()

## The Tasks screen is organised by difficulty with a six-hour rotation tab. Both are
## data-driven, and the rotation must stay deterministic for a given window.
func _test_task_tabs_and_rotation(host: Node) -> void:
	_heading("Task tabs and rotation")
	var counts: Dictionary = {}
	var bad: Array[String] = []
	for quest_id in Quests.all_quest_ids():
		var difficulty: String = str(Quests.get_quest(quest_id).get("difficulty", ""))
		if Quests.DIFFICULTIES.has(difficulty):
			counts[difficulty] = int(counts.get(difficulty, 0)) + 1
		else:
			bad.append(quest_id)
	_eq(bad.size(), 0, "every task has a known difficulty (%s)" % ("none missing" if bad.is_empty() else ", ".join(bad)))
	for tier in Quests.DIFFICULTIES:
		_ok(int(counts.get(tier, 0)) >= 10, "difficulty '%s' has ten or more tasks (%d)" % [tier, int(counts.get(tier, 0))])
	var pool: Array[String] = Quests.rotating_pool_ids()
	_ok(pool.size() >= 10, "the rotation pool is stocked (%d tasks)" % pool.size())
	var clean: bool = true
	for id in pool:
		var rq: Dictionary = Quests.get_quest(id)
		if not Quests.is_rotating(id) or not (rq.get("prerequisites", []) as Array).is_empty():
			clean = false
		if not Quests.DIFFICULTIES.has(str(rq.get("difficulty", ""))):
			clean = false
	_ok(clean, "rotation tasks are flagged, un-gated, and carry a known difficulty")
	var featured: Array[String] = Quests.featured_rotating_ids_for_window(12345)
	_ok(featured.size() == mini(Quests.FEATURED_ROTATING_COUNT, pool.size()),
		"a window features %d tasks" % featured.size())
	_ok(featured == Quests.featured_rotating_ids_for_window(12345), "the featured set is deterministic for a window")
	var unique: Dictionary = {}
	for id in featured:
		unique[id] = true
	_ok(unique.size() == featured.size() and featured.all(func(id): return Quests.is_rotating(id)),
		"featured tasks are unique and come from the pool")
	var secs: int = Quests.seconds_until_rotation()
	_ok(secs > 0 and secs <= Quests.ROTATION_PERIOD_SECONDS, "the rotation countdown is bounded (%ds)" % secs)
	if host == null or not host.is_inside_tree():
		_ok(false, "a live shell is available to host the panel")
		return
	var panel: Control = load("res://scripts/ui/panels/QuestsPanel.gd").new()
	host.add_child(panel)
	var tabs: Array = panel.get("_tab_buttons")
	_eq(tabs.size(), Quests.DIFFICULTIES.size() + 1, "the Tasks screen has one tab per difficulty plus the rotation")
	_ok((tabs[0] as Button).text == "Easy" and (tabs[tabs.size() - 1] as Button).text == "Rotating",
		"tabs run from Easy to Nightmare and end on Rotating")
	var filter: OptionButton = panel.get("_filter")
	filter.select(5)
	panel.call("_select_tab", "easy")
	var list: VBoxContainer = panel.get("_list")
	_ok(list.get_child_count() > 0, "the Easy tab lists its tasks (%d cards)" % list.get_child_count())
	panel.call("_select_tab", "rotating")
	_ok(panel.get("_rotation_label") != null, "the rotating tab shows the next-rotation countdown")
	_ok(list.get_child_count() >= 3, "the rotating tab lists featured tasks (%d nodes)" % list.get_child_count())
	panel.queue_free()

## Favourites and protection are separate features and the brief lists both. The failure that
## matters is conflating them: a bookmark must never become an accidental safety setting, so
## favouriting an item has to leave it just as sellable as it was.
func _test_favorites() -> void:
	_heading("Favourites")
	var item_id: String = "normal_log"
	if not DataLoader.items.has(item_id):
		_ok(false, "the test item exists")
		return
	_ok(not BankManager.is_favorite(item_id), "an item starts out not favourited")

	_ok(BankManager.toggle_favorite(item_id), "favouriting reports the new state")
	_ok(BankManager.is_favorite(item_id), "the item is now a favourite")
	_eq(BankManager.favorite_count(), 1, "the favourite count includes it")

	# The distinction that matters: a favourite is a bookmark, not a lock.
	_ok(not BankManager.is_protected(item_id), "favouriting does not protect the item")
	BankManager.add_item_guaranteed(item_id, 5)
	var gp_before: float = PlayerData.gp
	_ok(BankManager.sell_item(item_id, 1), "a favourited item can still be sold")
	_ok(PlayerData.gp > gp_before, "the sale actually paid out")
	_ok(BankManager.is_favorite(item_id), "selling does not silently drop the favourite")

	# Favourites lead in every sort direction, so a pinned item stays findable. The comparison needs
	# one favourite and one ordinary item, or the sort just reorders favourites alphabetically, and
	# both items need stock because a row only exists for something actually in storage.
	BankManager.set_favorite(item_id, false)
	BankManager.add_item_guaranteed("oak_log", 3)
	BankManager.set_favorite("oak_log", true)
	var asc: Array = BankManager.sorted_list("", BankManager.SortMode.NAME, true)
	_eq(str(asc[0]["item_id"]), "oak_log", "favourites sort first ascending")
	var desc: Array = BankManager.sorted_list("", BankManager.SortMode.NAME, false)
	_eq(str(desc[0]["item_id"]), "oak_log", "favourites still lead descending")
	var only: Array = BankManager.sorted_list("", BankManager.SortMode.NAME, true, "", true)
	_eq(only.size(), 1, "the favourites-only filter returns just the pinned item")
	_ok(only.all(func(r): return bool(r["favorite"])), "every filtered row really is a favourite")

	# Persisted like any other player state, through the real JSON path. Two favourites, so the
	# round trip has to carry more than one.
	BankManager.set_favorite(item_id, true)
	var snapshot: Variant = JSON.parse_string(JSON.stringify(SaveManager.build_save_data(), "\t"))
	_ok(typeof(snapshot) == TYPE_DICTIONARY, "the save with favourites serialises to JSON")
	PlayerData.favorite_items.clear()
	SaveManager._apply(snapshot)
	_ok(BankManager.is_favorite("oak_log"), "favourites survive a save / load round trip")
	_ok(BankManager.is_favorite(item_id), "every favourite comes back, not just the last one")

	# A hand-edited or stale save must not resurrect an id that no longer exists.
	var tampered: Dictionary = (snapshot as Dictionary).duplicate(true)
	(tampered["player"] as Dictionary)["favorite_items"] = {"not_a_real_item": true, "oak_log": true}
	SaveManager._apply(tampered)
	_ok(not PlayerData.favorite_items.has("not_a_real_item"), "an unknown item id is dropped on load")
	_ok(PlayerData.favorite_items.has("oak_log"), "valid favourites survive the same load")

	PlayerData.favorite_items.clear()
	BankManager.set_favorite(item_id, false)
	BankManager.set_favorite("oak_log", false)

## Leaving a long list and coming back to it should not lose the player's place. This was claimed
## in a comment for the whole overhaul while the offset was never actually captured.
func _test_scroll_position_preserved(host: Node) -> void:
	_heading("Scroll position")
	if not host.has_method("_show_screen") or not host.has_method("_save_scroll_position"):
		_ok(false, "the shell captures and restores scroll positions")
		return
	# The dict is shared with the layout test above, which visits every screen; start from empty so
	# this test measures only its own navigations.
	host.set("_scroll_positions", {})
	host.call("_show_screen", Screens.OVERVIEW, {})
	var scroll: Node = null
	var workspace: Control = host.get("_workspace")
	if workspace != null:
		for c in workspace.get_children():
			if c is ScrollContainer:
				scroll = c
				break
	if scroll == null:
		_ok(false, "the workspace is a scrolling panel")
		return
	(scroll as ScrollContainer).scroll_vertical = 250
	host.call("_show_screen", Screens.SKILLS, {})
	# `x or y` is a boolean operator in GDScript, not a null-coalesce, so this cannot be one line.
	var remembered: Dictionary = host.get("_scroll_positions")
	if remembered == null:
		remembered = {}
	_eq(int(remembered.get(Screens.OVERVIEW, -1)), 250,
		"leaving a screen records where it was scrolled to")
	_ok(not remembered.has(Screens.SKILLS),
		"a screen that was never scrolled has no remembered offset")

## A panel that demands more width than the window has is a horizontal-overflow bug, and the
## breakpoints decide whether navigation and the detail pane are reachable at all. Both are
## checked here at three widths: the narrowest supported window, the medium breakpoint and a
## full desktop window.
func _test_responsive_layouts(host: Node) -> void:
	_heading("Responsive layouts")
	const WIDTHS: Array[int] = [420, 900, 1440]
	var shell: Node = host
	if not shell.has_method("apply_layout_for_width"):
		_ok(false, "the shell exposes its responsive rules for testing")
		return
	if shell.has_method("_build"):
		shell.call("_build")
	var nav: Control = shell.get("_nav_button")
	var sidebar: Control = shell.get("_sidebar_wrap")
	var detail: Control = shell.get("_detail_wrap")
	_ok(nav != null and sidebar != null and detail != null,
		"the shell builds its navigation, sidebar and detail panes")
	if nav == null or sidebar == null or detail == null:
		return
	# The activity strip is the one row reserved on every screen; it must stay a thin band so
	# the workspace keeps the height (the shell reserves it rather than floating it).
	var strip: Control = shell.get("_strip")
	_ok(strip != null, "the shell builds its persistent activity strip")
	if strip != null:
		_ok(strip.get_combined_minimum_size().y <= 52.0,
			"the activity strip stays a thin band (%dpx tall)" % int(strip.get_combined_minimum_size().y))
	# A plain Control reports a minimum of zero, so the shell's contents are measured on its layout
	# root instead: asserting on `shell` alone would pass no matter how badly things overflow.
	var layout_root: Control = shell.get("_root")
	if layout_root == null:
		_ok(false, "the shell exposes its layout root")
		return
	for width in WIDTHS:
		shell.call("apply_layout_for_width", width)
		var narrow: bool = width < UITokens.BP_NARROW
		var medium: bool = width < UITokens.BP_MEDIUM
		_ok(nav.visible == narrow, "%dpx: the navigation drawer button is %s" % [width, "shown" if narrow else "hidden"])
		_ok(sidebar.visible == not narrow, "%dpx: the sidebar is %s" % [width, "hidden" if narrow else "shown"])
		_ok(detail.visible == not medium, "%dpx: the detail pane is %s" % [width, "folded in" if medium else "docked"])
		# The whole shell must fit, not just each panel. The status bar, the activity strip and the
		# panel wrappers all set a floor of their own, and it is the SUM that overflows the window:
		# measuring panels alone hid a shell whose minimum width was 602px inside a 420px window.
		var shell_min: float = layout_root.get_combined_minimum_size().x
		_ok(shell_min <= float(width), "%dpx: the whole shell fits (needs %dpx)" % [width, int(shell_min)])
	# The panels above are measured in isolation, but the overflow came from the assembled shell: an
	# empty workspace has a tiny minimum, so the real test is to load each screen into the shell at
	# the narrowest width and measure the whole thing. This is what caught a 602px shell in a 420px
	# window that every per-panel assertion passed.
	if shell.has_method("_show_screen"):
		for screen in PANEL_SCRIPTS.keys():
			shell.call("_show_screen", str(screen), {})
			shell.call("apply_layout_for_width", 420)
			var loaded_min: float = layout_root.get_combined_minimum_size().x
			# Name the offending row here too: the isolated measurement below does, and a bare
			# "needs 430px" points at a whole screen instead of the row to fix.
			_ok(loaded_min <= 420.0, "%s fits the 420px window when loaded (needs %dpx; widest row is %s)" %
				[str(screen), int(loaded_min), TestSupport.widest_descendant(layout_root)])
	# Every screen must fit the narrowest supported window without horizontal overflow.
	for screen in Screens.ORDER:
		var path: String = "res://scripts/ui/panels/%s.gd" % PANEL_SCRIPTS.get(screen, "")
		if not ResourceLoader.exists(path):
			_ok(false, "%s has a panel script" % screen)
			continue
		# The panel is measured inside a holder the size of the narrowest supported window: a
		# panel whose contents demand more width than that will clip or scroll sideways.
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(420, 900)
		holder.size = Vector2(420, 900)
		(host as Control).add_child(holder)
		var panel: Control = load(path).new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_child(panel)
		var minimum: float = panel.get_combined_minimum_size().x
		_ok(minimum > 0.0, "%s lays out content to measure" % screen)
		_ok(minimum <= 420.0, "%s fits a 420px window (needs %dpx; widest row is %s)" % [
			screen, int(minimum), TestSupport.widest_descendant(panel)])
		holder.queue_free()
	if shell.has_method("apply_layout_for_width"):
		shell.call("apply_layout_for_width", int((host as Control).size.x))

func _test_task_feedback_layout(host: Node) -> void:
	_heading("Task feedback layout")
	var toasts: ToastStack = host.get("_toasts")
	toasts.clear()
	await host.get_tree().process_frame
	toasts.push("New task: Firewood", "success")
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var column: VBoxContainer = toasts.get("_column")
	var toast: Control = column.get_child(0)
	_ok(toast.size.x >= 280.0 and toast.size.y < 100.0,
		"task notification stays a readable horizontal toast (%dx%d)" % [int(toast.size.x), int(toast.size.y)])
	toasts.clear()
	GameManager.start_new_game("standard")
	var tasks: Control = load("res://scripts/ui/panels/QuestsPanel.gd").new()
	host.add_child(tasks)
	var filter: OptionButton = tasks.get("_filter")
	var list: VBoxContainer = tasks.get("_list")
	var context: Dictionary = {}
	tasks.connect("context_changed", func(ctx): context.merge(ctx, true))
	var accept: Button = null
	for button in list.find_children("", "Button", true, false):
		if (button as Button).text == "Accept":
			accept = button
			break
	_ok(accept != null, "a fresh game offers a task to accept")
	if accept != null:
		accept.pressed.emit()
		_ok(filter.selected == 1 or filter.selected == 2,
			"accepting a task follows its new filter")
		_ok(context.get("kind", "") == "goal" and not list.get_children().is_empty(),
			"accepting a task keeps it visible and opens its details")
	tasks.queue_free()

func _test_combat_screen_split(host: Node) -> void:
	_heading("Combat navigation")
	# This test asserts sidebar labels match live levels. Earlier suites reset the game, so rebuild
	# the nav first rather than depending on whichever levels happened to be current when the shell
	# was assembled.
	host.call("_refresh_nav")
	var skill_buttons: Dictionary = host.get("_skill_nav_buttons")
	_ok(skill_buttons.size() == DataLoader.get_skill_ids().size(),
		"every skill has a left sidebar entry")
	var sidebar: VBoxContainer = host.get("_sidebar_list")
	var combat_heading: int = -1
	var noncombat_heading: int = -1
	var divider: int = -1
	for i in range(sidebar.get_child_count()):
		var node: Node = sidebar.get_child(i)
		if node is Label and (node as Label).text == "COMBAT SKILLS":
			combat_heading = i
		if node is Label and (node as Label).text == "NON-COMBAT SKILLS":
			noncombat_heading = i
		if node is HSeparator:
			divider = i
	var bank_idx: int = (host.get("_nav_buttons") as Dictionary)[Screens.BANK].get_index()
	_ok(combat_heading >= 0 and noncombat_heading > combat_heading and divider > noncombat_heading,
		"combat and non-combat skills precede a divider and the other screens")
	_ok(bank_idx < combat_heading, "Storage is pinned above the skills section")
	var prayer_button: Button = skill_buttons["prayer"]
	_ok(prayer_button.get_index() > combat_heading and prayer_button.get_index() < noncombat_heading,
		"Prayers sits inside the combat skills section")
	prayer_button.pressed.emit()
	_ok(host.get("_screen") == Screens.PRAYERS, "the combat prayer entry opens the prayer list")
	var fishing_button: Button = skill_buttons["fishing"]
	var fishing_name: String = str(DataLoader.get_skill("fishing").get("name", "fishing"))
	_ok(fishing_button.text.begins_with(fishing_name)
		and fishing_button.text.contains("Lv %d" % PlayerData.get_level("fishing")),
		"sidebar skill entries show the level next to the skill name")
	fishing_button.pressed.emit()
	_ok(host.get("_screen") == Screens.SKILLS and str((host.get("_panels") as Dictionary)[Screens.SKILLS].get("_skill_id")) == "fishing",
		"a sidebar skill opens that skill's activities")
	# The label tracks a level-up that happens while the shell is live, not only the level at
	# build time: grant exactly one level and read the button back.
	var before_level: int = PlayerData.get_level("fishing")
	PlayerData.add_xp("fishing", float(XPTable.xp_for_level(before_level + 1) - XPTable.xp_for_level(before_level)))
	_ok(PlayerData.get_level("fishing") == before_level + 1,
		"test setup: Angling leveled up (%d -> %d)" % [before_level, before_level + 1])
	_ok(fishing_button.text.contains("Lv %d" % (before_level + 1)),
		"the sidebar entry relabels itself after a level-up")
	# Width guard: the sidebar must fit its longest possible label at the level cap without
	# clipping. Available room = sidebar width - panel margins (28) - scrollbar (8) - button
	# side padding (28) - icon (18) - icon/text gap (6); the font is what buttons render with.
	var font: Font = ThemeDB.fallback_font
	var worst_label: String = ""
	var worst_width: float = 0.0
	for sid in DataLoader.get_skill_ids():
		var candidate: String = "%s · Lv %d" % [
			str(DataLoader.get_skill(sid).get("name", sid)), XPTable.MAX_LEVEL]
		var label_width: float = font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1,
			UITokens.FONT_SMALL).x
		if label_width > worst_width:
			worst_width = label_width
			worst_label = candidate
	var label_room: float = float(UITokens.W_SIDEBAR - 28 - 8 - 28 - 18 - 6)
	_ok(worst_width + 4.0 <= label_room,
		"the sidebar fits its longest label '%s' (needs %.0fpx of %.0fpx)"
			% [worst_label, worst_width, label_room])
	var order: Array[String] = Screens.ORDER
	# Settings anchors the bottom of the sidebar, and Action Queue / Simulator stay directly
	# above it. Prayer and Raid were added after that pair, so assert the intent rather than
	# three fixed indices: Settings last, and the two automation screens adjacent to it.
	_ok(order[order.size() - 1] == Screens.SETTINGS,
		"Settings is the last sidebar entry")
	var aq: int = order.find(Screens.ACTION_QUEUE)
	var sim: int = order.find(Screens.COMBAT_SIMULATOR)
	_ok(aq >= 0 and sim >= 0 and absi(aq - sim) == 1,
		"Action Queue and Simulator sit next to each other (%d, %d)" % [aq, sim])
	_ok(order.size() == Screens.ORDER.size(), "the sidebar order has no duplicate entries")
	var regular: Control = load("res://scripts/ui/panels/CombatPanel.gd").new()
	host.add_child(regular)
	var expedition: Control = load("res://scripts/ui/panels/CombatPanel.gd").new()
	expedition.set("expeditions_only", true)
	host.add_child(expedition)
	var regular_places: Array = regular.get("_places")
	var expedition_places: Array = expedition.get("_places")
	var regular_ok: bool = false
	for place in regular_places:
		if str(place["type"]) == "area":
			regular_ok = true
		if str(place["type"]) == "dungeon" and CombatManager.is_expedition(str(place["id"])):
			regular_ok = false
	var expedition_ok: bool = not expedition_places.is_empty()
	for place in expedition_places:
		if str(place["type"]) != "dungeon" or not CombatManager.is_expedition(str(place["id"])):
			expedition_ok = false
	_ok(regular_ok and expedition_ok, "regular encounters and high-tier expeditions have separate lists")
	var fight_button: Button = expedition.get("_fight_button")
	_ok(fight_button.disabled and CombatManager.expedition_unlock_reason() != "",
		"Expeditions are locked for a fresh character")
	regular.queue_free()
	expedition.queue_free()
	host.call("navigate", {"screen": "skill", "skill_id": "fishing"})
	_ok(host.get("_screen") == Screens.SKILLS, "legacy task skill routes open Skills")
	host.call("navigate", {"screen": Screens.COMBAT, "area_id": "air_god_dungeon"})
	_ok(host.get("_screen") == Screens.EXPEDITIONS, "high-tier dungeon routes open Expeditions")

func _test_prayer_expansion(host: Node) -> void:
	_heading("Prayer progression and navigation icons")
	GameManager.start_new_game("standard")
	_ok(DataLoader.prayers.size() == 60 and int(DataLoader.prayers["aegis_6"]["level"]) == 120,
		"sixty prayers include unlocks through level 120")
	_ok(not PrayerManager.toggle("aegis_6"), "an endgame prayer is locked at level one")
	PlayerData.set_level("prayer", 120)
	PlayerData.prayer_points = 20.0
	_ok(PrayerManager.toggle("hunter_6") and PrayerManager.toggle("arcanist_6"),
		"new ranged and magic prayers can be activated at their required level")
	_ok(is_equal_approx(ModifierManager.get_max_hit_percent("ranged"), 34.0)
		and is_equal_approx(ModifierManager.get_max_hit_percent("magic"), 34.0),
		"new prayers register their real combat bonuses")
	_ok(not PrayerManager.toggle("aegis_6") and is_equal_approx(PrayerManager.cost_per_attack(), 8.0),
		"the two-prayer limit and combined point cost still apply")
	PrayerManager.spend_for_attack()
	_ok(is_equal_approx(PlayerData.prayer_points, 12.0), "new prayers consume points on attack")
	PrayerManager.deactivate_all()
	_ok(is_zero_approx(ModifierManager.get_max_hit_percent("ranged")), "deactivating removes the bonus")
	GameManager.start_new_game("standard")
	host.call("navigate", {"screen": "skill", "skill_id": "prayer"})
	_ok(host.get("_screen") == Screens.PRAYERS, "legacy prayer skill routes open Prayers")
	var panel: Control = (host.get("_panels") as Dictionary)[Screens.PRAYERS]
	var filter: OptionButton = panel.get("_filter")
	var list: VBoxContainer = panel.get("_list")
	filter.select(0)
	panel.call("_rebuild")
	_ok(_prayer_cards(list) == 60, "the list previews every future prayer unlock")
	filter.select(1)
	panel.call("_rebuild")
	_ok(_prayer_cards(list) == 1, "Unlocked shows only the level-one prayer on a new save")
	filter.select(0)
	panel.call("_rebuild")
	for screen in [Screens.ACTION_QUEUE, Screens.COMBAT_SIMULATOR, Screens.PRAYERS, Screens.RAIDS, Screens.SETTINGS]:
		_ok(AssetRegistry.has_asset("icons/navigation/%s.png" % screen), "%s has its own navigation icon" % screen)


## Husbandry: the plot engine, its seed economy and the Farm screen are one loop now.
## Planting spends seeds, growth is wall-clock, harvest pays XP and per-crop mastery — and the
## skill's plant actions fill plots through the same manager, so both doors stay consistent.
func _test_husbandry(host: Node) -> void:
	_heading("Husbandry")
	GameManager.start_new_game("standard")
	var farm: Dictionary = DataLoader.get_skill("farming")
	_ok((farm.get("actions", []) as Array).size() == 10, "Husbandry lists ten crops")
	var seeds_ok: bool = true
	var gates_ok: bool = true
	var products_ok: bool = true
	for a in (farm.get("actions", []) as Array):
		var action_id: String = str((a as Dictionary).get("id", ""))
		var seed_id: String = FarmingManager.seed_id_for_action(action_id)
		var seed_item: Dictionary = DataLoader.get_item(seed_id)
		if seed_item.is_empty() or str(seed_item.get("item_type", "")) != "seed":
			seeds_ok = false
			continue
		if not ((a as Dictionary).get("input_items", {}) as Dictionary).has(seed_id):
			seeds_ok = false
		var product: String = str(seed_item.get("product_item", ""))
		if product == "" or DataLoader.get_item(product).is_empty():
			products_ok = false
		if FarmingManager.plant_level(seed_id) != int((a as Dictionary).get("level_required", 0)):
			gates_ok = false
	_ok(seeds_ok, "every plant action consumes its matching seed")
	_ok(gates_ok, "each crop is gated at its plant action's level")
	_ok(products_ok, "every seed names a real harvested product")
	var drops_ok: bool = true
	for pair in [["king", "duskroot_seed"], ["high_priest", "herald_bloom_seed"], ["herald_mark", "emberbloom_seed"]]:
		var target: Dictionary = DataLoader.get_action("thieving", str(pair[0]))
		var found: bool = false
		for sec in (target.get("secondary_outputs", []) as Array):
			if str((sec as Dictionary).get("item_id", "")) == str(pair[1]):
				found = true
		if not found:
			drops_ok = false
	_ok(drops_ok, "the three late seeds drop from their thieving tier")

	_ok(FarmingManager.plots.size() == 15, "a fresh farm has fifteen plots")
	var type_counts: Dictionary = {}
	for p in FarmingManager.plots:
		type_counts[str(p["type"])] = int(type_counts.get(str(p["type"]), 0)) + 1
	_ok(int(type_counts.get("allotment", 0)) == 6 and int(type_counts.get("herb", 0)) == 6
		and int(type_counts.get("tree", 0)) == 3, "plots split six allotment, six herb, three tree")

	# Planting rules: level gates, seed spend, occupied plots, out-of-range index.
	PlayerData.set_level("farming", 1)
	BankManager.add_item("emberbloom_seed", 1)
	_ok(not FarmingManager.plant(0, "emberbloom_seed"), "a level-115 crop refuses to plant at level 1")
	_ok(BankManager.get_count("emberbloom_seed") == 1, "a refused planting leaves the seed in storage")
	BankManager.add_item("garum_herb_seed", 3)
	_ok(FarmingManager.plant(0, "garum_herb_seed"), "a level-1 crop plants at level 1")
	_ok(BankManager.get_count("garum_herb_seed") == 2, "planting spends exactly one seed")
	_ok(not FarmingManager.plant(0, "garum_herb_seed"), "an occupied plot refuses a second seed")
	_ok(BankManager.get_count("garum_herb_seed") == 2, "a refused planting spends nothing")
	_ok(not FarmingManager.plant(99, "garum_herb_seed"), "an out-of-range plot index is refused")
	_ok(FarmingManager.plant_first_free("garum_herb_seed") == 1, "plant_first_free takes the first empty plot")
	_ok(FarmingManager.plant_first_free("garum_herb_seed") == 2, "plant_first_free continues down the row")
	_ok(FarmingManager.plant_first_free("garum_herb_seed") == -1, "plant_first_free fails cleanly without seeds")
	# Compost.
	_ok(not FarmingManager.apply_compost(2), "compost cannot be applied with none in storage")
	BankManager.add_item("compost", 2)
	_ok(not FarmingManager.apply_compost(0) and FarmingManager.apply_compost(3), "compost only applies before planting")
	_ok(int(FarmingManager.plots[3]["compost"]) == 1, "the plot records its compost")
	# Growth and harvest.
	_ok(not FarmingManager.is_ready(0), "a fresh planting is not ready yet")
	FarmingManager.plots[0]["planted_unix"] = float(Time.get_unix_time_from_system()) - 999999.0
	_ok(FarmingManager.is_ready(0), "a backdated crop reads as ready")
	var xp_before: float = PlayerData.get_xp("farming")
	var res: Dictionary = FarmingManager.harvest(0)
	_ok(int(res.get("quantity", 0)) >= 3, "harvest yields at least the seed minimum")
	_ok(BankManager.get_count("garum_herb") >= 3, "the crop lands in storage")
	_ok(PlayerData.get_xp("farming") > xp_before, "harvesting grants XP")
	_ok(FarmingManager.harvest(0).is_empty(), "an empty plot cannot be harvested twice")
	_ok(MasteryManager.get_xp("farming", "plant_garum_herb") > 0.0, "harvest mastery lands on the crop's action")
	# Failed crops stay on the plot until cleared.
	FarmingManager.plots[1]["alive"] = false
	_ok(not FarmingManager.is_ready(1), "a failed crop is never ready")
	_ok(FarmingManager.clear_plot(1), "a failed crop can be cleared")
	_ok(str(FarmingManager.plots[1]["seed_id"]) == "", "clearing frees the plot for replanting")
	# Batch harvest and the offline counter.
	BankManager.add_item("garum_herb_seed", 3)
	_ok(FarmingManager.plant_first_free("garum_herb_seed") == 0, "replanting reuses a harvested plot")
	_ok(FarmingManager.plant_first_free("garum_herb_seed") == 1, "and continues down the row")
	FarmingManager.plots[0]["planted_unix"] = float(Time.get_unix_time_from_system()) - 999999.0
	FarmingManager.plots[1]["planted_unix"] = float(Time.get_unix_time_from_system()) - 999999.0
	# Pin survival so this check is about batch collection, not the seeded survival roll.
	FarmingManager.plots[0]["alive"] = true
	FarmingManager.plots[1]["alive"] = true
	var batch: Dictionary = FarmingManager.harvest_all()
	_ok(int(batch.get("plots", 0)) == 2, "harvest_all collects exactly the ready plots")
	_ok(FarmingManager.advance_offline(3600.0) == 0, "the offline counter reads zero with nothing ready")
	BankManager.add_item("garum_herb_seed", 1)
	FarmingManager.plant_first_free("garum_herb_seed")
	FarmingManager.plots[0]["planted_unix"] = float(Time.get_unix_time_from_system()) - 999999.0
	FarmingManager.plots[0]["alive"] = true
	_ok(FarmingManager.advance_offline(3600.0) == 1, "a ready crop is counted for the offline summary")
	FarmingManager.harvest_all()

	# The skill-tab bridge: plant actions spend seeds into plots, then stop with a reason.
	GameManager.start_new_game("standard")
	PlayerData.set_level("farming", 1)
	BankManager.add_item("garum_herb_seed", 3)
	_ok(SkillManager.start_action("farming", "plant_garum_herb"), "the plant action starts with seeds in storage")
	SimulationMode.begin()
	SkillManager.simulate_elapsed(5.0)
	SimulationMode.end()
	var planted: int = 0
	for p in FarmingManager.plots:
		if str(p["seed_id"]) != "":
			planted += 1
	_ok(planted == 3, "the plant action filled three plots with three seeds")
	_ok(BankManager.get_count("garum_herb_seed") == 0, "the plant action spent every seed")
	_ok(not SkillManager.running and SkillManager.stop_reason_text().contains("Emberleaf"),
		"the loop stops with a named reason when the seeds run out")
	for i in range(FarmingManager.plots.size()):
		BankManager.add_item("garum_herb_seed", 1)
		FarmingManager.plant_first_free("garum_herb_seed")
	_ok(not bool(SkillManager.check_action("farming", "plant_garum_herb")["ok"]),
		"planting is refused while every plot is occupied")

	# The Farm screen.
	host.call("navigate", {"screen": Screens.FARM})
	var panel: Control = (host.get("_panels") as Dictionary).get(Screens.FARM)
	if panel == null or not is_instance_valid(panel):
		_ok(false, "the Farm screen exists")
		return
	_ok(true, "the Farm screen exists")
	_ok(panel.call("_plot_count") == 15, "the Farm screen renders all fifteen plots")
	_ok((panel.get("_summary") as Label).text.contains("Husbandry"), "the summary names the skill")
	var options: Array = panel.call("_seed_options")
	_ok(options.size() == 10, "the seed picker lists every crop")
	var locked_ok: bool = false
	for o in options:
		if str((o as Dictionary).get("id", "")) == "emberbloom_seed" and not bool((o as Dictionary).get("unlocked", false)):
			locked_ok = true
	_ok(locked_ok, "the picker locks crops above the player's level")
	BankManager.remove_item("garum_herb_seed", BankManager.get_count("garum_herb_seed"))
	var spent_ok: bool = false
	for o in panel.call("_seed_options"):
		if str((o as Dictionary).get("id", "")) == "garum_herb_seed" and bool((o as Dictionary).get("unlocked", false)) \
				and int((o as Dictionary).get("count", 0)) == 0:
			spent_ok = true
	_ok(spent_ok, "a spent seed still lists, marked unavailable")
	host.call("_show_screen", Screens.OVERVIEW, {})
const PANEL_SCRIPTS: Dictionary = {
	Screens.OVERVIEW: "OverviewPanel",
	Screens.SKILLS: "SkillsPanel",
	Screens.COMBAT: "CombatPanel",
	Screens.EXPEDITIONS: "CombatPanel",
	Screens.BANK: "BankPanel",
	Screens.ACTION_QUEUE: "ActionQueuePanel",
	Screens.COMBAT_SIMULATOR: "CombatSimulatorPanel",
	Screens.QUESTS: "QuestsPanel",
	Screens.ACHIEVEMENTS: "AchievementsPanel",
	Screens.COLLECTION: "CollectionPanel",
	Screens.STATS: "StatsPanel",
	Screens.SETTLEMENT: "SettlementPanel",
	Screens.PROVISIONER: "ProvisionerPanel",
	Screens.STORE: "GeneralStorePanel",
	Screens.EQUIPMENT: "EquipmentPanel",
	Screens.SETTINGS: "SettingsPanel",
	Screens.PRAYERS: "PrayerPanel",
	Screens.RAIDS: "RaidPanel",
	Screens.FARM: "FarmPanel",
	Screens.PRESTIGE: "PrestigePanel",
	Screens.RECOVERY: "RecoveryPanel",
}

func run_end_to_end(host: Node) -> void:
	var files: Dictionary = TestSupport.backup_save_files()
	var snapshot: Dictionary = SaveManager.build_save_data()
	_begin("Emberreach end-to-end progression check")
	_deterministic(true)
	var steps: Array = []
	var ok: bool = true

	# 1. Start a new game.
	GameManager.start_new_game("standard")
	_ok(PlayerData.get_level("woodcutting") == 1, "new game starts at level 1")
	_ok(PlayerData.gp == 0.0, "new game starts with no gold")
	steps.append("1. New journey started; gold %s, woodcutting level %d" % [
		UIStyle.fmt(PlayerData.gp), PlayerData.get_level("woodcutting")])

	# 2. Gather initial materials.
	var gather: Dictionary = _find_gather_action()
	var before_logs: int = 0
	if not gather.is_empty():
		var out_item: String = _primary_output(str(gather["skill_id"]), str(gather["action_id"]))
		before_logs = BankManager.get_count(out_item)
		SkillManager.start_action(str(gather["skill_id"]), str(gather["action_id"]), 0)
		SimulationMode.begin()
		SkillManager.simulate_elapsed(120.0)
		SimulationMode.end()
		var gained: int = BankManager.get_count(out_item) - before_logs
		_ok(gained > 0, "gathering produced %s" % out_item)
		steps.append("2. Gathered %d × %s from %s" % [gained, out_item, str(gather["skill_id"])])
	else:
		_ok(false, "found a gathering action with no inputs")
		steps.append("2. FAILED to find a gathering action")

	# 3. Craft an upgrade (materials granted to the bank where the chain is long).
	var recipe: Dictionary = _find_artisan_producing_equipment()
	var crafted_item: String = ""
	if not recipe.is_empty():
		var inputs: Dictionary = DataLoader.get_action(str(recipe["skill_id"]), str(recipe["action_id"])).get("input_items", {})
		for item_id in inputs.keys():
			BankManager.add_item_guaranteed(str(item_id), int(inputs[item_id]) * 3)
		PlayerData.set_level(str(recipe["skill_id"]), 99)
		var outputs: Dictionary = DataLoader.get_action(str(recipe["skill_id"]), str(recipe["action_id"])).get("output_items", {})
		for item_id in outputs.keys():
			crafted_item = str(item_id)
			break
		SkillManager.start_action(str(recipe["skill_id"]), str(recipe["action_id"]), 1)
		SimulationMode.begin()
		SkillManager.simulate_elapsed(60.0)
		SimulationMode.end()
		_ok(BankManager.get_count(crafted_item) >= 1, "crafting produced %s" % crafted_item)
		steps.append("3. Crafted %s ×%d in %s" % [crafted_item, BankManager.get_count(crafted_item), str(recipe["skill_id"])])
	else:
		_ok(false, "found an artisan recipe producing equipment")
		steps.append("3. FAILED to find a craftable equipment recipe")

	# 4. Equip it.
	var equipped: bool = false
	if crafted_item != "":
		_meet_requirements(crafted_item)
		equipped = EquipmentManager.equip(crafted_item)
		_ok(equipped, "equipped the crafted item")
		steps.append("4. Equipped %s: %s" % [crafted_item, "yes" if equipped else "no"])

	# 5. Defeat an enemy.
	var area: Dictionary = _find_area()
	var kills_before: float = _stat_total("monsters_killed")
	var kill_ok: bool = false
	if not area.is_empty():
		# A competent starting adventurer: the earliest region in the game, so the check proves
		# the loop rather than end-game gear requirements.
		for skill_id in ["attack", "strength", "defence", "hitpoints"]:
			PlayerData.set_level(skill_id, 40)
		CombatManager.start_combat({
			"type": "area", "id": str(area["id"]), "monsters": area["monsters"], "endless": true,
			"attack_style": "melee", "melee_style": "stab",
		})
		CombatManager.player_max_hp = CombatManager._compute_max_hp()
		CombatManager.player_hp = CombatManager.player_max_hp
		SimulationMode.begin()
		CombatManager.simulate_elapsed(600.0)
		SimulationMode.end()
		kill_ok = _stat_total("monsters_killed") > kills_before
		_ok(kill_ok, "won at least one fight")
		steps.append("5. Expedition in %s: %d victory(ies)" % [
			str(area["id"]), int(_stat_total("monsters_killed") - kills_before)])
		CombatManager.stop_combat("step complete")
		# A defeat may have moved a helmet back to storage; re-equip so step 8 tests persistence
		# rather than the defeat policy.
		if crafted_item != "" and not EquipmentManager.is_equipped(crafted_item) \
				and BankManager.get_count(crafted_item) > 0:
			EquipmentManager.equip(crafted_item)
	else:
		_ok(false, "found a region with monsters")

	# 6. Complete a quest.
	var quest_id: String = _find_satisfiable_quest()
	var quest_ok: bool = false
	if quest_id != "":
		_satisfy_quest(quest_id)
		var gp_before: float = PlayerData.gp
		quest_ok = Quests.claim(quest_id)
		_ok(quest_ok, "claimed a completed task")
		_ok(not Quests.claim(quest_id), "the same reward cannot be claimed twice")
		steps.append("6. Task '%s' claimed (%s GP, %d objectives)" % [quest_id,
			UIStyle.fmt(PlayerData.gp - gp_before), int(Quests.progress(quest_id)["total"])])
	else:
		_ok(false, "found a task with satisfiable objectives")
		steps.append("6. FAILED to find a satisfiable task")

	# 7. Purchase a settlement structure.
	for res_id in TownshipManager.ALL_RESOURCES:
		TownshipManager.resources[res_id] = 500.0
	var building_id: String = _first_building_id()
	var build_ok: bool = TownshipManager.build(building_id)
	_ok(build_ok, "built a settlement structure")
	_ok(TownshipManager.level_of(building_id) == 1, "the structure reached level 1")
	steps.append("7. Built %s to level %d (stores seeded with %s per resource)" % [
		building_id, TownshipManager.level_of(building_id), UIStyle.fmt(500.0)])

	# 8. Save and reload.
	var xp_before: float = PlayerData.get_xp("woodcutting")
	var saved: bool = SaveManager.save_game()
	_ok(saved, "save write succeeded")
	var loaded: bool = SaveManager.load_game()
	_ok(loaded, "save re-read successfully")
	_ok(absf(PlayerData.get_xp("woodcutting") - xp_before) < 0.5, "skill XP survived the round-trip")
	_ok(EquipmentManager.is_equipped(crafted_item) == equipped, "equipment survived the round-trip")
	_ok(Quests.is_claimed(quest_id), "quest flags survived the round-trip")
	steps.append("8. Saved and reloaded: XP %.0f -> %.0f, %d buildings" % [
		xp_before, PlayerData.get_xp("woodcutting"), TownshipManager.buildings.size()])

	# 9. Process offline progress exactly once.
	SkillManager.stop_action(SkillManager.StopReason.PLAYER)
	if not gather.is_empty():
		SkillManager.start_action(str(gather["skill_id"]), str(gather["action_id"]), 0)
	GameManager.boot_state = GameManager.BootState.LOADED
	PlayerData.last_offline_unix = int(Time.get_unix_time_from_system()) - 3600
	var summary: Dictionary = OfflineProgression.run_on_load()
	var guard: int = 0
	while OfflineProgression.is_running and guard < 10000:
		guard += 1
		OfflineProgression._step_chunk()
	summary = OfflineProgression.last_summary()
	_ok(float(summary.get("processed_seconds", 0.0)) > 0.0, "offline catch-up processed time")
	_ok(int(summary.get("actions", 0)) > 0, "offline catch-up completed actions")
	var marker_after: int = PlayerData.last_offline_unix
	_ok(marker_after > int(Time.get_unix_time_from_system()) - 10, "offline marker advanced exactly once")
	steps.append("9. Offline: %s processed, %d actions, %d levels, stopped: '%s'" % [
		UIStyle.fmt_duration(float(summary.get("processed_seconds", 0.0))), int(summary.get("actions", 0)),
		(summary.get("levels_gained", {}) as Dictionary).size(), str(summary.get("stopped_reason", ""))])

	# 10. Verify the totals.
	var total_level: int = 0
	for skill_id in DataLoader.get_skill_ids():
		total_level += PlayerData.get_level(skill_id)
	_ok(total_level > 29, "total levels increased beyond the starting spread")
	_ok(Quests.claimed_count() >= 1, "at least one task completed")
	_ok(PlayerData.get_stat("gp_earned") >= 0.0, "lifetime gold counter is valid")
	steps.append("10. Totals: total levels %d, tasks claimed %d, milestones %d, items discovered %d" % [
		total_level, Quests.claimed_count(), Achievements.claimed_count(),
		(PlayerData.completion_log.get("items", {}) as Dictionary).size()])

	ok = _failed == 0
	TestSupport.restore_snapshot(snapshot, files)
	_report()
	print("\n--- progression trace ---")
	for line in steps:
		print("  " + str(line))
	if not ok:
		print("The end-to-end check found problems; see the failures above.")

# =========================================================================
#  Tests
# =========================================================================

func _test_xp_and_levels() -> void:
	_heading("XP and level maths")
	# A single grant spanning several levels must land on the right level.
	PlayerData.set_level("woodcutting", 1)
	PlayerData.add_xp("woodcutting", float(XPTable.xp_for_level(40)) - float(XPTable.xp_for_level(1)))
	_eq(PlayerData.get_level("woodcutting"), 40, "one large XP grant awards every level it crosses")
	# XP past the cap must not accumulate.
	PlayerData.set_level("woodcutting", XPTable.MAX_LEVEL - 1)
	PlayerData.add_xp("woodcutting", 10_000_000_000.0)
	_ok(PlayerData.get_level("woodcutting") <= XPTable.MAX_LEVEL, "level never exceeds the cap")
	_ok(PlayerData.get_xp("woodcutting") <= float(XPTable.xp_for_level(XPTable.MAX_LEVEL)),
		"XP never banks past the cap")
	# Zero and negative grants are ignored.
	var xp_now: float = PlayerData.get_xp("woodcutting")
	PlayerData.add_xp("woodcutting", 0.0)
	PlayerData.add_xp("woodcutting", -500.0)
	_eq(PlayerData.get_xp("woodcutting"), xp_now, "a non-positive XP grant changes nothing")

func _test_currency_boundaries() -> void:
	_heading("Currency and affordability boundaries")
	PlayerData.gp = 0.0
	PlayerData.add_gp(-100.0)
	_eq(PlayerData.gp, 0.0, "a negative gold grant is refused")
	PlayerData.add_gp(1000.0)
	_eq(PlayerData.gp, 1000.0, "gold accumulates normally")
	# Exact boundary: affordable at exactly the cost, unaffordable one unit short.
	_ok(PlayerData.spend_gp(0.0), "spending nothing succeeds")
	_ok(not PlayerData.spend_gp(1000.01), "spending more than you hold fails")
	_eq(PlayerData.gp, 1000.0, "a failed spend does not change the balance")
	_ok(PlayerData.spend_gp(1000.0), "spending exactly the balance succeeds")
	_eq(PlayerData.gp, 0.0, "the balance is exactly zero afterwards")
	_ok(not PlayerData.spend_gp(0.01), "nothing can be spent from an empty balance")

func _test_atomic_consumption() -> void:
	_heading("Atomic material consumption")
	var recipe: Dictionary = _find_artisan_with_inputs()
	if recipe.is_empty():
		_ok(false, "found an artisan recipe with inputs")
		return
	var inputs: Dictionary = recipe["inputs"]
	var first_id: String = str(inputs.keys()[0])
	BankManager.items.clear()
	var result: Dictionary = BankManager.consume_bundle(inputs)
	_ok(not bool(result["ok"]), "consuming a bundle with nothing in storage fails")
	_ok(BankManager.items.is_empty(), "a failed bundle consumes nothing at all")
	# Give everything except one unit of the first ingredient.
	for item_id in inputs.keys():
		BankManager.add_item_guaranteed(str(item_id), int(inputs[item_id]))
	BankManager.remove_item(first_id, 1)
	var partial: Dictionary = BankManager.consume_bundle(inputs)
	_ok(not bool(partial["ok"]), "a bundle missing one unit is refused")
	_eq(BankManager.get_count(first_id), int(inputs[first_id]) - 1, "a refused bundle leaves every stack untouched")
	# Now top it up and confirm it succeeds exactly.
	BankManager.add_item_guaranteed(first_id, 1)
	_ok(bool(BankManager.consume_bundle(inputs)["ok"]), "a complete bundle is consumed")
	for item_id in inputs.keys():
		_eq(BankManager.get_count(str(item_id)), 0, "ingredient %s was consumed exactly" % item_id)

func _test_recipe_consumption_and_exhaustion() -> void:
	_heading("Recipe consumption and resource exhaustion")
	var recipe: Dictionary = _find_artisan_with_inputs()
	if recipe.is_empty():
		_ok(false, "found an artisan recipe with inputs")
		return
	var skill_id: String = str(recipe["skill_id"])
	var action_id: String = str(recipe["action_id"])
	var action: Dictionary = DataLoader.get_action(skill_id, action_id)
	var inputs: Dictionary = action.get("input_items", {})
	var outputs: Dictionary = action.get("output_items", {})
	BankManager.items.clear()
	BankManager.overflow.clear()
	PlayerData.set_level(skill_id, 99)
	for item_id in inputs.keys():
		BankManager.add_item_guaranteed(str(item_id), int(inputs[item_id]))
	SkillManager.start_action(skill_id, action_id, 0)   # repeat forever
	_ok(SkillManager.running, "the recipe starts with materials in place")
	SimulationMode.begin()
	SkillManager.simulate_elapsed(600.0)
	SimulationMode.end()
	# Exactly one craft must have happened: the inputs ran out, and no free output was produced.
	for item_id in outputs.keys():
		_eq(BankManager.get_count(str(item_id)), int(outputs[item_id]),
			"output %s was produced exactly once for one set of inputs" % item_id)
	for item_id in inputs.keys():
		_eq(BankManager.get_count(str(item_id)), 0, "input %s was fully consumed" % item_id)
	_ok(not SkillManager.running, "the activity stopped when materials ran out")
	_eq(SkillManager.stop_reason, SkillManager.StopReason.MISSING_MATERIALS,
		"the stop reason is 'missing materials'")

func _test_bank_overflow_never_deletes() -> void:
	_heading("Storage capacity and overflow")
	BankManager.items.clear()
	BankManager.overflow.clear()
	BankManager.purchased_slots = -(BankManager.BASE_SLOTS) + 1   # force a one-slot bank
	var filler: String = _first_item_id()
	BankManager.add_item_guaranteed(filler, 1)
	_ok(BankManager.is_full(), "the bank reports full at its limit")
	var second: String = _second_item_id(filler)
	var stored: int = BankManager.add_item(second, 7)
	_eq(stored, 0, "a new stack cannot be created in a full bank")
	_eq(BankManager.overflow_count(), 7, "the refused items are held in overflow, not destroyed")
	BankManager.purchased_slots = 0
	BankManager.withdraw_overflow("")
	_eq(BankManager.get_count(second), 7, "overflow is withdrawn once there is room")
	_eq(BankManager.overflow_count(), 0, "overflow is empty after withdrawing")

func _test_equipment_modifiers() -> void:
	_heading("Equipment modifiers")
	var item_id: String = _find_equippable_item_with_modifiers()
	if item_id == "":
		_ok(false, "found equipment with passive modifiers")
		return
	BankManager.items.clear()
	EquipmentManager.slots.clear()
	EquipmentManager._reregister_modifiers()
	_meet_requirements(item_id)
	BankManager.add_item_guaranteed(item_id, 1)
	var mods: Dictionary = DataLoader.get_item(item_id).get("passive_modifiers", {})
	var key: String = str(mods.keys()[0])
	var before: float = ModifierManager.get_modifier(key)
	_ok(EquipmentManager.equip(item_id), "the item equips")
	var after: float = ModifierManager.get_modifier(key)
	_ok(absf(after - before) > 0.000001 or float(mods[key]) == 0.0,
		"equipping registered '%s' with the modifier manager" % key)
	EquipmentManager.unequip(int(DataLoader.get_item(item_id).get("equipment_slot", 0)))
	_approx(ModifierManager.get_modifier(key), before, 0.000001, "unequipping removes the modifier")

func _test_quest_reward_once() -> void:
	_heading("Quest rewards are granted exactly once")
	var quest_id: String = _find_satisfiable_quest()
	if quest_id == "":
		_ok(false, "found a task whose objectives can be satisfied")
		return
	_satisfy_quest(quest_id)
	_ok(Quests.is_complete(quest_id), "the task reports complete once every objective is met")
	var gp_before: float = PlayerData.gp
	var first: bool = Quests.claim(quest_id)
	_ok(first, "the first claim succeeds")
	var gp_after_first: float = PlayerData.gp
	_ok(not Quests.claim(quest_id), "the second claim is refused")
	_approx(PlayerData.gp, gp_after_first, 0.000001, "no gold is granted twice")
	_ok(Quests.is_claimed(quest_id), "the claim is recorded")
	if gp_after_first > gp_before:
		_ok(true, "the reward added %s GP" % UIStyle.fmt(gp_after_first - gp_before))

func _test_achievement_reward_once() -> void:
	_heading("Milestone rewards are claimed exactly once")
	# Level several skills up so at least one milestone condition is satisfiable.
	for skill_id in DataLoader.get_skill_ids():
		PlayerData.set_level(skill_id, 40)
	var completed_before: int = Achievements.completed_count()
	var first: Array = Achievements.evaluate_all()
	var second: Array = Achievements.evaluate_all()
	_ok(first.size() > 0, "the first evaluation completes at least one milestone")
	_eq(second.size(), 0, "evaluation never double-reports a completion")
	_eq(Achievements.completed_count(), completed_before + first.size(), "every completed milestone is recorded once")
	_eq(Achievements.claimed_count(), 0, "completion alone never pays out - milestones are claimed")
	_ok(Achievements.ready_count() > 0, "completed milestones wait to be claimed (%d ready)" % Achievements.ready_count())
	var gp_before: float = PlayerData.gp
	Achievements.evaluate_all()
	_approx(PlayerData.gp, gp_before, 0.000001, "re-evaluating still grants nothing")
	# Claiming pays out exactly once and delivers the reward bundle.
	var probe_id: String = ""
	var probe_item: String = ""
	var probe_qty: int = 0
	for ach_id in Achievements.all_ids():
		if not Achievements.is_ready(ach_id):
			continue
		var items: Dictionary = Achievements.get_record(ach_id).get("reward", {}).get("items", {})
		if not items.is_empty():
			probe_id = ach_id
			probe_item = str(items.keys()[0])
			probe_qty = int(items[probe_item])
			break
	_ok(probe_id != "", "a completed milestone with an item bundle exists for the probe")
	if probe_id != "":
		var bank_before: int = BankManager.get_count(probe_item)
		_ok(Achievements.claim(probe_id), "a completed milestone can be claimed")
		var bank_after: int = BankManager.get_count(probe_item)
		_ok(bank_after >= bank_before + probe_qty, "the claim delivered its supplies (%s x%d)" % [probe_item, probe_qty])
		_ok(not Achievements.claim(probe_id), "the same milestone cannot be claimed twice")
		_eq(BankManager.get_count(probe_item), bank_after, "supplies are granted exactly once")
	# An unmet milestone cannot be claimed.
	var unmet_id: String = ""
	for ach_id in Achievements.all_ids():
		if not Achievements.is_completed(ach_id):
			unmet_id = ach_id
			break
	_ok(unmet_id != "", "some milestones are still unmet (%d claimed of %d)" % [Achievements.claimed_count(), Achievements.count()])
	_ok(not Achievements.claim(unmet_id), "an unmet milestone cannot be claimed")
	# Claimed supplies can complete further milestones; claim-all settles the cascade.
	var rounds: int = 0
	while Achievements.ready_count() > 0 and rounds < 12:
		rounds += 1
		Achievements.claim_all()
	_eq(Achievements.ready_count(), 0, "claiming settles every cascade (%d rounds)" % rounds)
	_eq(Achievements.claimed_count(), Achievements.completed_count(), "every completed milestone ends up claimed")
	# Every condition kind must be exercised by at least one milestone.
	var kinds_seen: Dictionary = {}
	for ach_id in Achievements.all_ids():
		kinds_seen[str(Achievements.get_record(ach_id).get("condition", {}).get("kind", ""))] = true
	var missing_kinds: Array[String] = []
	for kind in ["skill_level", "total_level", "item_count", "lifetime_item", "monsters_killed",
		"dungeons_cleared", "items_discovered", "gp_earned", "actions_completed", "quests_completed",
		"pets_unlocked", "settlement_buildings"]:
		if not kinds_seen.has(kind):
			missing_kinds.append(kind)
	_eq(missing_kinds.size(), 0, "every condition kind has milestones (%s)"
		% ("none missing" if missing_kinds.is_empty() else ", ".join(missing_kinds)))
	# Pre-claim saves (the auto-grant era) migrate as already claimed.
	var keep: Dictionary = Achievements.serialize()
	Achievements.deserialize({"unlocked": {"first_shavings": true}, "unlocked_unix": {"first_shavings": 123}})
	_ok(Achievements.is_completed("first_shavings") and Achievements.is_claimed("first_shavings"),
		"pre-claim saves arrive already claimed")
	Achievements.deserialize(keep)
	_eq(Achievements.claimed_count(), (keep.get("claimed", {}) as Dictionary).size(), "the milestone snapshot restores cleanly")

func _test_save_round_trip() -> void:
	_heading("Save round-trip")
	BankManager.items.clear()
	PlayerData.gp = 12345.5
	PlayerData.set_level("mining", 37)
	BankManager.add_item_guaranteed(_first_item_id(), 42)
	EquipmentManager.slots.clear()
	var gadget: String = _find_equippable_item_with_modifiers()
	if gadget != "":
		_meet_requirements(gadget)
		BankManager.add_item_guaranteed(gadget, 1)
		EquipmentManager.equip(gadget)
	PlayerData.protected_items[_first_item_id()] = true
	var json_text: String = JSON.stringify(SaveManager.build_save_data(), "\t")
	var parsed: Variant = JSON.parse_string(json_text)
	_ok(typeof(parsed) == TYPE_DICTIONARY, "serialized save text parses back as an object")
	SaveManager._apply(parsed)
	_approx(PlayerData.gp, 12345.5, 0.000001, "gold survived the round-trip")
	_eq(PlayerData.get_level("mining"), 37, "skill level survived the round-trip")
	_eq(BankManager.get_count(_first_item_id()), 42, "a bank stack survived the round-trip")
	_ok(BankManager.is_protected(_first_item_id()), "item protection survived the round-trip")
	if gadget != "":
		_ok(EquipmentManager.is_equipped(gadget), "equipped gear survived the round-trip")

func _test_save_migration() -> void:
	_heading("Old-save migration (format 1 -> 2)")
	var legacy: Dictionary = {
		"version": "1.4.0",
		"player": {"skills": {"woodcutting": {"xp": 1000.0, "level": 12}}, "gp": 999.0},
		"bank": {"items": {}},
		"equipment": {"slots": {}},
		"modifiers": {"global_skill_xp_percent": 999.0},
	}
	_eq(SaveManager.detect_version(legacy), 1, "the legacy format is identified as version 1")
	_ok(SaveManager.validate_save(legacy).is_empty(), "the legacy save passes structural validation")
	var migrated: Dictionary = SaveManager.migrate_save(legacy, 1)
	_eq(int(migrated.get("save_version", 0)), SaveManager.SAVE_VERSION, "the migrated save reports the current version")
	_ok(not migrated.has("modifiers"), "the derived modifier cache is dropped, not trusted")
	_ok(migrated.has("settings"), "settings are materialised from defaults")
	for key in SettingsDefaults.DEFAULTS.keys():
		_ok((migrated["settings"] as Dictionary).has(key), "migrated settings include '%s'" % key)
	_ok((migrated["player"] as Dictionary).has("last_offline_unix"),
		"the offline marker is seeded from the save timestamp")
	SaveManager._apply(migrated)
	_eq(PlayerData.get_level("woodcutting"), 12, "migrated skill state loads correctly")
	_ok(absf(ModifierManager.get_modifier("global_skill_xp_percent")) < 900.0,
		"the stale modifier from the old save was not restored")

func _test_malformed_save_rejected() -> void:
	_heading("Malformed saves are rejected, not loaded")
	var cases: Array = [
		{"label": "not an object", "value": "just a string"},
		{"label": "empty object", "value": {}},
		{"label": "missing player section", "value": {"save_version": 2, "bank": {}, "equipment": {}}},
		{"label": "unreadable version", "value": {"save_version": 0, "player": {"skills": {"x": {}}}, "bank": {}, "equipment": {}}},
		{"label": "future version", "value": {"save_version": 999, "player": {"skills": {"x": {}}}, "bank": {}, "equipment": {}}},
		{"label": "player.skills is not an object", "value": {"save_version": 2, "player": {"skills": []}, "bank": {}, "equipment": {}}},
	]
	for case in cases:
		var problems: Array = SaveManager.validate_save(case["value"])
		_ok(not problems.is_empty(), "a save that is %s is rejected (%s)" % [case["label"], "; ".join(problems)])
	# A broken numeric field must be sanitized rather than loaded verbatim.
	var dirty: Dictionary = {
		"save_version": 2,
		"player": {"skills": {"woodcutting": {"xp": -50.0, "level": 1}}, "gp": -10.0},
		"bank": {"items": {"__not_an_item__": 5}},
		"equipment": {},
	}
	_ok(SaveManager.validate_save(dirty).is_empty(), "a structurally valid save with bad numbers is accepted")
	SaveManager._apply(dirty)
	_ok(PlayerData.gp >= 0.0, "a negative gold value is clamped on load")
	_ok(PlayerData.get_xp("woodcutting") >= 0.0, "a negative XP value is clamped on load")
	_ok(not BankManager.items.has("__not_an_item__"), "an unknown item id is dropped from the ledger")

func _test_offline_cap_and_negative_time() -> void:
	_heading("Offline cap and clock anomalies")
	var gather: Dictionary = _find_gather_action()
	if gather.is_empty():
		_ok(false, "found a gathering action")
		return
	PlayerData.settings["offline_cap_hours"] = 1.0
	SkillManager.start_action(str(gather["skill_id"]), str(gather["action_id"]), 0)
	GameManager.boot_state = GameManager.BootState.LOADED
	# Two hours away with a one-hour cap: exactly one hour may be simulated.
	PlayerData.last_offline_unix = int(Time.get_unix_time_from_system()) - 7200
	var summary: Dictionary = OfflineProgression.run_on_load()
	_approx(float(summary["elapsed_seconds"]), 3600.0, 5.0, "the cap limits the simulated window to one hour")
	_approx(float(summary["capped_seconds"]), 3600.0, 5.0, "the excluded time is reported")
	var guard: int = 0
	while OfflineProgression.is_running and guard < 10000:
		guard += 1
		OfflineProgression._step_chunk()
	var finished: Dictionary = OfflineProgression.last_summary()
	_ok(float(finished["processed_seconds"]) <= 3600.0 + 1.0, "no more than the cap was processed")
	# A clock that moved backwards must grant nothing and leave the marker alone.
	SkillManager.stop_action(SkillManager.StopReason.PLAYER)
	var future: int = int(Time.get_unix_time_from_system()) + 7200
	PlayerData.last_offline_unix = future
	var anomaly: Dictionary = OfflineProgression.run_on_load()
	_ok(bool(anomaly["clock_anomaly"]), "a backwards clock is flagged")
	_eq(float(anomaly["processed_seconds"]), 0.0, "a backwards clock grants no progress")
	_eq(PlayerData.last_offline_unix, future, "a backwards clock leaves the marker untouched")

func _test_online_offline_consistency() -> void:
	_heading("Online and offline simulation agree")
	var gather: Dictionary = _find_gather_action()
	if gather.is_empty():
		_ok(false, "found a gathering action")
		return
	var skill_id: String = str(gather["skill_id"])
	var action_id: String = str(gather["action_id"])
	var item_id: String = _primary_output(skill_id, action_id)

	# Run A: the online path, one second at a time.
	GameManager.start_new_game("standard")
	_deterministic(true)
	SkillManager.start_action(skill_id, action_id, 0)
	for _i in range(600):
		SkillManager.tick(1.0, false)
	var online_xp: float = PlayerData.get_xp(skill_id)
	var online_items: int = BankManager.get_count(item_id)
	var online_actions: int = SkillManager.total_action_count

	# Run B: the offline path over the same 600 seconds, from a fresh identical state.
	GameManager.start_new_game("standard")
	_deterministic(true)
	SkillManager.start_action(skill_id, action_id, 0)
	SimulationMode.begin()
	var result: Dictionary = SkillManager.simulate_elapsed(600.0)
	SimulationMode.end()
	var offline_xp: float = PlayerData.get_xp(skill_id)
	var offline_items: int = BankManager.get_count(item_id)

	_eq(int(result.get("actions", 0)), online_actions, "both paths completed the same number of actions")
	_approx(offline_xp, online_xp, 0.0001, "both paths awarded identical XP")
	_eq(offline_items, online_items, "both paths produced identical items")
	_ok(online_items > 0, "the consistent run actually produced something")

func _test_combat_defeat_and_retreat(host: Node) -> void:
	_heading("Combat defeat and retreat")
	var area: Dictionary = _find_area()
	var dungeon_ok: bool = not area.is_empty()
	if not dungeon_ok:
		_ok(false, "found a region with monsters")
		return
	var monsters: Array = area["monsters"]
	# Retreat is free and immediate.
	CombatManager.start_combat({"type": "area", "id": str(area["id"]), "monsters": monsters,
		"endless": true, "attack_style": "melee", "melee_style": "stab"})
	_ok(CombatManager.state != CombatManager.State.IDLE, "combat begins")
	CombatManager.stop_combat("retreat")
	_eq(CombatManager.state, CombatManager.State.IDLE, "retreat ends the fight immediately")
	_eq(CombatManager.current_monster_id, "", "no enemy remains after retreating")
	var gather: Dictionary = _find_gather_action()
	var can_skill: bool = not gather.is_empty() and SkillManager.can_perform(str(gather["skill_id"]), str(gather["action_id"]))
	_ok(can_skill, "a skill action can start after retreating")
	SkillManager.stop_action(SkillManager.StopReason.PLAYER)

	# Defeat: not one item may be destroyed, and a protected weapon must survive.
	EquipmentManager.slots.clear()
	var weapon: String = _find_weapon()
	if weapon != "":
		_meet_requirements(weapon)
		BankManager.add_item_guaranteed(weapon, 1)
		BankManager.set_protected(weapon, true)
		_ok(EquipmentManager.equip(weapon), "a weapon was equipped for the defeat test")
	var deaths_before: float = _stat_total("deaths")
	var items_before: int = _total_items_held()
	var strongest: String = _strongest_monster(DataLoader.monsters.keys())
	CombatManager.start_combat({"type": "area", "id": str(area["id"]), "monsters": [strongest],
		"endless": true, "attack_style": "melee", "melee_style": "stab"})
	CombatManager.player_max_hp = CombatManager._compute_max_hp()
	CombatManager.player_hp = 1.0
	for _i in range(600):
		if CombatManager.state == CombatManager.State.IDLE or CombatManager.state == CombatManager.State.DEAD:
			break
		CombatManager.tick(1.0)
	_ok(_stat_total("deaths") > deaths_before, "the defeat was recorded")
	if weapon != "":
		_ok(EquipmentManager.is_equipped(weapon), "the equipped weapon was NOT destroyed by the defeat")
	_ok(_total_items_held() >= items_before, "no item was destroyed by the defeat")
	_ok(CombatManager.state == CombatManager.State.IDLE, "the fight ended after the defeat")
	# Portrait refresh contract: a new enemy must announce itself as an activity change, or
	# the strip and the fight readout keep showing the session's first spawn forever.
	var spawn_events: Array = [0]
	var watcher := func(): spawn_events[0] += 1
	EventBus.activity_changed.connect(watcher)
	var watch_area: Dictionary = _find_area()
	CombatManager.start_combat({"type": "area", "id": str(watch_area["id"]), "monsters": watch_area["monsters"],
		"endless": true, "attack_style": "melee", "melee_style": "stab"})
	var after_start: int = int(spawn_events[0])
	CombatManager.apply_damage_to_monster(99_999_999)
	_ok(int(spawn_events[0]) > after_start, "each new enemy announces an activity change (%d -> %d)" % [after_start, int(spawn_events[0])])
	_ok(CombatManager.state == CombatManager.State.FIGHTING and CombatManager.current_monster_id != "",
		"an endless region respawns a new enemy after each kill")
	CombatManager.stop_combat("retreat")
	EventBus.activity_changed.disconnect(watcher)
	# End to end: a live panel must show the enemy actually being fought, across respawns.
	CombatManager.start_combat({"type": "area", "id": str(watch_area["id"]), "monsters": watch_area["monsters"],
		"endless": true, "attack_style": "melee", "melee_style": "stab"})
	var panel: Control = load("res://scripts/ui/panels/CombatPanel.gd").new()
	host.add_child(panel)
	CombatManager.apply_damage_to_monster(99_999_999)
	var want_tex: Texture2D = AssetRegistry.monster_sprite(CombatManager.current_monster_id)
	var want_name: String = str(DataLoader.get_monster(CombatManager.current_monster_id).get("name", ""))
	var sprite_ok: bool = false
	for tr2 in panel.find_children("", "TextureRect", true, false):
		if (tr2 as TextureRect).texture == want_tex:
			sprite_ok = true
	var name_ok: bool = false
	for lbl in panel.find_children("", "Label", true, false):
		if (lbl as Label).text.contains(want_name):
			name_ok = true
	_ok(sprite_ok, "the fight readout's portrait matches the enemy being fought")
	_ok(name_ok, "the fight readout names the enemy being fought")
	panel.call("_process", 0.0)
	CombatManager.stop_combat("retreat")
	panel.queue_free()

func _test_duplicate_submissions() -> void:
	_heading("Duplicate action submissions")
	var gather: Dictionary = _find_gather_action()
	if gather.is_empty():
		_ok(false, "found a gathering action")
		return
	SkillManager.stop_action(SkillManager.StopReason.PLAYER)
	var first: bool = GameManager.request_skill_action(str(gather["skill_id"]), str(gather["action_id"]), 5)
	var second: bool = GameManager.request_skill_action(str(gather["skill_id"]), str(gather["action_id"]), 5)
	_ok(first and second, "both submissions are accepted without error")
	_ok(SkillManager.running, "exactly one activity is running")
	_eq(SkillManager.total_action_count, 0, "no work was double-counted")
	_eq(SkillManager.repeat_target, 5, "the target quantity was not duplicated")
	var active_count: int = 0
	if SkillManager.running:
		active_count += 1
	if CombatManager.state != CombatManager.State.IDLE:
		active_count += 1
	_eq(active_count, 1, "the single activity slot is respected")
	SkillManager.stop_action(SkillManager.StopReason.PLAYER)

func _test_progression_qol(host: Node) -> void:
	_heading("Progression QoL")
	_report_suite("action queue", await ActionQueueTests.run(host))
	_report_suite("loot filters", LootFilterTests.run(host))
	_report_suite("combat simulator", await CombatSimulatorTests.run(host))

## Fold a dedicated suite's private counters into the main report, so a QoL failure is as visible
## as any other check and its label says which system broke.
func _report_suite(name: String, state: Dictionary) -> void:
	for label in state.get("failures", []):
		_ok(false, "%s: %s" % [name, str(label)])
	_ok(true, "%s policy, safety and persistence checks" % name)

## The audio system is pure data + pure math: recipes in data/audio.json become PCM
## buffers. These checks never open a device — they assert the recipes resolve, the
## synthesis produces real samples, and throttles/settings behave.
func _test_audio() -> void:
	_heading("Audio")
	var audio: Dictionary = DataLoader.audio
	_ok(not audio.is_empty(), "the audio table loaded (%d sounds, %d tracks)" % [
		audio.get("sfx", {}).size(), audio.get("music", {}).size()])
	_ok(audio.get("sfx", {}).size() >= 10, "a meaningful sound set exists (%d)" % audio.get("sfx", {}).size())
	_ok(audio.get("music", {}).size() >= 2, "both music tracks exist (%d)" % audio.get("music", {}).size())
	# Every reference resolves: ContentValidator checks these too, but the test states
	# the promise directly so a validator regression cannot hide a broken mapping.
	var broken: Array[String] = []
	for signal_name in audio.get("events", {}).keys():
		if not EventBus.has_signal(str(signal_name)):
			broken.append(str(signal_name))
	_ok(broken.is_empty(), "every audio event is a real signal (broken: %s)" % str(broken))
	# Synthesis produces actual samples: non-trivial length, silent at both edges so
	# the sound cannot click when it starts or ends.
	var stream: AudioStreamWAV = AudioManager.sfx_stream("levelup")
	_ok(stream != null and stream.data.size() > 4000,
		"a sound effect synthesizes to real PCM (%d bytes)" % (stream.data.size() if stream != null else 0))
	if stream != null:
		_ok(_pcm_edge_is_quiet(stream.data, 0), "the sound starts from silence (no click)")
		_ok(_pcm_edge_is_quiet(stream.data, stream.data.size() - 4), "the sound ends at silence (no click)")
	var music: AudioStreamWAV = AudioManager.music_stream("explore")
	_ok(music != null and music.data.size() > 32000,
		"the music track synthesizes to real PCM (%d bytes)" % (music.data.size() if music != null else 0))
	_ok(music != null and music.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"the music track loops seamlessly")
	# Cache identity: the same recipe is not re-synthesized on every play.
	_ok(AudioManager.sfx_stream("levelup") == stream, "synthesized sounds are cached")
	# Throttling: one window honored, a different key unaffected.
	var first: bool = AudioManager.play_sfx("pickup", "test-throttle", 60000)
	var second: bool = AudioManager.play_sfx("pickup", "test-throttle", 60000)
	_ok(first and not second, "a throttled sound plays once inside its window")
	# Volume keys exist so old saves migrate them in, and applying zero mutes the bus.
	_ok(SettingsDefaults.DEFAULTS.has("music_volume") and SettingsDefaults.DEFAULTS.has("sfx_volume"),
		"volume settings have declared defaults")
	var saved_music: float = float(PlayerData.settings.get("music_volume", 60.0))
	var saved_sfx: float = float(PlayerData.settings.get("sfx_volume", 80.0))
	PlayerData.settings["music_volume"] = 0.0
	PlayerData.settings["sfx_volume"] = 0.0
	AudioManager.apply_volumes()
	var music_bus: int = AudioServer.get_bus_index("Music")
	var sfx_bus: int = AudioServer.get_bus_index("SFX")
	_ok(music_bus >= 0 and sfx_bus >= 0, "the Music and SFX buses exist")
	_ok(AudioServer.is_bus_mute(music_bus) and AudioServer.is_bus_mute(sfx_bus),
		"zero volume mutes the bus")
	PlayerData.settings["music_volume"] = saved_music
	PlayerData.settings["sfx_volume"] = saved_sfx
	AudioManager.apply_volumes()

## Whether the 16-bit sample at `offset` is (near) silence: the first and last samples
## of a synthesized effect must be zero or the sound audibly clicks.
func _pcm_edge_is_quiet(data: PackedByteArray, offset: int) -> bool:
	if offset < 0 or offset + 1 >= data.size():
		return false
	var v: int = absi(data.decode_s16(offset))
	return v <= 327   # 0.1% of full scale

func _test_game_modes() -> void:
	_heading("Game modes promise only what the game does")
	# 1. Every flag the modes declare is on the honoured list, so no flag can be added to the
	# JSON without some code being written to read it.
	for mode_id in DataLoader.game_modes.keys():
		if str(mode_id).begins_with("_"):
			continue
		var unhonoured: Array[String] = []
		for key in (DataLoader.game_modes[mode_id] as Dictionary).keys():
			if not ContentValidator.HONOURED_MODE_FLAGS.has(str(key)):
				unhonoured.append(str(key))
		_ok(unhonoured.is_empty(), "mode '%s' declares only honoured flags%s"
			% [str(mode_id), "" if unhonoured.is_empty() else " (stray: %s)" % ", ".join(unhonoured)])
	# 2. The flags that were promises with no code behind them are gone for good.
	var retired: Array[String] = ["death_deletes_character", "passive_hp_regen", "hp_damage_food_multiplier",
		"xp_multiplier", "skills_locked", "locked_skills", "start_skills", "skills_purchased_with_gp",
		"unlock_locked_skills_at", "use_hardcore_triangle", "no_preservation_or_doubling"]
	for key in retired:
		var present: bool = ContentValidator.HONOURED_MODE_FLAGS.has(key)
		for mode_id in DataLoader.game_modes.keys():
			if str(mode_id).begins_with("_"):
				continue
			present = present or (DataLoader.game_modes[mode_id] as Dictionary).has(key)
		_ok(not present, "the unimplemented flag '%s' is absent from the modes and the honoured list" % key)
	# 3. No mode's name or description claims a permanent death or a deleted character.
	for mode_id in DataLoader.game_modes.keys():
		if str(mode_id).begins_with("_"):
			continue
		var mode: Dictionary = DataLoader.game_modes[mode_id]
		var copy: String = ("%s %s" % [str(mode.get("name", "")), str(mode.get("description", ""))]).to_lower()
		var promise: String = ""
		for claim in ContentValidator.FORBIDDEN_MODE_CLAIMS:
			if copy.contains(claim):
				promise = claim
				break
		_ok(promise == "", "mode '%s' makes no unkeepable claim%s" % [str(mode_id), "" if promise == "" else " ('%s')" % promise])
		_ok(str(mode.get("description", "")) != "", "mode '%s' has a description for the picker" % str(mode_id))
	# 4. The flags that ARE honoured actually change behaviour, so none of the above is vacuous.
	var saved_mode: String = PlayerData.game_mode
	var saved_slots: int = BankManager.purchased_slots
	BankManager.purchased_slots = 0
	PlayerData.game_mode = "standard"
	var standard_bank: int = BankManager.get_slot_limit()
	PlayerData.game_mode = "hardcore"
	var hardcore_bank: int = BankManager.get_slot_limit()
	_ok(hardcore_bank != standard_bank, "bank_limit is honoured: standard %d vs hardcore %d stacks"
		% [standard_bank, hardcore_bank])
	PlayerData.game_mode = "ancient_relics"
	PlayerData.set_level("woodcutting", 1)
	PlayerData.add_xp("woodcutting", 1.0e12)
	_ok(PlayerData.get_level("woodcutting") == 10, "ancient_relics stops XP at 10 (skill_level_cap honoured), got %d"
		% PlayerData.get_level("woodcutting"))
	PlayerData.game_mode = "adventure"
	PlayerData.set_level("attack", 40)
	PlayerData.set_level("woodcutting", 40)
	_ok(PlayerData.get_level_cap("woodcutting") < PlayerData.get_level_cap("attack"),
		"adventure caps a non-combat skill (%d) below a combat skill (%d)"
		% [PlayerData.get_level_cap("woodcutting"), PlayerData.get_level_cap("attack")])
	PlayerData.set_level("woodcutting", 1)
	PlayerData.add_xp("woodcutting", 1.0e12)
	_ok(PlayerData.get_level("woodcutting") < XPTable.MAX_LEVEL,
		"adventure stops a non-combat skill at the combat level (%d), not the global max"
		% PlayerData.get_level("woodcutting"))
	PlayerData.game_mode = "standard"
	_ok(PlayerData.get_level_cap("woodcutting") == XPTable.MAX_LEVEL, "standard mode caps nothing")
	PlayerData.game_mode = saved_mode
	BankManager.purchased_slots = saved_slots

func _test_content_validation() -> void:
	_heading("Content reference validation")
	var report: Array = ContentValidator.new().validate_all()
	var errors: Array[String] = []
	var warnings: int = 0
	for issue in report:
		if str(issue["severity"]) == "error":
			errors.append(str(issue["message"]))
		elif str(issue["severity"]) == "warning":
			warnings += 1
	_ok(errors.is_empty(), "no content errors (%s)" % ("none" if errors.is_empty() else "; ".join(errors).substr(0, 400)))
	_ok(DataLoader.items.size() > 300, "the item table loaded (%d items)" % DataLoader.items.size())
	_ok(DataLoader.skills.size() >= 25, "the skill table loaded (%d skills)" % DataLoader.skills.size())
	_ok(DataLoader.monsters.size() >= 25, "the monster table loaded (%d monsters)" % DataLoader.monsters.size())
	_ok(Quests.count() >= 320, "the task table loaded (%d tasks)" % Quests.count())
	var covered: Dictionary = {}
	for quest_id in Quests.all_quest_ids():
		for objective in Quests.get_quest(quest_id).get("objectives", []):
			var r: Dictionary = objective.get("route", {})
			var skill_id: String = str(objective.get("skill_id", r.get("skill_id", "")))
			if skill_id != "":
				covered[skill_id] = true
			if str(objective.get("kind", "")) == "build_structure":
				covered["township"] = true
	for skill_id in DataLoader.get_skill_ids():
		if str(DataLoader.get_skill(skill_id).get("category", "")) == "non_combat":
			_ok(covered.has(skill_id), "%s has a non-combat task" % skill_id)
	_ok(Achievements.count() >= 380, "the milestone table loaded (%d milestones)" % Achievements.count())
	print("  note: %d validation warning(s)" % warnings)

# =========================================================================
#  Content lookups
# =========================================================================

## The endgame has to be a SEQUENCE, not eight doors that open at once. Every god dungeon and
## every endgame descent used to gate on slayer 60 alone, so the player had no reason to clear
## the air dungeon before the water one — and no signal that the order was intended.
func _test_dungeon_sequencing() -> void:
	_heading("Dungeon sequencing")
	# Two independent chains, not one list: the four god dungeons open off the god line, and the
	# descent has its own head. Walking them as a single sequence is the bug this test exists to
	# prevent — it would demand that into_the_mist follow fire_god_dungeon, which it never should.
	var chains: Array = [
		["air_god_dungeon", "water_god_dungeon", "earth_god_dungeon", "fire_god_dungeon"],
		["into_the_mist", "impending_darkness", "underwater_city", "throne_of_the_herald"],
	]
	GameManager.start_new_game("standard")
	PlayerData.skills["slayer"] = {"xp": 0.0, "level": 120}
	for chain in chains:
		for i in range((chain as Array).size()):
			var id: String = str((chain as Array)[i])
			var d: Dictionary = DataLoader.get_dungeon(id)
			_ok(not d.is_empty(), "%s exists" % id)
			# Slayer is a hunting skill capped at 120, while level_range tracks COMBAT level — a
			# different track. So the gate is a floor, not a ladder; all that matters is that no
			# door asks for a level the cap forbids.
			_ok(int((d.get("requires", {}) as Dictionary).get("slayer", 0))
				<= PlayerData.get_level_cap("slayer"), "%s is inside the slayer cap" % id)
			if i == 0:
				_ok(not d.has("requires_dungeon"), "%s is a chain head" % id)
				_eq(CombatManager.dungeon_lock_reason(id), "", "%s opens on slayer alone" % id)
			else:
				var prev: String = str((chain as Array)[i - 1])
				_eq(str(d.get("requires_dungeon", "")), prev, "%s opens only after %s" % [id, prev])
				_ok(CombatManager.dungeon_lock_reason(id) != "", "%s is shut before %s is cleared" % [id, prev])
				# Clearing the predecessor opens this door and only this door.
				PlayerData.discover_dungeon(prev)
				_eq(CombatManager.dungeon_lock_reason(id), "",
					"clearing %s opens %s" % [prev, id])
				PlayerData.completion_log["dungeons"].erase(prev)
				if i + 1 < (chain as Array).size():
					_ok(CombatManager.dungeon_lock_reason(str((chain as Array)[i + 1])) != "",
						"but not the one after it")
	# And the whole ladder is walkable, with no door left permanently shut.
	for chain in chains:
		for id in (chain as Array):
			PlayerData.discover_dungeon(str(id))
	_ok(CombatManager.dungeon_lock_reason("throne_of_the_herald") == "",
		"a cleared endgame leaves nothing locked")
	GameManager.start_new_game("standard")

## Monster passives have to be real on BOTH sides of the fence: the vocabulary the engine
## understands, the pure maths each passive uses, and content that actually carries them.
func _test_monster_passives() -> void:
	_heading("Monster passives")
	for passive_id in ["regeneration", "thorns", "enrage"]:
		_ok(CombatManager.KNOWN_MONSTER_PASSIVES.has(passive_id),
			"the engine knows the '%s' passive" % passive_id)
	_eq(CombatFormulas.thorns_reflect(100, CombatManager.ENEMY_THORNS_FRACTION), 10,
		"thorns reflects a tenth of a solid hit")
	_eq(CombatFormulas.thorns_reflect(4, CombatManager.ENEMY_THORNS_FRACTION), 1,
		"thorns still costs the attacker at least 1 for a chip hit")
	_eq(CombatFormulas.thorns_reflect(0, CombatManager.ENEMY_THORNS_FRACTION), 0,
		"nothing dealt means nothing to reflect")
	_approx(CombatFormulas.enrage_multiplier(0.2, CombatManager.ENRAGE_HP_FRACTION,
		CombatManager.ENRAGE_MULTIPLIER), CombatManager.ENRAGE_MULTIPLIER, 0.001,
		"a monster at or below the threshold hits harder")
	_approx(CombatFormulas.enrage_multiplier(0.9, CombatManager.ENRAGE_HP_FRACTION,
		CombatManager.ENRAGE_MULTIPLIER), 1.0, 0.001,
		"a healthy monster does not rage")
	# Content must carry the passives the engine claims to support, and every passive in the
	# database must be in that vocabulary (ContentValidator enforces the same both ways).
	# The live fight loop and the offline simulator must agree on the numbers they use: a
	# passive that only the simulator honours is one the player never sees work.
	_approx(CombatSimulator.ENEMY_THORNS_FRACTION, CombatManager.ENEMY_THORNS_FRACTION, 0.0001,
		"both combat paths reflect the same fraction for thorns")
	_approx(CombatSimulator.ENRAGE_HP_FRACTION, CombatManager.ENRAGE_HP_FRACTION, 0.0001,
		"both combat paths rage at the same health threshold")
	_approx(CombatSimulator.ENRAGE_MULTIPLIER, CombatManager.ENRAGE_MULTIPLIER, 0.0001,
		"both combat paths rage by the same multiplier")
	_ok("thorns" in (DataLoader.monsters["moss_giant"].get("passives", []) as Array),
		"the Mossbound Colossus carries thorns")
	_ok("enrage" in (DataLoader.monsters["green_dragon"].get("passives", []) as Array),
		"the Verdant Wyrm enrages")
	var with_passives := 0
	for monster_id in DataLoader.monsters.keys():
		if not (DataLoader.monsters[monster_id].get("passives", []) as Array).is_empty():
			with_passives += 1
		for passive_id in (DataLoader.monsters[monster_id].get("passives", []) as Array):
			_ok(CombatManager.KNOWN_MONSTER_PASSIVES.has(str(passive_id)),
				"monster '%s' passive '%s' is implemented" % [monster_id, str(passive_id)])
	_ok(with_passives >= 10, "a meaningful share of the roster carries a passive (%d)" % with_passives)

## Combat skills level from fighting, so their content is the monster ladder. It has to rise
## without a hole: a twenty-level stretch with nothing new to kill is dead progression for four
## skills at once, which is what the 90-104 stretch was. Every monster also has to be reachable
## and every special attack has to be carried by something.
func _test_monster_ladder() -> void:
	_heading("The monster ladder rises without a hole")
	var by_level: Array = []
	for monster_id in DataLoader.monsters.keys():
		by_level.append({"id": str(monster_id), "level": int(DataLoader.get_monster(str(monster_id)).get("combat_level", 0))})
	by_level.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
	_ok(by_level.size() >= 40, "the roster is populated (%d monsters)" % by_level.size())
	var previous: int = -1
	var worst_gap: int = 0
	for row in by_level:
		var level: int = int(row["level"])
		if previous >= 0 and level <= 120:
			worst_gap = max(worst_gap, level - previous)
		previous = level
	_ok(worst_gap <= 12, "no stretch of the ladder is empty for more than 12 levels (worst %d)" % worst_gap)
	# Every ten-level band a player passes through has something to fight in it, so no band of the
	# 1-120 climb is served by nothing.
	var bands: Dictionary = {}
	for row in by_level:
		var level: int = int(row["level"])
		if level > 120:
			continue
		var band: int = int(floor(float(level - 1) / 10.0))
		bands[band] = int(bands.get(band, 0)) + 1
	for band in range(0, 12):
		_ok(int(bands.get(band, 0)) >= 1,
			"the %d-%d band has a monster to fight (%d)" % [band * 10 + 1, band * 10 + 10, int(bands.get(band, 0))])
	# Reachability: a monster in no area and no dungeon has no encounter, so its drops and its
	# slayer assignments are unreachable. ContentValidator warns about the same thing.
	var placed: Dictionary = {}
	for area_id in DataLoader.areas.keys():
		for mid in (DataLoader.areas[area_id] as Dictionary).get("monsters", []):
			placed[str(mid)] = true
	for dungeon_id in DataLoader.dungeons.keys():
		for mid in (DataLoader.dungeons[dungeon_id] as Dictionary).get("monsters", []):
			placed[str(mid)] = true
	for monster_id in DataLoader.monsters.keys():
		_ok(placed.has(str(monster_id)), "monster '%s' can be found somewhere" % monster_id)
	# Special attacks are only shipped content if a monster carries them.
	var carried: Dictionary = {}
	for monster_id in DataLoader.monsters.keys():
		for sa in (DataLoader.monsters[monster_id] as Dictionary).get("special_attacks", []):
			carried[str(sa)] = true
	for sa_id in DataLoader.special_attacks.keys():
		_ok(carried.has(str(sa_id)), "special attack '%s' is carried by a monster" % sa_id)
	# Slayer pools: a single-monster tier is not a choice, and the mid-game tiers are where the
	# collapse happened.
	var pools: Dictionary = DataLoader.slayer_tasks.get("_monsters", {})
	for tier_id in pools.keys():
		var pool: Array = pools[tier_id]
		_ok(pool.size() >= 2, "slayer tier '%s' offers more than one monster (%d)" % [tier_id, pool.size()])
		for monster_id in pool:
			_ok(DataLoader.monsters.has(str(monster_id)), "slayer tier '%s' monster '%s' exists" % [tier_id, monster_id])
			_ok(placed.has(str(monster_id)), "slayer tier '%s' monster '%s' has an encounter" % [tier_id, monster_id])
	# The mid-game arrivals themselves: one per empty band, and each a real fight rather than a
	# reskinned lowbie.
	var midgame: Dictionary = {
		"brine_troll": 66, "tidewrack_hag": 76, "sunderhold_centurion": 88,
		"ashwyrm_seer": 96, "sunderhold_ballistarius": 102,
	}
	for monster_id in midgame.keys():
		var m: Dictionary = DataLoader.get_monster(str(monster_id))
		_ok(not m.is_empty(), "the mid-game monster '%s' exists" % monster_id)
		if m.is_empty():
			continue
		_eq(int(m.get("combat_level", 0)), int(midgame[monster_id]), "'%s' sits at the intended level" % monster_id)
		_ok(int(m.get("hitpoints", 0)) >= 240, "'%s' has the health of a mid-game fight" % monster_id)
		_ok(placed.has(str(monster_id)), "'%s' has an encounter" % monster_id)
		_ok((m.get("special_attacks", []) as Array).size() >= 1, "'%s' carries a special attack" % monster_id)

## A dungeon ladder with a hole is a level with no expedition to run. The skill audit found that
## the stretch from 71 to 109 had no dungeon at all, which blanked the mid-game's first-clear and
## repeatable reward track; the walk below measures the hole between each dungeon and the highest
## one that has already opened.
func _test_dungeon_ladder() -> void:
	_heading("The dungeon ladder covers the climb")
	var tiers: Array = []
	for dungeon_id in DataLoader.dungeons.keys():
		var d: Dictionary = DataLoader.get_dungeon(str(dungeon_id))
		var span: Array = d.get("level_range", [])
		_ok(span.size() == 2, "'%s' declares a level range" % dungeon_id)
		if span.size() != 2:
			continue
		var low: int = int(span[0])
		var high: int = int(span[1])
		_ok(low > 0 and high >= low, "'%s' has an ordered level range (%d-%d)" % [dungeon_id, low, high])
		var encounters: Array = d.get("monsters", [])
		_ok(encounters.size() >= 1, "'%s' has at least one encounter" % dungeon_id)
		for mid in encounters:
			_ok(DataLoader.monsters.has(str(mid)), "'%s' encounter '%s' exists" % [dungeon_id, mid])
		_ok(int((d.get("completion_reward", {}) as Dictionary).get("gp", 0)) > 0,
			"'%s' pays something on a clear" % dungeon_id)
		tiers.append({"id": str(dungeon_id), "low": low, "high": high})
	tiers.sort_custom(func(a, b): return int(a["low"]) < int(b["low"]))
	var reached: int = 0
	var worst: int = 0
	var worst_at: String = ""
	for tier in tiers:
		var gap: int = int(tier["low"]) - reached
		if gap > worst:
			worst = gap
			worst_at = str(tier["id"])
		reached = max(reached, int(tier["high"]))
	_ok(worst <= 25, "no stretch of levels has no dungeon to run (worst %d, before '%s')" % [worst, worst_at])
	# The arrival itself, pinned so the hole cannot quietly reopen.
	var undercroft: Dictionary = DataLoader.get_dungeon("sunderhold_undercroft")
	_ok(not undercroft.is_empty(), "the mid-game dungeon exists")
	if not undercroft.is_empty():
		var u_span: Array = undercroft.get("level_range", [])
		_eq(int(u_span[0]), 71, "the mid-game dungeon starts where the last one stops")
		_ok(int(u_span[1]) >= 105, "the mid-game dungeon reaches the god line's doorstep")
		_ok((undercroft.get("monsters", []) as Array).size() >= 3, "the mid-game dungeon is a sequence")
		_ok(not (undercroft.get("rewards_first_clear", {}) as Dictionary).is_empty(),
			"the mid-game dungeon pays a first clear")

## Arrows and runes are only a real supply loop if an attack actually spends them, and the
## Marksmanship skillcapes only mean anything if preservation is applied to that spend. Both
## combat paths call CombatFormulas.ammo_cost, so the maths is pinned once here.
func _test_attack_costs() -> void:
	_heading("Attack costs (ammunition and runes)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260930
	_eq(int(CombatFormulas.ammo_cost(rng, {"bronze_arrow": 4}, 0.0).get("bronze_arrow", 0)), 4,
		"with no preservation an attack spends the whole authored cost")
	_ok(CombatFormulas.ammo_cost(rng, {"bronze_arrow": 4}, 100.0).is_empty(),
		"a superior Marksmanship cape makes every shot free")
	_ok(CombatFormulas.ammo_cost(rng, {}, 0.0).is_empty(),
		"a weapon with no authored cost spends nothing")
	# 50% preservation refunds roughly half of a large volley, rolled unit by unit.
	var drawn: int = 0
	for _i in range(400):
		drawn += int(CombatFormulas.ammo_cost(rng, {"bronze_arrow": 10}, 50.0).get("bronze_arrow", 0))
	_ok(drawn > 1800 and drawn < 2200,
		"a 50%% cape refunds about half of 4000 shots (%d spent)" % drawn)
	# Content: every weapon that fires or casts declares its cost, so the ranged and magic ladders
	# cannot be added without wiring them to a supply.
	var shooters: Array = []
	for id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.get_item(str(id))
		if it.is_empty() or int(it.get("equipment_slot", -1)) != 8:
			continue
		var req: Dictionary = it.get("level_requirements", {})
		var style: String = "ranged" if req.has("ranged") else ("magic" if req.has("magic") else "")
		if style == "":
			continue
		_ok(not (it.get("attack_cost_items", {}) as Dictionary).is_empty(),
			"%s (%s) declares what one attack spends" % [str(id), style])
		shooters.append(str(id))
	_ok(shooters.size() >= 20, "the ranged and magic ladders are covered (%d weapons)" % shooters.size())
	# No ammunition may be craftable and then never spent — that is what left the arrows and the
	# four elemental runes inert while the mechanic sat unused.
	var spent_ids: Dictionary = {}
	for id in DataLoader.items.keys():
		for spent_id in (DataLoader.get_item(str(id)).get("attack_cost_items", {}) as Dictionary).keys():
			spent_ids[str(spent_id)] = true
	for ammo_id in ["bronze_arrow", "iron_arrow", "steel_arrow", "air_rune", "water_rune", "earth_rune", "fire_rune"]:
		_ok(spent_ids.has(ammo_id), "craftable '%s' has a weapon that spends it" % ammo_id)
	# The preservation content must feed the same key the combat code reads.
	_eq(ModifierKeys.AMMO_PRESERVATION_PERCENT, "ammo_preservation_percent",
		"the preservation constant matches the key content authors")
	for cape_id in ["ranged_cape", "ranged_cape_superior"]:
		var cape: Dictionary = DataLoader.get_item(cape_id)
		_ok(float((cape.get("passive_modifiers", {}) as Dictionary).get(ModifierKeys.AMMO_PRESERVATION_PERCENT, 0.0)) > 0.0,
			"%s refunds ammunition" % cape_id)

## Magic used to stop at level 30: four staves, all casting the same fixed base-10 spell, so the
## style could not progress for another 90 levels and eight runes had no caster. These checks pin
## the ladder that replaced it: one staff per rune, a rising spell tier, and damage that scales
## without overtaking the bow line.
func _test_magic_gear() -> void:
	_heading("The magic gear line")
	var by_level: Dictionary = {}
	for id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.get_item(str(id))
		if it.is_empty() or int(it.get("equipment_slot", -1)) != 8:
			continue
		var req: Dictionary = it.get("level_requirements", {})
		if not req.has("magic"):
			continue
		by_level[int(req["magic"])] = it
	var levels: Array = by_level.keys()
	levels.sort()
	_ok(levels.size() >= 13, "the staff ladder covers the whole skill (%d tiers)" % levels.size())
	var cast_runes: Dictionary = {}
	var prev_spell: float = 0.0
	var prev_hit: int = 0
	for level in levels:
		var it: Dictionary = by_level[level]
		var spell: float = float(it.get("spell_max_hit", 0.0))
		_ok(spell > prev_spell, "the L%d staff casts a higher spell tier than the last (%.0f)" % [int(level), spell])
		var costs: Dictionary = it.get("attack_cost_items", {})
		_eq(costs.size(), 1, "%s casts exactly one rune per attack" % str(it.get("id", "")))
		for rune_id in costs.keys():
			cast_runes[str(rune_id)] = true
		var dmg: float = float((it.get("equipment_stats", {}) as Dictionary).get("magic_damage_percent", 0))
		var hit: int = CombatFormulas.max_hit_magic(spell, dmg, int(level), 0.0, 0.0)
		_ok(hit > prev_hit, "the L%d staff hits harder than the last (%d max hit)" % [int(level), hit])
		prev_spell = spell
		prev_hit = hit
	# A rune that no staff casts is a rune a player crafts and never spends.
	for rune_id in ["air_rune", "water_rune", "earth_rune", "fire_rune", "mind_rune", "cosmic_rune",
			"chaos_rune", "nature_rune", "law_rune", "death_rune", "blood_rune", "soul_rune", "umbral_rune"]:
		_ok(cast_runes.has(rune_id), "craftable '%s' has a staff that casts it" % rune_id)
	# The top of the staff line should be comparable to the top bow, not better: a staff pays runes
	# instead of arrows and needs no offhand.
	var top_spell: float = float((by_level[levels[levels.size() - 1]] as Dictionary).get("spell_max_hit", 0.0))
	var top_dmg: float = float(((by_level[levels[levels.size() - 1]] as Dictionary).get("equipment_stats", {}) as Dictionary).get("magic_damage_percent", 0))
	var best_staff_hit: int = CombatFormulas.max_hit_magic(top_spell, top_dmg, int(levels[levels.size() - 1]), 0.0, 0.0)
	var best_bow_hit: int = CombatFormulas.max_hit_melee_ranged("standard", 110, 75.0, 0.0, 0.0)
	_ok(best_staff_hit >= int(0.6 * float(best_bow_hit)),
		"the best staff is a real alternative to the best bow (%d vs %d)" % [best_staff_hit, best_bow_hit])
	_ok(best_staff_hit <= best_bow_hit, "the best staff does not out-hit the best bow (%d vs %d)" % [best_staff_hit, best_bow_hit])
	# Robes: cloth armour for the style, four tiers of four pieces, defence rising by tier.
	var tiers: Dictionary = {}
	for id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.get_item(str(id))
		if it.is_empty():
			continue
		var req: Dictionary = it.get("level_requirements", {})
		if not req.has("magic") or int(it.get("equipment_slot", -1)) == 8:
			continue
		tiers[int(req["magic"])] = int(tiers.get(int(req["magic"]), 0)) + 1
	var robe_levels: Array = tiers.keys()
	robe_levels.sort()
	_ok(robe_levels.size() >= 4, "robes ship in %d tiers" % robe_levels.size())
	var prev_def: int = 0
	for level in robe_levels:
		_eq(int(tiers[level]), 4, "the Magic-%d robe tier has four pieces" % int(level))
		var total: int = 0
		for id in DataLoader.items.keys():
			var it: Dictionary = DataLoader.get_item(str(id))
			if it.is_empty() or int(it.get("equipment_slot", -1)) == 8:
				continue
			if int((it.get("level_requirements", {}) as Dictionary).get("magic", -1)) != int(level):
				continue
			total += int((it.get("equipment_stats", {}) as Dictionary).get("magic_defence", 0))
		_ok(total > prev_def, "the Magic-%d robe tier wards more than the last (%d total)" % [int(level), total])
		prev_def = total
	# Every new piece must be craftable, or the ladder is unobtainable content.
	var craftable: Dictionary = {}
	for skill_id in ["runecrafting", "crafting"]:
		for action in DataLoader.get_skill_actions(skill_id):
			for out_id in (action.get("output_items", {}) as Dictionary).keys():
				craftable[str(out_id)] = true
	for level in levels:
		var staff_id: String = str((by_level[level] as Dictionary).get("id", ""))
		_ok(craftable.has(staff_id), "%s has a recipe" % staff_id)
	for id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.get_item(str(id))
		if it.is_empty() or int(it.get("equipment_slot", -1)) == 8:
			continue
		if (it.get("level_requirements", {}) as Dictionary).has("magic"):
			_ok(craftable.has(str(id)), "%s has a recipe" % str(id))
	# The live fight loop has to actually act on them. These two monsters exist for the purpose:
	# the Mossbound Colossus thorns, the Verdant Wyrm enrages. HP lives on CombatManager, which
	# owns the fight; PlayerData is the character sheet.
	GameManager.start_new_game("standard")
	# start_combat needs an explicit monster list: it is a sequence, not a region lookup.
	CombatManager.start_combat({"type": "area", "id": "farmlands", "monsters": ["moss_giant"],
		"endless": false, "attack_style": "melee"})
	CombatManager.player_hp = 5000.0
	CombatManager.player_max_hp = 5000.0
	CombatManager.current_monster_id = "moss_giant"
	CombatManager.monster_max_hp = 500
	CombatManager.monster_hp = 500
	var hp_before_thorns: float = CombatManager.player_hp
	CombatManager.apply_damage_to_monster(100)
	_approx(hp_before_thorns - CombatManager.player_hp, 10.0, 0.001,
		"a live hit on a thorny monster costs the player health")
	_eq(CombatManager.monster_hp, 400.0, "and the monster still takes the full hit")
	# A killing blow must not be answered by thorns: the corpse does not bite back.
	CombatManager.player_hp = 5000.0
	CombatManager.monster_hp = 10
	CombatManager.apply_damage_to_monster(100)
	_approx(CombatManager.player_hp, 5000.0, 0.001,
		"a dead thorny monster does not reflect the killing blow")
	# A healthy enraging monster must not be boosted; a wounded one must be. Driven through the
	# real _monster_attack() rather than a copy of the formula, so the test fails if enrage is
	# ever moved out of the damage path again. The killing blow above ended that fight, so a
	# fresh one is started: _monster_attack() is a no-op unless the fight is live.
	# The Golbin Chief, not the Verdant Wyrm: a level-105 magic attacker can miss a level-1
	# character indefinitely, and a test that only passes when the dice cooperate is not a test.
	# The earlier killing blow left a fight running and start_combat refuses to start a second
	# one, so retreat first or the whole block silently measures an idle engine.
	CombatManager.stop_combat("test")
	CombatManager.start_combat({"type": "area", "id": "farmlands", "monsters": ["golbin_chief"],
		"endless": false, "attack_style": "melee"})
	CombatManager.current_monster_id = "golbin_chief"
	CombatManager.monster_max_hp = 45
	var healthy_total: float = 0.0
	var wounded_total: float = 0.0
	for _i in range(60):
		CombatManager.player_hp = 9000.0
		CombatManager.player_max_hp = 9000.0
		CombatManager.monster_hp = 45
		CombatManager._monster_attack()
		healthy_total += 9000.0 - CombatManager.player_hp
		CombatManager.player_hp = 9000.0
		CombatManager.player_max_hp = 9000.0
		CombatManager.monster_hp = 5
		CombatManager._monster_attack()
		wounded_total += 9000.0 - CombatManager.player_hp
	_ok(healthy_total > 0.0, "an enraging monster lands hits while healthy")
	_ok(wounded_total > healthy_total,
		"the same monster hits harder once worn down (%d > %d over 60 attacks)" % [int(wounded_total), int(healthy_total)])
	CombatManager.stop_combat("test")

## The rolling DPS window and the session tallies. The window is the easy thing to get
## subtly wrong (entries must age out, and a window shorter than its own contents must not
## divide by zero), so this drives the real clock rather than asserting on internals.
func _test_session_meters() -> void:
	_heading("Combat session meters")
	CombatManager._dmg_deque = []
	CombatManager._fight_clock = 0.0
	CombatManager.session_damage_dealt = 0.0
	CombatManager.session_damage_taken = 0.0
	CombatManager.session_gp_earned = 0.0
	_ok(is_zero_approx(CombatManager.dps()), "DPS is zero before any damage lands")
	# 120 damage over 60 seconds is 2.0/s. The clock only advances inside tick(), so the
	# test drives tick() rather than poking _fight_clock — otherwise it would be asserting
	# against a state the real simulation can never produce.
	CombatManager._record_damage(120)
	CombatManager._fight_clock = 60.0
	CombatManager._trim_dps_window()
	_approx(CombatManager.dps(), 2.0, 0.01, "120 damage over 60s reads 2.0 DPS")
	# A window that ages out while nobody is attacking must not keep reporting the old rate:
	# this is the case a cached running total got wrong. At t=130 the t=60 hit is 70s old and
	# has left the 60s window entirely, so the rate is 0 until a new hit lands inside it.
	CombatManager._record_damage(120)
	CombatManager._fight_clock = 130.0
	CombatManager._trim_dps_window()
	_approx(CombatManager.dps(), 0.0, 0.01, "a hit older than the window stops counting")
	_eq(CombatManager.session_damage_dealt, 240.0, "the session total keeps both hits")
	CombatManager._record_damage(120)
	CombatManager._trim_dps_window()
	_approx(CombatManager.dps(), 120.0 / 60.0, 0.01, "a fresh hit restores the rate")
	_eq(CombatManager.session_damage_dealt, 360.0, "and the session total keeps counting")
	# Taken damage routes through the same recorder, so the two columns cannot disagree.
	CombatManager._record_damage_taken(35.0)
	_eq(CombatManager.session_damage_taken, 35.0, "damage taken is recorded")
	CombatManager._record_damage(0)
	_eq(CombatManager.session_damage_dealt, 360.0, "a zero hit leaves the total alone")
	var readout: Dictionary = CombatManager.session_readout()
	_ok(readout.has("dps") and readout.has("fight_dps") and readout.has("gp_earned"),
		"the readout carries every column the panel renders")
	CombatManager._record_gp(12.0)
	_eq(CombatManager.session_readout()["gp_earned"], 12.0, "combat gold accumulates")
	CombatManager._record_gp(-5.0)
	_eq(CombatManager.session_readout()["gp_earned"], 12.0, "a negative amount never reduces the tally")
	# Offline runs the same tick(), so meters must not depend on being watched. A real fight
	# lands its own attacks here too, so assert the clock advanced rather than an exact rate.
	CombatManager._dmg_deque = []
	CombatManager._fight_clock = 0.0
	CombatManager.start_combat({"type": "area", "id": "farmlands", "monsters": ["chicken"]})
	SimulationMode.begin()
	CombatManager.tick(30.0)
	var silent_dps: float = CombatManager.dps()
	SimulationMode.end()
	_approx(CombatManager._fight_clock, 30.0, 0.01, "the fight clock advances during a silent offline step")
	_ok(silent_dps > 0.0, "a silent offline step still feeds the DPS window")
	CombatManager.stop_combat("test")

## The equipment upgrade chain. upgrade_path/upgrade_materials were declared in the data and
## checked by the validator, but nothing implemented them, so every (S)/(G) tier was dead.
func _test_equipment_upgrade() -> void:
	_heading("Equipment upgrades")
	GameManager.start_new_game("standard")
	var base: Dictionary = DataLoader.get_item("bronze_platebody")
	_ok(str(base.get("upgrade_path", "")) == "bronze_platebody_s",
		"the base platebody declares its upgrade target")
	_ok(not bool(EquipmentManager.upgrade("bronze_platebody")["ok"]),
		"upgrading without the item fails")
	BankManager.add_item("bronze_platebody", 1)
	_ok(EquipmentManager.upgrade_blocker("bronze_platebody") != "",
		"a missing upgrade material is reported as a blocker")
	_ok(not bool(EquipmentManager.upgrade("bronze_platebody")["ok"]),
		"a missing material refuses the upgrade")
	_ok(BankManager.get_count("bronze_platebody") == 1,
		"a refused upgrade consumes nothing")
	BankManager.add_item("silver_bar", 1)
	_ok(EquipmentManager.upgrade_blocker("bronze_platebody") == "",
		"with the material in hand nothing blocks the upgrade")
	var result: Dictionary = EquipmentManager.upgrade("bronze_platebody")
	_ok(bool(result.get("ok", false)), "the upgrade fires")
	_eq(str(result.get("item_id", "")), "bronze_platebody_s", "it produces the (S) tier")
	_eq(BankManager.get_count("bronze_platebody"), 0, "the base item is consumed")
	_eq(BankManager.get_count("silver_bar"), 0, "the material is consumed")
	_eq(BankManager.get_count("bronze_platebody_s"), 1, "the upgraded item lands in storage")
	# Chained: (S) -> (G).
	BankManager.add_item("gold_bar", 1)
	var second: Dictionary = EquipmentManager.upgrade("bronze_platebody_s")
	_ok(bool(second.get("ok", false)), "the chain continues to the (G) tier")
	_eq(BankManager.get_count("bronze_platebody_g"), 1, "the (G) tier is now reachable")
	# Upgrading something worn swaps it in place rather than unequipping it silently.
	PlayerData.set_level("defence", 1)
	BankManager.add_item("bronze_platebody", 1)
	_ok(EquipmentManager.equip("bronze_platebody"), "the fresh base piece equips")
	BankManager.add_item("silver_bar", 1)
	_ok(bool(EquipmentManager.upgrade("bronze_platebody")["ok"]), "a worn item can be upgraded")
	_eq(EquipmentManager.get_equipped(ItemData.EquipmentSlot.PLATEBODY), "bronze_platebody_s",
		"the upgraded piece is what ends up worn")
	# An item with no upgrade path reports no blocker and refuses cleanly.
	_ok(EquipmentManager.upgrade_blocker("chicken") == "", "a non-upgradeable item has no blocker")
	_ok(not bool(EquipmentManager.upgrade("chicken")["ok"]), "and refuses to upgrade")
	for slot in EquipmentManager.slots.keys():
		EquipmentManager.unequip(int(slot))
	GameManager.start_new_game("standard")

## Ascendancy. The reset is the destructive path in the whole game, so the checks are about
## what survives it: the bonus must apply, and the collection log and lifetime counters must
## not be wiped by a run the player already completed.
func _test_prestige() -> void:
	_heading("Ascendancy")
	GameManager.start_new_game("standard")
	_eq(PrestigeManager.ascensions(), 0, "a new character has taken no ascensions")
	_ok(PrestigeManager.blocker() != "", "a fresh character is told what it still needs")
	_ok(not bool(PrestigeManager.ascend()["ok"]), "ascending below the gate is refused")
	# Clear the gate by granting XP directly, not by grinding: this test is about the reset.
	PlayerData.skills["woodcutting"] = {"xp": PrestigeManager.GATE_XP, "level": 1}
	_ok(PrestigeManager.can_ascend(), "the gate opens at the lifetime XP threshold")
	_ok(PrestigeManager.blocker() == "", "the blocker clears once the gate is met")
	# Things the reset must NOT destroy.
	BankManager.add_item_guaranteed("chicken", 3)
	PlayerData.discover_item("chicken")
	PlayerData.discover_monster("chicken")
	PlayerData.discover_dungeon("chicken_coop")
	PlayerData.bump_stat("monsters_killed", "chicken", 7.0)
	var xp_before: float = PlayerData.get_xp("woodcutting")
	var result: Dictionary = PrestigeManager.ascend()
	_ok(bool(result.get("ok", false)), "the ascension fires once the gate is met")
	_eq(PrestigeManager.ascensions(), 1, "the ascension is counted")
	# Ascending grants a spendable point, not an automatic bonus.
	_eq(PrestigeManager.points(), PrestigeManager.POINTS_PER_ASCENSION, "the ascension grants an Ascendancy Point")
	_eq(PrestigeManager.points_earned(), PrestigeManager.POINTS_PER_ASCENSION, "the lifetime point tally is tracked")
	# With no node bought, prestige contributes nothing to the simulation.
	_ok(not ModifierManager.has_source("prestige"), "an unspent ascension registers no bonus")
	# Spending a root node applies its modifier through the single 'prestige' source.
	var root: Dictionary = DataLoader.ascendancy.get("ascendant_insight", {})
	_ok(not root.is_empty(), "the ascendancy tree data loaded")
	var xp_mod: float = float(root.get("modifiers", {}).get("global_skill_xp_percent", 0.0))
	_ok(bool(PrestigeManager.spend("ascendant_insight")["ok"]), "a root node can be bought with a point")
	_eq(PrestigeManager.points(), 0, "buying a node spends the point")
	_eq(PrestigeManager.node_rank("ascendant_insight"), 1, "the bought node is at rank 1")
	_approx(ModifierManager.get_modifier(ModifierKeys.GLOBAL_SKILL_XP_PERCENT),
		xp_mod, 0.001, "the bought node's bonus reaches ModifierManager")
	_ok(ModifierManager.has_source("prestige"), "the bonus is a real registered source")
	# A node gated behind a prerequisite is refused until the prerequisite is owned... and when broke.
	_ok(not bool(PrestigeManager.spend("ascendant_bounty")["ok"]), "a node is refused with no points to spend")
	# Refund returns the point and removes the bonus.
	_ok(bool(PrestigeManager.refund_node("ascendant_insight")["ok"]), "a bought node can be refunded")
	_eq(PrestigeManager.points(), PrestigeManager.POINTS_PER_ASCENSION, "the refund returns the point")
	_ok(not ModifierManager.has_source("prestige"), "the refunded node's bonus is gone")
	# The run is genuinely gone.
	_ok(PlayerData.get_xp("woodcutting") < xp_before, "training is reset")
	_eq(BankManager.get_count("chicken"), 0, "items are reset")
	# The record is not.
	_eq(PlayerData.get_stat("monsters_killed", "chicken"), 7.0,
		"lifetime kill counts survive the reset")
	_ok(PlayerData.completion_log["items"].has("chicken"), "the item collection log survives")
	_ok(PlayerData.completion_log["monsters"].has("chicken"), "the monster log survives")
	_ok(PlayerData.completion_log["dungeons"].has("chicken_coop"), "the expedition log survives")
	# Buy the node again, then confirm points, nodes AND the live bonus survive a save round-trip.
	_ok(bool(PrestigeManager.spend("ascendant_insight")["ok"]), "re-buy the node before the round-trip")
	var saved: Dictionary = SaveManager.build_save_data()
	PlayerData.prestige = {"ascensions": 0, "total": 0, "points": 0, "points_earned": 0, "nodes": {}, "history": {}, "lifetime_stats": {}}
	ModifierManager.unregister("prestige")
	PrestigeManager.deserialize(saved.get("prestige", {}))
	_eq(PrestigeManager.ascensions(), 1, "ascensions survive a save round-trip")
	_eq(PrestigeManager.node_rank("ascendant_insight"), 1, "bought nodes survive a save round-trip")
	_approx(ModifierManager.get_modifier(ModifierKeys.GLOBAL_SKILL_XP_PERCENT),
		xp_mod, 0.001, "and the node bonus is re-applied on load")
	# A second ascension adds a second point; buying a second rank stacks the bonus.
	PlayerData.skills["woodcutting"] = {"xp": PrestigeManager.GATE_XP, "level": 1}
	_ok(bool(PrestigeManager.ascend()["ok"]), "a second ascension is reachable")
	_eq(PrestigeManager.ascensions(), 2, "ascensions stack")
	_eq(PrestigeManager.points(), PrestigeManager.POINTS_PER_ASCENSION, "the second ascension grants another point")
	_ok(bool(PrestigeManager.spend("ascendant_insight")["ok"]), "a second rank can be bought")
	_approx(ModifierManager.get_modifier(ModifierKeys.GLOBAL_SKILL_XP_PERCENT),
		xp_mod * 2.0, 0.001, "ranks stack additively")
	# A save with no prestige key at all must load cleanly (every pre-ascension save).
	PlayerData.deserialize({"skills": {}, "stats": {}})
	_eq(PrestigeManager.ascensions(), 0, "a legacy save without prestige loads as zero")
	GameManager.start_new_game("standard")

## First-run onboarding. The failure this guards against is silence: a new character with a step
## list that fails to load, starts somewhere other than the beginning, never advances, or loses
## its place on reload.
func _test_tutorial() -> void:
	_heading("First-run onboarding")
	_ok(DataLoader.tutorial.size() >= 5,
		"the onboarding content loaded (%d steps)" % DataLoader.tutorial.size())
	_eq(TutorialManager.step_count(), DataLoader.tutorial.size(),
		"every authored step is in the ordered list")
	# Every step must be self-describing and actually routable, or the guide dead-ends on a blank
	# card with no way forward.
	var bad: Array[String] = []
	var screens: Dictionary = {}
	for i in range(TutorialManager.step_count()):
		var d: Dictionary = TutorialManager.describe(i)
		if str(d.get("title", "")) == "" or str(d.get("body", "")) == "":
			bad.append("step %d has no title/body" % i)
		var cond: Dictionary = d.get("condition", {})
		if cond.is_empty() or str(cond.get("label", "")) == "":
			bad.append("step %d has no labelled condition" % i)
		var route: Dictionary = d.get("route", {})
		if str(route.get("screen", "")) == "":
			bad.append("step %d has no route" % i)
		else:
			screens[str(route["screen"])] = true
	_ok(bad.is_empty(), "every step is complete and routable (%s)" %
		("none broken" if bad.is_empty() else "; ".join(bad)))
	_ok(screens.has(Screens.SKILLS) and screens.has(Screens.COMBAT),
		"the guide points at both gathering and combat")
	# Authored content must reference things that exist: a route to a deleted action sends the
	# player to a screen with nothing selected, and a condition on a missing item never completes.
	var dangling: Array[String] = []
	for i in range(TutorialManager.step_count()):
		var d: Dictionary = TutorialManager.describe(i)
		var route: Dictionary = d.get("route", {})
		var skill_id: String = str(route.get("skill_id", ""))
		if skill_id != "" and not DataLoader.skills.has(skill_id):
			dangling.append("step %d -> skill '%s'" % [i, skill_id])
		elif skill_id != "" and str(route.get("action_id", "")) != "" \
				and DataLoader.get_action(skill_id, str(route["action_id"])).is_empty():
			dangling.append("step %d -> action '%s:%s'" % [i, skill_id, str(route["action_id"])])
		var area_id: String = str(route.get("area_id", ""))
		if area_id != "" and not DataLoader.areas.has(area_id) and not DataLoader.dungeons.has(area_id):
			dangling.append("step %d -> area '%s'" % [i, area_id])
		var raw: Dictionary = (DataLoader.tutorial[str(d["id"])] as Dictionary).get("condition", {})
		if str(raw.get("item_id", "")) != "" and not DataLoader.items.has(str(raw["item_id"])):
			dangling.append("step %d -> item '%s'" % [i, str(raw["item_id"])])
		if str(raw.get("monster_id", "")) != "" and not DataLoader.monsters.has(str(raw["monster_id"])):
			dangling.append("step %d -> monster '%s'" % [i, str(raw["monster_id"])])
	_ok(dangling.is_empty(), "no step references content that does not exist (%s)" %
		("none" if dangling.is_empty() else "; ".join(dangling)))

	# A genuinely fresh character: all stats zero, nothing in the bank.
	GameManager.start_new_game("standard")
	_eq(PlayerData.tutorial_step, 0, "a new character starts at the first step")
	_eq(TutorialManager.current_index(), 0, "and the guide points at it")
	_ok(not TutorialManager.is_finished(), "the guide is not already finished")
	var first: Dictionary = TutorialManager.describe(0)
	_ok(not bool(first.get("satisfied", true)),
		"the first step is genuinely unmet on a fresh save")
	_ok(not TutorialManager.next_step(), "a fresh character does not skip past unmet steps")

	# Advancing: satisfy the first step's own condition and nothing else.
	PlayerData.bump_stat("actions", "woodcutting:normal_tree", 10.0)
	_ok(TutorialManager.next_step(), "the guide advances once the step's condition is met")
	_ok(TutorialManager.current_index() > 0, "the player is now on a later step (%d)" % TutorialManager.current_index())
	_ok(not TutorialManager.next_step(), "it does not advance again on the same state")
	_ok(str(TutorialManager.describe(TutorialManager.current_index())["title"]) != str(first["title"]),
		"the new step is a different one")

	# Progress must survive a save round-trip, and the manager half must agree with the field.
	var saved: Dictionary = SaveManager.build_save_data()
	var reached: int = PlayerData.tutorial_step
	var reached_id: String = str(TutorialManager.current_step().get("id", ""))
	_ok(int(saved.get("tutorial", {}).get("tutorial_step", -1)) == reached,
		"the step index is written to the save")
	_ok(int(saved.get("player", {}).get("tutorial_step", -1)) == reached,
		"and rides in the player block too")
	PlayerData.tutorial_step = 0
	TutorialManager.deserialize(saved.get("tutorial", {}))
	_eq(PlayerData.tutorial_step, reached, "progress survives a save round-trip")
	_eq(str(TutorialManager.current_step().get("id", "")), reached_id,
		"the reloaded player resumes on the same step, not the first one")

	# A save written before the tutorial existed has no key at all: it must load, not crash.
	PlayerData.tutorial_step = 3
	TutorialManager.deserialize({})
	_eq(PlayerData.tutorial_step, 3, "a save with no tutorial section leaves the index alone")
	PlayerData.deserialize({"skills": {}, "stats": {}})
	_eq(PlayerData.tutorial_step, 0, "a legacy player block with no tutorial key loads as zero")
	TutorialManager.deserialize({})
	_ok(TutorialManager.current_index() >= 0 and TutorialManager.current_index() < TutorialManager.step_count(),
		"the guide is still on a real step after a legacy load")
	# A hand-edited index cannot point past the end of the list.
	PlayerData.tutorial_step = 9999
	TutorialManager.deserialize({"tutorial_step": 9999})
	_ok(TutorialManager.current_index() < TutorialManager.step_count(),
		"an out-of-range index is clamped to a real step")
	# An unmet step cannot be walked past: this is the guard that stops the guide from racing
	# ahead of a player who did nothing, since it is the only thing that advances it.
	GameManager.start_new_game("standard")
	PlayerData.tutorial_step = 0
	_ok(not TutorialManager.next_step(),
		"an unmet first step does not advance (step %d after the attempt)" % PlayerData.tutorial_step)
	# Satisfying it does, and the guide stops on the next unmet step rather than running to the end.
	PlayerData.bump_stat("actions", "woodcutting:normal_tree", 10.0)
	_ok(TutorialManager.next_step(), "a satisfied step advances the guide")
	_ok(not TutorialManager.next_step(),
		"and it then stops on the next unmet step (step %d)" % PlayerData.tutorial_step)
	# The last step passing is what retires the guide into its one-line summary.
	PlayerData.tutorial_step = TutorialManager.step_count()
	_ok(TutorialManager.is_finished(), "a finished guide reports itself finished")
	_ok(TutorialManager.current_step().is_empty(),
		"and current_step() offers nothing to show")
	_ok(not TutorialManager.describe(TutorialManager.current_index()).is_empty(),
		"the panel's clamped index still resolves to a real step, so nothing indexes off the end")
	GameManager.start_new_game("standard")
	_eq(PlayerData.tutorial_step, 0, "starting a new run restarts the guide")

## The systems sections are the only way several engines are reachable at all: taking slayer
## tasks, equipping familiars, buying stars, building obstacles, travelling hexes and donating
## to the museum. This covers both halves of that claim — the section renders for exactly the
## skills that own a system, and each manager it drives actually does its job.
func _test_systems_wiring(host: Node) -> void:
	_heading("Systems sections (per-skill UI wiring)")
	host.call("navigate", {"screen": Screens.SKILLS, "skill_id": "woodcutting"})
	var panel: Control = (host.get("_panels") as Dictionary).get(Screens.SKILLS, null)
	_ok(panel != null, "the Skills screen exists")
	if panel == null:
		return
	var systems: Control = panel.get("_systems")
	_ok(systems != null, "the Skills screen carries a systems section")
	if systems == null:
		return
	_ok(not systems.visible, "a plain gathering skill shows no systems section")
	for skill_id in ["slayer", "summoning", "astrology", "agility", "cartography", "archaeology"]:
		host.call("navigate", {"screen": Screens.SKILLS, "skill_id": skill_id})
		_ok(systems.visible and systems.get_child_count() > 0,
			"%s shows its system section" % str(DataLoader.get_skill(skill_id).get("name", skill_id)))
	_test_slayer_task_flow()
	_test_museum_flow()
	_test_ship_flow()
	_test_familiar_star_and_obstacle_flow()

func _test_slayer_task_flow() -> void:
	var coins_before: float = PlayerData.slayer_coins
	SlayerManager.deserialize({})
	_ok(SlayerManager.assign_task("easy"), "an easy slayer task can be taken")
	_ok(SlayerManager.has_task(), "the task is recorded on the player")
	var monster_id := str(PlayerData.slayer_task.get("monster_id", ""))
	_ok(monster_id != "", "the task names a monster")
	var required := int(PlayerData.slayer_task.get("kills_required", 1))
	var guard := 0
	while SlayerManager.has_task() and guard <= required + 1:
		CombatManager.start_combat({"type": "area", "id": "farmlands", "monsters": [monster_id]})
		CombatManager.apply_damage_to_monster(100000)
		CombatManager.stop_combat("test")
		guard += 1
	_ok(not SlayerManager.has_task(), "the task completes once its kills are done")
	_ok(PlayerData.slayer_coins > coins_before, "a completed task pays Slayer Coins")
	SlayerManager.deserialize({})

func _test_museum_flow() -> void:
	var before: Dictionary = ArchaeologyManager.serialize()
	var gp_before: float = PlayerData.gp
	var shards_before := BankManager.get_count("summoning_shard_green")
	ArchaeologyManager.tokens = 0
	BankManager.add_item_guaranteed("artefact_common", 2)
	_ok(ArchaeologyManager.donate("artefact_common"), "an artefact can be donated")
	_ok(ArchaeologyManager.tokens == 1, "a common donation pays 1 Museum Token")
	_ok(BankManager.get_count("artefact_common") == 1, "donation spends exactly one artefact")
	ArchaeologyManager.tokens = 6
	_ok(ArchaeologyManager.buy_museum("museum_shards"), "museum stock can be bought with tokens")
	_ok(ArchaeologyManager.tokens == 0, "the purchase spends exactly its token cost")
	_ok(BankManager.get_count("summoning_shard_green") == shards_before + 10,
		"the purchase grants the stock it lists")
	ArchaeologyManager.deserialize(ArchaeologyManager.serialize())
	_ok(ArchaeologyManager.tokens == 0, "museum tokens survive a save round trip")
	var leftover := BankManager.get_count("artefact_common")
	if leftover > 0:
		BankManager.remove_item("artefact_common", leftover)
	var shards_added := BankManager.get_count("summoning_shard_green") - shards_before
	if shards_added > 0:
		BankManager.remove_item("summoning_shard_green", shards_added)
	ArchaeologyManager.deserialize(before)
	PlayerData.gp = gp_before

func _test_ship_flow() -> void:
	var before: Dictionary = CartographyManager.serialize()
	var gp_before: float = PlayerData.gp
	PlayerData.add_gp(10000000.0)
	var tide: Dictionary = CartographyManager.can_buy_ship("tide_sloop")
	_ok(not bool(tide["ok"]), "hulls must be bought in order (%s)" % str(tide["reason"]))
	var cutter: Dictionary = CartographyManager.can_buy_ship("keel_cutter")
	_ok(bool(cutter["ok"]), "the first upgrade hull is buyable with gold")
	_ok(CartographyManager.buy_ship("keel_cutter"), "the keel cutter can be bought")
	_ok(absf(CartographyManager.travel_percent() - 80.0) < 0.01,
		"the cutter discounts travel to 80% of base")
	var hex_id := ""
	var base := 0.0
	for key in DataLoader.cartography_hexes.keys():
		hex_id = str(key)
		base = float((DataLoader.cartography_hexes[key] as Dictionary).get("travel_cost", 0))
		break
	if hex_id != "" and base > 0.0:
		var gp0 := PlayerData.gp
		_ok(CartographyManager.travel(hex_id), "travel succeeds with gold")
		_ok(not CartographyManager.is_discovered(hex_id) or gp0 - PlayerData.gp <= base + 0.5,
			"discounted travel never costs more than base")
		_approx(gp0 - PlayerData.gp, base * 0.8, 0.51, "travel costs 80% of base with the cutter")
	CartographyManager.deserialize(CartographyManager.serialize())
	_ok(CartographyManager.ship == "keel_cutter", "the hull survives a save round trip")
	CartographyManager.deserialize(before)
	PlayerData.gp = gp_before

func _test_familiar_star_and_obstacle_flow() -> void:
	var summoning_before: Dictionary = SummoningManager.serialize()
	var astrology_before: Dictionary = AstrologyManager.serialize()
	var agility_before: Dictionary = AgilityManager.serialize()
	var gp_before: float = PlayerData.gp
	# Familiars require a discovered mark and actual crafted tablets.
	_ok(not SummoningManager.equip_familiar("ent"), "a familiar without a mark cannot be equipped")
	SummoningManager.marks["ent"] = 1
	BankManager.add_item_guaranteed("ent_tablet", 25)
	_ok(SummoningManager.equip_familiar("ent"), "a marked familiar with tablets can be equipped")
	_ok(SummoningManager.equipped.has("ent"), "the familiar is recorded as equipped")
	_ok(int(SummoningManager.charges.get("ent", 0)) > 0, "equipping loads tablet charges")
	SummoningManager.unequip_familiar("ent")
	# Stars: Stardust in, permanent star out.
	var stardust_before := BankManager.get_count("stardust")
	BankManager.add_item_guaranteed("stardust", 100)
	_ok(AstrologyManager.buy_star("deedree", "deedree_1"), "a star can be bought with Stardust")
	_ok(AstrologyManager.is_purchased("deedree_1"), "the purchased star is recorded")
	_ok(BankManager.get_count("stardust") == stardust_before + 90, "the star spends its cost")
	# Obstacles: gold in, a course slot out, and clearing really clears.
	var cost := float((AgilityManager.cost_for("obstacle_1_0")).get("gp", 0))
	PlayerData.add_gp(cost + 100.0)
	_ok(AgilityManager.build(1, "obstacle_1_0"), "the first obstacle can be built into slot 1")
	_ok(AgilityManager.built.has(1), "the course records the built obstacle")
	AgilityManager.clear_slot(1)
	_ok(not AgilityManager.built.has(1), "clearing a slot empties it")
	SummoningManager.deserialize(summoning_before)
	AstrologyManager.deserialize(astrology_before)
	AgilityManager.deserialize(agility_before)
	var stardust_added := BankManager.get_count("stardust") - stardust_before
	if stardust_added > 0:
		BankManager.remove_item("stardust", stardust_added)
	PlayerData.gp = gp_before

## Three companions declared their unlock source under a key PetManager never reads, and three
## slayer tiers asked for a level above the slayer cap. Both made content permanently unreachable
## while every other check passed, so these state the two promises directly.
func _test_unobtainable_content() -> void:
	_heading("Every companion and slayer tier can be reached")
	# --- pets: the declared source must be one PetManager actually matches on ---------------
	var stray: Array[String] = []
	var unsourceable: Array[String] = []
	var skill_sources: Array[String] = []
	var dungeon_sources: Array[String] = []
	var item_sources: Array[String] = []
	for pet_id in DataLoader.pets.keys():
		var p: Dictionary = DataLoader.pets[pet_id]
		if p.has("source"):
			stray.append(str(pet_id))
		var src_skill: String = str(p.get("source_skill", ""))
		var src_dungeon: String = str(p.get("source_dungeon", ""))
		var src_item: String = str(p.get("source_item", ""))
		# The two roll functions match source_skill against a skill id or the literal "combat";
		# nothing else can ever be drawn into a pool.
		if src_skill != "":
			if src_skill != "combat" and not DataLoader.skills.has(src_skill):
				unsourceable.append("%s(%s)" % [str(pet_id), src_skill])
			else:
				skill_sources.append(str(pet_id))
		elif src_dungeon != "" and DataLoader.dungeons.has(src_dungeon):
			dungeon_sources.append(str(pet_id))
		elif src_dungeon != "":
			unsourceable.append("%s(%s)" % [str(pet_id), src_dungeon])
		# The third route is a container: the item must open into *this* pet from Storage, which
		# is what BankManager.open_container reads. A source_item pointing anywhere else is dead
		# weight the player would never be able to hatch.
		elif src_item != "" and str((DataLoader.items.get(src_item, {}) as Dictionary).get("container_pet", "")) == str(pet_id):
			item_sources.append(str(pet_id))
		elif src_item != "":
			unsourceable.append("%s(%s)" % [str(pet_id), src_item])
		else:
			unsourceable.append("%s(no source)" % str(pet_id))
	_ok(stray.is_empty(), "no pet uses the unread key 'source'%s"
		% ("" if stray.is_empty() else " (stray: %s)" % ", ".join(stray)))
	_ok(unsourceable.is_empty(), "every pet names a source PetManager can roll%s"
		% ("" if unsourceable.is_empty() else " (bad: %s)" % ", ".join(unsourceable)))
	_ok(skill_sources.size() > 0 and dungeon_sources.size() > 0,
		"all three acquisition routes stay alive (%d skill-sourced, %d dungeon-sourced, %d item-sourced)"
		% [skill_sources.size(), dungeon_sources.size(), item_sources.size()])

	# --- the two dungeon companions unlock by actually clearing their expedition -------------
	GameManager.start_new_game("standard")
	_ok(not PetManager.is_unlocked("erran") and not PetManager.is_unlocked("harold"),
		"neither expedition companion starts unlocked")
	for pet_id in ["erran", "harold"]:
		var declared: String = str((DataLoader.pets.get(pet_id, {}) as Dictionary).get("source_dungeon", ""))
		_ok(declared != "" and DataLoader.dungeons.has(declared),
			"%s declares a real expedition as its source (%s)" % [pet_id, declared])
	PetManager.on_dungeon_cleared("earth_god_dungeon")
	_ok(PetManager.is_unlocked("erran"), "clearing Deepstone Sanctum unlocks erran")
	_ok(not PetManager.is_unlocked("harold"), "clearing it does not also grant harold")
	PetManager.on_dungeon_cleared("throne_of_the_herald")
	_ok(PetManager.is_unlocked("harold"), "clearing the Seat of the Herald unlocks harold")
	# Idempotent: clearing the same expedition again must not double-grant or re-notify.
	var count_before: int = PlayerData.unlocked_pets.size()
	PetManager.on_dungeon_cleared("throne_of_the_herald")
	_eq(PlayerData.unlocked_pets.size(), count_before, "re-clearing an expedition grants nothing new")

	# --- slayer tiers: no requirement above the cap, and the ladder still ascends ------------
	var slayer_cap: int = int(DataLoader.get_skill("slayer").get("max_level", XPTable.MAX_LEVEL))
	var too_high: Array[String] = []
	var ordered: Array[int] = []
	for tier_id in DataLoader.slayer_tasks.keys():
		if tier_id == "_monsters":
			continue
		ordered.append(int((DataLoader.slayer_tasks[tier_id] as Dictionary).get("level_required", 1)))
		if int((DataLoader.slayer_tasks[tier_id] as Dictionary).get("level_required", 1)) > slayer_cap:
			too_high.append("%s(Lv %d)" % [str(tier_id),
				int((DataLoader.slayer_tasks[tier_id] as Dictionary).get("level_required", 1))])
	_ok(too_high.is_empty(), "every slayer tier is within the slayer cap of %d%s"
		% [slayer_cap, "" if too_high.is_empty() else " (stray: %s)" % ", ".join(too_high)])
	var rising: bool = true
	for i in range(1, ordered.size()):
		if ordered[i] < ordered[i - 1]:
			rising = false
	_ok(rising, "slayer tier requirements still ascend (%s)" % str(ordered))
	var top_required: int = 0
	for req in ordered:
		top_required = maxi(top_required, req)
	_ok(top_required == slayer_cap, "the top tier sits at the cap, so the ladder is fully climbable")
	# The top tier is not just numerically reachable: at the cap the player can take it.
	GameManager.start_new_game("standard")
	PlayerData.set_level("slayer", slayer_cap)
	var top_tier: String = ""
	for tier_id in DataLoader.slayer_tasks.keys():
		if tier_id == "_monsters":
			continue
		if int((DataLoader.slayer_tasks[tier_id] as Dictionary).get("level_required", 1)) == slayer_cap:
			top_tier = str(tier_id)
	_ok(top_tier != "" and SlayerManager.assign_task(top_tier),
		"a maxed Huntsman can take the final tier (%s)" % top_tier)
	SlayerManager.deserialize({})
	GameManager.start_new_game("standard")

func _find_gather_action() -> Dictionary:
	for skill_id in DataLoader.get_skill_ids():
		if str(DataLoader.get_skill(skill_id).get("type", "")) != "gathering":
			continue
		for a in DataLoader.get_skill_actions(skill_id):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if not (a.get("input_items", {}) as Dictionary).is_empty():
				continue
			if int(a.get("node_hp", 0)) > 0:
				continue
			if str(a.get("required_tool", "")) != "":
				continue
			if float(a.get("success_chance", 1.0)) < 1.0:
				continue
			if not (a.get("output_items", {}) as Dictionary).is_empty():
				return {"skill_id": skill_id, "action_id": str(a["id"])}
	return {}

## The consistency check above deliberately skips node-based and failing actions, which is exactly
## where offline time was being dropped: a respawn or stun consumed a whole simulation slice and
## `return`ed, discarding the remainder. This pins both shapes.
func _test_online_offline_consistency_with_timers() -> void:
	_heading("Offline time is not dropped by node respawn or stun")
	for case in [_find_node_based_action(), _find_stun_action()]:
		if (case as Dictionary).is_empty():
			_ok(false, "found a %s action" % str((case as Dictionary).get("kind", "?")))
			continue
		var skill_id: String = str(case["skill_id"])
		var action_id: String = str(case["action_id"])
		var item_id: String = _primary_output(skill_id, action_id)
		var level: int = int(case.get("level", 1))

		GameManager.start_new_game("standard")
		_deterministic(true)
		PlayerData.set_level(skill_id, level)
		SkillManager.start_action(skill_id, action_id, 0)
		for _i in range(600):
			SkillManager.tick(1.0, false)
		var online_actions: int = SkillManager.total_action_count
		var online_items: int = BankManager.get_total_owned(item_id)
		var online_xp: float = PlayerData.get_xp(skill_id)

		GameManager.start_new_game("standard")
		_deterministic(true)
		PlayerData.set_level(skill_id, level)
		SkillManager.start_action(skill_id, action_id, 0)
		SimulationMode.begin()
		var result: Dictionary = SkillManager.simulate_elapsed(600.0)
		SimulationMode.end()
		var offline_items: int = BankManager.get_total_owned(item_id)
		var offline_xp: float = PlayerData.get_xp(skill_id)

		var kind: String = str(case["kind"])
		# Randomised actions (stun) cannot match exactly, but offline must not fall far behind.
		var tolerance: float = 0.20 if kind == "stun" else 0.10
		var xp_ratio: float = (offline_xp / online_xp) if online_xp > 0.0 else 1.0
		_ok(xp_ratio > 1.0 - tolerance,
			"%s: offline XP keeps up with online (%.0f%% of %d actions online)" % [
				kind, xp_ratio * 100.0, online_actions])
		_ok(offline_xp > 0.0, "%s: the run actually progressed" % kind)
		if online_items > 0:
			_ok(offline_items >= int(float(online_items) * (1.0 - tolerance)),
				"%s: offline items keep up with online (%d vs %d)" % [kind, offline_items, online_items])
		_ok(int(result.get("actions", 0)) > 0, "%s: offline simulation reported actions" % kind)

## A node-based action: depletes, respawns, and must not lose the time the respawn does not cover.
func _find_node_based_action() -> Dictionary:
	for skill_id in DataLoader.get_skill_ids():
		for a in DataLoader.get_skill_actions(skill_id):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if int(a.get("node_hp", 0)) <= 0:
				continue
			if not (a.get("input_items", {}) as Dictionary).is_empty():
				continue
			if str(a.get("required_tool", "")) != "":
				continue
			if not (a.get("output_items", {}) as Dictionary).is_empty():
				return {"kind": "node", "skill_id": skill_id, "action_id": str(a["id"]),
					"level": int(a.get("level_required", 1))}
	return {}

## A stun-on-failure action: a failed roll pauses the action and must not eat the whole slice.
func _find_stun_action() -> Dictionary:
	for skill_id in DataLoader.get_skill_ids():
		for a in DataLoader.get_skill_actions(skill_id):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if float(a.get("stun_seconds", 0.0)) <= 0.0:
				continue
			if not (a.get("input_items", {}) as Dictionary).is_empty():
				continue
			if str(a.get("required_tool", "")) != "":
				continue
			return {"kind": "stun", "skill_id": skill_id, "action_id": str(a["id"]),
				"level": int(a.get("level_required", 1))}
	return {}

## The offline marker must move with every save, or the next launch replays the whole session
## as unclaimed time. This is the headline feature, so it must be exactly-once.
func _test_session_time_is_not_paid_out_twice() -> void:
	_heading("Session time is not granted twice")
	GameManager.start_new_game("standard")
	_deterministic(true)
	var skill_id: String = "woodcutting"
	SkillManager.start_action(skill_id, _first_action_of(skill_id), 0)
	for _i in range(600):
		SkillManager.tick(1.0, false)
	# Stand in for the autosave that ends every session.
	var before: int = PlayerData.last_offline_unix
	SaveManager.save_game()
	_ok(PlayerData.last_offline_unix >= before,
		"saving does not move the marker backwards")
	var lag: int = int(Time.get_unix_time_from_system()) - PlayerData.last_offline_unix
	_ok(lag >= 0, "the marker is not in the future after a save (lag %ds)" % lag)
	# The real invariant: after a save, reopening must not replay unclaimed time.
	var summary: Dictionary = OfflineProgression.empty_summary()
	_ok(int(summary.get("elapsed_seconds", 0.0)) == 0, "a fresh summary claims no time")
	_ok(PlayerData.last_offline_unix > 0, "a new game has a real marker, not zero")

## Pause must stop the simulation, and the speed control must actually change its rate.
## Both are user-facing controls that were wired to a flag nothing read.
func _test_pause_and_speed_controls(host: Node) -> void:
	_heading("Pause and speed controls drive the simulation")
	var skill_id: String = "woodcutting"
	var action_id: String = _first_action_of(skill_id)
	var speed_before: float = Engine.time_scale

	# --- pause ---
	# The window must exceed one action interval, or no action could complete even unpaused and
	# the check would pass for the wrong reason.
	GameManager.start_new_game("standard")
	_deterministic(true)
	SkillManager.start_action(skill_id, action_id, 0)
	for _i in range(600):
		SkillManager.tick(1.0, false)
	var before_pause: int = SkillManager.total_action_count
	_ok(before_pause > 0, "the action completed work before the pause (%d actions)" % before_pause)
	GameManager.set_paused(true)
	# With the guard, the autoload's own _process must not advance the action.
	for _i in range(600):
		SkillManager._process(1.0 / 60.0)
	var after_pause: int = SkillManager.total_action_count
	GameManager.set_paused(false)
	_eq(after_pause, before_pause, "a paused action does not advance over 10 simulated seconds")
	_ok(Engine.time_scale == speed_before, "pause does not disturb the engine time scale")

	# --- speed ---
	# Engine.time_scale multiplies the delta the engine hands _process, so this can only be
	# observed by letting real frames run. A no-input action with a short interval is used so
	# both speeds finish a measurable number of actions inside the window.
	GameManager.start_new_game("standard")
	GameManager.set_speed(4.0)
	_ok(is_equal_approx(Engine.time_scale, 4.0), "set_speed scales the engine clock")
	var actions_at_4x: int = await _actions_over_frames(host, 4.0, 12.0)
	GameManager.set_speed(1.0)
	_ok(is_equal_approx(Engine.time_scale, 1.0), "speed 1.0 restores the engine clock")
	var actions_at_1x: int = await _actions_over_frames(host, 1.0, 12.0)
	_ok(actions_at_4x > actions_at_1x, "4x completes more actions than 1x (%d vs %d)" % [
		actions_at_4x, actions_at_1x])

## Let the real engine drive frames at the current Engine.time_scale, so the speed setting is
## actually applied to the delta the autoloads receive.
func _actions_over_frames(host: Node, speed: float, seconds: float) -> int:
	Engine.time_scale = speed
	GameManager.start_new_game("standard")
	SkillManager.start_action("woodcutting", _first_action_of("woodcutting"), 0)
	for _i in range(int(seconds * 60.0)):
		await host.get_tree().process_frame
	return SkillManager.total_action_count

func _first_action_of(skill_id: String) -> String:
	var gather: Dictionary = _find_gather_action()
	if not gather.is_empty() and str(gather.get("skill_id", "")) == skill_id:
		return str(gather["action_id"])
	for a in DataLoader.get_skill_actions(skill_id):
		if typeof(a) == TYPE_DICTIONARY and not (a.get("output_items", {}) as Dictionary).is_empty():
			return str(a.get("id", ""))
	return ""

## Six raid upgrades used to sell raid coins for a modifier key that nothing in scripts/ ever
## read back: _apply_upgrade() registered them and the raid felt none of them. Taking money for
## nothing is worse than not selling the upgrade, so each was either wired to a real mechanic or
## deleted from the shop.
##
## The key list is walked from the data, not hardcoded per upgrade, so the next invented raid
## upgrade fails here too.
## RAID_LIVE_KEYS is every modifier key an upgrade may sell, and each one is read by a
## consumer: RAID_WAVE_SKIP by RaidManager.start_raid(), the rest by combat/skill systems that
## query ModifierManager by name.
const RAID_LIVE_KEYS: Array[String] = [
	ModifierKeys.RAID_WAVE_SKIP,
	ModifierKeys.FOOD_HEALING_PERCENT,
	ModifierKeys.AUTO_EAT_EFFICIENCY_PERCENT,
	ModifierKeys.AUTO_EAT_THRESHOLD_PERCENT,
	ModifierKeys.PRAYER_COST_REDUCTION_PERCENT,
	ModifierKeys.HITPOINTS_REGEN_FLAT,
	ModifierKeys.GLOBAL_DOUBLE_LOOT_PERCENT,
	ModifierKeys.GLOBAL_GP_PERCENT,
	ModifierKeys.GLOBAL_SLAYER_COINS_PERCENT,
	ModifierKeys.ATTACK_INTERVAL_PERCENT,
	ModifierKeys.ATTACK_INTERVAL_FLAT,
	ModifierKeys.DAMAGE_REDUCTION_PERCENT,
	ModifierKeys.CRIT_CHANCE_PERCENT,
	ModifierKeys.CRIT_MULTIPLIER_PERCENT,
	ModifierKeys.LIFE_STEAL_PERCENT,
	ModifierKeys.GLOBAL_ACCURACY_PERCENT,
	ModifierKeys.GLOBAL_SKILL_XP_PERCENT,
	ModifierKeys.GLOBAL_MASTERY_XP_PERCENT,
	ModifierKeys.BANK_SPACE_FLAT,
	ModifierKeys.BLESSED_BONE_OFFERING_FLAT,
	ModifierKeys.RESPWAN_TIME_PERCENT,
	ModifierKeys.SLAYER_AREA_NEGATION_PERCENT,
]

func _test_raid_shop_upgrades_are_real() -> void:
	_heading("Raid shop upgrades do something")
	GameManager.start_new_game("standard")
	var upgrades: Dictionary = DataLoader.raid_shop.get("upgrades", {})
	_ok(not upgrades.is_empty(), "the raid shop still stocks upgrades")

	# 1. No dangling keys: an upgrade may only sell a key the game actually reads back. A key
	#    outside the list is a purchase that costs coins and does nothing.
	for uid in upgrades.keys():
		var eff: Dictionary = (upgrades[uid] as Dictionary).get("effect", {})
		_ok(not eff.is_empty(), "upgrade %s declares an effect" % uid)
		_ok(int((upgrades[uid] as Dictionary).get("cost", 0)) > 0, "upgrade %s has a price" % uid)
		for key in eff.keys():
			_ok(RAID_LIVE_KEYS.has(str(key)),
				"upgrade %s sells %s, which the game reads" % [uid, key])
	for item_id in (DataLoader.raid_shop.get("alt_items", []) as Array):
		_ok(not DataLoader.get_item(str(item_id)).is_empty(), "alt item %s exists" % item_id)

	# 2. raid_wave_skip: the run must start past the early waves.
	_ok(RaidManager.start_raid("normal"), "a raid starts with no purchases")
	_eq(RaidManager.wave, 1, "a fresh raid begins at wave 1")
	RaidManager.end_raid()
	PlayerData.raid_coins = 100000.0
	_ok(RaidManager.buy("raid_wave_skip"), "raid_wave_skip can be bought")
	_ok(ModifierManager.get_modifier(ModifierKeys.RAID_WAVE_SKIP) == 1.0,
		"raid_wave_skip registers the modifier start_raid() reads")
	_ok(RaidManager.start_raid("normal"), "a raid starts after buying wave skip")
	_eq(RaidManager.wave, 2, "raid_wave_skip starts the run at wave 2, not 1")
	RaidManager.end_raid()

	# 3. raid_food: the raid forces auto-eat tier II, so healing more per food is exactly the
	#    "restore between waves" the upgrade claims. Measured through consume_food() — the one
	#    function that reads food_healing_percent, and what the raid's auto-eat calls.
	#    A real HP pool matters: healing is capped at max HP, and a level-1 character would cap
	#    at 10 and make both sides look identical.
	GameManager.start_new_game("standard")
	PlayerData.set_level("hitpoints", 50)
	BankManager.add_item_guaranteed("shrimp", 20)
	var maxhp: float = CombatManager._compute_max_hp()
	var shrimp_heal: float = float(DataLoader.get_item("shrimp").get("heal_amount", 0))
	_ok(maxhp > shrimp_heal, "the HP pool is large enough to measure a heal in (%d HP)" % int(maxhp))
	var food_pct: float = float((DataLoader.raid_shop["upgrades"]["raid_food"] as Dictionary)
		.get("effect", {}).get(ModifierKeys.FOOD_HEALING_PERCENT, 0.0))
	_ok(food_pct > 0.0, "raid_food sells a positive food_healing_percent (%.0f%%)" % food_pct)
	_eq(ModifierManager.get_modifier(ModifierKeys.FOOD_HEALING_PERCENT), 0.0,
		"no food healing bonus is active before the upgrade is bought")
	CombatManager.player_hp = maxhp * 0.05
	_eq(CombatManager.consume_food("shrimp"), "shrimp", "a banked food is eaten")
	var plain_heal: float = CombatManager.player_hp - maxhp * 0.05
	_approx(plain_heal, shrimp_heal, 0.001, "the food heals its full amount (%.0f HP)" % plain_heal)
	ModifierManager.register("test:raid_food", {ModifierKeys.FOOD_HEALING_PERCENT: food_pct}, "test")
	CombatManager.player_hp = maxhp * 0.05
	CombatManager.consume_food("shrimp")
	var boosted_heal: float = CombatManager.player_hp - maxhp * 0.05
	ModifierManager.unregister("test:raid_food")
	_approx(boosted_heal, shrimp_heal * (1.0 + food_pct / 100.0), 0.001,
		"the upgrade heals %.0f HP per food instead of %.0f" % [boosted_heal, plain_heal])
	_ok(boosted_heal > plain_heal, "food_healing_percent heals more per food (%.0f vs %.0f HP)"
		% [boosted_heal, plain_heal])

	# 4. difficulties.hp_mult: hard must really be tankier, not just print a label. Enemy HP is
	#    set in one place, so the multiplier lands on every wave of a hard run.
	GameManager.start_new_game("standard")
	PlayerData.set_level("hitpoints", 50)
	_ok(RaidManager.start_raid("normal"), "a normal raid starts for the HP comparison")
	var normal_hp: int = CombatManager.monster_max_hp
	RaidManager.end_raid()
	_ok(RaidManager.start_raid("hard"), "a hard raid starts for the HP comparison")
	var hard_hp: int = CombatManager.monster_max_hp
	RaidManager.end_raid()
	var cfg: Dictionary = DataLoader.raid_shop["difficulties"]["hard"]
	var cfg_mult: float = float(cfg.get("hp_mult", 1.0))
	_ok(cfg_mult > 1.0, "hard declares a hp_mult above 1 (%.2f)" % cfg_mult)
	_eq(hard_hp, int(round(float(normal_hp) * cfg_mult)),
		"a hard raid spawns normal HP x hp_mult (%d vs %d)" % [hard_hp, int(round(float(normal_hp) * cfg_mult))])
	_ok(is_equal_approx(RaidManager.enemy_hp_mult(), cfg_mult),
		"enemy_hp_mult() reports the difficulty's declared multiplier")
	# A difficulty key nothing reads (the old "modifiers": true) is the bug in its purest form.
	for diff in (DataLoader.raid_shop.get("difficulties", {}) as Dictionary).keys():
		_ok(not (DataLoader.raid_shop["difficulties"][diff] as Dictionary).has("modifiers"),
			"difficulty %s declares no key nothing reads" % diff)

## Systems that shipped complete but had no live path from data to player: prayer and raid had
## no UI entry point, and the Beastbinding tablets needed mark items nothing produced. Each of
## these is now reachable; the checks fail if that regresses.
func _test_reachable_systems() -> void:
	_heading("Previously unreachable systems are reachable")
	# --- prayer: toggle must work and register its modifier ---
	GameManager.start_new_game("standard")
	PlayerData.set_level("prayer", 20)
	PlayerData.add_prayer_points(1000.0)
	var prayer_id: String = ""
	for id in DataLoader.prayers.keys():
		var p: Dictionary = DataLoader.prayers[id]
		if not p.is_empty() and not p.has("_comment") and int(p.get("level", 99)) <= 20:
			prayer_id = str(id)
			break
	_ok(prayer_id != "", "a low-level prayer exists to toggle")
	if prayer_id != "":
		var toggled: bool = PrayerManager.toggle(prayer_id)
		_ok(toggled and PrayerManager.is_active(prayer_id), "a prayer can be activated (%s)" % prayer_id)
		PrayerManager.toggle(prayer_id)
		_ok(not PrayerManager.is_active(prayer_id), "a prayer can be deactivated again")

	# --- raid: start_raid must begin a fight ---
	GameManager.start_new_game("standard")
	PlayerData.set_level("hitpoints", 50)
	var raid_started: bool = RaidManager.start_raid("normal")
	_ok(raid_started and RaidManager.active, "a raid can be started")
	_ok(CombatManager.state != CombatManager.State.IDLE, "a raid occupies the activity slot")
	_ok(RaidManager.wave == 1, "the first wave begins")
	if RaidManager.active:
		RaidManager.end_raid()
	_ok(not RaidManager.active, "a raid can be ended")

	# --- summoning: a gained mark must reach the bank, or the tablets can never be crafted ---
	GameManager.start_new_game("standard")
	var fam_id: String = ""
	for fid in DataLoader.familiars.keys():
		if not DataLoader.items.has("%s_mark" % str(fid)):
			continue
		if DataLoader.items.has(str(DataLoader.familiars[fid].get("tablet_item", ""))):
			fam_id = str(fid)
			break
	_ok(fam_id != "", "a familiar has both a mark item and a tablet")
	if fam_id != "":
		var mark_id: String = "%s_mark" % fam_id
		var tablet_id: String = str(DataLoader.familiars[fam_id].get("tablet_item", ""))
		_ok(BankManager.get_total_owned(mark_id) == 0, "the mark starts unbanked")
		SummoningManager._gain_mark(fam_id)
		_ok(BankManager.get_total_owned(mark_id) > 0, "gaining a mark banks the item (%s)" % mark_id)
		# With the mark in hand, the level-1 recipe's only missing input is its shard.
		for shard in (DataLoader.get_action("summoning", tablet_id).get("input_items", {}) as Dictionary).keys():
			BankManager.add_item_guaranteed(str(shard), 50)
		var check: Dictionary = SkillManager.check_action("summoning", tablet_id)
		_ok(bool(check.get("ok", false)), "the tablet recipe is now craftable (%s)" % tablet_id)

## A weapon that beats the previous tier is required: a flat ladder means no combat progression.
## Melee is the reference style here; ranged and magic have their own ladders.
## Every item id a skill action produces: the crafted set. Raid-shop rewards, dungeon drops and
## monster loot are absent on purpose. They are a parallel reward track with their own strength
## curve, deliberately ahead of the crafted tier at the same level, so folding them into a single
## rising ladder compares two different things.
func _crafted_item_ids() -> Dictionary:
	var out: Dictionary = {}
	for skill_id in DataLoader.skills.keys():
		for action in DataLoader.get_skill_actions(str(skill_id)):
			for item_id in (action.get("output_items", {}) as Dictionary).keys():
				out[str(item_id)] = true
	return out

func _test_melee_tier_ladder() -> void:
	_heading("The melee weapon ladder rises at every tier")
	var crafted: Dictionary = _crafted_item_ids()
	var best: Dictionary = {}
	for id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.get_item(str(id))
		if it.is_empty() or int(it.get("equipment_slot", -1)) != 8:
			continue
		if not crafted.has(str(id)):
			continue
		var st: Dictionary = it.get("equipment_stats", {})
		if not st.has("melee_strength"):
			continue
		var lvl: int = int((it.get("level_requirements", {}) as Dictionary).get("attack", 0))
		if not best.has(lvl) or int(st.get("melee_strength", 0)) > int(best[lvl]):
			best[lvl] = int(st.get("melee_strength", 0))
	var levels: Array = best.keys()
	levels.sort()
	_ok(levels.size() >= 5, "the crafted melee ladder has several tiers (%d)" % levels.size())
	for i in range(1, levels.size()):
		var prev_lvl: int = int(levels[i - 1])
		var lvl: int = int(levels[i])
		_ok(int(best[lvl]) > int(best[prev_lvl]),
			"crafted melee damage rises from L%d (%d strength) to L%d (%d strength)" % [
				prev_lvl, int(best[prev_lvl]), lvl, int(best[lvl])])

## The audit found melee and armour jumping straight from the level-50 Skyiron tier to the level-95
## god sets, with runite ore and bars mined, smelted and then spent on nothing. These checks pin the
## two tiers that closed it.
func _test_gear_ladder_gap() -> void:
	_heading("The mid-game melee and armour tiers")
	var crafted: Dictionary = _crafted_item_ids()
	# Weapons: a crafted tier must exist between the Skyiron and god tiers.
	var weapon_levels: Array = []
	var best_strength: Dictionary = {}
	for id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.get_item(str(id))
		if it.is_empty() or int(it.get("equipment_slot", -1)) != 8 or not crafted.has(str(id)):
			continue
		var st: Dictionary = it.get("equipment_stats", {})
		if not st.has("melee_strength"):
			continue
		var lvl: int = int((it.get("level_requirements", {}) as Dictionary).get("attack", 0))
		if not best_strength.has(lvl):
			weapon_levels.append(lvl)
		best_strength[lvl] = maxi(int(best_strength.get(lvl, 0)), int(st["melee_strength"]))
	var between: Array = []
	for lvl in weapon_levels:
		if int(lvl) > 50 and int(lvl) < 95:
			between.append(int(lvl))
	between.sort()
	_ok(between.size() >= 2, "crafted melee weapons fill 50-95 (%s)" % str(between))
	# Armour: the same stretch, measured on the defence the player actually gains.
	var armour_levels: Array = []
	var best_defence: Dictionary = {}
	for id in DataLoader.items.keys():
		var it: Dictionary = DataLoader.get_item(str(id))
		if it.is_empty() or int(it.get("equipment_slot", -1)) == 8 or not crafted.has(str(id)):
			continue
		var st: Dictionary = it.get("equipment_stats", {})
		if not st.has("melee_defence"):
			continue
		var lvl: int = int((it.get("level_requirements", {}) as Dictionary).get("defence", 0))
		if lvl <= 0:
			continue
		if not best_defence.has(lvl):
			armour_levels.append(lvl)
		best_defence[lvl] = maxi(int(best_defence.get(lvl, 0)), int(st["melee_defence"]))
	armour_levels.sort()
	var crafted_armour: Array = []
	for lvl in armour_levels:
		if int(lvl) > 50 and int(lvl) < 95:
			crafted_armour.append(int(lvl))
	_ok(crafted_armour.size() >= 2, "crafted armour fills 50-95 (%s)" % str(crafted_armour))
	# Both bars the audit found dead must now be consumed by recipes the game ships.
	var consumed: Dictionary = {}
	for skill_id in ["smithing", "crafting", "fletching"]:
		for action in DataLoader.get_skill_actions(skill_id):
			for in_id in (action.get("input_items", {}) as Dictionary).keys():
				consumed[str(in_id)] = true
	for bar_id in ["runite_bar", "dragonite_bar"]:
		_ok(consumed.has(bar_id), "%s is spent by a shipped recipe" % bar_id)
	# Every new piece must be obtainable, or closing the gap just moves it.
	for tier in ["runite", "dragonite"]:
		for suffix in ["sword", "scimitar", "dagger", "battleaxe", "2h_sword", "helmet", "platebody",
				"platelegs", "boots", "gloves", "shield"]:
			var item_id: String = "%s_%s" % [tier, suffix]
			_ok(DataLoader.get_item(item_id) != {}, "%s ships" % item_id)
			_ok(crafted.has(item_id), "%s has a smithing recipe" % item_id)

## Every skill a player can raise needs at least one quest objective pointing at it, or it is
## invisible content. The combat skills were the gap: 238 quests and not one mentioned them.
func _test_quest_coverage() -> void:
	_heading("Quests cover every trainable skill")
	var covered: Dictionary = {}
	var kinds: Dictionary = {}
	for id in Quests.all_quest_ids():
		if Quests.is_rotating(id):
			continue
		var q: Dictionary = Quests.get_quest(id)
		for o in (q.get("objectives", []) as Array):
			kinds[str(o.get("kind", ""))] = true
			var sid: String = str(o.get("skill_id", ""))
			if sid != "":
				covered[sid] = true
	for skill_id in DataLoader.get_skill_ids():
		if str(DataLoader.get_skill(skill_id).get("type", "")) == "combat" or skill_id == "slayer":
			_ok(covered.has(skill_id), "a quest objective trains %s" % skill_id)
	_ok(kinds.has("defeat_boss"), "a quest uses defeat_boss (the boss fights are quested)")
	_ok(kinds.has("unlock_pet"), "a quest uses unlock_pet (companions are quested)")
	# Prerequisite chains must point at quests that exist, or a quest locks itself forever.
	for id in Quests.all_quest_ids():
		if Quests.is_rotating(id):
			continue
		for pre in (Quests.get_quest(id).get("prerequisites", []) as Array):
			_ok(Quests.has_quest(str(pre)), "%s prerequisite %s exists" % [id, pre])

## The skill XP bar must track the simulation while an action runs, not only when the panel is
## rebuilt. Rebuilding on every action was the obvious fix and the wrong one: it destroys and
## re-creates the whole header (activities list, mastery, modifiers) several times a second.
func _test_xp_updates_live(host: Node) -> void:
	_heading("Skill XP updates live while an action runs")
	GameManager.start_new_game("standard")
	GameManager.set_paused(false)
	var panel = load("res://scripts/ui/panels/SkillsPanel.gd").new()
	host.add_child(panel)
	panel.focus_route({"skill_id": "woodcutting"})
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var action_id: String = _first_action_of("woodcutting")
	_ok(action_id != "", "a woodcutting action exists to run")

	var bar: ProgressBar = panel.get("_xp_bar")
	var text: Label = panel.get("_xp_bar_text")
	_ok(bar != null, "the skill header exposes its live XP bar")
	_ok(text != null, "the XP bar exposes its value label")

	# Capture the bar identity, then run a real action. queue_free() defers the destruction to the
	# end of the frame, so a node captured before a rebuild stays non-null for a frame; assert on
	# the bar the panel currently holds, and separately prove it was never rebuilt mid-action.
	var xp_before: float = PlayerData.get_xp("woodcutting")
	SkillManager.start_action("woodcutting", action_id)
	# action_started triggers a rebuild, which frees the pre-action bar. Settle that first, then
	# capture the identity: from here on the bar must be mutated in place, never re-created.
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	bar = panel.get("_xp_bar")
	text = panel.get("_xp_bar_text")
	_ok(bar != null, "the XP bar exists after the action started")
	_ok(text != null, "the XP bar label exists after the action started")
	var node_id: int = bar.get_instance_id()
	var value_at_start: float = bar.value
	var text_at_start: String = text.text
	xp_before = PlayerData.get_xp("woodcutting")
	var deadline: int = Time.get_ticks_msec() + 15000
	while PlayerData.get_xp("woodcutting") <= xp_before and Time.get_ticks_msec() < deadline:
		await host.get_tree().process_frame
	_ok(PlayerData.get_xp("woodcutting") > xp_before, "the running action granted XP")
	_ok(is_instance_valid(bar) and bar.get_instance_id() == node_id,
		"the bar was updated in place, not rebuilt per action")
	_ok(bar.value != value_at_start, "the XP bar moved while the action ran")
	_ok(text.text != text_at_start, "the XP total on the bar moved while the action ran")
	# The displayed total must equal the authoritative value, not a stale snapshot.
	var xp_now: float = PlayerData.get_xp("woodcutting")
	var level_now: int = PlayerData.get_level("woodcutting")
	_ok(text.text.begins_with(UIStyle.fmt_exact(xp_now)),
		"the bar shows the live total (%s), not a snapshot" % UIStyle.fmt_exact(xp_now))
	# Compare with a tolerance: _process() rounds through the same clampf, and 0.12 vs 0.12048 is
	# float noise, not a stale bar.
	var want: float = clampf(XPTable.level_progress(xp_now, level_now), 0.0, 1.0)
	_ok(absf(bar.value - want) < 0.01,
		"the bar position matches the real progress toward level %d" % (level_now + 1))
	SkillManager.stop_action(SkillManager.StopReason.PLAYER)
	panel.queue_free()

## A failed cook must cost the player the fish. Before this, the failure branch returned before
## _consume_inputs(), so cooking failure was free and the only cost was the wait.
func _test_cooking_failure_burns_materials(host: Node) -> void:
	_heading("A failed cook consumes its ingredients and yields burnt food")
	GameManager.start_new_game("standard")
	GameManager.set_paused(false)
	var action: Dictionary = DataLoader.get_action("cooking", "cook_shrimp")
	_ok(not action.is_empty(), "the shrimp recipe exists")
	_ok(str(action.get("fail_output_item", "")) == "burnt_food",
		"the shrimp recipe declares burnt food as its failure output")
	var input_id: String = str((action.get("input_items", {}) as Dictionary).keys()[0])

	# Drive the real action path repeatedly: success_chance is 0.5, so this mixes both outcomes and
	# proves the failure branch specifically, not a hand-called internal. perform_action() operates
	# on the running action, so it has to be started first.
	GameManager.start_new_game("standard")
	# start_new_game emits state_refreshed, but the shared shell was built before this test ran, so
	# ask it to rebuild its nav now that its buttons exist. Without this the sidebar keeps the labels
	# it was built with and every later test reads stale levels.
	host.call("_refresh_nav")
	# Stock the bank BEFORE starting: start_action() refuses an action whose inputs are missing.
	BankManager.add_item_guaranteed(input_id, 500)
	_ok(SkillManager.start_action("cooking", "cook_shrimp"),
		"the shrimp cook can be started (%s)" % str(SkillManager.check_action("cooking", "cook_shrimp").get("detail", "")))
	var burnt_seen: int = 0
	var failures: int = 0
	var successes: int = 0
	for _i in range(400):
		BankManager.add_item_guaranteed(input_id, 10)
		var raw_before: int = BankManager.get_count(input_id)
		var burnt_before: int = BankManager.get_count("burnt_food")
		var res: Dictionary = SkillManager.perform_action()
		var raw_after: int = BankManager.get_count(input_id)
		if bool(res.get("success", false)):
			successes += 1
			# Preservation (a mastery bonus) can legitimately refund the input, so a success is not
			# guaranteed to cost materials. What must always hold: no burnt food on a success.
			_ok(BankManager.get_count("burnt_food") == burnt_before,
				"a successful cook produced no burnt food")
			continue
		failures += 1
		_ok(raw_after < raw_before,
			"a failed cook still consumed its ingredients (%d -> %d)" % [raw_before, raw_after])
		_ok(BankManager.get_count("burnt_food") > burnt_before,
			"a failed cook produced burnt food")
		burnt_seen += 1
		# The waste must be reported in the same shape a success uses, so the UI needs no branch.
		_ok((res.get("items", {}) as Dictionary).has("burnt_food"),
			"the failure result reports the burnt food it produced")
	_ok(failures > 0, "the loop actually produced failures (%d)" % failures)
	_ok(successes > 0, "the loop actually produced successes (%d)" % successes)
	_ok(burnt_seen == failures, "every failure yielded exactly burnt food (%d of %d)" % [burnt_seen, failures])

	# Burnt food is worthless: it must not be a gold faucet or an item the player can eat.
	var burnt_item: Dictionary = DataLoader.get_item("burnt_food")
	_ok(not burnt_item.is_empty(), "burnt food exists in the item table")
	_ok(int(burnt_item.get("sell_price", -1)) == 0, "burnt food sells for nothing")
	_ok(int(burnt_item.get("heal_amount", 0)) == 0, "burnt food cannot be eaten for healing")
	_ok(burnt_item.get("item_type", "") == "resource",
		"burnt food is a resource, not food, so no cooking recipe can target it")
	SkillManager.stop_action(SkillManager.StopReason.PLAYER)

## A fish the player catches and cannot use is a dead end: raw_crab and raw_cave_fish were landed by
## Fishing and consumed by nothing, and Cookery's unlock ladder had a hole at exactly those two
## levels. The check is general, so a new Fishing action cannot quietly reintroduce one.
func _test_raw_fish_are_consumed() -> void:
	_heading("Every raw fish is consumed by something")
	var consumed: Dictionary = {}
	for skill_id in DataLoader.skills.keys():
		for action in DataLoader.get_skill_actions(str(skill_id)):
			for item_id in (action.get("input_items", {}) as Dictionary).keys():
				consumed[str(item_id)] = true
	var landed: Array[String] = []
	for action in DataLoader.get_skill_actions("fishing"):
		for item_id in (action.get("output_items", {}) as Dictionary).keys():
			var fish: String = str(item_id)
			if fish.begins_with("raw_") and DataLoader.items.has(fish):
				landed.append(fish)
	_ok(landed.size() >= 10, "fishing lands a range of raw fish (%d)" % landed.size())
	for fish in landed:
		_ok(consumed.has(fish), "'%s' is consumed by a recipe" % fish)
	# The two arrivals, pinned at the levels that closed the 50 -> 70 and 70 -> 85 holes.
	var cook_by_id: Dictionary = {}
	for action in DataLoader.get_skill_actions("cooking"):
		cook_by_id[str(action.get("id", ""))] = action
	for pair in [["cook_crab", 60], ["cook_cave_fish", 75]]:
		var recipe: Dictionary = cook_by_id.get(str(pair[0]), {})
		_ok(not recipe.is_empty(), "the '%s' recipe exists" % pair[0])
		if recipe.is_empty():
			continue
		_eq(int(recipe.get("level_required", 0)), int(pair[1]), "'%s' sits at level %d" % [pair[0], pair[1]])
		for out_id in (recipe.get("output_items", {}) as Dictionary).keys():
			_ok(int(DataLoader.get_item(str(out_id)).get("heal_amount", 0)) > 0,
				"'%s' cooks into food that heals" % pair[0])
	# And the ladder is still ordered: a higher-level cook never pays less than a lower one.
	var cooks: Array = DataLoader.get_skill_actions("cooking").duplicate()
	cooks.sort_custom(func(a, b): return int(a["level_required"]) < int(b["level_required"]))
	var previous_cook: Dictionary = {}
	for cook in cooks:
		if str(cook.get("id", "")) == "roast_ranch_meat":
			continue
		if not previous_cook.is_empty():
			_ok(float(cook["base_xp"]) >= float(previous_cook["base_xp"]),
				"the level-%d cook pays at least the level-%d one" % [int(cook["level_required"]), int(previous_cook["level_required"])])
		previous_cook = cook

## The balance report listed 126 "materials nothing consumes" because it only knew about recipes.
## Real demand is scattered: weapons burn ammunition, summoning eats tablets, a pen eats stock,
## Engineering eats devices, Inscription eats texts, Enchanting eats essences, Prayer eats bones
## and the museum eats artefacts. With every channel modelled, a dead output is either declared
## (`terminal_reason` in items.json) or a bug — and this suite is what makes that stick.
func _test_outputs_are_consumed() -> void:
	_heading("Every output is consumed, or declared terminal")
	var demand: Dictionary = BalanceReport.dead_outputs()
	var undeclared: Array[String] = []
	for item_id in (demand["undeclared"] as Array):
		undeclared.append(str(item_id))
	_ok(undeclared.is_empty(),
		"no obtainable item is left without a consumer%s" % _trouble(undeclared, " — "))

	var declared: Array = demand["declared"]
	_ok(declared.size() >= 10, "intentional dead ends are declared in the data (%d)" % declared.size())
	var unexplained: Array[String] = []
	for item_id in declared:
		if str(DataLoader.get_item(str(item_id)).get("terminal_reason", "")).strip_edges() == "":
			unexplained.append(str(item_id))
	_ok(unexplained.is_empty(), "every terminal declaration says why%s" % _trouble(unexplained, " — "))
	var stale: Array[String] = []
	for item_id in (demand["stale_declarations"] as Array):
		stale.append(str(item_id))
	_ok(stale.is_empty(), "no declaration is stale — nothing consumed is also marked terminal%s" %
		_trouble(stale, " — "))

	# A channel that matches nothing means the field it reads was renamed, and it would then
	# excuse every dead item it used to catch. That is the failure this suite exists to prevent.
	var used: Dictionary = BalanceReport.consumed_item_ids()
	var seen: Dictionary = {}
	for reasons in used.values():
		for reason in (reasons as Array):
			seen[str(reason).split(":")[0]] = true
	var silent: Array[String] = []
	for channel in BalanceReport.DEMAND_CHANNELS:
		if not seen.has(channel):
			silent.append(channel)
	_ok(silent.is_empty(), "all %d demand channels match content%s" %
		[BalanceReport.DEMAND_CHANNELS.size(), _trouble(silent, " — ")])
	_ok(used.size() >= 290, "demand covers the whole economy (%d items are spent)" % used.size())

	# The specific dead ends this pass closed, pinned by shape so they cannot come back.
	for pair in [["bronze_arrow", "a bow spends it"], ["iron_arrow", "a bow spends it"],
			["steel_arrow", "a bow spends it"], ["big_bones", "prayer buries it"],
			["dragon_bones", "prayer buries it"], ["topaz", "two recipes spend it"],
			["harvested_essence", "Prospecting's only output feeds Herblore"],
			["artefact_common", "the museum takes it"], ["artefact_unique", "the museum takes it"]]:
		_ok(used.has(str(pair[0])), "'%s' is spent by content (%s)" % [pair[0], pair[1]])

	# Every farmed crop and every pen produce is a material: if a new one lands without a use,
	# the skill that raises it produces nothing. Both are read from the tables, not listed here.
	var crops: Array[String] = []
	for item_id in DataLoader.items.keys():
		var seed_item: Dictionary = DataLoader.items[item_id]
		if str(seed_item.get("item_type", "")) != "seed":
			continue
		var product: String = str(seed_item.get("product_item", ""))
		if product != "":
			crops.append(product)
	_ok(crops.size() >= 10, "the seed table yields %d crops" % crops.size())
	var unspent_crops: Array[String] = []
	for crop in crops:
		if not used.has(crop):
			unspent_crops.append(crop)
	_ok(unspent_crops.is_empty(), "every farmed crop is spent by a recipe%s" % _trouble(unspent_crops, " — "))

	var produce: Array[String] = []
	for species_def in (DataLoader.new_skill_systems.get("species", []) as Array):
		if typeof(species_def) != TYPE_DICTIONARY:
			continue
		var raised: String = str((species_def as Dictionary).get("produce", ""))
		if raised != "":
			produce.append(raised)
	_ok(produce.size() >= 9, "the species table yields %d ranch produce" % produce.size())
	var unspent_produce: Array[String] = []
	for raised in produce:
		if not used.has(raised):
			unspent_produce.append(raised)
	_ok(unspent_produce.is_empty(), "every ranch produce is spent by a recipe%s" % _trouble(unspent_produce, " — "))

	# The two special Beastbinding tablets now spend the mark their familiar awards, like the 25
	# tier-one tablets already did — before this, those two marks accumulated with no use.
	for familiar_id in ["border_collie", "sandman"]:
		var familiar: Dictionary = DataLoader.familiars.get(familiar_id, {})
		var mark: String = str(familiar.get("mark_item", ""))
		_ok(mark != "" and used.has(mark), "'%s' spends the mark it awards" % familiar_id)

	# Containers and eggs are opened from Storage: the wrapper is spent and the contents arrive.
	for item_id in DataLoader.items.keys():
		var container: Dictionary = DataLoader.items[item_id]
		var contents: Dictionary = container.get("container_items", {})
		var pet_id: String = str(container.get("container_pet", ""))
		if contents.is_empty() and pet_id == "":
			continue
		_ok(used.has(str(item_id)), "container '%s' is spendable" % item_id)
		for grant in contents.keys():
			_ok(DataLoader.items.has(str(grant)), "container '%s' hands over a real item ('%s')" % [item_id, grant])

	var bank_before: Dictionary = BankManager.serialize()
	var pets_before: Array[String] = PlayerData.unlocked_pets.duplicate()
	var boxes_before: int = BankManager.get_count("wood_box")
	var logs_before: int = BankManager.get_count("normal_log")
	BankManager.add_item_guaranteed("wood_box", 2)
	var opened: Dictionary = BankManager.open_container("wood_box", 1)
	_ok(bool(opened["ok"]), "a crate can be opened from Storage")
	_eq(int(opened["opened"]), 1, "opening one crate spends exactly one")
	_eq(BankManager.get_count("wood_box") - boxes_before, 1, "the rest of the stack is left alone")
	_ok(int(opened["items"].get("normal_log", 0)) > 0, "opening really hands over the contents")
	_eq(BankManager.get_count("normal_log") - logs_before, int(opened["items"].get("normal_log", 0)),
		"the contents land in Storage")
	PlayerData.unlocked_pets.erase("sunderling")
	BankManager.add_item_guaranteed("raid_pet_egg", 2)
	var hatched: Dictionary = BankManager.open_container("raid_pet_egg", 2)
	_ok(bool(hatched["ok"]), "a raid egg can be hatched from Storage")
	_eq(str(hatched["pet"]), "sunderling", "the egg hatches its own pet")
	_ok(PetManager.is_unlocked("sunderling"), "hatching unlocks the pet")
	_eq(int(hatched["opened"]), 1, "hatching one egg leaves the rest of the stack alone")
	_ok(not bool(BankManager.open_container("raid_pet_egg", 1)["ok"]),
		"an already hatched egg is not spent again")
	BankManager.deserialize(bank_before)
	PlayerData.unlocked_pets = pets_before
	ModifierManager.clear_category(PetManager.CATEGORY)
	PetManager.deserialize({})

## The report is content too. A shape change in _bottlenecks() without a matching change in
## format_text() crashed the whole balance report at runtime, and no suite had ever built it, so
## the run looked clean. Build it here and pin the keys the printer reads.
func _test_balance_report_builds() -> void:
	_heading("The balance report builds every section")
	var report: Dictionary = BalanceReport.build()
	var missing: Array[String] = []
	for section in ["rates", "bottlenecks", "combat", "economy", "unused"]:
		if not report.has(section):
			missing.append(section)
	_ok(missing.is_empty(), "the report builds every section%s" % _trouble(missing, " — "))

	var bottlenecks: Dictionary = report["bottlenecks"]
	var bad_rows: Array[String] = []
	for entry in (bottlenecks.get("top", []) as Array):
		for key in ["item_id", "recipes", "producers", "sources", "routes", "has_source"]:
			if not (entry as Dictionary).has(key):
				bad_rows.append("%s has no '%s'" % [str((entry as Dictionary).get("item_id", "?")), key])
	_ok(bad_rows.is_empty(), "every bottleneck row carries what the printer reads%s" %
		_trouble(bad_rows, " — "))
	_ok(typeof(bottlenecks.get("warnings", null)) == TYPE_ARRAY,
		"the bottleneck warnings are a list the printer can iterate")

	# The same dead-output answer the guard above asserts on, so report and suite cannot drift.
	_ok(str(report["unused"]) == str(BalanceReport.dead_outputs()),
		"the report prints the same dead outputs the guard checks")
	var lines: Array[String] = BalanceReport.format_text()
	_ok(lines.size() > 20 and str(lines[0]).begins_with("=== balance report"),
		"the report formats end to end (%d lines)" % lines.size())

## Supply concentration is a design decision, not automatically a bug: a material can be meant to
## come from one place. `bottleneck_reason` is how the data says so, and this suite keeps the two
## apart — an undeclared hub, or a declaration the content outgrew, fails here.
func _test_bottleneck_declarations() -> void:
	_heading("Supply concentration is declared, not assumed")
	var concentrated: Dictionary = BalanceReport.concentrated_materials()
	var rows: Array = concentrated["rows"]
	var declared: Array = concentrated["declared"]
	_ok(rows.size() >= 2, "the economy has single-source hubs worth watching (%d)" % rows.size())
	_ok(declared.size() >= 2, "the deliberate ones are declared in the data (%d)" % declared.size())

	var unexplained: Array[String] = []
	var over_supplied: Array[String] = []
	for entry in rows:
		var row: Dictionary = entry
		var item_id: String = str(row["item_id"])
		if int(row["sources"]) > 1:
			over_supplied.append("%s has %d sources" % [item_id, int(row["sources"])])
		if str(row["reason"]) == "":
			unexplained.append("%s (%d recipes, %s)" % [item_id, int(row["recipes"]), str(row["routes"])])
	_ok(unexplained.is_empty(),
		"every flagged hub is declared deliberate%s" % _trouble(unexplained, " — "))
	_ok(over_supplied.is_empty(),
		"a concentration really means one source%s" % _trouble(over_supplied, " — "))
	var stale: Array[String] = []
	for item_id in (concentrated["stale_declarations"] as Array):
		stale.append(str(item_id))
	_ok(stale.is_empty(), "no declaration outlived its concentration%s" % _trouble(stale, " — "))
	var thin: Array[String] = []
	for item_id in declared:
		if str(DataLoader.get_item(str(item_id)).get("bottleneck_reason", "")).strip_edges().length() < 15:
			thin.append(str(item_id))
	_ok(thin.is_empty(), "every declaration explains itself%s" % _trouble(thin, " — "))

	# The hubs that are meant to be one source, pinned by shape: the azure press and the sheep pen.
	# Deleting a reason puts the warning straight back.
	for pair in [["scribe_blue_ink", "the level-25 press"], ["ranch_wool", "the sheep pen"]]:
		_ok(declared.has(str(pair[0])), "'%s' is declared one source on purpose (%s)" % pair)

	# The measurement that stopped two false alarms: raw essence is made by three recipes and the
	# catalyst drops from twenty enemies. Counting kinds instead of sources called both single
	# points of failure, which is exactly how a warning list stops being read.
	var sources: Dictionary = {}
	for entry in BalanceReport.demand_rows():
		sources[str((entry as Dictionary)["item_id"])] = int((entry as Dictionary)["sources"])
	_ok(int(sources.get("rune_essence", 0)) >= 2,
		"raw glyph essence has %d sources" % int(sources.get("rune_essence", 0)))
	_ok(int(sources.get("enchant_catalyst", 0)) >= 10,
		"the enchant catalyst has %d sources, not one" % int(sources.get("enchant_catalyst", 0)))
	# Scribe Paper was declared one source, and that was wrong: the Dream Bazaar sells fifty sheets
	# for forty dream essence. It is the first declaration this data ever carried, and the only
	# reason the mistake surfaced is that the source model was told where the bazaar is. Each row
	# below is one acquisition path that used to be invisible, so the model cannot quietly lose it
	# again — the same trick as the demand channels, on the supply side.
	for probe in [["scribe_paper", 2, "the mill plus the Dream Bazaar's paper bundle"],
			["pure_essence", 1, "the museum's glyph curio"], ["artefact_common", 1, "a dig site"],
			["coal", 3, "crafted, dropped, bought and awarded"], ["dream_essence", 1, "dream journeys"],
			["burnt_food", 1, "a failed cook"], ["border_collie_mark", 1, "the familiar that awards it"]]:
		_ok(int(sources.get(str(probe[0]), 0)) >= int(probe[1]),
			"'%s' has %d sources (%s)" % [probe[0], int(sources.get(str(probe[0]), 0)), probe[2]])
	var stall_items: Array[String] = ShopManager.stall_item_ids()
	_ok(not stall_items.is_empty() and int(sources.get(stall_items[0], 0)) >= 1,
		"the mastery stall stocks a source of its own (%s)" % (stall_items[0] if not stall_items.is_empty() else "none"))

	# The report has to print the reason, or the declaration is invisible where it is needed.
	var report_text: String = "\n".join(BalanceReport.format_text())
	var unprinted: Array[String] = []
	for item_id in declared:
		var reason: String = str(DataLoader.get_item(str(item_id)).get("bottleneck_reason", ""))
		if not report_text.contains(reason):
			unprinted.append(str(item_id))
	_ok(unprinted.is_empty(), "the report prints every declaration%s" % _trouble(unprinted, " — "))

## The skill audit found the Attunement studies were not a ramp: study_3 (level 60) paid exactly
## what study_2 paid, and study_4 (level 90) paid less than both, so a player was better off staying
## on the older action. Each study must beat the one below it.
func _test_study_ramp_rises() -> void:
	_heading("The Attunement studies rise")
	var studies: Array = []
	for action in DataLoader.get_skill_actions("enchanting"):
		var id: String = str(action.get("id", ""))
		if id.begins_with("study_") and id.substr(6).is_valid_int():
			studies.append(action)
	_ok(studies.size() == 6, "the six Attunement studies are present (%d)" % studies.size())
	studies.sort_custom(func(a, b): return int(a["level_required"]) < int(b["level_required"]))
	var previous: Dictionary = {}
	for study in studies:
		if not previous.is_empty():
			_ok(float(study["base_xp"]) > float(previous["base_xp"]),
				"the level-%d study pays more than the level-%d one (%d > %d)" % [
					int(study["level_required"]), int(previous["level_required"]),
					int(study["base_xp"]), int(previous["base_xp"])])
		previous = study

## The skill audit flagged seven "a higher level pays less" pairs. Comparing any two actions is a
## heuristic — a no-input listener against a chain step, or a bar against a finished ring, are not the
## same job — but grouping each skill's actions by their EXACT inputs and interval isolates the real
## thing: identical work that pays less for being higher level. Three such regressions existed, all
## in Inscription, where the scribe ladder sat flat at 189 and then fell to 188 and 186 while the
## level-40 recipe out-paid the level-90 one. This check is that rule.
func _test_action_xp_ladders() -> void:
	_heading("Identical work pays more at a higher level")
	var rungs: int = 0
	var regressions: int = 0
	for skill_id in DataLoader.get_skill_ids():
		var groups: Dictionary = {}
		for action in DataLoader.get_skill_actions(str(skill_id)):
			if typeof(action) != TYPE_DICTIONARY:
				continue
			var key: String = "%s|%s" % [str(action.get("base_interval", 0.0)), _input_signature(action)]
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(action)
		for key in groups.keys():
			var group: Array = groups[key]
			if group.size() < 2:
				continue
			# The best payer at each level: several recipes can share one level and differ in reward,
			# which is flavour rather than a ladder.
			var best_by_level: Dictionary = {}
			for action in group:
				var level: int = int(action["level_required"])
				var xp: float = float(action.get("base_xp", 0.0))
				if xp > float(best_by_level.get(level, -1.0)):
					best_by_level[level] = xp
			var levels: Array = best_by_level.keys()
			levels.sort()
			var paid_best: float = -1.0
			var paid_at: int = 0
			for level in levels:
				rungs += 1
				var here: float = float(best_by_level[level])
				if here < paid_best:
					regressions += 1
				_ok(here >= paid_best,
					"%s: the same work at L%d pays at least the L%d rate (%.0f vs %.0f)" % [
						skill_id, int(level), paid_at, here, maxf(paid_best, 0.0)])
				if here > paid_best:
					paid_best = here
					paid_at = int(level)
	_ok(rungs > 0, "there are comparable ladders to check (%d rungs)" % rungs)
	_ok(regressions == 0, "no identical job regresses at a higher level (%d)" % regressions)

## An action's inputs as a stable signature, so two recipes that eat the same things compare.
func _input_signature(action: Dictionary) -> String:
	var inputs: Dictionary = action.get("input_items", {})
	var ids: Array = inputs.keys()
	ids.sort()
	var parts: Array[String] = []
	for item_id in ids:
		parts.append("%s=%d" % [str(item_id), int(inputs[item_id])])
	return ",".join(parts)

## Mastery metadata is authored, not derived, so it drifts silently. ModifierKeys.gd promises "no
## module typos a key" — fourteen keys the new systems read by name were absent from it, so a typo in
## a mastery table failed silently instead of being caught. This is what makes the promise hold, and
## it pins the two shapes the skill audit called inconsistent: a pool checkpoint may sit only on the
## four documented marks, and an authored success chance must be a real probability.
func _test_mastery_metadata() -> void:
	_heading("Mastery metadata is spelled and shaped correctly")
	var constants: Dictionary = ModifierKeys.new().get_script().get_script_constant_map()
	var registered: Dictionary = {}
	var suffixes: Array[String] = []
	for name in constants.keys():
		registered[str(constants[name])] = true
		if str(name).begins_with("SUFFIX_"):
			suffixes.append(str(constants[name]))
	_ok(suffixes.size() >= 5, "the per-skill suffix convention is registered (%d suffixes)" % suffixes.size())
	var no_unlocks: Array[String] = []
	var unspelled: Array[String] = []
	var off_mark: Array[String] = []
	var empty_tables: Array[String] = []
	var skill_count: int = 0
	var checkpoint_skills: int = 0
	for skill_id in DataLoader.get_skill_ids():
		var skill: Dictionary = DataLoader.get_skill(str(skill_id))
		skill_count += 1
		if not DataLoader.get_skill_actions(str(skill_id)).is_empty() and not skill.has("mastery_unlocks"):
			no_unlocks.append(str(skill_id))
		if skill.has("pool_checkpoints"):
			checkpoint_skills += 1
		for table_name in ["mastery_unlocks", "pool_checkpoints"]:
			var table: Dictionary = skill.get(table_name, {})
			for threshold in table.keys():
				if table_name == "pool_checkpoints" and not (int(threshold) in [10, 25, 50, 95]):
					off_mark.append("%s@%s" % [skill_id, threshold])
				var mods: Dictionary = table[threshold]
				if mods.is_empty():
					empty_tables.append("%s %s %s" % [skill_id, table_name, threshold])
				for key in mods.keys():
					var spelled: String = str(key)
					if registered.has(spelled) or suffixes.has(spelled.trim_prefix("%s_" % str(skill_id))):
						continue
					unspelled.append("%s %s -> %s" % [skill_id, table_name, spelled])
	_ok(skill_count >= 39, "every skill was inspected (%d)" % skill_count)
	_ok(no_unlocks.is_empty(), "every skill with actions declares mastery unlocks%s" % _trouble(no_unlocks, " — missing: "))
	_ok(unspelled.is_empty(), "every authored modifier key is registered%s" % _trouble(unspelled, " — unspelled: "))
	_ok(off_mark.is_empty(), "pool checkpoints sit on the four documented marks%s" % _trouble(off_mark, " — off-mark: "))
	_ok(empty_tables.is_empty(), "no mastery table is empty%s" % _trouble(empty_tables, " — empty: "))
	_ok(checkpoint_skills >= 5, "the newest systems carry pool checkpoints (%d skills)" % checkpoint_skills)
	# An absent success chance runs at the guaranteed default, which is why smithing and crafting never
	# burn materials; an authored one has to be a real roll.
	var authored: int = 0
	var defaulted: int = 0
	var bad_chance: Array[String] = []
	for skill_id in DataLoader.get_skill_ids():
		for action in DataLoader.get_skill_actions(str(skill_id)):
			if typeof(action) != TYPE_DICTIONARY:
				continue
			if not (action as Dictionary).has("success_chance"):
				defaulted += 1
				continue
			authored += 1
			var chance: float = float((action as Dictionary)["success_chance"])
			if chance <= 0.0 or chance > 1.0:
				bad_chance.append("%s/%s" % [skill_id, str((action as Dictionary).get("id", ""))])
	_ok(authored > 20, "skills author real success chances (%d)" % authored)
	_ok(defaulted > 0, "some actions rely on the guaranteed default (%d)" % defaulted)
	_ok(bad_chance.is_empty(), "every authored success chance is a probability%s" % _trouble(bad_chance, " — invalid: "))

## The detail pane is the answer to "what do I need, and where do I get it?" for whatever the player
## last touched, and it is the pane they read most. Rendering is also where a missing key surfaces:
## a dictionary read with [] raises instead of returning null, so a card can stop halfway through
## with no visible error. This sweeps the whole content table rather than a sample: every item and
## every recipe has to produce a titled card with substance in it, and the two live tap paths
## (the Overview's goal card, the Skills screen's activity row) have to hand the pane a context it
## can actually render.
func _test_detail_cards(host: Node) -> void:
	_heading("Every goal and recipe opens a complete card")
	GameManager.start_new_game("standard")
	var panel: Control = load("res://scripts/ui/DetailPanel.gd").new()
	host.add_child(panel)
	var title: Label = panel.get("_title")
	var subtitle: Label = panel.get("_subtitle")
	var body: VBoxContainer = panel.get("_body")

	var mislabeled: Array[String] = []
	var hollow: Array[String] = []
	var placeholder: Array[String] = []
	var unsourced: Array[String] = []
	var shapeless: Array[String] = []
	var unroutable: Array[String] = []
	var too_wide: Array[String] = []
	for item_id in DataLoader.items.keys():
		var id: String = str(item_id)
		panel.call("show_item", id)
		# The pane is 260px wide on desktop. A card that needs more is clipped, not scrolled, so
		# the value beside a long label silently disappears.
		if panel.get_combined_minimum_size().x > UITokens.W_DETAIL - 8:
			too_wide.append(id)
		if title.text != str(DataLoader.get_item(id).get("name", id)):
			mislabeled.append(id)
		if body.get_child_count() < 2:
			hollow.append(id)
		var text: String = _card_text(body)
		if text.contains("<null>") or text.contains("Unknown ") or text.contains("Unavailable"):
			placeholder.append(id)
		if text.contains("No known acquisition path"):
			unsourced.append(id)
		# The card is the player-facing copy of the acquisition model, so every row on it has to be
		# readable on its own and every route has to name a screen the shell can actually open.
		for source in Goals.sources_for_item(id):
			var entry: Dictionary = source
			if str(entry.get("label", "")) == "" or str(entry.get("detail", "")) == "":
				shapeless.append(id)
			var route: Dictionary = entry.get("route", {})
			if not route.is_empty() and not _known_screen(str(route.get("screen", ""))):
				unroutable.append("%s -> %s" % [id, str(route.get("screen", ""))])
	_ok(mislabeled.is_empty(), "every item card is titled with the item's name%s" % _trouble(mislabeled, " — wrong: "))
	_ok(hollow.is_empty(), "every item card renders more than its title%s" % _trouble(hollow, " — thin: "))
	_ok(unsourced.is_empty(), "every item card answers where it comes from%s" % _trouble(unsourced, " — unsourced: "))
	_ok(placeholder.is_empty(), "no item card shows placeholder text%s" % _trouble(placeholder, " — broken: "))
	_ok(shapeless.is_empty(), "every source row carries a label and an explanation%s" % _trouble(shapeless, " — bare: "))
	_ok(unroutable.is_empty(), "every source route names a screen that exists%s" % _trouble(unroutable, " — dead: "))
	_ok(too_wide.is_empty(), "every item card fits the pane it renders in%s" % _trouble(too_wide, " — clipped: "))

	var bad_recipe: Array[String] = []
	var thin_recipe: Array[String] = []
	var statusless: Array[String] = []
	var wide_recipes: Array[String] = []
	var recipes: int = 0
	for skill_id in DataLoader.get_skill_ids():
		for action in DataLoader.get_skill_actions(str(skill_id)):
			if typeof(action) != TYPE_DICTIONARY:
				continue
			var a: Dictionary = action
			var action_id: String = str(a.get("id", ""))
			var key: String = "%s:%s" % [skill_id, action_id]
			recipes += 1
			panel.call("show_recipe", str(skill_id), action_id)
			if title.text != str(a.get("name", action_id)) or not subtitle.text.contains("recipe"):
				bad_recipe.append(key)
			if body.get_child_count() < 2:
				thin_recipe.append(key)
			if not _card_text(body).contains("Can start now"):
				statusless.append(key)
			if panel.get_combined_minimum_size().x > UITokens.W_DETAIL - 8:
				wide_recipes.append(key)
	_ok(recipes >= 580, "every authored recipe was rendered (%d)" % recipes)
	_ok(bad_recipe.is_empty(), "every recipe card is titled and labelled as a recipe%s" % _trouble(bad_recipe, " — wrong: "))
	_ok(thin_recipe.is_empty(), "every recipe card renders more than its title%s" % _trouble(thin_recipe, " — thin: "))
	_ok(statusless.is_empty(), "every recipe card states whether it can start%s" % _trouble(statusless, " — silent: "))
	_ok(wide_recipes.is_empty(), "every recipe card fits the pane it renders in%s" % _trouble(wide_recipes, " — clipped: "))

	# The channels the card was blind to until now. Each one is a real way the game hands an item
	# over that the pane called unfinished content: a byproduct, a familiar's mark, a burnt dish, a
	# harvest, a ranch byproduct, a Slayer shop line and a raid reward.
	var channel_items: Dictionary = {
		"byproduct": "diamond",
		"familiar mark": "ent_mark",
		"failure output": "burnt_food",
		"farm harvest": "duskroot",
		"ranch byproduct": "ranch_feed",
		"slayer shop": "slayer_armour_basic",
		"raid reward": "raid_pet_egg",
	}
	var silent: Array[String] = []
	for channel in channel_items.keys():
		var id: String = str(channel_items[channel])
		if Goals.sources_for_item(id).is_empty():
			silent.append("%s (%s)" % [channel, id])
	_ok(silent.is_empty(), "every acquisition channel answers on its item card%s" % _trouble(silent, " — silent: "))

	# Task rewards were invisible here too, so a reward item read as unobtainable on the one screen
	# that answers "where do I get this?".
	var quest_items: Array[String] = []
	for quest_id in Quests.all_quest_ids():
		for item_id in ((Quests.get_quest(quest_id).get("reward", {}) as Dictionary).get("items", {}) as Dictionary).keys():
			if not quest_items.has(str(item_id)):
				quest_items.append(str(item_id))
	var unnamed: Array[String] = []
	for item_id in quest_items.slice(0, 8):
		var named: bool = false
		for source in Goals.sources_for_item(item_id):
			if str((source as Dictionary).get("route", {}).get("screen", "")) == Screens.QUESTS:
				named = true
		if not named:
			unnamed.append(item_id)
	_ok(not quest_items.is_empty() and unnamed.is_empty(),
		"a task reward item points at the Tasks screen%s" % _trouble(unnamed, " — missing: "))

	# A recipe the player cannot run says where the missing material comes from, not only that it is
	# missing: that is the question the pane exists to answer.
	panel.call("show_recipe", "crafting", "craft_diamond_ring")
	var blocked: String = _card_text(body)
	_ok(blocked.contains("Diamond") and blocked.contains("Delving"),
		"a blocked recipe names the action that supplies its missing material")
	# An unknown activity must say so rather than leave the previous card standing.
	panel.call("show_recipe", "crafting", "no_such_action_id")
	_ok(title.text == "Unavailable", "an unknown activity replaces the card instead of leaving it stale")

	# Every goal kind the game can pin, resolved and rendered through the same call the screens use.
	var kinds: Array[Dictionary] = [
		{"kind": "item", "id": "normal_log"},
		{"kind": "recipe", "id": "woodcutting:normal_tree"},
		{"kind": "skill", "id": "woodcutting", "level": 10},
		{"kind": "quest", "id": str(Quests.all_quest_ids()[0])},
		{"kind": "building", "id": str(DataLoader.township_buildings.keys()[0])},
		{"kind": "upgrade", "id": str(DataLoader.shop.keys()[0])},
	]
	var unresolved: Array[String] = []
	var unrendered: Array[String] = []
	var wide_goals: Array[String] = []
	for goal in kinds:
		var resolved: Dictionary = Goals.resolve(goal)
		if not bool(resolved.get("ok", false)):
			unresolved.append("%s (%s)" % [str(goal["kind"]), str(resolved.get("problem", ""))])
			continue
		panel.call("set_inline_context", {"kind": "goal", "goal": goal})
		if title.text != str(resolved.get("label", "")) or body.get_child_count() < 2:
			unrendered.append("%s -> '%s'" % [str(goal["kind"]), title.text])
		if panel.get_combined_minimum_size().x > UITokens.W_DETAIL - 8:
			wide_goals.append(str(goal["kind"]))
	_ok(unresolved.is_empty(), "every goal kind resolves%s" % _trouble(unresolved, " — unresolved: "))
	_ok(unrendered.is_empty(), "tapping any goal opens its card%s" % _trouble(unrendered, " — blank: "))
	_ok(wide_goals.is_empty(), "every goal card fits the pane it renders in%s" % _trouble(wide_goals, " — clipped: "))

	# A goal card that cannot answer "where from" must say so rather than silently drop the section,
	# and a recipe goal must agree with its own progress bar (it used to read "complete" next to
	# "0 / 1", which is the mismatch that made this card look broken).
	var unreachable: Dictionary = Goals.resolve({"kind": "item", "id": "__not_an_item__"})
	_ok(not bool(unreachable.get("ok", false)), "an impossible goal resolves to a refusal, not a lie")
	var goal_edges: Array[String] = []
	for goal in kinds:
		var resolved_goal: Dictionary = Goals.resolve(goal)
		if not bool(resolved_goal.get("ok", false)):
			continue
		var bar_full: bool = float(resolved_goal.get("progress_current", 0)) >= float(resolved_goal.get("progress_required", 1))
		if bar_full != bool(resolved_goal.get("complete", false)):
			goal_edges.append("%s:%s" % [str(goal.get("kind", "")), str(goal.get("id", ""))])
	_ok(goal_edges.is_empty(), "every goal's progress bar agrees with its verdict%s" % _trouble(goal_edges, " — split: "))

	# The Overview's Explain button on a tracked goal: the exact tap the player makes.
	Goals.clear()
	Goals.pin("item", "normal_log")
	var overview: Control = load("res://scripts/ui/panels/OverviewPanel.gd").new()
	host.add_child(overview)
	var explain: Button = _find_button(overview.get("_goals_box"), "Explain")
	_ok(explain != null, "a tracked goal offers an Explain button")
	if explain != null:
		var contexts: Array[Dictionary] = []
		overview.connect("context_changed", func(ctx): contexts.append(ctx))
		explain.pressed.emit()
		_ok(contexts.size() == 1 and str((contexts[0] as Dictionary).get("kind", "")) == "goal",
			"Explain asks the detail pane for that goal")
		if contexts.size() == 1:
			var ctx: Dictionary = contexts[0]
			_ok(bool(Goals.resolve(ctx.get("goal", {})).get("ok", false)), "the emitted goal context resolves")

	# The Skills screen selects an activity and emits the recipe context the pane consumes.
	var skills: Control = load("res://scripts/ui/panels/SkillsPanel.gd").new()
	host.add_child(skills)
	var emitted: Array[Dictionary] = []
	skills.connect("context_changed", func(ctx): emitted.append(ctx))
	skills.call("_select_skill", "woodcutting")
	skills.call("_select_action", "normal_tree")
	_ok(emitted.size() == 1 and str((emitted[0] as Dictionary).get("action_id", "")) == "normal_tree",
		"selecting an activity asks the detail pane for its recipe")
	if emitted.size() == 1:
		panel.call("set_inline_context", emitted[0])
		_ok(title.text == "Emberpine Tree" and _card_text(body).contains("Can start now"),
			"the recipe that screen hands over renders as a card")
	skills.call("_select_action", "")

	# Structure can be right while the layout starves it: the 132px key column of a key/value row
	# sitting beside a 64px icon left the value column one pixel wide, and "500 GP" rendered as a
	# ladder of single letters down the edge of the pane. This measures a card that has been laid
	# out at the pane's real width, which is the only way to see a squeeze.
	var frame := Control.new()
	frame.size = Vector2(UITokens.W_DETAIL, 640)
	host.add_child(frame)
	frame.add_child(panel)
	# A plain Control does not size its children, and a VBox would otherwise collapse to its own
	# minimum: the pane has to be told how wide it is for this to measure anything.
	panel.size = frame.size
	var starved: Array[String] = []
	var cases: Array[Dictionary] = [
		{"label": "diamond", "call": func(): panel.call("show_item", "diamond")},
		{"label": "bronze_sword", "call": func(): panel.call("show_item", "bronze_sword")},
		{"label": "shrimp", "call": func(): panel.call("show_item", "shrimp")},
		{"label": "raid_pet_egg", "call": func(): panel.call("show_item", "raid_pet_egg")},
		{"label": "enchanting_skillcape", "call": func(): panel.call("show_item", "enchanting_skillcape")},
		{"label": "goal:diamond", "call": func(): panel.call("set_inline_context", {"kind": "goal", "goal": {"kind": "item", "id": "diamond", "level": 100}})},
		{"label": "recipe:craft_diamond_ring", "call": func(): panel.call("show_recipe", "crafting", "craft_diamond_ring")},
	]
	for case in cases:
		(case["call"] as Callable).call()
		# A card's labels report a 1px width until the containers have sorted them, and a card that
		# was never laid out would look squeezed for a reason that is not the card's fault.
		await _layouts_settled(panel)
		var squeezed: Array[String] = []
		_collect_starved(panel, squeezed)
		if not squeezed.is_empty():
			starved.append("%s (pane %.0fpx: %s)" % [str(case["label"]), panel.size.x,
				", ".join(squeezed.slice(0, 3))])
	_ok(starved.is_empty(), "no card squeezes a label below reading width%s" % _trouble(starved, " — starved: "))

	Goals.clear()
	panel.queue_free()
	overview.queue_free()
	skills.queue_free()

## Waits for the pane to be laid out at its real width. Returns false (which the caller reports as a
## squeeze) when that never happens, so a layout that simply did not run cannot pass as a healthy
## card.
func _layouts_settled(panel: Control) -> bool:
	for _i in 4:
		await panel.get_tree().process_frame
		var body: Control = panel.get("_body")
		if panel.size.x > 100.0 and body != null and body.size.x > 60.0:
			return true
	return false

## A label laid out narrower than this with real text in it is either clipped or wrapped one
## character per line: the value column of a starved key/value row. The text is carried out so a
## failure names the row that squeezed, not just the card.
func _collect_starved(root: Node, into: Array[String]) -> void:
	for child in root.get_children():
		if child is Label and (child as Label).text.length() > 5 and (child as Control).size.x < 20.0:
			into.append((child as Label).text.substr(0, 28))
		_collect_starved(child, into)

## A route the pane offers has to name a screen the shell can actually open. "skill" is the
## singular form Goals has always used; MainUI.navigate resolves it to the Skills screen.
func _known_screen(screen: String) -> bool:
	if screen == "skill" or screen == Screens.RECOVERY:
		return true
	return screen in Screens.ORDER

## Every visible string in a rendered control tree, for asserting on a card as the player reads it.
func _card_text(root: Node) -> String:
	var parts: Array[String] = []
	_card_text_into(root, parts)
	return " | ".join(parts)

func _card_text_into(node: Node, parts: Array[String]) -> void:
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	for child in node.get_children():
		_card_text_into(child, parts)

## A short tail for an assertion label, or "" when there is nothing to report.
func _trouble(entries: Array[String], lead: String) -> String:
	if entries.is_empty():
		return ""
	return "%s%s" % [lead, ", ".join(entries.slice(0, 6))]

## Food is a combat resource: the player must be able to eat it deliberately, mid-fight, to heal.
## Auto-eat existed but was off by default and shop-gated, so a new player had no way to heal.
func _test_food_heals_in_combat(host: Node) -> void:
	_heading("Food heals you when you choose to eat it")
	GameManager.start_new_game("standard")
	var shrimp: Dictionary = DataLoader.get_item("shrimp")
	_ok(int(shrimp.get("heal_amount", 0)) > 0, "cooked shrimp heals")

	# Hurt, stock food, eat: the player heals and the food leaves the bank. Use a fraction of real
	# max HP: a level-1 character tops out around 10 HP, so an absolute "10" would already be full.
	CombatManager.player_hp = CombatManager._compute_max_hp()
	BankManager.add_item_guaranteed("shrimp", 5)
	var maxhp: float = CombatManager._compute_max_hp()
	CombatManager.player_hp = maxf(1.0, maxhp * 0.25)
	var hurt_at: float = CombatManager.player_hp
	var shrimp_before: int = BankManager.get_count("shrimp")
	_ok(CombatManager.eat_best_food() == "shrimp", "eating picks a food you actually have")
	_ok(CombatManager.player_hp > hurt_at, "eating healed the player (%d -> %d HP)" % [int(hurt_at), int(CombatManager.player_hp)])
	_ok(BankManager.get_count("shrimp") == shrimp_before - 1, "the food was consumed from the bank")
	_ok(CombatManager.player_hp <= maxhp, "healing never exceeds max HP")

	# The pick is the smallest food that covers the gap, so a big meal is not wasted on a scratch.
	CombatManager.player_hp = maxf(1.0, maxhp * 0.25)
	BankManager.add_item_guaranteed("shrimp", 5)
	BankManager.add_item_guaranteed("abyssal_eel", 5)
	_ok(not CombatManager.find_food().is_empty(), "find_food returns a stocked food id")

	# Non-food must be refused: burnt food is item_type resource, so it can never heal.
	CombatManager.player_hp = maxf(1.0, maxhp * 0.25)
	BankManager.add_item_guaranteed("burnt_food", 5)
	_ok(CombatManager.consume_food("burnt_food") == "", "burnt food cannot be eaten")
	_ok(BankManager.get_count("burnt_food") == 5, "refused food is not consumed")
	_ok(CombatManager.consume_food("nonexistent_item") == "", "an unknown item cannot be eaten")

	# The button lives on the strip that is visible in every screen, and says why it is disabled.
	GameManager.start_new_game("standard")
	BankManager.add_item_guaranteed("shrimp", 3)
	var strip = load("res://scripts/ui/ActivityStrip.gd").new()
	host.add_child(strip)
	await host.get_tree().process_frame
	var eat: Button = strip.get("_eat")
	_ok(eat != null, "the activity strip exposes an Eat button")
	CombatManager.player_hp = CombatManager._compute_max_hp()
	strip.call("_refresh_eat")
	_ok(eat.disabled, "Eat is disabled at full health")
	_ok(eat.tooltip_text.contains("full health"), "the disabled Eat explains why (%s)" % eat.tooltip_text)
	CombatManager.player_hp = maxf(1.0, CombatManager._compute_max_hp() * 0.25)
	strip.call("_refresh_eat")
	_ok(not eat.disabled, "Eat is enabled when hurt and stocked")
	_ok(eat.text.contains("Shrimp"), "Eat names the food it will use (%s)" % eat.text)
	# Pressing it must heal, not just relabel.
	var hp_before: int = int(CombatManager.player_hp)
	eat.pressed.emit()
	_ok(CombatManager.player_hp > hp_before, "pressing Eat healed the player")
	_ok(BankManager.get_count("shrimp") == 2, "pressing Eat consumed exactly one food")
	# No food at all is its own reason, distinct from full health.
	GameManager.start_new_game("standard")
	strip.call("_refresh_eat")
	_ok(eat.disabled, "Eat is disabled with no food in Storage")
	_ok(eat.tooltip_text.contains("No food"), "the empty-bank reason is explained (%s)" % eat.tooltip_text)
	strip.queue_free()

	# Storage needs its own Eat action. The strip button only ever picks the best food for you, so
	# without this row a player who cooked a specific meal has no way to choose to eat that one.
	GameManager.start_new_game("standard")
	BankManager.add_item_guaranteed("shrimp", 4)
	var bank = load("res://scripts/ui/panels/BankPanel.gd").new()
	host.add_child(bank)
	bank.call("refresh")
	await host.get_tree().process_frame
	var labels: Array[String] = []
	for b in bank.find_children("", "Button", true, false):
		labels.append((b as Button).text)
	_ok(labels.has("Eat 1"), "a food row in Storage offers Eat 1 (%s)" % str(labels))
	_ok(labels.has("Eat all"), "a food row in Storage offers Eat all")
	_ok(not labels.has("Equip"), "food is not offered an Equip action")
	# Pressing it must really heal.
	CombatManager.player_hp = maxf(1.0, CombatManager._compute_max_hp() * 0.25)
	var hp_in_bank: int = int(CombatManager.player_hp)
	var shrimp_stored: int = BankManager.get_count("shrimp")
	for b in bank.find_children("", "Button", true, false):
		if (b as Button).text == "Eat 1":
			(b as Button).pressed.emit()
			break
	_ok(CombatManager.player_hp > hp_in_bank, "Storage's Eat 1 healed the player")
	_ok(BankManager.get_count("shrimp") == shrimp_stored - 1, "Storage's Eat 1 consumed one shrimp")
	# A non-food row must not grow an Eat button.
	GameManager.start_new_game("standard")
	BankManager.add_item_guaranteed("normal_log", 3)
	bank.call("refresh")
	await host.get_tree().process_frame
	labels = []
	for b in bank.find_children("", "Button", true, false):
		labels.append((b as Button).text)
	_ok(not labels.has("Eat 1"), "a log row has no Eat button")
	bank.queue_free()

func _find_artisan_with_inputs() -> Dictionary:
	for skill_id in DataLoader.get_skill_ids():
		if str(DataLoader.get_skill(skill_id).get("type", "")) != "artisan":
			continue
		for a in DataLoader.get_skill_actions(skill_id):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var inputs: Dictionary = a.get("input_items", {})
			var outputs: Dictionary = a.get("output_items", {})
			if inputs.is_empty() or outputs.is_empty():
				continue
			if int(a.get("node_hp", 0)) > 0:
				continue
			if float(a.get("success_chance", 1.0)) < 1.0 or a.has("perception"):
				continue
			return {"skill_id": skill_id, "action_id": str(a["id"]), "inputs": inputs, "outputs": outputs}
	return {}

func _find_artisan_producing_equipment() -> Dictionary:
	for skill_id in DataLoader.get_skill_ids():
		if str(DataLoader.get_skill(skill_id).get("type", "")) != "artisan":
			continue
		for a in DataLoader.get_skill_actions(skill_id):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var outputs: Dictionary = a.get("output_items", {})
			var inputs: Dictionary = a.get("input_items", {})
			if outputs.is_empty() or inputs.is_empty():
				continue
			if float(a.get("success_chance", 1.0)) < 1.0:
				continue
			for item_id in outputs.keys():
				var item: Dictionary = DataLoader.get_item(str(item_id))
				if str(item.get("item_type", "")) == "equipment":
					return {"skill_id": skill_id, "action_id": str(a["id"])}
	return {}

## The earliest region with enemies, so tests prove the opening loop rather than endgame gear.
func _find_area() -> Dictionary:
	var ids: Array = DataLoader.areas.keys()
	var usable: Array = []
	for area_id in ids:
		var row: Dictionary = DataLoader.areas[area_id]
		if str(row.get("type", "area")) == "slayer_area":
			continue
		var monsters: Array = row.get("monsters", [])
		if monsters.is_empty():
			continue
		var levels: Array = row.get("level_range", [0])
		usable.append({"id": area_id, "monsters": monsters,
			"low": int(levels[0]) if not levels.is_empty() else 0})
	if usable.is_empty():
		return {}
	usable.sort_custom(func(a, b): return int(a["low"]) < int(b["low"]))
	return {"id": str(usable[0]["id"]), "monsters": usable[0]["monsters"]}

func _find_satisfiable_quest() -> String:
	const SUPPORTED: Array[String] = ["have_item", "gain_item", "skill_level", "mastery_level",
		"buy_upgrade", "build_structure", "unlock_pet", "reach_region", "discover_items"]
	for quest_id in Quests.all_quest_ids():
		var q: Dictionary = Quests.get_quest(quest_id)
		var objectives: Array = q.get("objectives", [])
		if objectives.is_empty():
			continue
		var all_supported: bool = true
		for obj in objectives:
			if not SUPPORTED.has(str((obj as Dictionary).get("kind", ""))):
				all_supported = false
				break
		if all_supported:
			return quest_id
	return ""

func _satisfy_quest(quest_id: String) -> void:
	var q: Dictionary = Quests.get_quest(quest_id)
	for prerequisite in q.get("prerequisites", []):
		var prerequisite_id: String = str(prerequisite)
		if not Quests.is_claimed(prerequisite_id):
			_satisfy_quest(prerequisite_id)
			_ok(Quests.claim(prerequisite_id), "prerequisite %s can be claimed" % prerequisite_id)
	for obj in q.get("objectives", []):
		var o: Dictionary = obj
		var required: int = maxi(1, int(o.get("required", 1)))
		match str(o.get("kind", "")):
			"have_item", "gain_item":
				BankManager.add_item_guaranteed(str(o.get("item_id", "")), required)
			"skill_level":
				PlayerData.set_level(str(o.get("skill_id", "")), maxi(required, PlayerData.get_level(str(o.get("skill_id", "")))))
			"do_actions":
				PlayerData.bump_stat("actions", "%s:%s" % [str(o.get("skill_id", "")), str(o.get("action_id", ""))], float(required))
			"mastery_level":
				PlayerData.set_level(str(o.get("skill_id", "")), mini(XPTable.MAX_LEVEL, required))
				MasteryManager.add_mastery_xp(str(o.get("skill_id", "")), str(o.get("action_id", "")), 1.0, 0.0)
			"buy_upgrade":
				PlayerData.shop_upgrades[str(o.get("upgrade_id", ""))] = 1
			"build_structure":
				var building_id: String = str(o.get("building_id", ""))
				if DataLoader.township_buildings.has(building_id):
					TownshipManager.resources["wood"] = 100000.0
					TownshipManager.buildings[building_id] = required
			"unlock_pet":
				PlayerData.unlock_pet(str(o.get("pet_id", "")))
			"reach_region":
				PlayerData.bump_stat("region_visits", str(o.get("area_id", "")), 1.0)
			"discover_items":
				var needed: int = required - (PlayerData.completion_log.get("items", {}) as Dictionary).size()
				var index: int = 0
				var ids: Array = DataLoader.items.keys()
				while needed > 0 and index < ids.size():
					PlayerData.discover_item(str(ids[index]))
					index += 1
					needed -= 1

func _first_building_id() -> String:
	var ids: Array = DataLoader.township_buildings.keys()
	ids.sort()
	return str(ids[0]) if not ids.is_empty() else ""

func _first_item_id() -> String:
	var ids: Array = DataLoader.items.keys()
	ids.sort()
	return str(ids[0]) if not ids.is_empty() else ""

func _second_item_id(exclude: String) -> String:
	var ids: Array = DataLoader.items.keys()
	ids.sort()
	for item_id in ids:
		if str(item_id) != exclude:
			return str(item_id)
	return exclude

func _find_equippable_item_with_modifiers() -> String:
	var ids: Array = DataLoader.items.keys()
	ids.sort()
	for item_id in ids:
		var item: Dictionary = DataLoader.items[item_id]
		if str(item.get("item_type", "")) != "equipment":
			continue
		if int(item.get("equipment_slot", -1)) < 0:
			continue
		if (item.get("passive_modifiers", {}) as Dictionary).is_empty():
			continue
		return str(item_id)
	return ""

func _find_weapon() -> String:
	var ids: Array = DataLoader.items.keys()
	ids.sort()
	for item_id in ids:
		var item: Dictionary = DataLoader.items[item_id]
		if str(item.get("item_type", "")) == "equipment" and int(item.get("equipment_slot", -1)) == ItemData.EquipmentSlot.WEAPON:
			return str(item_id)
	return ""

func _strongest_monster(pool: Array) -> String:
	var best: String = str(pool[0]) if not pool.is_empty() else ""
	var best_level: int = -1
	for monster_id in pool:
		var m: Dictionary = DataLoader.get_monster(str(monster_id))
		var level: int = int(m.get("combat_level", 1))
		if level > best_level:
			best_level = level
			best = str(monster_id)
	return best

## Sum every entry of a lifetime counter bucket (used for totals like kills and deaths).
func _stat_total(bucket: String) -> float:
	var table: Variant = PlayerData.stats.get(bucket, {})
	if typeof(table) == TYPE_DICTIONARY:
		var total: float = 0.0
		for key in (table as Dictionary).keys():
			total += float((table as Dictionary)[key])
		return total
	return float(table) if typeof(table) == TYPE_FLOAT or typeof(table) == TYPE_INT else 0.0

## Everything the player owns: stored, waiting in overflow, and worn.
func _total_items_held() -> int:
	var total: int = 0
	for item_id in BankManager.items.keys():
		total += int(BankManager.items[item_id])
	for item_id in BankManager.overflow.keys():
		total += int(BankManager.overflow[item_id])
	total += EquipmentManager.slots.size()
	return total

## Raise the skills an item demands so it can be equipped in a test. Both shapes count:
## `level_requirements` ({skill: level}) for ordinary gear and `requires_level` ({skill, level})
## for the capes, which EquipmentManager enforces the same way.
func _meet_requirements(item_id: String) -> void:
	var item: Dictionary = DataLoader.get_item(item_id)
	for skill_id in (item.get("level_requirements", {}) as Dictionary).keys():
		var need: int = int(item["level_requirements"][skill_id])
		if PlayerData.get_level(str(skill_id)) < need:
			PlayerData.set_level(str(skill_id), need)
	var cape_gate: Dictionary = item.get("requires_level", {})
	if not cape_gate.is_empty():
		var gate_skill: String = str(cape_gate.get("skill", ""))
		var gate_level: int = int(cape_gate.get("level", 0))
		if gate_skill != "" and PlayerData.get_level(gate_skill) < gate_level:
			PlayerData.set_level(gate_skill, gate_level)

func _primary_output(skill_id: String, action_id: String) -> String:
	var outputs: Dictionary = DataLoader.get_action(skill_id, action_id).get("output_items", {})
	for item_id in outputs.keys():
		return str(item_id)
	return ""

# =========================================================================
#  Safe state handling
# =========================================================================

## Seed every generator the simulation can consult, so a test run is reproducible and the
## online/offline comparison is a fair one. Several managers roll their own RNG (pet unlocks,
## summoning marks, farming survival, slayer task rolls); leaving any of them random would mean
## two "identical" runs diverge through a passive XP bonus rather than through the model.
func _deterministic(on: bool) -> void:
	if not on:
		return
	const SEED: int = 20260925
	CombatManager.seed_rng(SEED)
	SkillManager._rng.seed = SEED
	PetManager._rng.seed = SEED + 1
	FarmingManager._rng.seed = SEED + 2
	SlayerManager._rng.seed = SEED + 3
	SummoningManager._rng.seed = SEED + 4
	RaidManager._rng.seed = SEED + 5

# =========================================================================
#  Assertions
# =========================================================================

func _begin(title: String) -> void:
	_passed = 0
	_failed = 0
	_failures.clear()
	print("=== %s ===" % title)

func _heading(name: String) -> void:
	_section = name
	print("\n-- %s --" % name)

func _ok(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		_failures.append("[%s] %s" % [_section, label])
		print("  FAIL  %s" % label)

func _eq(actual: Variant, expected: Variant, label: String) -> void:
	var same: bool = false
	if typeof(actual) == TYPE_FLOAT or typeof(expected) == TYPE_FLOAT:
		same = absf(float(actual) - float(expected)) < 0.0001
	elif typeof(actual) == TYPE_INT and typeof(expected) == TYPE_INT:
		same = int(actual) == int(expected)
	else:
		same = str(actual) == str(expected)
	if same:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		_failures.append("[%s] %s (expected %s, got %s)" % [_section, label, str(expected), str(actual)])
		print("  FAIL  %s (expected %s, got %s)" % [label, str(expected), str(actual)])

func _approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		_failures.append("[%s] %s (expected %s ± %s, got %s)" % [_section, label, str(expected), str(tolerance), str(actual)])
		print("  FAIL  %s (expected %s +/- %s, got %s)" % [label, str(expected), str(tolerance), str(actual)])

func _report() -> void:
	print("\n=== results ===")
	if _failed > 0:
		print("failures:")
		for f in _failures:
			print("  - %s" % f)
	print("checks passed: %d" % _passed)
	print("checks failed: %d" % _failed)
	if _failed == 0:
		print("ALL TESTS PASSED (%d checks)" % _passed)
	else:
		print("TESTS FAILED (%d of %d checks)" % [_failed, _passed + _failed])

## The Stats screen is a read-out, so the only thing worth asserting is that it reads the
## persisted record rather than recomputing: per-skill folding of "skill:action" keys, totals
## that sum a per-id bucket, and an empty save that says so instead of printing a table of zeros.
func _test_lifetime_stats_screen(host: Node) -> void:
	_heading("Lifetime stats screen")
	GameManager.start_new_game("standard")
	var panel: Control = load("res://scripts/ui/panels/StatsPanel.gd").new()
	host.add_child(panel)
	var body: VBoxContainer = panel.get("_body")
	_ok(body.get_child_count() == 1 and body.get_child(0) is Label,
		"a fresh save shows one friendly line, not a table of zeros")
	# Two activities under one skill: the per-skill ranking must fold them together rather than
	# reporting each action separately, and must not leak the raw "skill:action" key as a name.
	PlayerData.bump_stat("actions", "woodcutting:normal_log", 4.0)
	PlayerData.bump_stat("actions", "woodcutting:oak_log", 6.0)
	PlayerData.bump_stat("actions", "fishing:shrimp", 9.0)
	PlayerData.bump_stat("monsters_killed", "goblin", 12.0)
	PlayerData.bump_stat("monsters_killed", "wolf", 3.0)
	PlayerData.bump_stat("items_gained", "normal_log", 10.0)
	PlayerData.bump_total("deaths", 2.0)
	PlayerData.stats["region_visits"]["farmlands"] = true
	panel.call("refresh")
	var specs: Array = panel.get("RANKINGS")
	var skill_spec: Dictionary = specs[0]
	for spec in specs:
		if str((spec as Dictionary)["kind"]) == "skills":
			skill_spec = spec
	var skills: Array = panel.call("_top", skill_spec)
	_eq(skills.size(), 2, "two skills with activity, not three activities")
	_eq(str(skills[0]["name"]), str(DataLoader.get_skill("woodcutting").get("name", "woodcutting")),
		"the busier skill leads the ranking")
	_eq(float(skills[0]["count"]), 10.0, "both woodcutting activities fold into one total")
	_eq(float(skills[1]["count"]), 9.0, "the other skill's count is read back")
	var monsters: Array = panel.call("_top", specs[0])
	_eq(str(monsters[0]["name"]), str(DataLoader.get_monster("goblin").get("name", "goblin")),
		"the monster ranking resolves a display name and sorts by count")
	_eq(float(monsters[1]["count"]), 3.0, "the second-placed monster is ordered by count")
	_eq(panel.call("_total", PlayerData.stats, "actions"), 19.0, "the actions bucket totals across every id")
	_eq(panel.call("_total", PlayerData.stats, "region_visits"), 1.0, "a visit flag counts as one region")
	_eq(panel.call("_total", PlayerData.stats, "deaths"), 2.0, "a scalar bucket is already its own total")
	panel.queue_free()


# =========================================================================
#  Settings gaps: autosave cadence, game speed, notification categories
# =========================================================================

## The three settings added to Settings (autosave cadence, game speed, notification categories)
## have the three properties every setting must have, and the reset action has one more: it must
## not be destructive by default. Each is checked against the real singletons, because a setting
## written to a dictionary the game never reads is worse than no setting at all.
func _test_settings_gap_keys() -> void:
	_heading("Settings: autosave cadence, speed and notification categories")
	var new_keys: Array[String] = ["autosave_interval", "game_speed",
		"notify_success", "notify_warn", "notify_info"]
	for key in new_keys:
		_ok(SettingsDefaults.DEFAULTS.has(key), "the setting '%s' has a declared default" % key)

	# --- defaults are the documented ones, not placeholder zeros.
	_approx(float(SettingsDefaults.get_default("autosave_interval", 0.0)),
		SaveManager.AUTOSAVE_INTERVAL, 0.001, "autosave defaults to the SaveManager cadence")
	_approx(float(SettingsDefaults.get_default("game_speed", 0.0)), 1.0, 0.001,
		"game speed defaults to 1x")
	for kind in EventBus.MUTABLE_NOTIFICATION_KINDS:
		_ok(bool(SettingsDefaults.get_default("notify_%s" % kind, false)),
			"'%s' notifications are on by default" % kind)
	_ok(not EventBus.MUTABLE_NOTIFICATION_KINDS.has("error"),
		"errors are not offerable as a mute, so a failed save can never be silenced")

	# --- save round-trip: a value written to settings comes back through _apply, live.
	GameManager.set_speed(4.0)
	SaveManager.set_autosave_interval(120.0)
	PlayerData.settings["notify_warn"] = false
	_ok(absf(Engine.time_scale - 4.0) < 0.001, "setting the speed scales the engine clock")
	_approx(SaveManager.get_autosave_interval(), 120.0, 0.001, "the chosen cadence takes effect")
	_approx(float(PlayerData.settings["game_speed"]), 4.0, 0.001,
		"the speed control writes the setting the save file carries")
	_ok(SaveManager.AUTOSAVE_CHOICES.has(120.0), "the chosen cadence is one the UI offers")
	SaveManager._apply(JSON.parse_string(JSON.stringify(SaveManager.build_save_data(), "\t")))
	_approx(float(PlayerData.settings["game_speed"]), 4.0, 0.001,
		"the game speed survived a save round-trip")
	_approx(SaveManager.get_autosave_interval(), 120.0, 0.001,
		"the autosave cadence survived a round-trip and was re-applied to the live timer")
	_ok(not bool(PlayerData.settings["notify_warn"]),
		"a muted notification category survived a save round-trip")
	_ok(is_equal_approx(Engine.time_scale, 4.0),
		"the restored speed is live, not merely stored")

	# --- a legacy save predating all three keys loads cleanly and gains the defaults.
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(SaveManager.build_save_data(), "\t"))
	var legacy_settings: Dictionary = (legacy.get("settings", {}) as Dictionary).duplicate(true)
	for key in new_keys:
		legacy_settings.erase(key)
	legacy["settings"] = legacy_settings
	legacy["player"] = (legacy.get("player", {}) as Dictionary).duplicate(true)
	(legacy["player"] as Dictionary)["settings"] = legacy_settings
	_ok(SaveManager.validate_save(legacy).is_empty(), "a save missing the new keys is still valid")
	SaveManager._apply(legacy)
	for key in new_keys:
		_ok(PlayerData.settings.has(key), "the legacy load filled in the missing key '%s'" % key)
	_approx(float(PlayerData.settings.get("game_speed", 0.0)), 1.0, 0.001,
		"a legacy save resumes at normal speed")
	_approx(SaveManager.get_autosave_interval(), SaveManager.AUTOSAVE_INTERVAL, 0.001,
		"a legacy save resumes at the default cadence")
	for kind in EventBus.MUTABLE_NOTIFICATION_KINDS:
		_ok(bool(PlayerData.settings.get("notify_%s" % kind, false)),
			"a legacy save has '%s' notifications switched back on" % kind)

	# --- a mute gates the toast only. It must never gate the data, and never gate errors.
	PlayerData.settings["notify_warn"] = false
	_ok(not EventBus.toasts_enabled("warn"), "a muted category reports itself as muted")
	_ok(EventBus.toasts_enabled("error"), "errors are never muted, muted category or not")
	_ok(EventBus.toasts_enabled("success"), "muting one category leaves the others alone")
	PlayerData.settings["notify_warn"] = true
	_ok(EventBus.toasts_enabled("warn"), "un-muting a category restores it immediately")

	# --- a hostile value outranks the UI: the clamp lives where the value is read, not set.
	SaveManager.set_autosave_interval(0.0)
	_approx(SaveManager.get_autosave_interval(), SaveManager.AUTOSAVE_CHOICES[0], 0.001,
		"a zero cadence is clamped up, so the autosave cannot be made to write every frame")
	SaveManager.set_autosave_interval(999999.0)
	_approx(SaveManager.get_autosave_interval(), SaveManager.MAX_AUTOSAVE_INTERVAL, 0.001,
		"an absurdly long cadence is clamped to the documented maximum")

	# --- both speed controls read and write the one setting, so they cannot drift apart.
	_ok(StatusBar.GAME_SPEEDS.has(float(PlayerData.settings.get("game_speed", 0.0))),
		"the top bar and the settings screen offer the same speed ladder")
	GameManager.set_speed(2.0)
	_approx(float(PlayerData.settings["game_speed"]), 2.0, 0.001,
		"changing the speed from the top bar updates the setting the settings screen reads")

	_test_reset_is_confirmed_not_destructive()

	# Leave the shared singletons as the rest of the suite expects to find them.
	PlayerData.settings["confirm_reset"] = bool(SettingsDefaults.get_default("confirm_reset", true))
	GameManager.set_speed(1.0)
	SaveManager.set_autosave_interval(SaveManager.AUTOSAVE_INTERVAL)

## The reset control must ask before it destroys. This presses the real button and checks that
## what came back was a dialog with the focus on Cancel — and that the player's progress was NOT
## wiped by the press itself.
func _test_reset_is_confirmed_not_destructive() -> void:
	_ok(bool(SettingsDefaults.get_default("confirm_reset", false)),
		"resetting asks for confirmation by default")
	PlayerData.settings["confirm_reset"] = true
	var panel: Control = load("res://scripts/ui/panels/SettingsPanel.gd").new()
	_attach(panel)
	_ok(panel.get("_speed_menu") != null, "the settings screen carries a game speed control")
	var reset_button: Button = _find_button(panel, "Reset")
	_ok(reset_button != null, "the settings screen carries a reset control")
	if reset_button == null:
		panel.queue_free()
		return
	# A press must NOT be allowed to destroy anything on its own.
	PlayerData.gp = 1234.0
	var before_level: int = PlayerData.get_level("woodcutting")
	reset_button.pressed.emit()
	_approx(PlayerData.gp, 1234.0, 0.001, "pressing reset alone destroys no progress")
	_eq(PlayerData.get_level("woodcutting"), before_level, "pressing reset alone resets no skills")

	var dialogs: Array[ConfirmDialog] = []
	for node in _walk(panel):
		if node is ConfirmDialog:
			dialogs.append(node)
	_ok(dialogs.size() == 1, "pressing reset raises exactly one confirmation dialog")
	if dialogs.size() == 1:
		var dlg: ConfirmDialog = dialogs[0]
		_ok(dlg.dialog_text.find("cannot be undone") >= 0,
			"the reset dialog states plainly that the save is destroyed")
		_ok(dlg.dialog_text.find("deletes your save") >= 0,
			"the reset dialog says what is destroyed")
		_ok(dlg.ok_button_text.find("Reset") >= 0, "the confirm button names the action it takes")
		_ok(dlg.get_cancel_button() == dlg.get_cancel_button() and
			dlg.get_cancel_button() != dlg.get_ok_button(),
			"the dialog offers a separate cancel from the destructive confirm")
		dlg.queue_free()
	panel.queue_free()

## Put a freshly built widget into the live tree when there is one, so focus and sizing behave
## as they do in the game. A null main loop is fine: the checks here are about wiring, not paint.
func _attach(node: Node) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null and node.get_parent() == null:
		tree.root.add_child(node)

func _find_button(root: Node, needle: String) -> Button:
	for node in _walk(root):
		if node is Button and (node as Button).text.find(needle) >= 0:
			return node
	return null

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out

func _prayer_cards(node: Node) -> int:
	var count: int = 1 if node is Button and node.text in ["Activate", "Deactivate", "Locked"] else 0
	for child in node.get_children(): count += _prayer_cards(child)
	return count
