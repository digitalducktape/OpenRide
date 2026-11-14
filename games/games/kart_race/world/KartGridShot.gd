class_name KartGridShot
extends RefCounted
## Kart Race's title shot over the grid (#43): the camera spot that frames the dresser's hero
## piece (KartDress.hero) over the karts on the grid, solved once per KartWorld.build (a few
## hundred candidates, pure maths): nothing per frame. KartWorld.grid_shot holds the result;
## KartWorld's solve_grid_shot, shot_project, shot_kart_rects and shot_score call in here (solve,
## project, kart_rects, rate).

## The grid shot's frame (the HUD's pixels) and what covers it during the title: karts stay clear
## of the title band; the landmark of the band and the framework's clock and buttons (top right).
const SHOT_SIZE := Vector2(1920.0, 1080.0)
## KartHud's title card band (bottom left, in the HUD's 1920×1080 pixels).
const TITLE_BAND := Rect2(-40.0, 790.0, 1180.0, 240.0)
const SHOT_CORNER := Rect2(1240.0, 0.0, 680.0, 310.0)
const SHOT_KART := Vector3(0.85, 1.4, 1.15)  ## a kart and driver's half-width, height, half-length
const GRID_KARTS := 8


## Searches camera spots round the grid for the one that frames the dresser's hero piece
## (KartDress.hero) over the karts on the grid: the piece clear of the HUD, on a third; no kart
## under the title band or half off the frame; as many karts in shot as possible.
## {eye, look, fov, focus, score}, or empty when the theme has no hero piece or no spot works.
static func solve(world: KartWorld) -> Dictionary:
	var dress := world.dress
	var track := world.track
	var terrain := world.terrain
	if dress == null or dress.hero.is_empty():
		return {}
	var focus: Vector3 = dress.hero.p
	var size: float = dress.hero.get("size", 10.0)
	var g := track.position_at(track.wrap(-22.0), 0.0)
	var eyes: Array[Vector3] = []
	for b in 16:
		var a := TAU * b / 16.0
		for dist: float in [11.0, 15.0, 20.0]:
			for h: float in [2.6, 4.5, 7.5, 12.0]:
				eyes.append(g + Vector3(cos(a), 0.0, sin(a)) * dist + Vector3.UP * h)
	if dress.hero.get("flat", false):
		# A lake: also from beyond its far shore, looking back across the ice to the grid.
		var across := Vector3(focus.x - g.x, 0.0, focus.z - g.z).normalized()
		for turn: float in [-0.5, -0.25, 0.0, 0.25, 0.5]:
			for k: float in [0.6, 0.9, 1.2]:
				for h: float in [6.0, 10.0, 14.0]:
					var at := focus + across.rotated(Vector3.UP, turn) * size * k
					eyes.append(Vector3(at.x, terrain.height_at(at.x, at.z) + h, at.z))
	var best := {}
	var best_score := -INF
	for eye in eyes:
		if not _eye_ok(world, eye):
			continue
		for w: float in [0.3, 0.45, 0.6, 0.75]:
			var dir := (g + Vector3.UP * 0.6 - eye).normalized() * (1.0 - w) + (focus - eye).normalized() * w
			var look_at := eye + dir.normalized() * 10.0
			for fov: float in [46.0, 54.0, 62.0]:
				var score := rate(world, eye, look_at, fov, focus, size)
				if score > best_score:
					best_score = score
					best = {"eye": eye, "look": look_at, "fov": fov, "focus": focus, "score": score}
	return best if best_score > -INF else {}


## Where a world point lands in the 1920×1080 frame of a camera at `eye` looking at `look_at`
## with vertical `fov` (degrees): (x, y, depth); depth < 0 when behind the lens.
static func project(eye: Vector3, look_at: Vector3, fov: float, p: Vector3) -> Vector3:
	var basis := Basis.looking_at(look_at - eye, Vector3.UP)
	var local := basis.transposed() * (p - eye)
	if local.z > -0.1:
		return Vector3(0.0, 0.0, -1.0)
	var t := tan(deg_to_rad(fov) * 0.5)
	var x := local.x / -local.z / (t * SHOT_SIZE.x / SHOT_SIZE.y)
	var y := local.y / -local.z / t
	return Vector3((x * 0.5 + 0.5) * SHOT_SIZE.x, (0.5 - y * 0.5) * SHOT_SIZE.y, -local.z)


## The screen rects of the karts on the grid in that shot; an empty Rect2 for a kart wholly
## behind the lens, and a zero-size one at (-1, -1) for a kart the lens is inside or too near.
static func kart_rects(track: KartTrackModel, eye: Vector3, look_at: Vector3, fov: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in GRID_KARTS:
		var s := track.wrap(-(KartRaceLogic.GRID_FIRST + KartRaceLogic.GRID_GAP * i))
		var d := -KartRaceLogic.GRID_D if i % 2 == 0 else KartRaceLogic.GRID_D
		var pt := track.sample(s)
		var at := track.position_at(s, d)
		var fwd := Vector3(pt.tangent.x, 0.0, pt.tangent.z).normalized()
		var right := Vector3(pt.right.x, 0.0, pt.right.z).normalized()
		if at.distance_to(eye) < 6.0:
			out.append(Rect2(-1.0, -1.0, 0.0, 0.0))
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var behind := 0
		for corner in 8:
			var p := at + right * SHOT_KART.x * (1.0 if corner & 1 else -1.0) \
				+ fwd * SHOT_KART.z * (1.0 if corner & 2 else -1.0) + Vector3.UP * (SHOT_KART.y if corner & 4 else 0.0)
			var q := project(eye, look_at, fov, p)
			if q.z < 0.0:
				behind += 1
				continue
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		if behind == 8:
			out.append(Rect2())
		elif behind > 0:
			out.append(Rect2(-1.0, -1.0, 0.0, 0.0))
		else:
			out.append(Rect2(lo, hi - lo))
	return out


## How good a title shot is (-INF: unusable). Unusable: the hero piece off its framing area,
## under the HUD or hidden by the land; a kart under the title band or the lens inside one;
## fewer than four karts in shot. Better: more karts wholly in shot, the piece on a third and
## big enough to read.
static func rate(world: KartWorld, eye: Vector3, look_at: Vector3, fov: float, focus: Vector3, size: float) -> float:
	var dress := world.dress
	var track := world.track
	var band := TITLE_BAND.grow(16.0)
	var screen := Rect2(Vector2.ZERO, SHOT_SIZE)
	var fp := project(eye, look_at, fov, focus)
	# A flat piece (a lake) is seen from above, and may fill the foreground: aim lower.
	var flat: bool = dress.hero.get("flat", false) if dress else false
	if flat and (eye.y - focus.y) < 0.15 * Vector2(eye.x - focus.x, eye.z - focus.z).length():
		return -INF
	var aim_y := 0.62 if flat else 0.32
	if fp.z < 0.0 or fp.x < SHOT_SIZE.x * 0.08 or fp.x > SHOT_SIZE.x * 0.92 or fp.y < SHOT_SIZE.y * 0.08 \
			or fp.y > SHOT_SIZE.y * (0.85 if flat else 0.66):
		return -INF
	if SHOT_CORNER.grow(40.0).has_point(Vector2(fp.x, fp.y)) or band.has_point(Vector2(fp.x, fp.y)):
		return -INF
	if not _line_of_sight(world, eye, focus):
		return -INF
	var whole := 0
	var cut := 0
	var tall := 0.0
	for r in kart_rects(track, eye, look_at, fov):
		if r.position.x == -1.0 and r.size == Vector2.ZERO:
			return -INF
		if r.size == Vector2.ZERO or not r.intersects(screen):
			continue
		if r.intersects(band):
			return -INF
		if screen.encloses(r):
			whole += 1
			tall += r.size.y / SHOT_SIZE.y
		else:
			cut += 1
	if whole < 4:
		return -INF
	var thirds := minf(absf(fp.x / SHOT_SIZE.x - 0.66), absf(fp.x / SHOT_SIZE.x - 0.34))
	var px := size / maxf(fp.z, 1.0) / tan(deg_to_rad(fov) * 0.5) * 0.5
	# The karts big enough to read (a tenth of the frame's height, on average, is plenty).
	var kart_size := 30.0 * minf(tall / maxf(whole, 1.0), 0.1)
	return whole + kart_size - 0.6 * cut - 3.0 * thirds - 2.0 * absf(fp.y / SHOT_SIZE.y - aim_y) + 4.0 * minf(px, 0.25) \
		- 0.04 * eye.distance_to(track.position_at(track.wrap(-22.0), 0.0)) \
		+ float(dress.hero.get("lift", 0.0) if dress else 0.0) * (eye.y - track.position_at(track.wrap(-22.0), 0.0).y) / 12.0


## A camera spot for the title: above the land, on the road side of the barriers (low), clear of
## the grandstand and the gate.
static func _eye_ok(world: KartWorld, eye: Vector3) -> bool:
	var track := world.track
	if eye.y < world.terrain.height_at(eye.x, eye.z) + 1.5:
		return false
	var near := track.project(eye)
	var edge := track.half_width(near.s) + track.verge
	var height := eye.y - near.position.y
	if absf(near.d) > edge - 0.5 and height < 10.0:
		return false
	if near.d > edge - 0.5 and world.in_stand(near.s):
		return false
	var ss := near.s - track.length if near.s > track.length * 0.5 else near.s
	# Not beside a flag pole (they line the start: KartStartArea.build_flags) or in the gate.
	if ss > -72.0 and ss < 42.0 and absf(absf(near.d) - (edge + 1.2)) < 3.0:
		return false
	return absf(ss - 1.0) > 3.0 or height > 9.0


## Whether the land leaves the line from `a` to `b` clear (sampled; the far end's last 10% is
## the piece itself, so it isn't tested).
static func _line_of_sight(world: KartWorld, a: Vector3, b: Vector3) -> bool:
	var terrain := world.terrain
	var stand := world.stand_xf.affine_inverse()
	var has_stand := world.has_grandstand()
	for i in range(1, 22):
		var p := a.lerp(b, i / 23.0)
		if terrain.height_at(p.x, p.z) > p.y + 0.5:
			return false
		if has_stand:
			var q := stand * p
			if q.x > -3.0 and q.x < 10.0 and q.y < 10.5 and absf(q.z) < KartWorld.STAND_LENGTH * 0.5 + 1.0:
				return false
	return true
