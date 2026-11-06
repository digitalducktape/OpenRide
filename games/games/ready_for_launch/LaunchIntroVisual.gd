class_name LaunchIntroVisual
extends HBoxContainer
## The intro card's picture: a small dawn scene with the real rocket on its pad, then the launch's
## three steps with their seconds and watts, every figure from this segment's `LaunchLogic`. Built
## once with SafeMesh (no per-frame cost).

const PICTURE := Vector2(440, 270)
const CORNER := 22.0
const ROCKET_SCALE := 0.33
const MARK := 1


func _init(theme: GameTheme, logic: LaunchLogic) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 36)
	var pic := Control.new()
	pic.custom_minimum_size = PICTURE
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.draw.connect(_draw_picture.bind(pic))
	add_child(pic)
	var rocket: Node2D = SafeDial.Layer.new()
	rocket.name = "Rocket"
	rocket.position = Vector2(PICTURE.x * 0.56, PICTURE.y - 40.0)
	rocket.scale = Vector2(ROCKET_SCALE, ROCKET_SCALE)
	rocket.paint = _paint_rocket
	pic.add_child(rocket)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 8)
	add_child(words)
	var mid_w: float = roundi(logic.fuel_full)
	words.add_child(_step(theme, "Fuel", "%d s at %d W" % [roundi(logic.fuel_sec), mid_w], Color("ffcf66")))
	words.add_child(_step(theme, "Count", "%d s, keep spinning" % roundi(LaunchLogic.COUNT_SEC), GameTheme.INK))
	words.add_child(_step(theme, "Push", "%d s past %d W" % [roundi(LaunchLogic.PUSH_SEC), roundi(logic.target)], theme.accent))
	var far := roundi(LaunchLogic.FUEL_MAX_MULT / LaunchLogic.FUEL_MIN_MULT)
	words.add_child(theme.label("A full tank flies %d times as far" % far, HudTheme.SMALL + 6, GameTheme.MUTED, true))


func _step(theme: GameTheme, word: String, detail: String, col: Color) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	var head := theme.label(word, 44, col, true)
	head.custom_minimum_size = Vector2(140, 0)
	row.add_child(head)
	row.add_child(theme.label(detail, 40, GameTheme.INK, true))
	return row


func _paint_rocket(ci: CanvasItem) -> void:
	var spec: Dictionary = LaunchRocket.MARKS[MARK]
	var parts: Array = spec.sections
	var offsets: Array[float] = []
	var y := LaunchRocket.BELL_H
	for i in parts.size():
		offsets.append(y)
		y += float(parts[i].h) + LaunchRocket.SKIRT_H
	for i in range(parts.size() - 1, -1, -1):
		var next_w: float = float(parts[i + 1].w) if i + 1 < parts.size() else 0.0
		var m := SafeMesh.new()
		LaunchRocket.paint_section(m, parts[i], next_w, spec.bells, i)
		for k in m.points.size():
			m.points[k] += Vector2(0, -offsets[i])
		m.flush(ci)


func _draw_picture(c: Control) -> void:
	var w := PICTURE.x
	var h := PICTURE.y
	var p := LaunchPlaces.place(0)
	var m := SafeMesh.new()
	m.round_rect(Rect2(Vector2.ZERO, PICTURE), CORNER, p.sky_top, p.sky_low)
	m.glow(Vector2(350, 188), Vector2(170, 90), Color(p.sun_col, 0.8), 10)
	m.circle(Vector2(350, 188), 24.0, Color("fff0c8"))
	m.rect_v(Rect2(0, 188, w, 22), Color("c9a0a6"), Color("6a7ea0"))
	m.round_rect(Rect2(0, h - 2.0 * CORNER - 22.0, w, 2.0 * CORNER + 22.0), CORNER, p.near, p.near2)
	# The tower and the table.
	var x := w * 0.56
	var steel := Color("3f4658")
	m.rect(Rect2(x - 118.0, 42.0, 9.0, h - 80.0), steel)
	m.rect(Rect2(x - 86.0, 42.0, 9.0, h - 80.0), steel)
	for k in 6:
		var y := 50.0 + k * 34.0
		m.line(Vector2(x - 114.0, y), Vector2(x - 82.0, y + 34.0), 3.0, steel)
		m.line(Vector2(x - 118.0, y), Vector2(x - 77.0, y), 4.0, steel)
	m.round_rect(Rect2(x - 128.0, 34.0, 60.0, 14.0), 3.0, Color("c8452f"))
	m.round_rect(Rect2(x - 92.0, h - 40.0, 184.0, 14.0), 3.0, Color("6a7186"), Color("3f4658"))
	m.flush(c)
