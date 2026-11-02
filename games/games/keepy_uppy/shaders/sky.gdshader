// Keepy Uppy's sky: a clear summer afternoon (ART_BIBLE §4), a horizon gradient, a warm sun with a
// soft halo, and thin high cloud streaks, with Keepy's grade (no vignette). No TIME, so the sky's
// radiance cubemap is only drawn once (and again if a uniform changes) and the background samples
// it: one read a pixel, as Tug of War's.
shader_type sky;

#include "res://games/keepy_uppy/shaders/keepy_look.gdshaderinc"

uniform vec3 top_color : source_color = vec3(0.31, 0.64, 0.91);
uniform vec3 horizon_color : source_color = vec3(0.81, 0.91, 0.97);
uniform vec3 below_color : source_color = vec3(0.6, 0.75, 0.55);
uniform vec3 disc_color : source_color = vec3(1.0, 0.96, 0.86);
uniform float sun_size = 0.03;
uniform float halo = 0.5;
uniform float clouds = 0.45;

void sky() {
	if (!AT_CUBEMAP_PASS) {
		COLOR = texture(RADIANCE, EYEDIR).rgb;
	} else {
		vec3 dir = EYEDIR;
		float h = dir.y;
		vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.5));
		col = mix(col, below_color, smoothstep(0.0, -0.06, h));
		float s = dot(dir, LIGHT0_DIRECTION);
		col += disc_color * halo * pow(max(s, 0.0), 10.0) * 0.5;
		col += disc_color * 0.2 * halo * pow(max(s, 0.0), 2.0) * smoothstep(0.4, 0.0, h);
		col = mix(col, disc_color * 1.5, smoothstep(1.0 - sun_size * 0.6, 1.0 - sun_size * 0.5, s));
		if (h > 0.0 && clouds > 0.0) {
			// Thin, wind-stretched streaks high up (the big cumulus are meshes).
			vec2 uv = dir.xz / (h + 0.2);
			float n = vnoise(vec2(uv.x * 0.6, uv.y * 2.6)) * 0.65 + vnoise(uv * 5.0) * 0.35;
			float c = smoothstep(0.55, 0.85, n) * smoothstep(0.05, 0.3, h) * clouds;
			col = mix(col, vec3(1.0), c * 0.6);
		}
		COLOR = grade(col, vec2(0.5));
	}
}
