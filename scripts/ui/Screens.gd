class_name Screens
extends RefCounted
## Screens — the navigation route table.
##
## Every screen answers "what do I need next?" with a concrete route to the activity that
## resolves it. Those routes are plain dictionaries ({screen, skill_id, action_id, ...}) built by
## Goals / Quests / Widgets and resolved here. Keeping navigation in one place means a lesson
## panel, a quest objective and a dependency hint all send the player to the same place.

const OVERVIEW := "overview"
const SKILLS := "skills"
const COMBAT := "combat"
const EXPEDITIONS := "expeditions"
const BANK := "bank"
const ACTION_QUEUE := "action_queue"
const COMBAT_SIMULATOR := "combat_simulator"
const QUESTS := "quests"
const ACHIEVEMENTS := "achievements"
const COLLECTION := "collection"
## The lifetime record. Milestones tell you what a condition unlocks; this tells you what you have
## already done, so it sits beside the collection log rather than among the goal screens.
const STATS := "stats"
const SETTLEMENT := "settlement"
const PROVISIONER := "provisioner"
## The general store is a counter you come back to, the provisioner a catalogue you exhaust, so
## they are two screens: one page cannot hold thirty-one stock lines and a wall of upgrades well.
const STORE := "store"
const EQUIPMENT := "equipment"
const SETTINGS := "settings"
const RECOVERY := "recovery"
## Prayer and raid both had complete backends with no entry point; they sit with the combat
## screens because both are combat-time systems.
const PRAYERS := "prayers"
const RAIDS := "raids"
## The Farm screen is Husbandry made reachable: plots that grow in real time, planted and
## harvested by hand. It sits with the other system screens above the task lists.
const FARM := "farm"
## Ascendancy: the reset layer. It is the only screen that can delete a run, so it sits with
## Settings and Recovery at the bottom rather than up in the progress screens.
const PRESTIGE := "prestige"

## Storage leads: the bank is the screen a player returns to between everything else, so it is the
## first thing under the brand rather than the fourth.
const ORDER: Array[String] = [BANK, OVERVIEW, SKILLS, COMBAT, PRAYERS, EQUIPMENT, EXPEDITIONS, RAIDS, FARM,
	QUESTS, ACHIEVEMENTS, COLLECTION, STATS, SETTLEMENT, PROVISIONER, STORE, ACTION_QUEUE,
	COMBAT_SIMULATOR, PRESTIGE, SETTINGS]

const LABELS: Dictionary = {
	OVERVIEW: "Overview",
	SKILLS: "Skills",
	COMBAT: "Combat",
	EXPEDITIONS: "Expeditions",
	BANK: "Storage",
	ACTION_QUEUE: "Action Queue",
	COMBAT_SIMULATOR: "Simulator",
	QUESTS: "Tasks",
	ACHIEVEMENTS: "Milestones",
	COLLECTION: "Collection",
	STATS: "Stats",
	SETTLEMENT: "Settlement",
	PROVISIONER: "Provisioner",
	STORE: "General Store",
	EQUIPMENT: "Equipment",
	SETTINGS: "Settings",
	RECOVERY: "Recovery",
	PRAYERS: "Prayers",
	RAIDS: "Raid",
	FARM: "Farm",
	PRESTIGE: "Ascendancy",
}

const ICONS: Dictionary = {
	OVERVIEW: "skills",
	SKILLS: "skills",
	COMBAT: "areas",
	EXPEDITIONS: "dungeons",
	BANK: "items",
	ACTION_QUEUE: "navigation",
	COMBAT_SIMULATOR: "navigation",
	QUESTS: "currencies",
	ACHIEVEMENTS: "pets",
	COLLECTION: "items",
	STATS: "items",
	SETTLEMENT: "obstacles",
	PROVISIONER: "currencies",
	STORE: "items",
	EQUIPMENT: "items",
	SETTINGS: "navigation",
	PRAYERS: "navigation",
	RAIDS: "navigation",
	FARM: "skills",
	PRESTIGE: "navigation",
}

static var _shell: Node = null

static func register(shell_node: Node) -> void:
	_shell = shell_node

static func shell() -> Node:
	return _shell

## Navigate to a screen, optionally focused on a specific skill/action/item/region/quest.
static func go(route: Dictionary) -> void:
	if route.is_empty():
		return
	if _shell == null or not is_instance_valid(_shell):
		push_warning("Screens: no shell registered for route %s" % str(route))
		return
	_shell.call("navigate", route)

static func show(screen: String) -> void:
	go({"screen": screen})

static func label_for(screen: String) -> String:
	return str(LABELS.get(screen, screen.capitalize()))
