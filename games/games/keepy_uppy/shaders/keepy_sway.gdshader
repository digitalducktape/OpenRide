shader_type canvas_item;

// Keepy Uppy's swaying shapes (#77): the foreground grass and the height pole's streamers. Each
// vertex's UV.x (SafeMesh's `depth`) is its sway weight: 0 at a root or the pole, 1 at a tip. They
// lean with the wind and wave in it, harder while `gust` is up (a gust's warning); `flutter` is a
// streamer's quick ripple along its length. Never a redraw.

uniform float wind = 0.3;  // -1 (to the left) .. +1
uniform float gust = 0.0;  // 0-1
uniform float amount = 6.0;  // px at full weight
uniform float flutter = 0.0;  // px of ripple along a streamer

void vertex() {
	float w = UV.x;
	float ph = VERTEX.x * 0.013 + VERTEX.y * 0.02;
	float speed = 1.5 + gust * 4.0;
	float a = amount * (1.0 + gust * 2.0);
	VERTEX.x += (sin(TIME * speed + ph) * 0.6 + wind) * a * w;
	VERTEX.y += sin(TIME * (7.0 + gust * 8.0) - VERTEX.x * 0.08) * flutter * (1.0 + gust * 1.5) * w;
}
