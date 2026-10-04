// A beat ring (Cadence Karaoke, #42): the outline of a rectangle that flies down the tunnel, one
// per beat. Only the border is drawn (the rest is discarded), so it costs almost no fill rate.
shader_type spatial;
render_mode unshaded, fog_disabled, blend_add, cull_disabled, depth_draw_never;

uniform vec3 ring_color : source_color = vec3(0.2, 0.8, 1.0);
uniform float pulse = 0.0;  // 0-1, how bright the ring is on this beat
uniform float border = 0.012;  // the outline's thickness, as a share of the quad
uniform float fade = 0.035;

void fragment() {
	vec2 e = min(UV, 1.0 - UV);
	float edge = min(e.x * 0.45, e.y);  // the quad is wider than it is tall
	if (edge > border) {
		discard;
	}
	float f = exp(-fade * length(VERTEX));
	ALBEDO = ring_color * (0.6 + 2.0 * pulse) * f;
}
