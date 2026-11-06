shader_type canvas_item;
render_mode blend_add;

// Slow glints on the river (#81): a strip mesh over the bake, UV.y running down the river. Broken
// horizontal ripples that drift, tinted by the sky (`tint`), never a redraw.

uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.6, 1.0);
uniform float strength = 0.5;

float ripple(vec2 p) {
	return sin(p.x * 0.09 + TIME * 0.5 + sin(p.y * 0.21) * 2.0) * sin(p.y * 0.55 - TIME * 0.7);
}

varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	float scale = mix(2.4, 0.6, UV.y);
	float r = ripple(world * scale);
	float line = smoothstep(0.55, 0.92, r);
	float a = line * strength * mix(0.5, 1.0, UV.y);
	COLOR = vec4(tint.rgb * a, a);
}
