class_name KartFx
extends Node3D
## Kart Race's effects (#43): exhaust puffs, dust off the kerbs and grass, drift sparks in three
## tiers, boost flames, hit stars, contact sparks and the draft streaks' screen point. Three
## pooled MultiMeshes drawn facing the camera (alpha-blended puffs, additive sparks and flames as
## velocity-stretched streaks with hot cores (spark.gdshader), alpha-blended stars), simulated here and written to the MultiMesh buffers: 3 draw
## calls for every effect on every kart, nothing allocated per frame.
##
## The pools simulate every SIM_EVERY frames (30 Hz: the main thread is the tablet's limit).
## Emission still runs every frame, and on the frames between, sparks born that frame are written
## straight away, so a flame never trails its exhaust; puffs are born transparent and wait.
##
## It only reads: each KartState (drift_dir/drift_tier for sparks, boost_time for flames,
## spin_time for stars, surface for dust, draft) and the race's events (`listen`): tier pings
## burst sparks, a drift boost's flames take its tier's colour, hits and shield blocks burst,
## bumps throw sparks. It pokes the views' `boost_glow` and the camera's `kick` (the views take
## their drift slide from KartState.slide themselves).

const PUFFS := 160
const SPARKS := 140
const STARS := 48
const STARS_PER_KART := 5
const BOOST_SEC := 0.9
const TIER_COLORS := KartTheme.TIER_COLORS
const FLAME := Color(1.0, 0.55, 0.15)
const FLAME_CORE := Color(1.0, 0.9, 0.5)
const STAR_SEC := 1.4  ## hit stars after a hit, if the kart isn't spinning that long
const DRAFT_RANGE := Vector2(1.5, 8.0)  ## metres behind the kart ahead (the spec's draft)
const DRAFT_LATERAL := 1.6
const SIM_EVERY := 2

var views: Array = []
var camera: KartChaseCamera
## The quality governor's trim (KartQualityGovernor): the share of PUFFS and SPARKS that may be
## alive at once. New particles past the cap are skipped; live ones run out.
var cap_share := 1.0:
	set(v):
		cap_share = clampf(v, 0.1, 1.0)
		_puff_cap = roundi(PUFFS * cap_share)
		_spark_cap = roundi(SPARKS * cap_share)
var _puff_cap := PUFFS
var _spark_cap := SPARKS

var _puff_mm: MultiMesh
var _spark_mm: MultiMesh
var _star_mm: MultiMesh
var _puff_buf := PackedFloat32Array()
var _spark_buf := PackedFloat32Array()
var _star_buf := PackedFloat32Array()
# Per particle: position, velocity, age, life, size start/end, colour.
var _pp := PackedVector3Array()
var _pv := PackedVector3Array()
var _pa := PackedFloat32Array()
var _pl := PackedFloat32Array()
var _ps := PackedVector2Array()
var _pc := PackedColorArray()
var _pn := 0
var _sp := PackedVector3Array()
var _sv := PackedVector3Array()
var _sa := PackedFloat32Array()
var _sl := PackedFloat32Array()
var _ss := PackedVector2Array()
var _sc := PackedColorArray()
var _sn := 0
var _rng := RandomNumberGenerator.new()
var _emit := PackedFloat32Array()  # per kart: exhaust timer
var _boost_t := PackedFloat32Array()  # per kart: flames left from `boost()`
var _boost_color := PackedColorArray()
var _star_t := PackedFloat32Array()  # per kart: hit stars left
var _time := 0.0
var _sim_dt := 0.0  ## time since the pools last simulated
var _frames := 0
var _sn_drawn := 0  ## sparks in the buffer (the rest were born since)
var _events: KartRaceEvents

static var _star_tex: ImageTexture


func _ready() -> void:
	_rng.seed = 77
	_puff_mm = _pool("Puffs", PUFFS, false, MeshKit3D.soft_disc(32, 0.0))
	_spark_mm = _pool("Sparks", SPARKS, true, null)
	_star_mm = _pool("Stars", STARS, false, star_texture())
	_pp.resize(PUFFS); _pv.resize(PUFFS); _pa.resize(PUFFS); _pl.resize(PUFFS); _ps.resize(PUFFS); _pc.resize(PUFFS)
	_sp.resize(SPARKS); _sv.resize(SPARKS); _sa.resize(SPARKS); _sl.resize(SPARKS); _ss.resize(SPARKS); _sc.resize(SPARKS)
	_puff_buf.resize(PUFFS * 16)
	_spark_buf.resize(SPARKS * 16)
	_star_buf.resize(STARS * 16)


## A new race: the views per kart id.
func begin(kart_views: Array) -> void:
	views = kart_views
	var n := views.size()
	# (Packed arrays are values: resize each member itself, not copies in a list.)
	_emit.resize(n)
	_boost_t.resize(n)
	_star_t.resize(n)
	_boost_color.resize(n)
	for i in n:
		_emit[i] = _rng.randf() * 0.1
		_boost_t[i] = 0.0
		_boost_color[i] = FLAME
		_star_t[i] = 0.0
	_pn = 0
	_sn = 0
	_sn_drawn = 0


## Listens to a race's events (from KartRace's race_began).
func listen(events: KartRaceEvents) -> void:
	_events = events
	events.drift_tier.connect(_on_drift_tier)
	events.boost_started.connect(_on_boost_started)
	events.kart_hit.connect(func(id: int, _by: int, _item: String): _hit(id))
	events.shield_blocked.connect(_on_shield)
	events.wall_bump.connect(func(id: int, strength: float): _bump(id, strength, Vector3.ZERO))
	events.kart_bump.connect(_on_kart_bump)


## A boost on kart `id` (an item, the start, a pad): flames, a glow and, for the rider, a camera
## kick. `color` tints the flames (a drift boost's tier).
func boost(id: int, seconds := BOOST_SEC, color := FLAME) -> void:
	if id < _boost_t.size():
		_boost_t[id] = maxf(_boost_t[id], seconds)
		_boost_color[id] = color
		if id == 0 and camera:
			camera.kick(1.0)


## A tier reached: a ring of streaks bursting flat round the kart's tail in the tier's colour
## (more and faster by tier), and a spray off each rear wheel.
func _on_drift_tier(id: int, tier: int) -> void:
	if id >= views.size() or tier <= 0:
		return
	var v: KartView = views[id]
	var c: Color = TIER_COLORS[clampi(tier - 1, 0, 2)]
	var b := v.global_transform.basis
	var centre := (v.anchor("wheel_rl").global_position + v.anchor("wheel_rr").global_position) * 0.5
	var n := 10 + 4 * tier
	for i in n:
		var a := TAU * i / n
		var out := b * Vector3(cos(a), 0.0, sin(a))
		_spark(centre + out * 0.3, out * (6.0 + 1.5 * tier) + b.y * 1.5, 0.32, Vector2(0.2, 0.06), c)
	for a in ["wheel_rl", "wheel_rr"]:
		var p := v.anchor(a).global_position
		for i in 4:
			_spark(p, _jitter(3.5) + Vector3.UP * 2.5, 0.35, Vector2(0.18, 0.04), c)


func _on_boost_started(id: int, kind: String, tier: int) -> void:
	var color := FLAME
	if kind == "drift" and tier > 0:
		color = TIER_COLORS[clampi(tier - 1, 0, 2)]
	boost(id, BOOST_SEC if kind != "drift" else 0.5 + 0.3 * tier, color)


func _hit(id: int) -> void:
	if id >= views.size():
		return
	_star_t[id] = STAR_SEC
	var p: Vector3 = (views[id] as KartView).anchor("driver_head").global_position
	for i in 14:
		_spark(p, _jitter(5.0) + Vector3.UP * 3.0, 0.45, Vector2(0.3, 0.05), Color(1.0, 0.85, 0.3))


func _on_shield(id: int) -> void:
	if id >= views.size():
		return
	var p: Vector3 = (views[id] as KartView).global_position + Vector3.UP * 0.6
	for i in 20:
		var a := TAU * i / 20.0
		_spark(p, Vector3(cos(a), 0.4, sin(a)) * 6.0, 0.4, Vector2(0.35, 0.05), Color(0.45, 0.85, 1.0))


func _on_kart_bump(a: int, b: int, strength: float) -> void:
	if a < views.size() and b < views.size():
		var pa: Vector3 = (views[a] as KartView).global_position
		var pb: Vector3 = (views[b] as KartView).global_position
		_bump(a, strength, (pa + pb) * 0.5 + Vector3.UP * 0.4)


func _bump(id: int, strength: float, at: Vector3) -> void:
	if id >= views.size():
		return
	var v: KartView = views[id]
	if at == Vector3.ZERO:
		at = v.global_position + Vector3.UP * 0.4
	for i in int(4 + 10 * clampf(strength, 0.0, 1.0)):
		_spark(at, _jitter(4.0) + Vector3.UP * 2.0, 0.25, Vector2(0.14, 0.03), Color(1.0, 0.92, 0.6))
	_puff(at, _jitter(1.0) + Vector3.UP, 0.6, Vector2(0.4, 1.2), Color(0.8, 0.78, 0.75, 0.4))


func step(race: KartRaceLogic, dt: float) -> void:
	if race == null or views.is_empty():
		return
	_time += dt
	var racing := race.phase == KartRaceLogic.Phase.RACING or race.phase == KartRaceLogic.Phase.FINISHED
	var n := mini(views.size(), race.karts.size())
	for i in n:
		_kart(i, race.karts[i], views[i], race, dt, racing)
	_sim_dt += dt
	_frames += 1
	if _frames % SIM_EVERY == 0:
		_simulate(_sim_dt)
		_sim_dt = 0.0
	else:
		_draw_new_sparks()
	_stars(race, n)


func _kart(i: int, k: KartState, v: KartView, race: KartRaceLogic, dt: float, racing: bool) -> void:
	var back := v.global_transform.basis.z
	# Exhaust: puffs from both pipes, faster with speed; a little idle smoke on the grid. None
	# (and no dust) while the camera can't see the kart (KartView.seen).
	_emit[i] -= dt
	if _emit[i] <= 0.0 and v.seen:
		_emit[i] = 0.09 if k.speed > 2.0 else 0.22
		for a in ["exhaust_l", "exhaust_r"]:
			var p := v.anchor(a).global_position
			_puff(p, back * 1.2 + Vector3.UP * 0.6 + _jitter(0.3), 0.55, Vector2(0.16, 0.55), Color(0.55, 0.55, 0.6, 0.38))
	# Dust off the road edges and the grass.
	if racing and v.seen and k.surface != KartTrackModel.Surface.ROAD and k.speed > 4.0 and _rng.randf() < dt * 30.0:
		var w := v.anchor("wheel_rl" if _rng.randf() < 0.5 else "wheel_rr").global_position
		var dusty := k.surface == KartTrackModel.Surface.OFFROAD
		_puff(w, back * 2.0 + Vector3.UP * 1.0 + _jitter(0.8), 0.9 if dusty else 0.6, Vector2(0.3, 1.4 if dusty else 0.9),
			Color(0.72, 0.62, 0.45, 0.55) if dusty else Color(0.8, 0.78, 0.76, 0.35))
	# Drifting: the physics' drift (the view takes its slide from KartState.slide).
	if racing and k.drift_dir != 0:
		_drift_sparks(v, back, float(k.drift_dir), k.drift_tier, dt)
	# Boost flames: from `boost()` (events) or any boost the physics runs.
	if _boost_t[i] > 0.0:
		_boost_t[i] -= dt
	var flames := _boost_t[i] > 0.0 or k.boost_time > 0.0
	if flames:
		var col := _boost_color[i] if _boost_t[i] > 0.0 else FLAME
		for a in ["exhaust_l", "exhaust_r"]:
			var p := v.anchor(a).global_position
			_spark(p, back * 4.0 + _jitter(0.6), 0.18, Vector2(0.55, 0.15), col)
			_spark(p, back * 3.0 + _jitter(0.4), 0.12, Vector2(0.32, 0.08), FLAME_CORE)
	v.boost_glow = clampf(maxf(_boost_t[i] / BOOST_SEC, minf(k.boost_time, 1.0)), 0.0, 1.0)
	if _star_t[i] > 0.0:
		_star_t[i] -= dt


## A flickering glow at both rear wheels in the tier's colour, sparks spraying back, and a
## little tyre smoke off the outside wheel.
func _drift_sparks(v: KartView, back: Vector3, dir: float, tier: int, dt: float) -> void:
	var outer := "wheel_rr" if dir > 0.0 else "wheel_rl"
	var inner := "wheel_rl" if dir > 0.0 else "wheel_rr"
	if tier > 0:
		var c: Color = TIER_COLORS[clampi(tier - 1, 0, 2)]
		var rate := 50.0 + 30.0 * tier
		# Both rear wheels, every frame of a drift: two passes over `side`, no [outer, inner] arrays.
		for side in 2:
			var a := outer if side == 0 else inner
			var w := v.anchor(a).global_position - Vector3.UP * 0.18
			_spark(w, Vector3.ZERO, 0.05, Vector2(0.42 + 0.12 * tier + 0.2 * _rng.randf(), 0.4), Color(c.r, c.g, c.b, 0.9))
		for side in 2:
			var a := outer if side == 0 else inner
			if _rng.randf() < dt * rate:
				var p := v.anchor(a).global_position - Vector3.UP * 0.22
				_spark(p, back * 3.0 + Vector3.UP * _rng.randf_range(1.0, 3.0) + _jitter(2.0), 0.3, Vector2(0.16, 0.04), c)
				_spark(p, back * 2.0 + Vector3.UP * _rng.randf_range(0.5, 2.0) + _jitter(1.5), 0.18, Vector2(0.09, 0.03), Color(1, 1, 0.9))
	if _rng.randf() < dt * 14.0:
		_puff(v.anchor(outer).global_position, back * 1.5 + Vector3.UP * 0.8 + _jitter(0.5), 0.7, Vector2(0.3, 1.0), Color(0.85, 0.85, 0.88, 0.35))


## Hit stars: five little stars circling each stunned driver's head.
func _stars(race: KartRaceLogic, n: int) -> void:
	var count := 0
	for i in n:
		var k: KartState = race.karts[i]
		var left := maxf(_star_t[i], k.spin_time)
		if left <= 0.0 or count + STARS_PER_KART > STARS:
			continue
		var head: Vector3 = (views[i] as KartView).anchor("driver_head").global_position + Vector3.UP * 0.55
		var fade := clampf(left / 0.3, 0.0, 1.0)
		for j in STARS_PER_KART:
			var a := _time * 5.0 + TAU * j / STARS_PER_KART
			var p := head + Vector3(cos(a) * 0.55, 0.08 * sin(a * 2.0), sin(a) * 0.55)
			var s := 0.32 * (0.85 + 0.15 * sin(_time * 12.0 + j)) * fade
			_write(_star_buf, count, p, s, Color(1.0, 0.88, 0.25, fade))
			count += 1
	_star_mm.visible_instance_count = count
	if count > 0:
		_star_mm.buffer = _star_buf


## Where the rider is drafting toward, for the HUD's streaks: sets `hud.draft_point` to the kart
## ahead's screen position and returns the draft amount (0 when not drafting).
func draft_screen(race: KartRaceLogic, cam: Camera3D, hud: KartHud) -> float:
	if race == null or cam == null:
		return 0.0
	var k: KartState = race.karts[KartRaceLogic.RIDER]
	if k.draft <= 0.01:
		return 0.0
	var best := -1
	var best_gap := INF
	for i in range(1, race.karts.size()):
		var o: KartState = race.karts[i]
		var gap := race.track.delta(k.s, o.s)
		if gap > DRAFT_RANGE.x * 0.5 and gap < DRAFT_RANGE.y + 2.0 and absf(o.d - k.d) < DRAFT_LATERAL * 1.5 and gap < best_gap:
			best_gap = gap
			best = i
	if best < 0:
		return k.draft
	# Where it's drawn (between logic ticks), not where the logic has it.
	var target: Vector3 = (views[best] as Node3D).global_position + Vector3.UP * 0.6 if best < views.size() \
		else race.karts[best].pos + Vector3.UP * 0.6
	if cam.is_position_behind(target):
		return k.draft
	var vp := cam.get_viewport()
	var p := cam.unproject_position(target)
	hud.draft_point = Stage.from_view(p, vp.get_visible_rect().size.max(Vector2.ONE)) if vp else p
	return k.draft


func _jitter(r: float) -> Vector3:
	return Vector3(_rng.randf_range(-r, r), _rng.randf_range(-r, r) * 0.5, _rng.randf_range(-r, r))


func _puff(p: Vector3, vel: Vector3, life: float, size: Vector2, c: Color) -> void:
	if _pn >= _puff_cap:
		return
	_pp[_pn] = p; _pv[_pn] = vel; _pa[_pn] = 0.0; _pl[_pn] = life; _ps[_pn] = size; _pc[_pn] = c
	_pn += 1


func _spark(p: Vector3, vel: Vector3, life: float, size: Vector2, c: Color) -> void:
	if _sn >= _spark_cap:
		return
	_sp[_sn] = p; _sv[_sn] = vel; _sa[_sn] = 0.0; _sl[_sn] = life; _ss[_sn] = size; _sc[_sn] = c
	_sn += 1


func _simulate(dt: float) -> void:
	var i := 0
	while i < _pn:
		_pa[i] += dt
		if _pa[i] >= _pl[i]:
			_pn -= 1
			_pp[i] = _pp[_pn]; _pv[i] = _pv[_pn]; _pa[i] = _pa[_pn]; _pl[i] = _pl[_pn]; _ps[i] = _ps[_pn]; _pc[i] = _pc[_pn]
			continue
		_pv[i] *= 1.0 - 2.5 * dt
		_pv[i].y += 0.6 * dt
		_pp[i] += _pv[i] * dt
		var t := _pa[i] / _pl[i]
		var s := lerpf(_ps[i].x, _ps[i].y, sqrt(t))
		var c := _pc[i]
		_write(_puff_buf, i, _pp[i], s, Color(c.r, c.g, c.b, c.a * (1.0 - t) * minf(1.0, t * 8.0)))
		i += 1
	i = 0
	while i < _sn:
		_sa[i] += dt
		if _sa[i] >= _sl[i]:
			_sn -= 1
			_sp[i] = _sp[_sn]; _sv[i] = _sv[_sn]; _sa[i] = _sa[_sn]; _sl[i] = _sl[_sn]; _ss[i] = _ss[_sn]; _sc[i] = _sc[_sn]
			continue
		_sv[i].y -= 9.0 * dt
		_sp[i] += _sv[i] * dt
		var t := _sa[i] / _sl[i]
		var c := _sc[i]
		_write_streak(_spark_buf, i, _sp[i], _sv[i], lerpf(_ss[i].x, _ss[i].y, t), Color(c.r, c.g, c.b, 1.0 - t * t))
		i += 1
	_puff_mm.visible_instance_count = _pn
	_spark_mm.visible_instance_count = _sn
	_sn_drawn = _sn
	if _pn > 0:
		_puff_mm.buffer = _puff_buf
	if _sn > 0:
		_spark_mm.buffer = _spark_buf


## Between simulations: the sparks born this frame, at birth, after the ones already drawn.
func _draw_new_sparks() -> void:
	if _sn <= _sn_drawn:
		return
	for i in range(_sn_drawn, _sn):
		var c := _sc[i]
		_write_streak(_spark_buf, i, _sp[i], _sv[i], _ss[i].x, Color(c.r, c.g, c.b, 1.0))
	_sn_drawn = _sn
	_spark_mm.visible_instance_count = _sn
	_spark_mm.buffer = _spark_buf


## One instance in a TRANSFORM_3D + colour buffer: a uniform scale at p, then RGBA.
static func _write(buf: PackedFloat32Array, i: int, p: Vector3, s: float, c: Color) -> void:
	var o := i * 16
	buf[o] = s; buf[o + 1] = 0.0; buf[o + 2] = 0.0; buf[o + 3] = p.x
	buf[o + 4] = 0.0; buf[o + 5] = s; buf[o + 6] = 0.0; buf[o + 7] = p.y
	buf[o + 8] = 0.0; buf[o + 9] = 0.0; buf[o + 10] = s; buf[o + 11] = p.z
	buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a


## One spark: as `_write`, but the velocity goes in the basis's first column (where a uniform
## scale has its zeros, so it's the same writes) for spark.gdshader's streaks.
static func _write_streak(buf: PackedFloat32Array, i: int, p: Vector3, v: Vector3, s: float, c: Color) -> void:
	var o := i * 16
	buf[o] = v.x; buf[o + 1] = 0.0; buf[o + 2] = 0.0; buf[o + 3] = p.x
	buf[o + 4] = v.y; buf[o + 5] = s; buf[o + 6] = 0.0; buf[o + 7] = p.y
	buf[o + 8] = v.z; buf[o + 9] = 0.0; buf[o + 10] = s; buf[o + 11] = p.z
	buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a


## A five-pointed star sprite with a dark rim (white fill, tinted per instance). Made once.
static func star_texture(size := 64) -> ImageTexture:
	if _star_tex:
		return _star_tex
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var outer := size * 0.47
	var inner := outer * 0.45
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * i / 10.0
		pts.append(c + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var inside := Geometry2D.is_point_in_polygon(p, pts)
			var edge := INF
			for i in 10:
				var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % 10])
				edge = minf(edge, p.distance_to(q))
			var a := 0.0
			var col := Color.WHITE
			if inside:
				a = 1.0
				if edge < size * 0.06:
					col = Color(0.35, 0.2, 0.05)
			elif edge < 1.0:
				a = 1.0 - edge
				col = Color(0.35, 0.2, 0.05)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	img.generate_mipmaps()
	_star_tex = ImageTexture.create_from_image(img)
	return _star_tex


func _pool(node_name: String, count: int, additive: bool, texture: Texture2D) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	if additive:
		# The sparks: velocity-stretched streaks (spark.gdshader), no texture.
		var streaks := ShaderMaterial.new()
		streaks.shader = KartLook.shader("spark.gdshader")
		quad.material = streaks
	else:
		quad.material = _sprite_material(texture)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = count
	mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Particles go anywhere on the track: never cull the pool by its (empty) bounds.
	node.custom_aabb = AABB(Vector3(-2000, -200, -2000), Vector3(4000, 400, 4000))
	add_child(node)
	return mm


## The puffs' and stars' material: camera-facing alpha sprites tinted per instance.
static func _sprite_material(texture: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = texture
	mat.disable_fog = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat
