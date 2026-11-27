extends Control
## Existing frontier art with restoration markers layered over it.

var map: Texture2D = preload("res://assets/caravans/maps/ferryman_run.png")
var labels: Array[String] = ["FIELDS", "ROAD", "ROOST"]
var stage: int = 0
var states: Array[String] = []

func _ready() -> void:
	custom_minimum_size = Vector2(0, 180)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var source := Rect2(0, 150, map.get_width(), 350)
	draw_texture_rect_region(map, Rect2(Vector2.ZERO, size), source, Color(0.60, 0.60, 0.58) if stage == 0 else Color.WHITE)
	var font := get_theme_default_font()
	for i in range(labels.size()):
		var center := Vector2(size.x * (float(i) + 0.5) / float(labels.size()), size.y * 0.60)
		var state: String = states[i] if i < states.size() else ("completed" if stage > i else "locked")
		var color: Color = UITokens.GREEN if state == "completed" else (UITokens.GOLD_BRIGHT if state == "ready" else (UITokens.BLUE if state in ["available", "in_progress"] else UITokens.TEXT_MUTED))
		draw_circle(center, 18, Color("1b2631"))
		draw_arc(center, 18, 0, TAU, 32, color, 3.0, true)
		draw_string(font, center + Vector2(-5, 5), "✓" if state == "completed" else str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
		var width := font.get_string_size(labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, center + Vector2(-width / 2.0, 37), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), Color("b39b70"), false, 1.0)
