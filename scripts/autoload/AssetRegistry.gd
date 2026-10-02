extends Node
## AssetRegistry — the art system. Loads textures by convention from res://assets/
## and returns a generated placeholder when a file is missing, so the game looks
## intentional at every stage of art production.
##
## Conventions (all PNG, transparent):
##   res://assets/icons/items/<item_id>.png          32x32
##   res://assets/icons/skills/<skill_id>.png        32x32
##   res://assets/sprites/monsters/<monster_id>.png  96x96
##   res://assets/icons/areas|dungeons|prayers|pets|familiars|obstacles/<id>.png
##   res://assets/icons/currencies/<id>.png          24x24
##   res://assets/icons/slots/<slot_id>.png          28x28
##   res://assets/icons/status/<effect_id>.png       24x24
##   res://assets/ui/<name>.png                      (panel_9slice, button_9slice, ...)

const BASE: String = "res://assets/"
const PLACEHOLDER_COLOR: Color = Color("#22303f")

var _cache: Dictionary = {}          # rel_path -> Texture2D
var _placeholders: Dictionary = {}   # kind:id -> Texture2D

# ---------------- Public API ----------------
func item_icon(item_id: String) -> Texture2D:
    var source: String = str(DataLoader.get_item(item_id).get("icon_id", item_id))
    if source in ["ranching", "inscription", "engineering", "enchanting", "dreamwalking"]:
        return skill_icon(source)
    return _load("icons/items/%s.png" % source, "items", source)

func skill_icon(skill_id: String) -> Texture2D:
    return _load("icons/skills/%s.png" % skill_id, "skills", skill_id)

func monster_sprite(monster_id: String) -> Texture2D:
    if monster_id == "":
        return null
    return _load("sprites/monsters/%s.png" % monster_id, "monsters", monster_id)

func icon(kind: String, id: String) -> Texture2D:
    return _load("icons/%s/%s.png" % [kind, id], kind, id)

func ui(icon_name: String) -> Texture2D:
    return _load("ui/%s.png" % icon_name, "ui", icon_name)

## True if an authored file exists (used by the asset report).
func has_asset(rel: String) -> bool:
    return ResourceLoader.exists(BASE + rel)

# ---------------- Internals ----------------
func _load(rel: String, kind: String, id: String) -> Texture2D:
    if _cache.has(rel):
        return _cache[rel]
    var tex: Texture2D = null
    if ResourceLoader.exists(BASE + rel):
        tex = load(BASE + rel)
    if tex == null:
        tex = _placeholder(kind, id)
    _cache[rel] = tex
    return tex

func _size_for(kind: String) -> int:
    match kind:
        "monsters": return 96
        "constellations", "areas", "dungeons": return 48
        "ui": return 16
        "currencies", "status": return 24
        _: return 32

## Deterministic coloured tile with a small glyph — distinguishes kinds at a glance.
func _placeholder(kind: String, id: String) -> Texture2D:
    var key: String = "%s:%s" % [kind, id]
    if _placeholders.has(key):
        return _placeholders[key]
    var size: int = _size_for(kind)
    var base: Color = PLACEHOLDER_COLOR
    if id != "":
        var hue: float = float(abs(hash(key)) % 360) / 360.0
        base = Color.from_hsv(hue, 0.35, 0.42, 1.0)
    var bytes := PackedByteArray()
    bytes.resize(size * size * 4)
    var r: int = int(base.r * 255.0); var g: int = int(base.g * 255.0)
    var b: int = int(base.b * 255.0); var a: int = int(base.a * 255.0)
    for i in range(size * size):
        var o: int = i * 4
        bytes[o] = r; bytes[o + 1] = g; bytes[o + 2] = b; bytes[o + 3] = a
    var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes)
    var edge: Color = base.darkened(0.45)
    for x in range(size):
        img.set_pixel(x, 0, edge); img.set_pixel(x, size - 1, edge)
    for y in range(size):
        img.set_pixel(0, y, edge); img.set_pixel(size - 1, y, edge)
    var c: int = floori(size / 2.0)
    var mark: Color = Color(1, 1, 1, 0.85)
    var arm: int = floori(size / 5.0)
    for i in range(arm + 1):
        if c + i < size - 1:
            img.set_pixel(c + i, c, mark)
        if c - i > 0:
            img.set_pixel(c - i, c, mark)
    if kind == "monsters" or kind == "items" or kind == "skills":
        for i in range(arm + 1):
            if c + i < size - 1:
                img.set_pixel(c, c + i, mark)
            if c - i > 0:
                img.set_pixel(c, c - i, mark)
    var tex := ImageTexture.create_from_image(img)
    _placeholders[key] = tex
    return tex
