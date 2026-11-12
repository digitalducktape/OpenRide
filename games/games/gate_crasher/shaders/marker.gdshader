// The take-off line and the chevrons leading to it, every fence's in one mesh: UV.x is the fence
// and UV.y the piece (0 the line, 1-3 the chevrons). Only `active` shows. `stage` is the beats
// counted so far: from the first the whole approach turns gold, and on the line it pulses teal.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://games/gate_crasher/shaders/gate_look.gdshaderinc"

uniform float active = 0.0;
uniform float stage = 0.0;  // 0 none, 1-3 chevrons lit, 4 the line is live
uniform vec3 lit : source_color = vec3(1.0, 0.82, 0.2);
uniform vec3 live : source_color = vec3(0.18, 0.77, 0.7);

varying vec3 v_col;

void vertex() {
	if (abs(UV.x - active) > 0.5) {
		VERTEX = vec3(0.0, -50.0, 0.0);
	}
	vec3 col = mix(COLOR.rgb, lit, step(0.5, stage));
	if (UV.y < 0.5 && stage > 3.5) {
		col = mix(lit, live, 0.55 + 0.45 * sin(TIME * 14.0));
	}
	v_col = col;
}

void fragment() {
	ALBEDO = grade(v_col, SCREEN_UV);
}
