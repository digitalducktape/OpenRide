// The rider's light-bike nose at the bottom of the view (ART_BIBLE.md §5): a dark wedge whose
// edges glow headlight-warm (UV.y: 0 on the body, 1 on an edge), brighter on the beat of the
// pedals (`pulse`), amber while out of the lane (`warn`). Opaque, unshaded.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

uniform vec3 body : source_color = vec3(0.05, 0.09, 0.1);
uniform vec3 edge_color : source_color = vec3(1.0, 0.94, 0.8);
uniform vec3 warn_color : source_color = vec3(1.0, 0.69, 0.13);
uniform float warn = 0.0;
uniform float pulse = 0.0;

void fragment() {
	float e = smoothstep(0.7, 1.0, UV.y);
	vec3 ec = mix(edge_color, warn_color, warn);
	ALBEDO = mix(body, ec * (1.1 + 0.4 * pulse), e);
}
