// Soft round shadows under the balls (one MultiMesh of flat quads): cheaper than real-time
// shadows, and they show how far away a ball is. INSTANCE_CUSTOM.r: darkness, 0-1.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

varying float dark;

void vertex() {
	dark = INSTANCE_CUSTOM.r;
}

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	ALBEDO = vec3(0.0);
	ALPHA = smoothstep(1.0, 0.2, d) * 0.55 * dark;
}
