extends RefCounted
## Recorded one-shot samples for the generators (docs/GAMES.md, "Sampled instruments"): CC0
## drums and instrument tones under `res://audio/samples/` (listed in `assets/SOURCES.md`).
## MusicGen mixes drum hits as they are and plays instrument tones at any pitch
## (`Dsp.render_sampled_note`).
##
## Samples are imported as uncompressed 16-bit WAV (`compress/mode=0` in their .import files),
## because QOA-compressed data can't be decoded from GDScript. Each is decoded once to mono
## floats at `Dsp.SR` and cached. `warm()` loads them on the main thread before threaded renders.

const Dsp := preload("res://audio/Dsp.gd")

static var _cache := {}  # path -> {data: PackedFloat32Array, loop_start, loop_end}
static var _mutex := Mutex.new()


## The sample at `path` as mono floats at Dsp.SR, or an empty array if it can't be read.
static func data(path: String) -> PackedFloat32Array:
	return entry(path).get("data", PackedFloat32Array())


## {data, loop_start, loop_end}: the loop is a steady stretch for sustaining a held note,
## between two rising zero crossings.
static func entry(path: String) -> Dictionary:
	_mutex.lock()
	var cached: Dictionary = _cache.get(path, {})
	_mutex.unlock()
	if not cached.is_empty():
		return cached
	var decoded := _decode(path)
	_mutex.lock()
	_cache[path] = decoded
	_mutex.unlock()
	return decoded


## Loads every path now (main thread), so worker-thread renders only read the cache.
static func warm(paths: Array) -> void:
	for path in paths:
		entry(str(path))


static func _decode(path: String) -> Dictionary:
	var wav := load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
	if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS:
		push_warning("Samples: %s is missing or not 16-bit PCM (set compress/mode=0)" % path)
		return {"data": PackedFloat32Array(), "loop_start": 0, "loop_end": 0}
	var bytes := wav.data
	var channels := 2 if wav.stereo else 1
	var frames := bytes.size() / (2 * channels)
	var src := PackedFloat32Array()
	src.resize(frames)
	for i in frames:
		var v := 0.0
		for c in channels:
			v += bytes.decode_s16((i * channels + c) * 2) / 32768.0
		src[i] = v / channels
	var out := src
	if wav.mix_rate != Dsp.SR:
		# Linear resampling to the generator's rate.
		var ratio := float(wav.mix_rate) / Dsp.SR
		var n := int(frames / ratio)
		out = PackedFloat32Array()
		out.resize(n)
		for i in n:
			var x := i * ratio
			var j := int(x)
			var f := x - j
			out[i] = src[j] * (1.0 - f) + src[mini(j + 1, frames - 1)] * f
	var loop_start := _rising_zero(out, int(out.size() * 0.3))
	var loop_end := _rising_zero(out, int(out.size() * 0.85))
	if loop_end <= loop_start + 64:
		loop_start = 0
		loop_end = out.size()
	return {"data": out, "loop_start": loop_start, "loop_end": loop_end}


static func _rising_zero(buf: PackedFloat32Array, from: int) -> int:
	for i in range(maxi(1, from), buf.size()):
		if buf[i - 1] < 0.0 and buf[i] >= 0.0:
			return i
	return from
