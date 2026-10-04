// The river between the two piers (Tug of War, #40): drifting ripples, a reflection tint at
// grazing angles and sparkles, lit and fogged by hand. The river covers a third of the screen,
// and the engine's per-pixel light and fog cost the tablet's GPU too much (see verge.gdshader).
shader_type spatial;
render_mode unshaded, fog_disabled;

uniform vec3 light_color = vec3(1.0);
uniform vec3 fog_color : source_color = vec3(0.7, 0.8, 0.9);
uniform float fog_density = 0.006;
uniform vec3 deep : source_color = vec3(0.07, 0.25, 0.36);
uniform vec3 shallow : source_color = vec3(0.16, 0.46, 0.55);
uniform vec3 sky_tint : source_color = vec3(0.75, 0.85, 0.95);
uniform float sparkle = 0.35;
// Value noise from a 64x64 random texture (one unit of the coordinate is one texel).
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The river flows across the view (along x).
	vec2 uv = world_pos.xz;
	float a = texture(noise_tex, uv * 0.045 + vec2(TIME * 0.05, TIME * 0.012)).r;
	float b = texture(noise_tex, uv * 0.13 + vec2(TIME * 0.11, -TIME * 0.02)).r;
	float ripple = a * 0.6 + b * 0.4;
	vec3 col = mix(deep, shallow, ripple);
	// Fresnel: the sky shows in the water at a grazing view, the depth looking down.
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(up_view, normalize(VIEW)), 0.0, 1.0), 3.0);
	col = mix(col, sky_tint, fres * 0.65);
	col += vec3(1.0) * smoothstep(0.74, 0.9, b) * sparkle * (0.4 + 0.6 * a);
	float fog = 1.0 - exp(-fog_density * length(VERTEX));
	// A floor under the light, so the river never goes black at night: it still reflects the sky.
	vec3 lit = max(light_color, vec3(0.62)) * 0.9;
	ALBEDO = mix(col * lit, fog_color, fog);
}
