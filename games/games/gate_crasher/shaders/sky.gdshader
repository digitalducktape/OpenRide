// The morning sky: one dome around the camera. A clean blue from the zenith to a pale warm
// horizon, with soft cumulus from two noise reads. Graded like the world, without the vignette.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_front, depth_draw_never;

#include "res://games/gate_crasher/shaders/gate_look.gdshaderinc"

uniform vec3 zenith : source_color = vec3(0.26, 0.52, 0.86);
uniform vec3 horizon : source_color = vec3(0.93, 0.89, 0.78);

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	float h = clamp(v_dir.y, -0.05, 1.0);
	vec3 col = mix(horizon, zenith, smoothstep(0.0, 0.42, h));
	vec2 cp = v_dir.xz / max(v_dir.y + 0.12, 0.08);
	float c = vnoise(cp * 1.4) * 0.65 + vnoise(cp * 3.7 + 9.0) * 0.35;
	float cloud = smoothstep(0.52, 0.72, c) * smoothstep(0.02, 0.14, h);
	col = mix(col, vec3(1.0, 0.98, 0.94), cloud * 0.9);
	ALBEDO = grade(col, vec2(0.5));
}
