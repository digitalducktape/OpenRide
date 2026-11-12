// The grandstand: one MultiMesh of quads turned to face the camera about y, each drawn as a seated
// person in its instance colour, hopping with `excitement`. Light per vertex.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://games/gate_crasher/shaders/gate_look.gdshaderinc"

uniform float excitement = 0.0;  // 0-1

varying vec3 v_light;
varying float v_haze;
varying vec3 v_tint;
varying float v_skin;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.283;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	vec3 fwd = normalize(to_cam + vec3(0.0001, 0.0, 0.0));
	vec3 right = vec3(fwd.z, 0.0, -fwd.x);
	float hop = abs(sin(TIME * (5.0 + 3.0 * INSTANCE_CUSTOM.y) + phase)) * (0.02 + 0.28 * excitement * INSTANCE_CUSTOM.y);
	VERTEX = right * VERTEX.x + vec3(0.0, VERTEX.y + hop, 0.0);
	v_light = hemi(vec3(0.0, 1.0, 0.0)) + sun_color * 0.4;
	v_haze = haze_amount(length(CAMERA_POSITION_WORLD - origin));
	v_tint = COLOR.rgb;
	v_skin = 0.7 + 0.3 * INSTANCE_CUSTOM.z;
}

void fragment() {
	vec2 p = UV * vec2(1.0, 1.6);
	float head = length(p - vec2(0.5, 0.32)) - 0.2;
	vec2 b = p - vec2(0.5, 1.12);
	float body = length(max(abs(b) - vec2(0.16, 0.42), 0.0)) - 0.14;
	if (min(head, body) > 0.0) {
		discard;
	}
	vec3 col = head <= body ? vec3(0.86, 0.66, 0.5) * v_skin : v_tint;
	ALBEDO = grade(hazed(col * v_light, v_haze), SCREEN_UV);
}
