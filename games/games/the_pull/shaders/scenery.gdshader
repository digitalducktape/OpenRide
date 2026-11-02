// The Pull's baked scenery (stands, barriers, boards, towers, tents, the far fair, the Full
// Pull arch), the sled, the weight box, the bike and the best flag. Vertex-coloured with painted
// AO (PullMeshes), lit and hazed per vertex by hand, graded per pixel. Vertex data:
//   COLOR.a  1 - sway weight: the flag's cloth and the bunting move.
//   UV.x     how much the floodlight pools reach it (0 on the far horizon).
//   UV.y     glow: lamps, fair lights, board faces and the line are self-lit (× `glow_gain`).
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

#include "res://games/the_pull/shaders/pull_look.gdshaderinc"

uniform float sway = 0.0;  // metres at full weight
uniform float wave = 0.0;  // the flag: a travelling wave along local x
uniform float glow_gain = 1.0;  // the Full Pull flare lifts it
uniform float self_lit = 0.0;  // 0-1: share of light that ignores the dusk (the bars up close)

varying vec3 v_light;
varying float v_haze;

void vertex() {
	float w = 1.0 - COLOR.a;
	if (w > 0.0) {
		float ph = dot((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, vec3(0.31, 0.0, 0.23));
		VERTEX.x += sin(TIME * 1.7 + ph) * sway * w;
		VERTEX.z += sin(TIME * 7.0 - VERTEX.x * 6.0) * wave * w;
		VERTEX.y += sin(TIME * 5.3 - VERTEX.x * 5.0) * wave * 0.3 * w;
	}
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 light = sun_light(wn) * 0.7 + flood_color * pool_at(wp.xz) * UV.x * (0.65 + 0.35 * max(wn.y, 0.0)) * 1.2;
	light = mix(light, vec3(1.0), self_lit);
	v_light = mix(light, vec3(1.15 * glow_gain), UV.y);
	v_haze = haze_amount(length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz)) * (1.0 - UV.y * 0.6);
}

void fragment() {
	ALBEDO = grade(hazed(COLOR.rgb * v_light, v_haze), SCREEN_UV);
}
