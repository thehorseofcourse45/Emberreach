extends VBoxContainer
## SkillList — left sidebar. One button per skill (combat first, then non-combat),
## with a level and a filter box. Emits skill_chosen(skill_id).

signal skill_chosen(skill_id: String)

var _list: VBoxContainer
var _filter: LineEdit

func _ready() -> void:
    add_theme_constant_override("separation", 6)
    add_child(UIStyle.title("Skills", 16))
    _filter = LineEdit.new()
    _filter.placeholder_text = "Filter skills…"
    _filter.text_changed.connect(func(_t): _rebuild())
    add_child(_filter)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(scroll)
    _list = VBoxContainer.new()
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_list)
    EventBus.skill_level_up.connect(func(_s, _l): _rebuild())
    _rebuild()

func _rebuild() -> void:
    for c in _list.get_children():
        c.queue_free()
    var q: String = _filter.text.to_lower().strip_edges()
    var ids: Array[String] = DataLoader.get_skill_ids()
    # Explicit canonical order (combat first, then non-combat) from the skill data.
    ids.sort_custom(func(a, b):
        var oa: int = int(DataLoader.get_skill(a).get("order", 999))
        var ob: int = int(DataLoader.get_skill(b).get("order", 999))
        if oa == ob:
            return a < b
        return oa < ob)
    for section in [["combat", "Combat"], ["non_combat", "Non-Combat"]]:
        var matching: Array[String] = []
        for skill_id in ids:
            var s: Dictionary = DataLoader.get_skill(skill_id)
            if s.get("category", "") != section[0]:
                continue
            var nm: String = s.get("name", skill_id)
            if q != "" and not (nm.to_lower().contains(q) or skill_id.contains(q)):
                continue
            matching.append(skill_id)
        if matching.is_empty():
            continue
        var header := UIStyle.label("%s  (%d)" % [section[1], matching.size()], true, 13)
        header.add_theme_color_override("font_color", UIStyle.ACCENT)
        _list.add_child(header)
        for skill_id in matching:
            var s2: Dictionary = DataLoader.get_skill(skill_id)
            var b := UIStyle.button("%s  Lv %d" % [s2.get("name", skill_id), PlayerData.get_level(skill_id)])
            b.icon = AssetRegistry.skill_icon(skill_id)
            b.add_theme_constant_override("icon_max_width", 20)
            b.alignment = HORIZONTAL_ALIGNMENT_LEFT
            b.pressed.connect(func(): skill_chosen.emit(skill_id))
            _list.add_child(b)
