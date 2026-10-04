// The rider's shield: a faint visor strip over the handlebars, a hexagon grid under a lit top
// edge. `strength` follows the shield (0-1); `flash` spikes when it breaks or comes back. Kept
// faint, so it never fills the view.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float strength = 1.0;
uniform float flash = 0.0;
uniform vec3 tint : source_color = vec3(0.3, 0.75, 1.0);

float hex(vec2 p) {
	p.x *= 1.1547;
	p.y += mod(floor(p.x), 2.0) * 0.5;
	p = abs(fract(p) - 0.5);
	return abs(max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0);
}

void fragment() {
	vec2 uv = UV;
	float sides = smoothstep(0.0, 0.25, uv.x) * smoothstep(1.0, 0.75, uv.x);
	float top = smoothstep(0.45, 0.0, uv.y);
	float grid = smoothstep(0.1, 0.0, hex(uv * vec2(18.0, 3.2)));
	float a = (top * 0.55 + grid * 0.25 * (1.0 - uv.y)) * sides * strength * 0.45;
	a += flash * sides * (0.25 + grid * 0.6);
	ALBEDO = tint * a;
}
