extends VBoxContainer
## QuestsPanel — the Tasks screen: difficulty sub-tabs, the six-hour rotation, and the task list.
##
## Tasks are organised the way players scan them: by difficulty tier (Easy → Nightmare), with a
## separate tab for the rotation whose featured tasks change every six hours. The Show filter
## narrows within the open tab; the state badges on every card still tell the whole story.
##
## Each objective states whether it counts something you HOLD (and can therefore un-satisfy) or
## something you have EVER DONE (a lifetime counter that cannot regress). That distinction is
## shown on every row, because it changes how the player should plan.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

const ROTATING_TAB: String = "rotating"
const CONTRACT_TAB: String = "contracts"
const RESTORATION_TAB: String = "restoration"
## Boards of their own: expeditions and the Astral Trial Chamber. Their tasks are tagged with a
## `tab` in data, so they are listed here instead of under their difficulty.
const EXPEDITIONS_TAB: String = "expeditions"
const ASTRAL_TAB: String = "astral"
const RESTORATION_CAMPAIGNS: Array = [
	{"name": "Hearthfall Fields", "prefix": "hearthfall_restore_", "map": "ferryman_run", "labels": ["FIELDS", "ROAD", "ROOST", "REPAIR", "SECURE"], "scenes": ["Broken fences · raids on the fields · the road lies quiet", "Fences repaired · scouts driven back · the road awaits supplies", "Trade road reopened · farms supplied · the Roost remains a threat", "Fields secure · caravans moving · the Roost cleared", "The fields are safe; permanent defences still need work", "Fields and frontier are secure"]},
	{"name": "Ashen Barrows", "prefix": "barrows_restore_", "map": "nightveil_passage", "labels": ["CAIRNS", "ROAD", "BARROW", "REPAIR", "SECURE"], "scenes": ["Broken cairns · restless dead · the road is silent", "Cairns repaired · skeletons driven back · supplies needed", "Caravans bring timber · the Barrow remains disturbed", "Cairns restored · road open · the Barrow quiet", "The Barrow is quiet; the cairns need lasting repairs", "The cairns and chapel stand secure"]},
	{"name": "Reedwrack Marsh", "prefix": "reedwrack_restore_", "map": "reed_road", "labels": ["PATHS", "SUPPLIES", "WARREN", "REPAIR", "SECURE"], "scenes": ["Paths overgrown · spiders threaten the marsh", "Paths cleared · spiders driven back · supplies needed", "Food reaches the marsh · the Warren remains a threat", "Paths open · supplies delivered · the Warren cleared", "The Warren is cleared; the marsh still needs defences", "The marsh paths and nearby crossing are secure"]},
	{"name": "Ashwood Trails", "prefix": "ashwood_restore_", "map": "charcoal_haul", "labels": ["PATROL", "GATHER", "TRADE", "THREAT", "REPAIR"], "scenes": ["Ashwood Trails: the approaches are threatened", "Ashwood Trails: the approaches are secure", "Ashwood Trails: supplies gathered for restoration", "Ashwood Trails: supply caravans have arrived", "Ashwood Trails: the threat has been defeated", "Ashwood Trails: repairs are complete"]},
	{"name": "Dune Crossing", "prefix": "dunecross_restore_", "map": "dune_crossing", "labels": ["PATROL", "GATHER", "TRADE", "THREAT", "REPAIR"], "scenes": ["Dune Crossing: the approaches are threatened", "Dune Crossing: the approaches are secure", "Dune Crossing: supplies gathered for restoration", "Dune Crossing: supply caravans have arrived", "Dune Crossing: the threat has been defeated", "Dune Crossing: repairs are complete"]},
	{"name": "Ashen Bastion", "prefix": "ashenkeep_restore_", "map": "ember_throne_route", "labels": ["PATROL", "GATHER", "TRADE", "THREAT", "REPAIR"], "scenes": ["Ashen Bastion: the approaches are threatened", "Ashen Bastion: the approaches are secure", "Ashen Bastion: supplies gathered for restoration", "Ashen Bastion: supply caravans have arrived", "Ashen Bastion: the threat has been defeated", "Ashen Bastion: repairs are complete"]},
	{"name": "Sunderhold Keep", "prefix": "sunderhold_restore_", "map": "kings_road", "labels": ["PATROL", "GATHER", "TRADE", "THREAT", "REPAIR"], "scenes": ["Sunderhold Keep: the approaches are threatened", "Sunderhold Keep: the approaches are secure", "Sunderhold Keep: supplies gathered for restoration", "Sunderhold Keep: supply caravans have arrived", "Sunderhold Keep: the threat has been defeated", "Sunderhold Keep: repairs are complete"]},
	{"name": "Frostbound Reach", "prefix": "frostbound_restore_", "map": "lantern_pass", "labels": ["PATROL", "GATHER", "TRADE", "THREAT", "REPAIR"], "scenes": ["Frostbound Reach: the approaches are threatened", "Frostbound Reach: the approaches are secure", "Frostbound Reach: supplies gathered for restoration", "Frostbound Reach: supply caravans have arrived", "Frostbound Reach: the threat has been defeated", "Frostbound Reach: repairs are complete"]},
	{"name": "Tidebreak Cliffs", "prefix": "tidebreak_restore_", "map": "lighthouse_route", "labels": ["PATROL", "GATHER", "TRADE", "THREAT", "REPAIR"], "scenes": ["Tidebreak Cliffs: the approaches are threatened", "Tidebreak Cliffs: the approaches are secure", "Tidebreak Cliffs: supplies gathered for restoration", "Tidebreak Cliffs: supply caravans have arrived", "Tidebreak Cliffs: the threat has been defeated", "Tidebreak Cliffs: repairs are complete"]},
	{"name": "Greyharrow Quarry", "prefix": "greyharrow_restore_", "map": "quarry_road", "labels": ["PATROL", "GATHER", "TRADE", "THREAT", "REPAIR"], "scenes": ["Greyharrow Quarry: the approaches are threatened", "Greyharrow Quarry: the approaches are secure", "Greyharrow Quarry: supplies gathered for restoration", "Greyharrow Quarry: supply caravans have arrived", "Greyharrow Quarry: the threat has been defeated", "Greyharrow Quarry: repairs are complete"]},
	{"name": "Cinderkin Forge", "prefix": "cinderforge_restore_", "map": "smithy_line", "labels": ["PATROL", "GATHER", "TRADE", "THREAT", "REPAIR"], "scenes": ["Cinderkin Forge: the approaches are threatened", "Cinderkin Forge: the approaches are secure", "Cinderkin Forge: supplies gathered for restoration", "Cinderkin Forge: supply caravans have arrived", "Cinderkin Forge: the threat has been defeated", "Cinderkin Forge: repairs are complete"]},
	{"name": "Rookwood Crossing", "prefix": "rookwood_restore_", "map": "tollgate_road", "labels": ["PATROL", "GATHER", "TRADE", "THREAT", "REPAIR"], "scenes": ["Rookwood Crossing: the approaches are threatened", "Rookwood Crossing: the approaches are secure", "Rookwood Crossing: supplies gathered for restoration", "Rookwood Crossing: supply caravans have arrived", "Rookwood Crossing: the threat has been defeated", "Rookwood Crossing: repairs are complete"]},
]
## Tier colours follow the house semantics: green/teal/blue read as progress, purple as rare
## mastery, red as danger — a readable ramp from Easy to Nightmare.
const DIFFICULTY_COLORS: Dictionary = {
	"easy": UITokens.GREEN,
	"normal": UITokens.TEAL,
	"hard": UITokens.BLUE,
	"expert": UITokens.PURPLE,
	"nightmare": UITokens.RED,
}

var _list: VBoxContainer
var _filter: OptionButton
var _filter_keys: Array[String] = ["available", "in_progress", "ready", "completed", "locked", "all"]
var _tabs_root: HFlowContainer
var _tab_buttons: Array[Button] = []
var _tab_ids: Array[String] = []
var _active_tab: String = ""
var _rotation_label: Label = null
var _rotation_timer: Timer
var _last_window: int = -1
var _built: bool = false
var _restoration_index: int = 0
var _restoration_choice: OptionButton
const RESTORATION_LABELS: Dictionary = {
	"hearthfall_restore_": ["FIELDS", "ROAD", "ROOST", "HARVEST", "CELLAR"],
	"barrows_restore_": ["CAIRNS", "SUPPLIES", "BARROW", "NAMES", "CHAPEL"],
	"reedwrack_restore_": ["PATHS", "FOOD", "WARREN", "CROSSING", "VIADUCT"],
	"ashwood_restore_": ["TRACKS", "FIREBREAK", "CURE", "NEST", "WATCH"],
	"dunecross_restore_": ["SURVEY", "WATER", "CARGO", "GLASS", "BEACON"],
	"ashenkeep_restore_": ["RAMPARTS", "FURNACE", "ORDERS", "KEEP", "WATCH"],
	"sunderhold_restore_": ["ARMOURY", "BALLISTA", "SEAL", "CRYPT", "GARRISON"],
	"frostbound_restore_": ["TRACKS", "CAMP", "CROSSING", "DEN", "PASS"],
	"tidebreak_restore_": ["TIDES", "LEDGE", "GRAVES", "ORACLE", "BEACON"],
	"greyharrow_restore_": ["LEDGER", "SEAMS", "STALKERS", "DEPTHS", "LIFT"],
	"cinderforge_restore_": ["SCOUTS", "COPPER", "FURNACE", "FORGE", "TOOLS"],
	"rookwood_restore_": ["COURIER", "TOLLS", "WATCH", "TOWER", "ROAD"],
}

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Frontier tasks", UITokens.FONT_DISPLAY))
	add_child(UIStyle.label(
		"Objectives are measured from your whole run: things you have already done count, so accepting a task never invalidates progress. Rewards are granted once, when you claim them.",
		true, UITokens.FONT_SMALL))
	# Difficulty sub-tabs (plus the rotating window) are the primary way tasks are scanned.
	_tab_ids = Quests.DIFFICULTIES.duplicate()
	_tab_ids.append(ROTATING_TAB)
	_tab_ids.append(EXPEDITIONS_TAB)
	_tab_ids.append(ASTRAL_TAB)
	_tab_ids.append(CONTRACT_TAB)
	_tab_ids.append(RESTORATION_TAB)
	var labels: Array[String] = []
	for tab_id in _tab_ids:
		labels.append(_tab_label(tab_id))
	var strip: Dictionary = Widgets.tab_flow(labels, func(index): _select_tab(_tab_ids[index]))
	_tabs_root = strip["root"] as HFlowContainer
	_tab_buttons.assign(strip["buttons"])
	add_child(_tabs_root)
	_active_tab = _tab_ids[0]
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", UITokens.SP_4)
	bar.add_child(UIStyle.label("Show", true, UITokens.FONT_SMALL))
	_filter = Widgets.option_menu(["Available", "In progress", "Ready to claim", "Completed", "Locked", "All"],
		func(_i): _rebuild(), 0)
	bar.add_child(_filter)
	add_child(bar)
	_list = UIStyle.vbox(UITokens.SP_4)
	add_child(_list)
	# The rotation flips on wall-clock boundaries; a slow timer keeps the open tab honest between
	# them (and rebuilds the moment a new window begins) without touching a frame budget.
	_rotation_timer = Timer.new()
	_rotation_timer.wait_time = 30.0
	_rotation_timer.autostart = true
	_rotation_timer.timeout.connect(_on_rotation_tick)
	add_child(_rotation_timer)
	EventBus.quest_objective_progress.connect(func(_q, _i, _c, _r): Widgets.rebuild_once_per_frame(_rebuild))
	EventBus.quest_reward_claimed.connect(func(_q): _rebuild())
	EventBus.bank_changed.connect(func(): Widgets.rebuild_once_per_frame(_rebuild))
	EventBus.state_refreshed.connect(_rebuild)
	ContractManager.board_changed.connect(_rebuild)
	ContractManager.contract_progress_changed.connect(func(_slot): _rebuild())
	FactionManager.faction_changed.connect(func(_id): _rebuild())
	FactionManager.reputation_changed.connect(func(_id, _reputation): _rebuild())
	_update_tab_buttons()
	_rebuild()

func focus_route(route: Dictionary) -> void:
	var quest_id: String = str(route.get("quest_id", ""))
	if quest_id != "":
		context_changed.emit({"kind": "goal", "goal": {"kind": "quest", "id": quest_id}})

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Tasks",
		"body": "Select a task to see its objectives, prerequisites, reward and the route to each objective."}

func _tab_label(tab_id: String) -> String:
	match tab_id:
		ROTATING_TAB: return "Rotating"
		EXPEDITIONS_TAB: return "Expeditions"
		ASTRAL_TAB: return "Astral trials"
		CONTRACT_TAB: return "Contracts & factions"
		RESTORATION_TAB: return "Restoration"
	return tab_id.capitalize()

func _select_tab(tab_id: String) -> void:
	_active_tab = tab_id if _tab_ids.has(tab_id) else _tab_ids[0]
	(_filter.get_parent() as Control).visible = _active_tab != RESTORATION_TAB
	_update_tab_buttons()
	_rebuild()

func _update_tab_buttons() -> void:
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].button_pressed = _tab_ids[i] == _active_tab

func _rebuild() -> void:
	if not _built or Widgets.defer_offscreen_rebuild(self, _rebuild):
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rotation_label = null
	var filter: String = _filter_keys[clampi(_filter.selected, 0, _filter_keys.size() - 1)]
	_last_window = Quests.rotation_window()
	if _active_tab == CONTRACT_TAB:
		_rebuild_contracts()
	elif _active_tab == RESTORATION_TAB:
		_rebuild_restoration()
	elif _active_tab == ROTATING_TAB:
		_rebuild_rotating(filter)
	elif _active_tab in [EXPEDITIONS_TAB, ASTRAL_TAB]:
		_rebuild_board(_active_tab, filter)
	else:
		_rebuild_difficulty(filter)

func _rebuild_restoration() -> void:
	_restoration_choice = Widgets.option_menu(RESTORATION_CAMPAIGNS.map(func(c): return str(c.name)),
		func(index):
			_restoration_index = index
			_rebuild(), _restoration_index)
	_list.add_child(_restoration_choice)
	var campaign: Dictionary = RESTORATION_CAMPAIGNS[_restoration_index]
	var stages: Array[String] = []
	for n in range(1, 6): stages.append(str(campaign.prefix) + str(n))
	var completed: int = 0
	var states: Array[String] = []
	for id in stages:
		if Quests.is_claimed(id): completed += 1
		states.append(_restoration_stage_state(id))
	var section := UIStyle.section(str(campaign.name), "A regional restoration campaign · %d / 5 stages restored" % completed)
	var landscape := preload("res://scripts/ui/RestorationLandscape.gd").new()
	landscape.name = "RestorationLandscape"
	landscape.stage = completed
	landscape.states = states
	landscape.map = load("res://assets/caravans/maps/%s.png" % campaign.map)
	landscape.labels.assign(RESTORATION_LABELS.get(str(campaign.prefix), campaign.labels))
	section.add_child(landscape)
	var scene_text: String = "Restoration work has not started." if completed == 0 else "Latest restored stage: " + str(Quests.get_quest(stages[completed - 1]).get("name", ""))
	var scene_label := UIStyle.label(scene_text, true, UITokens.FONT_SMALL)
	scene_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(scene_label)
	section.add_child(Widgets.progress_bar(float(completed), 5.0, UITokens.GREEN, "%d / 5" % completed, 16, "Restoration progress"))
	_list.add_child(section)
	var stage_map := UIStyle.section("Campaign progress map", "Completed, available, and locked stages are shown together. Claim a completed task to unlock its next stage.")
	_list.add_child(stage_map)
	for i in range(stages.size()):
		stage_map.add_child(_restoration_stage_row(stages[i], i + 1, states[i]))
	_list.add_child(UIStyle.section("Stage objectives", "Accept tasks, follow their objectives, and claim rewards below."))
	for id in stages:
		var card := _matching_card(id, "all")
		if card != null: _list.add_child(card)

func _restoration_stage_state(id: String) -> String:
	if Quests.is_claimed(id): return "completed"
	if not Quests.prerequisites_met(id): return "locked"
	if Quests.is_complete(id): return "ready"
	return "in_progress" if Quests.is_accepted(id) else "available"

func _restoration_stage_row(id: String, number: int, state: String) -> Control:
	var quest: Dictionary = Quests.get_quest(id)
	var card := UIStyle.card(state == "ready")
	card.name = "RestorationStage%d" % number
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITokens.SP_3)
	card.add_child(row)
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(48, 48)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = _restoration_stage_art(id, quest)
	row.add_child(art)
	var details := UIStyle.vbox(UITokens.SP_1)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(details)
	var title := UIStyle.label("%d. %s" % [number, str(quest.get("legacy_name" if Quests.uses_legacy_campaign_objectives(id) else "name", id))], false, UITokens.FONT_SMALL)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(title)
	var labels: Dictionary = {"completed": "Completed", "ready": "Ready to claim", "in_progress": "In progress", "available": "Available", "locked": "Locked"}
	var color: Color = UITokens.GREEN if state == "completed" else (UITokens.GOLD_BRIGHT if state == "ready" else (UITokens.BLUE if state in ["available", "in_progress"] else UITokens.TEXT_MUTED))
	details.add_child(UIStyle.colored_label(str(labels.get(state, state)), color, UITokens.FONT_SMALL))
	var reward := UIStyle.label("Reward: " + Quests.describe_reward(quest.get("reward", {})), true, UITokens.FONT_MICRO)
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(reward)
	if Quests.uses_legacy_campaign_objectives(id):
		details.add_child(UIStyle.label("Existing objectives preserved", true, UITokens.FONT_MICRO))
	if state == "locked":
		var reason := UIStyle.label(Quests.lock_reason(id), true, UITokens.FONT_MICRO)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(reason)
	var view := UIStyle.mini_button("Details")
	view.pressed.connect(func(): context_changed.emit({"kind": "goal", "goal": {"kind": "quest", "id": id}}))
	details.add_child(view)
	return card

func _restoration_stage_art(id: String, quest: Dictionary) -> Texture2D:
	for obj in Quests.objectives_for(id):
		if obj.has("monster_id"): return AssetRegistry.monster_sprite(str(obj.monster_id))
		if obj.has("item_id"): return AssetRegistry.item_icon(str(obj.item_id))
		if obj.has("skill_id"): return AssetRegistry.skill_icon(str(obj.skill_id))
		var route: Dictionary = obj.get("route", {})
		if route.has("dungeon_id"): return AssetRegistry.icon("dungeons", str(route.dungeon_id))
	return AssetRegistry.icon("areas", str(quest.get("region", "")))

func _rebuild_difficulty(filter: String) -> void:
	var shown: int = 0
	for quest_id in Quests.all_quest_ids():
		# tab_of reports the rotating window and the tagged boards as their own tabs, so a task
		# never appears twice.
		if Quests.tab_of(quest_id) != _active_tab:
			continue
		var card: Control = _matching_card(quest_id, filter)
		if card == null:
			continue
		shown += 1
		_list.add_child(card)
	if shown == 0:
		_list.add_child(Widgets.empty_state("Nothing in this tab",
			"No tasks match the current filter here. Switch the filter, or make progress on an active task.",
			"Show all", func():
				_filter.selected = 5
				_rebuild()))

## The expedition and Astral Trial Chamber boards: their own tabs, still narrowed by the Show
## filter. Both count lifetime state, so a run made before opening the tab still counts.
func _rebuild_board(board: String, filter: String) -> void:
	_list.add_child(UIStyle.section(_board_title(board), _board_hint(board)))
	var shown: int = 0
	for quest_id in Quests.all_quest_ids():
		if Quests.tab_of(quest_id) != board:
			continue
		var card: Control = _matching_card(quest_id, filter)
		if card == null:
			continue
		shown += 1
		_list.add_child(card)
	if shown == 0:
		_list.add_child(Widgets.empty_state("Nothing in this tab",
			"No tasks match the current filter here. Switch the filter, or make progress on an active task.",
			"Show all", func():
				_filter.selected = 5
				_rebuild()))

func _board_title(board: String) -> String:
	return "Astral Trial Chamber" if board == ASTRAL_TAB else "Expeditions"

func _board_hint(board: String) -> String:
	if board == ASTRAL_TAB:
		return "%d of %d trials cleared · the chamber opens once The Final Horizon is beaten" % [
			RaidManager.astral_completions.size(), RaidManager.ASTRAL_TRIALS.size()]
	return "Dungeon runs and their bosses · objectives count every clear you have ever made"

func _rebuild_contracts() -> void:
	_list.add_child(UIStyle.section("Faction allegiances", "Pledge allegiance to one faction at a time; reputation is retained when switching"))
	for faction_id in FactionManager.all_faction_ids():
		var id: String = str(faction_id)
		var faction: Dictionary = FactionManager.get_faction(id)
		var current: bool = FactionManager.selected_faction == id
		var card := UIStyle.card(current)
		var content := UIStyle.vbox(UITokens.SP_2)
		card.add_child(content)
		content.add_child(UIStyle.title(str(faction.get("name", id)), UITokens.FONT_SUBHEAD))
		content.add_child(UIStyle.label(str(faction.get("description", "")), true, UITokens.FONT_SMALL))
		content.add_child(UIStyle.label("%s · %d reputation" % [FactionManager.get_rank_name(id), FactionManager.get_reputation(id)], true, UITokens.FONT_SMALL))
		var next: Dictionary = FactionManager.get_next_rank(id)
		if not next.is_empty():
			content.add_child(UIStyle.label("Next: %s at %d reputation" % [str(next.get("name", "")), int(next.get("reputation", 0))], true, UITokens.FONT_MICRO))
		var join := UIStyle.button("Pledged" if current else "Pledge allegiance")
		join.disabled = current
		join.pressed.connect(func(): FactionManager.select_faction(id))
		content.add_child(join)
		for vendor_offer in FactionManager.vendor_offers(id):
			var reward_id: String = str(vendor_offer.get("id", ""))
			var owned: bool = FactionManager.vendor_purchased(id, reward_id)
			var blocker: String = FactionManager.vendor_blocker(id, reward_id)
			content.add_child(UIStyle.label(str(vendor_offer.get("name", reward_id)) + " — " + str(vendor_offer.get("description", "")), true, UITokens.FONT_MICRO))
			var buy := UIStyle.button("Purchased" if owned else "Buy for %s GP" % UIStyle.fmt(float(vendor_offer.get("cost_gp", 0))))
			buy.disabled = blocker != ""
			buy.tooltip_text = blocker if blocker != "" else "Buy this permanent faction perk"
			buy.pressed.connect(func(): FactionManager.purchase_vendor_reward(id, reward_id))
			content.add_child(buy)
		_list.add_child(card)
	_list.add_child(UIStyle.section("Contract board", "Three fresh-work objectives; complete them for GP, XP and faction reputation"))
	for index in range(ContractManager.get_offers().size()):
		var offer: Dictionary = ContractManager.get_offer(index)
		var progress: Dictionary = ContractManager.progress(index)
		var ready: bool = bool(progress.get("satisfied", false))
		var card := UIStyle.card(ready)
		var col := UIStyle.vbox(UITokens.SP_3)
		card.add_child(col)
		col.add_child(UIStyle.title("%s · %s" % [str(offer.get("tier_name", "Bronze")), str(offer.get("name", "Contract"))], UITokens.FONT_SUBHEAD))
		col.add_child(UIStyle.label(str(offer.get("description", "")), true, UITokens.FONT_SMALL))
		col.add_child(UIStyle.label("%s: %d / %d" % [str(offer.get("objective", {}).get("label", "Work")), int(progress.current), int(progress.required)], true, UITokens.FONT_SMALL))
		col.add_child(Widgets.progress_bar(float(progress.current), maxf(1.0, float(progress.required)), UITokens.TEAL, "%d / %d" % [int(progress.current), int(progress.required)]))
		col.add_child(UIStyle.label("Reward: " + ContractManager.describe_reward(index), true, UITokens.FONT_MICRO))
		var claim := UIStyle.primary_button("Claim reward" if ready else "In progress")
		claim.disabled = not ready
		var slot: int = index
		claim.pressed.connect(func(): ContractManager.claim_contract(slot))
		col.add_child(claim)
		var route: Dictionary = offer.get("objective", {}).get("route", {})
		if not route.is_empty():
			var go := UIStyle.button("Go to activity")
			go.pressed.connect(func(): navigated.emit(route))
			col.add_child(go)
		_list.add_child(card)
	var refresh := UIStyle.button("Refresh contracts · %d GP" % ContractManager.get_refresh_cost())
	refresh.disabled = PlayerData.gp < float(ContractManager.get_refresh_cost())
	refresh.tooltip_text = "Replace all three contracts; unfinished progress on the current offers is lost."
	refresh.pressed.connect(func(): ContractManager.refresh_board())
	_list.add_child(refresh)

func _rebuild_rotating(filter: String) -> void:
	_rotation_label = UIStyle.colored_label(_rotation_headline(), UITokens.GOLD_BRIGHT, UITokens.FONT_SMALL)
	_list.add_child(_rotation_label)
	_list.add_child(UIStyle.label(
		"Featured from the rotation pool. A claimed task reopens next rotation and needs fresh progress. Daily streak: %d day(s), rewards x%.1f. Claim one each day to keep it." % [Quests.current_streak(), Quests.streak_multiplier()],
		true, UITokens.FONT_MICRO))
	var shown: int = 0
	for quest_id in Quests.featured_rotating_ids():
		var card: Control = _matching_card(quest_id, filter, true)
		if card == null:
			continue
		shown += 1
		_list.add_child(card)
	if shown == 0:
		_list.add_child(Widgets.empty_state("Nothing to show in this rotation",
			"No featured tasks match the current filter. Switch the filter, or check back after the next rotation.",
			"Show all", func():
				_filter.selected = 5
				_rebuild()))

func _rotation_headline() -> String:
	return "Fresh selection in %s — the rotation changes every six hours." % UIStyle.fmt_duration(float(Quests.seconds_until_rotation()))

func _on_rotation_tick() -> void:
	if _active_tab != ROTATING_TAB:
		return
	if Quests.rotation_window() != _last_window:
		_rebuild()
	elif _rotation_label != null and is_instance_valid(_rotation_label):
		_rotation_label.text = _rotation_headline()

## Builds the card for a task only when it matches the state filter; null otherwise.
func _matching_card(quest_id: String, filter: String, show_difficulty := false) -> Control:
	var q: Dictionary = Quests.get_quest(quest_id)
	var p: Dictionary = Quests.progress(quest_id)
	var claimed: bool = Quests.is_claimed(quest_id)
	var complete: bool = p["all_satisfied"] and not claimed
	var locked: bool = not Quests.prerequisites_met(quest_id)
	var accepted: bool = Quests.is_accepted(quest_id)
	var state: String = "completed" if claimed else ("locked" if locked else ("ready" if complete else ("in_progress" if accepted else "available")))
	if filter != "all" and state != filter:
		return null
	return _quest_card(quest_id, q, p, state, show_difficulty)

func _quest_card(quest_id: String, q: Dictionary, p: Dictionary, state: String, show_difficulty := false) -> Control:
	var accent: bool = state == "ready"
	var card := UIStyle.card(accent)
	var col := UIStyle.vbox(UITokens.SP_3)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITokens.SP_4)
	head.add_child(UIStyle.icon_texture("currencies", "gp"))
	var title := UIStyle.title(str(q.get("legacy_name" if Quests.uses_legacy_campaign_objectives(quest_id) else "name", quest_id)), UITokens.FONT_SUBHEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(title)
	if show_difficulty:
		var difficulty: String = str(q.get("difficulty", "normal"))
		head.add_child(Widgets.badge(difficulty.capitalize(), DIFFICULTY_COLORS.get(difficulty, UITokens.TEXT_MUTED),
			"Rotation difficulty"))
	match state:
		"completed":
			head.add_child(Widgets.badge("Completed", UITokens.GREEN))
		"ready":
			head.add_child(Widgets.badge("Ready to claim", UITokens.GOLD_BRIGHT, "Every objective is satisfied"))
		"locked":
			head.add_child(Widgets.badge("Locked", UITokens.TEXT_MUTED))
		"in_progress":
			head.add_child(Widgets.badge("In progress", UITokens.BLUE))
		_:
			if not show_difficulty:
				head.add_child(Widgets.badge("Chapter %d" % int(q.get("chapter", 1)), UITokens.BLUE))
	head.add_child(Widgets.badge("Objectives %d/%d" % [int(p["satisfied"]), int(p["total"])], UITokens.TEAL,
		"Objectives satisfied"))
	col.add_child(head)
	if Quests.uses_legacy_campaign_objectives(quest_id):
		col.add_child(UIStyle.label("Your existing objectives are preserved for this stage.", true, UITokens.FONT_SMALL))

	col.add_child(Widgets.progress_bar(float(p["satisfied"]), maxf(1.0, float(p["total"])),
		UITokens.GOLD_BRIGHT if state == "ready" else UITokens.TEAL,
		"%d / %d" % [int(p["satisfied"]), int(p["total"])], 12, "Objective progress"))

	var description: String = str(q.get("legacy_description" if Quests.uses_legacy_campaign_objectives(quest_id) else "description", ""))
	if description != "":
		var d := UIStyle.label(description, true, UITokens.FONT_SMALL)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(d)
	if state == "locked":
		var reason := UIStyle.colored_label("Locked — %s" % Quests.lock_reason(quest_id), UITokens.AMBER, UITokens.FONT_SMALL)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(reason)

	for obj in p["objectives"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITokens.SP_4)
		var mark := Label.new()
		mark.text = "✓" if bool(obj["satisfied"]) else "✗"
		mark.add_theme_font_size_override("font_size", UITokens.FONT_SMALL)
		mark.add_theme_color_override("font_color", UITokens.GREEN if bool(obj["satisfied"]) else UITokens.AMBER)
		mark.custom_minimum_size = Vector2(14, 0)
		row.add_child(mark)
		var text := UIStyle.vbox(UITokens.SP_1)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Wrapped unconditionally: with a few hundred tasks, one long label must never set the
		# whole panel's minimum width at the narrowest supported window.
		var obj_label := UIStyle.label(str(obj["label"]), false, UITokens.FONT_SMALL)
		obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(obj_label)
		var detail: String = "%s / %s  ·  %s" % [UIStyle.fmt(float(obj["current"])), UIStyle.fmt(float(obj["required"])), str(obj["hint"])]
		var detail_label := UIStyle.label(detail, true, UITokens.FONT_MICRO)
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(detail_label)
		row.add_child(text)
		row.add_child(Widgets.badge("Lifetime" if bool(obj["lifetime"]) else "Held now",
			UITokens.PURPLE if bool(obj["lifetime"]) else UITokens.BLUE,
			"Lifetime counters never regress; held items can be spent." if bool(obj["lifetime"]) else "This objective checks what you are holding right now."))
		var route: Dictionary = obj.get("route", {})
		if not route.is_empty() and not bool(obj["satisfied"]):
			var go := UIStyle.mini_button("Go")
			var r: Dictionary = route
			go.pressed.connect(func(): navigated.emit(r))
			row.add_child(go)
		col.add_child(row)

	var reward_items: Dictionary = q.get("reward", {}).get("items", {})
	if not reward_items.is_empty():
		col.add_child(Widgets.item_rewards(reward_items))
	col.add_child(Widgets.key_value("Reward", Quests.describe_reward(q.get("reward", {})), UITokens.GOLD_BRIGHT))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", UITokens.SP_3)
	if state == "ready":
		var claim := UIStyle.primary_button("Claim reward")
		claim.pressed.connect(func():
			Quests.claim(quest_id)
			_rebuild())
		buttons.add_child(claim)
	elif state == "available":
		var accept := UIStyle.button("Accept")
		accept.pressed.connect(func():
			if Quests.accept(quest_id):
				_filter.select(2 if Quests.is_complete(quest_id) else 1)
				context_changed.emit({"kind": "goal", "goal": {"kind": "quest", "id": quest_id}})
			_rebuild())
		buttons.add_child(accept)
	var explain := UIStyle.mini_button("Track as goal")
	explain.pressed.connect(func():
		Goals.pin("quest", quest_id)
		context_changed.emit({"kind": "goal", "goal": {"kind": "quest", "id": quest_id}}))
	buttons.add_child(explain)
	col.add_child(buttons)
	return card
