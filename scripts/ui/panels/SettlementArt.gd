extends RefCounted
## The settlement's visual components and icon mappings.

const ART := "res://assets/settlement/"
const RESOURCE_ICONS := {
	"wood": ["items", "normal_log"],
	"stone": ["items", "tin_ore"],
	"metal": ["items", "iron_bar"],
	"food": ["items", "trout"],
	"goods": ["items", "wood_box"],
	"reagents": ["items", "garum_herb"],
	"drills": ["items", "iron_sword"],
	"supplies": ["skills", "caravaneering"],
	"faith": ["currencies", "prayer_points"],
	"astral_dust": ["currencies", "stardust"],
	"population": ["skills", "township"],
}
const PROJECT_ICONS := {
	"wonder_astral_observatory": "astrology",
	"wonder_skyport": "caravaneering",
	"wonder_masterwork_forge": "smithing",
	"wonder_archive_echoes": "echo_keeping",
}


static func art(file: String) -> Texture2D:
	var path := ART + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func icon(kind: String, id: String) -> Texture2D:
	return AssetRegistry.item_icon(id) if kind == "items" else AssetRegistry.icon(kind, id)


static func resource_icon(id: String) -> Texture2D:
	var source: Array = RESOURCE_ICONS.get(id, ["skills", "township"])
	return icon(source[0], source[1])


static func structure_icon(id: String) -> Texture2D:
	var illustration := art(id + ".png")
	if illustration != null:
		return illustration
	return icon("skills", PROJECT_ICONS.get(id, "township"))


static func texture_rect(texture: Texture2D, dimensions: Vector2, nearest := true) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = dimensions
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if nearest:
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return image


static func hero() -> PanelContainer:
	var frame := PanelContainer.new()
	frame.clip_contents = true
	frame.add_theme_stylebox_override("panel", UIStyle.flat_box("panel", true))
	return frame


static func hero_shade() -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.30, 0.64, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.035, 0.065, 0.11, 0.96), Color(0.035, 0.065, 0.11, 0.86),
		Color(0.035, 0.065, 0.11, 0.46), Color(0.035, 0.065, 0.11, 0.14)
	])
	var shade := GradientTexture2D.new()
	shade.gradient = gradient
	shade.width = 512
	shade.height = 4
	return texture_rect(shade, Vector2.ZERO, false)


static func section(heading: String, texture: Texture2D, hint := "") -> VBoxContainer:
	var section_box := UIStyle.vbox(UITokens.SP_3)
	var row := UIStyle.hbox(UITokens.SP_3)
	row.add_child(texture_rect(texture, Vector2(20, 20)))
	var title := UIStyle.title(heading, UITokens.FONT_SUBHEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	section_box.add_child(row)
	if hint != "":
		section_box.add_child(copy(hint))
	return section_box


static func grid() -> GridContainer:
	var container := GridContainer.new()
	container.add_theme_constant_override("h_separation", UITokens.SP_4)
	container.add_theme_constant_override("v_separation", UITokens.SP_4)
	return container


static func card(parent: Container, highlighted := false) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UIStyle.surface_box("card", highlighted))
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	var body := UIStyle.vbox(UITokens.SP_3)
	frame.add_child(body)
	return body


static func card_heading(title: String, image: Texture2D, caption := "", illustration := false) -> HBoxContainer:
	var row := UIStyle.hbox(UITokens.SP_4)
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", UIStyle.flat_box("slot"))
	var edge: int = 64 if illustration else 32
	well.add_child(texture_rect(image, Vector2(edge, edge)))
	row.add_child(well)
	var names := UIStyle.vbox(UITokens.SP_1)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(names)
	var heading := UIStyle.title(title, UITokens.FONT_SUBHEAD)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(heading)
	if caption != "":
		names.add_child(copy(caption))
	return row


static func copy(text: String, color := UITokens.TEXT_MUTED, font_size := UITokens.FONT_SMALL) -> Label:
	var label := UIStyle.colored_label(text, color, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func chips() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", UITokens.SP_2)
	flow.add_theme_constant_override("v_separation", UITokens.SP_2)
	return flow


static func chip(image: Texture2D, text: String, color := UITokens.TEXT, tooltip := "") -> Control:
	var frame := PanelContainer.new()
	frame.set_meta("widget", "stat_chip")
	frame.add_theme_stylebox_override("panel", UIStyle.surface_box("chip"))
	frame.tooltip_text = tooltip
	var row := UIStyle.hbox(UITokens.SP_2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texture_rect(image, Vector2(16, 16)))
	var label := UIStyle.colored_label(text, color, UITokens.FONT_MICRO)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	frame.add_child(row)
	return frame


static func resource_costs(parent: VBoxContainer, costs: Dictionary) -> void:
	if costs.is_empty():
		return
	var row := chips()
	for id in costs:
		var have: float = float(TownshipManager.resources.get(id, 0.0))
		var need: float = float(costs[id])
		var label: String = TownshipManager.resource_name(id)
		row.add_child(chip(resource_icon(id), "%s %s" % [UIStyle.fmt(need), label],
			UITokens.TEXT if have >= need else UITokens.AMBER, "%s / %s %s in stores" % [
			UIStyle.fmt(have), UIStyle.fmt(need), label]))
	parent.add_child(row)


static func requirement(image: Texture2D, label: String, have: float, need: float) -> HBoxContainer:
	var row := UIStyle.hbox(UITokens.SP_2)
	row.add_child(texture_rect(image, Vector2(18, 18)))
	var numbers := Widgets.requirement_row(label, have, need, have >= need)
	numbers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(numbers)
	return row

