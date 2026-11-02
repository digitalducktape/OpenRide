// The Pull's grade (ART_BIBLE §4: warm floodlit clay under a deep blue dusk) on the 3D games'
// shared hand light (framework/shaders/world_look.gdshaderinc), plus the floodlight pools every
// Pull world shader shares. The vignette is painted into the view grid (PullMeshes.view_image).
#define LOOK_SAT 1.12
#define LOOK_CONTRAST 1.06
#define LOOK_GAIN vec3(1.05, 1.0, 0.95)
#define LOOK_LIFT vec3(0.0, 0.01, 0.04)
#include "res://framework/shaders/world_look.gdshaderinc"

// Floodlight towers stand every `flood_spacing` metres along -z on both sides at x = ±flood_x.
uniform vec3 flood_color : source_color = vec3(1.0, 0.85, 0.63);
uniform float flood_strength = 1.0;  // the Full Pull flare lifts it for a moment
uniform float flood_spacing = 40.0;
uniform float flood_x = 8.5;
uniform float flood_reach = 8.0;  // the pool's radius (one sigma), metres

// The floodlights' pool at a world position (x, z): the nearest tower pair and the next, both
// sides, as a gaussian falloff. A mod, no loop.
float pool_at(vec2 xz) {
	float dz = mod(xz.y + flood_spacing * 0.5, flood_spacing) - flood_spacing * 0.5;
	float dz2 = flood_spacing - abs(dz);
	float l = xz.x + flood_x;
	float r = xz.x - flood_x;
	float k = -0.5 / (flood_reach * flood_reach);
	float near = exp((l * l + dz * dz) * k) + exp((r * r + dz * dz) * k);
	float far = exp((l * l + dz2 * dz2) * k) + exp((r * r + dz2 * dz2) * k);
	return min(near + far, 1.4) * flood_strength;
}

// Haze per vertex (as Tug's): the share of haze at a distance.
float haze_amount(float dist) {
	return min(1.0 - exp(-haze_density * dist), haze_max);
}

vec3 hazed(vec3 col, float amount) {
	return mix(col, haze_color, amount);
}
