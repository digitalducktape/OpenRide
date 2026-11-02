// Keepy Uppy's grade (ART_BIBLE §4: fresh and airy, soft blue-green shadows) on the 3D games'
// shared hand light (framework/shaders/world_look.gdshaderinc). Every Keepy world shader includes
// this instead of the framework file, so the grade is set once. The vignette (0.18) is painted
// into the view grid's vertex colours (KeepyMeshes.view_image), not worked out per pixel.
#define LOOK_SAT 1.08
#define LOOK_CONTRAST 1.03
#define LOOK_GAIN vec3(1.0, 1.02, 1.02)
#define LOOK_LIFT vec3(0.0, 0.015, 0.03)
#include "res://framework/shaders/world_look.gdshaderinc"

// The wind the world shows (-1 left .. +1 right) and how gusty it is (0-1): grass, leaves,
// streamers and the windsock all lean with it.
uniform float wind_dir = 0.3;
uniform float gusty = 0.0;

// Haze per vertex (as Tug's): the share of `haze_color` at a distance, worked out in vertex()
// and passed in a varying; mix it in with `hazed`.
float haze_amount(float dist) {
	return min(1.0 - exp(-haze_density * dist), haze_max);
}

vec3 hazed(vec3 col, float amount) {
	return mix(col, haze_color, amount);
}

// A sway offset for a vertex at world position `wp` with weight `w` (0-1).
vec3 sway_offset(vec3 wp, float w, float amount, float t) {
	float ph = dot(wp, vec3(0.31, 0.0, 0.23));
	float speed = 1.6 + gusty * 3.0;
	float a = amount * (1.0 + gusty * 2.5);
	vec3 o;
	o.x = (sin(t * speed + ph) * 0.6 + wind_dir * 0.8) * a * w;
	o.z = sin(t * speed * 1.37 + ph * 1.7) * a * w * 0.6;
	o.y = 0.0;
	return o;
}
