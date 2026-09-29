extends SceneTree
## Writes the starter SfxSynth presets (`res://audio/sfx/`) and the MusicGen styles
## (`res://audio/styles/`) from the tables below. The .tres files are the source of truth
## once written: tune them in the inspector or the style gallery, or edit this and rerun:
##   $GODOT_BIN --headless --path games -s res://audio/tools/make_library.gd
## Existing files are overwritten.

const W := SfxPreset.Wave

const PRESETS := {
	# The starter library.
	"whoosh": {"wave": W.NOISE, "attack": 0.08, "sustain": 0.05, "decay": 0.28, "lowpass_start": 500.0, "lowpass_end": 4500.0, "highpass": 250.0, "volume": 0.6},
	"thud": {"wave": W.SINE, "freq_start": 130.0, "freq_end": 45.0, "sweep_time": 0.12, "attack": 0.002, "sustain": 0.02, "decay": 0.22, "noise_mix": 0.25, "lowpass_start": 900.0, "lowpass_end": 300.0, "punch": 0.5, "volume": 0.7},
	"click": {"wave": W.SQUARE, "freq_start": 1800.0, "freq_end": 1100.0, "attack": 0.001, "sustain": 0.006, "decay": 0.025, "lowpass_start": 5000.0, "volume": 0.3},
	"chime": {"wave": W.TRIANGLE, "freq_start": 1046.5, "freq_end": 1046.5, "jump_ratio": 1.5, "jump_time": 0.08, "attack": 0.002, "sustain": 0.06, "decay": 0.6, "vibrato_depth": 0.08, "vibrato_rate": 5.0, "volume": 0.4},
	"alarm_soft": {"wave": W.TRIANGLE, "freq_start": 660.0, "freq_end": 620.0, "attack": 0.02, "sustain": 0.12, "decay": 0.1, "vibrato_depth": 0.3, "vibrato_rate": 8.0, "lowpass_start": 2500.0, "repeats": 2, "repeat_gap": 0.32, "volume": 0.35},
	"boost": {"wave": W.SAW, "freq_start": 200.0, "freq_end": 900.0, "sweep_time": 0.35, "attack": 0.01, "sustain": 0.25, "decay": 0.2, "lowpass_start": 1200.0, "lowpass_end": 5000.0, "vibrato_depth": 0.2, "vibrato_rate": 12.0, "volume": 0.3},
	"countdown_beep": {"wave": W.SQUARE, "freq_start": 880.0, "freq_end": 880.0, "attack": 0.002, "sustain": 0.08, "decay": 0.08, "lowpass_start": 3000.0, "volume": 0.28},
	"go": {"wave": W.SQUARE, "freq_start": 1318.5, "freq_end": 1318.5, "attack": 0.002, "sustain": 0.25, "decay": 0.25, "vibrato_depth": 0.12, "vibrato_rate": 6.0, "lowpass_start": 4000.0, "volume": 0.3},
	# The framework's cues (AudioDirector; `countdown` is countdown_beep).
	"segment_end": {"wave": W.TRIANGLE, "freq_start": 523.25, "freq_end": 523.25, "jump_ratio": 1.335, "jump_time": 0.1, "attack": 0.003, "sustain": 0.12, "decay": 0.5, "volume": 0.45},
	"pause": {"wave": W.TRIANGLE, "freq_start": 660.0, "freq_end": 440.0, "sweep_time": 0.12, "attack": 0.003, "sustain": 0.08, "decay": 0.1, "volume": 0.4},
	"resume": {"wave": W.TRIANGLE, "freq_start": 440.0, "freq_end": 660.0, "sweep_time": 0.12, "attack": 0.003, "sustain": 0.08, "decay": 0.1, "volume": 0.4},
	"summary": {"wave": W.SQUARE, "freq_start": 523.25, "freq_end": 523.25, "jump_ratio": 2.0, "jump_time": 0.14, "attack": 0.003, "sustain": 0.3, "decay": 0.7, "vibrato_depth": 0.1, "vibrato_rate": 5.0, "lowpass_start": 2500.0, "lowpass_end": 1200.0, "volume": 0.3},
	# The demo game's effects.
	"dodge": {"wave": W.SAW, "freq_start": 400.0, "freq_end": 1200.0, "attack": 0.003, "sustain": 0.03, "decay": 0.09, "lowpass_start": 3000.0, "volume": 0.25},
	"hit": {"wave": W.SINE, "freq_start": 180.0, "freq_end": 60.0, "sweep_time": 0.15, "noise_mix": 0.5, "attack": 0.001, "sustain": 0.03, "decay": 0.25, "lowpass_start": 2000.0, "lowpass_end": 400.0, "punch": 0.6, "volume": 0.6},
}

const PAD := {"wave": "saw", "wave2": "saw", "detune": 10.0, "cutoff": 1500.0, "attack": 0.1, "decay": 0.4, "sustain": 0.8, "release": 0.12, "gain": 0.13}
const STAB := {"wave": "saw", "wave2": "square", "detune": 6.0, "cutoff": 2400.0, "cutoff_env": 1500.0, "filter_decay": 0.06, "attack": 0.003, "decay": 0.12, "sustain": 0.35, "release": 0.04, "gain": 0.13}

const STYLES := {
	"drive": {
		"description": "Energetic minor key, driving four-on-the-floor drums, pumping eighth-note bass (Dodge Ball).",
		"root": 45, "mode": "minor", "progressions": [[0, 5, 2, 6], [0, 6, 5, 6], [0, 3, 5, 4]], "b_progressions": [[5, 6, 0, 0], [3, 4, 5, 6]],
		"drums": "four_floor", "bass": "pulse8", "harmony": "stabs", "energy": 0.85, "lead_low": 69, "lead_high": 86, "lead_density": 0.55,
		"bass_voice": {"wave": "saw", "cutoff": 450.0, "cutoff_env": 1500.0, "filter_decay": 0.07, "attack": 0.003, "decay": 0.1, "sustain": 0.6, "release": 0.03, "gain": 0.45},
		"harmony_voice": STAB,
		"lead_voice": {"wave": "square", "cutoff": 3500.0, "attack": 0.008, "decay": 0.1, "sustain": 0.6, "release": 0.05, "vibrato": 0.15, "vibrato_rate": 5.5, "gain": 0.17},
		"tempo_min": 70.0, "tempo_max": 115.0, "suggested_gates": {"harmony": 0.3, "lead": 0.8},
	},
	"demo_drive": {
		"description": "The demo game's music: a lighter minor-key four-on-the-floor with a pad.",
		"root": 43, "mode": "dorian", "progressions": [[0, 3, 0, 6], [0, 4, 3, 6]], "b_progressions": [[2, 3, 4, 4]],
		"drums": "four_floor", "bass": "offbeat", "harmony": "pad", "energy": 0.65, "lead_low": 67, "lead_high": 84, "lead_density": 0.45,
		"bass_voice": {"wave": "square", "cutoff": 500.0, "cutoff_env": 900.0, "filter_decay": 0.06, "attack": 0.003, "decay": 0.1, "sustain": 0.6, "release": 0.03, "gain": 0.42},
		"harmony_voice": PAD,
		"lead_voice": {"wave": "pulse", "cutoff": 3000.0, "attack": 0.01, "decay": 0.1, "sustain": 0.6, "release": 0.06, "vibrato": 0.12, "vibrato_rate": 5.0, "gain": 0.18},
		"tempo_min": 70.0, "tempo_max": 115.0, "suggested_gates": {"harmony": 0.5, "lead": 0.85},
	},
	"heave": {
		"description": "Heavy half-time drums and a bass that builds phrase by phrase, Phrygian and dark (Tug of War).",
		"root": 40, "mode": "phrygian", "progressions": [[0, 0, 5, 6], [0, 1, 0, 6], [0, 5, 1, 0]], "b_progressions": [[3, 3, 4, 4], [5, 5, 1, 1]],
		"drums": "halftime", "bass": "halftime_build", "harmony": "pad", "energy": 0.75, "lead_low": 64, "lead_high": 79, "lead_density": 0.3,
		"bass_voice": {"wave": "saw", "wave2": "sine", "octave2": -1.0, "mix2": 0.4, "cutoff": 380.0, "cutoff_env": 900.0, "filter_decay": 0.1, "attack": 0.005, "decay": 0.2, "sustain": 0.75, "release": 0.06, "gain": 0.5},
		"harmony_voice": {"wave": "saw", "wave2": "saw", "detune": 14.0, "cutoff": 900.0, "attack": 0.2, "decay": 0.5, "sustain": 0.8, "release": 0.15, "gain": 0.12},
		"lead_voice": {"wave": "saw", "cutoff": 1800.0, "attack": 0.03, "decay": 0.2, "sustain": 0.7, "release": 0.1, "vibrato": 0.2, "vibrato_rate": 4.5, "gain": 0.15},
		"drum_levels": {"kick": 1.0, "snare": 1.0, "tom": 1.0, "tom_low": 1.0, "hat": 0.7},
		"tempo_min": 60.0, "tempo_max": 100.0, "suggested_gates": {"drums": 0.0, "lead": 0.7},
	},
	"noir": {
		"description": "Calm, sparse jazz noir: brushed drums and ride, walking bass, swung comping (Safe Cracker, 70-80 bpm).",
		"root": 38, "mode": "harmonic_minor", "chord_size": 4,
		"progressions": [[1, 4, 0, 0], [0, 3, 1, 4], [0, 5, 1, 4]], "b_progressions": [[3, 3, 0, 0], [5, 4, 0, 4]],
		"drums": "brushes", "bass": "walking", "harmony": "comp", "swing": 0.33, "swing_grid": 8, "energy": 0.35, "loudness": 0.8,
		"lead_low": 62, "lead_high": 79, "lead_density": 0.28,
		"bass_voice": {"wave": "triangle", "wave2": "sine", "mix2": 0.5, "cutoff": 700.0, "cutoff_env": 500.0, "filter_decay": 0.05, "attack": 0.006, "decay": 0.3, "sustain": 0.45, "release": 0.06, "gain": 0.55},
		"harmony_voice": {"wave": "sine", "wave2": "sine", "octave2": 1.0, "mix2": 0.25, "cutoff": 3000.0, "attack": 0.004, "decay": 0.5, "sustain": 0.35, "release": 0.12, "tremolo": 0.25, "tremolo_rate": 4.5, "gain": 0.1},
		"lead_voice": {"wave": "sine", "wave2": "triangle", "octave2": 2.0, "mix2": 0.15, "cutoff": 4000.0, "attack": 0.003, "decay": 0.6, "sustain": 0.3, "release": 0.2, "tremolo": 0.35, "tremolo_rate": 5.0, "gain": 0.2},
		"drum_levels": {"kick": 0.6, "ride": 1.0, "brush": 1.0, "crash": 0.0},
		"tempo_min": 65.0, "tempo_max": 85.0, "suggested_gates": {"harmony": 0.3, "lead": 0.6},
	},
	"bright": {
		"description": "Bright synth-pop with rich seventh chords and a sixteenth-note arpeggio (Cadence Karaoke).",
		"root": 41, "mode": "major", "chord_size": 4,
		"progressions": [[0, 4, 5, 3], [5, 3, 0, 4], [0, 5, 3, 4]], "b_progressions": [[3, 4, 2, 5], [1, 4, 0, 0]],
		"drums": "backbeat", "bass": "root_fifth", "harmony": "arp", "energy": 0.75, "lead_low": 67, "lead_high": 86, "lead_density": 0.5,
		"bass_voice": {"wave": "square", "wave2": "saw", "detune": 5.0, "cutoff": 600.0, "cutoff_env": 1400.0, "filter_decay": 0.08, "attack": 0.003, "decay": 0.12, "sustain": 0.6, "release": 0.04, "gain": 0.42},
		"harmony_voice": {"wave": "pulse", "cutoff": 2600.0, "cutoff_env": 2000.0, "filter_decay": 0.05, "attack": 0.002, "decay": 0.12, "sustain": 0.3, "release": 0.04, "gain": 0.12},
		"lead_voice": {"wave": "saw", "wave2": "square", "detune": 7.0, "cutoff": 3200.0, "attack": 0.01, "decay": 0.15, "sustain": 0.65, "release": 0.07, "vibrato": 0.18, "vibrato_rate": 5.5, "gain": 0.15},
		"tempo_min": 60.0, "tempo_max": 110.0, "suggested_gates": {"harmony": 0.2, "lead": 0.99},
	},
	"racer": {
		"description": "Upbeat racing electronica: busy breakbeat drums, off-beat bass, stabs and a bright saw lead (Kart Race). Ask for {\"transpose\": 2, \"energy\": 1.0} for the final lap.",
		"root": 43, "mode": "mixolydian", "progressions": [[0, 6, 3, 0], [0, 3, 6, 3], [0, 4, 6, 3]], "b_progressions": [[5, 6, 0, 0], [3, 3, 6, 6]],
		"drums": "racer", "bass": "offbeat", "harmony": "stabs", "energy": 0.9, "lead_low": 67, "lead_high": 88, "lead_density": 0.6,
		"bass_voice": {"wave": "saw", "wave2": "square", "detune": 8.0, "cutoff": 550.0, "cutoff_env": 2000.0, "filter_decay": 0.06, "attack": 0.002, "decay": 0.1, "sustain": 0.55, "release": 0.03, "gain": 0.42},
		"harmony_voice": STAB,
		"lead_voice": {"wave": "saw", "wave2": "saw", "detune": 12.0, "cutoff": 3800.0, "attack": 0.006, "decay": 0.1, "sustain": 0.7, "release": 0.05, "vibrato": 0.2, "vibrato_rate": 6.0, "gain": 0.14},
		"tempo_min": 70.0, "tempo_max": 120.0, "suggested_gates": {"drums": 0.2, "lead": 0.6},
	},
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://audio/sfx")
	DirAccess.make_dir_recursive_absolute("res://audio/styles")
	var failed := 0
	for n in PRESETS:
		var p := SfxPreset.new()
		for k in PRESETS[n]:
			p.set(k, PRESETS[n][k])
		failed += int(ResourceSaver.save(p, "res://audio/sfx/%s.tres" % n) != OK)
	for n in STYLES:
		var s := MusicStyle.new()
		s.name = n
		for k in STYLES[n]:
			s.set(k, STYLES[n][k])
		failed += int(ResourceSaver.save(s, "res://audio/styles/%s.tres" % n) != OK)
	print("wrote %d presets and %d styles, %d failed" % [PRESETS.size(), STYLES.size(), failed])
	quit(1 if failed else 0)
