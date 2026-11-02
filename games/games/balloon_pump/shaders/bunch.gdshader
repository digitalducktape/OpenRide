// The bunch over the stall (ART_BIBLE §1: the score you can see): one MultiMesh of balloons on
// strings (PumpMeshes.bunch_balloon). Each instance's local -Y points at the tether, and it
// sways about the tether in the vertex shader, string and all. Per instance:
//   INSTANCE_COLOR       the balloon's colour
//   INSTANCE_CUSTOM.x    its sway phase
//   INSTANCE_CUSTOM.y    1 for a gold balloon (a glint)
//   INSTANCE_CUSTOM.z    its string's length, in the instance's local units
// Vertex data: UV.x = 0 on the balloon, 0-1 along the string; COLOR.r darker on the knot.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://games/balloon_pump/shaders/pump_look.gdshaderinc"

const float KNOT_Y = -1.0;  // the knot's local height (PumpMeshes.BUNCH_KNOT)

uniform float bob = 0.0;  // 0-1: a celebration bob (a heat won)

varying vec3 v_normal;
varying vec3 v_world;
varying float v_string;
varying float v_gold;
varying vec3 v_color;

void vertex() {
	float len = INSTANCE_CUSTOM.z;
	v_string = UV.x;
	if (UV.x > 0.0) {
		VERTEX.y = KNOT_Y - UV.x * len;
	}
	// Sway about the tether (local (0, KNOT_Y - len, 0)): a small rotation about x and z.
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float ax = sin(TIME * 0.9 + ph) * 0.07 + sin(TIME * 2.3 + ph * 2.0) * 0.02 + bob * sin(TIME * 7.0 + ph) * 0.06;
	float az = sin(TIME * 0.73 + ph * 1.3) * 0.06;
	vec3 pivot = vec3(0.0, KNOT_Y - len, 0.0);
	vec3 p = VERTEX - pivot;
	vec3 nn = NORMAL;
	float cx = cos(ax);
	float sx = sin(ax);
	float cz = cos(az);
	float sz = sin(az);
	p = vec3(p.x * cz - p.y * sz, p.x * sz + p.y * cz, p.z);
	p = vec3(p.x, p.y * cx - p.z * sx, p.y * sx + p.z * cx);
	nn = vec3(nn.x * cz - nn.y * sz, nn.x * sz + nn.y * cz, nn.z);
	nn = vec3(nn.x, nn.y * cx - nn.z * sx, nn.y * sx + nn.z * cx);
	VERTEX = p + pivot;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(nn, 0.0)).xyz);
	v_gold = INSTANCE_CUSTOM.y;
	v_color = COLOR.rgb;
}

void fragment() {
	vec3 n = normalize(v_normal);
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
	vec3 col;
	if (v_string > 0.0) {
		col = vec3(0.95, 0.93, 0.9) * hemi(n) * 1.1;
	} else {
		col = balloon_light(v_color, n, v, 0.7);
		if (v_gold > 0.0) {
			float band = smoothstep(0.1, 0.0, abs(fract(v_world.y * 0.9 - v_world.x * 0.5 - TIME * 0.4) - 0.5));
			col += vec3(1.0, 0.9, 0.55) * band * 0.5;
		}
	}
	ALBEDO = grade(col, SCREEN_UV);
}
