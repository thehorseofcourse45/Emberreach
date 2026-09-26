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
	_test_combat_defeat_and_retreat()
	_test_duplicate_submissions()
	_test_mastery_stall()
	_test_general_store()
	_test_endgame_crafting_chains()
	_test_responsive_layouts(host)
	# After the layout suite, which is what assembles the shell the tests share: a screen test run
	# before it would navigate a shell with no panels built and no sidebar to find a tab in.
	_test_general_store_screen(host)
	await _test_task_feedback_layout(host)
	_test_combat_screen_split(host)
	_test_scroll_position_preserved(host)
	_test_favorites()
	_test_overview_skill_tabs(host)
	_test_content_validation()
	test_identity_theme_builds()
	test_surface_box_falls_back()
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
	var skills_menu: OptionButton = skills_panel.get("_skill_picker")
	_eq(skills_menu.item_count, 2 + DataLoader.get_skill_ids().size(),
		"the Skills picker includes both group headings")
	_ok(skills_menu.get_item_text(0) == "Combat", "the Skills picker starts with Combat")
	var non_combat_index: int = -1
	for i in skills_menu.item_count:
		if skills_menu.get_item_text(i) == "Non-combat":
			non_combat_index = i
	_ok(non_combat_index > 0, "the Skills picker separates non-combat skills")
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
	var first_game: int = (host.get("_nav_buttons") as Dictionary)[Screens.BANK].get_index()
	_ok(combat_heading >= 0 and noncombat_heading > combat_heading and divider > noncombat_heading and first_game > divider,
		"combat and non-combat skills precede a divider and the other screens")
	(skill_buttons["fishing"] as Button).pressed.emit()
	_ok(host.get("_screen") == Screens.SKILLS and str((host.get("_panels") as Dictionary)[Screens.SKILLS].get("_skill_id")) == "fishing",
		"a sidebar skill opens that skill's activities")
	var order: Array[String] = Screens.ORDER
	_ok(order[order.size() - 3] == Screens.ACTION_QUEUE
		and order[order.size() - 2] == Screens.COMBAT_SIMULATOR
		and order[order.size() - 1] == Screens.SETTINGS,
		"Action Queue and Simulator sit immediately above Settings")
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
	Screens.SETTLEMENT: "SettlementPanel",
	Screens.PROVISIONER: "ProvisionerPanel",
	Screens.STORE: "GeneralStorePanel",
	Screens.EQUIPMENT: "EquipmentPanel",
	Screens.SETTINGS: "SettingsPanel",
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
		total_level, Quests.claimed_count(), Achievements.unlocked_count(),
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
	_heading("Achievement rewards are granted exactly once")
	# Level several skills up so at least one achievement condition is satisfiable.
	for skill_id in DataLoader.get_skill_ids():
		PlayerData.set_level(skill_id, 40)
	var unlocked_before: int = Achievements.unlocked_count()
	var first: Array = Achievements.evaluate_all()
	var unlocked_after: int = Achievements.unlocked_count()
	var second: Array = Achievements.evaluate_all()
	_ok(first.size() > 0, "the first evaluation unlocks at least one milestone")
	_eq(second.size(), 0, "the second evaluation unlocks nothing new")
	_eq(unlocked_after, unlocked_before + first.size(), "every milestone unlocked this pass is recorded once")
	# A second full pass over every condition must not change the gold balance.
	var gp_before: float = PlayerData.gp
	Achievements.evaluate_all()
	_approx(PlayerData.gp, gp_before, 0.000001, "re-evaluating grants no further reward")

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

func _test_combat_defeat_and_retreat() -> void:
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

## Task 2 pin: build_theme() must return a Theme with the ember display/text fonts
## registered (missing files fall back to the default font, never crash).
## NOTE: uses _ok/_heading like every neighboring test — TestRunner has no assert_* helpers.
func test_identity_theme_builds() -> void:
	_heading("Identity theme")
	var theme: Theme = UIStyle.build_theme()
	_ok(theme != null, "build_theme must return a Theme")
	_ok(theme != null and theme.has_font("display", ""), "display font registered")
	_ok(theme != null and theme.has_font("text", ""), "text font registered")

## Task 3 pin: surface_box() uses 9-slice art when present, StyleBoxFlat otherwise.
## Missing art must never break the theme — it falls back to today's flat box.
## NOTE: uses _ok/_heading like every neighboring test — TestRunner has no assert_* helpers.
func test_surface_box_falls_back() -> void:
	_heading("Identity surfaces")
	var sb: StyleBox = UIStyle.surface_box("nonexistent_kind_xyz")
	_ok(sb is StyleBoxFlat, "missing art must fall back to StyleBoxFlat")
	if ResourceLoader.exists("res://assets/ui/panel_9slice.png"):
		var art: StyleBox = UIStyle.surface_box("panel")
		_ok(art is StyleBoxTexture, "existing art must build a StyleBoxTexture")

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
	_ok(Quests.count() >= 20, "the task table loaded (%d tasks)" % Quests.count())
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
	_ok(Achievements.count() >= 20, "the milestone table loaded (%d milestones)" % Achievements.count())
	print("  note: %d validation warning(s)" % warnings)

# =========================================================================
#  Content lookups
# =========================================================================

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
