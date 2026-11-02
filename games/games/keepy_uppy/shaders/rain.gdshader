// Keepy Uppy's falling streaks, alpha blended (ART_BIBLE §7): the rain under the rain cloud (an
// open cylinder card) and the downdraft's curtain of dark, slanting air rolling toward the fan (a
// wide vertical card). `amount` fades it in and out; `tint`, `fall` and `density` set its look.
shader_type spatial;
render_mode unshaded, fog_disabled, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float amount = 0.0;
uniform vec3 tint : source_color = vec3(0.78, 0.82, 0.88);
uniform float fall = 2.2;  // UV a second
uniform float columns = 40.0;
uniform float density = 0.62;  // higher: fewer, thinner streaks
uniform float opacity = 0.45;
uniform float slant = 0.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

void fragment() {
	// UV.y runs down the card (0 at its top), so subtracting time moves the streaks down.
	vec2 uv = vec2(UV.x * columns + UV.y * slant, UV.y * 1.5 - TIME * fall);
	float n = texture(noise_tex, vec2(uv.x / 16.0, uv.y * 0.12)).r;
	float streak = smoothstep(density, density + 0.18, n);
	float fade = smoothstep(0.0, 0.15, UV.y) * (1.0 - smoothstep(0.75, 1.0, UV.y));
	fade *= smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.88, 1.0, UV.x)) * 0.5 + 0.5;
	ALBEDO = tint;
	ALPHA = streak * fade * amount * opacity;
}
