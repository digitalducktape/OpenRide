// Full-screen feedback over the 3D view (under the HUD): a vignette that flashes on a hit
// (`flash`, in `flash_color`) and glows gold at the edges while the power bonus is on
// (`power`). Edges only, so the centre of the view never changes: comfortable on a stationary
// bike.
shader_type canvas_item;

uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.15, 0.1, 1.0);
uniform float power = 0.0;
uniform vec4 power_color : source_color = vec4(1.0, 0.75, 0.2, 1.0);
uniform float base_vignette = 0.25;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.x *= 1.25;
	float r = length(p);
	float v = smoothstep(0.75, 1.45, r);
	vec3 col = vec3(0.0);
	float a = v * base_vignette;
	float pw = v * power * (0.55 + 0.15 * sin(TIME * 6.0));
	col = mix(col, power_color.rgb, pw / max(a + pw, 0.001));
	a += pw;
	float f = smoothstep(0.45, 1.3, r) * flash;
	col = mix(col, flash_color.rgb, f / max(a + f, 0.001));
	a += f;
	COLOR = vec4(col, clamp(a, 0.0, 0.85));
}
