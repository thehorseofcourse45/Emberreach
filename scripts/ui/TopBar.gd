extends HBoxContainer
class_name TopBar
## TopBar — live GP / Slayer Coins / Prayer Points / combat level + save & pause.

var _gp: Label
var _sc: Label
var _pp: Label
var _cl: Label
var _pause_btn: Button

func _ready() -> void:
    add_theme_constant_override("separation", 18)
    _gp = UIStyle.label("")
    _sc = UIStyle.label("")
    _pp = UIStyle.label("")
    _cl = UIStyle.label("")
    add_child(_currency_icon("gp"))
    add_child(_gp)
    add_child(_currency_icon("slayer_coins"))
    add_child(_sc)
    add_child(_currency_icon("prayer_points"))
    add_child(_pp)
    add_child(_cl)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(spacer)
    _pause_btn = UIStyle.button("Pause")
    _pause_btn.pressed.connect(_on_pause)
    add_child(_pause_btn)
    var save_btn := UIStyle.button("Save")
    save_btn.pressed.connect(func(): SaveManager.save_game())
    add_child(save_btn)

    EventBus.gp_changed.connect(func(_a, _t): _refresh())
    EventBus.slayer_coins_changed.connect(func(_a, _t): _refresh())
    EventBus.prayer_points_changed.connect(func(_t): _refresh())
    EventBus.skill_level_up.connect(func(_s, _l): _refresh())
    _refresh()

func _refresh() -> void:
    _gp.text = "GP: %s" % _fmt(PlayerData.gp)
    _sc.text = "Slayer Coins: %s" % _fmt(PlayerData.slayer_coins)
    _pp.text = "Prayer: %s" % _fmt(PlayerData.prayer_points)
    _cl.text = "Combat Lv: %d" % PlayerData.get_combat_level()

func _on_pause() -> void:
    GameManager.set_paused(not GameManager.is_paused)
    _pause_btn.text = "Resume" if GameManager.is_paused else "Pause"

func _currency_icon(id: String) -> TextureRect:
    var tr := TextureRect.new()
    tr.texture = AssetRegistry.icon("currencies", id)
    tr.custom_minimum_size = Vector2(20, 20)
    tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    return tr

static func _fmt(v: float) -> String:
    if v >= 1_000_000_000.0:
        return "%.2fB" % (v / 1_000_000_000.0)
    if v >= 1_000_000.0:
        return "%.2fM" % (v / 1_000_000.0)
    if v >= 1_000.0:
        return "%.1fK" % (v / 1_000.0)
    return str(int(v))
