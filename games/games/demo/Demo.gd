extends Game
## The demo game: a reference for game authors (docs/GAMES.md, "Adding a game"). Lean to dodge
## falling balls; pedal above the cadence floor for dodges to score. The rules are in
## `DemoLogic`; this scene only draws them and wires the framework:
##   - declarations in info(), the intro card's target in target_text()
##   - a TargetBand on the HUD, music and effects from AudioDirector
##   - points only through award(), which applies the effort multiplier and the freezes

const MUSIC_STYLE := {
	"name": "demo_drive",
	# Drums and bass always; harmony and lead come in as cadence nears the target.
	"stem_gates": {"harmony": 0.5, "lead": 0.85},
}
## Logs lean and ball outcomes every frame, for steering checks on the bike (docs/GAMES.md).
const TRACE_LEAN := true
const STRIPES := 12
const BACKGROUND := Color(0.08, 0.09, 0.16)
const BALL_COLOR := Color(1.0, 0.45, 0.2)
const PLAYER_COLOR := Color(0.24, 0.86, 0.52)
const STANDING_COLOR := Color(1.0, 0.9, 0.2)

var logic: DemoLogic

var _player: Polygon2D
var _stripes: Array[ColorRect] = []
var _ball_sprites: Array[Sprite2D] = []
var _ball_texture: ImageTexture
var _burst: CPUParticles2D
var _cadence_band: TargetBand


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "demo"
	i.title = "Demo"
	i.how_to = "Lean left and right to dodge the falling balls"
	i.supports = ["minutes", "open"]
	i.min_sec = 60
	i.max_sec = 3600
	# Any role, so circuit mode (#37) can use it until the real games land.
	i.roles = ["warmup", "work", "recovery", "cooldown"]
	i.tracker_mode = "lean_x"
	i.effort_in_just_ride = true
	i.stars_per_minute = true
	# Points per minute. 3 stars needs about 1.3× effort: a perfect run at 1.0× stays below.
	i.star_thresholds = {
		"easy": [220, 480, 760],
		"standard": [300, 650, 1020],
		"hard": [390, 850, 1300],
	}
	return i


func target_text(seg: Dictionary) -> String:
	return "Keep your cadence above %d rpm" % roundi(_cadence_floor(seg))


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BACKGROUND
	bg.size = DemoLogic.FIELD
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	for i in STRIPES:
		var stripe := ColorRect.new()
		stripe.color = Color(1, 1, 1, 0.18)
		stripe.size = Vector2(12, 60)
		stripe.position = Vector2(DemoLogic.FIELD.x / 2 - 6, i * DemoLogic.FIELD.y / STRIPES)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(stripe)
		_stripes.append(stripe)
	_ball_texture = _circle_texture(int(DemoLogic.BALL_RADIUS), BALL_COLOR)
	_player = Polygon2D.new()
	_player.polygon = PackedVector2Array([Vector2(0, -50), Vector2(-DemoLogic.PLAYER_HALF_WIDTH, 40), Vector2(DemoLogic.PLAYER_HALF_WIDTH, 40)])
	_player.color = PLAYER_COLOR
	_player.position = Vector2(DemoLogic.FIELD.x / 2, DemoLogic.PLAYER_Y)
	add_child(_player)
	_burst = CPUParticles2D.new()
	_burst.one_shot = true
	_burst.emitting = false
	_burst.amount = 50
	_burst.lifetime = 0.5
	_burst.explosiveness = 1.0
	_burst.spread = 180.0
	_burst.initial_velocity_min = 200.0
	_burst.initial_velocity_max = 500.0
	_burst.scale_amount_min = 4.0
	_burst.scale_amount_max = 8.0
	_burst.color = Color(1, 0.8, 0.3)
	add_child(_burst)


func _on_prepare(seg: Dictionary) -> void:
	logic = DemoLogic.new(rng.seed, difficulty, _cadence_floor(seg))
	_sync_balls()
	_cadence_band = TargetBand.new("cadence", 0, 130, logic.cadence_floor, INF, "rpm")
	_cadence_band.source = func(): return InputBus.cadence
	hud.add_widget(_cadence_band)
	# One beat per pedal stroke at a comfortable cadence above the floor.
	AudioDirector.play_music(MUSIC_STYLE, logic.cadence_floor + 20.0, int(seg.get("seed", 0)))


func _on_frame(delta: float) -> void:
	var events := logic.step(delta, InputBus.lean_x, InputBus.cadence)
	if TRACE_LEAN:
		# Steering diagnosis on the bike: every frame's lean and position, and each ball's outcome.
		print("OPENRIDE_GAMES lean t=%d x=%+.3f px=%.0f tr=%d" % [
			Time.get_ticks_msec(), InputBus.lean_x, logic.player_x, InputBus.tracker_state])
		for event in events:
			if event.type != "spawn":
				print("OPENRIDE_GAMES ball %s t=%d bx=%.0f px=%.0f" % [
					event.type, Time.get_ticks_msec(), event.at.x, logic.player_x])
	for event in events:
		match event.type:
			"dodge":
				if award(event.points) > 0.0:
					AudioDirector.play_sfx("dodge", 0.0, 1.0 + 0.05 * mini(logic.streak, 6))
			"hit":
				_burst.position = event.at
				_burst.restart()
				AudioDirector.play_sfx("hit")
	_player.position.x = logic.player_x
	_player.color = STANDING_COLOR if InputBus.standing else PLAYER_COLOR
	var scroll := DemoLogic.fall_speed(InputBus.cadence) * 0.6 * delta
	for stripe in _stripes:
		stripe.position.y = fposmod(stripe.position.y + scroll, DemoLogic.FIELD.y + 60) - 60
	_sync_balls()
	AudioDirector.set_intensity(InputBus.cadence / (logic.cadence_floor + 20.0))
	stats = {"dodged": logic.dodged, "hits": logic.hits, "best_streak": logic.best_streak}


func _cadence_floor(seg: Dictionary) -> float:
	var p: Dictionary = seg.get("params", {})
	if p.has("cadence_floor"):
		return float(p.cadence_floor)
	var level: Dictionary = DemoLogic.LEVELS.get(str(seg.get("difficulty", "standard")), DemoLogic.LEVELS.standard)
	return level.cadence_floor


func _sync_balls() -> void:
	var balls: Array[Vector2] = logic.balls if logic else []
	while _ball_sprites.size() < balls.size():
		var sprite := Sprite2D.new()
		sprite.texture = _ball_texture
		add_child(sprite)
		move_child(sprite, _player.get_index())
		_ball_sprites.append(sprite)
	for i in _ball_sprites.size():
		_ball_sprites[i].visible = i < balls.size()
		if i < balls.size():
			_ball_sprites[i].position = balls[i]


static func _circle_texture(radius: int, color: Color) -> ImageTexture:
	var img := Image.create(radius * 2, radius * 2, false, Image.FORMAT_RGBA8)
	for y in radius * 2:
		for x in radius * 2:
			var d := Vector2(x - radius + 0.5, y - radius + 0.5).length()
			img.set_pixel(x, y, Color(color, clampf(radius - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
