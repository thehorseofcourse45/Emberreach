class_name Motion
extends RefCounted
## Motion — shared tween/floater helper for the UI identity pass.
##
## Every func is a no-op when reduced motion is on (the real setting, same source as
## ToastStack.UITokens_motion_reduced(), or the `force_reduced` test hook). Floaters
## reuse hidden Labels from a per-parent pool capped at 12 children — never queue_free.

static var force_reduced := false

const MAX_FLOATERS: int = 12
const _PULSE_META: String = "motion_pulse_tween"
const _HOME_Y_META: String = "motion_home_y"

## Silent simulation (offline catch-up, the test runner) never animates either: nobody is
## watching, and a burst of tweens there only costs frames.
static func _is_reduced() -> bool:
	if force_reduced or SimulationMode.is_silent():
		return true
	return bool(PlayerData.settings.get("reduced_motion", false))

## The reduced-motion gate, for the bespoke tweens that are not Motion helpers (a hit flash, a
## sliding nav accent). `_is_reduced` stays private; this is the name other files call.
static func reduced() -> bool:
	return _is_reduced()

## Tween a ProgressBar to its new value over 0.25s.
##
## Bars are built by a factory and parented by the caller afterwards, so the usual case arrives
## before the bar is in the tree — and a tween cannot be created off-tree at all. The value is set
## straight away (it is the authoritative one, since this func is a no-op under reduced motion) and
## the glide is armed on `tree_entered` instead of being dropped. One-shot, so re-parenting a bar
## cannot stack a second glide on top of the first.
static func tween_bar(bar: ProgressBar, to_value: float) -> void:
	if _is_reduced():
		return
	if bar == null or not is_instance_valid(bar):
		return
	if not bar.is_inside_tree():
		bar.value = to_value
		bar.tree_entered.connect(func() -> void: _tween_bar_when_shown(bar, to_value), Object.CONNECT_ONE_SHOT)
		return
	_tween_bar_now(bar, to_value)

## The deferred half of tween_bar. Reduced motion is re-checked rather than assumed: the setting
## can be flipped between arming the glide and the bar reaching the screen.
static func _tween_bar_when_shown(bar: ProgressBar, to_value: float) -> void:
	if _is_reduced():
		return
	if bar == null or not is_instance_valid(bar) or not bar.is_inside_tree():
		return
	_tween_bar_now(bar, to_value)

static func _tween_bar_now(bar: ProgressBar, to_value: float) -> void:
	var tween: Tween = bar.create_tween()
	tween.tween_property(bar, "value", to_value, 0.25)

## Rise 28px and fade over 0.7s, then hide for reuse. Pool stays bounded at 12.
static func spawn_floater(parent: Node, text: String, color: Color) -> void:
	if _is_reduced():
		return
	if parent == null or not is_instance_valid(parent):
		return
	var label: Label = null
	for child in parent.get_children():
		var existing := child as Label
		if existing != null and not existing.visible:
			label = existing
			break
	if label == null:
		if parent.get_child_count() >= MAX_FLOATERS:
			return
		label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.set_meta(_HOME_Y_META, label.position.y)
		parent.add_child(label)
	else:
		label.position.y = float(label.get_meta(_HOME_Y_META, label.position.y))
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.visible = true
	label.modulate.a = 1.0
	if not label.is_inside_tree():
		return
	var rise_to: float = label.position.y - 28.0
	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", rise_to, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(label.hide)

## Gentle attention loop, scale 1.0 <-> 1.04. Re-calling restarts it, never stacks.
static func pulse(control: Control) -> void:
	if _is_reduced():
		return
	if control == null or not is_instance_valid(control):
		return
	if control.has_meta(_PULSE_META):
		var old: Variant = control.get_meta(_PULSE_META)
		if old is Tween and is_instance_valid(old):
			(old as Tween).kill()
		control.remove_meta(_PULSE_META)
	if not control.is_inside_tree():
		return
	_center_pivot(control)
	var tween: Tween = control.create_tween().set_loops()
	control.set_meta(_PULSE_META, tween)
	# Re-read on every lap, not only here. A caller pulses a control on the frame it is added,
	# when `size` is still zero and the pivot would sit in the corner, so the bar would breathe
	# lopsided; a window resize moves the centre again while the loop is still running.
	tween.tween_callback(_center_pivot.bind(control))
	tween.tween_property(control, "scale", Vector2(1.04, 1.04), 0.45).set_trans(Tween.TRANS_SINE)
	tween.tween_property(control, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)

## The pulse pivots on the control's centre, which is only knowable once it has been laid out.
static func _center_pivot(control: Control) -> void:
	control.pivot_offset = control.size * 0.5

## A ring of gold runes bursts from `target` (a level-up): a ring that grows and fades over 0.6s and
## a one-shot spray of sparks, both drawn on `layer` so a scrolled or clipped sidebar cannot cut them.
static func rune_burst(layer: Control, target: Control) -> void:
	if _is_reduced() or layer == null or target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var burst := Control.new()
	burst.set_meta("rune_burst", true)
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burst.z_index = UITokens.Z_TOAST
	layer.add_child(burst)
	burst.global_position = target.get_global_rect().get_center()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 0.8, 0.4, 0.0), Color(1, 0.82, 0.45, 0.9), Color(1, 0.6, 0.2, 0.0)])
	grad.offsets = PackedFloat32Array([0.55, 0.75, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 96
	tex.height = 96
	var ring := TextureRect.new()
	ring.texture = tex
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size = Vector2(96, 96)
	ring.position = Vector2(-48, -48)
	ring.pivot_offset = Vector2(48, 48)
	ring.scale = Vector2(0.6, 0.6)
	burst.add_child(ring)
	var sparks := CPUParticles2D.new()
	sparks.one_shot = true
	sparks.amount = 16
	sparks.lifetime = 0.6
	sparks.explosiveness = 1.0
	sparks.spread = 180.0
	sparks.initial_velocity_min = 40.0
	sparks.initial_velocity_max = 90.0
	sparks.gravity = Vector2.ZERO
	sparks.color = UITokens.GOLD_BRIGHT
	sparks.emitting = true
	burst.add_child(sparks)
	var tween: Tween = burst.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(1.6, 1.6), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(burst.queue_free)

## Count a number up to its new value over 0.4s. Gated or off-tree: the final text at once.
static func count_up(label: Label, from: float, to: float, formatter: Callable) -> void:
	if label == null or not is_instance_valid(label):
		return
	if _is_reduced() or not label.is_inside_tree() or is_equal_approx(from, to):
		label.text = formatter.call(to)
		return
	var tween: Tween = label.create_tween()
	tween.tween_method(func(v: float) -> void: label.text = formatter.call(v), from, to, 0.4)

## A page arrives: fade in while rising 12px over 0.18s. Gated or off-tree: shown at once.
static func page_in(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	if _is_reduced() or not control.is_inside_tree():
		control.modulate.a = 1.0
		return
	var home: float = control.position.y
	control.modulate.a = 0.0
	control.position.y = home + 12.0
	var tween: Tween = control.create_tween().set_parallel(true)
	tween.tween_property(control, "modulate:a", 1.0, UITokens.DUR_NORMAL)
	tween.tween_property(control, "position:y", home, UITokens.DUR_NORMAL)

## A soft highlight that sweeps along a bar every few seconds. One per bar.
static func shimmer(bar: ProgressBar) -> void:
	if _is_reduced() or bar == null or not is_instance_valid(bar) or not bar.is_inside_tree():
		return
	for c in bar.get_children():
		if c.has_meta("shimmer"):
			return
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 0.95, 0.8, 0.28), Color(1, 1, 1, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 32
	tex.height = 2
	var glint := TextureRect.new()
	glint.set_meta("shimmer", true)
	glint.texture = tex
	glint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glint.stretch_mode = TextureRect.STRETCH_SCALE
	glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glint.anchor_top = 0.0
	glint.anchor_bottom = 1.0
	glint.size = Vector2(32, bar.size.y)
	bar.clip_contents = true
	bar.add_child(glint)
	var tween: Tween = glint.create_tween().set_loops()
	tween.tween_callback(func() -> void: glint.position.x = -32.0)
	tween.tween_property(glint, "position:x", maxf(bar.size.x, 64.0), 1.4).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(2.6)

## Buttons press in: scale to 0.97 while held. Applied by UIStyle's button factories.
static func press(button: BaseButton) -> void:
	button.button_down.connect(func() -> void: _press_to(button, 0.97))
	button.button_up.connect(func() -> void: _press_to(button, 1.0))

static func _press_to(button: BaseButton, s: float) -> void:
	if _is_reduced() or not is_instance_valid(button) or not button.is_inside_tree():
		button.scale = Vector2.ONE
		return
	button.pivot_offset = button.size * 0.5
	button.create_tween().tween_property(button, "scale", Vector2(s, s), 0.06)

## Fade in while settling up 6px over 0.18s. Outside the tree, snap to visible.
static func fade_rise(control: Control) -> void:
	if _is_reduced():
		return
	if control == null or not is_instance_valid(control):
		return
	control.modulate.a = 0.0
	control.position.y += 6.0
	if not control.is_inside_tree():
		control.modulate.a = 1.0
		control.position.y -= 6.0
		return
	var tween: Tween = control.create_tween().set_parallel(true)
	tween.tween_property(control, "modulate:a", 1.0, 0.18)
	tween.tween_property(control, "position:y", control.position.y - 6.0, 0.18)
