extends VBoxContainer
## ShopPanel — buy upgrades from data/shop.json. Shows cost, ownership and the reason
## a purchase is blocked.

var _list: VBoxContainer

func _ready() -> void:
    add_theme_constant_override("separation", 8)
    add_child(UIStyle.title("Shop", 18))
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(scroll)
    _list = VBoxContainer.new()
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_list)
    EventBus.gp_changed.connect(func(_a, _t): _rebuild())
    EventBus.shop_upgrade_purchased.connect(func(_id): _rebuild())
    _rebuild()

func _rebuild() -> void:
    for c in _list.get_children():
        c.queue_free()
    for upgrade_id in DataLoader.shop.keys():
        var u: Dictionary = DataLoader.get_shop_upgrade(upgrade_id)
        var owned: int = int(PlayerData.shop_upgrades.get(upgrade_id, 0))
        var check: Dictionary = ShopManager.can_buy(upgrade_id)
        var row := HBoxContainer.new()
        var name_text: String = "%s — %s GP" % [u.get("name", upgrade_id), TopBar._fmt(float(u.get("cost", 0)))]
        if owned > 0:
            name_text += "  (owned ×%d)" % owned
        var l := UIStyle.label(name_text, owned > 0)
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(l)
        var b := UIStyle.button("Buy")
        b.disabled = not bool(check["ok"])
        if not bool(check["ok"]):
            b.tooltip_text = str(check["reason"])
        b.pressed.connect(func(): ShopManager.buy(upgrade_id))
        row.add_child(b)
        _list.add_child(row)
