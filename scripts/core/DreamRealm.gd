extends RefCounted
## Dream Realm journeys are manual choices; pending rewards are paid only on a successful return.

const FRAGMENT := "lucid_fragment"
const REGIONS := [
	{"id":"lantern_garden", "name":"Lantern Garden", "level":60, "cost":100, "bonus":2, "item":"lantern_dream_amulet", "price":8, "previous":"", "description":"A floating garden where lost memories bloom beneath moonlit lanterns.", "nodes":[
		{"text":"A lantern flickers beside a path of sleeping flowers.", "safe":"Shield the lantern", "bold":"Follow the wandering light"},
		{"text":"A gardener offers a seed that hums with forgotten memories.", "safe":"Help tend the beds", "bold":"Plant the restless seed"},
		{"text":"A bridge of petals leads back toward waking.", "safe":"Wait for the petals to settle", "bold":"Leap across the drifting bridge"}]},
	{"id":"mirror_library", "name":"Mirror Library", "level":75, "cost":140, "bonus":3, "item":"mirror_dream_mantle", "price":12, "previous":"lantern_garden", "description":"Infinite shelves reflect stories that have not yet been lived.", "nodes":[
		{"text":"Two reflections reach for the same unread book.", "safe":"Read the familiar reflection", "bold":"Follow the stranger between shelves"},
		{"text":"Pages turn without wind around a sealed atlas.", "safe":"Copy the margin notes", "bold":"Open the sealed atlas"},
		{"text":"The library rearranges its doors as you leave.", "safe":"Trace your steps", "bold":"Step through the newest door"}]},
	{"id":"sunken_reverie", "name":"Sunken Reverie", "level":90, "cost":180, "bonus":4, "item":"reverie_mirror_shield", "price":16, "previous":"mirror_library", "description":"A drowned cathedral rings beneath a quiet sea of stars.", "nodes":[
		{"text":"A bell rings far below the surface.", "safe":"Listen from the shore", "bold":"Dive toward the bell"},
		{"text":"A choir offers a silver mirror filled with tides.", "safe":"Sing the gentle refrain", "bold":"Look into the deepest tide"},
		{"text":"The flooded nave begins to rise around you.", "safe":"Climb the steady steps", "bold":"Ride the rising current"}]},
	{"id":"nightmare_labyrinth", "name":"Nightmare Labyrinth", "level":105, "cost":220, "bonus":5, "item":"nightmare_dream_crown", "price":20, "previous":"sunken_reverie", "description":"A shifting maze gives form to fears and forgotten promises.", "nodes":[
		{"text":"A shadow repeats your last words from the maze entrance.", "safe":"Answer calmly", "bold":"Challenge the shadow"},
		{"text":"The walls reveal a shortcut through a sleeping nightmare.", "safe":"Walk the outer path", "bold":"Cross the nightmare's chamber"},
		{"text":"A crown rests at the center of a circle of thorns.", "safe":"Untangle the thorns", "bold":"Seize the crown"}]},
	{"id":"dawn_throne", "name":"Throne of Dawn", "level":115, "cost":260, "bonus":6, "item":"dawn_dream_ring", "price":24, "previous":"nightmare_labyrinth", "description":"At the edge of waking, a radiant throne holds the first light of every dream.", "nodes":[
		{"text":"A herald asks what you would carry into the dawn.", "safe":"Offer a cherished memory", "bold":"Ask for the herald's secret"},
		{"text":"The throne reflects every path you have taken.", "safe":"Honor the paths behind you", "bold":"Reach for an unwritten path"},
		{"text":"The first light gathers at the threshold of waking.", "safe":"Carry a single ember", "bold":"Carry the whole sunrise"}]},
	{"id":"astral_orchard", "name":"The Astral Orchard", "level":116, "cost":290, "bonus":7, "item":"orchard_memory_charm", "price":28, "previous":"dawn_throne", "description":"Constellations ripen on silver boughs above the first dawn.", "branch":true, "discovery":"A seed holds the memory of a star that chose to fall.", "nodes":[
		{"text":"A keeper offers a fallen star-seed while a comet tears through the orchard.", "safe":"Protect the fallen seed", "bold":"Follow the comet"},
		{"text":"The orchard opens around you.", "safe_text":"The seed reveals a hidden grove where forgotten dreams take root.", "bold_text":"The comet leads to a broken constellation trapped in silver branches.", "safe":"Listen to the rustling leaves", "bold":"Wake the sleeping boughs"},
		{"text":"The keeper waits at the threshold of waking.", "safe_text":"The grove offers you a memory to carry home.", "bold_text":"The freed constellation offers a shard of its light.", "safe":"Carry the gift carefully", "bold":"Gather the scattered starlight"}]},
	{"id":"tide_of_names", "name":"The Tide of Names", "level":118, "cost":320, "bonus":8, "item":"nameless_tide_band", "price":32, "previous":"astral_orchard", "description":"A moonlit sea carries the names of dreams the waking world has forgotten.", "branch":true, "discovery":"A glass bottle preserves a name no dreamer remembers speaking.", "nodes":[
		{"text":"A ferryman offers passage; beneath the water, a nameless voice calls for help.", "safe":"Take the ferryman's passage", "bold":"Dive toward the voice"},
		{"text":"The tide carries you onward.", "safe_text":"The ferryman tells you why he carries forgotten names across the sea.", "bold_text":"The nameless voice belongs to a dreamer trapped beneath the tide.", "safe":"Hear the whole story", "bold":"Bargain with the tide"},
		{"text":"The shore of waking appears through the mist.", "safe_text":"The ferryman entrusts you with a name to remember.", "bold_text":"The freed dreamer offers a pearl of living moonlight.", "safe":"Preserve the gift", "bold":"Follow the last breaking wave"}]},
	{"id":"unwritten_horizon", "name":"The Unwritten Horizon", "level":120, "cost":360, "bonus":9, "item":"horizon_weavers_mantle", "price":36, "previous":"tide_of_names", "description":"Beyond the last dawn, unfinished dreams wait for someone to choose their ending.", "branch":true, "discovery":"A blank page reveals a map of a place that has not yet been dreamed.", "nodes":[
		{"text":"Two doors stand in the horizon: one remembers the past, the other has no handle.", "safe":"Open the door of memories", "bold":"Imagine a way through the unwritten door"},
		{"text":"The horizon takes shape around your choice.", "safe_text":"Familiar dreamers gather to repair the stories they left unfinished.", "bold_text":"A weaver of possibilities invites you to give a new dream its first shape.", "safe":"Weave the quiet threads", "bold":"Pull the brightest thread"},
		{"text":"The horizon trembles as waking approaches.", "safe_text":"Your restored stories light a path home.", "bold_text":"Your new dream reaches toward the waking world.", "safe":"Seal the story gently", "bold":"Carry the unfinished dream home"}]},
]

var completed: Dictionary = {}
var run: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func regions() -> Array:
	return REGIONS

func region(id: String) -> Dictionary:
	for entry in REGIONS:
		if entry.id == id: return entry
	return {}

func lock_reason(id: String) -> String:
	var entry := region(id)
	if entry.is_empty(): return "Unknown region"
	if PlayerData.get_level("dreamwalking") < int(entry.level): return "Reach Dreamwalking %d" % int(entry.level)
	if str(entry.previous) != "" and not completed.has(str(entry.previous)): return "Complete %s" % str(region(str(entry.previous)).name)
	return ""

func start(id: String) -> bool:
	var entry := region(id)
	if not run.is_empty() or entry.is_empty() or lock_reason(id) != "" or not BankManager.has_item("dream_essence", int(entry.cost)):
		return false
	if not BankManager.remove_item("dream_essence", int(entry.cost)): return false
	run = {"region":id, "step":0, "clarity":2, "fragments":0}
	_changed()
	return true

func choose(choice: String) -> Dictionary:
	if run.is_empty() or choice not in ["safe", "bold"]: return {"ok":false}
	var entry := region(str(run.region))
	if entry.is_empty() or int(run.step) < 0 or int(run.step) >= entry.nodes.size(): return {"ok":false}
	if bool(entry.get("branch", false)) and int(run.step) == 0:
		run["path"] = choice
		run["discovery"] = _rng.randf() < 0.15
		if bool(run.discovery): EventBus.notify("Rare discovery: " + str(entry.discovery) + " Return safely to keep its fragments.", "success")
	if choice == "safe":
		run.fragments = int(run.fragments) + 1
		run.clarity = mini(3, int(run.clarity) + 1)
	else:
		run.fragments = int(run.fragments) + 4
		run.clarity = int(run.clarity) - 1
		if _rng.randf() < 0.25:
			run.clarity = int(run.clarity) - 1
			EventBus.notify("The dream shifts: an extra point of clarity is lost.", "warn")
	if int(run.clarity) <= 0:
		run = {}
		EventBus.notify("The dream dissolved. Your unbanked fragments were lost.", "warn")
		_changed()
		return {"ok":true, "result":"failed"}
	run.step = int(run.step) + 1
	if int(run.step) >= entry.nodes.size():
		var reward: int = int(run.fragments) + int(entry.bonus)
		if bool(entry.get("branch", false)):
			reward += 2 if str(run.get("path", "safe")) == "safe" else 4
			if bool(run.get("discovery", false)): reward += 5
		var first: bool = not completed.has(str(entry.id))
		completed[str(entry.id)] = true
		run = {}
		BankManager.add_item_guaranteed(FRAGMENT, reward)
		PlayerData.add_xp("dreamwalking", 5000.0 + float(entry.level) * 100.0)
		EventBus.notify("Returned from %s with %d Lucid Fragments." % [entry.name, reward], "success")
		_changed()
		return {"ok":true, "result":"complete", "fragments":reward, "first":first}
	_changed()
	return {"ok":true, "result":"continue"}

func abandon() -> bool:
	if run.is_empty(): return false
	run = {}
	_changed()
	return true

func purchase(id: String) -> bool:
	var entry := region(id)
	if entry.is_empty() or not completed.has(id) or not BankManager.has_item(FRAGMENT, int(entry.price)):
		return false
	if not BankManager.remove_item(FRAGMENT, int(entry.price)): return false
	BankManager.add_item_guaranteed(str(entry.item), 1)
	_changed()
	return true

func _changed() -> void:
	EventBus.state_refreshed.emit()
	SaveManager._save_on_event()

func serialize() -> Dictionary:
	return {"completed":completed.duplicate(true), "run":run.duplicate(true)}

func deserialize(data: Dictionary) -> void:
	completed = {}
	var raw: Variant = data.get("completed", {})
	if raw is Dictionary:
		for id in raw:
			if not region(str(id)).is_empty() and bool(raw[id]): completed[str(id)] = true
	run = {}
	var candidate: Variant = data.get("run", {})
	if not candidate is Dictionary or candidate.is_empty(): return
	var entry := region(str(candidate.get("region", "")))
	if entry.is_empty(): return
	var step: int = int(candidate.get("step", -1))
	var clarity: int = int(candidate.get("clarity", 0))
	var fragments: int = int(candidate.get("fragments", -1))
	if step < 0 or step >= entry.nodes.size() or clarity < 1 or clarity > 3 or fragments < 0 or fragments > step * 4: return
	run = {"region":str(entry.id), "step":step, "clarity":clarity, "fragments":fragments}
	if bool(entry.get("branch", false)) and step > 0:
		var path := str(candidate.get("path", ""))
		if path not in ["safe", "bold"]:
			run = {}
			return
		run["path"] = path
		run["discovery"] = bool(candidate.get("discovery", false))
