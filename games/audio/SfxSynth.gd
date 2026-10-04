class_name SfxSynth
extends RefCounted
## Sound effects generated in code (#36): renders SfxPreset resources to AudioStreamWAVs,
## once each, and caches them. Written for this repo; no recorded samples.
##
## The starter library lives in `res://audio/sfx/<name>.tres`. A game extends it with its own
## presets, either as files in its own folder or in code:
##
##   SfxSynth.add_preset_dir("res://games/dodge_ball/sfx")
##   SfxSynth.add_preset("launch_whoosh", preset)
##
## Games normally play effects by name through AudioDirector (`play_sfx("whoosh")`), which asks
## `SfxSynth.stream(name)` the first time (see Cues.gd).

const Dsp := preload("res://audio/Dsp.gd")
const LIBRARY_DIR := "res://audio/sfx"

static var _dirs: Array[String] = [LIBRARY_DIR]
static var _presets := {}  # name -> SfxPreset, added in code
static var _streams := {}  # name -> AudioStreamWAV
static var _mutex := Mutex.new()


## The rendered effect for a preset name, or null when no preset has that name. Rendered on
## first use and cached.
static func stream(sound: String) -> AudioStreamWAV:
	_mutex.lock()
	var cached: AudioStreamWAV = _streams.get(sound)
	_mutex.unlock()
	if cached:
		return cached
	var p := preset(sound)
	if p == null:
		return null
	var wav := render(p)
	_mutex.lock()
	_streams[sound] = wav
	_mutex.unlock()
	return wav


## The preset for a name: one added in code, else `<dir>/<name>.tres` from the preset dirs
## (newest dir first), else null.
static func preset(sound: String) -> SfxPreset:
	if _presets.has(sound):
		return _presets[sound]
	for i in range(_dirs.size() - 1, -1, -1):
		var path := "%s/%s.tres" % [_dirs[i], sound]
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is SfxPreset:
				return res
	return null


static func add_preset(sound: String, p: SfxPreset) -> void:
	_presets[sound] = p
	_forget(sound)


## Adds a folder of `<name>.tres` presets; later folders win over earlier ones.
static func add_preset_dir(dir: String) -> void:
	dir = dir.trim_suffix("/")
	if not _dirs.has(dir):
		_dirs.append(dir)
		_mutex.lock()
		_streams.clear()
		_mutex.unlock()


## Every preset name available, sorted.
static func names() -> PackedStringArray:
	var found := {}
	for dir in _dirs:
		for file in ResourceLoader.list_directory(dir):
			# Exported builds list text resources as "<name>.tres.remap".
			file = file.trim_suffix(".remap")
			if file.ends_with(".tres"):
				found[file.get_basename()] = true
	for sound in _presets:
		found[sound] = true
	var list := PackedStringArray(found.keys())
	list.sort()
	return list


static func clear_cache() -> void:
	_mutex.lock()
	_streams.clear()
	_mutex.unlock()


static func _forget(sound: String) -> void:
	_mutex.lock()
	_streams.erase(sound)
	_mutex.unlock()


## Renders a preset to a 22.05 kHz mono stream (looping if the preset loops).
static func render(p: SfxPreset) -> AudioStreamWAV:
	return Dsp.to_wav(render_samples(p), p.loop)


## Renders a preset to float samples. Deterministic: the same preset always gives the same
## samples. A one-shot starts and ends at zero; a loop joins its end to its start.
static func render_samples(p: SfxPreset) -> PackedFloat32Array:
	var sr := Dsp.SR
	var one := _render_once(p, p.sustain + (0.05 if p.loop else 0.0))
	if p.loop:
		return _close_loop(one, int(p.sustain * sr))
	if p.repeats <= 1:
		return one
	var gap := int(p.repeat_gap * sr)
	var out := PackedFloat32Array()
	out.resize(gap * (p.repeats - 1) + one.size())
	for r in p.repeats:
		Dsp.mix_into(out, one, r * gap, 1.0)
	return out


static func _render_once(p: SfxPreset, sustain: float) -> PackedFloat32Array:
	var sr := Dsp.SR
	var attack := 0 if p.loop else int(p.attack * sr)
	var hold := int(sustain * sr)
	var decay := 0 if p.loop else maxi(1, int(p.decay * sr))
	var n := maxi(1, attack + hold + decay)
	var out := PackedFloat32Array()
	out.resize(n)

	var wave := int(p.wave)
	var is_noise := wave == Dsp.Wave.NOISE
	var table := Dsp.noise() if is_noise else Dsp.table(wave, maxf(p.freq_start, p.freq_end) * maxf(1.0, p.jump_ratio))
	var noise := Dsp.noise()
	var noise_mix := 0.0 if is_noise else p.noise_mix
	var tone_mix := 1.0 - noise_mix
	var table_size := float(table.size())
	var sweep_n := float(int(p.sweep_time * sr) if p.sweep_time > 0.0 else n)
	var jump_at := int(p.jump_time * sr) if p.jump_ratio != 1.0 else n + 1
	var ratio := p.freq_end / p.freq_start
	var lp_on := p.lowpass_start > 0.0 or p.lowpass_end > 0.0
	var lp_a := 1.0
	var hp_a := Dsp.lp_coef(p.highpass) if p.highpass > 0.0 else 0.0

	var phase := 0.0
	var noise_pos := 0
	var lp := 0.0
	var hp_low := 0.0
	var i := 0
	while i < n:
		var block_end := mini(i + Dsp.BLOCK, n)
		var t := float(i) / sr
		var sweep := minf(1.0, i / sweep_n)
		var freq := p.freq_start * pow(ratio, sweep)
		if i >= jump_at:
			freq *= p.jump_ratio
		if p.vibrato_depth > 0.0:
			freq *= pow(2.0, p.vibrato_depth * sin(TAU * p.vibrato_rate * t) / 12.0)
		var inc := (1.0 if is_noise else freq * table_size / sr)
		if lp_on:
			var cut_start := p.lowpass_start if p.lowpass_start > 0.0 else 11000.0
			var cut_end := p.lowpass_end if p.lowpass_end > 0.0 else cut_start
			lp_a = Dsp.lp_coef(lerpf(cut_start, cut_end, float(i) / n))
		while i < block_end:
			var s: float
			if is_noise:
				s = table[int(phase) & (Dsp.NOISE_SIZE - 1)]
			else:
				s = table[int(phase)] * tone_mix
				if noise_mix > 0.0:
					s += noise[noise_pos] * noise_mix
					noise_pos = (noise_pos + 1) & (Dsp.NOISE_SIZE - 1)
			phase += inc
			if phase >= table_size:
				phase -= table_size
			lp += lp_a * (s - lp)
			var y := lp
			if hp_a > 0.0:
				hp_low += hp_a * (y - hp_low)
				y -= hp_low
			# Envelope: attack, then sustain (with punch), then decay to zero.
			var env: float
			if i < attack:
				env = float(i) / attack
			elif i < attack + hold:
				env = 1.0 + p.punch * (1.0 - float(i - attack) / maxf(1.0, hold))
			else:
				env = 1.0 - float(i - attack - hold) / decay
			out[i] = y * env * p.volume
			i += 1
	if not p.loop:
		Dsp.fade_edges(out, 8, 32)
	return out


## Makes `samples` loop seamlessly at `length` by crossfading the overhang past `length` into
## the start.
static func _close_loop(samples: PackedFloat32Array, length: int) -> PackedFloat32Array:
	length = mini(length, samples.size())
	var fade := mini(samples.size() - length, length / 4)
	for i in fade:
		var w := float(i) / fade
		samples[i] = samples[i] * w + samples[length + i] * (1.0 - w)
	samples.resize(length)
	return samples
