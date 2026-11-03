// The Pull's clay track and the dark infield around it (two materials of this shader). Lit by
// hand: ambient from the dusk sky plus the floodlight pools, both per vertex on a fine grid
// (PullMeshes.ground_grid), hazed per vertex, graded per pixel. Two noise reads a pixel for the
// grain; ruts and the chalk lines are arithmetic on the world position.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

#include "res://games/the_pull/shaders/pull_look.gdshaderinc"

uniform vec3 clay : source_color = vec3(0.47, 0.3, 0.22);
uniform vec3 chalk : source_color = vec3(0.93, 0.9, 0.84);
uniform float ruts = 1.0;  // 0 on the infield
uniform float lines = 1.0;  // the chalk side lines and the start line
uniform float half_width = 5.8;  // the chalk lines' x
uniform float grain_scale = 1.4;

varying vec3 v_light;
varying vec2 v_xz;
varying float v_haze;
varying float v_pool;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_xz = wp.xz;
	v_pool = pool_at(wp.xz);
	v_light = hemi(vec3(0.0, 1.0, 0.0)) * 0.42 + flood_color * v_pool * 1.65;
	v_haze = haze_amount(length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
}

void fragment() {
	float g = vnoise(v_xz * grain_scale);
	float g2 = vnoise(v_xz * vec2(0.35, 0.08) + vec2(31.0, 7.0));
	vec3 col = clay * (0.78 + 0.34 * g) * (0.85 + 0.3 * g2);
	// Clods: the brightest grain reads as lumps, lit on top, with a dark side.
	float clod = smoothstep(0.78, 0.86, g) * ruts;
	col = mix(col, clay * 1.25, clod * 0.6);
	col *= 1.0 - smoothstep(0.86, 0.95, g) * 0.35 * ruts;
	// Two worn grooves where the sleds' runners go, with chevron tyre treads across them.
	float rx = abs(abs(v_xz.x) - 0.9);
	float groove = (1.0 - smoothstep(0.18, 0.42, rx)) * ruts;
	float chevron = fract(v_xz.y * 2.2 + rx * 1.6 + g * 0.3);
	float tread = smoothstep(0.42, 0.5, chevron) * (1.0 - smoothstep(0.62, 0.7, chevron)) * groove;
	col *= 1.0 - groove * 0.2 - tread * 0.18;
	// The berm: loose clay banked against each barrier, darker and redder.
	float berm = smoothstep(half_width - 0.9, half_width + 0.3, abs(v_xz.x)) * ruts;
	col = mix(col, clay * vec3(0.78, 0.62, 0.55), berm * 0.6);
	vec3 lit = col * v_light;
	// A damp sheen where the floods fall (the track is watered between pulls).
	lit += flood_color * smoothstep(0.55, 1.1, v_pool) * (0.05 + 0.07 * g2) * (1.0 - groove);
	// Chalk: the side lines (antialiased with fwidth) and the start line at z = 0.
	float w = fwidth(v_xz.x) + 0.01;
	float side = 1.0 - smoothstep(0.07, 0.07 + w, abs(abs(v_xz.x) - half_width));
	float wz = fwidth(v_xz.y) + 0.01;
	float start = (1.0 - smoothstep(0.1, 0.1 + wz, abs(v_xz.y))) * step(abs(v_xz.x), half_width);
	float c = max(side, start) * lines * (0.75 + 0.25 * g);
	lit = mix(lit, chalk * (0.45 + v_light * 0.7), c);
	ALBEDO = grade(hazed(lit, v_haze), SCREEN_UV);
}
