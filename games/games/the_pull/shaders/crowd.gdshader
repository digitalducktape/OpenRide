// The crowd in the stands: one MultiMesh of quads, each turned to face the camera about y, drawn
// as a person (a round head over rounded shoulders) in its instance colour. They hop with
// `excitement`. Lit by the floodlight pools per vertex, hazed per vertex.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://games/the_pull/shaders/pull_look.gdshaderinc"

uniform float excitement = 0.0;  // 0-1

varying vec3 v_light;
varying float v_haze;
varying vec3 v_tint;
varying float v_skin;
varying float v_arms;
varying float v_cap;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.283;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	vec3 fwd = normalize(to_cam + vec3(0.0001, 0.0, 0.0));
	vec3 right = vec3(fwd.z, 0.0, -fwd.x);
	float hop = abs(sin(TIME * (5.0 + 3.0 * INSTANCE_CUSTOM.y) + phase)) * (0.04 + 0.3 * excitement * INSTANCE_CUSTOM.y);
	// Instances are placed by translation only (PullWorld), so a world offset is a local one.
	VERTEX = right * VERTEX.x + vec3(0.0, VERTEX.y + hop, 0.0);
	vec3 wp = origin + VERTEX;
	v_light = hemi(vec3(0.0, 1.0, 0.0)) * 0.6 + flood_color * pool_at(wp.xz) * 1.1;
	v_haze = haze_amount(length(CAMERA_POSITION_WORLD - wp));
	v_tint = COLOR.rgb;
	v_skin = 0.7 + 0.3 * INSTANCE_CUSTOM.z;
	// Arms go up while the crowd cheers, each figure on its own beat.
	v_arms = step(0.35, excitement * INSTANCE_CUSTOM.y) * step(0.0, sin(TIME * 3.0 + phase));
	v_cap = step(0.6, fract(INSTANCE_CUSTOM.x * 7.3));
}

void fragment() {
	// UV: x 0-1 across, y 0 at the top. A head circle and a rounded body below it.
	vec2 p = UV * vec2(1.0, 1.6);
	float head = length(p - vec2(0.5, 0.32)) - 0.2;
	vec2 b = p - vec2(0.5, 1.12);
	float body = length(max(abs(b) - vec2(0.16, 0.42), 0.0)) - 0.14;
	// Raised arms: a rounded bar up from each shoulder.
	vec2 la = vec2(abs(p.x - 0.5) - 0.32, p.y - 0.62);
	float arm = (length(max(abs(la) - vec2(0.0, 0.3), 0.0)) - 0.06) + (1.0 - v_arms) * 10.0;
	float d = min(min(head, body), arm);
	if (d > 0.0) {
		discard;
	}
	vec3 skin = vec3(0.86, 0.66, 0.5) * v_skin;
	vec3 col = v_tint;
	if (head <= min(body, arm)) {
		col = (v_cap > 0.5 && p.y < 0.3) ? v_tint * 0.7 : skin;
	} else if (arm < body && p.y < 0.45) {
		col = skin;
	}
	ALBEDO = grade(hazed(col * v_light, v_haze), SCREEN_UV);
}
