# Writes the four DodgeTimeOfDay presets (dawn, day, dusk, night) next to this file.
# Run: python3 games/games/dodge_ball/tod/make_presets.py
import os

HERE = os.path.dirname(os.path.abspath(__file__))

PRESETS = {
    "dawn": dict(sky_top=(0.32, 0.42, 0.72), sky_horizon=(1.0, 0.66, 0.48), sky_ground=(0.28, 0.24, 0.26),
                 clouds=0.55, cloud_color=(1.0, 0.78, 0.7), stars=0.15, halo=0.9, sun_size=0.04,
                 sun_elevation=9.0, sun_azimuth=-35.0, sun_color=(1.0, 0.72, 0.5), sun_energy=0.95,
                 ambient=(0.62, 0.55, 0.62), ambient_energy=0.55, fog_color=(0.92, 0.68, 0.58), fog_density=0.008,
                 lamp_glow=0.25, headlight=0.0, ball_glow=0.05),
    "day": dict(sky_top=(0.2, 0.46, 0.92), sky_horizon=(0.72, 0.84, 0.96), sky_ground=(0.3, 0.34, 0.3),
                clouds=0.5, cloud_color=(1.0, 1.0, 1.0), stars=0.0, halo=0.35, sun_size=0.03,
                sun_elevation=52.0, sun_azimuth=-28.0, sun_color=(1.0, 0.97, 0.9), sun_energy=1.15,
                ambient=(0.6, 0.7, 0.85), ambient_energy=0.62, fog_color=(0.74, 0.84, 0.95), fog_density=0.0055,
                lamp_glow=0.0, headlight=0.0, ball_glow=0.0),
    "dusk": dict(sky_top=(0.16, 0.13, 0.36), sky_horizon=(1.0, 0.42, 0.26), sky_ground=(0.2, 0.15, 0.18),
                 clouds=0.6, cloud_color=(0.95, 0.5, 0.45), stars=0.3, halo=1.0, sun_size=0.045,
                 sun_elevation=5.0, sun_azimuth=30.0, sun_color=(1.0, 0.5, 0.3), sun_energy=0.8,
                 ambient=(0.5, 0.4, 0.55), ambient_energy=0.5, fog_color=(0.75, 0.38, 0.32), fog_density=0.009,
                 lamp_glow=0.7, headlight=0.35, ball_glow=0.15),
    "night": dict(sky_top=(0.01, 0.015, 0.05), sky_horizon=(0.06, 0.08, 0.17), sky_ground=(0.02, 0.02, 0.03),
                  clouds=0.25, cloud_color=(0.12, 0.14, 0.22), stars=1.0, halo=0.5, sun_size=0.025,
                  sun_elevation=38.0, sun_azimuth=25.0, sun_color=(0.6, 0.7, 1.0), sun_energy=0.18,
                  ambient=(0.22, 0.27, 0.45), ambient_energy=0.28, fog_color=(0.04, 0.05, 0.1), fog_density=0.013,
                  lamp_glow=1.0, headlight=1.0, ball_glow=0.35),
}


def value(v):
    if isinstance(v, tuple):
        return "Color(%s, %s, %s, 1)" % v
    return repr(float(v))


for name, props in PRESETS.items():
    lines = [
        '[gd_resource type="Resource" script_class="DodgeTimeOfDay" format=3]',
        "",
        '[ext_resource type="Script" path="res://games/dodge_ball/TimeOfDay.gd" id="1_tod"]',
        "",
        "[resource]",
        'script = ExtResource("1_tod")',
        'id = "%s"' % name,
    ]
    lines += ["%s = %s" % (k, value(v)) for k, v in props.items()]
    with open(os.path.join(HERE, name + ".tres"), "w") as f:
        f.write("\n".join(lines) + "\n")
