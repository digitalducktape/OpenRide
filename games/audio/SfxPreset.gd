class_name SfxPreset
extends Resource
## One sound effect's parameters for SfxSynth (#36), an sfxr-style generator written for this
## repo: an oscillator (or noise), an attack/sustain/decay envelope, a pitch sweep with vibrato
## and an optional jump, and low-/high-pass filters. Presets are small .tres files, rendered
## once to an AudioStreamWAV and cached.

enum Wave { SINE, TRIANGLE, SAW, SQUARE, PULSE, NOISE }

@export var wave: Wave = Wave.SQUARE
## Mixes white noise into a tonal wave, 0-1 (ignored when `wave` is NOISE).
@export_range(0.0, 1.0) var noise_mix := 0.0

@export_group("Envelope")
@export_range(0.0, 2.0, 0.001, "suffix:s") var attack := 0.005
## Time held at full level after the attack.
@export_range(0.0, 4.0, 0.001, "suffix:s") var sustain := 0.05
## Time to fade from full level to silence.
@export_range(0.0, 4.0, 0.001, "suffix:s") var decay := 0.2
## Extra level at the start of the sustain, fading over it (0-1).
@export_range(0.0, 1.0) var punch := 0.0

@export_group("Pitch")
@export_range(20.0, 8000.0, 1.0, "suffix:Hz") var freq_start := 440.0
@export_range(20.0, 8000.0, 1.0, "suffix:Hz") var freq_end := 440.0
## How long the sweep from freq_start to freq_end takes; 0 = the whole sound.
@export_range(0.0, 4.0, 0.001, "suffix:s") var sweep_time := 0.0
@export_range(0.0, 12.0, 0.01, "suffix:st") var vibrato_depth := 0.0
@export_range(0.0, 30.0, 0.1, "suffix:Hz") var vibrato_rate := 6.0
## Multiplies the pitch at `jump_time` (1 = no jump), e.g. 1.5 for a rising fifth.
@export_range(0.25, 4.0, 0.001) var jump_ratio := 1.0
@export_range(0.0, 4.0, 0.001, "suffix:s") var jump_time := 0.0

@export_group("Filter")
## Low-pass cutoff at the start and end of the sound (0 = off).
@export_range(0.0, 11000.0, 1.0, "suffix:Hz") var lowpass_start := 0.0
@export_range(0.0, 11000.0, 1.0, "suffix:Hz") var lowpass_end := 0.0
@export_range(0.0, 8000.0, 1.0, "suffix:Hz") var highpass := 0.0

@export_group("Output")
@export_range(0.0, 1.0) var volume := 0.5
## Plays the sound this many times in total, `repeat_gap` apart (for beeps).
@export_range(1, 8) var repeats := 1
@export_range(0.0, 2.0, 0.001, "suffix:s") var repeat_gap := 0.15
## A continuous sound (e.g. an engine hum): the stream loops seamlessly and has no attack or
## decay; `sustain` is the loop length.
@export var loop := false


func duration() -> float:
	if loop:
		return sustain
	return attack + sustain + decay + (repeats - 1) * repeat_gap
