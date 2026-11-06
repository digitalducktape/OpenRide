// Gate Crasher's baked scenery, the rails and the horse. Vertex-coloured with painted AO
// (GateMeshes), lit and hazed per vertex by hand, graded per pixel.
//   COLOR.a  1 - sway weight: the mane and the bunting move.
//   UV.y     glow: self-lit share.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

#include "res://games/gate_crasher/shaders/gate_look.gdshaderinc"

uniform float sway = 0.0;  // metres at full weight
uniform float self_lit = 0.0;  // 0-1: the horse keeps its light whichever way the course turns
uniform float rim = 0.0;  // a warm rim of sun round the edges (the horse up close)

varying vec3 v_light;
varying float v_haze;

void vertex() {
	float w = 1.0 - COLOR.a;
	if (w > 0.0) {
		float ph = VERTEX.z * 5.0 + VERTEX.x * 3.0;
		VERTEX.x += sin(TIME * 7.0 + ph) * sway * w;
		VERTEX.y += sin(TIME * 5.3 + ph) * sway * 0.5 * w;
	}
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 light = sun_light(wn);
	light = mix(light, vec3(1.0), self_lit);
	float facing = max(dot(wn, normalize(CAMERA_POSITION_WORLD - wp)), 0.0);
	light += sun_color * rim * pow(1.0 - facing, 2.5);
	v_light = mix(light, vec3(1.15), UV.y);
	v_haze = haze_amount(length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
}

void fragment() {
	ALBEDO = grade(hazed(COLOR.rgb * v_light, v_haze), SCREEN_UV);
}
