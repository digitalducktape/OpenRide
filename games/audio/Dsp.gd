extends RefCounted
## Shared DSP for SfxSynth and MusicGen (#36): wavetables, deterministic noise, a note voice
## and the float → AudioStreamWAV conversion. Written for this repo.
##
## Everything renders mono at 22.05 kHz into PackedFloat32Arrays. The hot loops keep their
## state in typed locals and step the envelope and filter per block, not per sample.
## Tables are built once (`warm()`, on the main thread at startup) and only read afterwards,
## so renders on WorkerThreadPool threads share them safely.

const SR := 22050
const TABLE_SIZE := 2048
const PHASE_BITS := 16  ## fixed-point fraction bits of an oscillator phase
const PHASE_MASK := (TABLE_SIZE << PHASE_BITS) - 1
const NOISE_SIZE := 65536
const BLOCK := 32  ## samples per envelope/filter/vibrato update

enum Wave { SINE, TRIANGLE, SAW, SQUARE, PULSE, NOISE }

## Band-limited tables: band k covers notes up to BAND_TOP_HZ * 2^k, with a harmonic count that
## keeps the top harmonic under about 7 kHz.
const BAND_TOP_HZ := 110.0
const BAND_HARMONICS := [64, 32, 16, 8, 4, 2]

static var _tables := {}  # Wave -> Array[PackedFloat32Array] per band
static var _noise := PackedFloat32Array()
static var _mutex := Mutex.new()
static var _ready := false


## Builds the tables. Cheap after the first call; call it on the main thread before any
## threaded render.
static func warm() -> void:
	if _ready:
		return
	_mutex.lock()
	if not _ready:
		_build()
		_ready = true
	_mutex.unlock()


static func _build() -> void:
	var sine := PackedFloat32Array()
	sine.resize(TABLE_SIZE)
	for i in TABLE_SIZE:
		sine[i] = sin(TAU * i / TABLE_SIZE)
	_tables[Wave.SINE] = [sine]
	var tri := PackedFloat32Array()
	tri.resize(TABLE_SIZE)
	for i in TABLE_SIZE:
		var p := float(i) / TABLE_SIZE
		tri[i] = 4.0 * p - 1.0 if p < 0.5 else 3.0 - 4.0 * p
	_tables[Wave.TRIANGLE] = [tri]
	_tables[Wave.SAW] = _additive(sine, false)
	_tables[Wave.SQUARE] = _additive(sine, true)
	# A 25% pulse: the difference of two saws a quarter cycle apart.
	var pulse_bands := []
	for saw: PackedFloat32Array in _tables[Wave.SAW]:
		var p := PackedFloat32Array()
		p.resize(TABLE_SIZE)
		var shift := TABLE_SIZE / 4
		for i in TABLE_SIZE:
			p[i] = 0.5 * (saw[i] - saw[(i + shift) % TABLE_SIZE])
		pulse_bands.append(p)
	_tables[Wave.PULSE] = pulse_bands
	# White noise from a fixed LCG, so every platform renders the same bits.
	_noise.resize(NOISE_SIZE)
	var state := 22222
	for i in NOISE_SIZE:
		state = (state * 1103515245 + 12345) & 0x7fffffff
		_noise[i] = float(state) / 1073741823.5 - 1.0


static func _additive(sine: PackedFloat32Array, odd_only: bool) -> Array:
	var bands := []
	for harmonics: int in BAND_HARMONICS:
		var t := PackedFloat32Array()
		t.resize(TABLE_SIZE)
		var h := 1
		while h <= harmonics:
			var amp := 1.0 / h
			var step := h
			var idx := 0
			for i in TABLE_SIZE:
				t[i] += sine[idx] * amp
				idx = (idx + step) & (TABLE_SIZE - 1)
			h += 2 if odd_only else 1
		# Normalise to a peak of 1.
		var peak := 0.0
		for i in TABLE_SIZE:
			peak = maxf(peak, absf(t[i]))
		for i in TABLE_SIZE:
			t[i] /= peak
		bands.append(t)
	return bands


## The table for a wave at a pitch (the band that keeps it under Nyquist).
static func table(wave: int, freq: float) -> PackedFloat32Array:
	warm()
	var bands: Array = _tables.get(wave, _tables[Wave.SINE])
	var band := 0
	var top := BAND_TOP_HZ
	while band < bands.size() - 1 and freq > top:
		band += 1
		top *= 2.0
	return bands[band]


static func noise() -> PackedFloat32Array:
	warm()
	return _noise


static func wave_from_name(name: String) -> int:
	match name:
		"sine": return Wave.SINE
		"triangle", "tri": return Wave.TRIANGLE
		"saw": return Wave.SAW
		"square": return Wave.SQUARE
		"pulse": return Wave.PULSE
		"noise": return Wave.NOISE
	return Wave.SINE


static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## One-pole low-pass coefficient for a cutoff in Hz.
static func lp_coef(cutoff_hz: float) -> float:
	return 1.0 - exp(-TAU * clampf(cutoff_hz, 10.0, SR * 0.45) / SR)


## Renders one pitched note additively into `buf` from sample `start`, `length` samples long
## (the release is included in that length). `voice` keys (all optional):
##   wave, wave2 ("" for none): sine | triangle | saw | square | pulse | noise
##   detune (cents, for wave2), octave2 (octaves, for wave2), mix2 (0-1)
##   attack, decay, sustain (level), release (s)
##   cutoff, cutoff_env (Hz added at the start, decaying with filter_decay s)
##   vibrato (semitones), vibrato_rate (Hz), tremolo (0-1), tremolo_rate (Hz), gain
static func render_note(buf: PackedFloat32Array, start: int, length: int, freq: float, velocity: float, voice: Dictionary) -> void:
	var end := mini(start + length, buf.size())
	if end <= start:
		return
	var n := end - start
	var wave := wave_from_name(voice.get("wave", "saw"))
	var wave2_name: String = voice.get("wave2", "")
	var has2 := not wave2_name.is_empty()
	var freq2 := freq * pow(2.0, float(voice.get("detune", 0.0)) / 1200.0 + float(voice.get("octave2", 0.0)))
	var t1: PackedFloat32Array = noise() if wave == Wave.NOISE else table(wave, freq)
	var t2: PackedFloat32Array = t1
	if has2:
		var w2 := wave_from_name(wave2_name)
		t2 = noise() if w2 == Wave.NOISE else table(w2, freq2)
	var mix2: float = float(voice.get("mix2", 0.5)) if has2 else 0.0
	var mix1 := 1.0 - mix2
	var gain: float = float(voice.get("gain", 0.5)) * velocity

	var attack := maxi(8, int(float(voice.get("attack", 0.005)) * SR))
	var decay := maxi(1, int(float(voice.get("decay", 0.1)) * SR))
	var sustain: float = voice.get("sustain", 0.7)
	var release := maxi(16, int(float(voice.get("release", 0.05)) * SR))
	release = mini(release, n / 2)
	var release_at := n - release

	var cutoff: float = voice.get("cutoff", 6000.0)
	var cutoff_env: float = voice.get("cutoff_env", 0.0)
	var filter_decay: float = maxf(0.001, float(voice.get("filter_decay", 0.15)))
	var vib_depth: float = voice.get("vibrato", 0.0)
	var vib_rate: float = voice.get("vibrato_rate", 5.5)
	var trem: float = voice.get("tremolo", 0.0)
	var trem_rate: float = voice.get("tremolo_rate", 4.0)

	# Noise tables are read at a fixed rate; tonal ones at the note's pitch.
	var scale := float(TABLE_SIZE << PHASE_BITS) / SR
	var inc1_base := (float(1 << PHASE_BITS) if wave == Wave.NOISE else freq * scale)
	var inc2_base := freq2 * scale
	var mask1 := ((NOISE_SIZE << PHASE_BITS) - 1) if wave == Wave.NOISE else PHASE_MASK
	var mask2 := PHASE_MASK
	if has2 and wave_from_name(wave2_name) == Wave.NOISE:
		inc2_base = float(1 << PHASE_BITS)
		mask2 = (NOISE_SIZE << PHASE_BITS) - 1
	var p1 := 0
	var p2 := (TABLE_SIZE << PHASE_BITS) / 3  # decorrelate the second oscillator
	var y := 0.0
	var env := 0.0
	var pos := 0
	while pos < n:
		var block_end := mini(pos + BLOCK, n)
		var t := float(pos) / SR
		# Envelope target at the end of this block (linear within the block).
		var env_end: float
		if block_end <= attack:
			env_end = float(block_end) / attack
		elif block_end <= attack + decay:
			env_end = 1.0 - (1.0 - sustain) * float(block_end - attack) / decay
		else:
			env_end = sustain
		if block_end > release_at:
			var rel_start_level := sustain if release_at > attack + decay else (
				float(release_at) / attack if release_at <= attack else
				1.0 - (1.0 - sustain) * float(release_at - attack) / decay)
			env_end = rel_start_level * maxf(0.0, 1.0 - float(block_end - release_at) / release)
		if trem > 0.0:
			env_end *= 1.0 - trem * (0.5 + 0.5 * sin(TAU * trem_rate * t))
		var denv := (env_end - env) / (block_end - pos)
		var a := lp_coef(cutoff + cutoff_env * exp(-t / filter_decay))
		var vib := 1.0
		if vib_depth > 0.0:
			vib = pow(2.0, vib_depth * sin(TAU * vib_rate * t) / 12.0)
		var inc1 := int(inc1_base * (1.0 if wave == Wave.NOISE else vib))
		var inc2 := int(inc2_base * vib)
		var g := env * gain
		var dg := denv * gain
		var i := start + pos
		var i_end := start + block_end
		if has2:
			while i < i_end:
				var s := t1[p1 >> PHASE_BITS] * mix1 + t2[p2 >> PHASE_BITS] * mix2
				p1 = (p1 + inc1) & mask1
				p2 = (p2 + inc2) & mask2
				y += a * (s - y)
				buf[i] += y * g
				g += dg
				i += 1
		else:
			while i < i_end:
				y += a * (t1[p1 >> PHASE_BITS] - y)
				p1 = (p1 + inc1) & mask1
				buf[i] += y * g
				g += dg
				i += 1
		env = env_end
		pos = block_end


## Mixes `src` × gain into `buf` at `offset` (clipped to buf).
static func mix_into(buf: PackedFloat32Array, src: PackedFloat32Array, offset: int, gain: float) -> void:
	var n := mini(src.size(), buf.size() - offset)
	var j := maxi(0, -offset)
	while j < n:
		buf[offset + j] += src[j] * gain
		j += 1


## Fades the first `fade_in` and last `fade_out` samples of `buf` to zero, so any concatenation
## of such buffers is continuous (no clicks at the joins or the loop point).
static func fade_edges(buf: PackedFloat32Array, fade_in: int, fade_out: int) -> void:
	var n := buf.size()
	fade_in = mini(fade_in, n / 2)
	fade_out = mini(fade_out, n / 2)
	for i in fade_in:
		buf[i] *= float(i) / fade_in
	for i in fade_out:
		buf[n - 1 - i] *= float(i) / fade_out


## Mono float samples → 16-bit PCM AudioStreamWAV, converted natively (Godot's WAV loader
## reads 32-bit float WAV data). `loop` sets a forward loop over the whole stream.
static func to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(44)
	bytes.encode_u32(0, 0x46464952)  # "RIFF"
	bytes.encode_u32(4, 36 + n * 4)
	bytes.encode_u32(8, 0x45564157)  # "WAVE"
	bytes.encode_u32(12, 0x20746d66)  # "fmt "
	bytes.encode_u32(16, 16)
	bytes.encode_u16(20, 3)  # IEEE float
	bytes.encode_u16(22, 1)  # mono
	bytes.encode_u32(24, SR)
	bytes.encode_u32(28, SR * 4)
	bytes.encode_u16(32, 4)
	bytes.encode_u16(34, 32)
	bytes.encode_u32(36, 0x61746164)  # "data"
	bytes.encode_u32(40, n * 4)
	bytes.append_array(samples.to_byte_array())
	var wav := AudioStreamWAV.load_from_buffer(bytes, {
		"compress/mode": 0, "edit/trim": false, "edit/normalize": false, "edit/loop_mode": 0,
		"force/mono": false, "force/8_bit": false, "force/max_rate": false,
	})
	if wav == null:
		return null
	set_loop(wav, loop)
	return wav


static func set_loop(wav: AudioStreamWAV, loop: bool) -> void:
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = frames(wav)
	else:
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED


## A 16-bit mono stream from raw PCM bytes (the disk cache's format).
static func wav_from_pcm(pcm: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = pcm
	set_loop(wav, loop)
	return wav


## Frames in a 16-bit mono stream.
static func frames(wav: AudioStreamWAV) -> int:
	return wav.data.size() / 2


## Sample i of a 16-bit mono stream, -1..1 (for tests and analysis).
static func sample(wav: AudioStreamWAV, i: int) -> float:
	return wav.data.decode_s16(i * 2) / 32768.0
