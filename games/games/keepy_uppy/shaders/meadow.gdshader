// Keepy Uppy's built things and scenery: the meadow (hills, hedges, trees), the fan crate and its
// blades, the height pole and its streamers, the clouds and the birds. Lit and hazed per vertex
// by hand, graded per pixel (keepy_look.gdshaderinc). Vertex data (KeepyMeshes):
//   COLOR.a  1 - sway weight (leaves, streamers).
//   UV.x     ground grain on the hills; on a bird, the wings (flapped by `flap`).
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

#include "res://games/keepy_uppy/shaders/keepy_look.gdshaderinc"

uniform float sway = 0.05;  // metres at full weight
uniform float self_lit = 0.0;  // 0-1: light that ignores the sun (clouds a little)
uniform float flap = 0.0;  // birds: 0 perched, 1 flying
uniform float grain = 1.0;
uniform float dim = 1.0;  // the rain's shade on this object

varying vec3 v_light;
varying vec2 v_ground;
varying float v_grain;
varying float v_haze;

void vertex() {
	float w = 1.0 - COLOR.a;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (w > 0.0) {
		VERTEX += sway_offset(wp, w, sway, TIME);
	}
	if (flap > 0.0 && UV.x > 0.5) {
		float side = sign(VERTEX.x);
		float beat = sin(TIME * 22.0) * flap;
		VERTEX.y += abs(VERTEX.x) * beat * 1.6;
		VERTEX.x -= side * abs(beat) * 0.03;
	}
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_light = mix(sun_light(wn), vec3(1.0), self_lit) * dim;
	v_ground = wp.xz;
	v_grain = UV.x * grain * (1.0 - step(0.5, flap));
	v_haze = haze_amount(length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
}

void fragment() {
	vec3 col = COLOR.rgb;
	if (v_grain > 0.0) {
		float g = vnoise(v_ground * 0.35 + vec2(17.0, 3.0));
		col *= mix(1.0, 0.82 + 0.36 * g, v_grain);
	}
	ALBEDO = grade(hazed(col * v_light, v_haze), SCREEN_UV);
}
