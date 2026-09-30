extends VBoxContainer
## StatsPanel — the lifetime record: what you have done, and what you have done most of.
##
## A pure read-out of PlayerData.stats, which ProgressTracker writes from the real simulation, so
## every number here already includes progress made while the game was closed. Nothing on this
## screen is recomputed, estimated or recomputed from the bank.

signal navigated(route: Dictionary)
signal context_changed(ctx: Dictionary)

## Headline counters. The second entry is the PlayerData.stats bucket each one is read from.
const LIFETIME_ROWS: Array = [
	["Actions completed", "actions"],
	["Items gained", "items_gained"],
	["Items crafted", "items_crafted"],
	["Items sold", "items_sold"],
	["Monsters killed", "monsters_killed"],
	["Expeditions cleared", "dungeons_cleared"],
	["Regions visited", "region_visits"],
	["Gold earned", "gp_earned"],
	["Tasks completed", "quests_completed"],
	["Deaths", "deaths"],
]

## Rankings, in display order. `by_skill` folds "skill:action" keys into per-skill totals.
const RANKINGS: Array = [
	{"bucket": "monsters_killed", "kind": "monsters", "by_skill": false,
		"title": "Most killed monsters", "hint": "the ten you have put down most often"},
	{"bucket": "items_gained", "kind": "items", "by_skill": false,
		"title": "Most gathered / crafted items", "hint": "everything that ever entered your bank"},
	{"bucket": "actions", "kind": "skills", "by_skill": true,
		"title": "Skills by actions performed", "hint": "every activity counted toward its skill"},
]

const TOP_N: int = 10

var _body: VBoxContainer
var _built: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", UITokens.SP_5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	add_child(UIStyle.title("Lifetime record", UITokens.FONT_DISPLAY))
	add_child(UIStyle.label(
		"Counted from the moment your journey began, and including everything that happened while the game was closed.",
		true, UITokens.FONT_SMALL))
	_body = UIStyle.vbox(UITokens.SP_5)
	add_child(_body)
	EventBus.state_refreshed.connect(refresh)
	refresh()

func focus_route(_route: Dictionary) -> void:
	pass

func detail_context() -> Dictionary:
	return {"kind": "text", "title": "Lifetime record",
		"body": "The simulation writes these counters as it runs, so offline gains are already in them. Rankings show the ten highest of each kind."}

func refresh() -> void:
	if not _built:
		return
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var rows: Array = _lifetime_rows()
	var any: bool = false
	for r in rows:
		if float(r["value"]) > 0.0:
			any = true
			break
	if not any:
		_body.add_child(UIStyle.label(
			"Nothing recorded yet. Gather, craft or fight for a while and your totals will show up here.",
			true, UITokens.FONT_SMALL))
		return
	_body.add_child(_lifetime(rows))
	for spec in RANKINGS:
		var ranking: Control = _ranking(spec)
		if ranking != null:
			_body.add_child(ranking)

func _lifetime(rows: Array) -> Control:
	var box := UIStyle.section("Lifetime", "totals across every system")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", UITokens.SP_4)
	flow.add_theme_constant_override("v_separation", UITokens.SP_4)
	for r in rows:
		flow.add_child(Widgets.stat_card(str(r["label"]), UIStyle.fmt(float(r["value"]))))
	box.add_child(flow)
	return box

func _ranking(spec: Dictionary) -> Control:
	var entries: Array = _top(spec)
	if entries.is_empty():
		return null
	var box := UIStyle.section(str(spec["title"]), str(spec["hint"]))
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		box.add_child(Widgets.key_value("%d.  %s" % [i + 1, str(entry["name"])],
			UIStyle.fmt(float(entry["count"])), UITokens.TEXT_STRONG))
	return box

## Top entries of a bucket, descending, ties broken by name so the order never shuffles.
func _top(spec: Dictionary) -> Array:
	var raw: Variant = PlayerData.stats.get(str(spec["bucket"]), {})
	if typeof(raw) != TYPE_DICTIONARY:
		return []
	var totals: Dictionary = {}
	for key in (raw as Dictionary).keys():
		# Actions are stored as "skill_id:action_id"; the ranking is per skill.
		var group: String = str(key).get_slice(":", 0) if bool(spec["by_skill"]) else str(key)
		totals[group] = float(totals.get(group, 0.0)) + float(raw[key])
	var entries: Array = []
	for group in totals.keys():
		if float(totals[group]) <= 0.0:
			continue
		entries.append({"name": _display_name(str(group), str(spec["kind"])), "count": float(totals[group])})
	entries.sort_custom(func(a, b):
		if not is_equal_approx(float(a["count"]), float(b["count"])):
			return float(a["count"]) > float(b["count"])
		return str(a["name"]) < str(b["name"]))
	return entries.slice(0, TOP_N)

func _lifetime_rows() -> Array:
	var stats: Dictionary = PlayerData.stats
	var rows: Array = []
	for entry in LIFETIME_ROWS:
		rows.append({"label": str(entry[0]), "value": _total(stats, str(entry[1]))})
	return rows

## One bucket's worth. Dictionary buckets hold one counter per id; the scalar buckets (gold
## earned, tasks completed, deaths) are already totals. region_visits holds booleans, which sum
## to the number of regions visited.
func _total(stats: Dictionary, bucket: String) -> float:
	var raw: Variant = stats.get(bucket, 0.0)
	if typeof(raw) != TYPE_DICTIONARY:
		return float(raw)
	var sum: float = 0.0
	for v in (raw as Dictionary).values():
		sum += float(v)
	return sum

func _display_name(id: String, kind: String) -> String:
	match kind:
		"monsters": return str(DataLoader.get_monster(id).get("name", id))
		"items": return str(DataLoader.get_item(id).get("name", id))
		"skills": return str(DataLoader.get_skill(id).get("name", id))
	return id
