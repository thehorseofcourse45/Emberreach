class_name TextureFactory
extends RefCounted
## TextureFactory — the grimoire surfaces, painted in code: oxblood leather, smoked vellum and a gold
## trim frame. Built once from noise and gradients, then cached, so every panel shares a handful of
## textures. Painted art (assets/ui/<kind>_grimoire_9slice.png) replaces these per piece; see
## UIStyle.surface_box.

## Test hook: every builder returns null, so the caller's flat fallback can be exercised.
static var fail_for_test: bool = false
static var _cache: Dictionary = {}

static func clear_cache() -> void:
	_cache.clear()

## Oxblood leather with a fine grain and a gold trim frame painted on its edge.
static func leather(size: Vector2i = Vector2i(96, 96)) -> Texture2D:
	return _cached("leather", size, func(): return _paint(size, UITokens.LEATHER_TOP, UITokens.LEATHER_BOTTOM, 0.06, 0.0, true))

## Smoked vellum: umber paper grain, a darker vignette at the edge and a thin vellum-coloured rim.
static func vellum(size: Vector2i = Vector2i(64, 64)) -> Texture2D:
	return _cached("vellum", size, func(): return _paint(size, UITokens.VELLUM_TOP, UITokens.VELLUM_BOTTOM, 0.05, 0.18, false))

## A standalone gold trim frame with a transparent centre (24 x 24).
static func gold_trim() -> Texture2D:
	return _cached("trim", Vector2i(24, 24), func():
		var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_frame(img, Color("#1a0d07"), Color("#c88c2c"), Color("#f0c870"))
		return ImageTexture.create_from_image(img))

static func _cached(kind: String, size: Vector2i, build: Callable) -> Texture2D:
	if fail_for_test:
		return null
	var key: String = "%s:%d:%d" % [kind, size.x, size.y]
	if not _cache.has(key):
		_cache[key] = build.call()
	return _cache[key]

## Vertical gradient top->bottom, simplex grain of `grain` strength, optional edge vignette, and
## either a gold trim frame (leather) or a 1 px vellum rim (vellum).
static func _paint(size: Vector2i, top: Color, bottom: Color, grain: float, vignette: float, trimmed: bool) -> Texture2D:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.08
	noise.seed = 7
	for y in range(size.y):
		var base: Color = top.lerp(bottom, float(y) / float(maxi(1, size.y - 1)))
		for x in range(size.x):
			var c: Color = base
			c = c.lightened(noise.get_noise_2d(x, y) * grain) if noise.get_noise_2d(x, y) > 0.0 else c.darkened(-noise.get_noise_2d(x, y) * grain)
			if vignette > 0.0:
				var edge: float = minf(minf(x, size.x - 1 - x), minf(y, size.y - 1 - y)) / 6.0
				c = c.darkened(vignette * (1.0 - clampf(edge, 0.0, 1.0)))
			img.set_pixel(x, y, c)
	if trimmed:
		_frame(img, Color("#1a0d07"), Color("#c88c2c"), Color("#f0c870"))
	else:
		_rect_outline(img, 0, UITokens.BORDER)
	return ImageTexture.create_from_image(img)

## 1 px outer line, 2 px gold, 1 px highlight, drawn inward from the image edge.
static func _frame(img: Image, outer: Color, gold: Color, highlight: Color) -> void:
	_rect_outline(img, 0, outer)
	_rect_outline(img, 1, gold)
	_rect_outline(img, 2, gold)
	_rect_outline(img, 3, highlight)

static func _rect_outline(img: Image, inset: int, color: Color) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	for x in range(inset, w - inset):
		img.set_pixel(x, inset, color)
		img.set_pixel(x, h - 1 - inset, color)
	for y in range(inset, h - inset):
		img.set_pixel(inset, y, color)
		img.set_pixel(w - 1 - inset, y, color)
