extends AcceptDialog
## SurveyMinigame - surveying a hex is a tile hunt over its map picture.
##
## The picture is PICTURE_SIZE px square, cut into TILE_SIZE px tiles (a GRID x GRID board). Every
## tile starts fogged. Revealing one uncovers that piece of the picture and shows how many tiles
## away the Point of Interest is (Chebyshev distance, so a diagonal step counts as 1). Find it
## within _max_reveals to claim the POI; run out and the fog rolls back for another attempt.
##
## Art: reusable terrain maps and transparent landmark overlays in res://assets/survey/.
## Optional <hex_id>.png overrides the composition; a placeholder covers missing terrain.

signal finished(found: bool)

const PICTURE_SIZE: int = 256
const TILE_SIZE: int = 32
const GRID: int = 8   # PICTURE_SIZE / TILE_SIZE; the test suite checks they agree
var _max_reveals: int = 12   # set per hex from its terrain in _ready

var hex_id: String = ""
var _poi: Vector2i
var _picture: Texture2D
var _fog: Texture2D
var _tiles: Array[TextureButton] = []
var _revealed: Dictionary = {}
var _found: bool = false
var _status: Label

## Where the POI hides on this hex's board. Deterministic, so a reopened map keeps its secret.
static func poi_cell(id: String) -> Vector2i:
	var h: int = absi(hash(id))
	return Vector2i(h % GRID, floori(h / float(GRID)) % GRID)

static func hint(cell: Vector2i, poi: Vector2i) -> int:
	return maxi(absi(cell.x - poi.x), absi(cell.y - poi.y))

static func placeholder_picture(id: String) -> Texture2D:
	var img := Image.create_empty(PICTURE_SIZE, PICTURE_SIZE, false, Image.FORMAT_RGBA8)
	var hue: float = float(absi(hash(id)) % 360) / 360.0
	for y in range(PICTURE_SIZE):
		for x in range(PICTURE_SIZE):
			var c := Color.from_hsv(hue, 0.35, 0.3 + 0.4 * float(x + y) / float(2 * PICTURE_SIZE))
			if x % TILE_SIZE == 0 or y % TILE_SIZE == 0:
				c = c.darkened(0.3)
			img.set_pixel(x, y, c)
	# A gold cross on the POI tile, so finding it reads at a glance before real art exists.
	var half: int = TILE_SIZE >> 1
	var centre: Vector2i = poi_cell(id) * TILE_SIZE + Vector2i(half, half)
	for i in range(-half + 4, half - 3):
		img.set_pixel(centre.x + i, centre.y, Color.GOLD)
		img.set_pixel(centre.x, centre.y + i, Color.GOLD)
	return ImageTexture.create_from_image(img)

## Compose reusable terrain and a hidden landmark; custom per-hex art wins.
static func picture_for_hex(id: String, show_landmark: bool = true) -> Texture2D:
	var custom_path: String = "res://assets/survey/%s.png" % id
	if ResourceLoader.exists(custom_path):
		return load(custom_path)
	var hex: Dictionary = DataLoader.cartography_hexes.get(id, {})
	var path: String = "res://assets/survey/terrain/%s.png" % str(hex.get("terrain", "plains"))
	if not ResourceLoader.exists(path):
		return placeholder_picture(id)
	var source: Texture2D = load(path)
	var picture: Image = source.get_image()
	if picture.is_compressed(): picture.decompress()
	picture.convert(Image.FORMAT_RGBA8)
	picture.resize(PICTURE_SIZE, PICTURE_SIZE, Image.INTERPOLATE_NEAREST)
	var landmark_path: String = "res://assets/survey/landmarks/%s.png" % str(hex.get("landmark", "relic"))
	if show_landmark and not hex.get("poi", {}).is_empty() and ResourceLoader.exists(landmark_path):
		var landmark: Texture2D = load(landmark_path)
		var overlay: Image = landmark.get_image()
		if overlay.is_compressed(): overlay.decompress()
		overlay.convert(Image.FORMAT_RGBA8)
		overlay.resize(TILE_SIZE, TILE_SIZE, Image.INTERPOLATE_LANCZOS)
		picture.blend_rect(overlay, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), poi_cell(id) * TILE_SIZE)
	return ImageTexture.create_from_image(picture)

func _ready() -> void:
	title = "Survey"
	ok_button_text = "Leave"
	_max_reveals = CartographyManager.survey_reveals(hex_id)
	_poi = poi_cell(hex_id)
	_picture = picture_for_hex(hex_id)
	var fog := Image.create_empty(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	fog.fill(Color("#1b2430"))
	_fog = ImageTexture.create_from_image(fog)
	var col := VBoxContainer.new()
	add_child(col)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(PICTURE_SIZE, 0)
	col.add_child(_status)
	var grid := GridContainer.new()
	grid.columns = GRID
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	col.add_child(grid)
	for y in range(GRID):
		for x in range(GRID):
			var tile := TextureButton.new()
			var cell := Vector2i(x, y)
			tile.pressed.connect(func(): _reveal(cell))
			var mark := Label.new()
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			mark.set_anchors_preset(Control.PRESET_FULL_RECT)
			tile.add_child(mark)
			grid.add_child(tile)
			_tiles.append(tile)
	confirmed.connect(_close)
	canceled.connect(_close)
	_reset()

func _reset(note: String = "") -> void:
	_revealed.clear()
	for tile in _tiles:
		tile.texture_normal = _fog
		tile.disabled = false
		tile.tooltip_text = "Survey this tile"
		(tile.get_child(0) as Label).text = ""
	_status.text = note + "Find the Point of Interest under the fog. Each tile you reveal shows how many tiles away it is. %d reveals per attempt." % _max_reveals

func _reveal(cell: Vector2i) -> void:
	if _found or _revealed.has(cell):
		return
	_revealed[cell] = true
	var tile: TextureButton = _tiles[cell.y * GRID + cell.x]
	var piece := AtlasTexture.new()
	piece.atlas = _picture
	piece.region = Rect2(Vector2(cell * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE))
	tile.texture_normal = piece
	tile.disabled = true
	var d: int = hint(cell, _poi)
	(tile.get_child(0) as Label).text = "" if d == 0 else str(d)
	tile.tooltip_text = "Point of Interest" if d == 0 else "%d tiles away" % d
	if d == 0:
		_found = true
		for t in _tiles:
			t.disabled = true
		CartographyManager.survey(hex_id)
		_status.text = "Found it. The Point of Interest is claimed."
	elif _revealed.size() >= _max_reveals:
		_reset("Out of reveals, and the fog rolls back in. ")
	else:
		_status.text = "%d tiles away. %d reveals left." % [d, _max_reveals - _revealed.size()]

func _close() -> void:
	finished.emit(_found)
	queue_free()
