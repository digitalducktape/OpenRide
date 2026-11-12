class_name TugWorld
extends Node3D
## Tug of War's 3D view (#40), first person: the rider stands at the end of a wooden pier, the
## rope runs out over a river to a wind-up tin robot on the far pier, and a flag on the rope shows
## who is winning. Win and the bot is hauled off its pier into the water; lose and the camera is
## pulled in. The look is in ART_BIBLE.md (this folder).
##
## It only draws: `TugLogic` holds the rules, and `update_view` is told the rope marker and the
## bot's state each frame. The tablet recipe (docs/GAMES.md, "World look (3D)"): every surface is
## unshaded and lit by hand on the shared look (`WorldLook`, shaders/tug_look.gdshaderinc), the
## statics are baked into one vertex-coloured mesh (`TugMeshes`), and the crowd, torches, flag,
## bunting, reeds, steam and the bot's key move in their shaders. Per frame, GDScript only lays
## out the rope's 22 segments and poses the bot. The trees are the CC0 Kenney nature-kit models
## Dodge Ball ships, baked into the scenery.

const EYE_HEIGHT := 1.6
const CAMERA_PITCH := -9.0
const FOV := 66.0
const DECK_TOP := 0.4  ## the piers' top, above the water at y = 0
const BANK_TOP := DECK_TOP - 0.05  ## the banks' grass
const NEAR_EDGE_Z := -2.6  ## the near pier's end
const FAR_EDGE_Z := -11.0  ## the far pier's end
const NEAR_BANK_Z := -1.4  ## the near bank's top edge (the pier juts out past it)
const FAR_BANK_Z := -12.2  ## the far bank's top edge
const BOT_HOME_Z := -13.6
const ROPE_SEGMENTS := 22
const CROWD_FAR := 44
const CROWD_NEAR := 16
const FALL_SEC := 1.3
## The rider's fists, in the camera's space: low and ahead, so both show above the screen's foot.
const HANDS_POS := Vector3(0.0, -0.3, -0.95)
## Where the rope meets the bot's mittens, from its feet.
const BOT_GRIP := Vector3(0.0, 1.3, 0.97)
## The wind-up key's speed (radians a second) per bot state: a lazy turn, fast on a telegraph.
const KEY_SPEED := {"": 1.6, "telegraph": 14.0, "surge": 7.0}
## How many frames `prewarm` keeps the hidden effects drawn (the render thread may lag a frame).
const WARM_FRAMES := 3

## The bots: a material and an animal, so each rung's opponent gets a new name and colour.
## Plain words only: none of this is anyone's character.
const MATERIALS := ["Rust", "Copper", "Tin", "Brass", "Iron", "Steel", "Zinc", "Chrome"]
const ANIMALS := ["Mule", "Ox", "Badger", "Heron", "Otter", "Moose", "Walrus", "Yak"]
const BOT_COLORS := [Color(0.68, 0.32, 0.16), Color(0.82, 0.48, 0.25), Color(0.62, 0.68, 0.72),
	Color(0.85, 0.7, 0.28), Color(0.38, 0.42, 0.5), Color(0.52, 0.6, 0.68), Color(0.5, 0.58, 0.55),
	Color(0.78, 0.82, 0.88)]
const CROWD_COLORS := [Color(0.9, 0.35, 0.3), Color(0.95, 0.75, 0.25), Color(0.3, 0.6, 0.9),
	Color(0.4, 0.75, 0.4), Color(0.85, 0.5, 0.8), Color(0.95, 0.95, 0.9), Color(0.95, 0.55, 0.2)]

const SHADERS := "res://games/tug_of_war/shaders/"

var camera: Camera3D
var excitement := 0.0  ## 0-1, how much the crowd is cheering
var flag_t := 0.5  ## where the flag is along the rope, 0 at the rider, 1 at the bot

var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _noise: ImageTexture
## Every hand-lit material, for `WorldLook.apply` in `set_time_of_day`.
var _lit: Array[ShaderMaterial] = []
var _water_mat: ShaderMaterial
var _scenery_mat: ShaderMaterial
var _deck_mat: ShaderMaterial
var _crowd_mat: ShaderMaterial
var _flame_mat: ShaderMaterial
var _bot_mat: ShaderMaterial
var _eye_mat: ShaderMaterial
var _steam_mat: ShaderMaterial
var _foam_mat: ShaderMaterial
var _rig: Node3D
var _hands: Node3D
var _rope_mm: MultiMesh
var _flag: Node3D
var _bot: Node3D
var _ears: MeshInstance3D
var _horns: MeshInstance3D
var _steam: MultiMeshInstance3D
var _splash: CPUParticles3D
var _ring: MeshInstance3D
var _bot_color: Color = BOT_COLORS[0]
var _fall := 0.0  ## 0-1 through a fall into the water
var _faller := 0  ## +1: the bot falls, -1: the rider falls, 0: nobody
var _t := 0.0
var _pull_phase := 0.0
var _shake := 0.0
var _key_angle := 0.0
var _excite_shown := -1.0
var _bot_name := ""
var _warming := false  ## prewarm is drawing the hidden effects
var _splashing := false  ## a splash's ripple is showing
var _steam_shown := false  ## the steam as update_view wants it


func _ready() -> void:
	_noise = WorldLook.noise_texture()
	_build_environment()
	_build_river_and_banks()
	_build_piers()
	_build_crowd()
	_build_rope()
	_build_bot()
	_build_rig()
	_build_fx()
	set_bot(0)


## The rider's view of the rope: `p` is the marker (-1 to +1), `tension` 0.5-1 how taut the
## rope is, `surge` the bot's state ("", "telegraph" or "surge"), `cadence` in rpm.
func update_view(delta: float, p: float, tension: float, surge: String, cadence: float) -> void:
	_t += delta
	if _faller != 0:
		_fall = minf(_fall + delta / FALL_SEC, 1.0)
	_pull_phase += delta * cadence / 60.0 * TAU
	_shake = move_toward(_shake, 0.012 if surge == "surge" else 0.0, delta * 0.05)
	var bot_pull := clampf(p, 0.0, 1.0)
	var rider_pull := clampf(-p, 0.0, 1.0)
	# The bot is hauled toward the near pier, the camera toward the far one.
	var bot_pos := Vector3(0.0, DECK_TOP, BOT_HOME_Z + bot_pull * 3.8)
	bot_pos.y -= smoothstep(0.88, 1.0, bot_pull) * 0.35
	if _faller > 0:
		bot_pos.y -= ease(_fall, 2.0) * 2.6
		bot_pos.z += _fall * 0.8
	var cam_pos := Vector3(0.0, EYE_HEIGHT, -rider_pull * 3.2)
	cam_pos.y -= smoothstep(0.88, 1.0, rider_pull) * 0.25
	if _faller < 0:
		cam_pos.y -= ease(_fall, 2.0) * 1.35
		cam_pos.z -= _fall * 0.9
	var jitter := Vector3(sin(_t * 61.0), cos(_t * 53.0), 0.0) * _shake
	_rig.position = cam_pos + jitter
	camera.rotation_degrees.x = CAMERA_PITCH + (_fall * 8.0 if _faller < 0 else 0.0)
	var fists := HANDS_POS + Vector3(0.0, sin(_pull_phase) * 0.018, 0.0)
	_hands.position = fists
	# The bot braces on a telegraphed surge and leans into it; its key winds faster, its eyes
	# flash amber then burn red, and its chimney puffs.
	var lean := 0.0
	var eyes := Color(0.3, 0.9, 1.0)
	var glow := 1.5
	var steam := 0.0
	match surge:
		"telegraph":
			lean = -10.0
			eyes = Color(1.0, 0.7, 0.2)
			glow = 2.5 + 2.0 * absf(sin(_t * 18.0))
			steam = 0.5
		"surge":
			lean = -16.0
			eyes = Color(1.0, 0.2, 0.15)
			glow = 3.5
			steam = 1.0
	if _faller > 0:
		steam = 0.0
	_bot.position = bot_pos
	_bot.rotation_degrees.x = lerpf(_bot.rotation_degrees.x, lean + bot_pull * 8.0, minf(delta * 8.0, 1.0))
	_key_angle = fmod(_key_angle + delta * float(KEY_SPEED.get(surge, 1.6)), TAU)
	_bot_mat.set_shader_parameter("key_angle", _key_angle)
	_eye_mat.set_shader_parameter("eye_color", eyes)
	_eye_mat.set_shader_parameter("glow", glow)
	_steam_shown = steam > 0.0
	_steam.visible = _steam_shown or _warming
	_steam_mat.set_shader_parameter("steam", steam)
	# The bot's blob shadow on its deck, gone once it is over the water.
	var on_deck := 1.0 - smoothstep(FAR_EDGE_Z - 0.6, FAR_EDGE_Z + 0.2, bot_pos.z)
	_deck_mat.set_shader_parameter("shadow", Vector4(bot_pos.x, bot_pos.z, 0.85, 0.45 * on_deck * (1.0 - _fall * float(_faller > 0))))
	_update_rope(cam_pos + camera.basis * fists, bot_pos + BOT_GRIP, tension, p)
	if absf(excitement - _excite_shown) > 0.02:
		_excite_shown = excitement
		_crowd_mat.set_shader_parameter("excite", excitement)


## A new bot for this ladder rung (or round): its name and colour, returned as the name.
func set_bot(rung: int) -> String:
	var m := rung % MATERIALS.size()
	var a := (rung * 3 + rung / MATERIALS.size()) % ANIMALS.size()
	_bot_color = BOT_COLORS[m]
	_bot_mat.set_shader_parameter("body_color", _bot_color)
	_ears.visible = rung % 2 == 0
	_horns.visible = rung % 2 == 1
	_bot_name = "%s %s" % [MATERIALS[m], ANIMALS[a]]
	return _bot_name


func bot_name() -> String:
	return _bot_name


## The current bot's body colour (the status widget's BOT colour).
func bot_color() -> Color:
	return _bot_color


## Whether the current bot wears horns (odd rungs) rather than ears.
func bot_has_horns() -> bool:
	return _horns.visible


## A round has ended: the loser falls into the river. The splash lands a moment later, at the
## far pier's end for the bot and just ahead of the camera for the rider.
func fall(bot_falls: bool) -> void:
	_faller = 1 if bot_falls else -1
	_fall = 0.0
	var splash_at_z := FAR_EDGE_Z + 1.4 if bot_falls else _rig.position.z - 3.2
	var timer := get_tree().create_timer(FALL_SEC * 0.55)
	timer.timeout.connect(func(): splash_at(Vector3(0.0, 0.05, splash_at_z)))


## A new round: the rope returns to the middle.
func reset_round() -> void:
	_faller = 0
	_fall = 0.0


func splash_at(pos: Vector3) -> void:
	_splash.position = pos
	_splash.restart()
	_splash.emitting = true
	_ring.position = pos + Vector3(0.0, 0.03, 0.0)
	_ring.visible = true
	_splashing = true
	_foam_mat.set_shader_parameter("progress", 0.0)
	var tween := create_tween()
	tween.tween_property(_foam_mat, "shader_parameter/progress", 1.0, 1.6)
	tween.tween_callback(func():
		_splashing = false
		_ring.visible = false)
	_shake = 0.03


## Draws every effect that starts hidden once, behind the intro card, so its shader compiles
## then and not on the first telegraph or splash: the Compatibility renderer compiles a material
## the first time it draws it, a stall of a tenth of a second or more on the tablet. The steam and
## the ripple draw fully transparent for a few frames; the droplets burst under the water, where
## the river hides them.
func prewarm() -> void:
	_warming = true
	_steam.visible = true
	_steam_mat.set_shader_parameter("steam", 0.0)
	_ring.position = Vector3(0.0, 0.03, FAR_EDGE_Z + 1.4)
	_ring.visible = true
	_foam_mat.set_shader_parameter("progress", 1.0)
	_splash.position = Vector3(0.0, -3.0, -6.0)
	_splash.restart()
	_splash.emitting = true
	for i in WARM_FRAMES:
		await get_tree().process_frame
	_warming = false
	_splash.emitting = false
	if not _splashing:
		_ring.visible = false
	_steam.visible = _steam_shown


## The world's light for a time-of-day preset: `WorldLook`'s uniforms (sun, hemisphere ambient,
## haze), plus Tug's own keys (`sky_top`, `sky_horizon`, `lamp`: how much the torches, bulbs and
## the bot's torch light glow).
static func look_for(tod: TimeOfDay) -> Dictionary:
	var sky := tod.ambient * tod.ambient_energy
	var ground := Color(sky.r * 0.55 + 0.03, sky.g * 0.5 + 0.02, sky.b * 0.42)
	return {
		&"sun_dir": WorldLook.sun_dir(tod.sun_elevation, tod.sun_azimuth),
		&"sun_color": tod.sun_color * tod.sun_energy,
		&"sky_color": sky,
		&"ground_color": ground,
		&"haze_color": tod.fog_color,
		&"haze_density": tod.fog_density,
		&"haze_max": 0.85,
		&"sky_top": tod.sky_top,
		&"sky_horizon": tod.sky_horizon,
		&"lamp": clampf(tod.lamp_glow + (1.0 - tod.sun_energy * 0.7) * 0.5, 0.0, 1.0),
		&"sparkle": 0.55 if tod.sun_elevation > 25.0 else 0.8,
	}


func set_time_of_day(tod: TimeOfDay) -> void:
	_sky_mat.set_shader_parameter("top_color", tod.sky_top)
	_sky_mat.set_shader_parameter("horizon_color", tod.sky_horizon)
	_sky_mat.set_shader_parameter("below_color", tod.sky_ground)
	_sky_mat.set_shader_parameter("disc_color", tod.sun_color)
	_sky_mat.set_shader_parameter("sun_size", tod.sun_size)
	_sky_mat.set_shader_parameter("halo", tod.halo)
	_sky_mat.set_shader_parameter("stars", tod.stars)
	_sky_mat.set_shader_parameter("clouds", tod.clouds)
	_sky_mat.set_shader_parameter("cloud_color", tod.cloud_color)
	var look := look_for(tod)
	var to_sun: Vector3 = look.sun_dir
	_sun.basis = Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
	_sun.light_color = tod.sun_color
	_sun.light_energy = tod.sun_energy
	WorldLook.apply(_lit, look)
	_water_mat.set_shader_parameter("sky_top", tod.sky_top)
	_water_mat.set_shader_parameter("sky_horizon", tod.sky_horizon)
	_water_mat.set_shader_parameter("sparkle", look.sparkle)
	_scenery_mat.set_shader_parameter("lamp", look.lamp)
	_flame_mat.set_shader_parameter("lamp", look.lamp)
	_deck_mat.set_shader_parameter("lamp", look.lamp)
	_bot_mat.set_shader_parameter("torch_fill", look.lamp)


# --- Building ---

func _material(shader_file: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS + shader_file)
	m.set_shader_parameter("noise_tex", _noise)
	_lit.append(m)
	return m


func _instance(mesh: Mesh, mat: Material, node_name: String, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build_environment() -> void:
	_env = WorldEnvironment.new()
	var env := Environment.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load(SHADERS + "sky.gdshader")
	_sky_mat.set_shader_parameter("noise_tex", _noise)
	_sky_mat.set_shader_parameter("star_tex", WorldLook.noise_texture())
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	# The sky is drawn once into its radiance cubemap (when the time of day changes) and the
	# background samples it (sky.gdshader). 256 a face keeps the disc, clouds and stars sharp at
	# the view's 0.1° a pixel. The cubemap is only kept up to date while the sky is a reflection
	# source; no material reads it (they're all unshaded).
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Everything lights itself (unshaded): no engine ambient, reflections or fog to pay for.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.environment = env
	add_child(_env)
	# The sun only places the sky's disc (LIGHT0_DIRECTION); it lights nothing.
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = false
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
	add_child(_sun)


func _build_river_and_banks() -> void:
	_water_mat = _material("water.gdshader")
	_water_mat.set_shader_parameter("waterlines", TugMeshes.waterlines())
	_water_mat.set_shader_parameter("pier_ends", Vector2(NEAR_EDGE_Z, FAR_EDGE_Z))
	var water := PlaneMesh.new()
	water.size = Vector2(160.0, 60.0)
	# 5 m cells, for the haze worked out per vertex (water.gdshader).
	water.subdivide_width = 31
	water.subdivide_depth = 11
	var wi := _instance(water, _water_mat, "Water")
	wi.position = Vector3(0.0, 0.0, -8.6)
	# The riverside: banks, hills, trees, pier frames, masts, bunting, lights, reeds, the tent.
	var models := {
		"trees": [TugMeshes.model(MeshKit3D.model_mesh("tree_default.glb"), Color(0.32, 0.56, 0.2), Color(0.42, 0.29, 0.19)),
			TugMeshes.model(MeshKit3D.model_mesh("tree_oak.glb"), Color(0.26, 0.48, 0.17), Color(0.42, 0.29, 0.19)),
			TugMeshes.model(MeshKit3D.model_mesh("tree_pineTallA.glb"), Color(0.16, 0.36, 0.2), Color(0.42, 0.29, 0.19)),
			TugMeshes.model(MeshKit3D.model_mesh("tree_cone.glb"), Color(0.38, 0.6, 0.22), Color(0.42, 0.29, 0.19))],
		"bush": TugMeshes.model(MeshKit3D.model_mesh("plant_bushLarge.glb"), Color(0.3, 0.52, 0.2), Color(0.3, 0.52, 0.2)),
		"rock": TugMeshes.model(MeshKit3D.model_mesh("rock_largeA.glb"), Color(0.42, 0.41, 0.39), Color(0.5, 0.5, 0.47)),
	}
	_scenery_mat = _material("scenery.gdshader")
	var scenery := _instance(TugMeshes.scenery(models), _scenery_mat, "Scenery")
	scenery.extra_cull_margin = 4.0
	# Lily pads drifting downstream, wide of the rope's line.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3307
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true  # Compatibility zeroes COLOR in a MultiMesh without instance colours
	mm.mesh = TugMeshes.lily_pad(true)
	mm.instance_count = 14
	var lines := TugMeshes.waterlines()
	for i in mm.instance_count:
		var near := i % 2 == 0
		var z := lines.x - rng.randf_range(0.5, 1.6) if near else lines.y + rng.randf_range(0.5, 2.2)
		var s := rng.randf_range(0.28, 0.5)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(0.0, 0.015, z)))
		mm.set_instance_color(i, Color.WHITE)
		mm.set_instance_custom_data(i, Color(float(i) / mm.instance_count + rng.randf() * 0.05, rng.randf(), rng.randf(), 0.0))
	var lilies := MultiMeshInstance3D.new()
	lilies.name = "Lilies"
	lilies.multimesh = mm
	lilies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lilies.material_override = _material("lily.gdshader")
	lilies.extra_cull_margin = 40.0
	add_child(lilies)


func _build_piers() -> void:
	_deck_mat = _material("deck.gdshader")
	_deck_mat.set_shader_parameter("near_end", NEAR_EDGE_Z)
	_deck_mat.set_shader_parameter("far_end", FAR_EDGE_Z)
	_instance(TugMeshes.decks(), _deck_mat, "Decks")
	# The torch flames: one additive card each, flickering in the shader.
	_flame_mat = _material("flame.gdshader")
	_instance(TugMeshes.flames(), _flame_mat, "Flames")


func _build_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 515
	var count := CROWD_FAR + CROWD_NEAR
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = TugMeshes.crowd_fan()
	mm.instance_count = count
	for i in count:
		var near := i >= CROWD_FAR
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos: Vector3
		if near:
			pos = Vector3(side * rng.randf_range(3.2, 8.0), BANK_TOP, rng.randf_range(NEAR_BANK_Z + 0.3, NEAR_BANK_Z + 2.6))
		else:
			pos = Vector3(side * rng.randf_range(4.0, 14.0), BANK_TOP, rng.randf_range(FAR_BANK_Z - 5.0, FAR_BANK_Z - 0.5))
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(i, TugMeshes.lin(CROWD_COLORS[rng.randi() % CROWD_COLORS.size()] * 0.92))
		mm.set_instance_custom_data(i, Color(rng.randf_range(1.6, 1.9), rng.randf(), rng.randf(), rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Crowd"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crowd_mat = _material("crowd.gdshader")
	_crowd_mat.set_shader_parameter("sprite", TugMeshes.crowd_sprite())
	_crowd_mat.set_shader_parameter("ground_tint", TugMeshes.GRASS)
	mmi.material_override = _crowd_mat
	mmi.extra_cull_margin = 3.0
	add_child(mmi)


func _build_rope() -> void:
	var seg := CylinderMesh.new()
	seg.top_radius = 0.035
	seg.bottom_radius = 0.035
	seg.height = 1.0
	seg.radial_segments = 6
	seg.rings = 1
	seg.cap_top = false
	seg.cap_bottom = false
	_rope_mm = MultiMesh.new()
	_rope_mm.transform_format = MultiMesh.TRANSFORM_3D
	_rope_mm.mesh = seg
	_rope_mm.instance_count = ROPE_SEGMENTS
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rope"
	mmi.multimesh = _rope_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.material_override = _material("rope.gdshader")
	mmi.extra_cull_margin = 40.0
	add_child(mmi)
	# The flag: a pole and a swallowtail pennant flying broadside, its cloth fluttering in the
	# shader. Self-lit, so the one red on screen reads at night.
	_flag = Node3D.new()
	_flag.name = "Flag"
	var flag_mat := _material("scenery.gdshader")
	flag_mat.set_shader_parameter("sway", 0.0)
	flag_mat.set_shader_parameter("wave", 0.06)
	flag_mat.set_shader_parameter("self_lit", 0.55)
	var pennant := _instance(TugMeshes.flag(), flag_mat, "Pennant", _flag)
	pennant.rotation_degrees = Vector3(0.0, 25.0, -22.0)
	add_child(_flag)


func _update_rope(from: Vector3, to: Vector3, tension: float, p: float) -> void:
	var sag := 0.55 * (1.0 - clampf(tension, 0.0, 1.0)) + 0.06
	var prev := from
	for i in ROPE_SEGMENTS:
		var t := float(i + 1) / ROPE_SEGMENTS
		var point := from.lerp(to, t)
		point.y -= sag * 4.0 * t * (1.0 - t)
		var d := point - prev
		var len := d.length()
		var q := Quaternion(Vector3.UP, d / len)
		_rope_mm.set_instance_transform(i, Transform3D(Basis(q).scaled_local(Vector3(1.0, len * 1.08, 1.0)), (prev + point) * 0.5))
		prev = point
	flag_t = 0.5 + 0.42 * p
	var fp := from.lerp(to, flag_t)
	fp.y -= sag * 4.0 * flag_t * (1.0 - flag_t)
	_flag.position = fp


func _build_bot() -> void:
	_bot = Node3D.new()
	_bot.name = "Bot"
	add_child(_bot)
	_bot_mat = _material("bot.gdshader")
	_bot_mat.set_shader_parameter("key_pivot", TugMeshes.BOT_KEY_PIVOT)
	_instance(TugMeshes.bot_body(), _bot_mat, "Body", _bot)
	_ears = _instance(TugMeshes.bot_ears(), _bot_mat, "Ears", _bot)
	_horns = _instance(TugMeshes.bot_horns(), _bot_mat, "Horns", _bot)
	_eye_mat = ShaderMaterial.new()
	_eye_mat.shader = load(SHADERS + "eyes.gdshader")
	_instance(TugMeshes.bot_eyes(), _eye_mat, "Eyes", _bot)
	# Steam from the chimney: a tiny pooled MultiMesh of puffs, shown only in a telegraph or surge.
	var puff := QuadMesh.new()
	puff.size = Vector2(2.0, 2.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = puff
	mm.instance_count = 4
	for i in 4:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
	_steam = MultiMeshInstance3D.new()
	_steam.name = "Steam"
	_steam.multimesh = mm
	_steam.position = TugMeshes.BOT_CHIMNEY_TOP
	_steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_steam_mat = _material("steam.gdshader")
	_steam.material_override = _steam_mat
	_steam.extra_cull_margin = 2.0
	_steam.visible = false
	_bot.add_child(_steam)
	_bot.position = Vector3(0.0, DECK_TOP, BOT_HOME_Z)


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 260.0
	camera.rotation_degrees = Vector3(CAMERA_PITCH, 0.0, 0.0)
	_rig.add_child(camera)
	_rig.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	add_child(_rig)
	# The rider's gloves on the rope, in the camera's space, lit by their own key light.
	_hands = Node3D.new()
	_hands.name = "Hands"
	camera.add_child(_hands)
	var gloves := _instance(TugMeshes.gloves(), _material("hands.gdshader"), "Gloves", _hands)
	gloves.scale = Vector3.ONE * 1.3


func _build_fx() -> void:
	# Droplets as short streaks along their velocity.
	var drop := CapsuleMesh.new()
	drop.radius = 0.028
	drop.height = 0.26
	drop.radial_segments = 4
	drop.rings = 1
	_splash = CPUParticles3D.new()
	_splash.mesh = drop
	# Unshaded and bright: a lit drop reads as a dark blob against the water at night.
	var drop_mat := StandardMaterial3D.new()
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mat.albedo_color = Color(0.85, 0.95, 1.0)
	drop_mat.disable_fog = true
	_splash.material_override = drop_mat
	_splash.amount = 48
	_splash.lifetime = 1.3
	_splash.one_shot = true
	_splash.emitting = false
	_splash.explosiveness = 0.95
	_splash.direction = Vector3.UP
	_splash.spread = 38.0
	_splash.initial_velocity_min = 3.0
	_splash.initial_velocity_max = 6.5
	_splash.gravity = Vector3(0.0, -9.8, 0.0)
	_splash.particle_flag_align_y = true
	_splash.scale_amount_min = 0.6
	_splash.scale_amount_max = 1.2
	_splash.local_coords = false
	add_child(_splash)
	# The foam: a ripple ring over a fading disc, a flat quad on the water.
	var disc := PlaneMesh.new()
	disc.size = Vector2(9.0, 9.0)
	_foam_mat = _material("foam.gdshader")
	_ring = _instance(disc, _foam_mat, "Ripple")
	_ring.visible = false
