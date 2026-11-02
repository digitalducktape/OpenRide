// Keepy Uppy's column of air from the fan (ART_BIBLE §7): soft white streaks rising up an open
// cone, additive and faint (art-director note: under about 0.25 at full lift, so the balloon and
// its birds read through it). `speed` follows the lift; a downdraft turns the streaks downward.
shader_type spatial;
render_mode unshaded, fog_disabled, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength = 0.5;  // 0-1: how much air the fan moves
uniform float speed = 1.0;  // the streaks' climb, in UV a second (negative: falling)
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying float v_edge;

void vertex() {
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Brighter where the cone is seen edge-on, so it reads as a column, not a sheet.
	v_edge = 1.0 - abs(vn.z);
}

void fragment() {
	vec2 uv = vec2(UV.x * 6.0, UV.y * 2.2 - TIME * speed);
	float streak = texture(noise_tex, vec2(uv.x * 0.16, uv.y * 0.05)).r;
	streak = smoothstep(0.55, 0.9, streak);
	float fade = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float a = streak * fade * (0.35 + 0.65 * v_edge) * strength * 0.24;
	ALBEDO = vec3(1.0, 1.0, 0.97) * a;
}
