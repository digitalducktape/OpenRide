# Writes Safe Cracker's SfxPreset parameter files (synth settings only, no samples) next to
# this file. Run: python3 games/games/safe_cracker/sfx/make_presets.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# wave: 0 sine, 1 triangle, 2 saw, 3 square, 4 pulse, 5 noise
PRESETS = {
    "tumbler_click": dict(wave=5, attack=0.001, sustain=0.004, decay=0.05, highpass=900.0, lowpass_start=5000.0,
                          lowpass_end=2500.0, repeats=2, repeat_gap=0.07, volume=0.45),
    "proximity_tick": dict(wave=0, attack=0.001, sustain=0.01, decay=0.04, freq_start=1500.0, freq_end=1500.0,
                           volume=0.22),
    "soft_alarm": dict(wave=0, attack=0.02, sustain=0.12, decay=0.25, freq_start=440.0, freq_end=330.0,
                       sweep_time=0.3, vibrato_depth=0.2, vibrato_rate=6.0, repeats=2, repeat_gap=0.3, volume=0.28),
    "vault_open": dict(wave=1, attack=0.004, sustain=0.05, decay=0.9, freq_start=392.0, freq_end=392.0,
                       jump_ratio=1.5, jump_time=0.1, punch=0.3, repeats=3, repeat_gap=0.13, volume=0.4),
    "door_creak": dict(wave=2, noise_mix=0.3, attack=0.08, sustain=0.5, decay=0.6, freq_start=120.0, freq_end=190.0,
                       sweep_time=1.0, vibrato_depth=1.2, vibrato_rate=9.0, lowpass_start=900.0, lowpass_end=500.0,
                       volume=0.25),
}

for name, props in PRESETS.items():
    lines = ['[gd_resource type="Resource" script_class="SfxPreset" format=3]', '',
             '[ext_resource type="Script" path="res://audio/SfxPreset.gd" id="1_sfx"]', '', '[resource]',
             'script = ExtResource("1_sfx")']
    lines += ["%s = %s" % (k, ("true" if v else "false") if isinstance(v, bool) else v) for k, v in props.items()]
    with open(os.path.join(HERE, name + ".tres"), "w") as f:
        f.write("\n".join(lines) + "\n")
