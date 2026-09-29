class_name DemoLogic
extends RefCounted
## The demo game's rules, apart from drawing so they're tested headless: lean to steer along
## the bottom of the screen, dodge the falling balls. Cadence sets their speed; a dodge scores
## only while cadence is at or above the floor, with a bonus for a streak of clean dodges.
## Balls come faster on harder difficulties, and some aim at where the rider is.

const FIELD := Vector2(1920, 1080)
const PLAYER_Y := 930.0
const PLAYER_HALF_WIDTH := 55.0
const EDGE := 120.0  ## full lean puts the player this far from the screen edge
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


## The player's x for a lean from -1 (left) to +1 (right).
static func x_for_lean(lean: float) -> float:
	return FIELD.x / 2 + clampf(lean, -1.0, 1.0) * (FIELD.x / 2 - EDGE)


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
		var before := ball.y
		ball.y += dy
		if _crosses_player(before, ball.y) and absf(ball.x - player_x) < PLAYER_HALF_WIDTH + BALL_RADIUS:
			hits += 1
			streak = 0
			events.append({"type": "hit", "at": Vector2(ball.x, PLAYER_Y)})
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


func _crosses_player(before: float, after: float) -> bool:
	return before < PLAYER_Y and after >= PLAYER_Y


func _spawn_x() -> float:
	if _rng.randf() < AIM_CHANCE:
		return clampf(player_x + _rng.randf_range(-40.0, 40.0), BALL_RADIUS, FIELD.x - BALL_RADIUS)
	return _rng.randf_range(BALL_RADIUS, FIELD.x - BALL_RADIUS)
