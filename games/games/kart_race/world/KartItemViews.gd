class_name KartItemViews
extends Node3D
## Kart Race's item views (#43, spec "Items"): everything `KartItemLogic` simulates, drawn.
##
## - **Pods:** floating, slowly turning glass capsules with a glowing gem core that cycles
##   through the hues, a soft light pool on the road under each, popping back in when they
##   respawn. Three MultiMeshes for every pod on the track.
## - **Bumper Puck:** a chunky toy puck with a glowing amber bumper ring, spinning, with a
##   ribbon trail.
## - **Seeker Drone:** a little quad-rotor with blurred rotors, blinking red/green navigation
##   lights and a cyan trail; a red lock-on ring pulses on the road under its target.
## - **Goo Puddle:** a glossy violet slime with a bulging rim, droplets, slow swirls and
##   bubbles; it splats in and shrinks away.
## - **Shield Bubble:** an iridescent soap-film sphere with a sweeping hex lattice; it grows in,
##   flickers before it runs out and pops into sparks when it blocks a hit.
## - **Draft Magnet:** a tube of light from the puller to the kart ahead, rings rushing along
##   it, and a grip ring on the target.
## - Bursts (glass shards and sparkles) when a pod breaks, a puck ends or a shield pops.
##
## Nodes only read the logic (`bind` each race, `sync` each frame from the scene), so a pause
## freezes them. Pools are fixed and preallocated; the tablet budget is a handful of draw calls
## while nothing is flying.

static var _rotor_shader: Shader  ## see _make_rotor_shader

const SHADERS := "res://games/kart_race/world/shaders/"
const POD_LIFT := 1.1  ## the capsule's centre over the road
const POD_BOB := 0.12
const POD_SPIN := 0.8  ## rad/s
const POD_POP_SEC := 0.45
## Pods farther than this from the camera (metres), or behind it, keep their last pose: a bob
## and a spin nobody can see aren't worth the main thread (the tablet's limit).
const POD_ANIM_RANGE := 80.0
const PUCKS := KartItemLogic.PUCK_MAX
const DRONES := KartItemLogic.DRONE_MAX
const SHIELD_RADIUS := 1.6
const TRAIL_POINTS := 16
const TRAIL_EVERY := 0.025  ## s between trail samples
const SPARKS := 160
const SHARDS := 72
const GOO_SHRINK_SEC := 0.3
const GOO_GROW_SEC := 0.35
const SHIELD_GROW_SEC := 0.25
const SHIELD_POP_SEC := 0.3
const SHIELD_FLICKER_SEC := 1.8
const PUCK_COLOR := Color(1.0, 0.62, 0.16)
const DRONE_TRAIL := Color(0.35, 0.85, 1.0)
const GOO_SPLAT := Color(0.75, 0.3, 0.95)
const SHIELD_COLOR := Color(0.4, 0.88, 1.0)
const MAGNET_COLOR := Color(0.35, 1.0, 0.72)

var items: KartItemLogic
var race: KartRaceLogic
## Drawing between logic ticks (KartRace, every frame): the share of a tick since the last one,
## and the karts as drawn (KartState.draw_into). Without them, the logic's own state.
var alpha := 1.0
var draw_karts: Array[KartState] = []

var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _pod_glass: MultiMesh
var _pod_core: MultiMesh
var _pod_halo: MultiMesh
var _pod_band: MultiMesh
var _pod_drawn := PackedInt32Array()  ## per pod: 1 drawn ready, 0 drawn gone, -1 not yet
var _beam_clock := 0.0
var _pucks: Array[Dictionary] = []  ## {root, body, rim, trail, mesh, shot, points, clock}
var _drones: Array[Dictionary] = []  ## {root, body, red, green, strobe, lock, trail, mesh, shot, points, clock}
var _goos: Array[Dictionary] = []  ## {node, mat, goo, gone}
var _shields: Array[Dictionary] = []  ## {node, mat, on, age, pop}
var _magnets: Array[Dictionary] = []  ## {beam, mat, grip}
var _slot_of := {}  ## Shot -> its pool slot
# Bursts: sparkles (billboards, additive) and shards (spinning glass chips).
var _spark_mm: MultiMesh
var _sp := PackedVector3Array()
var _sv := PackedVector3Array()
var _sl := PackedFloat32Array()
var _sa := PackedFloat32Array()
var _ss := PackedFloat32Array()
var _sc := PackedColorArray()
var _sn := 0
var _shard_mm: MultiMesh
var _hp := PackedVector3Array()
var _hv := PackedVector3Array()
var _hr := PackedVector3Array()
var _hw := PackedVector3Array()
var _hl := PackedFloat32Array()
var _ha := PackedFloat32Array()
var _hh := PackedFloat32Array()
var _hn := 0
var _materials := {}


func _ready() -> void:
	_rng.seed = 4711
	_build_pod_pools()
	_spark_mm = _billboards("Sparkles", SPARKS)
	_shard_mm = _shard_pool("Shards", SHARDS)
	for i in PUCKS:
		_pucks.append(_make_puck(i))
	for i in DRONES:
		_drones.append(_make_drone(i))
	for i in KartItemLogic.GOO_MAX:
		_goos.append(_make_goo(i))


## A new race: draw `logic`'s pods, shots, goo and magnets, and listen to its events.
func bind(logic: KartItemLogic, race_logic: KartRaceLogic) -> void:
	items = logic
	race = race_logic
	_slot_of.clear()
	for slot in _pucks + _drones:
		slot.shot = null
		slot.root.visible = false
		if slot.has("lock"):
			slot.lock.visible = false
	for slot in _goos:
		slot.goo = null
		slot.node.visible = false
	_pod_glass.instance_count = logic.pods.size()
	_pod_core.instance_count = logic.pods.size()
	_pod_halo.instance_count = logic.pods.size()
	_pod_band.instance_count = logic.pods.size()
	_pod_drawn.resize(logic.pods.size())
	_pod_drawn.fill(-1)
	while _shields.size() < race.karts.size():
		_shields.append(_make_shield(_shields.size()))
		_magnets.append(_make_magnet(_magnets.size()))
	for s in _shields:
		s.on = false
		s.pop = -1.0
		s.node.visible = false
	for m in _magnets:
		m.beam.visible = false
		m.grip.visible = false
	logic.pod_broken.connect(_on_pod_broken)
	race.events.shield_blocked.connect(_on_shield_blocked)
	race.events.kart_hit.connect(_on_kart_hit)
	sync(0.0)


## Every frame, after the logic's steps.
func sync(dt: float) -> void:
	_time += dt
	if items == null:
		return
	_sync_pods()
	_sync_shots(dt)
	_sync_goos(dt)
	_sync_shields(dt)
	_sync_magnets()
	_simulate(dt)


## Kart `id` as drawn this frame (between ticks), or the logic's when nothing draws it.
func _drawn(id: int) -> KartState:
	return draw_karts[id] if id < draw_karts.size() else race.karts[id]


# --- Pods ---

func _sync_pods() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye := cam.global_position if cam else Vector3.ZERO
	var look := -cam.global_transform.basis.z if cam else Vector3.ZERO
	for i in items.pods.size():
		var pod: KartItemLogic.Pod = items.pods[i]
		var ready := pod.ready()
		if cam and _pod_drawn[i] == int(ready):
			var to := pod.pos - eye
			if to.length_squared() > POD_ANIM_RANGE * POD_ANIM_RANGE or to.dot(look) < -3.0:
				continue
			if not ready:
				continue  # drawn gone already
		_pod_drawn[i] = int(ready)
		if not ready:
			var gone := Transform3D(Basis().scaled(Vector3.ONE * 0.0001), pod.pos)
			_pod_glass.set_instance_transform(i, gone)
			_pod_core.set_instance_transform(i, gone)
			_pod_halo.set_instance_transform(i, gone)
			_pod_band.set_instance_transform(i, gone)
			continue
		var phase := float(i) * 1.7
		var hue := fposmod(float(i) * 0.19 + _time * 0.06, 1.0)
		var pop := clampf(1.0 - pod.age / 0.25, 0.0, 1.0) * 0.6
		var grow := pod_grow(pod)
		var xf := pod_transform(i, pod)
		var centre := xf.origin
		_pod_glass.set_instance_transform(i, xf)
		_pod_glass.set_instance_custom_data(i, Color(hue, pop, 0.0, 0.0))
		var core_b := Basis(Vector3.UP, -_time * 2.4 + phase) * Basis(Vector3.RIGHT, 0.6)
		var beat := 1.0 + 0.1 * sin(_time * 6.0 + phase)
		_pod_core.set_instance_transform(i, Transform3D(core_b.scaled(Vector3.ONE * grow * beat), centre))
		_pod_core.set_instance_custom_data(i, Color(hue, pop, 1.1, 0.0))
		# The glowing band round the capsule's waist, turning the other way.
		var band_b := Basis(Vector3.UP, -_time * 1.4 + phase).scaled(Vector3(1.0, 0.5, 1.0) * grow)
		_pod_band.set_instance_transform(i, Transform3D(band_b, centre))
		_pod_band.set_instance_custom_data(i, Color(hue, pop, 0.9, 0.0))
		var halo := Transform3D(Basis().scaled(Vector3(1.0, 1.0, 1.0) * grow * (1.0 + 0.08 * sin(_time * 2.1 + phase))), pod.pos + Vector3.UP * 0.04)
		_pod_halo.set_instance_transform(i, halo)
		var hc := _hue(hue)
		_pod_halo.set_instance_color(i, Color(hc.r, hc.g, hc.b, 0.55))


## Pod `i`'s capsule transform now: floating, bobbing, turning, popping in after a respawn.
func pod_transform(i: int, pod: KartItemLogic.Pod) -> Transform3D:
	if not pod.ready():
		return Transform3D(Basis().scaled(Vector3.ONE * 0.0001), pod.pos)
	var phase := float(i) * 1.7
	var centre := pod.pos + Vector3.UP * (POD_LIFT + POD_BOB * sin(_time * 2.1 + phase))
	var b := Basis(Vector3.UP, _time * POD_SPIN + phase) * Basis(Vector3.BACK, 0.1 * sin(_time * 1.3 + phase))
	return Transform3D(b.scaled(Vector3.ONE * pod_grow(pod)), centre)


static func pod_grow(pod: KartItemLogic.Pod) -> float:
	if pod.age < POD_POP_SEC:
		return maxf(0.05, _back_out(pod.age / POD_POP_SEC))
	return 1.0


func _on_pod_broken(index: int, _kart_id: int) -> void:
	if index < 0 or index >= items.pods.size():
		return
	var pod: KartItemLogic.Pod = items.pods[index]
	var at := pod.pos + Vector3.UP * POD_LIFT
	var hue := fposmod(float(index) * 0.19 + _time * 0.06, 1.0)
	for i in 14:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.2, 1.0), _rng.randf_range(-1, 1)).normalized()
		_shard(at + dir * 0.3, dir * _rng.randf_range(3.0, 7.0) + Vector3.UP * 2.0, _rng.randf_range(0.5, 0.9), _rng.randf_range(0.12, 0.24))
	for i in 18:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 1.0), _rng.randf_range(-1, 1)).normalized()
		var c := _hue(fposmod(hue + _rng.randf_range(-0.1, 0.1), 1.0)).lerp(Color.WHITE, 0.3)
		_spark(at, dir * _rng.randf_range(2.0, 6.0), _rng.randf_range(0.35, 0.7), _rng.randf_range(0.18, 0.4), c)
	_spark(at, Vector3.ZERO, 0.25, 2.4, Color(1, 1, 1, 0.8))


# --- Pucks and drones ---

func _sync_shots(dt: float) -> void:
	_release_ended(_pucks)
	_release_ended(_drones)
	for shot: KartItemLogic.Shot in items.shots:
		if not shot.alive:
			continue
		var pool := _pucks if shot.kind == "puck" else _drones
		if not _slot_of.has(shot):
			var free := -1
			for i in pool.size():
				if pool[i].shot == null:
					free = i
					break
			if free < 0:
				continue
			_slot_of[shot] = free
			pool[free].shot = shot
			pool[free].points = PackedVector3Array()
			pool[free].clock = 0.0
		var slot: Dictionary = pool[_slot_of[shot]]
		if shot.kind == "puck":
			_pose_puck(slot, shot, dt)
		else:
			_pose_drone(slot, shot, dt)


## Releases the slots of shots that ended (with a puff where they went). Per pool, every frame:
## no concatenated array.
func _release_ended(pool: Array[Dictionary]) -> void:
	for slot in pool:
		var shot: KartItemLogic.Shot = slot.shot
		if shot != null and not shot.alive:
			_end_burst(slot)
			_slot_of.erase(shot)
			slot.shot = null
			slot.root.visible = false
			slot.trail.visible = false
			if slot.has("lock"):
				slot.lock.visible = false


func _pose_puck(slot: Dictionary, shot: KartItemLogic.Shot, dt: float) -> void:
	var at := shot.prev_pos.lerp(shot.pos, alpha) + Vector3.UP * 0.2
	slot.root.visible = true
	slot.root.global_transform = Transform3D(Basis(Vector3.UP, shot.heading), at)
	slot.body.rotation.y = -_time * 14.0
	slot.rim.rotation.y = _time * 6.0
	_trail(slot, at + Vector3.UP * 0.05, dt, 0.42, PUCK_COLOR)


func _pose_drone(slot: Dictionary, shot: KartItemLogic.Shot, dt: float) -> void:
	var at := shot.prev_pos.lerp(shot.pos, alpha) + Vector3.UP * (shot.height + 0.08 * sin(_time * 5.0))
	slot.root.visible = true
	var tilt := Basis(Vector3.RIGHT, -0.22)  # nose down, flying forward
	slot.root.global_transform = Transform3D(Basis(Vector3.UP, shot.heading) * tilt, at)
	var blink := fmod(_time * 2.5, 1.0)
	slot.red.visible = blink < 0.18
	slot.green.visible = blink > 0.5 and blink < 0.68
	slot.strobe.visible = fmod(_time * 1.3, 1.0) < 0.06
	_trail(slot, at - slot.root.global_basis.z * -0.3, dt, 0.18, DRONE_TRAIL)
	# The lock-on ring under the target.
	if shot.target >= 0 and shot.target < race.karts.size():
		var t := _drawn(shot.target)
		slot.lock.visible = true
		var pulse := 1.0 + 0.15 * sin(_time * 14.0)
		slot.lock.global_transform = Transform3D(Basis(Vector3.UP, _time * 2.0).scaled(Vector3(pulse, 1.0, pulse)), t.pos + Vector3.UP * 0.06)
	else:
		slot.lock.visible = false


## Adds `at` to the slot's trail every TRAIL_EVERY seconds and rebuilds its ribbon (camera-facing
## sideways, `width` wide at the head, fading to nothing at the tail).
func _trail(slot: Dictionary, at: Vector3, dt: float, width: float, color: Color) -> void:
	slot.clock += dt
	var pts: PackedVector3Array = slot.points
	if pts.is_empty() or slot.clock >= TRAIL_EVERY:
		slot.clock = 0.0
		pts.insert(0, at)
		if pts.size() > TRAIL_POINTS:
			pts.resize(TRAIL_POINTS)
	else:
		pts[0] = at
	slot.points = pts
	var im: ImmediateMesh = slot.mesh
	im.clear_surfaces()
	slot.trail.visible = pts.size() >= 2
	if pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye := cam.global_position if cam else at + Vector3.UP * 10.0
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var p := pts[i]
		var along := (pts[maxi(i - 1, 0)] - pts[mini(i + 1, pts.size() - 1)])
		if along.length_squared() < 0.000001:
			along = Vector3.FORWARD
		var side := along.cross(eye - p).normalized()
		var f := 1.0 - float(i) / (pts.size() - 1)
		var w := width * (0.25 + 0.75 * f)
		var c := Color(color.r, color.g, color.b, f * f)
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(0.0, f))
		im.surface_add_vertex(p - side * w)
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(1.0, f))
		im.surface_add_vertex(p + side * w)
	im.surface_end()


func _end_burst(slot: Dictionary) -> void:
	var at: Vector3 = slot.root.global_position if slot.root.visible else Vector3.ZERO
	if not slot.root.visible:
		return
	var c := PUCK_COLOR if slot.has("rim") else DRONE_TRAIL
	for i in 16:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.0, 1.0), _rng.randf_range(-1, 1)).normalized()
		_spark(at, dir * _rng.randf_range(2.5, 6.5), _rng.randf_range(0.3, 0.6), _rng.randf_range(0.15, 0.32), c.lerp(Color.WHITE, _rng.randf() * 0.5))
	_spark(at, Vector3.ZERO, 0.22, 2.0, Color(1, 0.95, 0.85, 0.9))


# --- Goo ---

func _sync_goos(dt: float) -> void:
	# Fading out the ones that ended.
	for slot in _goos:
		var goo: KartItemLogic.Goo = slot.goo
		if goo != null and not goo.alive:
			slot.gone += dt
			var f: float = 1.0 - slot.gone / GOO_SHRINK_SEC
			if f <= 0.0:
				slot.goo = null
				slot.node.visible = false
			else:
				slot.node.scale = Vector3(f, 1.0, f) * (1.0 + (1.0 - f) * 0.3)
				slot.mat.set_shader_parameter("fade", f)
	for goo: KartItemLogic.Goo in items.goos:
		if not goo.alive:
			continue
		var slot: Dictionary = {}
		for s in _goos:
			if s.goo == goo:
				slot = s
				break
		if slot.is_empty():
			# A free slot, else one still fading out: the logic keeps at most GOO_MAX live, so
			# one of the pool is always free or fading, and a live puddle is never undrawn.
			var take: Dictionary = {}
			for s in _goos:
				if s.goo == null:
					take = s
					break
				if not s.goo.alive and (take.is_empty() or s.gone > take.gone):
					take = s
			if not take.is_empty():
				var s: Dictionary = take
				slot = s
				s.goo = goo
				s.gone = 0.0
				s.node.visible = true
				s.mat.set_shader_parameter("fade", 1.0)
				s.mat.set_shader_parameter("seed", _rng.randf() * 10.0)
				var n: KartTrackPoint = race.track.sample(goo.s)
				var up := n.normal if n.normal.length_squared() > 0.5 else Vector3.UP
				var fwd := Vector3(-sin(goo.heading), 0.0, -cos(goo.heading))
				fwd = (fwd - up * fwd.dot(up)).normalized()
				s.node.global_transform = Transform3D(Basis.looking_at(fwd, up), goo.pos + up * 0.03)
				for i in 10:
					var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.4, 1.0), _rng.randf_range(-1, 1)).normalized()
					_spark(goo.pos + Vector3.UP * 0.2, dir * _rng.randf_range(1.5, 3.5), _rng.randf_range(0.3, 0.5), _rng.randf_range(0.15, 0.3), GOO_SPLAT)
		if slot.is_empty():
			continue
		var g := 1.0
		if goo.age < GOO_GROW_SEC:
			g = maxf(0.05, _back_out(goo.age / GOO_GROW_SEC))
		var wobble := 1.0 + 0.04 * sin(_time * 3.0 + goo.s)
		var basis: Basis = slot.node.global_basis.orthonormalized()
		slot.node.global_basis = basis.scaled(Vector3(g * wobble, 1.0, g / wobble))


# --- Shields ---

func _sync_shields(dt: float) -> void:
	for k: KartState in race.karts:
		var slot: Dictionary = _shields[k.id]
		var on := k.shield_time > 0.0
		if on and not slot.on:
			slot.age = 0.0
			slot.pop = -1.0
		slot.on = on
		var node: MeshInstance3D = slot.node
		var mat: ShaderMaterial = slot.mat
		if on:
			slot.age += dt
			node.visible = true
			var grow := _back_out(minf(1.0, slot.age / SHIELD_GROW_SEC))
			mat.set_shader_parameter("grow", maxf(grow, 0.05))
			mat.set_shader_parameter("flicker", 1.0 if k.shield_time < SHIELD_FLICKER_SEC else 0.0)
			mat.set_shader_parameter("hit", 0.0)
		elif slot.pop >= 0.0:
			slot.pop += dt
			var f: float = slot.pop / SHIELD_POP_SEC
			if f >= 1.0:
				slot.pop = -1.0
				node.visible = false
			else:
				mat.set_shader_parameter("grow", 1.0 + f * 0.6)
				mat.set_shader_parameter("hit", 1.0 - f)
				mat.set_shader_parameter("flicker", 0.0)
		else:
			node.visible = false
		if node.visible:
			var drawn := _drawn(k.id)
			var up := drawn.normal if drawn.normal.length_squared() > 0.5 else Vector3.UP
			node.global_position = drawn.pos + up * 0.75


func _on_shield_blocked(kart_id: int) -> void:
	if kart_id < 0 or kart_id >= _shields.size():
		return
	var slot: Dictionary = _shields[kart_id]
	slot.pop = 0.0
	slot.node.visible = true
	var at: Vector3 = race.karts[kart_id].pos + Vector3.UP * 0.75
	for i in 26:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.4, 1), _rng.randf_range(-1, 1)).normalized()
		_spark(at + dir * SHIELD_RADIUS, dir * _rng.randf_range(2.0, 5.0), _rng.randf_range(0.3, 0.6), _rng.randf_range(0.15, 0.35),
			SHIELD_COLOR.lerp(Color.WHITE, _rng.randf() * 0.6))


func _on_kart_hit(kart_id: int, _by_id: int, item: String) -> void:
	if item != "goo" or kart_id < 0 or kart_id >= race.karts.size():
		return
	var at: Vector3 = race.karts[kart_id].pos + Vector3.UP * 0.3
	for i in 16:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.3, 1.0), _rng.randf_range(-1, 1)).normalized()
		_spark(at, dir * _rng.randf_range(2.0, 4.5), _rng.randf_range(0.35, 0.6), _rng.randf_range(0.2, 0.4), GOO_SPLAT.lerp(Color.WHITE, _rng.randf() * 0.25))


# --- Magnets ---

func _sync_magnets() -> void:
	for k: KartState in race.karts:
		var slot: Dictionary = _magnets[k.id]
		var t_id: int = items.magnet_target[k.id]
		var on: bool = items.magnet_time[k.id] > 0.0 and t_id >= 0
		slot.beam.visible = on
		slot.grip.visible = on
		if not on:
			continue
		var t := _drawn(t_id)
		var kd := _drawn(k.id)
		var a := kd.pos + kd.forward() * 1.1 + Vector3.UP * 0.75
		var b := t.pos - t.forward() * 1.2 + Vector3.UP * 0.75
		var axis := b - a
		var length := axis.length()
		if length < 0.5:
			slot.beam.visible = false
			continue
		var y := axis / length
		var x := y.cross(Vector3.UP)
		if x.length_squared() < 0.0001:
			x = Vector3.RIGHT
		x = x.normalized()
		var z := x.cross(y).normalized()
		var flare := 1.0 + 0.12 * sin(_time * 20.0)
		slot.beam.global_transform = Transform3D(Basis(x * flare, y * length, z * flare), (a + b) * 0.5)
		slot.mat.set_shader_parameter("beam_length", length)
		var fade := clampf(items.magnet_time[k.id] / 0.4, 0.0, 1.0)
		slot.mat.set_shader_parameter("strength", fade)
		var pulse := 1.0 + 0.2 * sin(_time * 16.0)
		slot.grip.global_transform = Transform3D(Basis(x, y, z).scaled(Vector3.ONE * pulse), b)
		# Motes streaming down the beam toward the puller.
		_beam_clock += get_process_delta_time()
		if _beam_clock > 0.05:
			_beam_clock = 0.0
			var p := b - axis * _rng.randf_range(0.0, 0.4) + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.4, 0.4))
			_spark(p, -y * _rng.randf_range(12.0, 18.0), minf(0.5, length / 15.0), _rng.randf_range(0.15, 0.3), MAGNET_COLOR.lerp(Color.WHITE, 0.4))


# --- Bursts ---

func _spark(p: Vector3, v: Vector3, life: float, size: float, c: Color) -> void:
	var i := _sn % SPARKS
	_sn += 1
	_sp[i] = p
	_sv[i] = v
	_sl[i] = life
	_sa[i] = 0.0
	_ss[i] = size
	_sc[i] = c


func _shard(p: Vector3, v: Vector3, life: float, size: float) -> void:
	var i := _hn % SHARDS
	_hn += 1
	_hp[i] = p
	_hv[i] = v
	_hl[i] = life
	_ha[i] = 0.0
	_hh[i] = size
	_hr[i] = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0.0)
	_hw[i] = Vector3(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12), 0.0)


func _simulate(dt: float) -> void:
	var shown := 0
	for i in SPARKS:
		if _sa[i] >= _sl[i]:
			continue
		_sa[i] += dt
		if _sa[i] >= _sl[i]:
			continue
		_sv[i] *= 1.0 - minf(1.0, 2.5 * dt)
		_sv[i].y -= 6.0 * dt
		_sp[i] += _sv[i] * dt
		var f := _sa[i] / _sl[i]
		var c := _sc[i]
		c.a *= 1.0 - f * f
		var s := _ss[i] * (1.0 - 0.6 * f)
		_spark_mm.set_instance_transform(shown, Transform3D(Basis().scaled(Vector3.ONE * s), _sp[i]))
		_spark_mm.set_instance_color(shown, c)
		shown += 1
	_spark_mm.visible_instance_count = shown
	shown = 0
	for i in SHARDS:
		if _ha[i] >= _hl[i]:
			continue
		_ha[i] += dt
		if _ha[i] >= _hl[i]:
			continue
		_hv[i].y -= 14.0 * dt
		_hp[i] += _hv[i] * dt
		_hr[i] += _hw[i] * dt
		var f := _ha[i] / _hl[i]
		var s := _hh[i] * (1.0 - f * f)
		var b := Basis.from_euler(_hr[i]).scaled(Vector3.ONE * s)
		_shard_mm.set_instance_transform(shown, Transform3D(b, _hp[i]))
		_shard_mm.set_instance_custom_data(shown, Color(fposmod(float(i) * 0.13, 1.0), 0.0, 1.0 - f * 0.5, 0.0))
		shown += 1
	_shard_mm.visible_instance_count = shown


# --- Builders ---

func _shader(file: String) -> Shader:
	if not _materials.has(file):
		_materials[file] = load(SHADERS + file)
	return _materials[file]


func _mat(file: String, params := {}) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(file)
	if file in ["item_glass.gdshader", "item_goo.gdshader"]:
		KartLook.apply_light(mat)
	for key in params:
		mat.set_shader_parameter(key, params[key])
	return mat


func _glow(color: Color, strength := 1.0, pulse := 0.2, hz := 2.0) -> ShaderMaterial:
	return _mat("item_glow.gdshader", {"color": color, "strength": strength, "pulse": pulse, "pulse_hz": hz})


func _build_pod_pools() -> void:
	var glass := MeshKit3D.capsule(0.52, 1.5, 8, 2)
	var core := MeshKit3D.sphere(0.27, 4, 2)  # a faceted gem
	var halo := PlaneMesh.new()
	halo.size = Vector2(2.4, 2.4)
	var glass_node := MeshKit3D.multimesh_node(glass, [], "PodGlass")
	_pod_glass = _custom_mm(glass_node, glass)
	glass_node.material_override = _mat("item_glass.gdshader")
	add_child(glass_node)
	var band := MeshKit3D.torus(0.5, 0.6, 20, 4)
	var band_node := MeshKit3D.multimesh_node(band, [], "PodBands")
	_pod_band = _custom_mm(band_node, band)
	band_node.material_override = _mat("item_glow.gdshader", {"per_instance": true, "pulse": 0.3, "pulse_hz": 1.0})
	add_child(band_node)
	var core_node := MeshKit3D.multimesh_node(core, [], "PodCores")
	_pod_core = _custom_mm(core_node, core)
	core_node.material_override = _mat("item_glow.gdshader", {"per_instance": true, "pulse": 0.15, "pulse_hz": 1.5})
	add_child(core_node)
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.vertex_color_use_as_albedo = true
	halo_mat.albedo_texture = MeshKit3D.soft_disc(64)
	halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	halo_mat.disable_fog = true
	halo.material = halo_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = halo
	var halo_node := MultiMeshInstance3D.new()
	halo_node.name = "PodHalos"
	halo_node.multimesh = mm
	halo_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo_node.custom_aabb = _everywhere()
	add_child(halo_node)
	_pod_halo = mm


func _custom_mm(node: MultiMeshInstance3D, mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true  # Compatibility: custom data without colours zeroes COLOR
	mm.mesh = mesh
	node.multimesh = mm
	node.custom_aabb = _everywhere()
	return mm


static func _everywhere() -> AABB:
	return AABB(Vector3(-2000, -200, -2000), Vector3(4000, 400, 4000))


func _billboards(node_name: String, count: int) -> MultiMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _star_texture()
	mat.disable_fog = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var quad := QuadMesh.new()
	quad.material = mat
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
	node.custom_aabb = _everywhere()
	add_child(node)
	_sp.resize(count)
	_sv.resize(count)
	_sl.resize(count)
	_sa.resize(count)
	_ss.resize(count)
	_sc.resize(count)
	return mm


func _shard_pool(node_name: String, count: int) -> MultiMesh:
	var mesh := MeshKit3D.prism(Vector3(1.0, 1.2, 0.25))
	var node := MeshKit3D.multimesh_node(mesh, [], node_name)
	var mm := _custom_mm(node, mesh)
	mm.instance_count = count
	mm.visible_instance_count = 0
	node.material_override = _mat("item_glow.gdshader", {"per_instance": true, "pulse": 0.0, "strength": 0.8})
	add_child(node)
	_hp.resize(count)
	_hv.resize(count)
	_hr.resize(count)
	_hw.resize(count)
	_hl.resize(count)
	_ha.resize(count)
	_hh.resize(count)
	return mm


## A four-point sparkle with a soft core (white; vertex colours tint it).
static func _star_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var u := (x - c) / c
			var v := (y - c) / c
			var r := sqrt(u * u + v * v)
			var core := clampf(1.0 - r * 1.6, 0.0, 1.0)
			var rays := clampf(1.0 - absf(u) * 9.0, 0.0, 1.0) * clampf(1.0 - absf(v), 0.0, 1.0) \
				+ clampf(1.0 - absf(v) * 9.0, 0.0, 1.0) * clampf(1.0 - absf(u), 0.0, 1.0)
			var a := clampf(core * core + rays * 0.8, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _make_puck(i: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Puck%d" % i
	root.visible = false
	add_child(root)
	var kit := MeshKit3D.new()
	kit.add(MeshKit3D.cylinder(0.42, 0.45, 0.26, 16), MeshKit3D.xf(Vector3.ZERO), Color(0.14, 0.16, 0.3, 0.9))
	kit.add(MeshKit3D.cylinder(0.3, 0.36, 0.06, 16), MeshKit3D.xf(Vector3(0, 0.15, 0)), Color(0.95, 0.95, 1.0, 0.9))
	kit.add(MeshKit3D.cylinder(0.12, 0.12, 0.05, 10), MeshKit3D.xf(Vector3(0, 0.19, 0)), Color(1.0, 0.55, 0.12, 0.9))
	for k in 3:
		var a := TAU * k / 3.0
		kit.add(MeshKit3D.box(Vector3(0.08, 0.04, 0.2)), MeshKit3D.xf(Vector3(sin(a) * 0.22, 0.19, cos(a) * 0.22), Vector3(0, rad_to_deg(a), 0)), Color(1.0, 0.55, 0.12, 0.9))
	var body := MeshKit3D.mesh_node(kit.commit(), KartLook.kart_material(true), "Body")
	root.add_child(body)
	var rim := MeshKit3D.mesh_node(MeshKit3D.torus(0.4, 0.55, 18, 6), _glow(PUCK_COLOR, 1.1, 0.25, 4.0), "Rim")
	rim.scale = Vector3(1.0, 0.7, 1.0)
	root.add_child(rim)
	var trail := _trail_node("PuckTrail%d" % i)
	return {"root": root, "body": body, "rim": rim, "trail": trail, "mesh": trail.mesh, "shot": null,
		"points": PackedVector3Array(), "clock": 0.0}


func _make_drone(i: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Drone%d" % i
	root.visible = false
	add_child(root)
	var kit := MeshKit3D.new()
	var hull := Color(0.96, 0.96, 0.98, 0.95)
	var dark := Color(0.12, 0.13, 0.2, 0.6)
	var accent := Color(0.2, 0.7, 1.0, 0.95)
	kit.add(MeshKit3D.sphere(0.3, 12, 6), MeshKit3D.xf(Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.55, 1.25)), hull)
	kit.add(MeshKit3D.sphere(0.17, 10, 5, true), MeshKit3D.xf(Vector3(0, 0.1, -0.12), Vector3.ZERO, Vector3(1.0, 0.8, 1.2)), dark)
	kit.add(MeshKit3D.box(Vector3(0.36, 0.06, 0.12)), MeshKit3D.xf(Vector3(0, -0.08, 0.32)), accent)
	for k in 4:
		var x := 0.42 if k % 2 == 0 else -0.42
		var z := 0.36 if k < 2 else -0.36
		kit.add(MeshKit3D.box(Vector3(0.05, 0.05, 0.6)), MeshKit3D.xf(Vector3(x * 0.5, 0.0, z * 0.5), Vector3(0, rad_to_deg(atan2(x, z)), 0)), dark)
		kit.add(MeshKit3D.cylinder(0.07, 0.08, 0.1, 8), MeshKit3D.xf(Vector3(x, 0.03, z)), accent)
	var body := MeshKit3D.mesh_node(kit.commit(), KartLook.kart_material(true), "Body")
	root.add_child(body)
	# The rotors: blurred discs, the blades swept by their shader.
	for k in 4:
		var x := 0.42 if k % 2 == 0 else -0.42
		var z := 0.36 if k < 2 else -0.36
		var disc := MeshKit3D.mesh_node(_rotor_mesh(), _rotor_material(), "Rotor%d" % k)
		disc.position = Vector3(x, 0.1, z)
		disc.rotation.y = float(k) * 0.9
		root.add_child(disc)
	var red := MeshKit3D.mesh_node(MeshKit3D.sphere(0.07, 6, 3), _glow(Color(1.0, 0.15, 0.1), 2.0, 0.0), "Red")
	red.position = Vector3(-0.32, 0.0, 0.05)
	root.add_child(red)
	var green := MeshKit3D.mesh_node(MeshKit3D.sphere(0.07, 6, 3), _glow(Color(0.2, 1.0, 0.3), 2.0, 0.0), "Green")
	green.position = Vector3(0.32, 0.0, 0.05)
	root.add_child(green)
	var strobe := MeshKit3D.mesh_node(MeshKit3D.sphere(0.09, 6, 3), _glow(Color(1, 1, 1), 2.5, 0.0), "Strobe")
	strobe.position = Vector3(0.0, -0.17, 0.0)
	root.add_child(strobe)
	# A cyan eye at the front: the seeker.
	var eye := MeshKit3D.mesh_node(MeshKit3D.sphere(0.06, 6, 3), _glow(Color(0.3, 0.9, 1.0), 2.0, 0.4, 3.0), "Eye")
	eye.position = Vector3(0.0, -0.02, -0.37)
	root.add_child(eye)
	var lock := MeshKit3D.mesh_node(MeshKit3D.torus(1.15, 1.35, 28, 4), _glow(Color(1.0, 0.18, 0.2), 1.2, 0.4, 5.0), "LockRing%d" % i)
	lock.scale = Vector3(1.0, 0.15, 1.0)
	lock.visible = false
	add_child(lock)
	var trail := _trail_node("DroneTrail%d" % i)
	return {"root": root, "body": body, "red": red, "green": green, "strobe": strobe, "lock": lock,
		"trail": trail, "mesh": trail.mesh, "shot": null, "points": PackedVector3Array(), "clock": 0.0}


func _rotor_mesh() -> ArrayMesh:
	if _materials.has("rotor_mesh"):
		return _materials.rotor_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 0.24
	var corners := [Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[idx])
		st.add_vertex(corners[idx])
	var mesh := st.commit()
	_materials["rotor_mesh"] = mesh
	return mesh


func _rotor_material() -> ShaderMaterial:
	if _materials.has("rotor_mat"):
		return _materials.rotor_mat
	if _rotor_shader == null:
		_rotor_shader = _make_rotor_shader()
	var mat := ShaderMaterial.new()
	mat.shader = _rotor_shader
	_materials["rotor_mat"] = mat
	return mat


## Built once per engine and kept: a new Shader each race would be compiled again (Game.gd).
static func _make_rotor_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, blend_mix, depth_draw_never;
// A spinning rotor seen as a motion blur: a faint disc with two soft blade sweeps.
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) + TIME * 31.0;
	float blades = pow(abs(cos(a)), 6.0);
	float disc = smoothstep(1.0, 0.9, r);
	float hub = smoothstep(0.22, 0.12, r);
	ALBEDO = mix(vec3(0.85, 0.9, 1.0), vec3(0.15, 0.17, 0.25), hub);
	ALPHA = disc * (0.16 + blades * 0.35) + hub * 0.9;
}
"""
	return sh


func _trail_node(node_name: String) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var node := MeshKit3D.mesh_node(im, _mat("item_trail.gdshader"), node_name)
	node.custom_aabb = _everywhere()
	node.visible = false
	add_child(node)
	return node


func _make_goo(i: int) -> Dictionary:
	var mat := _mat("item_goo.gdshader")
	var node := MeshKit3D.mesh_node(_goo_mesh(i), mat, "Goo%d" % i)
	node.visible = false
	add_child(node)
	return {"node": node, "mat": mat, "goo": null, "gone": 0.0}


## An irregular slime puddle, KartItemLogic.GOO_RADIUS across: a domed middle, a bulging rim
## (COLOR.a = 1 at the rim, for the shader), and a few droplets around it.
static func _goo_mesh(variant: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = 77 + variant * 13
	noise.frequency = 0.9
	var radius := KartItemLogic.GOO_RADIUS
	var segs := 28
	var rings := [[0.0, 0.07, 0.0], [0.45, 0.065, 0.0], [0.8, 0.09, 0.6], [0.93, 0.07, 1.0], [1.0, 0.0, 1.0]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid := []
	for ri in rings.size():
		var row := []
		for j in segs:
			var a := TAU * j / segs
			var wob := 1.0 + 0.22 * noise.get_noise_2d(cos(a) * 2.0, sin(a) * 2.0)
			var rr: float = rings[ri][0] * radius * wob
			row.append(Vector3(cos(a) * rr, rings[ri][1], sin(a) * rr))
		grid.append(row)
	for ri in rings.size() - 1:
		for j in segs:
			var j2 := (j + 1) % segs
			var a: Vector3 = grid[ri][j]
			var b: Vector3 = grid[ri][j2]
			var c: Vector3 = grid[ri + 1][j2]
			var d: Vector3 = grid[ri + 1][j]
			var ma: float = rings[ri][2]
			var mb: float = rings[ri + 1][2]
			for tri in [[a, c, b, ma, mb, ma], [a, d, c, ma, mb, mb]]:
				var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				if n.y < 0.0:
					n = -n
				n = (n + Vector3.UP * 0.6).normalized()
				for k in 3:
					st.set_color(Color(1, 1, 1, tri[3 + k]))
					st.set_normal(n)
					st.add_vertex(tri[k])
	var mesh := st.commit()
	# Droplets.
	var kit := MeshKit3D.new()
	kit.add_baked(mesh, Transform3D.IDENTITY)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	for k in 5:
		var a := rng.randf() * TAU
		var r := radius * rng.randf_range(1.12, 1.45)
		var s := rng.randf_range(0.07, 0.16)
		kit.add(MeshKit3D.sphere(s, 8, 4, true), MeshKit3D.xf(Vector3(cos(a) * r, 0.0, sin(a) * r), Vector3.ZERO, Vector3(1.0, 0.55, 1.0)), Color(1, 1, 1, 0.3))
	return kit.commit()


func _make_shield(i: int) -> Dictionary:
	var mat := _mat("item_shield.gdshader", {"color": SHIELD_COLOR})
	var node := MeshKit3D.mesh_node(MeshKit3D.sphere(SHIELD_RADIUS, 20, 10), mat, "Shield%d" % i)
	node.scale = Vector3(1.0, 0.82, 1.15)
	node.visible = false
	add_child(node)
	return {"node": node, "mat": mat, "on": false, "age": 0.0, "pop": -1.0}


func _make_magnet(i: int) -> Dictionary:
	var mat := _mat("item_beam.gdshader", {"color": MAGNET_COLOR})
	var tube := CylinderMesh.new()
	tube.top_radius = 0.42
	tube.bottom_radius = 0.42
	tube.height = 1.0
	tube.radial_segments = 10
	tube.rings = 1
	var beam := MeshKit3D.mesh_node(tube, mat, "MagnetBeam%d" % i)
	beam.visible = false
	add_child(beam)
	var grip := MeshKit3D.mesh_node(MeshKit3D.torus(0.55, 0.75, 20, 4), _glow(MAGNET_COLOR, 1.3, 0.4, 6.0), "MagnetGrip%d" % i)
	grip.visible = false
	add_child(grip)
	return {"beam": beam, "mat": mat, "grip": grip}


# --- Helpers ---

static func _back_out(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var x := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + c3 * x * x * x + c1 * x * x


static func _hue(h: float) -> Color:
	return Color.from_hsv(h, 0.75, 1.0)
