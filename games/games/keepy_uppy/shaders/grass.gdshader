// Keepy Uppy's grass tufts and flowers: a MultiMesh of crossed blade cards near the camera, swaying
// with the wind (COLOR.a = 1 - sway weight up the blade) and flattening where the downdraft's band
// passes. The flower heads take the instance colour; blades keep their own. Lit per vertex.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://games/keepy_uppy/shaders/keepy_look.gdshaderinc"

uniform vec3 downdraft = vec3(-40.0, 6.0, 0.0);
uniform float dim = 1.0;

varying vec3 v_col;
varying float v_haze;

void vertex() {
	float w = 1.0 - COLOR.a;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 o = sway_offset(root, w, 0.07, TIME);
	float into = (root.z - downdraft.x) / downdraft.y;
	float flat_ = smoothstep(-1.0, -0.3, into) * (1.0 - smoothstep(0.0, 0.3, into)) * downdraft.z;
	o.z += flat_ * w * 0.18;
	VERTEX.y *= 1.0 - flat_ * 0.55 * w;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * o);
	// The flower head (white in the mesh) takes the instance colour.
	vec3 c = COLOR.rgb;
	if (COLOR.r > 0.99 && COLOR.g > 0.99) {
		c = INSTANCE_CUSTOM.rgb;
	}
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = c * mix(sun_light(vec3(0.0, 1.0, 0.0)), sun_light(wn), 0.4) * dim;
	// The downdraft's band: flattened and in shadow.
	v_col *= 1.0 - flat_ * 0.5;
	v_haze = haze_amount(length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
}

void fragment() {
	ALBEDO = grade(hazed(v_col, v_haze), SCREEN_UV);
}
