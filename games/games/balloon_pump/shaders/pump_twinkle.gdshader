shader_type canvas_item;

// Balloon Pump's string-light bulbs and the wheel's lamps (#76; ART_BIBLE.md §7): drawn once into
// a SafeMesh batch, each bulb's vertices carrying its own phase in UV.x (SafeMesh.depth). They
// breathe slowly from TIME, never a redraw. `speed` sets the breathing rate; nothing flashes
// faster than twice a second.

uniform float speed = 1.4;
uniform float depth = 0.35;  // how far a bulb dims at its lowest

void fragment() {
	float phase = UV.x * 37.0;
	float b = 1.0 - depth * (0.5 + 0.5 * sin(TIME * speed * (0.6 + 0.4 * fract(UV.x * 13.0)) + phase));
	b = UV.x > 0.0 ? b : 1.0;  // the wheel's frame (no phase) holds still
	COLOR = vec4(COLOR.rgb * b, COLOR.a * mix(1.0, b, 0.5));
}
