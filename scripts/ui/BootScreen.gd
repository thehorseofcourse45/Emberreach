extends Control
## Scene loading only: gameplay bootstrap stays paused until the interface is ready.
const MAIN: String = "res://scenes/main.tscn"
const CLI_FLAGS: Array[String] = ["--validate", "--test", "--tests", "--smoke", "--selftest",
	"--assetreport", "--offline", "--balance", "--shot", "--docs"]
var _bar: ProgressBar
var _status: Label
var _percent: Label
var _loading: bool = false
var _autosave_was_enabled: bool
var _major_save_was_enabled: bool
var _paused_was: bool

func _ready() -> void:
	GameManager.cli_mode = true
	for flag: String in CLI_FLAGS:
		if flag in OS.get_cmdline_user_args():
			_open_main.call_deferred(load(MAIN) as PackedScene, false)
			return
	# No simulation or saving may run against the not-yet-loaded character.
	_autosave_was_enabled = SaveManager.autosave_enabled
	_major_save_was_enabled = SaveManager.save_on_major_event
	_paused_was = GameManager.is_paused
	SaveManager.autosave_enabled = false
	SaveManager.save_on_major_event = false
	GameManager.is_paused = true
	_build()
	# Let the splash draw and the original deferred bootstrap observe cli_mode first.
	await get_tree().process_frame
	await get_tree().process_frame
	var error: Error = ResourceLoader.load_threaded_request(MAIN, "PackedScene")
	if error != OK:
		_fail("Could not start loading the interface (%s)." % error_string(error))
		return
	_loading = true

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("0b1220")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.custom_minimum_size.x = minf(520, get_viewport_rect().size.x - 48)
	center.add_child(column)
	var crest := TextureRect.new()
	crest.texture = load("res://assets/ui/emberreach_crest.svg")
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.custom_minimum_size = Vector2(0, 260)
	column.add_child(crest)
	var title := _label("EMBERREACH", 46, Color("f0d59b"))
	if ResourceLoader.exists("res://assets/fonts/ember_display.ttf"):
		title.add_theme_font_override("font", load("res://assets/fonts/ember_display.ttf"))
	column.add_child(title)
	column.add_child(_label("T H E   R I V E N   F R O N T I E R", 13, Color("adbed0")))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	column.add_child(spacer)
	_bar = ProgressBar.new()
	_bar.name = "LoadingProgress"
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 8
	var track := StyleBoxFlat.new()
	track.bg_color = Color("162638")
	track.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ddae64")
	fill.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill)
	column.add_child(_bar)
	var line := HBoxContainer.new()
	column.add_child(line)
	_status = _label("Preparing interface…", 14, Color("adbed0"))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_status)
	_percent = _label("0%", 14, Color("ddae64"))
	line.add_child(_percent)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _process(_delta: float) -> void:
	if not _loading:
		return
	var progress: Array = []
	var state: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(MAIN, progress)
	if not progress.is_empty():
		_bar.value = maxf(_bar.value, float(progress[0]) * 90.0)
		_percent.text = "%d%%" % int(_bar.value)
	if state == ResourceLoader.THREAD_LOAD_LOADED:
		_loading = false
		_bar.value = 90
		_status.text = "Building interface…"
		_percent.text = "90%"
		await get_tree().process_frame
		var packed := ResourceLoader.load_threaded_get(MAIN) as PackedScene
		_open_main(packed, true)
	elif state == ResourceLoader.THREAD_LOAD_FAILED or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_loading = false
		_fail("The interface could not be loaded. Please check the game log.")

func _open_main(packed: PackedScene, bootstrap: bool) -> void:
	if packed == null or not packed.can_instantiate():
		_fail("The interface scene is unavailable. Please check the game log.")
		return
	var main: Node = packed.instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	if bootstrap:
		_bar.value = 100
		_percent.text = "100%"
		SaveManager.autosave_enabled = _autosave_was_enabled
		SaveManager.save_on_major_event = _major_save_was_enabled
		GameManager.is_paused = _paused_was
		GameManager.cli_mode = false
		GameManager.call_deferred("_bootstrap")
	queue_free()

func _fail(message: String) -> void:
	push_error(message)
	if _status != null:
		_status.text = message
		_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_percent.text = ""
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
