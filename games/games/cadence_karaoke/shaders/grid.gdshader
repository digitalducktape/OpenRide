// The tunnel's surfaces (Cadence Karaoke, #42): a dark panel with glowing lines that scroll toward
// the rider and flare on the beat. Unshaded and fogged by hand (see verge.gdshader for why).
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

uniform vec3 line_color : source_color = vec3(0.2, 0.8, 1.0);
uniform vec3 base_color : source_color = vec3(0.02, 0.03, 0.06);
uniform vec3 across_axis = vec3(1.0, 0.0, 0.0);  // which way the cross lines run on this surface
uniform float scroll = 0.0;
uniform float beat = 0.0;  // 0-1, a flare that decays after each beat
uniform float spacing = 2.5;
uniform float fade = 0.03;

varying vec3 world_pos;

float lines(float x, float w) {
	float f = abs(fract(x) - 0.5);
	return smoothstep(0.5 - w, 0.5, f);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float along = (world_pos.z - scroll) / spacing;
	float across = dot(world_pos, across_axis) / spacing;
	float glow = max(lines(along, 0.035), lines(across, 0.025) * 0.7);
	vec3 col = base_color + line_color * glow * (0.55 + beat * 1.6);
	float f = exp(-fade * length(VERTEX));
	ALBEDO = col * f;
}
