// Watt Lane's lane (ART_BIBLE.md): an illuminated horizontal band that comes in from the right
// (the future) and steps up or down, read against the cursor at RIDER_X. Its light is layered:
//   - a deep soft glow around the band, a translucent body with a vertical sheen, and crisp
//     bright edges that pulse on the music's beat (`beat`);
//   - streaks of light running left inside it, the lane's motion;
//   - while the rider is in it (`in_lane`), a beam from the cursor along the band;
//   - an announced step: a glowing riser where the band jumps and amber chevrons leading to it;
//   - behind the cursor, the band dims (played), and the path the cursor rode is a dashed line.
// From arrays WattLaneTrack fills each frame (64 columns across the window, stage px).
// Premultiplied alpha: light adds, solid strokes cover.
shader_type canvas_item;
render_mode blend_premul_alpha;

const int COLS = 64;

uniform float band_lo[64];  // the band's lower edge (larger y) per column, stage px
uniform float band_hi[64];  // its upper edge
uniform float trail[64];  // the path's y per column, < 0 where there is none
uniform float col_x0 = -68.0;
uniform float col_dx = 33.0;
uniform vec2 origin = vec2(-68.0, 300.0);
uniform vec2 rect_size = vec2(2056.0, 700.0);
uniform float rider_x = 520.0;
uniform float rider_y = 620.0;
uniform float scroll = 0.0;
uniform float glow = 1.0;  // 1 in the lane, lower out, up to 2 in a catch's flash
uniform float in_lane = 1.0;  // 0-1, eased
uniform float beat = 0.0;  // 0-1, flares on the beat
uniform float step_x = -1.0;  // stage x of the announced step (< 0: none)
uniform float step_dir = 1.0;  // -1: up the screen (more watts), +1 down
uniform float chevrons = 0.0;
uniform vec3 band_color : source_color = vec3(1.0, 0.78, 0.32);
uniform vec3 edge_color : source_color = vec3(1.0, 0.93, 0.75);
uniform vec3 path_color : source_color = vec3(0.75, 0.9, 1.0);
uniform vec3 warn_color : source_color = vec3(1.0, 0.69, 0.13);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

float vnoise(vec2 p) {
	return texture(noise_tex, p / 64.0).r;
}

float column(float x) {
	return clamp((x - col_x0) / col_dx, 0.0, float(COLS) - 1.001);
}

vec2 band_at(float x) {
	float c = column(x);
	int i = int(c);
	float t = c - float(i);
	return vec2(mix(band_hi[i], band_hi[i + 1], t), mix(band_lo[i], band_lo[i + 1], t));
}

float trail_dist(float x, float y) {
	float c = column(x);
	int i = int(c);
	float a = trail[i];
	float b = trail[i + 1];
	if (a < 0.0 || b < 0.0) {
		return 1e4;
	}
	float ty = mix(a, b, c - float(i));
	float slope = (b - a) / col_dx;
	return abs(y - ty) / sqrt(1.0 + slope * slope);
}

void fragment() {
	vec2 p = origin + UV * rect_size;
	vec2 b = band_at(p.x);
	float hi = b.x;
	float lo = b.y;
	float mid = (hi + lo) * 0.5;
	float half_h = max((lo - hi) * 0.5, 1.0);
	float past = 1.0 - smoothstep(rider_x - 30.0, rider_x + 30.0, p.x);
	float fade = smoothstep(origin.x, origin.x + 140.0, p.x) * (1.0 - smoothstep(origin.x + rect_size.x - 260.0, origin.x + rect_size.x, p.x));
	float strength = mix(1.0, 0.4, past) * glow * fade;
	vec3 pm = vec3(0.0);
	float a = 0.0;
	// Depth: a wide soft glow around the band.
	float dist = max(abs(p.y - mid) - half_h, 0.0);
	pm += band_color * exp(-dist * 0.035) * 0.16 * strength;
	// The body: translucent, brighter at its middle (a sheen), with streaks of light running left.
	float inside = smoothstep(hi - 1.0, hi + 1.0, p.y) * (1.0 - smoothstep(lo - 1.0, lo + 1.0, p.y));
	float sheen = 1.0 - pow(abs(p.y - mid) / half_h, 2.0);
	float streak = smoothstep(0.82, 0.97, vnoise(vec2((p.x + scroll * 1.8) / 16.0, p.y / 2.5)));
	// Light, not paint: the body adds glow (brighter toward its edges, like a lit tube) and only
	// barely covers the field, so it never turns muddy over the teal.
	float tube = 0.06 + 0.16 * pow(1.0 - sheen, 2.0) + 0.05 * sheen;
	pm += band_color * inside * (tube + streak * 0.25) * strength;
	a += inside * 0.03 * fade;
	// Crisp edges that pulse on the beat.
	float edge = min(abs(p.y - hi), abs(p.y - lo));
	float pulse = 1.0 + beat * 0.6;
	float core = (1.0 - smoothstep(1.2, 2.6, edge)) * min(strength, 1.0);
	pm = mix(pm, edge_color * pulse, core);
	a = mix(a, 1.0, core);
	pm += edge_color * exp(-edge * 0.22) * 0.35 * strength * pulse;
	// The beam: from the cursor along the band while the rider is in it.
	if (p.x > rider_x) {
		float beam = exp(-abs(p.y - rider_y) * 0.12) * exp(-(p.x - rider_x) / 520.0) * in_lane * inside;
		pm += edge_color * beam * 0.55 * fade;
	}
	// The announced step: a riser of light where the band jumps, and chevrons leading into it.
	if (step_x > 0.0) {
		float riser = exp(-abs(p.x - step_x) * 0.08) * inside;
		pm += warn_color * riser * 0.8 * chevrons;
		if (p.x > step_x - 280.0 && p.x < step_x - 18.0) {
			float cx = mod(p.x - step_x, 70.0) - 35.0;
			float v = (p.y - mid) * step_dir * 0.85 + abs(cx) * 0.9;
			float stroke = (1.0 - smoothstep(8.0, 11.0, abs(v))) * (1.0 - smoothstep(28.0, 32.0, abs(cx)));
			stroke *= 1.0 - smoothstep(30.0, 46.0, abs(p.y - mid));
			float f = smoothstep(step_x - 280.0, step_x - 210.0, p.x) * chevrons;
			pm = mix(pm, warn_color * 1.1, stroke * f);
			a = mix(a, 1.0, stroke * f);
		}
	}
	// The path the cursor rode: a thin dashed line behind it, fading as it recedes.
	if (p.x < rider_x - 34.0) {
		float d = trail_dist(p.x, p.y);
		float age = smoothstep(origin.x + 60.0, rider_x, p.x);
		float dash = step(fract((p.x + scroll) / 26.0), 0.55);
		float stroke = (1.0 - smoothstep(1.5, 3.0, d)) * dash * age * 0.85;
		pm = mix(pm, path_color, stroke);
		a = mix(a, 1.0, stroke);
	}
	COLOR = vec4(pm, clamp(a, 0.0, 1.0));
}
