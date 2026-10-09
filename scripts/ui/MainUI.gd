extends Control
## MainUI — the application shell.
##
## Layout (desktop):
##   [ status bar: resources · save state · playtime · pause/speed ]
##   [ sidebar nav ] [ workspace (selected screen) ] [ contextual detail pane ]
##   [ persistent activity strip ]
##
## Layout (narrow / mobile):
##   the sidebar collapses to a drawer opened by a Navigation button, the detail pane moves
##   underneath the workspace, and the activity strip stays pinned at the bottom where it
##   cannot cover a control. Panels are built with containers only, so nothing overflows
##   horizontally at any width.
##
## This file also owns the headless verification entry points (`--validate`, `--tests`,
## `--smoke`, `--selftest`, `--offline N`), so one command surface covers the whole project.

const SidebarNav = preload("res://scripts/ui/SidebarNav.gd")

var _root: VBoxContainer
var _status_bar: Control
var _body: HBoxContainer
var _sidebar_wrap: PanelContainer
var _sidebar_list: VBoxContainer
var _sidebar_scroll: ScrollContainer
var _workspace: PanelContainer
var _detail_wrap: PanelContainer
var _detail: DetailPanel
var _strip: ActivityStrip
var _toasts: ToastStack
var _nav_button: Button
var _drawer: PanelContainer
var _recovery_panel: Control
var _accent_fx: Control
var _accent_bar: ColorRect

var _screen: String = Screens.OVERVIEW
var _context: Dictionary = {}
var _panels: Dictionary = {}        # screen -> Control
var _nav_buttons: Dictionary = {}   # screen -> Button
var _skill_nav_buttons: Dictionary = {}  # skill_id -> Button
var _unlock_badges: Dictionary = {}  # screen -> int
var _compact: bool = false
var _medium: bool = false
var _boot_refresh_pending: bool = true
## False while a headless CLI mode is running: the shell was never built, so _process must not
## touch the workspace it does not have.
var _shell_built: bool = false
## `--shot <dir>` renders the real window and writes PNGs, then quits. It needs a display, so it is
## the one mode that must NOT be run with --headless: the headless tests cover structure, this
## covers pixels.
var _shot_mode: bool = false
var _shot_dir: String = "res://shots"
## Vertical scroll offset per screen, so leaving a long list and coming back to it does not lose
## the player's place. Keyed by screen id, not by node: the workspace is rebuilt every navigation.
var _scroll_positions: Dictionary = {}

func _ready() -> void:
	# Awaited: _handle_cli() is a coroutine because the --tests/--selftest suites yield across
	# frames. Calling it un-awaited is a parse error, and skipping it entirely would leave a
	# headless run with nothing to quit the tree.
	if await _handle_cli():
		return
	Screens.register(self)
	_build()
	_show_screen(Screens.OVERVIEW, {})
	EventBus.save_status.connect(_on_save_status)
	EventBus.state_refreshed.connect(func(): _refresh_all())
	EventBus.quest_completed.connect(func(_q): _bump_badge(Screens.QUESTS))
	EventBus.achievement_unlocked.connect(func(_a): _bump_badge(Screens.ACHIEVEMENTS))
	EventBus.bank_capacity_changed.connect(func(): _bump_badge(Screens.BANK))
	EventBus.offline_catchup_started.connect(_on_catchup_started)
	EventBus.offline_catchup_finished.connect(func(_s): _on_save_status("ok", "Offline progress restored"))
	get_window().size_changed.connect(_apply_responsive)
	_apply_responsive()
	if _shot_mode:
		_run_screenshot_sweep()

# =========================================================================
#  Build
# =========================================================================

func _build() -> void:
	_shell_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIStyle.build_theme()
	add_child(_build_backdrop())
	_root = UIStyle.vbox(UITokens.SP_3)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_status_bar = load("res://scripts/ui/StatusBar.gd").new()
	_root.add_child(_status_bar)

	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", UITokens.SP_5)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_body)

	_sidebar_wrap = PanelContainer.new()
	_sidebar_wrap.custom_minimum_size = Vector2(UITokens.W_SIDEBAR, 0)
	_sidebar_wrap.add_theme_stylebox_override("panel", UIStyle.surface_box("panel"))
	_body.add_child(_sidebar_wrap)
	var nav := SidebarNav.build(self, _sidebar_wrap)
	_sidebar_list = nav["list"]
	_sidebar_scroll = nav["scroll"]
	_drawer = nav["drawer"]
	_nav_button = nav["nav_button"]
	_nav_buttons = nav["nav_buttons"]
	_skill_nav_buttons = nav["skill_buttons"]
	_accent_fx = nav["accent_fx"]
	_accent_bar = nav["accent_bar"]

	_workspace = PanelContainer.new()
	_workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace.add_theme_stylebox_override("panel", UIStyle.surface_box("panel"))
	_body.add_child(_workspace)

	_detail_wrap = PanelContainer.new()
	_detail_wrap.custom_minimum_size = Vector2(UITokens.W_DETAIL, 0)
	_detail_wrap.add_theme_stylebox_override("panel", UIStyle.surface_box("panel"))
	_body.add_child(_detail_wrap)
	_detail = DetailPanel.new()
	_detail.navigated.connect(func(route): navigate(route))
	_detail_wrap.add_child(_detail)

	_strip = ActivityStrip.new()
	_root.add_child(_strip)

	_toasts = ToastStack.new()
	add_child(_toasts)

	# Loading / blocked states get their own screen instead of a silent failure.
	_recovery_panel = load("res://scripts/ui/panels/RecoveryPanel.gd").new()
	# The sidebar is built from the current levels, but a new game (or save import) can have reset
	# them since. state_refreshed is connected above, before this shell exists, so a reset that
	# happens during construction never reached the nav; relabel once the buttons exist.
	_refresh_nav()
	# The sidebar carries levels ("Timbercraft · Lv 12"), so a level-up relabels its one
	# entry right away. The is_connected guard keeps a rebuilt shell from double-connecting.
	if not EventBus.skill_level_up.is_connected(_on_skill_level_up):
		EventBus.skill_level_up.connect(_on_skill_level_up)

## The night sky the glass panels float over: a radial violet light top-left fading to near-black,
## plus a faint magenta glow bottom-right. Purely decorative and click-through.
func _build_backdrop() -> Control:
	var layer := Control.new()
	layer.name = "Backdrop"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := ColorRect.new()
	base.color = UITokens.BG_DEEP
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(base)
	layer.add_child(_radial_glow(Vector2(0.22, 0.0), Vector2(1.05, 0.95),
		[UITokens.BG_GLOW_A, UITokens.BG_GLOW_B, Color(UITokens.BG_DEEP, 0.0)], [0.0, 0.45, 1.0]))
	var pink := UITokens.ACCENT_PINK
	layer.add_child(_radial_glow(Vector2(0.95, 1.0), Vector2(0.45, 0.45),
		[Color(pink, 0.16), Color(pink, 0.0)], [0.0, 1.0]))
	return layer

func _radial_glow(from: Vector2, to: Vector2, colors: Array, offsets: Array) -> TextureRect:
	var grad := Gradient.new()
	grad.colors = PackedColorArray(colors)
	grad.offsets = PackedFloat32Array(offsets)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = from
	tex.fill_to = to
	tex.width = 512
	tex.height = 512
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect



# =========================================================================
#  Navigation
# =========================================================================

## Public entry point used by Screens.go() and by anything holding a route dictionary.
func navigate(route: Dictionary) -> void:
	var screen: String = str(route.get("screen", _screen))
	if screen == "":
		screen = _screen
	if screen == "skill":
		screen = Screens.SKILLS
	if screen == Screens.SKILLS and str(route.get("skill_id", "")) == "township":
		screen = Screens.SETTLEMENT
	if screen == Screens.SKILLS and str(route.get("skill_id", "")) == "prayer":
		screen = Screens.PRAYERS
	if screen == Screens.COMBAT and CombatManager.is_expedition(str(route.get("area_id", ""))):
		screen = Screens.EXPEDITIONS
	_show_screen(screen, route)

func _show_screen(screen: String, route: Dictionary) -> void:
	# Remember where the outgoing screen was before its workspace is torn down.
	_save_scroll_position()
	_screen = screen
	_context = route
	_clear_workspace()
	# The recovery screen takes over the workspace when a save could not be loaded, so the
	# player is never dropped into a fresh character without being told.
	var panel: Control = _panel_for(screen)
	if panel == null:
		panel = Widgets.empty_state("Nothing here yet",
			"This screen has not been built. Everything else in the game still works.")
	var work := _work_area(panel)
	_workspace.add_child(work)
	Motion.fade_rise(work)
	# A focused route (a specific skill / region / quest) refines the pane it opens.
	if panel.has_method("focus_route"):
		panel.call("focus_route", route)
	_refresh_nav()
	var detail_route: Dictionary = route.duplicate()
	detail_route["screen"] = screen
	_detail.set_context(panel, detail_route)
	_detail_wrap.visible = not _medium
	if _compact:
		_drawer.visible = false
	_restore_scroll_position(work, screen)

## The scroll offset belongs to the screen being left, so it is captured before the swap.
func _save_scroll_position() -> void:
	for c in _workspace.get_children():
		if c is ScrollContainer:
			_scroll_positions[_screen] = float((c as ScrollContainer).scroll_vertical)
			return

## Restored a frame later: a ScrollContainer clamps its offset to the content height, and the
## freshly rebuilt content has no height until layout has run once.
func _restore_scroll_position(work: Control, screen: String) -> void:
	var pos: float = float(_scroll_positions.get(screen, 0.0))
	if pos <= 0.0 or not (work is ScrollContainer):
		return
	var sc: ScrollContainer = work
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = int(pos)

## A screen is a scrolling workspace with an optional fixed header row.
func _work_area(panel: Control) -> Control:
	var scroll := UIStyle.scroll()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.name = "WorkScroll"
	# Screens are cached and reused, so a panel may still be parented to the previous scroll, which
	# is only queue_freed (not yet gone) at this point. Detach it first: otherwise add_child fails
	# and the old scroll, when it finally frees, takes the cached panel down with it — leaving the
	# workspace empty and the cache holding a freed node.
	if panel.get_parent() != null:
		panel.get_parent().remove_child(panel)
	scroll.add_child(panel)
	# Tagged with its screen so the scroll offset can be matched back up in _save/_restore_scroll_position.
	scroll.set_meta("screen", _screen)
	return scroll

func _panel_for(screen: String) -> Control:
	if screen == Screens.RECOVERY:
		if not _panels.has(screen):
			_recovery_panel = load("res://scripts/ui/panels/RecoveryPanel.gd").new()
			_panels[screen] = _recovery_panel
		return _panels[screen]
	if _panels.has(screen):
		return _panels[screen]
	var path: String = "res://scripts/ui/panels/%s.gd" % PANEL_SCRIPTS.get(screen, "")
	if not ResourceLoader.exists(path):
		return null
	var panel: Control = load(path).new()
	if screen == Screens.COMBAT or screen == Screens.EXPEDITIONS:
		panel.set("expeditions_only", screen == Screens.EXPEDITIONS)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if panel.has_signal("navigated"):
		panel.connect("navigated", func(route): navigate(route))
	if panel.has_signal("context_changed"):
		panel.connect("context_changed", func(ctx): _detail.set_inline_context(ctx))
	_panels[screen] = panel
	return panel

const PANEL_SCRIPTS: Dictionary = {
	Screens.OVERVIEW: "OverviewPanel",
	Screens.SKILLS: "SkillsPanel",
	Screens.COMBAT: "CombatPanel",
	Screens.EXPEDITIONS: "CombatPanel",
	Screens.BANK: "BankPanel",
	Screens.ACTION_QUEUE: "ActionQueuePanel",
	Screens.COMBAT_SIMULATOR: "CombatSimulatorPanel",
	Screens.QUESTS: "QuestsPanel",
	Screens.ACHIEVEMENTS: "AchievementsPanel",
	Screens.COLLECTION: "CollectionPanel",
	Screens.STATS: "StatsPanel",
	Screens.SETTLEMENT: "SettlementPanel",
	Screens.PROVISIONER: "ProvisionerPanel",
	Screens.STORE: "GeneralStorePanel",
	Screens.EQUIPMENT: "EquipmentPanel",
	Screens.SETTINGS: "SettingsPanel",
	Screens.PRAYERS: "PrayerPanel",
	Screens.RAIDS: "RaidPanel",
	Screens.FARM: "FarmPanel",
	Screens.PRESTIGE: "PrestigePanel",
	# Not a sidebar tab (it takes over only when a save cannot load), but listed so the smoke
	# check and the layout tests cover it like every other screen.
	Screens.RECOVERY: "RecoveryPanel",
}

func _clear_workspace() -> void:
	# Cached screens are reused across navigations, but they live inside the scroll about to be
	# freed. Detach every cached panel first, or the scroll's teardown destroys the screen you are
	# about to come back to and leaves `_panels` holding a dead node. A dead entry is dropped here
	# too, so the cache heals itself instead of returning a freed instance later.
	for screen_id in _panels.keys():
		var p: Node = _panels[screen_id]
		if not is_instance_valid(p):
			_panels.erase(screen_id)
			continue
		if p.get_parent() != null:
			p.get_parent().remove_child(p)
	for c in _workspace.get_children():
		_workspace.remove_child(c)
		c.queue_free()

func _refresh_nav() -> void:
	var selected_row: Button = null
	for screen in _nav_buttons.keys():
		var b: Button = _nav_buttons[screen]
		var badge: int = int(_unlock_badges.get(screen, 0))
		var label: String = SidebarNav.skill_nav_text("township") if screen == Screens.SETTLEMENT else Screens.label_for(screen)
		b.text = label if badge == 0 else "%s  (%d)" % [label, badge]
		b.tooltip_text = label if badge == 0 else "%s — %d new" % [label, badge]
		var selected: bool = screen == _screen
		if selected:
			selected_row = b
			b.add_theme_stylebox_override("normal", UIStyle.surface_box("raised", true))
			b.add_theme_color_override("font_color", UITokens.TEXT_STRONG)
		else:
			b.add_theme_stylebox_override("normal", UIStyle.surface_box("flat"))
			b.add_theme_color_override("font_color", UITokens.TEXT_MUTED)
	var selected_skill: String = str(_context.get("skill_id", ""))
	if selected_skill == "" and _panels.has(Screens.SKILLS) and is_instance_valid(_panels[Screens.SKILLS]):
		selected_skill = str((_panels[Screens.SKILLS] as Control).get("_skill_id"))
	for skill_id in _skill_nav_buttons.keys():
		var button: Button = _skill_nav_buttons[skill_id]
		button.text = SidebarNav.skill_nav_text(skill_id)
		var selected: bool = (_screen == Screens.SKILLS and skill_id == selected_skill) or (_screen == Screens.PRAYERS and skill_id == "prayer")
		if selected:
			selected_row = button
		button.add_theme_stylebox_override("normal", UIStyle.surface_box("raised" if selected else "flat", selected))
		button.add_theme_color_override("font_color", UITokens.TEXT_STRONG if selected else UITokens.TEXT_MUTED)
	SidebarNav.slide_accent(_accent_fx, _accent_bar, selected_row)

## Sidebar skill labels carry levels, so the one button whose skill just leveled is relabelled
## on the spot instead of rebuilding the whole navigation.
func _on_skill_level_up(skill_id: String, _level: int) -> void:
	var button: Button = _nav_buttons.get(Screens.SETTLEMENT) if skill_id == "township" else _skill_nav_buttons.get(skill_id)
	if button != null and is_instance_valid(button):
		button.text = SidebarNav.skill_nav_text(skill_id)
	if skill_id == "township" and is_instance_valid(_drawer):
		for drawer_button in _drawer.find_children("*", "Button", true, false):
			if drawer_button.text.begins_with("Settlement"):
				drawer_button.text = SidebarNav.skill_nav_text(skill_id)

func _bump_badge(screen: String) -> void:
	if _screen == screen:
		return
	_unlock_badges[screen] = int(_unlock_badges.get(screen, 0)) + 1
	_refresh_nav()

func _clear_badge(screen: String) -> void:
	if _unlock_badges.has(screen):
		_unlock_badges.erase(screen)
		_refresh_nav()

func _refresh_all() -> void:
	for screen in _panels.keys():
		var p: Control = _panels[screen]
		if is_instance_valid(p) and p.has_method("refresh"):
			p.call("refresh")
	_strip.refresh()
	_refresh_nav()

## Rebuild the currently visible panel (used after a save import or a migration).
func rebuild_current() -> void:
	_show_screen(_screen, _context)

# =========================================================================
#  Responsive layout
# =========================================================================

func _apply_responsive() -> void:
	var width: int = int(size.x)
	if width <= 0:
		width = int(get_viewport_rect().size.x)
	apply_layout_for_width(width)

## The responsive rules live here, keyed on a width rather than on the node's own size, so the
## headless layout test can assert what each breakpoint does without a display server.
func apply_layout_for_width(width: int) -> void:
	_compact = width < UITokens.BP_NARROW
	_medium = width < UITokens.BP_MEDIUM
	# Null-safe: the rules are decidable (and tested) without a built shell.
	if _sidebar_wrap == null or _nav_button == null or _detail_wrap == null:
		return
	_sidebar_wrap.visible = not _compact
	_sidebar_wrap.custom_minimum_size = Vector2(UITokens.W_SIDEBAR if not _compact else 0, 0)
	_nav_button.visible = _compact
	_detail_wrap.visible = not _medium
	if _medium:
		# The detail pane is only reachable as part of the workspace on medium and narrow
		# layouts, so the two never fight for horizontal space.
		_detail_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", UITokens.SP_2 if _compact else UITokens.SP_5)
	if _compact:
		SidebarNav.populate_drawer(self, _drawer)

# =========================================================================
#  Status
# =========================================================================

func _on_save_status(kind: String, message: String) -> void:
	if is_instance_valid(_status_bar) and _status_bar.has_method("set_save_state"):
		_status_bar.call("set_save_state", kind, message)

func _on_catchup_started(seconds: float) -> void:
	_on_save_status("saving", "Restoring %s of offline progress…" % UIStyle.fmt_duration(seconds))

func _process(_delta: float) -> void:
	if not _shell_built:
		return
	if _boot_refresh_pending:
		_boot_refresh_pending = false
		# A failed load takes precedence over the normal overview.
		if SaveManager.last_outcome == SaveManager.LoadOutcome.FAILED or GameManager.boot_state == GameManager.BootState.LOAD_FAILED:
			_show_screen(Screens.RECOVERY, {})
			return
		_show_screen(Screens.OVERVIEW, {})
		add_child(load("res://scripts/ui/OfflineSummaryDialog.gd").new())

# =========================================================================
#  Headless verification entry points
# =========================================================================

func _handle_cli() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	# Verification and screenshot runs drive the singletons themselves. A normal launch must
	# leave deferred boot enabled so GameManager loads the player's save.
	GameManager.cli_mode = false
	for flag in ["--validate", "--tests", "--smoke", "--selftest", "--assetreport",
			"--offline", "--balance", "--shot", "--docs"]:
		if flag in args:
			GameManager.cli_mode = true
			break
	if "--validate" in args:
		_run_validation()
		get_tree().quit()
		return true
	if "--docs" in args:
		var current: bool = _run_docs_check("--fix" in args)
		get_tree().quit(0 if current else 1)
		return true
	if "--tests" in args:
		# Awaited: run_all() is a coroutine (the UI suites build nodes across frames). An
		# un-awaited call would suspend at its first await and get_tree().quit() would then run
		# before the remaining checks ever executed.
		await TestRunner.new().run_all(self)
		get_tree().quit()
		return true
	if "--smoke" in args:
		_run_smoke_checks()
		get_tree().quit()
		return true
	if "--selftest" in args:
		TestRunner.new().run_end_to_end(self)
		get_tree().quit()
		return true
	if "--assetreport" in args:
		_run_asset_report()
		get_tree().quit()
		return true
	if "--offline" in args:
		_run_offline_probe(args)
		get_tree().quit()
		return true
	if "--balance" in args:
		_run_balance_report()
		get_tree().quit()
		return true
	var shot_idx: int = args.find("--shot")
	if shot_idx >= 0:
		# Build the real shell (return false) and let _ready start the sweep over the coming frames.
		_shot_mode = true
		if shot_idx + 1 < args.size() and not str(args[shot_idx + 1]).begins_with("--"):
			_shot_dir = str(args[shot_idx + 1])
		return false
	return false

## Renders the real window at each supported breakpoint and writes a PNG per screen, so layout can
## be reviewed by eye instead of only asserted structurally. Requires a display: do not pass
## --headless. Prints the written paths and quits when done.
func _run_screenshot_sweep() -> void:
	# Screens flip faster than anyone can listen, so capture runs are silent. Muting Master (not the
	# sfx_volume setting) means nothing muted can ever be written to a save.
	AudioServer.set_bus_mute(0, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var widths: Array[int] = [420, 900, 1440]
	var shots: Array[String] = Screens.ORDER.duplicate()
	for w in widths:
		get_window().size = Vector2i(w, 900)
		# Two frames for the resize to propagate through the layout, matching a real window drag.
		await get_tree().process_frame
		await get_tree().process_frame
		for screen_id in shots:
			_show_screen(screen_id, {})
			for _i in 3:
				await get_tree().process_frame
			# Capture after the frame is actually drawn, or the image can be a frame behind.
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			var out: String = "%s/%d_%s.png" % [_shot_dir.trim_suffix("/"), w, screen_id]
			print("shot: %s (%s)" % [out, "ok" if img.save_png(out) == OK else "FAILED"])
		# The Overview's skill sub-tab is a distinct view, not just a different panel, so it gets its
		# own capture: a tab strip that renders but shows an empty card would otherwise look fine.
		var overview: Node = _panels.get(Screens.OVERVIEW)
		if overview != null and is_instance_valid(overview) and overview.has_method("_select_tab"):
			_show_screen(Screens.OVERVIEW, {})
			overview.call("_select_tab", "woodcutting")
			for _i in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var card: Image = get_viewport().get_texture().get_image()
			var card_out: String = "%s/%d_skillcard.png" % [_shot_dir.trim_suffix("/"), w]
			print("shot: %s (%s)" % [card_out, "ok" if card.save_png(card_out) == OK else "FAILED"])
			overview.call("_select_tab", "")
		# The Tasks screen's Rotating tab is a distinct view too: capture it so the countdown
		# and featured cards are covered by the gate, then restore the default difficulty tab.
		var tasks_panel: Node = _panels.get(Screens.QUESTS)
		if tasks_panel != null and is_instance_valid(tasks_panel) and tasks_panel.has_method("_select_tab"):
			# Pin the rotation window for this capture: the featured set and countdown are then
			# identical on every run, instead of flapping across six-hour boundaries.
			Quests.rotation_window_override = 123456
			_show_screen(Screens.QUESTS, {})
			tasks_panel.call("_select_tab", "rotating")
			for _i in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var rot: Image = get_viewport().get_texture().get_image()
			var rot_out: String = "%s/%d_tasks_rotation.png" % [_shot_dir.trim_suffix("/"), w]
			print("shot: %s (%s)" % [rot_out, "ok" if rot.save_png(rot_out) == OK else "FAILED"])
			tasks_panel.call("_select_tab", str(Quests.DIFFICULTIES[0]))
			Quests.rotation_window_override = -1
		if w == 420:
			_show_screen(Screens.SKILLS, {"skill_id": "woodcutting"})
			_drawer.visible = true
			for _i in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var nav: Image = get_viewport().get_texture().get_image()
			var nav_out: String = "%s/420_navigation.png" % _shot_dir.trim_suffix("/")
			print("shot: %s (%s)" % [nav_out, "ok" if nav.save_png(nav_out) == OK else "FAILED"])
			_drawer.visible = false
	print("screenshot sweep complete -> ", _shot_dir)
	get_tree().quit()

## Prints the tuning checks and writes them to res://BALANCE_REPORT.md so a balance question can
## be answered from the repository rather than from memory.
func _run_balance_report() -> void:
	var lines: Array[String] = BalanceReport.format_text()
	for line in lines:
		print(line)
	var f := FileAccess.open("res://BALANCE_REPORT.md", FileAccess.WRITE)
	if f != null:
		f.store_string("```\n" + "\n".join(lines) + "\n```\n")
		f.close()

func _run_validation() -> void:
	var validator := ContentValidator.new()
	var report: Array = validator.validate_all()
	print(validator.format_report(true))
	var f := FileAccess.open("res://VALIDATION_REPORT.md", FileAccess.WRITE)
	if f != null:
		f.store_string(validator.format_report(true))
		f.close()
	EventBus.content_validation_report.emit(report)

func _run_offline_probe(args: PackedStringArray) -> void:
	var seconds: float = 3600.0
	var idx: int = args.find("--offline")
	if idx >= 0 and idx + 1 < args.size():
		seconds = float(args[idx + 1])
	print("=== offline probe: %s ===" % UIStyle.fmt_duration(seconds))
	var summary: Dictionary = OfflineProgression.simulate_synchronously(seconds)
	print("activity: ", summary.get("activity", "none"))
	print("processed: %.1fs  capped: %.1fs" % [float(summary.get("processed_seconds", 0.0)), float(summary.get("capped_seconds", 0.0))])
	print("actions: ", int(summary.get("actions", 0)))
	print("stopped: ", summary.get("stopped_reason", ""))
	print("items gained: ", summary.get("items_gained", {}))
	print("consumed: ", summary.get("items_consumed", {}))
	print("xp: ", summary.get("xp_gained", {}))
	print("combat: ", summary.get("combat", {}))
	print("=== offline probe complete ===")

func _run_asset_report() -> void:
	print("=== asset report ===")
	var groups: Dictionary = {
		"icons/items": DataLoader.items.keys(),
		"icons/skills": DataLoader.skills.keys(),
		"sprites/monsters": DataLoader.monsters.keys(),
		"icons/areas": DataLoader.areas.keys(),
		"icons/dungeons": DataLoader.dungeons.keys(),
		"icons/status": ["idle", "ok", "warning", "danger"],
	}
	var lines: Array[String] = ["# Asset status", ""]
	var present: int = 0
	var total: int = 0
	for g in groups.keys():
		var ids: Array = groups[g]
		var have: int = 0
		for id in ids:
			if AssetRegistry.has_asset("%s/%s.png" % [g, id]):
				have += 1
		present += have
		total += ids.size()
		print("%s: %d / %d present" % [g, have, ids.size()])
		lines.append("| %s | %d | %d |" % [g, have, ids.size()])
	lines.append("")
	lines.append("Authored: **%d / %d**" % [present, total])
	print("assets present: ", present, " / ", total)
	var f := FileAccess.open("res://assets/ASSET_STATUS.md", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()

func _run_smoke_checks() -> void:
	print("=== Emberreach smoke checks ===")
	print("skills loaded: ", DataLoader.skills.size())
	print("items loaded: ", DataLoader.items.size())
	print("monsters loaded: ", DataLoader.monsters.size())
	print("dungeons loaded: ", DataLoader.dungeons.size())
	print("quests loaded: ", Quests.count())
	print("achievements loaded: ", Achievements.count())
	print("XP lvl 99: ", XPTable.xp_for_level(99), " (expect 13034431)")
	print("XP lvl 120: ", XPTable.xp_for_level(120), " (expect 104273167)")
	print("hit chance equal ratings: ", CombatFormulas.chance_to_hit(100.0, 100.0), " (expect 50)")
	print("combat level fresh char: ", PlayerData.get_combat_level(), " (expect 1)")
	print("save version: ", SaveManager.SAVE_VERSION)

# =========================================================================
#  README drift check (--docs, --docs --fix)
# =========================================================================
#
# The docs rot the same way every time: a content pass lands, the managers and screens grow, and
# the hand-written token counts and system tables in README.md keep describing the previous build.
# Two guards, both cheap: the counts live in ONE generated block that --fix rewrites, and every
# autoload and screen must at least be *named* in the README, so the systems list cannot silently
# come up short. Prose is deliberately not scanned — a number that is not written down cannot rot.

const DOC_PATH: String = "res://README.md"
const DOC_BLOCK_START: String = "<!-- doc-facts:start -->"
const DOC_BLOCK_END: String = "<!-- doc-facts:end -->"

## Label/value rows, derived from the live singletons. One list feeds both the generated block and
## the comparison, so they cannot disagree.
func _doc_facts() -> Array:
	var combat: int = 0
	var actions: int = 0
	for id in DataLoader.skills.keys():
		var skill: Dictionary = DataLoader.skills[id]
		if str(skill.get("category", "")) == "combat":
			combat += 1
		actions += (skill.get("actions", []) as Array).size()
	var autoloads: int = 0
	for prop in ProjectSettings.get_property_list():
		if str(prop.get("name", "")).begins_with("autoload/"):
			autoloads += 1
	return [
		["Skills", "%d (%d combat / %d non-combat)" % [DataLoader.skills.size(), combat, DataLoader.skills.size() - combat]],
		["Skill actions", str(actions)],
		["Items", str(DataLoader.items.size())],
		["Monsters", str(DataLoader.monsters.size())],
		["Areas", str(DataLoader.areas.size())],
		["Dungeons", str(DataLoader.dungeons.size())],
		["Prayers", str(DataLoader.prayers.size())],
		["Autoload singletons", str(autoloads)],
		["Screens", str(Screens.ORDER.size() + 1)],
	]

func _doc_block() -> String:
	var lines: Array[String] = [DOC_BLOCK_START, "| Check | Value |", "|---|---|"]
	for row: Array in _doc_facts():
		lines.append("| %s | %s |" % [row[0], row[1]])
	lines.append(DOC_BLOCK_END)
	return "\n".join(lines)

## Returns true when the README matches the live build. With `fix`, rewrites the fact block first
## (naming gaps still need a human, since the responsibility text is the thing worth reading).
func _run_docs_check(fix: bool) -> bool:
	var file: FileAccess = FileAccess.open(DOC_PATH, FileAccess.READ)
	if file == null:
		push_error("docs: cannot read %s" % DOC_PATH)
		return false
	var text: String = file.get_as_text()
	file.close()
	var generated: String = _doc_block()
	var start: int = text.find(DOC_BLOCK_START)
	var end: int = text.find(DOC_BLOCK_END)
	if fix and start >= 0 and end > start:
		text = text.substr(0, start) + generated + text.substr(end + DOC_BLOCK_END.length())
		var out: FileAccess = FileAccess.open(DOC_PATH, FileAccess.WRITE)
		if out == null:
			push_error("docs: cannot write %s" % DOC_PATH)
			return false
		out.store_string(text)
		out.close()
		start = text.find(DOC_BLOCK_START)
		end = text.find(DOC_BLOCK_END)
	var stale: Array[String] = []
	if start < 0 or end < start:
		stale.append("no %s / %s block found" % [DOC_BLOCK_START, DOC_BLOCK_END])
	elif text.substr(start, end - start + DOC_BLOCK_END.length()) != generated:
		stale.append("the fact block no longer matches the loaded content")
	for prop in ProjectSettings.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if prop_name.begins_with("autoload/"):
			var singleton: String = prop_name.trim_prefix("autoload/")
			if not text.contains(singleton):
				stale.append("autoload `%s` is never mentioned (add it to the §4 table)" % singleton)
	var screen_ids: Array[String] = Screens.ORDER.duplicate()
	screen_ids.append(Screens.RECOVERY)
	for screen_id in screen_ids:
		var label: String = Screens.label_for(screen_id)
		if not text.contains(label):
			stale.append("screen \"%s\" (%s) is never mentioned (add it to the §5 table)" % [label, screen_id])
	if stale.is_empty():
		print("docs: README.md is current (%s autoloads, %d screens, %d fact rows)" % [
			_doc_facts()[7][1], screen_ids.size(), _doc_facts().size()])
		return true
	print("docs: README.md is stale%s" % (" (block rewritten; naming gaps remain)" if fix else ""))
	for message in stale:
		print("  STALE  " + message)
	if not fix:
		print("--- replacement fact block (run `--docs --fix` to write it) ---")
		print(generated)
	return false
