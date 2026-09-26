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
const SETTLEMENT := "settlement"
const PROVISIONER := "provisioner"
## The general store is a counter you come back to, the provisioner a catalogue you exhaust, so
## they are two screens: one page cannot hold thirty-one stock lines and a wall of upgrades well.
const STORE := "store"
const EQUIPMENT := "equipment"
const SETTINGS := "settings"
const RECOVERY := "recovery"

## Storage leads: the bank is the screen a player returns to between everything else, so it is the
## first thing under the brand rather than the fourth.
const ORDER: Array[String] = [BANK, OVERVIEW, SKILLS, COMBAT, EQUIPMENT, EXPEDITIONS,
	QUESTS, ACHIEVEMENTS, COLLECTION, SETTLEMENT, PROVISIONER, STORE, ACTION_QUEUE,
	COMBAT_SIMULATOR, SETTINGS]

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
	SETTLEMENT: "Settlement",
	PROVISIONER: "Provisioner",
	STORE: "General Store",
	EQUIPMENT: "Equipment",
	SETTINGS: "Settings",
	RECOVERY: "Recovery",
}

const ICONS: Dictionary = {
	OVERVIEW: "skills",
	SKILLS: "skills",
	COMBAT: "areas",
	EXPEDITIONS: "dungeons",
	BANK: "items",
	ACTION_QUEUE: "status",
	COMBAT_SIMULATOR: "combat",
	QUESTS: "currencies",
	ACHIEVEMENTS: "pets",
	COLLECTION: "items",
	SETTLEMENT: "obstacles",
	PROVISIONER: "currencies",
	STORE: "items",
	EQUIPMENT: "items",
	SETTINGS: "status",
}

static var _shell: Node = null

static func register(shell: Node) -> void:
	_shell = shell

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
