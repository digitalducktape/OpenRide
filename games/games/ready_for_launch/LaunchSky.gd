class_name LaunchSky
extends Node2D
## Everything above the ground (#82; ART_BIBLE.md §7), driven by one number, the climb: the sky's
## colour (`rfl_sky.gdshader` on one rect), cloud decks the rocket punches through, the stars, the
## Earth's limb coming up under it, then the Earth shrinking away and the Moon rising to meet it.
## Each body is one mesh painted once; a frame only moves, scales and fades them. The rect is
## opaque, and hidden while the baked place fills the screen.
##
## `front` holds the near cloud deck, which passes in front of the rocket with a gap down the middle.

const RECT := Rect2(-160, 0, 2240, 1080)
const STAR_COUNT := 150
const EARTH_R := 1500.0
const EARTH_AIR := 170.0  ## the atmosphere's glow past the limb
const EARTH_MAP := "res://games/ready_for_launch/earth_map.png"
const MAP_PX_PER_RAD := 2048.0 / TAU  ## earth_map.png's width round the equator
## The view of the Earth, in degrees. Near it the limb shows the Mediterranean, Europe and North
## Africa along the top of the disc; far away the whole Atlantic side, Africa and the Americas.
const NEAR_VIEW := Vector2(14.0, -36.0)  ## longitude, latitude
const FAR_VIEW := Vector2(-22.0, 12.0)
const MOON_R := 620.0
## Climb marks. The milestones are 5 / 12 / 22 / 34 (LaunchLogic.MILESTONES).
const GROUND_GONE := 3.5  ## the place has scrolled off by this climb
const DECK_IN := 2.4  ## the cloud decks come down the screen between these
const DECK_OUT := 7.2
const SPACE_FROM := 5.0  ## the sky darkens between these
const SPACE_AT := 12.0
const EARTH_RISE := 8.0  ## the limb rises into view between these
const EARTH_UP := 18.0
const MOON_FROM := 21.0  ## and the Moon grows between these
const MOON_AT := 34.0
const MOON_START := Vector2(1370, 430)
const MOON_END := Vector2(960, 1720)
const MOON_END_SCALE := 1.5
## The Moon's top at the end, where the capsule's feet come to rest.
const SURFACE_Y := MOON_END.y - MOON_R * MOON_END_SCALE

var rect: ColorRect
var stars: Node2D
var earth: Node2D
var globe: ColorRect
var moon: Node2D
var deck_far: Node2D
var front: Node2D  ## add after the rocket
var _place := 0
var _low := Color.BLACK
var _top := Color.BLACK
var _star_y := 0.0


func _init() -> void:
	name = "Sky"
	rect = ColorRect.new()
	rect.name = "SkyRect"
	rect.position = RECT.position
	rect.size = RECT.size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://games/ready_for_launch/shaders/rfl_sky.gdshader")
	rect.material = mat
	add_child(rect)
	stars = PaintLayer.new()
	stars.name = "Stars"
	stars.paint = func(ci: CanvasItem) -> void:
		MeshBatch2D.built("rfl:stars", func(m: MeshBatch2D) -> void: paint_stars(m)).draw_on(ci)
	add_child(stars)
	moon = PaintLayer.new()
	moon.name = "Moon"
	moon.paint = func(ci: CanvasItem) -> void:
		MeshBatch2D.built("rfl:moon", func(m: MeshBatch2D) -> void: paint_moon(m)).draw_on(ci)
	add_child(moon)
	earth = Node2D.new()
	earth.name = "Earth"
	add_child(earth)
	globe = ColorRect.new()
	globe.name = "Globe"
	globe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	globe.size = Vector2.ONE * 2.0 * (EARTH_R + EARTH_AIR)
	globe.position = -globe.size * 0.5
	var globe_mat := ShaderMaterial.new()
	globe_mat.shader = preload("res://games/ready_for_launch/shaders/rfl_earth.gdshader")
	# Loaded, not preloaded: a preload is held by this script for the app's life (about 11 MB of
	# texture with its mipmaps); this way the map is freed with the game.
	globe_mat.set_shader_parameter("map", load(EARTH_MAP))
	globe_mat.set_shader_parameter("disc", EARTH_R / (EARTH_R + EARTH_AIR))
	globe.material = globe_mat
	earth.add_child(globe)
	deck_far = PaintLayer.new()
	deck_far.name = "DeckFar"
	deck_far.paint = _paint_deck.bind(0)
	add_child(deck_far)
	front = PaintLayer.new()
	front.name = "DeckNear"
	front.paint = _paint_deck.bind(1)


func set_place(index: int) -> void:
	_place = index
	deck_far.queue_redraw()
	front.queue_redraw()
	var p := LaunchPlaces.place(index)
	_low = p.sky_top
	_top = p.sky_top
	update(0.0, 0.0, 0.0)


## Where the ground has scrolled to at a climb: slow at first, as a big rocket rises.
static func ground_off(climb: float) -> float:
	var t := clampf(climb / GROUND_GONE, 0.0, 1.0)
	return LaunchPlaces.SIZE.y * 1.04 * t * t


## How far into space the sky is: 0 still air, 1 black.
static func space_at(climb: float) -> float:
	return smoothstep(SPACE_FROM, SPACE_AT, climb)


## Sets everything to where it stands at this climb. `speed` is climb units a second; `delta` the
## frame, for the stars' slow drift.
func update(climb: float, speed: float, delta: float) -> void:
	var p := LaunchPlaces.place(_place)
	var flying := climb > 0.0
	rect.visible = flying
	var s := space_at(climb)
	var mid := smoothstep(0.6, SPACE_FROM, climb)
	# Flat at the place's own top colour while the ground is in view, so the bake's top edge
	# doesn't show; then a deep blue high above, then black.
	var top: Color = (p.sky_top as Color).lerp(Color("0d2a66"), mid).lerp(Color("03040d"), s)
	var low: Color = (p.sky_top as Color).lerp(Color("4f8fd0").lerp(p.sky_low, 0.3), mid).lerp(Color("060a1c"), s)
	var mat := rect.material as ShaderMaterial
	if flying:
		mat.set_shader_parameter("top_col", top)
		mat.set_shader_parameter("low_col", low)
		mat.set_shader_parameter("rush", clampf(speed / 1.2, 0.0, 1.0) * (1.0 - s) * mid)
	_star_y = fposmod(_star_y + delta * (6.0 + speed * 26.0), LaunchPlaces.SIZE.y)
	stars.position.y = _star_y
	stars.modulate.a = smoothstep(7.0, 13.0, climb)
	stars.visible = stars.modulate.a > 0.01
	_update_decks(climb)
	_update_earth(climb)
	_update_moon(climb)


func _update_decks(climb: float) -> void:
	var t := clampf((climb - DECK_IN) / (DECK_OUT - DECK_IN), 0.0, 1.0)
	deck_far.visible = t > 0.0 and climb < 13.0
	front.visible = t > 0.0 and t < 1.0
	# The far deck comes down and stays as a floor below the rocket, then sinks away; the near
	# one races past.
	deck_far.position.y = lerpf(-1000.0, 330.0, ease(t, 0.7)) + maxf(climb - 8.0, 0.0) * 160.0
	front.position.y = lerpf(-900.0, 1400.0, t)


func _update_earth(climb: float) -> void:
	var rise := smoothstep(EARTH_RISE, EARTH_UP, climb)
	var away := smoothstep(MOON_FROM, MOON_AT - 2.0, climb)
	earth.visible = rise > 0.0
	if not earth.visible:
		return
	var limb_y := lerpf(1120.0, 760.0, rise)  # the top of the disc on screen
	var at := Vector2(LaunchPlaces.PAD_X, limb_y + EARTH_R)
	var far := Vector2(300.0, 730.0)
	var s := lerpf(1.0, 0.075, pow(away, 0.45))
	earth.scale = Vector2(s, s)
	earth.position = at.lerp(far, pow(away, 0.32))
	var view := NEAR_VIEW.lerp(FAR_VIEW, smoothstep(0.0, 0.6, away))
	var mat := globe.material as ShaderMaterial
	mat.set_shader_parameter("view_lon", deg_to_rad(view.x + climb * 0.2))
	mat.set_shader_parameter("view_lat", deg_to_rad(view.y))
	mat.set_shader_parameter("lod", maxf(log(MAP_PX_PER_RAD / (EARTH_R * s)) / log(2.0), 0.0))
	mat.set_shader_parameter("cloud_shift", climb * 0.0012)


func _update_moon(climb: float) -> void:
	var t := clampf((climb - MOON_FROM) / (MOON_AT - MOON_FROM), 0.0, 1.0)
	moon.visible = t > 0.0
	if not moon.visible:
		return
	var grow := pow(t, 3.2)
	var s := lerpf(0.1, MOON_END_SCALE, grow)
	moon.scale = Vector2(s, s)
	moon.position = MOON_START.lerp(MOON_END, pow(t, 2.6))


## Drawn in the sky: the Moon's rect, for the frame check.
func moon_rect() -> Rect2:
	var r := MOON_R * moon.scale.x
	return Rect2(moon.position - Vector2(r, r), Vector2(r, r) * 2.0)


## Two copies of the same field, one screen apart, so the drift wraps without a seam.
static func paint_stars(m: MeshBatch2D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90
	for i in STAR_COUNT:
		var at := Vector2(rng.randf_range(-160.0, 2080.0), rng.randf_range(0.0, 1080.0))
		var r := rng.randf_range(1.2, 3.0)
		var bright := rng.randf_range(0.4, 1.0)
		var c := Color(1.0, 0.97, 0.9, bright) if i % 4 else Color(0.74, 0.86, 1.0, bright)
		for copy in 2:
			var p := at - Vector2(0, 1080.0 * copy)
			m.fill(PackedVector2Array([p + Vector2(0, -r * 2.0), p + Vector2(r * 0.5, 0), p + Vector2(0, r * 2.0), p + Vector2(-r * 0.5, 0)]), c, false)
			m.fill(PackedVector2Array([p + Vector2(-r * 2.0, 0), p + Vector2(0, r * 0.5), p + Vector2(r * 2.0, 0), p + Vector2(0, -r * 0.5)]), c, false)


## The Moon: grey with dark seas and craters, lit from the right. Centred on the origin.
static func paint_moon(m: MeshBatch2D) -> void:
	var r := MOON_R
	m.glow(Vector2.ZERO, Vector2(r + 70.0, r + 70.0), Color(0.86, 0.9, 1.0, 0.07), 8, 0.86, r - 30.0)
	m.circle(Vector2.ZERO, r, Color("b9b7b2"))
	m.glow(Vector2(r * 0.26, -r * 0.24), Vector2(r * 0.62, r * 0.62), Color("e6e3da"), 12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	for i in 9:
		var a := rng.randf() * TAU
		var at := Vector2(cos(a), sin(a)) * rng.randf_range(0.1, 0.72) * r
		var size := rng.randf_range(0.14, 0.3) * r
		m.fill(_blob(at, Vector2(size, size * 0.82), rng), Color("9b9998"))
	for i in 44:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r * 0.94
		var at := Vector2(cos(a), sin(a)) * d
		var cr := rng.randf_range(0.015, 0.075) * r
		m.circle(at, cr, Color("8d8b8f"))
		m.circle(at + Vector2(cr * 0.16, -cr * 0.14), cr * 0.8, Color("aeaca8"))
		m.ring(at, cr * 0.86, cr * 1.04, Color("dedbd2"), -0.9, 1.3)
		m.ring(at, cr * 0.86, cr * 1.02, Color("6f6d74"), 2.2, 4.4)
	m.glow(Vector2(-r * 0.92, r * 0.5), Vector2(r * 1.4, r * 1.4), Color(0.03, 0.03, 0.09, 0.72), 10)


## A soft lump: solid to 60% of its radius, fading out by the edge. Few vertices, because the
## decks and the Earth's weather are drawn every frame they show, not baked.
static func _soft(m: MeshBatch2D, at: Vector2, radius: Vector2, col: Color) -> void:
	var inner := MeshBatch2D._ellipse(at, radius * 0.6, 16)
	m.fill(inner, col, false)
	m.band(inner, MeshBatch2D._ellipse(at, radius, 16), col, Color(col, 0.0))


## A soft-edged land or sea shape: an ellipse wobbled by two low sine waves, so it never looks cut.
static func _blob(at: Vector2, size: Vector2, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var a := rng.randf_range(0.0, TAU)
	var b := rng.randf_range(0.0, TAU)
	for k in 32:
		var ang := TAU * k / 32.0
		var wob := 1.0 + 0.2 * sin(ang * 3.0 + a) + 0.1 * sin(ang * 5.0 + b)
		pts.append(at + Vector2(cos(ang) * size.x, sin(ang) * size.y) * wob)
	return pts


## A wide cloud deck: lumpy tops, a flat base, lit from the right. Deck 0 is a full-width floor,
## deck 1 banks at the sides with a gap for the rocket.
func _paint_deck(ci: CanvasItem, deck: int) -> void:
	var m := MeshBatch2D.new()
	var p := LaunchPlaces.place(_place)
	var lit: Color = p.cloud
	var shade: Color = p.cloud2
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + deck
	if deck == 0:
		m.rect_v(Rect2(-240.0, 720.0, 2400.0, 760.0), shade.lerp(lit, 0.55), shade)
	# Rows front to back: small soft lumps, each lit on its sunward top, overlapping into a bank.
	for row in 3:
		var x := -220.0 + row * 37.0
		var base := (700.0 if deck == 0 else 520.0) + row * 46.0
		var tone := 0.72 - row * 0.2
		while x < 2140.0:
			var r := rng.randf_range(42.0, 96.0)
			if deck == 1 and absf(x - LaunchPlaces.PAD_X) < 420.0:
				x += r
				continue
			var at := Vector2(x, base + rng.randf_range(-34.0, 26.0))
			_soft(m, at + Vector2(0, r * 0.3), Vector2(r * 1.5, r * 1.1), shade.lerp(lit, tone * 0.6))
			_soft(m, at + Vector2(r * 0.2, -r * 0.1), Vector2(r * 1.05, r * 0.85), shade.lerp(lit, tone + 0.28))
			x += r * rng.randf_range(0.8, 1.2)
	m.flush(ci)
