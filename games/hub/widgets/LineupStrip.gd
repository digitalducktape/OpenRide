class_name LineupStrip
extends Control
## A circuit's lineup as role-coloured pills, each as wide as its slot is long (its intro card
## included), like the HUD's CircuitStrip. With `names`, a pill wide enough shows its game's
## short name. Drawn once (it lives in a bake, or redraws only on a new lineup).

const GAP := 4.0
const INTRO_SEC := 10
const SHORT := {"kart_race": "Kart", "dodge_ball": "Dodge", "tug_of_war": "Tug", "safe_cracker": "Safe",
	"cadence_karaoke": "Cadence", "watt_lane": "Watts", "the_pull": "Pull", "balloon_pump": "Pump"}

var slots: Array = []
var names := false


func _init(lineup: Array, strip_size: Vector2, show_names := false) -> void:
	slots = lineup
	names = show_names
	custom_minimum_size = strip_size
	size = strip_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Each pill's rect, left to right.
func pill_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var total := 0.0
	for s in slots:
		total += float(s.get("duration_sec", 0)) + INTRO_SEC
	if total <= 0.0:
		return out
	var free := size.x - GAP * maxf(0, slots.size() - 1)
	var x := 0.0
	for s in slots:
		var w := free * (float(s.get("duration_sec", 0)) + INTRO_SEC) / total
		out.append(Rect2(x, 0, maxf(w, 2.0), size.y))
		x += w + GAP
	return out


func _draw() -> void:
	var rects := pill_rects()
	var font := GameTheme.display_font()
	var fs := HudTheme.SMALL
	for i in rects.size():
		var role := str(slots[i].get("role", "free"))
		var style := StyleBoxFlat.new()
		style.bg_color = HudTheme.role_color(role)
		style.set_corner_radius_all(int(minf(10.0, rects[i].size.x / 2.0)))
		style.anti_aliasing = true
		draw_style_box(style, rects[i])
		if names:
			var text: String = SHORT.get(str(slots[i].get("game_id", "")), "")
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if w + 16 <= rects[i].size.x:
				var base := rects[i].position.y + (rects[i].size.y + font.get_ascent(fs) - font.get_descent(fs)) / 2.0
				draw_string(font, Vector2(rects[i].get_center().x - w / 2.0, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					HubTheme.look().ink)
