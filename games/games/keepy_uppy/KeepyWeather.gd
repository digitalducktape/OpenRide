class_name KeepyWeather
extends Node2D
## Keepy Uppy's weather on screen (#77, 2D; ART_BIBLE.md §2 and §7). Each force shows in the
## place before it acts, from its warning:
##   rain       a dark cloud sails in from the right and its shadow creeps over the ground; then
##              rain falls under it (a streak shader on one rect)
##   bird       a bird flaps in from the left to land on the balloon
##   downdraft  a curtain of dark, slanting air sweeps in from the right over the warning and
##              passes over the column (the same streak shader, its leading edge a uniform)
##   gust       (the high band) a few pale wind lines sweep past the balloon
## Shapes are drawn once; per frame only positions and a few uniforms change. The cloud's shadow
## and the cloud sit behind the balloon (`back`); the rain, the curtain and the wind lines in
## front of it (`front`, added by the scene above the balloon).

const CLOUD_FROM := Vector2(2150, 500)  ## low and small on the horizon, under the HUD's panels
const CLOUD_OVER := Vector2(1150, 380)
const CLOUD_GONE := Vector2(-260, 500)
const CLOUD_W := 340.0
const RAIN_W := 460.0
const BIRD_FROM := Vector2(-180, 520)
const SHADOW_Y := 930.0
const CLOUD_FAR_SCALE := 0.4

var back: Node2D
var front: Node2D
var cloud: Node2D
var shadow: Node2D
var rain: ColorRect
var curtain: ColorRect
var flyer: Node2D
var wind_lines: Node2D
var _cloud_t := 0.0  ## 0 off to the right, 1 overhead
var _leaving := false
var _rain := 0.0
var _curtain := 0.0
var _reach := 0.0
var _t := 0.0
var _warming := false


func _init() -> void:
	back = Node2D.new()
	back.name = "WeatherBack"
	front = Node2D.new()
	front.name = "WeatherFront"
	shadow = PaintLayer.new()
	shadow.name = "CloudShadow"
	shadow.paint = func(ci: CanvasItem) -> void:
		var m := MeshBatch2D.new()
		m.glow(Vector2.ZERO, Vector2(420, 70), Color(0.05, 0.08, 0.14, 0.32), 10)
		m.flush(ci)
	shadow.visible = false
	back.add_child(shadow)
	cloud = PaintLayer.new()
	cloud.name = "RainCloud"
	cloud.paint = func(ci: CanvasItem) -> void:
		var m := MeshBatch2D.new()
		KeepyPlaces.cumulus(m, Vector2.ZERO, CLOUD_W, Color("8592a4"), Color("56606f"))
		KeepyPlaces.cumulus(m, Vector2(-150, 34), CLOUD_W * 0.6, Color("75818f"), Color("4c5562"))
		m.flush(ci)
	cloud.visible = false
	back.add_child(cloud)
	rain = _streaks("Rain", Rect2(-RAIN_W * 0.5, 40, RAIN_W, 620), {"tint": Color(0.8, 0.86, 0.95), "fall": 1.8,
		"columns": 60.0, "slant": 0.12, "density": 0.6, "opacity": 0.75})
	front.add_child(rain)
	rain.visible = false
	curtain = _streaks("Downdraft", Rect2(-KeepyPlaces.BLEED, 0, KeepyPlaces.WIDE.x, 980), {"tint": Color(0.16, 0.2, 0.28),
		"fall": 1.3, "columns": 90.0, "slant": -0.35, "density": 0.55, "opacity": 0.55, "soft_edge": 0.16})
	front.add_child(curtain)
	curtain.visible = false
	flyer = PaintLayer.new()
	flyer.name = "FlyingBird"
	flyer.paint = func(ci: CanvasItem) -> void: KeepyBalloon.paint_bird(ci, false, true)
	flyer.visible = false
	front.add_child(flyer)
	wind_lines = PaintLayer.new()
	wind_lines.name = "WindLines"
	wind_lines.paint = _paint_wind_lines
	wind_lines.visible = false
	front.add_child(wind_lines)


func _streaks(n: String, r: Rect2, params: Dictionary) -> ColorRect:
	var c := ColorRect.new()
	c.name = n
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://games/keepy_uppy/shaders/keepy_streaks.gdshader")
	for k in params:
		mat.set_shader_parameter(k, params[k])
	c.material = mat
	return c


## Draws the logic's weather. `balloon_at` is where the balloon is drawn now (the bird's perch).
func update(delta: float, logic: KeepyLogic, balloon_at: Vector2) -> void:
	_t += delta
	# The rain cloud: in on its warning, overhead while it rains, then away to the left.
	var coming := logic.force == "rain" and logic.weather != KeepyLogic.Weather.CALM
	if coming:
		_leaving = false
		if logic.weather == KeepyLogic.Weather.TELEGRAPH:
			_cloud_t = maxf(_cloud_t, 1.0 - logic.force_left / KeepyLogic.WARNING.rain)
		else:
			_cloud_t = 1.0
	elif logic.raining:
		_cloud_t = 1.0
	elif _cloud_t > 0.0:
		_leaving = true
		_cloud_t = move_toward(_cloud_t, 0.0, delta / 4.0)
	var e := ease(_cloud_t, -1.8)
	var from := CLOUD_GONE if _leaving else CLOUD_FROM
	cloud.position = from.lerp(CLOUD_OVER, e) + Vector2(sin(_t * 0.3) * 8.0, 0.0)
	cloud.scale = Vector2.ONE * lerpf(CLOUD_FAR_SCALE, 1.0, e)  # it grows as it nears
	cloud.visible = _cloud_t > 0.001 or _warming
	shadow.visible = cloud.visible
	shadow.position = Vector2(cloud.position.x - 60.0, SHADOW_Y)
	shadow.modulate.a = e
	_rain = move_toward(_rain, 1.0 if logic.raining else 0.0, delta / 1.2)
	rain.visible = _rain > 0.01 or _warming
	rain.position = cloud.position + Vector2(-RAIN_W * 0.5, 40.0)
	(rain.material as ShaderMaterial).set_shader_parameter("amount", _rain)
	# The downdraft's curtain: sweeps in over the warning, holds over the column, then clears.
	var dd := logic.force == "downdraft"
	if dd and logic.weather == KeepyLogic.Weather.TELEGRAPH:
		_curtain = minf(_curtain + delta * 2.0, 1.0)
		_reach = 0.55 * (1.0 - logic.force_left / KeepyLogic.WARNING.downdraft)
	elif dd and logic.weather == KeepyLogic.Weather.ACTIVE:
		_curtain = 1.0
		_reach = minf(_reach + delta * 0.4, 1.15)
	else:
		_curtain = move_toward(_curtain, 0.0, delta * 1.2)
		_reach = minf(_reach + delta * 0.4, 1.2)
	curtain.visible = _curtain > 0.01 or _warming
	if curtain.visible:
		var cm := curtain.material as ShaderMaterial
		cm.set_shader_parameter("amount", _curtain)
		cm.set_shader_parameter("reach", _reach)
	# The bird flapping in to land on the balloon.
	var incoming := logic.weather == KeepyLogic.Weather.TELEGRAPH and logic.force == "bird" \
		and logic.balloon == KeepyLogic.Balloon.FLYING
	flyer.visible = incoming or _warming
	if incoming:
		var p := 1.0 - logic.force_left / KeepyLogic.WARNING.bird
		var perch: Vector2 = KeepyBalloon.PERCHES[mini(logic.birds, KeepyBalloon.PERCHES.size() - 1)]
		var land := balloon_at + perch
		var k := ease(clampf(p, 0.0, 1.0), -1.6)
		flyer.position = BIRD_FROM.lerp(land, k) + Vector2(0.0, -sin(p * PI) * 90.0)
		flyer.scale = Vector2(1.0, 0.8 + 0.2 * sin(_t * 22.0))
	# A gust's wind lines sweeping past the balloon.
	wind_lines.visible = logic.gust != "" or _warming
	if wind_lines.visible:
		wind_lines.position = Vector2(fposmod(_t * 900.0, 1400.0) + 260.0, balloon_at.y)


## Draws every hidden effect once (alpha nothing to see), so its shader compiles behind the
## intro card.
func prewarm() -> void:
	_warming = true
	for i in 3:
		await get_tree().process_frame
	_warming = false


## Three pale curved strokes, like a breeze in a picture book.
func _paint_wind_lines(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	for k in 3:
		var y := -60.0 + k * 55.0
		var pts := MeshBatch2D.arc_points(Vector2(0, y + 120.0), 140.0, PI * 1.35, PI * 1.65, 10)
		for j in pts.size() - 1:
			m.line(pts[j] + Vector2(k * 40.0, 0), pts[j + 1] + Vector2(k * 40.0, 0), 4.0, Color(1, 1, 1, 0.55))
	m.flush(ci)
