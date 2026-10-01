class_name MusicGen
extends RefCounted
## Generated game music (#36): a seeded composer plus a small synth, written for this repo.
##
## Given a style (MusicStyle), a tempo, a seed and a bar count, it renders four **looping
## stems** (drums, bass, harmony, lead) as 22.05 kHz mono AudioStreamWAVs of exactly the same
## length. AudioDirector plays them in sync (AudioStreamSynchronized) and gates stems by
## intensity; Cues.gd registers `generate` with it.
##
## - **Deterministic:** the same style, seed, tempo and bars always give the same samples. The
##   composition depends on the style and seed only, so a tempo change keeps the same tune.
## - **Form:** phrases of 4 bars, A A' B A over 16 bars, one chord per bar.
## - **Seamless loops:** every bar starts and ends at silence, so the loop point never clicks.
## - **Fast:** a bar that repeats (same notes) is rendered once and copied; the four stems render
##   in parallel on WorkerThreadPool; the float → PCM conversion is native.
## - **Disk cache:** `user://audio_cache/`, keyed by style content + tempo + seed + bars,
##   pruned to 50 MB (oldest first).

const Dsp := preload("res://audio/Dsp.gd")

const STEMS: Array[String] = ["drums", "bass", "harmony", "lead"]
const VERSION := 1  ## bump when the output changes, so old cache files are ignored
const STYLE_DIR := "res://audio/styles"
const CACHE_DIR := "user://audio_cache"
const CACHE_LIMIT_BYTES := 50 * 1024 * 1024
const DEFAULT_BARS := 16
const PHRASE_BARS := 4
const STEPS := 16  ## grid steps per bar (sixteenth notes in 4/4)
const BEATS_PER_BAR := 4
const TEMPO_MIN := 30.0
const TEMPO_MAX := 240.0
const FADE_IN := 16  ## samples faded in at each bar start
const FADE_OUT := 48  ## samples faded out at each bar end
## Each stem's peak after normalising (× the style's loudness). The sum stays under full scale
## in practice, because the stems' peaks rarely coincide.
const STEM_PEAK := {"drums": 0.42, "bass": 0.3, "harmony": 0.2, "lead": 0.24}

const MODES := {
	"major": [0, 2, 4, 5, 7, 9, 11],
	"minor": [0, 2, 3, 5, 7, 8, 10],
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10],
	"phrygian": [0, 1, 3, 5, 7, 8, 10],
	"harmonic_minor": [0, 2, 3, 5, 7, 8, 11],
}

enum Drum { KICK, SNARE, HAT, OPEN_HAT, RIDE, CRASH, TOM, TOM_LOW, CLAP, BRUSH }
const DRUM_KEYS := ["kick", "snare", "hat", "open_hat", "ride", "crash", "tom", "tom_low", "clap", "brush"]

static var cache_enabled := true  ## tests turn it off
static var parallel := true  ## render the stems on WorkerThreadPool threads
static var _styles := {}  # name -> MusicStyle
static var _styles_mutex := Mutex.new()
static var _cache_mutex := Mutex.new()


# --- Entry points ---

## The AudioDirector music generator: `request` is {style, tempo_bpm, seed}; `style` is the
## game's dictionary: {"name": ..., any MusicStyle property as an override, "bars": 16}.
## Returns {stem: looping AudioStreamWAV}, or {} for an unknown style. Safe on a worker thread.
static func generate(request: Dictionary) -> Dictionary:
	var style_request: Dictionary = request.get("style", {})
	var style := resolve_style(style_request)
	if style == null:
		push_warning("MusicGen: unknown style %s" % style_request.get("name", "?"))
		return {}
	var bars := int(style_request.get("bars", DEFAULT_BARS))
	return render(style, float(request.get("tempo_bpm", 90.0)), int(request.get("seed", 0)), bars)


## Renders (or loads from the disk cache) the four stems. `tempo_bpm` is the requested tempo
## (the cadence); the music plays at music_tempo(style, tempo_bpm).
static func render(style: MusicStyle, tempo_bpm: float, music_seed: int, bars := DEFAULT_BARS) -> Dictionary:
	Dsp.warm()
	tempo_bpm = music_tempo(style, tempo_bpm)
	bars = maxi(1, bars)
	var key := cache_key(style, tempo_bpm, music_seed, bars)
	var started := Time.get_ticks_usec()
	if cache_enabled:
		var cached := _load_cache(key)
		if not cached.is_empty():
			print("OPENRIDE_GAMES music %s %.1f bpm %d bars: cache hit in %d ms" % [style.name, tempo_bpm, bars,
				(Time.get_ticks_usec() - started) / 1000])
			return cached
	var samples := render_samples(style, tempo_bpm, music_seed, bars)
	var stems := {}
	for stem in STEMS:
		stems[stem] = Dsp.to_wav(samples[stem], true)
	var render_ms := (Time.get_ticks_usec() - started) / 1000
	if cache_enabled:
		_save_cache(key, stems)
	print("OPENRIDE_GAMES music %s %.1f bpm %d bars: rendered in %d ms (%s)" % [style.name, tempo_bpm, bars,
		render_ms, "parallel" if parallel else "serial"])
	return stems


## The four stems as float samples (no cache, no PCM conversion).
static func render_samples(style: MusicStyle, tempo_bpm: float, music_seed: int, bars := DEFAULT_BARS) -> Dictionary:
	Dsp.warm()
	var score := compose(style, music_seed, bars)
	var ctx := {"style": style, "bar_len": bar_samples(tempo_bpm), "score": score}
	var out := {}
	if parallel:
		var mutex := Mutex.new()
		var task := WorkerThreadPool.add_group_task(func(i: int):
			var stem: String = STEMS[i]
			var s := _render_stem(ctx, stem)
			mutex.lock()
			out[stem] = s
			mutex.unlock()
			, STEMS.size(), -1, true, "MusicGen stems")
		WorkerThreadPool.wait_for_group_task_completion(task)
	else:
		for stem in STEMS:
			out[stem] = _render_stem(ctx, stem)
	return out


## A style by name from `res://audio/styles/`, with the request's other keys as overrides.
static func resolve_style(style_request: Dictionary) -> MusicStyle:
	var base := style(String(style_request.get("name", "")))
	if base == null:
		return null
	return base.with_overrides(style_request)


## A library style by name (cached), or null.
static func style(style_name: String) -> MusicStyle:
	_styles_mutex.lock()
	var s: MusicStyle = _styles.get(style_name)
	_styles_mutex.unlock()
	if s:
		return s
	var path := "%s/%s.tres" % [STYLE_DIR, style_name]
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	if not res is MusicStyle:
		return null
	_styles_mutex.lock()
	_styles[style_name] = res
	_styles_mutex.unlock()
	return res


## Every library style name, sorted.
static func style_names() -> PackedStringArray:
	var list := PackedStringArray()
	for file in ResourceLoader.list_directory(STYLE_DIR):
		file = file.trim_suffix(".remap")
		if file.ends_with(".tres"):
			list.append(file.get_basename())
	list.sort()
	return list


## Loads every library style (call on the main thread at startup, so worker threads only read).
static func preload_styles() -> void:
	for n in style_names():
		style(n)


# --- Timing ---

## The tempo the music actually plays at for a requested tempo: × the style's tempo_scale.
static func music_tempo(style: MusicStyle, tempo_bpm: float) -> float:
	return clampf(tempo_bpm * style.tempo_scale, TEMPO_MIN, TEMPO_MAX)


## Samples per bar at a tempo. Every bar has exactly this length, so a stem is bars × this.
static func bar_samples(tempo_bpm: float) -> int:
	return int(round(BEATS_PER_BAR * 60.0 * Dsp.SR / clampf(tempo_bpm, TEMPO_MIN, TEMPO_MAX)))


static func loop_samples(tempo_bpm: float, bars := DEFAULT_BARS) -> int:
	return bar_samples(tempo_bpm) * bars


## Seconds from `position_sec` (a playback position in the loop) to the next phrase boundary,
## where a tempo change should land. 0 exactly on a boundary.
static func seconds_to_next_phrase(position_sec: float, tempo_bpm: float, phrase_bars := PHRASE_BARS) -> float:
	var phrase := float(bar_samples(tempo_bpm) * phrase_bars) / Dsp.SR
	var into := fposmod(position_sec, phrase)
	return 0.0 if into < 0.0005 else phrase - into


static func cache_key(style: MusicStyle, tempo_bpm: float, music_seed: int, bars: int) -> String:
	return JSON.stringify({"v": VERSION, "style": style.signature(), "tempo": snappedf(tempo_bpm, 0.01),
		"seed": music_seed, "bars": bars}).sha256_text()


# --- Composition ---

## The score: {chords: [chord per bar], drums|bass|harmony|lead: [events per bar]}.
## Pitched events are [step, length_steps, midi, velocity]; drum events [step, Drum, velocity].
## Depends on the style and seed only.
static func compose(style: MusicStyle, music_seed: int, bars := DEFAULT_BARS) -> Dictionary:
	var scale: Array = MODES.get(style.mode, MODES["minor"])
	var rng := _rng(music_seed, "form")
	var prog_a: Array = style.progressions[rng.randi() % style.progressions.size()]
	var prog_b: Array = style.b_progressions[rng.randi() % style.b_progressions.size()] if not style.b_progressions.is_empty() else prog_a
	var phrases := int(ceil(float(bars) / PHRASE_BARS))
	var chords := []  # per bar: {degree, tones (semitones above the root), phrase, bar_in_phrase, section}
	for b in bars:
		var phrase := b / PHRASE_BARS
		var section := "B" if phrases >= 4 and phrase % 4 == 2 else "A"
		var prog := prog_b if section == "B" else prog_a
		var degree := int(prog[b % prog.size()])
		chords.append({"degree": degree, "tones": _chord_tones(scale, degree, style.chord_size),
			"phrase": phrase, "bar_in_phrase": b % PHRASE_BARS, "section": section,
			"last": b == bars - 1})
	return {
		"chords": chords,
		"drums": _compose_drums(style, music_seed, chords),
		"bass": _compose_bass(style, music_seed, chords, scale),
		"harmony": _compose_harmony(style, music_seed, chords),
		"lead": _compose_lead(style, music_seed, chords, scale),
	}


static func _rng(music_seed: int, part: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d/%s" % [music_seed, part]).hash()
	return rng


static func _degree_semitones(scale: Array, degree: int) -> int:
	var octave := floori(degree / 7.0)
	return int(scale[posmod(degree, 7)]) + 12 * octave


static func _chord_tones(scale: Array, degree: int, size: int) -> Array:
	var tones := []
	for k in size:
		tones.append(_degree_semitones(scale, degree + 2 * k))
	return tones


static func _compose_drums(style: MusicStyle, music_seed: int, chords: Array) -> Array:
	var rng := _rng(music_seed, "drums")
	var e := style.energy
	var main := _drum_groove(style.drums, e, rng, false)
	var alt := _drum_groove(style.drums, e, rng, true)
	var fills := [_drum_fill(style.drums, e, rng), _drum_fill(style.drums, e, rng)]
	var bars := []
	for c: Dictionary in chords:
		var bar: Array
		var bip: int = c.bar_in_phrase
		if bip == PHRASE_BARS - 1 or c.last:
			bar = _with_fill(main, fills[int(c.phrase) % 2])
		elif bip == 2:
			bar = alt.duplicate()
		else:
			bar = main.duplicate()
		# A crash marks the top of the loop and of the B section.
		if bip == 0 and (int(c.phrase) == 0 or c.section == "B") and style.drums != "brushes":
			bar = bar.duplicate()
			bar.append([0, Drum.CRASH, 0.8])
		bars.append(bar)
	return bars


## One bar of the family's groove. `variant` adds the family's variation.
static func _drum_groove(family: String, e: float, rng: RandomNumberGenerator, variant: bool) -> Array:
	var ev := []
	match family:
		"four_floor":
			for s in [0, 4, 8, 12]:
				ev.append([s, Drum.KICK, 1.0])
			for s in [4, 12]:
				ev.append([s, Drum.CLAP if e > 0.6 else Drum.SNARE, 0.85])
			for s in [2, 6, 10, 14]:
				ev.append([s, Drum.OPEN_HAT if (variant and s == 14) else Drum.HAT, 0.8])
			if e > 0.7:
				for s in [1, 3, 5, 7, 9, 11, 13, 15]:
					ev.append([s, Drum.HAT, 0.35])
			if variant and rng.randf() < 0.6:
				ev.append([15, Drum.KICK, 0.6])
		"halftime":
			ev.append([0, Drum.KICK, 1.0])
			ev.append([10, Drum.KICK, 0.9])
			if variant or rng.randf() < 0.4:
				ev.append([7, Drum.KICK, 0.7])
			ev.append([8, Drum.SNARE, 1.0])
			for s in range(0, 16, 2):
				ev.append([s, Drum.HAT, 0.7 if s % 4 == 0 else 0.45])
			if e > 0.6:
				ev.append([14, Drum.TOM_LOW, 0.5])
		"backbeat":
			ev.append([0, Drum.KICK, 1.0])
			ev.append([8, Drum.KICK, 0.95])
			ev.append([6 if not variant else 10, Drum.KICK, 0.7])
			for s in [4, 12]:
				ev.append([s, Drum.SNARE, 0.9])
				if e > 0.7:
					ev.append([s, Drum.CLAP, 0.5])
			var step := 1 if e > 0.8 else 2
			for s in range(0, 16, step):
				ev.append([s, Drum.HAT, 0.65 if s % 4 == 0 else (0.5 if s % 2 == 0 else 0.3)])
		"brushes":
			# Ride "ding, ding-a ding, ding-a" with feathered kick and a brush on 2 and 4.
			for s in [0, 4, 6, 8, 12, 14]:
				ev.append([s, Drum.RIDE, 0.7 if s % 4 == 0 else 0.45])
			for s in [0, 8]:
				ev.append([s, Drum.KICK, 0.35])
			for s in [4, 12]:
				ev.append([s, Drum.BRUSH, 0.7])
			for s in [2, 10, 15] if variant else [10]:
				if rng.randf() < 0.7:
					ev.append([s, Drum.BRUSH, 0.25])
		"racer":
			for s in ([0, 6, 10] if not variant else [0, 3, 6, 10, 14]):
				ev.append([s, Drum.KICK, 1.0 if s == 0 else 0.85])
			for s in [4, 12]:
				ev.append([s, Drum.SNARE, 0.95])
				if e > 0.6:
					ev.append([s, Drum.CLAP, 0.45])
			ev.append([15, Drum.SNARE, 0.3])
			for s in 16:
				ev.append([s, Drum.OPEN_HAT if (s == 14 and variant) else Drum.HAT, 0.6 if s % 2 == 1 else 0.35])
	return ev


## A fill over the bar's last beat or two.
static func _drum_fill(family: String, e: float, rng: RandomNumberGenerator) -> Array:
	var ev := []
	var kind := rng.randi() % 3
	if family == "brushes":
		for s in [12, 13, 14, 15]:
			ev.append([s, Drum.BRUSH, 0.3 + 0.1 * (s - 12)])
		ev.append([14, Drum.RIDE, 0.5])
		return ev
	match kind:
		0:  # snare sixteenths, rising
			for s in [12, 13, 14, 15]:
				ev.append([s, Drum.SNARE, 0.45 + 0.15 * (s - 12)])
		1:  # toms, high to low
			for s in [12, 13]:
				ev.append([s, Drum.TOM, 0.8])
			for s in [14, 15]:
				ev.append([s, Drum.TOM_LOW, 0.85])
		_:  # snare and tom over two beats
			for s in [8, 10, 12]:
				ev.append([s, Drum.SNARE, 0.6 + 0.1 * (s - 8) / 2.0])
			ev.append([14, Drum.TOM, 0.8])
			ev.append([15, Drum.TOM_LOW, 0.9])
	ev.append([12, Drum.KICK, 0.9])
	if e > 0.8:
		ev.append([15, Drum.KICK, 0.7])
	return ev


static func _with_fill(groove: Array, fill: Array) -> Array:
	var start := 16
	for f in fill:
		start = mini(start, int(f[0]))
	var bar := []
	for g in groove:
		# Keep the kick and hats under the fill; drop the groove's snares and toms there.
		if int(g[0]) >= start and int(g[1]) in [Drum.SNARE, Drum.CLAP, Drum.TOM, Drum.TOM_LOW, Drum.BRUSH]:
			continue
		bar.append(g)
	bar.append_array(fill)
	return bar


static func _bass_note(style: MusicStyle, semis: int) -> int:
	# Keep the bass within a fifth below to a seventh above the tonic.
	var n := style.root + posmod(semis, 12)
	if n > style.root + 7:
		n -= 12
	return n


static func _compose_bass(style: MusicStyle, music_seed: int, chords: Array, scale: Array) -> Array:
	var rng := _rng(music_seed, "bass")
	var e := style.energy
	var bars := []
	# Choices made once per section so repeated phrases render once.
	var octave_steps := []
	for s in [2, 6, 10, 14]:
		if rng.randf() < 0.3 + 0.3 * e:
			octave_steps.append(s)
	var walk_choice := [rng.randi() % 2, rng.randi() % 2, rng.randi() % 2]
	for b in chords.size():
		var c: Dictionary = chords[b]
		var nxt: Dictionary = chords[(b + 1) % chords.size()]
		var tones: Array = c.tones
		var root := _bass_note(style, tones[0])
		var fifth := _bass_note(style, tones[2])
		var next_root := _bass_note(style, nxt.tones[0])
		var ev := []
		match style.bass:
			"pulse8":
				for s in range(0, 16, 2):
					var n := root + (12 if s in octave_steps else 0)
					if s == 14 and c.bar_in_phrase == PHRASE_BARS - 1:
						n = fifth
					ev.append([s, 1.6, n, 0.95 if s % 4 == 0 else 0.75])
			"offbeat":
				if c.bar_in_phrase == 0:
					ev.append([0, 1.5, root, 0.7])
				for s in [2, 6, 10, 14]:
					ev.append([s, 1.8, root + (12 if s in octave_steps else 0), 0.9])
			"walking":
				var third := _bass_note(style, tones[1])
				ev.append([0, 3.6, root, 0.95])
				ev.append([4, 3.6, third if walk_choice[0] == 0 else fifth, 0.8])
				ev.append([8, 3.6, fifth if walk_choice[1] == 0 else root + 12, 0.85])
				# Approach the next chord's root a semitone below or above.
				var approach := next_root + (-1 if walk_choice[2] == 0 else 1)
				if approach < style.root - 7:
					approach += 12
				ev.append([12, 3.6, approach, 0.8])
			"halftime_build":
				var building: int = int(c.phrase) % 4
				if building >= 3:
					for s in range(0, 16, 2):
						ev.append([s, 1.7, root + (12 if s == 8 else 0), 0.9])
				else:
					ev.append([0, 7.5, root, 1.0])
					ev.append([8, 5.5 if building == 0 else 3.5, root + (12 if building >= 1 else 0), 0.85])
					if building >= 1:
						ev.append([12, 1.7, fifth, 0.8])
						ev.append([14, 1.7, root, 0.8])
			"root_fifth":
				ev.append([0, 2.6, root, 1.0])
				ev.append([3, 0.9, root, 0.7])
				ev.append([6, 1.7, root + 12 if 6 in octave_steps or 2 in octave_steps else root, 0.8])
				ev.append([8, 2.6, fifth, 0.9])
				ev.append([11, 0.9, fifth, 0.65])
				ev.append([14, 1.7, root + 12, 0.8])
		bars.append(ev)
	return bars


## Chord tones placed within an octave window around the harmony's centre, so successive
## chords move by small steps.
static func _voicing(style: MusicStyle, tones: Array) -> Array:
	var centre := style.root + 12 + 7
	var notes := []
	for t in tones:
		var n := style.root + 12 + posmod(int(t), 12)
		while n < centre - 6:
			n += 12
		while n >= centre + 6:
			n -= 12
		notes.append(n)
	notes.sort()
	return notes


static func _compose_harmony(style: MusicStyle, music_seed: int, chords: Array) -> Array:
	var rng := _rng(music_seed, "harmony")
	var stab_patterns := [[2, 6, 10, 14], [0, 3, 6, 10, 14], [2, 5, 8, 10, 14]]
	var stab: Array = stab_patterns[rng.randi() % stab_patterns.size()]
	var comp_patterns := [[[6, 2.0], [12, 3.0]], [[0, 3.0], [7, 1.5], [10, 2.0]], [[3, 2.0], [8, 1.5], [14, 1.5]]]
	var comp_a: Array = comp_patterns[rng.randi() % comp_patterns.size()]
	var comp_b: Array = comp_patterns[rng.randi() % comp_patterns.size()]
	var arp_up := rng.randf() < 0.6
	var bars := []
	for c: Dictionary in chords:
		var notes := _voicing(style, c.tones)
		var ev := []
		match style.harmony:
			"pad":
				for n in notes:
					ev.append([0, 16.0, n, 0.8])
			"stabs":
				for s in stab:
					for n in notes:
						ev.append([s, 1.2, n, 0.85 if s % 4 == 2 else 0.7])
			"comp":
				var pattern: Array = comp_a if int(c.bar_in_phrase) % 2 == 0 else comp_b
				for hit in pattern:
					for n in notes:
						ev.append([hit[0], hit[1], n, 0.75])
			"arp":
				var seq := notes.duplicate()
				for n in notes:
					seq.append(n + 12)
				if not arp_up:
					seq.reverse()
				var step := 1 if style.energy >= 0.5 else 2
				var k := 0
				for s in range(0, 16, step):
					ev.append([s, 0.9 * step, seq[k % seq.size()], 0.8 if s % 4 == 0 else 0.6])
					k += 1
		bars.append(ev)
	return bars


static func _compose_lead(style: MusicStyle, music_seed: int, chords: Array, scale: Array) -> Array:
	var rng := _rng(music_seed, "lead")
	# Lead degrees are scale steps above the tonic an octave up; keep them in range.
	var low_deg := _degree_at_or_above(style, scale, style.lead_low)
	var high_deg := _degree_at_or_below(style, scale, style.lead_high)
	var motif_a := _motif(style, rng)
	var motif_b := _motif(style, rng)
	var start_a := low_deg + (high_deg - low_deg) / 3
	var start_b := low_deg + (high_deg - low_deg) / 2
	var phrase_cache := {}
	var bars := []
	for b in chords.size():
		var c: Dictionary = chords[b]
		var phrase := int(c.phrase)
		var section: String = c.section
		# A A' B A: phrases 0 and 3 are identical; 1 ends differently; 2 is the B tune.
		var variant := "A" if section == "A" and phrase % 4 != 1 else ("A2" if section == "A" else "B")
		var key := "%s" % variant
		if not phrase_cache.has(key):
			var first_bar := b - int(c.bar_in_phrase)
			var phrase_chords := []
			for k in PHRASE_BARS:
				phrase_chords.append(chords[mini(first_bar + k, chords.size() - 1)])
			var motif := motif_b if variant == "B" else motif_a
			var start := start_b if variant == "B" else start_a
			phrase_cache[key] = _realise_phrase(style, scale, motif, start, low_deg, high_deg, phrase_chords, variant == "A2", rng)
		bars.append(phrase_cache[key][int(c.bar_in_phrase)])
	return bars


static func _degree_at_or_above(style: MusicStyle, scale: Array, midi: int) -> int:
	var d := -14
	while style.root + _degree_semitones(scale, d) < midi:
		d += 1
	return d


static func _degree_at_or_below(style: MusicStyle, scale: Array, midi: int) -> int:
	var d := 40
	while style.root + _degree_semitones(scale, d) > midi:
		d -= 1
	return d


## A two-bar motif: onsets (steps 0-31) with lengths, and a contour of scale-step moves.
static func _motif(style: MusicStyle, rng: RandomNumberGenerator) -> Dictionary:
	var onsets := []
	for s in 32:
		var weight := 0.95 if s % 8 == 0 else (0.7 if s % 4 == 0 else (0.45 if s % 2 == 0 else 0.2 * style.energy))
		if rng.randf() < weight * style.lead_density * 1.4:
			onsets.append(s)
	if onsets.is_empty() or onsets[0] > 2:
		onsets.push_front(0)
	var moves := []
	for i in onsets.size():
		var r := rng.randf()
		moves.append(0 if r < 0.15 else (1 if r < 0.45 else (-1 if r < 0.72 else (2 if r < 0.84 else (-2 if r < 0.94 else 3)))))
	return {"onsets": onsets, "moves": moves}


## Four bars of melody from a motif over the phrase's chords: the motif, then the motif again
## from a new chord tone with a cadence on a long chord tone (a different one for A').
static func _realise_phrase(style: MusicStyle, scale: Array, motif: Dictionary, start: int, low: int, high: int,
		chords: Array, alt_ending: bool, rng: RandomNumberGenerator) -> Array:
	var bars := [[], [], [], []]
	var deg := start
	for half in 2:
		var onsets: Array = motif.onsets
		var moves: Array = motif.moves
		for i in onsets.size():
			var s: int = onsets[i]
			var bar := half * 2 + s / 16
			var step := s % 16
			if half == 1 and s >= 16:
				continue  # the cadence bar is written below
			deg += int(moves[i])
			if deg > high:
				deg -= 2 * (deg - high)
			if deg < low:
				deg += 2 * (low - deg)
			var chord: Dictionary = chords[bar]
			if step % 8 == 0:
				deg = _nearest_chord_degree(deg, chord, scale, low, high)
			var next_s: int = onsets[i + 1] if i + 1 < onsets.size() else 32
			var length := clampf(float(next_s - s) - 0.3, 0.7, 6.0)
			if half == 0 and s < 16 and next_s >= 16:
				length = minf(length, float(16 - step) - 0.3)
			bars[bar].append([step, length, style.root + _degree_semitones(scale, deg), 0.95 if step % 4 == 0 else 0.75])
		if half == 0:
			deg = _nearest_chord_degree(deg + (2 if rng.randf() < 0.5 else -1), chords[2], scale, low, high)
	# Cadence: one or two notes landing on a chord tone of the last bar's chord.
	var last: Dictionary = chords[3]
	var target := _nearest_chord_degree(deg - 1, last, scale, low, high)
	if alt_ending:
		target = _nearest_chord_degree(deg + 2, last, scale, low, high)
	# Step into the target from above, or from below at the top of the range.
	var lead_in := target + (2 if not alt_ending else 1)
	if lead_in > high:
		lead_in = target - (2 if not alt_ending else 1)
	lead_in = _in_range(lead_in, low, high)
	if alt_ending:
		bars[3].append([0, 3.7, style.root + _degree_semitones(scale, lead_in), 0.8])
		bars[3].append([4, 7.5, style.root + _degree_semitones(scale, target), 0.9])
	else:
		bars[3].append([0, 1.7, style.root + _degree_semitones(scale, lead_in), 0.8])
		bars[3].append([2, 9.5, style.root + _degree_semitones(scale, target), 0.9])
	return bars


## A scale degree moved by octaves into low..high.
static func _in_range(deg: int, low: int, high: int) -> int:
	while deg > high:
		deg -= 7
	while deg < low:
		deg += 7
	return deg


static func _nearest_chord_degree(deg: int, chord: Dictionary, scale: Array, low: int, high: int) -> int:
	var root_deg: int = chord.degree
	var size: int = chord.tones.size()
	var best := _in_range(deg, low, high)
	var best_dist := 99
	for d in range(deg - 3, deg + 4):
		if d < low or d > high:
			continue
		var rel := posmod(d - root_deg, 7)
		if rel % 2 == 0 and rel / 2 < size:
			var dist := absi(d - deg)
			if dist < best_dist:
				best = d
				best_dist = dist
	return best


# --- Rendering ---

static func _render_stem(ctx: Dictionary, stem: String) -> PackedFloat32Array:
	var style: MusicStyle = ctx.style
	var bar_len: int = ctx.bar_len
	var bars: Array = ctx.score[stem]
	var kit := _drum_kit(style) if stem == "drums" else {}
	var voice: Dictionary
	match stem:
		"bass": voice = style.bass_voice
		"harmony": voice = style.harmony_voice
		"lead": voice = style.lead_voice
	# Render each distinct bar once.
	var rendered := {}  # bar events (as text) -> samples
	var keys := []
	for events: Array in bars:
		var key := var_to_str(events)
		keys.append(key)
		if not rendered.has(key):
			rendered[key] = _render_bar(events, style, bar_len, voice, kit)
	# Normalise the stem's peak, so every style mixes at the same level.
	var peak := 0.0
	for key in rendered:
		var buf: PackedFloat32Array = rendered[key]
		for i in buf.size():
			peak = maxf(peak, absf(buf[i]))
	if peak > 0.0:
		var gain: float = STEM_PEAK[stem] * style.loudness / peak
		for key in rendered:
			var buf: PackedFloat32Array = rendered[key]
			for i in buf.size():
				buf[i] *= gain
			rendered[key] = buf
	var out := PackedFloat32Array()
	for key in keys:
		out.append_array(rendered[key])
	return out


static func _step_offset(style: MusicStyle, step: float, bar_len: int) -> int:
	var step_len := float(bar_len) / STEPS
	var t := step * step_len
	var s := int(step)
	if style.swing > 0.0 and float(s) == step:
		if style.swing_grid == 8 and s % 4 == 2:
			t += style.swing * 2.0 * step_len
		elif style.swing_grid == 16 and s % 2 == 1:
			t += style.swing * step_len
	return int(t)


static func _render_bar(events: Array, style: MusicStyle, bar_len: int, voice: Dictionary, kit: Dictionary) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(bar_len)
	var step_len := float(bar_len) / STEPS
	var loud := 0.75 + 0.25 * style.energy
	for ev: Array in events:
		var start := _step_offset(style, float(ev[0]), bar_len)
		if not kit.is_empty():
			var hit: PackedFloat32Array = kit.get(int(ev[1]), PackedFloat32Array())
			Dsp.mix_into(buf, hit, start, float(ev[2]) * loud)
		else:
			# Every note (with its release) ends before the bar's fade-out.
			var length := mini(int(float(ev[1]) * step_len), bar_len - FADE_OUT - start)
			var freq := Dsp.midi_hz(float(ev[2]) + style.transpose)
			Dsp.render_note(buf, start, length, freq, float(ev[3]) * loud, voice)
	Dsp.fade_edges(buf, FADE_IN, FADE_OUT)
	return buf


## The drum sounds, each synthesised once per render.
static func _drum_kit(style: MusicStyle) -> Dictionary:
	var levels := style.drum_levels
	var kit := {}
	for d in DRUM_KEYS.size():
		var level := float(levels.get(DRUM_KEYS[d], 1.0))
		if level > 0.0:
			kit[d] = _drum(d, level)
	return kit


static func _drum(drum: int, level: float) -> PackedFloat32Array:
	var sr := float(Dsp.SR)
	match drum:
		Drum.KICK:
			return _drum_tone(0.32, 150.0, 45.0, 0.05, 0.9 * level, 0.1, 0.004)
		Drum.TOM:
			return _drum_tone(0.25, 210.0, 150.0, 0.12, 0.55 * level, 0.08, 0.003)
		Drum.TOM_LOW:
			return _drum_tone(0.3, 150.0, 100.0, 0.12, 0.6 * level, 0.08, 0.003)
		Drum.SNARE:
			var body := _drum_tone(0.1, 200.0, 170.0, 0.05, 0.35 * level, 0.0, 0.0)
			var rattle := _drum_noise(0.2, 1200.0, 7000.0, 0.07, 0.45 * level, 0.001)
			Dsp.mix_into(rattle, body, 0, 1.0)
			return rattle
		Drum.HAT:
			return _drum_noise(0.06, 7000.0, 11000.0, 0.018, 0.22 * level, 0.0005)
		Drum.OPEN_HAT:
			return _drum_noise(0.3, 6500.0, 11000.0, 0.09, 0.2 * level, 0.001)
		Drum.RIDE:
			var ride := _drum_noise(0.7, 5000.0, 9000.0, 0.22, 0.12 * level, 0.001)
			var bell := _drum_tone(0.5, 2300.0, 2300.0, 0.16, 0.05 * level, 0.0, 0.0, Dsp.Wave.SQUARE)
			Dsp.mix_into(ride, bell, 0, 1.0)
			return ride
		Drum.CRASH:
			return _drum_noise(1.4, 3500.0, 10000.0, 0.45, 0.25 * level, 0.002)
		Drum.CLAP:
			var clap := PackedFloat32Array()
			clap.resize(int(0.22 * sr))
			var burst := _drum_noise(0.2, 900.0, 3000.0, 0.012, 0.35 * level, 0.0005)
			var tail := _drum_noise(0.2, 900.0, 3000.0, 0.06, 0.3 * level, 0.0005)
			Dsp.mix_into(clap, burst, 0, 1.0)
			Dsp.mix_into(clap, burst, int(0.011 * sr), 1.0)
			Dsp.mix_into(clap, tail, int(0.022 * sr), 1.0)
			return clap
		Drum.BRUSH:
			return _drum_noise(0.25, 700.0, 3500.0, 0.08, 0.25 * level, 0.02)
	return PackedFloat32Array()


## A pitched drum: an exponentially falling pitch and level, with a click of noise at the start.
static func _drum_tone(seconds: float, f0: float, f1: float, decay: float, gain: float, click: float, attack: float,
		wave := Dsp.Wave.SINE) -> PackedFloat32Array:
	var sr := float(Dsp.SR)
	var n := int(seconds * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var table := Dsp.table(wave, f0)
	var noise := Dsp.noise()
	var size := float(table.size())
	var phase := 0.0
	var attack_n := maxi(1, int(attack * sr))
	for i in n:
		var t := i / sr
		var f := f1 + (f0 - f1) * exp(-t / 0.035)
		phase += f * size / sr
		if phase >= size:
			phase -= size
		var env := exp(-t / decay) * minf(1.0, float(i) / attack_n)
		var s := table[int(phase)] * env
		if click > 0.0 and i < 90:
			s += noise[i] * click * (1.0 - i / 90.0)
		out[i] = s * gain
	Dsp.fade_edges(out, 4, 64)
	return out


## A noise drum: band-limited white noise (high-pass, then low-pass) with an exponential decay.
static func _drum_noise(seconds: float, highpass: float, lowpass: float, decay: float, gain: float, attack: float) -> PackedFloat32Array:
	var sr := float(Dsp.SR)
	var n := int(seconds * sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var noise := Dsp.noise()
	var hp_a := Dsp.lp_coef(highpass)
	var lp_a := Dsp.lp_coef(lowpass)
	var low := 0.0
	var y := 0.0
	var attack_n := maxi(1, int(attack * sr))
	var env := 1.0
	var k := exp(-1.0 / (decay * sr))
	for i in n:
		var x := noise[(i * 7 + 1234) & (Dsp.NOISE_SIZE - 1)]
		low += hp_a * (x - low)
		y += lp_a * ((x - low) - y)
		env *= k
		out[i] = y * env * gain * minf(1.0, float(i) / attack_n)
	Dsp.fade_edges(out, 4, 64)
	return out


# --- Disk cache ---

static func _cache_path(key: String) -> String:
	return "%s/%s.stems" % [CACHE_DIR, key]


static func _load_cache(key: String) -> Dictionary:
	var path := _cache_path(key)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data = f.get_var()
	f.close()
	if not data is Dictionary or int(data.get("v", -1)) != VERSION:
		return {}
	var pcm: Dictionary = data.get("stems", {})
	var stems := {}
	var size := -1
	for stem in STEMS:
		var bytes = pcm.get(stem)
		if not bytes is PackedByteArray or (size != -1 and bytes.size() != size):
			return {}
		size = bytes.size()
		stems[stem] = Dsp.wav_from_pcm(bytes, true)
	return stems


static func _save_cache(key: String, stems: Dictionary) -> void:
	_cache_mutex.lock()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var pcm := {}
	for stem in stems:
		pcm[stem] = (stems[stem] as AudioStreamWAV).data
	var path := _cache_path(key)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f != null:
		f.store_var({"v": VERSION, "stems": pcm})
		f.close()
		DirAccess.rename_absolute(tmp, path)
		prune_cache(CACHE_LIMIT_BYTES, path)
	_cache_mutex.unlock()


## Deletes the oldest cache files until the cache fits in `limit_bytes`. `keep` is never deleted.
static func prune_cache(limit_bytes := CACHE_LIMIT_BYTES, keep := "") -> void:
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		return
	var files := []
	var total := 0
	for name in DirAccess.get_files_at(CACHE_DIR):
		var path := "%s/%s" % [CACHE_DIR, name]
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var size := f.get_length()
		f.close()
		total += size
		files.append({"path": path, "size": size, "time": FileAccess.get_modified_time(path)})
	files.sort_custom(func(a, b): return a.time < b.time or (a.time == b.time and a.path < b.path))
	for file in files:
		if total <= limit_bytes:
			break
		if file.path == keep:
			continue
		DirAccess.remove_absolute(file.path)
		total -= file.size


static func clear_cache() -> void:
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		return
	for name in DirAccess.get_files_at(CACHE_DIR):
		DirAccess.remove_absolute("%s/%s" % [CACHE_DIR, name])
