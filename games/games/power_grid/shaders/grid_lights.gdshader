shader_type canvas_item;
render_mode blend_add;

// Power Grid's town lights (#81; GridLights.gd): one mesh, every light's channel and turn in UV.x
// (channel + threshold) and its seed in UV.y. A light is on once its channel's level passes its
// threshold, so a district comes on window by window as one uniform rises, and a brown-out drops
// them the same way. All per vertex: the fragment does nothing but pass the colour through.
// Nothing flashes faster than about twice a second.

uniform vec4 levels = vec4(1.0);
uniform vec4 flicker = vec4(0.0);  // per channel, 0-1: a dimming district's unsteady supply
uniform float night = 1.0;  // the lights read stronger as the sky darkens
uniform float chase = 0.0;  // the funfair's bulbs step round on this (a phase, in steps)

float pick(vec4 v, float channel) {
	return channel < 0.5 ? v.x : (channel < 1.5 ? v.y : (channel < 2.5 ? v.z : v.w));
}

void vertex() {
	float channel = floor(UV.x);
	float threshold = fract(UV.x);
	float seed = UV.y;
	float on = smoothstep(threshold * 0.9, threshold * 0.9 + 0.1, pick(levels, channel));
	float unsteady = pick(flicker, channel);
	float wobble = sin(TIME * 7.0 + seed * 31.0 + threshold * 57.0) * 0.5 + 0.5;
	on *= 1.0 - unsteady * 0.65 * wobble;
	float steady = 1.0 - 0.14 * (0.5 + 0.5 * sin(TIME * (0.4 + fract(seed) * 1.1) + fract(seed) * 40.0));
	if (seed >= 2.0) {
		// A chasing bulb: four phases, each lit in turn, never fully off.
		float step_at = fract((seed - 2.0) + chase * 0.25);
		steady = step_at < 0.25 ? 1.0 : 0.55;
	}
	float strength = mix(0.72, 1.0, night);
	COLOR.a *= on * steady * strength;
}

void fragment() {
	COLOR = vec4(COLOR.rgb * COLOR.a, COLOR.a);
}
