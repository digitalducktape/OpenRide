# Writes Tug of War's SfxPreset parameter files (synth settings only, no samples) next to
# this file. Run: python3 games/games/tug_of_war/sfx/make_presets.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# wave: 0 sine, 1 triangle, 2 saw, 3 square, 4 pulse, 5 noise
PRESETS = {
    "rope_creak": dict(wave=2, noise_mix=0.35, attack=0.02, sustain=0.08, decay=0.25, freq_start=180.0,
                       freq_end=140.0, sweep_time=0.2, vibrato_depth=1.5, vibrato_rate=14.0,
                       lowpass_start=1200.0, lowpass_end=600.0, volume=0.3),
    "crowd_swell": dict(wave=5, attack=0.8, sustain=0.3, decay=0.9, lowpass_start=500.0, lowpass_end=2400.0,
                        highpass=200.0, volume=0.35),
    "surge_drumroll": dict(wave=0, noise_mix=0.25, attack=0.001, sustain=0.01, decay=0.08, freq_start=120.0,
                           freq_end=90.0, sweep_time=0.06, punch=0.5, repeats=8, repeat_gap=0.11, volume=0.55),
    "win_sting": dict(wave=1, attack=0.004, sustain=0.06, decay=0.7, freq_start=523.3, freq_end=523.3,
                      jump_ratio=1.4983, jump_time=0.07, punch=0.3, repeats=3, repeat_gap=0.14, volume=0.45),
    "lose_sting": dict(wave=2, attack=0.01, sustain=0.25, decay=0.9, freq_start=294.0, freq_end=98.0,
                       sweep_time=0.9, lowpass_start=2500.0, lowpass_end=300.0, volume=0.4),
    "splash": dict(wave=5, attack=0.005, sustain=0.05, decay=0.5, lowpass_start=6000.0, lowpass_end=900.0,
                   highpass=150.0, volume=0.5),
}

for name, props in PRESETS.items():
    lines = ['[gd_resource type="Resource" script_class="SfxPreset" format=3]', '',
             '[ext_resource type="Script" path="res://audio/SfxPreset.gd" id="1_sfx"]', '', '[resource]',
             'script = ExtResource("1_sfx")']
    lines += ["%s = %s" % (k, ("true" if v else "false") if isinstance(v, bool) else v) for k, v in props.items()]
    with open(os.path.join(HERE, name + ".tres"), "w") as f:
        f.write("\n".join(lines) + "\n")
