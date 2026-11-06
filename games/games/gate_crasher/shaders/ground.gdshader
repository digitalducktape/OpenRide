// The ground: one grid. Raked arena sand inside the ring with a darker worn band along the
// course, mown grass stripes outside. All from world position and one noise read a pixel; the
// light and haze are per vertex.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

#include "res://games/gate_crasher/shaders/gate_look.gdshaderinc"

uniform vec3 sand : source_color = vec3(0.85, 0.74, 0.55);
uniform vec3 worn : source_color = vec3(0.70, 0.57, 0.40);
uniform vec3 grass : source_color = vec3(0.36, 0.56, 0.26);
uniform float straight = 130.0;
uniform float radius = 28.0;
uniform float track_half = 7.0;
uniform float ring = 9.0;

varying vec3 v_light;
varying float v_haze;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_light = sun_light(vec3(0.0, 1.0, 0.0));
	v_haze = haze_amount(length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
}

void fragment() {
	// The distance from the course: a stadium shape about the z axis.
	vec2 p = v_world.xz;
	float dz = max(abs(p.y) - straight * 0.5, 0.0);
	float d = abs(length(vec2(p.x, dz)) - radius);
	float n = vnoise(p * 0.35);
	float fine = vnoise(p * 3.1);
	vec3 col = mix(sand, worn, (1.0 - smoothstep(track_half * 0.35, track_half, d + (n - 0.5) * 3.0)) * 0.8);
	col *= 0.93 + 0.14 * fine;
	// Rake lines along the course.
	col *= 1.0 - 0.05 * step(0.5, fract(d * 1.4));
	float inside = 1.0 - step(ring + 0.2, d);
	float stripe = step(0.5, fract((p.x + p.y * 0.02) / 9.0));
	vec3 mown = grass * (0.92 + 0.14 * stripe) * (0.88 + 0.24 * n);
	col = mix(mown, col, inside);
	ALBEDO = grade(hazed(col * v_light, v_haze), SCREEN_UV);
}
