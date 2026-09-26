extends VBoxContainer
## SkillPanel — centre panel for one skill: level/XP, mastery pool, the action list
## (locked actions greyed out), the selected action's details, a live progress bar,
## and XP/hour. Drives SkillManager.

var skill_id: String = ""
var _selected_action: String = ""

var _header: Label
var _xp_line: Label
var _progress: ProgressBar
var _node_line: Label
var _pool_line: Label
var _detail: Label
var _start_btn: Button
var _rate_line: Label
var _actions_box: VBoxContainer

var _last_xp: float = 0.0
var _rate_window: float = 0.0
var _rate_xp: float = 0.0
var _xp_per_hour: float = 0.0

func _ready() -> void:
    add_theme_constant_override("separation", 8)
    _header = UIStyle.title("Select a skill", 18)
    add_child(_header)
    _xp_line = UIStyle.label("", true)
    add_child(_xp_line)
    _pool_line = UIStyle.label("", true)
    add_child(_pool_line)
    _progress = ProgressBar.new()
    _progress.max_value = 100.0
    _progress.show_percentage = false
    _progress.custom_minimum_size = Vector2(0, 14)
    add_child(_progress)
    _node_line = UIStyle.label("", true)
    add_child(_node_line)
    _rate_line = UIStyle.label("", true)
    add_child(_rate_line)

    _detail = UIStyle.label("Choose an action below.", true)
    add_child(_detail)
    _start_btn = UIStyle.button("Start")
    _start_btn.pressed.connect(_on_start_stop)
    add_child(_start_btn)

    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(scroll)
    _actions_box = VBoxContainer.new()
    _actions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_actions_box)

    EventBus.action_tick.connect(_on_action_tick)
    EventBus.action_completed.connect(func(_s, _a, _r): _refresh_rate())
    EventBus.action_started.connect(func(_s, _a): _sync_button())
    EventBus.action_stopped.connect(func(_s, _a): _sync_button())
    EventBus.skill_level_up.connect(func(s, _l): if s == skill_id: refresh())

func set_skill(p_skill_id: String) -> void:
    skill_id = p_skill_id
    _selected_action = ""
    refresh()

func refresh() -> void:
    if skill_id == "":
        return
    var s: Dictionary = DataLoader.get_skill(skill_id)
    var lvl: int = PlayerData.get_level(skill_id)
    _header.text = "%s — Level %d" % [s.get("name", skill_id), lvl]
    var xp: float = PlayerData.get_xp(skill_id)
    var to_next: int = XPTable.xp_to_next_level(xp, lvl)
    _xp_line.text = "XP %s  ·  %s to next level" % [TopBar._fmt(xp), TopBar._fmt(float(to_next))]
    _progress.value = XPTable.level_progress(xp, lvl) * 100.0
    _pool_line.text = "Mastery pool: %.1f%%" % MasteryManager.get_pool_percent(skill_id)
    _rebuild_actions()
    _sync_button()
    _refresh_rate(true)

func _rebuild_actions() -> void:
    for c in _actions_box.get_children():
        c.queue_free()
    for a in DataLoader.get_skill_actions(skill_id):
        var aid: String = a.get("id", "")
        var lvl_req: int = int(a.get("level_required", 1))
        var unlocked: bool = PlayerData.get_level(skill_id) >= lvl_req
        var mlevel: int = MasteryManager.get_level(skill_id, aid)
        var text: String = "%s  ·  Lv %d  ·  Mastery %d" % [a.get("name", aid), lvl_req, mlevel]
        var b := UIStyle.button(text)
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.disabled = not unlocked
        b.pressed.connect(func(): _select_action(aid))
        _actions_box.add_child(b)

func _select_action(action_id: String) -> void:
    _selected_action = action_id
    var a: Dictionary = DataLoader.get_action(skill_id, action_id)
    var parts: Array[String] = []
    parts.append("Interval %.2fs" % ModifierManager.get_interval(skill_id, float(a.get("base_interval", 3.0))))
    parts.append("XP %d" % int(a.get("base_xp", 0)))
    if a.has("input_items") and not a["input_items"].is_empty():
        parts.append("In: %s" % _dict_str(a["input_items"]))
    if a.has("output_items") and not a["output_items"].is_empty():
        parts.append("Out: %s" % _dict_str(a["output_items"]))
    _detail.text = "%s — %s" % [a.get("name", action_id), ", ".join(parts)]

func _dict_str(d: Dictionary) -> String:
    var out: Array[String] = []
    for k in d.keys():
        out.append("%s×%s" % [k, str(d[k])])
    return ", ".join(out)

func _on_start_stop() -> void:
    if _selected_action == "":
        return
    if SkillManager.running and SkillManager.active_skill == skill_id and SkillManager.active_action_id == _selected_action:
        SkillManager.stop_action()
    else:
        SkillManager.start_action(skill_id, _selected_action)
    _sync_button()

func _sync_button() -> void:
    var active: bool = SkillManager.running and SkillManager.active_skill == skill_id and SkillManager.active_action_id == _selected_action
    _start_btn.text = "Stop" if active else "Start"

func _on_action_tick(s: String, _a: String, progress: float) -> void:
    if s == skill_id:
        _progress.value = clampf(progress, 0.0, 1.0) * 100.0

func _refresh_rate(force := false) -> void:
    var xp: float = PlayerData.get_xp(skill_id)
    _rate_xp += maxf(0.0, xp - _last_xp)
    _last_xp = xp
    _rate_window += get_process_delta_time() if Engine.is_in_physics_frame() else 0.0
    if force:
        return
    # approximate: recompute XP/hour using a rolling window updated in _process
    _rate_line.text = "≈ %s XP / hour" % TopBar._fmt(_xp_per_hour)

func _process(delta: float) -> void:
    if skill_id == "":
        return
    var xp: float = PlayerData.get_xp(skill_id)
    _rate_xp += maxf(0.0, xp - _last_xp)
    _last_xp = xp
    _rate_window += delta
    if _rate_window >= 5.0:
        _xp_per_hour = _rate_xp / _rate_window * 3600.0
        _rate_xp = 0.0
        _rate_window = 0.0
        _rate_line.text = "≈ %s XP / hour" % TopBar._fmt(_xp_per_hour)
    if SkillManager.running and SkillManager.active_skill == skill_id:
        _progress.value = clampf(SkillManager.progress / maxf(SkillManager.current_interval, 0.001), 0.0, 1.0) * 100.0
    if SkillManager.is_node_based() and SkillManager.active_skill == skill_id:
        _node_line.text = "Node HP: %d / %d" % [SkillManager.node_hp, SkillManager.node_max_hp]
    else:
        _node_line.text = ""
