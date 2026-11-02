// A balloon on the nozzle, on the rack or in flight (ART_BIBLE §2): its kind's colour, lit per
// pixel (pump_look.gdshaderinc, balloon_light). `taut` (0-1) stretches the sheen as it nears
// full; `wobble` shakes it while it leaks; `gold` adds a glint that sweeps across. The mesh's
// knot is at the origin and the balloon grows up from it (PumpMeshes.balloon).
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

#include "res://games/balloon_pump/shaders/pump_look.gdshaderinc"

uniform vec3 body_color : source_color = vec3(1.0, 0.31, 0.59);
uniform float taut = 0.0;
uniform float wobble = 0.0;
uniform float gold = 0.0;

varying vec3 v_normal;
varying vec3 v_world;
varying vec3 v_local;

void vertex() {
	if (wobble > 0.0) {
		float k = smoothstep(0.1, 1.0, VERTEX.y);
		VERTEX.xz *= 1.0 + sin(TIME * 9.0 + VERTEX.y * 4.0) * 0.03 * wobble * k;
		VERTEX.y *= 1.0 - 0.04 * wobble * k;
	}
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_normal);
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
	// The knot and neck (COLOR.r < 1) are darker, thicker rubber.
	vec3 base = body_color * mix(0.62, 1.0, COLOR.r);
	vec3 col = balloon_light(base, n, v, taut);
	if (gold > 0.0) {
		float sweep = fract(TIME * 0.45);
		float band = smoothstep(0.08, 0.0, abs(fract(v_local.y * 0.5 - v_local.x * 0.4 - sweep) - 0.5));
		col += vec3(1.0, 0.9, 0.55) * band * 0.6 * gold;
	}
	ALBEDO = grade(col, SCREEN_UV);
}
