// Soft additive glows: the floodlights' halos and the dust motes drifting through their light.
// Camera-facing quads (a MultiMesh for the halos, particles for the motes); the glow is a
// radial falloff in the instance colour, brighter with `strength` (the Full Pull flare).
// Additive, no depth write, so they cost little and never hide anything.
shader_type spatial;
render_mode unshaded, fog_disabled, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength = 1.0;
uniform bool billboard = true;  // the halos turn to the camera; particles do it themselves

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float core = 1.0 - smoothstep(0.0, 0.25, r);
	float halo = pow(max(1.0 - r, 0.0), 2.2);
	ALBEDO = COLOR.rgb * (halo * 0.55 + core * 0.9) * strength * COLOR.a;
}
