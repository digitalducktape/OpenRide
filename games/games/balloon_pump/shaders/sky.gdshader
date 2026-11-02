// Balloon Pump's noon sky (ART_BIBLE §4): a clear gradient, a soft sun halo and hazy clouds,
// graded like the world (pump_look.gdshaderinc, no vignette). No TIME, so the sky's radiance
// cubemap (256 a face, PumpWorld) is drawn once and the background only samples it (Tug's tablet
// recipe: the full sky every pixel every frame cost a third of the screen).
shader_type sky;

#include "res://games/balloon_pump/shaders/pump_look.gdshaderinc"

uniform vec3 top_color : source_color = vec3(0.37, 0.72, 0.94);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.92, 0.98);
uniform vec3 below_color : source_color = vec3(0.45, 0.62, 0.35);

void sky() {
	if (!AT_CUBEMAP_PASS) {
		COLOR = texture(RADIANCE, EYEDIR).rgb;
	} else {
		vec3 dir = EYEDIR;
		float h = dir.y;
		vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.5));
		col = mix(col, below_color, smoothstep(0.0, -0.06, h));
		float s = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		col += vec3(1.0, 0.97, 0.88) * (pow(s, 12.0) * 0.35 + pow(s, 400.0) * 1.5);
		if (h > 0.0) {
			vec2 uv = dir.xz / (h + 0.2);
			float n = vnoise(uv * 1.1) * 0.6 + vnoise(uv * 2.9) * 0.3 + vnoise(uv * 6.5) * 0.1;
			float c = smoothstep(0.55, 0.82, n) * smoothstep(0.02, 0.2, h);
			col = mix(col, vec3(1.0), c * 0.75);
		}
		COLOR = grade(col, vec2(0.5));
	}
}
