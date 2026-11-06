shader_type canvas_item;
render_mode blend_add;

// The power on the wires (#81; ART_BIBLE.md §7): soft even dashes running from the shed down the
// line, faster and brighter with the rider's supply. UV.x is the length along the wire, UV.y its
// channel (0 the trunk, 1-4 a district's feeder). The dash is symmetric, with no head and no tail:
// the silhouette rule (a round head with a tapering tail must never move across the screen).

uniform float phase = 0.0;  // px travelled: advanced by GridStage, so a change of speed never jumps
uniform float glow = 0.5;  // 0-1, the trunk's brightness
uniform vec4 levels = vec4(1.0);  // the four feeders
uniform vec4 tint : source_color = vec4(1.0, 0.84, 0.5, 1.0);

const float SPACING = 46.0;

varying float v_level;

void vertex() {
	float c = UV.y;
	v_level = c < 0.5 ? 1.0 : (c < 1.5 ? levels.x : (c < 2.5 ? levels.y : (c < 3.5 ? levels.z : levels.w)));
}

void fragment() {
	float d = fract((UV.x - phase) / SPACING);
	float dash = smoothstep(0.0, 0.22, d) * smoothstep(0.5, 0.28, d);
	float a = dash * glow * v_level;
	COLOR = vec4(tint.rgb * a, a);
}
