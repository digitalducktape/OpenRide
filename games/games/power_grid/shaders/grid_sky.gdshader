shader_type canvas_item;
render_mode blend_disabled;

// The whole painted valley on one opaque sprite (#81; ART_BIBLE.md §7): TEXTURE is the dusk bake,
// `night_tex` the night bake, and `night` the evening's progress. The two are painted, not graded,
// so the night has its own colours, and it costs one screen of fill and no blending.
// `flash` is lightning: a cold lift of the sky, for a moment.

uniform sampler2D night_tex : filter_linear;
uniform float night = 0.0;
uniform float flash = 0.0;
uniform float gloom = 0.0;  // the storm's overcast

void fragment() {
	vec3 dusk = texture(TEXTURE, UV).rgb;
	vec3 dark = texture(night_tex, UV).rgb;
	vec3 c = mix(dusk, dark, night);
	c *= 1.0 - gloom * 0.2;
	c += vec3(0.62, 0.68, 0.9) * flash * (1.15 - UV.y);
	COLOR = vec4(c, 1.0);
}
