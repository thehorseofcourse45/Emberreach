extends Node
## AudioManager — Emberreach's entire soundtrack is synthesized at runtime from
## data/audio.json: the project ships no audio files, so every sound effect and both
## music loops are built as AudioStreamWAV buffers from declarative recipes.
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
##  - Two audio buses ("Music", "SFX") keep the two volume settings independent.

const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"
## One pool player per concurrent effect; the pool cycles, so a burst of item pickups
## overlaps a few sounds instead of cutting each other off.
const SFX_PLAYERS: int = 8
const SAMPLE_RATE: int = 22050

var _sfx_cache: Dictionary = {}          # sound id -> AudioStreamWAV
var _music_cache: Dictionary = {}        # track id -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _music_player: AudioStreamPlayer
var _last_played_ms: Dictionary = {}     # throttle key -> Time.get_ticks_msec()
var _current_music: String = ""
var _started: bool = false

func _ready() -> void:
	_ensure_buses()
	for i in range(SFX_PLAYERS):
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = BUS_MUSIC
	add_child(_music_player)
	# Wiring is cheap and needs no audio device, so it always happens. Music startup is
	# gated inside set_music, because MainUI sets cli_mode AFTER autoloads initialise.
	_wire_data_events()
	EventBus.state_refreshed.connect(_on_state_refreshed)
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

## Switch the looping background track. Same track twice is a no-op.
## Gated on cli_mode: verification runs never pay the music synthesis cost, and their
## screenshots need no soundtrack. One-shot effects still play (headless uses a dummy
## audio driver), which lets tests exercise the throttle and volume logic for real.
func set_music(track_id: String) -> void:
	if GameManager.cli_mode:
		return
	if track_id == _current_music and _music_player.playing:
		return
	var stream: AudioStreamWAV = music_stream(track_id)
	if stream == null:
		return
	_current_music = track_id
	_music_player.stream = stream
	if float(PlayerData.settings.get("music_volume", 60.0)) > 0.0:
		_music_player.play()

## Push both volume settings onto their buses. Called at boot, on load and whenever
## the Settings sliders move.
func apply_volumes() -> void:
	_set_bus_volume(BUS_MUSIC, float(PlayerData.settings.get("music_volume", 60.0)))
	_set_bus_volume(BUS_SFX, float(PlayerData.settings.get("sfx_volume", 80.0)))

func music_track() -> String:
	return _current_music

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

## The looping stream for a music track id, or null when the recipe is missing/invalid.
func music_stream(track_id: String) -> AudioStreamWAV:
	if _music_cache.has(track_id):
		return _music_cache[track_id]
	var recipe: Variant = _audio_data().get("music", {}).get(track_id)
	if typeof(recipe) != TYPE_DICTIONARY:
		return null
	var stream := _synth_music(recipe as Dictionary)
	if stream != null:
		_music_cache[track_id] = stream
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

## Looping music recipe -> PCM of exactly `chords.size() * pattern.size()` steps, so the
## loop point lands on a beat and wraps seamlessly.
static func _synth_music(recipe: Dictionary) -> AudioStreamWAV:
	var chords: Array = recipe.get("chords", [])
	var pattern: Array = recipe.get("pattern", [])
	if chords.is_empty() or pattern.is_empty():
		return null
	var rate: int = clampi(int(recipe.get("rate", 22050)), 8000, 48000)
	var root_hz: float = maxf(20.0, float(recipe.get("root_hz", 220.0)))
	var bpm: float = clampf(float(recipe.get("bpm", 100.0)), 30.0, 300.0)
	var lead_wave: String = str(recipe.get("wave", "triangle"))
	var bass_wave: String = str(recipe.get("bass_wave", "sine"))
	var lead_gain: float = clampf(float(recipe.get("lead_gain", 0.45)), 0.0, 1.0)
	var bass_gain: float = clampf(float(recipe.get("bass_gain", 0.5)), 0.0, 1.0)
	var step_seconds: float = 60.0 / bpm / 2.0   # eighth notes
	var steps: int = chords.size() * pattern.size()
	var frames: int = int(float(steps) * step_seconds * float(rate))
	if frames <= 0:
		return null
	var pcm := PackedFloat32Array()
	pcm.resize(frames)
	for s in range(steps):
		var bar: int = s / pattern.size()
		var chord: Array = chords[clampi(bar, 0, chords.size() - 1)]
		if chord.is_empty():
			continue
		var degree: int = int(pattern[s % pattern.size()]) % chord.size()
		var lead_hz: float = root_hz * pow(2.0, float(chord[degree]) / 12.0)
		_note_into(pcm, rate, float(s) * step_seconds, step_seconds * 0.92,
			lead_hz, lead_wave, lead_gain)
		# Bass holds the chord root for the whole step, one octave down.
		var bass_hz: float = maxf(20.0, root_hz * pow(2.0, float(chord[0]) / 12.0) * 0.5)
		_note_into(pcm, rate, float(s) * step_seconds, step_seconds * 0.98,
			bass_hz, bass_wave, bass_gain)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	# Every note envelope starts and ends at zero amplitude, so the seam (last step ->
	# first step) is already click-free — no fade needed, and a fade would audibly dip
	# the volume once per loop.
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	stream.data = _pcm_to_bytes(pcm)
	return stream

## Add one enveloped note into an existing PCM buffer.
static func _note_into(pcm: PackedFloat32Array, rate: int, at_seconds: float,
		duration: float, freq: float, wave: String, gain: float) -> void:
	var frames: int = pcm.size()
	var from: int = int(at_seconds * float(rate))
	var count: int = maxi(1, int(duration * float(rate)))
	var phase: float = 0.0
	for i in range(count):
		var idx: int = from + i
		if idx < 0 or idx >= frames:
			continue
		phase += TAU * freq / float(rate)
		var env: float = _attack_release(float(i) / float(rate), duration)
		pcm[idx] += _wave(wave, phase) * env * gain

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
	# Background music follows combat, straight from data.
	var music_events: Dictionary = _audio_data().get("music_events", {})
	for signal_name in music_events.keys():
		if not EventBus.has_signal(str(signal_name)):
			continue
		var track_id: String = str(music_events[signal_name])
		var mus_name: String = str(signal_name)
		EventBus.connect(mus_name, func(_a = null, _b = null, _c = null, _d = null):
			set_music(track_id))
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

## The first state refresh of a session starts the ambient track.
func _on_state_refreshed() -> void:
	if _started:
		return
	_started = true
	set_music("explore")

func _on_game_loaded() -> void:
	apply_volumes()
	if not _started:
		_started = true
		set_music("explore")

func _set_bus_volume(bus_name: String, volume_100: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v: float = clampf(volume_100, 0.0, 100.0)
	AudioServer.set_bus_mute(idx, v <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 1.0) / 100.0))

func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
