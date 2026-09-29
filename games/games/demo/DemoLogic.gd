class_name DemoLogic
extends RefCounted
## The demo game's rules, apart from drawing so they're tested headless: lean to steer along
## the bottom of the screen, dodge the falling balls. Cadence sets their speed; a dodge scores
## only while cadence is at or above the floor, with a bonus for a streak of clean dodges.
## Balls come faster on harder difficulties, and some aim at where the rider is.

const FIELD := Vector2(1920, 1080)
const PLAYER_Y := 930.0
const PLAYER_HALF_WIDTH := 55.0
## The player's triangle around (player_x, PLAYER_Y). Balls hit it only when they touch this
## shape, so a ball that visibly misses misses: on the bike, a box as wide as the triangle's base
## counted balls passing the tip up to 24 px clear of it.
const PLAYER_SHAPE := [Vector2(0, -50), Vector2(-PLAYER_HALF_WIDTH, 40), Vector2(PLAYER_HALF_WIDTH, 40)]
const EDGE := 120.0  ## full lean puts the player this far from the screen edge
## Lean → position gain. On the bike (run 2) the player crossed the screen in about 1.2 s and
## moved at a median 0.68 lean units/s, limited by how far the head must travel; 1.3 lets it
## reach the edge at 77% of the tracker's full lock, so the same head speed crosses faster.
const STEERING_GAIN := 1.3
const BALL_RADIUS := 40.0
const BASE_SPEED := 300.0  ## px/s at 0 rpm
const SPEED_PER_RPM := 5.0
const DODGE_POINTS := 10.0
const STREAK_BONUS_MAX := 5  ## +1 per clean dodge in a row, up to +5
const AIM_CHANCE := 0.4  ## share of balls aimed at the player

## Per difficulty: seconds between balls and the default cadence floor (rpm).
const LEVELS := {
	"easy": {"spawn_sec": 1.2, "cadence_floor": 55.0},
	"standard": {"spawn_sec": 0.9, "cadence_floor": 60.0},
	"hard": {"spawn_sec": 0.7, "cadence_floor": 70.0},
}

var player_x := FIELD.x / 2
var balls: Array[Vector2] = []
var spawn_sec := 0.9
var cadence_floor := 60.0
var streak := 0
var best_streak := 0
var dodged := 0
var hits := 0

var _rng := RandomNumberGenerator.new()
var _spawn_left := 0.0


func _init(seed_value: int, difficulty := "standard", floor_rpm := -1.0) -> void:
	_rng.seed = seed_value
	var level: Dictionary = LEVELS.get(difficulty, LEVELS.standard)
	spawn_sec = level.spawn_sec
	cadence_floor = floor_rpm if floor_rpm > 0.0 else level.cadence_floor
	_spawn_left = 0.5


## The player's x for a lean from -1 (left) to +1 (right), with STEERING_GAIN: the screen edge
## comes at 1 / STEERING_GAIN of the tracker's full lock.
static func x_for_lean(lean: float) -> float:
	return FIELD.x / 2 + clampf(lean * STEERING_GAIN, -1.0, 1.0) * (FIELD.x / 2 - EDGE)


static func fall_speed(cadence: float) -> float:
	return BASE_SPEED + maxf(cadence, 0.0) * SPEED_PER_RPM


## Advances one frame. Returns events for the scene: {type: "spawn"}, {type: "hit", at},
## {type: "dodge", points, at} (points 0 below the cadence floor).
func step(delta: float, lean: float, cadence: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	player_x = x_for_lean(lean)
	_spawn_left -= delta
	if _spawn_left <= 0.0:
		_spawn_left += spawn_sec
		balls.append(Vector2(_spawn_x(), -BALL_RADIUS))
		events.append({"type": "spawn"})
	var dy := fall_speed(cadence) * delta
	var kept: Array[Vector2] = []
	for ball in balls:
		ball.y += dy
		if touches_player(ball, player_x):
			hits += 1
			streak = 0
			events.append({"type": "hit", "at": ball})
		elif ball.y > FIELD.y + BALL_RADIUS:
			dodged += 1
			var points := 0.0
			if cadence >= cadence_floor:
				streak += 1
				best_streak = maxi(best_streak, streak)
				points = DODGE_POINTS + mini(streak - 1, STREAK_BONUS_MAX)
			events.append({"type": "dodge", "points": points, "at": ball})
		else:
			kept.append(ball)
	balls = kept
	return events


## Whether a ball at `ball` overlaps the player's triangle at `x`.
static func touches_player(ball: Vector2, x: float) -> bool:
	var local := ball - Vector2(x, PLAYER_Y)
	if Geometry2D.is_point_in_polygon(local, PackedVector2Array(PLAYER_SHAPE)):
		return true
	for i in 3:
		var a: Vector2 = PLAYER_SHAPE[i]
		var b: Vector2 = PLAYER_SHAPE[(i + 1) % 3]
		if local.distance_to(Geometry2D.get_closest_point_to_segment(local, a, b)) < BALL_RADIUS:
			return true
	return false


func _spawn_x() -> float:
	if _rng.randf() < AIM_CHANCE:
		return clampf(player_x + _rng.randf_range(-40.0, 40.0), BALL_RADIUS, FIELD.x - BALL_RADIUS)
	return _rng.randf_range(BALL_RADIUS, FIELD.x - BALL_RADIUS)
