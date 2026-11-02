// Balloon Pump's baked scenery (PumpMeshes): the lawn, the stall, tents, the wheel, trees, hills,
// bunting, the pump and its hose. Lit and hazed per vertex by hand, graded per pixel
// (pump_look.gdshaderinc). Vertex data (KartMeshKit flags):
//   COLOR.a  1 - sway weight: bunting and pennants sway.
//   UV.x     ground grain: one noise read breaks up the lawn.
//   UV.y     self-lit share (the stall's bulbs).
// `gloss` > 0 (the brass): a per-pixel highlight, so polished brass reads as metal.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

#include "res://games/balloon_pump/shaders/pump_look.gdshaderinc"

uniform float sway = 0.05;  // metres at full weight
uniform float sway_speed = 1.9;
uniform float gloss = 0.0;

varying vec3 v_light;
varying vec2 v_ground;
varying float v_grain;
varying float v_haze;
varying vec3 v_normal;
varying vec3 v_world;

void vertex() {
	float w = 1.0 - COLOR.a;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (w > 0.0) {
		float ph = dot(wp, vec3(0.41, 0.0, 0.27));
		VERTEX.z += sin(TIME * sway_speed + ph) * sway * w;
		VERTEX.x += sin(TIME * sway_speed * 1.31 + ph * 1.7) * sway * w * 0.6;
	}
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_light = mix(sun_light(wn), vec3(1.0), UV.y);
	v_ground = wp.xz;
	v_grain = UV.x;
	v_normal = wn;
	v_world = wp;
	v_haze = haze_amount(length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
}

void fragment() {
	vec3 col = COLOR.rgb * v_light;
	if (v_grain > 0.0) {
		float g = vnoise(v_ground * 1.3 + vec2(11.0, 5.0)) * 0.6 + vnoise(v_ground * 0.17) * 0.4;
		col *= mix(1.0, 0.82 + 0.36 * g, v_grain);
	}
	if (gloss > 0.0) {
		vec3 n = normalize(v_normal);
		vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
		vec3 h = normalize(normalize(sun_dir) + v);
		float nh = max(dot(n, h), 0.0);
		float edge = pow(1.0 - abs(dot(n, v)), 2.0);
		col += COLOR.rgb * sun_color * (pow(nh, 24.0) * 1.2 + edge * 0.25) * gloss;
	}
	ALBEDO = grade(hazed(col, v_haze), SCREEN_UV);
}
