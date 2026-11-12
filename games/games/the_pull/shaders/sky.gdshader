// The dusk sky: one dome mesh around the camera (PullWorld keeps it on the camera), a gradient from the zenith
// through mid-blue to an orange horizon band, faint stars from one noise read. No cubemap, no
// sky pass. Graded like the world (without the vignette).
shader_type spatial;
render_mode unshaded, fog_disabled, cull_front, depth_draw_never;

#include "res://games/the_pull/shaders/pull_look.gdshaderinc"

uniform vec3 zenith : source_color = vec3(0.08, 0.11, 0.27);
uniform vec3 mid : source_color = vec3(0.23, 0.29, 0.54);
uniform vec3 horizon : source_color = vec3(0.91, 0.45, 0.23);
uniform vec3 glow_dir = vec3(0.35, 0.0, -0.94);  // where the sun went down (ahead, a little right)

varying vec3 v_dir;

void vertex() {
	// The dome follows the camera (PullWorld moves it), inside the far plane.
	v_dir = normalize(VERTEX);
}

void fragment() {
	float h = clamp(v_dir.y, -0.1, 1.0);
	float sunward = max(dot(normalize(v_dir.xz), normalize(glow_dir.xz)), 0.0);
	vec3 col = mix(mid, zenith, smoothstep(0.08, 0.6, h));
	float band = (1.0 - smoothstep(0.0, 0.16 + 0.12 * sunward, h)) * (0.55 + 0.45 * sunward * sunward);
	col = mix(col, horizon, band);
	// Long cloud banks near the horizon, their undersides lit by the last of the sun.
	vec2 cp = v_dir.xz / max(v_dir.y + 0.06, 0.04);
	float cloud = smoothstep(0.55, 0.8, vnoise(cp * vec2(1.2, 6.0) + vec2(13.0, 5.0)));
	float cloud_band = smoothstep(0.02, 0.07, h) * (1.0 - smoothstep(0.16, 0.3, h));
	vec3 cloud_col = mix(vec3(0.16, 0.12, 0.24), horizon * 1.15, 0.35 + 0.65 * sunward);
	col = mix(col, cloud_col, cloud * cloud_band * 0.85);
	float stars = smoothstep(0.93, 0.99, vnoise(v_dir.xz / max(v_dir.y, 0.2) * 90.0)) * smoothstep(0.25, 0.6, h);
	col += vec3(stars * 0.6);
	ALBEDO = grade(col, vec2(0.5));
}
