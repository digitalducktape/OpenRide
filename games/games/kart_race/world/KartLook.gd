class_name KartLook
extends RefCounted
## Kart Race's art direction in one place (#43): each theme's light, sky and palette, and the
## material factories that set them. Everything in the world is `unshaded` and lit by hand from
## these values (shaders/light.gdshaderinc), so the karts, the road and the scenery always
## agree, and no engine light pass runs on the tablet.
##
## `set_theme()` (KartWorld calls it when it builds a track) re-lights every material made here,
## karts and HUD portraits included. The sun keeps one compass bearing in every theme (only its
## height and colour change), so blob shadows cast from `SUN_DIR` stay right everywhere.

## Towards the sun: low in the west-south-west, behind and left of Meadow Ring's start straight,
## so karts on the grid are lit and their shadows stretch long to the right. (Meadow's values;
## the other themes share the bearing.)
const SUN_DIR := Vector3(-0.762, 0.438, -0.476)
const SUN_COLOR := Color(1.0, 0.85, 0.64)
const SKY_AMBIENT := Color(0.52, 0.62, 0.84)
const GROUND_AMBIENT := Color(0.44, 0.40, 0.28)
const HAZE := Color(0.93, 0.84, 0.74)
const HAZE_DENSITY := 0.0024

const SHADERS := "res://games/kart_race/world/shaders/"

## Per theme: `light` (shared by every shader), `sky`, `road`, `ground` (shader uniforms) and the
## builders' colours (`wall_*`, `stand_*`, `flags`, `cloud`).
const THEMES := {
	"meadow": {
		"sun_height": 0.438,
		"light": {"sun_color": Color(1.0, 0.85, 0.64), "sky_color": Color(0.52, 0.62, 0.84),
			"ground_color": Color(0.44, 0.40, 0.28), "haze_color": Color(0.93, 0.84, 0.74), "haze_density": 0.0024},
		"sky": {"top_color": Color(0.24, 0.45, 0.85), "mid_color": Color(0.55, 0.72, 0.95),
			"horizon_color": Color(1.0, 0.84, 0.66), "ground_color": Color(0.55, 0.62, 0.42),
			"sun_color": Color(1.0, 0.9, 0.7), "cloud_lit": Color(1.0, 0.97, 0.92), "cloud_shade": Color(0.72, 0.74, 0.86),
			"glare": 0.38, "halo": 0.07},
		"road": {"asphalt": Color(0.30, 0.31, 0.35), "asphalt_dark": Color(0.20, 0.21, 0.24),
			"line_color": Color(0.96, 0.95, 0.9), "kerb_a": Color(0.86, 0.13, 0.12), "kerb_b": Color(0.97, 0.97, 0.95),
			"grass_a": Color(0.36, 0.62, 0.20), "grass_b": Color(0.44, 0.70, 0.24), "verge_stripes": 0.4,
			"verge_dust": Color(0.42, 0.38, 0.3)},
		"ground": {"grass_a": Color(0.33, 0.58, 0.19), "grass_b": Color(0.50, 0.71, 0.25), "dry": Color(0.70, 0.68, 0.36),
			"flowers": 1.0, "rock_a": Color(0.55, 0.52, 0.46), "rock_b": Color(0.46, 0.43, 0.38),
			"rock_c": Color(0.62, 0.58, 0.5), "rock_slope": 0.55, "strata": 2.5,
			"speck_a": Color(1.0, 0.95, 0.35), "speck_b": Color(0.98, 0.98, 1.0), "speck_c": Color(0.95, 0.45, 0.75)},
		"wall_a": Color(0.96, 0.96, 0.97), "wall_b": Color(0.16, 0.52, 0.86), "wall_rail": Color(0.9, 0.2, 0.16),
		"wall_cap": Color(0.9, 0.91, 0.93), "wall_foot": Color(0.13, 0.13, 0.15), "wall_style": "tyres",
		"stand_a": Color(0.15, 0.45, 0.85), "stand_b": Color(1.0, 0.78, 0.15), "stand_roof": Color(0.92, 0.24, 0.2),
		"gate": Color(0.12, 0.14, 0.3), "gate_band": Color(0.9, 0.2, 0.17),
		"cloud": Color(1.0, 0.97, 0.93), "clouds": 14,
	},
	"canyon": {
		"sun_height": 0.62,
		"light": {"sun_color": Color(1.0, 0.88, 0.7), "sky_color": Color(0.55, 0.66, 0.86),
			"ground_color": Color(0.62, 0.38, 0.24), "haze_color": Color(0.96, 0.80, 0.62), "haze_density": 0.0021},
		"sky": {"top_color": Color(0.20, 0.42, 0.82), "mid_color": Color(0.52, 0.70, 0.93),
			"horizon_color": Color(1.0, 0.82, 0.62), "ground_color": Color(0.80, 0.52, 0.34),
			"sun_color": Color(1.0, 0.93, 0.78), "cloud_lit": Color(1.0, 0.96, 0.9), "cloud_shade": Color(0.82, 0.74, 0.74)},
		"road": {"asphalt": Color(0.33, 0.30, 0.31), "asphalt_dark": Color(0.24, 0.21, 0.22),
			"line_color": Color(0.98, 0.93, 0.8), "kerb_a": Color(0.88, 0.16, 0.12), "kerb_b": Color(0.98, 0.96, 0.92),
			"grass_a": Color(0.86, 0.60, 0.36), "grass_b": Color(0.92, 0.68, 0.42), "verge_stripes": 0.0,
			"verge_dust": Color(0.70, 0.46, 0.30)},
		"ground": {"grass_a": Color(0.88, 0.58, 0.34), "grass_b": Color(0.95, 0.70, 0.44), "dry": Color(0.80, 0.50, 0.30),
			"flowers": 0.25, "rock_a": Color(0.78, 0.36, 0.20), "rock_b": Color(0.62, 0.25, 0.15),
			"rock_c": Color(0.93, 0.62, 0.40), "rock_slope": 0.82, "strata": 1.6,
			"speck_a": Color(0.45, 0.55, 0.22), "speck_b": Color(0.62, 0.42, 0.28), "speck_c": Color(0.98, 0.85, 0.6)},
		"wall_a": Color(0.74, 0.52, 0.32), "wall_b": Color(0.95, 0.45, 0.12), "wall_rail": Color(0.18, 0.18, 0.22),
		"wall_cap": Color(0.86, 0.68, 0.46), "wall_foot": Color(0.42, 0.24, 0.16), "wall_style": "timber",
		"stand_a": Color(0.1, 0.62, 0.66), "stand_b": Color(1.0, 0.85, 0.3), "stand_roof": Color(0.98, 0.5, 0.18),
		"gate": Color(0.35, 0.16, 0.12), "gate_band": Color(0.1, 0.62, 0.66),
		"cloud": Color(1.0, 0.95, 0.9), "clouds": 10,
	},
	"harbor": {
		"sun_height": 0.16,
		"light": {"sun_color": Color(1.0, 0.66, 0.42), "sky_color": Color(0.50, 0.46, 0.76),
			"ground_color": Color(0.40, 0.30, 0.34), "haze_color": Color(0.98, 0.70, 0.58), "haze_density": 0.0026},
		"sky": {"top_color": Color(0.22, 0.20, 0.52), "mid_color": Color(0.70, 0.46, 0.66),
			"horizon_color": Color(1.0, 0.62, 0.36), "ground_color": Color(0.26, 0.30, 0.48),
			"sun_color": Color(1.0, 0.78, 0.45), "cloud_lit": Color(1.0, 0.72, 0.56), "cloud_shade": Color(0.48, 0.38, 0.62)},
		"road": {"asphalt": Color(0.30, 0.29, 0.34), "asphalt_dark": Color(0.21, 0.20, 0.25),
			"line_color": Color(0.98, 0.92, 0.82), "kerb_a": Color(0.16, 0.42, 0.85), "kerb_b": Color(0.97, 0.96, 0.95),
			"grass_a": Color(0.58, 0.54, 0.52), "grass_b": Color(0.66, 0.62, 0.58), "verge_stripes": 0.0,
			"verge_dust": Color(0.42, 0.38, 0.38), "cobbles": 1.0},
		"ground": {"grass_a": Color(0.40, 0.56, 0.26), "grass_b": Color(0.52, 0.64, 0.30), "dry": Color(0.62, 0.56, 0.44),
			"flowers": 0.5, "rock_a": Color(0.56, 0.52, 0.52), "rock_b": Color(0.44, 0.40, 0.42),
			"rock_c": Color(0.66, 0.6, 0.56), "rock_slope": 0.7, "strata": 1.2,
			"speck_a": Color(1.0, 0.85, 0.4), "speck_b": Color(1.0, 0.6, 0.65), "speck_c": Color(0.95, 0.95, 1.0)},
		"wall_a": Color(0.96, 0.95, 0.94), "wall_b": Color(0.16, 0.42, 0.85), "wall_rail": Color(0.98, 0.78, 0.2),
		"wall_cap": Color(0.86, 0.84, 0.82), "wall_foot": Color(0.36, 0.34, 0.38), "wall_style": "quay",
		"stand_a": Color(0.16, 0.42, 0.85), "stand_b": Color(0.98, 0.98, 0.98), "stand_roof": Color(0.9, 0.22, 0.28),
		"gate": Color(0.1, 0.18, 0.36), "gate_band": Color(0.98, 0.78, 0.2),
		"cloud": Color(1.0, 0.78, 0.7), "clouds": 14,
	},
	"frost": {
		"sun_height": 0.34,
		"light": {"sun_color": Color(1.0, 0.93, 0.84), "sky_color": Color(0.60, 0.72, 0.92),
			"ground_color": Color(0.62, 0.66, 0.74), "haze_color": Color(0.84, 0.90, 0.98), "haze_density": 0.0030},
		"sky": {"top_color": Color(0.26, 0.48, 0.86), "mid_color": Color(0.62, 0.78, 0.96),
			"horizon_color": Color(0.94, 0.94, 0.98), "ground_color": Color(0.80, 0.86, 0.94),
			"sun_color": Color(1.0, 0.96, 0.86), "cloud_lit": Color(1.0, 1.0, 1.0), "cloud_shade": Color(0.74, 0.80, 0.92)},
		"road": {"asphalt": Color(0.31, 0.33, 0.38), "asphalt_dark": Color(0.22, 0.24, 0.29),
			"line_color": Color(0.98, 0.98, 1.0), "kerb_a": Color(0.85, 0.14, 0.18), "kerb_b": Color(0.98, 0.98, 1.0),
			"grass_a": Color(0.90, 0.93, 0.98), "grass_b": Color(0.96, 0.98, 1.0), "verge_stripes": 0.0,
			"verge_dust": Color(0.70, 0.76, 0.88), "verge_grain": 0.06, "verge_gain": 1.2},
		"ground": {"grass_a": Color(0.90, 0.93, 0.99), "grass_b": Color(0.98, 0.99, 1.0), "dry": Color(0.80, 0.86, 0.95),
			"snow": 1.0, "grain": 0.06, "flowers": 0.0, "rock_a": Color(0.42, 0.44, 0.52), "rock_b": Color(0.32, 0.34, 0.42),
			"rock_c": Color(0.55, 0.57, 0.64), "rock_slope": 0.62, "strata": 3.0,
			"speck_a": Color(0.7, 0.85, 1.0), "speck_b": Color(1.0, 1.0, 1.0), "speck_c": Color(0.8, 0.9, 1.0)},
		"wall_a": Color(0.97, 0.97, 0.99), "wall_b": Color(0.85, 0.14, 0.18), "wall_rail": Color(0.85, 0.14, 0.18),
		"wall_cap": Color(0.98, 0.99, 1.0), "wall_foot": Color(0.5, 0.6, 0.8), "wall_style": "snow",
		"stand_a": Color(0.85, 0.14, 0.18), "stand_b": Color(0.15, 0.4, 0.75), "stand_roof": Color(0.45, 0.28, 0.18),
		"gate": Color(0.18, 0.24, 0.4), "gate_band": Color(0.85, 0.14, 0.18),
		"cloud": Color(0.98, 0.99, 1.0), "clouds": 12,
	},
}

## The current theme's name and values (KartWorld sets them per track).
static var theme := "meadow"
static var look: Dictionary = THEMES.meadow

static var _noise: ImageTexture
static var _shaders := {}
static var _lit: Array[WeakRef] = []


static func noise() -> ImageTexture:
	if _noise == null:
		_noise = MeshKit3D.noise_texture(4242)
	return _noise


static func shader(file: String) -> Shader:
	if not _shaders.has(file):
		_shaders[file] = load(SHADERS + file)
	return _shaders[file]


## Switches to `name`'s theme and re-lights every material made by `material()`.
static func set_theme(name: String) -> void:
	theme = name if THEMES.has(name) else "meadow"
	look = THEMES[theme]
	var alive: Array[WeakRef] = []
	for ref in _lit:
		var mat: ShaderMaterial = ref.get_ref()
		if mat != null:
			apply_light(mat)
			alive.append(ref)
	_lit = alive


## Towards the sun in the current theme: SUN_DIR's bearing at the theme's height.
static func sun_dir() -> Vector3:
	var flat := Vector3(SUN_DIR.x, 0.0, SUN_DIR.z).normalized()
	var h: float = look.get("sun_height", SUN_DIR.y)
	return (flat * sqrt(1.0 - h * h) + Vector3.UP * h).normalized()


## A ShaderMaterial on one of the world shaders, with the current light set (and kept current).
static func material(file: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader(file)
	apply_light(mat)
	_lit.append(weakref(mat))
	return mat


static func apply_light(mat: ShaderMaterial) -> void:
	var light: Dictionary = look.light
	mat.set_shader_parameter("sun_dir", sun_dir())
	mat.set_shader_parameter("sun_color", light.sun_color)
	mat.set_shader_parameter("sky_color", light.sky_color)
	mat.set_shader_parameter("ground_color", light.ground_color)
	mat.set_shader_parameter("haze_color", light.haze_color)
	mat.set_shader_parameter("haze_density", light.haze_density)
	mat.set_shader_parameter("noise_tex", noise())


## Sets a dictionary of uniforms (a theme's `road`, `ground` or `sky`) on `mat`.
static func apply(mat: ShaderMaterial, values: Dictionary) -> void:
	for key in values:
		mat.set_shader_parameter(key, values[key])


## The kart paint and fur material, with its outline as the next pass.
static func kart_material(outline := true) -> ShaderMaterial:
	var mat := material("kart.gdshader")
	if outline:
		var line := ShaderMaterial.new()
		line.shader = shader("outline.gdshader")
		mat.next_pass = line
	return mat
