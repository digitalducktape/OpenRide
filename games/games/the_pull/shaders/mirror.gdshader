// The handlebar mirror's glass: the mirror camera's SubViewport, flipped left-right as a mirror
// shows it, in an oval that fills the quad (discard outside it), lifted a little so the sled
// reads at 1 m, with a slight cool sheen.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

uniform sampler2D view : source_color, filter_linear;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	vec3 col = texture(view, vec2(1.0 - UV.x, UV.y)).rgb * 1.3;
	col = mix(col, vec3(0.75, 0.85, 1.0), 0.06 + 0.1 * smoothstep(0.75, 1.0, r));
	float sheen = 1.0 - smoothstep(0.0, 0.12, abs(UV.x + UV.y - 0.75));
	col += vec3(0.12) * sheen;
	ALBEDO = col;
}
