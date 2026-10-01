class_name MusicStyle
extends Resource
## A MusicGen style (#36): what a game's music is made of. MusicGen composes from a style and
## a seed, then renders at a tempo. Styles live in `res://audio/styles/<name>.tres`; a game
## asks for one by name, and any other key in its request overrides that property:
##
##   AudioDirector.play_music({"name": "drive", "transpose": 2, "stem_gates": {"lead": 0.8}}, 90, seed)
##
## The style gallery (`res://audio/gallery/StyleGallery.tscn`) auditions them.

@export var name := ""
@export_multiline var description := ""

@export_group("Harmony")
## MIDI note of the key's tonic, in the bass octave (45 = A2).
@export_range(28, 60) var root := 45
## Semitones added to everything, e.g. a final-lap lift.
@export_range(-12, 12) var transpose := 0
## major, minor, dorian, mixolydian, phrygian or harmonic_minor
@export_enum("major", "minor", "dorian", "mixolydian", "phrygian", "harmonic_minor") var mode := "minor"
## Chord progressions for the A phrases, each a list of scale degrees (0 = the tonic), one
## chord per bar. MusicGen picks one per seed.
@export var progressions: Array = [[0, 5, 2, 6]]
## Progressions for the B phrase (the third of four).
@export var b_progressions: Array = [[5, 6, 0, 0]]
## 3 = triads, 4 = sevenths.
@export_range(3, 4) var chord_size := 3

@export_group("Rhythm")
## four_floor, halftime, backbeat, brushes or racer
@export_enum("four_floor", "halftime", "backbeat", "brushes", "racer") var drums := "four_floor"
## pulse8, offbeat, walking, halftime_build or root_fifth
@export_enum("pulse8", "offbeat", "walking", "halftime_build", "root_fifth") var bass := "pulse8"
## pad, stabs, comp or arp
@export_enum("pad", "stabs", "comp", "arp") var harmony := "pad"
## Delay of off-beat notes, as a fraction of a grid step (0 = straight, 0.33 = a triplet feel).
@export_range(0.0, 0.5) var swing := 0.0
## 8: swing the eighths (jazz); 16: swing the sixteenths.
@export_enum("8:8", "16:16") var swing_grid := 16
## 0-1: busier drums, more lead notes, harder-hit notes.
@export_range(0.0, 1.0) var energy := 0.7
## Overall level, 0-1: each stem is normalised to a fixed peak, times this.
@export_range(0.0, 1.0) var loudness := 1.0

@export_group("Lead")
## Lowest and highest MIDI note of the melody.
@export_range(48, 96) var lead_low := 67
@export_range(48, 96) var lead_high := 84
## 0-1: how many of the grid's steps start a note.
@export_range(0.0, 1.0) var lead_density := 0.5

@export_group("Timbres")
## Voice dictionaries for Dsp.render_note: wave, wave2, detune, octave2, mix2, attack, decay,
## sustain, release, cutoff, cutoff_env, filter_decay, vibrato, vibrato_rate, tremolo, gain.
@export var bass_voice := {"wave": "saw", "cutoff": 600.0, "cutoff_env": 1200.0, "filter_decay": 0.08, "attack": 0.004, "decay": 0.12, "sustain": 0.7, "release": 0.03, "gain": 0.5}
@export var harmony_voice := {"wave": "saw", "wave2": "saw", "detune": 9.0, "cutoff": 1400.0, "attack": 0.12, "decay": 0.3, "sustain": 0.8, "release": 0.12, "gain": 0.16}
@export var lead_voice := {"wave": "square", "cutoff": 3000.0, "attack": 0.01, "decay": 0.1, "sustain": 0.6, "release": 0.06, "vibrato": 0.15, "vibrato_rate": 5.5, "gain": 0.2}
## 0-1 per drum: kick, snare, hat, ride, crash, tom, clap, brush.
@export var drum_levels := {}
## Recorded one-shots for drums, by drum name ("kick", "snare", "hat", …) → a sample under
## `res://audio/samples/`, plus an optional "gain" (0.8). Drums not listed are synthesised.
@export var drum_samples := {}
## Offline effects per stem, applied to each rendered bar (`Dsp.apply_fx`): {stem: {highpass,
## lowpass, drive, comp_threshold, comp_ratio, comp_release}}. Reverb and bus compression are
## the game's, through `AudioDirector.set_bus_effects`.
@export var stem_fx := {}

@export_group("Tempo")
## The music plays at the requested tempo (a game passes the target cadence in rpm) times
## this. 1 = one beat per pedal stroke. 2 = one beat per leg (double time), still locked to
## pedalling. The knob to turn if a style feels too slow.
@export_range(0.5, 2.0, 0.25) var tempo_scale := 1.0

@export_group("Gallery")
## The tempo range the style is written for (the gallery's slider and a guide for games).
@export var tempo_min := 70.0
@export var tempo_max := 110.0
## Suggested `stem_gates` for games (AudioDirector reads the game's own).
@export var suggested_gates := {}


## A copy with `overrides` applied (keys that aren't properties are ignored, e.g. stem_gates).
func with_overrides(overrides: Dictionary) -> MusicStyle:
	var copy: MusicStyle = duplicate(true)
	var props := {}
	for p in get_property_list():
		props[p.name] = true
	for key in overrides:
		if key != "name" and props.has(key):
			copy.set(key, overrides[key])
	return copy


## The musical content as a plain dictionary (the disk cache key uses it, so an edited style
## never plays a stale render).
func signature() -> Dictionary:
	return {
		"root": root, "transpose": transpose, "mode": mode, "progressions": progressions,
		"b_progressions": b_progressions, "chord_size": chord_size, "drums": drums, "bass": bass,
		"harmony": harmony, "swing": swing, "swing_grid": swing_grid, "energy": energy,
		"lead_low": lead_low, "lead_high": lead_high, "lead_density": lead_density,
		"bass_voice": bass_voice, "harmony_voice": harmony_voice, "lead_voice": lead_voice,
		"drum_levels": drum_levels, "loudness": loudness, "drum_samples": drum_samples, "stem_fx": stem_fx,
	}


## Every sample this style plays: its drum samples and any voice's `sample`.
func sample_paths() -> Array:
	var paths := []
	for key in drum_samples:
		if key != "gain":
			paths.append(str(drum_samples[key]))
	for voice: Dictionary in [bass_voice, harmony_voice, lead_voice]:
		if voice.has("sample"):
			paths.append(str(voice.sample))
	return paths
