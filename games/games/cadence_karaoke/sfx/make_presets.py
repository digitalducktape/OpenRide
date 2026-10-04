# Writes Cadence Karaoke's SfxPreset parameter files (synth settings only, no samples) next to
# this file. Run: python3 games/games/cadence_karaoke/sfx/make_presets.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# wave: 0 sine, 1 triangle, 2 saw, 3 square, 4 pulse, 5 noise
PRESETS = {
    "beat_tick": dict(wave=0, attack=0.001, sustain=0.008, decay=0.05, freq_start=1100.0, freq_end=1100.0,
                      volume=0.25),
    "streak_up": dict(wave=1, attack=0.003, sustain=0.05, decay=0.5, freq_start=659.3, freq_end=659.3,
                      jump_ratio=1.5, jump_time=0.08, punch=0.3, repeats=2, repeat_gap=0.08, volume=0.35),
    "band_exit": dict(wave=0, attack=0.005, sustain=0.05, decay=0.3, freq_start=494.0, freq_end=330.0,
                      sweep_time=0.25, volume=0.28),
    "ease_off_chime": dict(wave=1, attack=0.01, sustain=0.1, decay=0.6, freq_start=587.3, freq_end=440.0,
                           sweep_time=0.4, vibrato_depth=0.15, vibrato_rate=5.0, repeats=2, repeat_gap=0.35,
                           volume=0.3),
}

for name, props in PRESETS.items():
    lines = ['[gd_resource type="Resource" script_class="SfxPreset" format=3]', '',
             '[ext_resource type="Script" path="res://audio/SfxPreset.gd" id="1_sfx"]', '', '[resource]',
             'script = ExtResource("1_sfx")']
    lines += ["%s = %s" % (k, ("true" if v else "false") if isinstance(v, bool) else v) for k, v in props.items()]
    with open(os.path.join(HERE, name + ".tres"), "w") as f:
        f.write("\n".join(lines) + "\n")
