class_name DodgeTimeOfDay
extends Resource
## One lighting preset for Dodge Ball's road (`tod/<name>.tres`): sky, sun, ambient light, fog,
## and how much the street lamps and the bike's headlight glow. The rider picks one in the
## pause screen's "Game options", or "Auto" follows the local clock (`for_hour`).

const NAMES := ["dawn", "day", "dusk", "night"]

@export var id := "day"
@export_group("Sky")
@export var sky_top := Color(0.25, 0.5, 0.95)
@export var sky_horizon := Color(0.75, 0.85, 0.95)
@export var sky_ground := Color(0.3, 0.32, 0.3)
@export var clouds := 0.5
@export var cloud_color := Color(1, 1, 1)
@export var stars := 0.0
@export var halo := 0.4
@export var sun_size := 0.03
@export_group("Sun")
@export var sun_elevation := 50.0  ## degrees above the horizon
@export var sun_azimuth := -30.0  ## degrees from straight ahead, + to the right
@export var sun_color := Color(1, 0.96, 0.88)
@export var sun_energy := 1.1
@export_group("Ambient and fog")
@export var ambient := Color(0.6, 0.7, 0.85)
@export var ambient_energy := 0.6
@export var fog_color := Color(0.75, 0.85, 0.95)
@export var fog_density := 0.012
@export_group("Lights")
@export var lamp_glow := 0.0
@export var headlight := 0.0
@export var ball_glow := 0.0  ## extra self-lighting on the balls, so they read at night


static func load_preset(name: String) -> DodgeTimeOfDay:
	return load("res://games/dodge_ball/tod/%s.tres" % name) as DodgeTimeOfDay


## The preset for a local hour: dawn 5-8, day 8-17, dusk 17-20, night otherwise.
static func for_hour(hour: int) -> String:
	if hour >= 5 and hour < 8:
		return "dawn"
	if hour >= 8 and hour < 17:
		return "day"
	if hour >= 17 and hour < 20:
		return "dusk"
	return "night"


## The option's value ("auto", "dawn", …) as a preset name, with "auto" following the clock.
static func resolve(option: String, hour := -1) -> String:
	if option in NAMES:
		return option
	if hour < 0:
		hour = int(Time.get_datetime_dict_from_system().hour)
	return for_hour(hour)
