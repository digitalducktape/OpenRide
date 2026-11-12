class_name IconButton
extends Button
## A 120 px secondary pill with a drawn icon (the display face has no ▲ ▼ ✕ glyphs), like
## GearButton: "up", "down" or "remove", or the music card's "previous", "play", "pause" and
## "next", and "music" (a note) for the hub header's music button. One triangle array; it draws only when its state
## changes. A disabled one fades its icon (the shape and the fade, never colour alone).

const TOOLTIPS := {"up": "Move up", "down": "Move down", "remove": "Remove", "previous": "Previous",
	"play": "Play", "pause": "Pause", "next": "Next", "music": "Music", "left": "More games",
	"right": "More games"}

var icon_name := ""


func _init(which: String, action: Callable) -> void:
	icon_name = which
	name = which.capitalize()
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(HubTheme.TARGET, HubTheme.TARGET)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tooltip_text = TOOLTIPS.get(which, which)
	HubTheme.look().style_button(self, GameTheme.SECONDARY)
	pressed.connect(action)


func _draw() -> void:
	var c := size / 2.0 + Vector2(0, -2)
	var ink := Color(1, 1, 1, 0.35 if disabled else 1.0)
	var b := ShapeBatch.new()
	match icon_name:
		"up":
			b.convex(PackedVector2Array([c + Vector2(0, -26), c + Vector2(30, 20), c + Vector2(-30, 20)]), ink)
		"down":
			b.convex(PackedVector2Array([c + Vector2(0, 26), c + Vector2(-30, -20), c + Vector2(30, -20)]), ink)
		"remove":
			b.line(c + Vector2(-24, -24), c + Vector2(24, 24), 13.0, ink).line(c + Vector2(-24, 24), c + Vector2(24, -24), 13.0, ink)
		"play":
			b.convex(PackedVector2Array([c + Vector2(-20, -30), c + Vector2(30, 0), c + Vector2(-20, 30)]), ink)
		"pause":
			b.quad(c + Vector2(-24, -28), c + Vector2(-8, -28), c + Vector2(-8, 28), c + Vector2(-24, 28), ink)
			b.quad(c + Vector2(8, -28), c + Vector2(24, -28), c + Vector2(24, 28), c + Vector2(8, 28), ink)
		"next":
			b.convex(PackedVector2Array([c + Vector2(-26, -26), c + Vector2(14, 0), c + Vector2(-26, 26)]), ink)
			b.quad(c + Vector2(16, -26), c + Vector2(26, -26), c + Vector2(26, 26), c + Vector2(16, 26), ink)
		"left":
			b.convex(PackedVector2Array([c + Vector2(-26, 0), c + Vector2(20, -30), c + Vector2(20, 30)]), ink)
		"right":
			b.convex(PackedVector2Array([c + Vector2(26, 0), c + Vector2(-20, 30), c + Vector2(-20, -30)]), ink)
		"music":
			b.note(c, 1.0, ink)
		"previous":
			b.convex(PackedVector2Array([c + Vector2(26, -26), c + Vector2(-14, 0), c + Vector2(26, 26)]), ink)
			b.quad(c + Vector2(-26, -26), c + Vector2(-16, -26), c + Vector2(-16, 26), c + Vector2(-26, 26), ink)
	b.draw(self)


## Swaps the drawn icon (play / pause).
func set_icon(which: String) -> void:
	if which != icon_name:
		icon_name = which
		tooltip_text = TOOLTIPS.get(which, which)
		queue_redraw()


func set_enabled(on: bool) -> void:
	if disabled == on:
		disabled = not on
		queue_redraw()
