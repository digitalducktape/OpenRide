class_name KeepyIntroVisual
extends HBoxContainer
## The intro card's picture: a small scene of the game (the fan in its crate over a meadow, the
## coral balloon riding its column of air, the pole's three bands beside it), then the bands with
## their stars and two lines on what pushes it down. Built with MeshBatch2D once (no per-frame cost).

const PICTURE := Vector2(440, 250)
const CORNER := 22.0
const BALLOON := Color("ff5e5b")
const STAR_R := 13.0


func _init(theme: GameTheme, steer: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 36)
	var pic := Control.new()
	pic.custom_minimum_size = PICTURE
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.draw.connect(_draw_picture.bind(pic, theme.ink))
	add_child(pic)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 6)
	add_child(words)
	var bands := HBoxContainer.new()
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.add_theme_constant_override("separation", 26)
	words.add_child(bands)
	for i in 3:
		bands.add_child(_band(theme, i))
	var line := "Rain, birds and downdrafts push it down" if not steer else "Wind drifts it: lean the fan back under"
	words.add_child(theme.label(line, HudTheme.SMALL, GameTheme.MUTED, true))
	words.add_child(theme.label("Touch the ground and it pops: −%d" % roundi(KeepyLogic.POP_PENALTY),
		HudTheme.SMALL, GameTheme.MUTED, true))


## A band's name and its stars, in the pole's colour.
func _band(theme: GameTheme, i: int) -> Control:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	var col: Color = KeepyStatus.BAND_COLORS[i]
	box.add_child(theme.label(KeepyStatus.BAND_NAMES[i], HudTheme.SMALL + 4, col, true))
	var count := KeepyLogic.multiplier(i as KeepyLogic.Band)
	var stars := Control.new()
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.custom_minimum_size = Vector2(KeepyStatus.stars_width(count, STAR_R), STAR_R * 2.0)
	stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stars.draw.connect(func() -> void:
		KeepyStatus.draw_stars(stars, count, Vector2(STAR_R, STAR_R), STAR_R, col))
	box.add_child(stars)
	return box


func _draw_picture(c: Control, ink: Color) -> void:
	var w := PICTURE.x
	var h := PICTURE.y
	var m := MeshBatch2D.new()
	# The sky, the sun, a far ridge and the meadow, inside the rounded frame.
	m.round_rect(Rect2(Vector2.ZERO, PICTURE), CORNER, Color("7fc4e8"), Color("e3f2ee"))
	m.glow(Vector2(96, 62), Vector2(84, 84), Color(1.0, 0.95, 0.72, 0.75), 10)
	m.circle(Vector2(96, 62), 24.0, Color("fff4cf"))
	_hills(m, h * 0.60, 14.0, 0.021, Color("a6c98f"))
	m.round_rect(Rect2(0, h - 2.0 * CORNER, w, 2.0 * CORNER), CORNER, Color("6f9d4e"))
	_hills(m, h * 0.72, 8.0, 0.034, Color("7fae59"))
	# The pole's bands at the right, bottom to top.
	var pole := Rect2(w - 46.0, 26.0, 16.0, h - 62.0)
	var band_h := pole.size.y / 3.0
	m.rect(pole.grow(3.0), ink)
	for i in 3:
		m.rect(Rect2(pole.position.x, pole.end.y - band_h * (i + 1), pole.size.x, band_h), KeepyStatus.BAND_COLORS[i])
	# The column of air, the crate and its grille.
	var fan := Vector2(190, h - 54.0)
	m.quad4(fan + Vector2(-48, 0), fan + Vector2(48, 0), fan + Vector2(66, -160), fan + Vector2(-66, -160),
		Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0))
	m.round_rect(Rect2(fan.x - 76, fan.y + 34, 152, 12), 6.0, Color(0.1, 0.16, 0.1, 0.32))
	m.round_rect(Rect2(fan.x - 72, fan.y, 144, 40), 6.0, Color("d6b285"), Color("b48d5e"))
	m.round_rect(Rect2(fan.x - 58, fan.y - 8, 116, 12), 5.0, ink)
	# The balloon in the mid band with its knot (no string: ART_BIBLE §3's silhouette rule).
	var at := Vector2(190, pole.end.y - band_h * 1.5)
	m.circle(at, 37.0, ink)
	m.circle(at, 34.0, BALLOON)
	m.glow(at + Vector2(-11, -13), Vector2(14, 14), Color("ffd6c9"), 6)
	m.fill(PackedVector2Array([at + Vector2(-6, 33), at + Vector2(6, 33), at + Vector2(9, 44), at + Vector2(-9, 44)]), BALLOON.darkened(0.3))
	m.flush(c)


## A rolling crest across the picture, down to the meadow's flat part.
func _hills(m: MeshBatch2D, y: float, swell: float, wave: float, col: Color) -> void:
	var bottom := PICTURE.y - CORNER
	var x := 0.0
	while x < PICTURE.x:
		var x2 := minf(x + 20.0, PICTURE.x)
		m.quad(Vector2(x, y + sin(x * wave) * swell), Vector2(x2, y + sin(x2 * wave) * swell),
			Vector2(x2, bottom), Vector2(x, bottom), col)
		x = x2
