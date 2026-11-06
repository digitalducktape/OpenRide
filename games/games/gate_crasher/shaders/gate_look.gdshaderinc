// Gate Crasher's grade (ART_BIBLE §4: warm, clean morning light) on the 3D games' shared hand
// light. The vignette is painted into the view grid (PullMeshes.view_image).
#define LOOK_SAT 1.1
#define LOOK_CONTRAST 1.05
#define LOOK_GAIN vec3(1.04, 1.01, 0.97)
#define LOOK_LIFT vec3(0.01, 0.01, 0.015)
#include "res://framework/shaders/world_look.gdshaderinc"

float haze_amount(float dist) {
	return min(1.0 - exp(-haze_density * dist), haze_max);
}

vec3 hazed(vec3 col, float amount) {
	return mix(col, haze_color, amount);
}
