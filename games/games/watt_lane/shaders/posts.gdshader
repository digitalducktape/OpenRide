// Watt Lane's street lamps (ART_BIBLE.md §6): one MultiMesh of posts down both shoulders, moved
// toward the rider by `scroll` in the vertex shader (each wraps to the far end, in the haze), so
// GDScript never touches them. Vertex colour is the part's colour; alpha 1 marks the lamp head,
// which glows sodium. Opaque.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://games/watt_lane/shaders/wl_look.gdshaderinc"

uniform float scroll = 0.0;
uniform float spacing = 40.0;
uniform vec3 sodium : source_color = vec3(1.0, 0.6, 0.3);

varying float dist;
varying float lamp;

void vertex() {
	VERTEX.z += fract(scroll / spacing) * spacing;
	dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	lamp = COLOR.a;
}

void fragment() {
	vec3 c = mix(COLOR.rgb, sodium * 1.6, lamp);
	ALBEDO = grade(haze(c, dist), SCREEN_UV);
}
