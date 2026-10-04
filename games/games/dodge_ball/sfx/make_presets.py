# Writes Dodge Ball's SfxPreset parameter files (synth settings only, no samples) next to
# this file. Run: python3 games/games/dodge_ball/sfx/make_presets.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

PRESETS = {
    "launch_whoosh": dict(wave=5, attack=0.12, sustain=0.05, decay=0.35, lowpass_start=300.0, lowpass_end=3200.0,
                          highpass=200.0, volume=0.35),
    "dodge_tick": dict(wave=1, attack=0.001, sustain=0.02, decay=0.12, freq_start=880.0, freq_end=1320.0,
                       sweep_time=0.06, punch=0.4, volume=0.35),
    "streak_chime": dict(wave=1, attack=0.002, sustain=0.08, decay=0.9, freq_start=1318.5, freq_end=1318.5,
                         vibrato_depth=0.06, vibrato_rate=5.0, jump_ratio=1.3348, jump_time=0.09, repeats=2,
                         repeat_gap=0.09, volume=0.4),
    "hit_body": dict(wave=0, attack=0.001, sustain=0.03, decay=0.3, freq_start=140.0, freq_end=45.0, sweep_time=0.18,
                     punch=0.7, noise_mix=0.15, lowpass_start=1800.0, lowpass_end=300.0, volume=0.7),
    "shield_zap": dict(wave=3, attack=0.002, sustain=0.05, decay=0.45, freq_start=1600.0, freq_end=180.0,
                       sweep_time=0.4, noise_mix=0.25, lowpass_start=6000.0, lowpass_end=800.0, volume=0.35),
    "shield_ready": dict(wave=1, attack=0.01, sustain=0.1, decay=0.4, freq_start=523.3, freq_end=1046.5,
                         sweep_time=0.25, vibrato_depth=0.1, vibrato_rate=8.0, volume=0.3),
    "game_over": dict(wave=2, attack=0.01, sustain=0.3, decay=0.9, freq_start=330.0, freq_end=110.0, sweep_time=1.0,
                      lowpass_start=2500.0, lowpass_end=400.0, volume=0.4),
    "catch_chime": dict(wave=1, attack=0.002, sustain=0.04, decay=0.35, freq_start=987.8, freq_end=987.8,
                        jump_ratio=1.4983, jump_time=0.05, punch=0.3, volume=0.4),
    "miss_whiff": dict(wave=5, attack=0.02, sustain=0.02, decay=0.25, lowpass_start=1400.0, lowpass_end=300.0,
                       highpass=120.0, volume=0.3),
    "fumble_thud": dict(wave=0, attack=0.001, sustain=0.02, decay=0.2, freq_start=220.0, freq_end=110.0,
                        sweep_time=0.15, punch=0.4, noise_mix=0.2, lowpass_start=1500.0, lowpass_end=400.0,
                        volume=0.5),
    "wind": dict(wave=5, attack=0.0, sustain=1.6, decay=0.0, lowpass_start=900.0, lowpass_end=900.0,
                 highpass=180.0, volume=0.45, loop=True),
}

for name, props in PRESETS.items():
    lines = ['[gd_resource type="Resource" script_class="SfxPreset" format=3]', '',
             '[ext_resource type="Script" path="res://audio/SfxPreset.gd" id="1_sfx"]', '', '[resource]',
             'script = ExtResource("1_sfx")']
    lines += ["%s = %s" % (k, ("true" if v else "false") if isinstance(v, bool) else v) for k, v in props.items()]
    with open(os.path.join(HERE, name + ".tres"), "w") as f:
        f.write("\n".join(lines) + "\n")
