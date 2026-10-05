extends Node
## AudioManager — Emberreach's entire soundtrack is synthesized at runtime from
## data/audio.json: the project ships no audio files, so every sound effect is
## built as an AudioStreamWAV buffer from a declarative recipe. There is no music.
##
## Design rules:
##  - Nothing here hardcodes a sound. Events, throttles, tracks and the notification-kind
##    table all come from data/audio.json; volumes come from PlayerData.settings — so
##    adding a sound is a data edit, not a code change.
##  - Sounds are synthesized once, lazily, and cached. Synthesis is pure PCM math over
##    the recipe's tones, so the same recipe always yields the same bytes.
##  - The manager is inert in CLI modes (GameManager.cli_mode): verification runs never
##    open audio devices or pay synthesis cost, and tests can still call the pure
##    synthesis helpers directly.
##  - One audio bus (SFX) carries every effect and its volume setting.

const BUS_SFX: String = "SFX"
## One pool player per concurrent effect; the pool cycles, so a burst of item pickups
## overlaps a few sounds instead of cutting each other off.
const SFX_PLAYERS: int = 8
const SAMPLE_RATE: int = 22050

var _sfx_cache: Dictionary = {}          # sound id -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _last_played_ms: Dictionary = {}     # throttle key -> Time.get_ticks_msec()

func _ready() -> void:
	_ensure_buses()
	for i in range(SFX_PLAYERS):
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_players.append(p)
	_wire_data_events()
	EventBus.game_loaded.connect(_on_game_loaded)
	apply_volumes()

# ==========================================================================
#  Public API
# ==========================================================================

## Play a synthesized sound effect by id. Returns false when the sound is unknown,
## the SFX volume is zero, or the throttle window has not elapsed.
func play_sfx(sound_id: String, throttle_key: String = "", throttle_ms: int = 0) -> bool:
	if SimulationMode.is_silent(): return false
	if str(sound_id) == "":
		return false
	if float(PlayerData.settings.get("sfx_volume", 80.0)) <= 0.0:
		return false
	if throttle_key != "" and throttle_ms > 0:
		var now: int = Time.get_ticks_msec()
		var last: int = int(_last_played_ms.get(throttle_key, -1000000))
		if now - last < throttle_ms:
			return false
		_last_played_ms[throttle_key] = now
	var stream: AudioStreamWAV = sfx_stream(sound_id)
	if stream == null:
		return false
	var player: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.play()
	return true

## Push the SFX volume setting onto its bus. Called at boot, on load and whenever
## the Settings slider moves.
func apply_volumes() -> void:
	_set_bus_volume(BUS_SFX, float(PlayerData.settings.get("sfx_volume", 80.0)))

# ==========================================================================
#  Synthesis (pure; callable from tests without touching playback)
# ==========================================================================

## The synthesized stream for a sound id, or null when the recipe is missing/invalid.
func sfx_stream(sound_id: String) -> AudioStreamWAV:
	if _sfx_cache.has(sound_id):
		return _sfx_cache[sound_id]
	var recipe: Variant = _audio_data().get("sfx", {}).get(sound_id)
	if typeof(recipe) != TYPE_DICTIONARY:
		return null
	var stream := _synth_sfx(recipe as Dictionary)
	if stream != null:
		_sfx_cache[sound_id] = stream
	return stream

## One-shot SFX recipe -> PCM. Tones without an explicit "at" play back to back;
## "at" places a tone at an absolute offset so layers can overlap.
static func _synth_sfx(recipe: Dictionary) -> AudioStreamWAV:
	var tones: Array = recipe.get("tones", [])
	if tones.is_empty():
		return null
	var default_wave: String = str(recipe.get("wave", "sine"))
	var base_gain: float = clampf(float(recipe.get("gain", 0.5)), 0.0, 1.0)
	# Place tones on a timeline first, so "at" and sequential modes share one code path.
	var placed: Array = []
	var cursor: float = 0.0
	for tone in tones:
		if typeof(tone) != TYPE_DICTIONARY:
			continue
		var start: float = float((tone as Dictionary).get("at", cursor))
		var dur: float = maxf(0.02, float((tone as Dictionary).get("dur", 0.1)))
		placed.append({"start": start, "dur": dur, "tone": tone})
		cursor = start + dur
	if placed.is_empty():
		return null
	var total_seconds: float = cursor + 0.05   # tail so the last envelope cannot click
	var frames: int = int(total_seconds * float(SAMPLE_RATE))
	var pcm := PackedFloat32Array()
	pcm.resize(frames)
	for entry in placed:
		var start_s: float = float(entry["start"])
		var dur: float = float(entry["dur"])
		var tone: Dictionary = entry["tone"]
		var freq_start: float = maxf(1.0, float(tone.get("freq", 440.0)))
		var freq_end: float = float(tone.get("freq_end", freq_start))
		var wave: String = str(tone.get("wave", default_wave))
		var gain: float = clampf(float(tone.get("gain", 1.0)), 0.0, 1.0) * base_gain
		var from: int = int(start_s * float(SAMPLE_RATE))
		var count: int = maxi(1, int(dur * float(SAMPLE_RATE)))
		var phase: float = 0.0
		for i in range(count):
			var idx: int = from + i
			if idx < 0 or idx >= frames:
				continue
			var t: float = float(i) / float(count)
			var freq: float = lerpf(freq_start, freq_end, t)
			phase += TAU * freq / float(SAMPLE_RATE)
			var env: float = _attack_release(float(i) / float(SAMPLE_RATE), dur)
			pcm[idx] += _wave(wave, phase) * env * gain
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = _pcm_to_bytes(pcm)
	return stream

## Attack ramp + exponential-ish release: starts and ends each note at zero amplitude
## so neither a note boundary nor the loop seam can produce a click.
static func _attack_release(t: float, duration: float) -> float:
	var attack: float = minf(0.008, duration * 0.25)
	var env: float = 1.0
	if t < attack:
		env = t / maxf(attack, 0.0001)
	var release: float = clampf((t - duration * 0.7) / maxf(duration * 0.3, 0.0001), 0.0, 1.0)
	return env * (1.0 - release) * (1.0 - release)

static func _wave(wave: String, phase: float) -> float:
	match wave:
		"square": return 1.0 if sin(phase) >= 0.0 else -1.0
		"saw": return 2.0 * fposmod(phase / TAU + 0.5, 1.0) - 1.0
		"triangle": return 2.0 * absf(2.0 * fposmod(phase / TAU + 0.25, 1.0) - 1.0) - 1.0
		"noise": return randf() * 2.0 - 1.0
		_: return sin(phase)   # "sine"

static func _pcm_to_bytes(pcm: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(pcm.size() * 2)
	for i in range(pcm.size()):
		var v: float = clampf(pcm[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(round(v * 32767.0)))
	return bytes

# ==========================================================================
#  Wiring
# ==========================================================================

func _audio_data() -> Dictionary:
	return DataLoader.audio

## Connect every event named in data/audio.json. The mapping is data, so a new sound
## never needs a code change here — ContentValidator checks the names resolve.
func _wire_data_events() -> void:
	var events: Dictionary = _audio_data().get("events", {})
	for signal_name in events.keys():
		if not EventBus.has_signal(str(signal_name)):
			continue
		var spec: Dictionary = {}
		var raw: Variant = events[signal_name]
		if typeof(raw) == TYPE_STRING:
			spec = {"sound": str(raw), "throttle_ms": 0}
		elif typeof(raw) == TYPE_DICTIONARY:
			spec = raw
		var sound_id: String = str(spec.get("sound", ""))
		var throttle_ms: int = int(spec.get("throttle_ms", 0))
		var ev_name: String = str(signal_name)   # snapshot: never trust loop-var capture
		EventBus.connect(ev_name, func(_a = null, _b = null, _c = null, _d = null):
			if ev_name in ["skill_level_up", "mastery_level_up", "pet_unlocked"] and not EventBus.toasts_enabled("success"): return
			play_sfx(sound_id, ev_name, throttle_ms))
	# Notification sounds pick by kind (info/success/warn/error).
	EventBus.notification.connect(_on_notification)

func _on_notification(_text: String, kind: String) -> void:
	if not EventBus.toasts_enabled(kind):
		return   # muting a category silences its chime as well as its toast
	var table: Dictionary = _audio_data().get("notification_sounds", {})
	table.erase("_comment")
	var sound_id: String = str(table.get(kind, ""))
	if sound_id != "":
		play_sfx(sound_id, "notification:" + kind, 400)

func _on_game_loaded() -> void:
	apply_volumes()

func _set_bus_volume(bus_name: String, volume_100: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v: float = clampf(volume_100, 0.0, 100.0)
	AudioServer.set_bus_mute(idx, v <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 1.0) / 100.0))

func _ensure_buses() -> void:
	for bus_name in [BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
