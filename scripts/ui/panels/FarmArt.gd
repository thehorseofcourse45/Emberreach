extends RefCounted
## Farm illustrations and presentation helpers.

const ART := "res://assets/farm/"


static func texture(file: String) -> Texture2D:
	var path := ART + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func picture(source: Texture2D, dimensions := Vector2.ZERO) -> TextureRect:
	var image := TextureRect.new()
	image.texture = source
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = dimensions
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


static func banner(body: Control) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size.y = 192
	frame.clip_contents = true
	frame.add_theme_stylebox_override("panel", UIStyle.flat_box("panel", true))
	var image := picture(texture("farmstead.webp"))
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(image)

	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.30, 0.69, 1.0])
	colors.colors = PackedColorArray([
		Color(0.04, 0.08, 0.11, 0.95), Color(0.04, 0.08, 0.11, 0.81),
		Color(0.04, 0.08, 0.11, 0.32), Color(0.04, 0.08, 0.11, 0.12),
	])
	var shading := GradientTexture2D.new()
	shading.width = 512
	shading.height = 4
	shading.gradient = colors
	var shade := picture(shading)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	frame.add_child(shade)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UITokens.SP_6)
	margin.add_theme_constant_override("margin_right", UITokens.SP_5)
	margin.add_theme_constant_override("margin_top", UITokens.SP_4)
	margin.add_theme_constant_override("margin_bottom", UITokens.SP_4)
	margin.add_child(body)
	frame.add_child(margin)
	return frame


static func plot_picture(kind: String, state: String) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.add_theme_stylebox_override("panel", UIStyle.flat_box("slot"))
	var image := picture(texture("%s_%s.png" % [kind, state]), Vector2(94, 88))
	if image.texture == null:
		image.texture = AssetRegistry.skill_icon("farming")
	frame.add_child(image)
	return frame


static func label(value: String, color := UITokens.TEXT_MUTED, font_size := UITokens.FONT_SMALL) -> Label:
	var text := UIStyle.colored_label(value, color, font_size)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return text


static func button_icon(button: Button, kind: String, id: String) -> void:
	button.icon = AssetRegistry.item_icon(id) if kind == "items" else AssetRegistry.icon(kind, id)
	button.add_theme_constant_override("icon_max_width", UITokens.ICON_SM)


static func selected_tab() -> StyleBoxFlat:
	var style := UIStyle.flat_box("button", true)
	style.bg_color = UITokens.SURFACE_3
	style.border_color = UITokens.GOLD_BRIGHT
	style.border_width_bottom = 2
	return style

