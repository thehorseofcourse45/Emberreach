extends VBoxContainer
## RightPanel — equipment display plus the headline combat stats.

var _equip_box: VBoxContainer
var _stats: Label

const SLOT_NAMES := ["Helmet", "Platebody", "Platelegs", "Boots", "Gloves", "Cape",
    "Amulet", "Ring", "Weapon", "Shield", "Quiver", "Summon 1", "Summon 2", "Passive", "Consumable"]

func _ready() -> void:
    add_theme_constant_override("separation", 6)
    add_child(UIStyle.title("Equipment", 16))
    _equip_box = VBoxContainer.new()
    add_child(_equip_box)
    _stats = UIStyle.label("", true)
    add_child(_stats)
    add_child(UIStyle.title("Combat stats", 16))
    _stats.text = ""
    EventBus.item_equipped.connect(func(_s, _i): _rebuild())
    EventBus.item_unequipped.connect(func(_s, _i): _rebuild())
    EventBus.gp_changed.connect(func(_a, _t): _rebuild())
    _rebuild()

func _rebuild() -> void:
    for c in _equip_box.get_children():
        c.queue_free()
    for i in range(SLOT_NAMES.size()):
        var item_id: String = EquipmentManager.get_equipped(i)
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 6)
        var tr := TextureRect.new()
        tr.texture = AssetRegistry.icon("slots", SLOT_NAMES[i].to_lower().replace(" ", "_"))
        tr.custom_minimum_size = Vector2(22, 22)
        tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        row.add_child(tr)
        var item_name: String = DataLoader.get_item(item_id).get("name", "—") if item_id != "" else "—"
        row.add_child(UIStyle.label("%s: %s" % [SLOT_NAMES[i], item_name], item_id == ""))
        _equip_box.add_child(row)
    _stats.text = "Max hit: %d  ·  DR: %.1f%%\nAcc(bonus): %d  ·  Attack: %.2fs" % [
        _estimate_max_hit(),
        ModifierManager.get_damage_reduction(),
        EquipmentManager.get_attack_bonus("slash"),
        ModifierManager.get_attack_interval(EquipmentManager.get_weapon_attack_speed())]

func _estimate_max_hit() -> int:
    var eff: int = PlayerData.get_level("strength") + ModifierManager.get_hidden_levels("strength")
    return CombatFormulas.max_hit_melee_ranged(PlayerData.game_mode, eff,
        float(EquipmentManager.get_strength_bonus("melee")),
        ModifierManager.get_max_hit_percent("melee"), ModifierManager.get_max_hit_flat("melee"))
