shader_type canvas_item;

// Ready for Launch's Earth (#82; ART_BIBLE §7): a real sphere on one square rect. Each pixel inside
// the disc finds its latitude and longitude and reads `earth_map.png` (tools/art/make_earth_map.py:
// day colours in RGB, clouds in alpha), so the continents are the ones you know. On top: the sun's
// light with a soft day and night terminator warming at its edge, city lights on the night side,
// the sun's glint on the sea, clouds that drift and shade the ground, and the atmosphere as a thin
// blue rim that glows out past the limb. `lod` picks the map's mip by hand: automatic mips would
// streak along the seam where longitude wraps.

uniform sampler2D map : filter_linear_mipmap, repeat_enable;
uniform float disc = 0.893;  // the planet's radius as a share of the rect's half width
uniform float view_lat = 0.0;  // radians: the latitude at the middle of the disc
uniform float view_lon = 0.0;  // radians
uniform float lod = 0.0;
uniform float cloud_shift = 0.0;  // the clouds' own drift, in map widths
uniform vec3 sun = vec3(0.55, 0.5, 0.67);  // toward the sun, in view space (x right, y up, z out)

const float TAU_ = 6.2831853;
const float PI_ = 3.1415927;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 / disc;
	float r = length(p);
	vec3 glow_col = vec3(0.32, 0.62, 1.0);
	if (r >= 1.0) {
		// The air past the limb, brightest toward the sun, gone by the rect's edge.
		float out_t = (r - 1.0) / (1.0 / disc - 1.0);
		float lit = clamp(dot(normalize(vec3(p.x, -p.y, 0.0)), sun) * 0.7 + 0.5, 0.0, 1.0);
		float a = pow(max(1.0 - out_t, 0.0), 3.2) * mix(0.1, 0.8, lit);
		COLOR = vec4(glow_col, a);
	} else {
		float z = sqrt(max(1.0 - r * r, 0.0));
		vec3 n = vec3(p.x, -p.y, z);
		// Tip the sphere by the viewing latitude, then read its latitude and longitude.
		float c = cos(view_lat);
		float s = sin(view_lat);
		vec3 g = vec3(n.x, n.y * c + n.z * s, -n.y * s + n.z * c);
		float lat = asin(clamp(g.y, -1.0, 1.0));
		float lon = atan(g.x, g.z) + view_lon;
		vec2 uv = vec2(lon / TAU_ + 0.5, 0.5 - lat / PI_);
		vec3 ground = textureLod(map, uv, lod).rgb;
		float cloud = textureLod(map, uv + vec2(cloud_shift, 0.0), lod).a;
		float shadow = textureLod(map, uv + vec2(cloud_shift - 0.0016, 0.0012), lod + 1.0).a;

		float d = dot(n, sun);
		float day = smoothstep(-0.1, 0.24, d);
		float light = 0.1 + 0.98 * clamp(d * 1.2 + 0.14, 0.0, 1.0);
		vec3 col = ground * (1.0 - shadow * 0.42) * light;
		// The sea is bluer than it is bright, and holds the sun's glint.
		float sea = step(ground.r + 0.04, ground.b) * (1.0 - cloud);
		vec3 half_v = normalize(sun + vec3(0.0, 0.0, 1.0));
		float glint = pow(max(dot(n, half_v), 0.0), 90.0);
		col += vec3(1.0, 0.92, 0.76) * glint * sea * 0.65;
		// City lights: scattered warm points on the land's night side.
		vec2 cell = floor(uv * vec2(420.0, 210.0));
		float city = step(0.965, hash(cell)) * (1.0 - step(ground.r + 0.04, ground.b)) * step(abs(lat), 1.1);
		col += vec3(1.0, 0.78, 0.42) * city * (1.0 - day) * (1.0 - cloud) * 0.8;
		// Clouds, lit like the ground, rosy along the terminator.
		float edge = smoothstep(-0.16, 0.06, d) * (1.0 - smoothstep(0.06, 0.34, d));
		vec3 cloud_col = mix(vec3(0.97, 0.98, 1.0), vec3(1.0, 0.68, 0.46), edge * 0.8) * (0.06 + 0.98 * clamp(d * 1.3 + 0.16, 0.0, 1.0));
		col = mix(col, cloud_col, cloud * 0.94);
		col += vec3(1.0, 0.45, 0.2) * edge * 0.1;
		// The air: a thin blue rim on the lit side, deepening the limb.
		float rim = pow(1.0 - z, 3.0);
		col = mix(col, glow_col * (0.25 + 0.95 * clamp(d + 0.3, 0.0, 1.0)), clamp(rim * 1.05, 0.0, 0.85));
		float aa = 1.0 - smoothstep(0.9985, 1.0, r);
		COLOR = vec4(mix(glow_col * 0.5, col, aa), 1.0);
	}
}
