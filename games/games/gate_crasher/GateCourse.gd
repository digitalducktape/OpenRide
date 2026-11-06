class_name GateCourse
extends RefCounted
## Gate Crasher's course (#80): a closed loop round the arena, two straights joined by two half
## circles, indexed by the distance ridden `s` (metres; it keeps counting past a lap). The rules
## only need its length; `GateWorld` and `GateMeshes` place everything with `point` and `heading`.
##
## The first straight runs down -z at x = +RADIUS from z = +STRAIGHT / 2, and the loop turns left.

const STRAIGHT := 130.0
const RADIUS := 28.0
const LENGTH := 2.0 * STRAIGHT + TAU * RADIUS
const _TURN := PI * RADIUS


## The point `s` metres round the loop, on the ground.
static func point(s: float) -> Vector3:
	var d := fposmod(s, LENGTH)
	if d < STRAIGHT:
		return Vector3(RADIUS, 0.0, STRAIGHT / 2.0 - d)
	d -= STRAIGHT
	if d < _TURN:
		var a := d / RADIUS
		return Vector3(RADIUS * cos(a), 0.0, -STRAIGHT / 2.0 - RADIUS * sin(a))
	d -= _TURN
	if d < STRAIGHT:
		return Vector3(-RADIUS, 0.0, -STRAIGHT / 2.0 + d)
	d -= STRAIGHT
	var b := d / RADIUS
	return Vector3(-RADIUS * cos(b), 0.0, STRAIGHT / 2.0 + RADIUS * sin(b))


## The yaw (radians, about +y) that faces along the loop at `s`: 0 looks down -z.
static func heading(s: float) -> float:
	var d := fposmod(s, LENGTH)
	if d < STRAIGHT:
		return 0.0
	d -= STRAIGHT
	if d < _TURN:
		return d / RADIUS
	d -= _TURN
	if d < STRAIGHT:
		return PI
	return PI + (d - STRAIGHT) / RADIUS


## The transform of something standing on the loop at `s`, facing along it.
static func frame(s: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, heading(s)), point(s))
