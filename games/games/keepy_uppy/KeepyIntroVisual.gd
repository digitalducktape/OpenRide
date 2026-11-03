class_name KeepyIntroVisual
extends HBoxContainer
## The intro card's picture: the height pole's three bands with their multipliers, the coral
## balloon floating in the mid band over the fan, and one line on what pushes it down. Drawn with
## shapes once (no per-frame cost), like Tug of War's bot portrait.

const PICTURE := Vector2(150, 150)
const BAND_COLORS := [Color("f2efe6"), Color("8fd0f0"), Color("f5c04a")]
const BALLOON := Color("ff5e5b")


func _init(theme: GameTheme, steer: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 28)
	var pic := Control.new()
	pic.custom_minimum_size = PICTURE
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.draw.connect(_draw_picture.bind(pic, theme.ink))
	add_child(pic)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	add_child(words)
	var bands := HBoxContainer.new()
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.add_theme_constant_override("separation", 18)
	words.add_child(bands)
	for i in 3:
		var text := "%s %d×" % [KeepyStatus.BAND_NAMES[i], KeepyLogic.multiplier(i as KeepyLogic.Band)]
		bands.add_child(theme.label(text, HudTheme.SMALL + 4, BAND_COLORS[i], true))
	var line := "Rain, birds and downdrafts push it down" if not steer else "Wind drifts it: lean the fan back under"
	words.add_child(theme.label(line, HudTheme.SMALL, GameTheme.MUTED, true))
	words.add_child(theme.label("Touch the ground and it pops: −%d" % roundi(KeepyLogic.POP_PENALTY),
		HudTheme.SMALL, GameTheme.MUTED, true))


func _draw_picture(c: Control, ink: Color) -> void:
	var w := PICTURE.x
	var h := PICTURE.y
	# The pole's bands on the right, bottom to top.
	var pole := Rect2(w - 26.0, 10.0, 14.0, h - 30.0)
	var band_h := pole.size.y / 3.0
	for i in 3:
		c.draw_rect(Rect2(pole.position.x, pole.end.y - band_h * (i + 1), pole.size.x, band_h), BAND_COLORS[i])
	# The fan's crate and grille at the foot.
	c.draw_rect(Rect2(20.0, h - 34.0, 70.0, 24.0), Color("c9a577"))
	c.draw_rect(Rect2(28.0, h - 38.0, 54.0, 6.0), ink)
	# The column of air, then the balloon in the mid band with its knot (no string: ART_BIBLE §3's
	# silhouette rule).
	for k in 3:
		var x := 38.0 + k * 17.0
		c.draw_line(Vector2(x, h - 44.0), Vector2(x + (k - 1) * 4.0, 40.0), Color(1, 1, 1, 0.35), 3.0, true)
	var centre := Vector2(55.0, h * 0.45)
	c.draw_circle(centre, 30.0, ink)
	c.draw_circle(centre, 27.0, BALLOON)
	c.draw_circle(centre + Vector2(-9.0, -10.0), 7.0, Color("ffd6c9"))
	c.draw_colored_polygon(PackedVector2Array([centre + Vector2(-5, 26), centre + Vector2(5, 26),
		centre + Vector2(7, 34), centre + Vector2(-7, 34)]), BALLOON.darkened(0.3))
