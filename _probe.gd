extends SceneTree
## Temporary probe: measure the card one frame after it is rendered, when layout has run.

var _panel: Control
var _cases: Array = ["diamond", "bronze_sword", "shrimp", "enchanting_skillcape", "ash", "raid_pet_egg"]
var _index: int = -1
var _measure_next: bool = false

func _process(_delta: float) -> bool:
	if _index < 0:
		(root.get_node("GameManager") as Node).call("start_new_game", "standard")
		var holder := Control.new()
		root.add_child(holder)
		holder.size = Vector2(253, 900)
		_panel = load("res://scripts/ui/DetailPanel.gd").new()
		holder.add_child(_panel)
		_panel.size = Vector2(253, 900)
		_index = 0
		_panel.call("show_item", _cases[0])
		_measure_next = true
		return false
	if not _measure_next:
		return false
	var id: String = str(_cases[_index])
	print("\n%s min=%.0f  starved=%d" % [id, _panel.get_combined_minimum_size().x, _starved_count(_panel, 0)])
	_starved(_panel, "  ", 0)
	_index += 1
	if _index >= _cases.size():
		quit()
		return false
	_panel.call("show_item", str(_cases[_index]))
	return false

func _starved_count(node: Node, found: int) -> int:
	for child in node.get_children():
		if child is Label and (child as Label).text.length() > 5 and (child as Control).size.x < 20.0:
			found += 1
		found = _starved_count(child, found)
	return found

func _starved(node: Node, indent: String, depth: int) -> void:
	if depth > 4:
		return
	for child in node.get_children():
		var c: Control = child as Control
		if c == null:
			continue
		if c is Label and (c as Label).text.length() > 5 and c.size.x < 20.0:
			print("%sSTARVED \"%s\" size=%.0f" % [indent, (c as Label).text.substr(0, 40), c.size.x])
		_starved(child, indent + "  ", depth + 1)
