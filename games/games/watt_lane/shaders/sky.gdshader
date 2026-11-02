// Watt Lane's sky and horizon (ART_BIBLE.md §6): one far backdrop card. A petrol-to-teal night
// gradient, stars, a thin crescent moon high left, flat mesas, and a low city skyline straight
// ahead whose windows twinkle and whose haze glows teal. Everything drawn here; opaque.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

#include "res://games/watt_lane/shaders/wl_look.gdshaderinc"

uniform vec3 top_color : source_color = vec3(0.012, 0.035, 0.05);
uniform vec3 horizon_color : source_color = vec3(0.07, 0.29, 0.3);
uniform vec3 city_color : source_color = vec3(0.02, 0.05, 0.06);
uniform vec3 window_color : source_color = vec3(1.0, 0.78, 0.45);
uniform vec3 mesa_color : source_color = vec3(0.015, 0.04, 0.05);
uniform float horizon_v = 0.86;  // UV.y of the horizon on the card
uniform float time = 0.0;

void fragment() {
	vec2 uv = UV;
	float above = horizon_v - uv.y;  // > 0 above the horizon
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, above));
	col += horizon_color * 0.35 * exp(-max(above, 0.0) * 22.0);
	// Stars: sparse bright texels of the noise, twinkling.
	vec2 sp = uv * vec2(900.0, 300.0);
	float n = vnoise(sp);
	float star = smoothstep(0.93, 0.99, n) * smoothstep(0.08, 0.3, above);
	star *= 0.6 + 0.4 * sin(time * 1.7 + n * 60.0);
	col += vec3(0.85, 0.95, 1.0) * star * 0.9;
	// A thin crescent moon, low left of the city (clear of the HUD).
	vec2 mp = (uv - vec2(0.4, 0.76)) * vec2(3.0, 1.0);
	float moon = smoothstep(0.022, 0.018, length(mp)) * smoothstep(0.016, 0.02, length(mp - vec2(0.008, -0.004)));
	col = mix(col, vec3(0.92, 0.96, 0.9), moon);
	col += vec3(0.4, 0.6, 0.6) * exp(-length(mp) * 40.0) * 0.25;
	// Mesas: flat-topped silhouettes on the horizon.
	float mh = vnoise(vec2(uv.x * 26.0, 3.0)) * 0.7 + vnoise(vec2(uv.x * 90.0, 7.0)) * 0.3;
	float mesa_top = horizon_v - 0.006 - 0.028 * smoothstep(0.45, 0.62, mh);
	float fwm = fwidth(uv.y);
	float mesa = smoothstep(mesa_top - fwm, mesa_top + fwm, uv.y);
	col = mix(col, mesa_color, mesa * smoothstep(0.1, 0.16, abs(uv.x - 0.5)));
	// The city: blocks of different heights in the middle, windows lit on a grid.
	float cx = (uv.x - 0.5) / 0.12;
	if (abs(cx) < 1.0) {
		float block = floor(uv.x * 220.0);
		float bh = (0.01 + 0.05 * vnoise(vec2(block * 7.3, 1.0)) * (1.0 - cx * cx));
		float in_city = step(horizon_v - bh, uv.y) * step(uv.y, horizon_v + 0.01);
		vec2 wg = vec2(uv.x * 1400.0, uv.y * 900.0);
		float lit = step(0.62, vnoise(floor(wg) * 1.3)) * step(0.3, fract(wg.x)) * step(0.35, fract(wg.y));
		lit *= 0.7 + 0.3 * sin(time * 0.6 + floor(wg.x) * 3.1);
		col = mix(col, city_color + window_color * lit * 0.8, in_city);
		col += horizon_color * 0.5 * exp(-abs(above + 0.02) * 30.0) * (1.0 - cx * cx);
	}
	ALBEDO = grade(col, SCREEN_UV);
}
