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

static func _is_reduced() -> bool:
	if force_reduced:
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
