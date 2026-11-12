class_name KartDress
extends RefCounted
## A theme's land and set pieces for KartWorld (#43). Each theme subclasses it: `base_height`
## shapes the land away from the road (KartTerrain blends the road's level into it),
## `ground_tint` colours patches of it, and `dress` adds the theme's scenery into the world's
## trackside cells (baked meshes, culled by distance), the far woods' sectors, or its own nodes.
## Shared models (trees, rocks) live here so every theme keeps one consistent toy style.

const THEMES := {
	"meadow": "res://games/kart_race/world/KartDressMeadow.gd",
	"canyon": "res://games/kart_race/world/KartDressCanyon.gd",
	"harbor": "res://games/kart_race/world/KartDressHarbor.gd",
	"frost": "res://games/kart_race/world/KartDressFrost.gd",
}

var world: KartWorld
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()

## The theme's hero set piece for the title shot over the grid (KartWorld.grid_shot): {p (the
## point to frame), size (metres across)}; the dresser sets it where it builds the piece.
var hero := {}

var _level_pts := PackedVector3Array()


static func for_theme(theme: String) -> KartDress:
	return load(THEMES.get(theme, THEMES.meadow)).new()


func _init() -> void:
	noise.seed = 31
	noise.frequency = 0.006
	noise.fractal_octaves = 3


## The land's height at (x, z), `r_road` metres beyond the nearest barrier (KartTerrain.FAR when
## the road is far). Default: gently rolling, rising to hills beyond the track.
func base_height(x: float, z: float, _r_road: float) -> float:
	return world.centre.y + 1.2 * noise.get_noise_2d(x * 3.0, z * 3.0) + hills(x, z, 12.0, 55.0, 40.0)


## Hills rising from just beyond the track's reach: `low` + `high` × noise metres, plus `far`
## more toward the horizon.
func hills(x: float, z: float, low: float, high: float, far: float) -> float:
	var rc := Vector2(x - world.centre.x, z - world.centre.z).length()
	var r0 := world.reach + 70.0
	var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
	return smoothstep(r0, r0 + 180.0, rc) * (low + high * n) + smoothstep(r0 + 200.0, r0 + 650.0, rc) * far


## The road's general height near (x, z): an inverse-distance blend of the road every 30 m,
## so land far from the road still slopes with it (a mountainside, not an embankment).
func road_level(x: float, z: float) -> float:
	if _level_pts.is_empty():
		var s := 0.0
		while s < world.track.length:
			_level_pts.append(world.track.sample(s).position)
			s += 30.0
	var wsum := 0.0
	var hsum := 0.0
	for p in _level_pts:
		var w := 1.0 / ((x - p.x) * (x - p.x) + (z - p.z) * (z - p.z) + 900.0)
		wsum += w
		hsum += w * p.y
	return hsum / wsum - 0.6


## A basis whose local +y runs along `dir` (posts, struts, cables between two points).
static func along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


## Steps a height into terraces `step` metres tall with steep risers (mesas, ledges).
static func terrace(h: float, step: float) -> float:
	var f := h / step
	var i := floorf(f)
	return (i + smoothstep(0.72, 1.0, f - i)) * step


## Whether `p` stands in the sight line from the grid to the hero piece (or on the piece), where
## scattered scenery would hide it from the title shot. Dressers set `hero` before scattering.
func in_hero_sight(p: Vector3) -> bool:
	if hero.is_empty():
		return false
	var g: Vector3 = world.grid_shot.get("eye", world.track.position_at(world.track.wrap(-22.0), 0.0))
	var a := Vector2(g.x, g.z)
	var b := Vector2(hero.p.x, hero.p.z)
	var q := Vector2(p.x, p.z)
	var ab := b - a
	var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.2)
	return q.distance_to(a + ab * t) < 6.0 + float(hero.get("size", 10.0)) * 0.6 * t


## A colour multiplied into the land at (x, z) (Color.WHITE: none).
func ground_tint(_x: float, _z: float, _h: float) -> Color:
	return Color.WHITE


## Places the theme's hero set piece (the one the title shot frames) and sets `hero`. Runs before
## `dress`, so the shot is solved first and the scatter keeps out of its sight line.
func dress_hero(_scenery: Node3D, _props: Dictionary) -> void:
	pass


## Adds the theme's scenery. `foliage` and `props` are trackside cell kits (KartWorld.cell);
## `woods` the far sectors (KartWorld.sector_of).
func dress(_scenery: Node3D, _foliage: Dictionary, _props: Dictionary, _woods: Array) -> void:
	pass


# --- Shared helpers ---

## Scatters `count` of `meshes` (chosen by `pick(rng) -> int`) beside the road, `near`..`far`
## metres beyond the barrier, scaled `size` (Vector2 min, max), into `cells`. Skips the
## grandstand when `skip_stand`.
func scatter(cells: Dictionary, meshes: Array, count: int, near: float, far: float, size: Vector2,
		pick: Callable, clearance := KartWorld.TREE_CLEARANCE, skip_stand := true, sink := 0.15) -> int:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 25:
		tries += 1
		var s := rng.randf_range(0.0, world.track.length)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var out := lerpf(near, far, rng.randf() * rng.randf())
		if skip_stand and side > 0.0 and out < 22.0 and world.in_stand(s):
			continue
		var spot = world.beyond(s, side, out, clearance)
		if spot == null or in_hero_sight(spot):
			continue
		var sc := rng.randf_range(size.x, size.y)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.2), sc))
		var p: Vector3 = spot - Vector3.UP * sink
		world.cell(cells, p).add_baked(meshes[pick.call(rng)], Transform3D(basis, p))
		placed += 1
	return placed


## Scatters `count` of `meshes` over the far land (r from the centre between `r0` and `r1`
## beyond the track's reach) into the woods' sectors.
func scatter_far(woods: Array, meshes: Array, count: int, r0: float, r1: float, size: Vector2, pick: Callable) -> void:
	for i in count:
		var a := rng.randf() * TAU
		var r := world.reach + rng.randf_range(r0, r1)
		var x := world.centre.x + cos(a) * r
		var z := world.centre.z + sin(a) * r
		if not world.clear_of_road(Vector3(x, 0.0, z), 20.0) or in_hero_sight(Vector3(x, 0.0, z)):
			continue
		var sc := rng.randf_range(size.x, size.y)
		var at := Vector3(x, world.ground_at(x, z) - 0.3, z)
		woods[world.sector_of(at)].add_baked(meshes[pick.call(rng)], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), at))


## Broadleaf, pine, bush and a low-poly far pine. `snow` caps the pines and bushes white.
static func tree_meshes(leaf := Color(0.30, 0.56, 0.18), snow := false) -> Array:
	var trunk := Color(0.42, 0.28, 0.17, 0.0)
	var white := Color(0.95, 0.97, 1.0)
	var kit := MeshKit3D.new()
	kit.ao_y0 = 1.0
	kit.ao_y1 = 5.5
	kit.ao_min = 0.5
	kit.add(MeshKit3D.cylinder(0.18, 0.3, 2.4, 5), MeshKit3D.xf(Vector3(0, 1.2, 0)), trunk)
	for b in [[Vector3(0, 3.6, 0), 1.95], [Vector3(1.1, 3.0, 0.3), 1.35], [Vector3(-1.0, 3.1, -0.4), 1.4],
			[Vector3(0.1, 4.6, -0.1), 1.3]]:
		var c := leaf.lerp(Color(0.45, 0.68, 0.22), clampf((b[0].y - 3.0) / 1.7, 0.0, 1.0))
		if snow:
			c = c.lerp(white, 0.5 if b[0].y > 4.0 else 0.15)
		c.a = clampf(b[0].y / 5.0, 0.0, 1.0)
		kit.add(MeshKit3D.sphere(b[1], 7, 3), MeshKit3D.xf(b[0]), c)
	var broad := kit.commit()
	if snow:
		broad = snow_cap(broad, 0.3)
	kit = MeshKit3D.new()
	kit.ao_y0 = 0.5
	kit.ao_y1 = 7.0
	kit.ao_min = 0.45
	kit.add(MeshKit3D.cylinder(0.15, 0.25, 1.6, 5), MeshKit3D.xf(Vector3(0, 0.8, 0)), trunk)
	for k in 3:
		var y := 1.4 + k * 1.7
		var c := Color(0.16, 0.40, 0.22, clampf(y / 6.0, 0.0, 1.0)).lerp(Color(0.24, 0.5, 0.26, 1.0), k / 3.0)
		kit.add(MeshKit3D.cylinder(0.0, 2.1 - k * 0.55, 2.6, 7), MeshKit3D.xf(Vector3(0, y + 1.3, 0)), c)
	var pine := kit.commit()
	if snow:
		pine = snow_cap(pine, 0.45)
	kit = MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 1.4
	kit.ao_min = 0.5
	for b in [[Vector3(0, 0.6, 0), 0.9], [Vector3(0.7, 0.45, 0.2), 0.65]]:
		var c := Color(0.34, 0.58, 0.2, 0.5) if not snow else Color(0.88, 0.92, 0.98, 0.3)
		kit.add(MeshKit3D.sphere(b[1], 6, 3), MeshKit3D.xf(b[0]), c)
	var bush := kit.commit()
	if snow:
		bush = snow_cap(bush, 0.2)
	kit = MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 6.0
	kit.ao_min = 0.5
	kit.add(MeshKit3D.cylinder(0.0, 2.0, 3.6, 5), MeshKit3D.xf(Vector3(0, 2.6, 0)), Color(0.18, 0.42, 0.22, 0.6))
	kit.add(MeshKit3D.cylinder(0.0, 1.4, 2.8, 5), MeshKit3D.xf(Vector3(0, 4.6, 0)),
		Color(0.24, 0.5, 0.26, 1.0) if not snow else Color(0.92, 0.95, 1.0, 1.0))
	var far := kit.commit()
	return [broad, pine, bush, far]


## `mesh` with snow lying on it: every face whose normal points up more than `from` turns
## white (alpha kept). No extra geometry or overdraw.
static func snow_cap(mesh: ArrayMesh, from: float, snow := Color(0.95, 0.97, 1.0)) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in colors.size():
		var c := colors[i]
		var k := smoothstep(from, from + 0.2, normals[i].y)
		var w := c.lerp(snow, k)
		w.a = c.a
		colors[i] = w
	arrays[Mesh.ARRAY_COLOR] = colors
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## A chunky low-poly boulder in `color` (rough sphere, squashed), for props (alpha 0).
static func rock_mesh(color: Color, seed_value: int, squash := 0.7) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var base := MeshKit3D.sphere(1.0, 7, 4).get_mesh_arrays()
	var verts: PackedVector3Array = base[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = base[Mesh.ARRAY_INDEX]
	# Jitter each distinct position once, so the facets stay closed.
	var moved := {}
	for i in verts.size():
		var key := Vector3i(roundi(verts[i].x * 100), roundi(verts[i].y * 100), roundi(verts[i].z * 100))
		if not moved.has(key):
			moved[key] = verts[i] * r.randf_range(0.8, 1.15)
		var v: Vector3 = moved[key]
		verts[i] = Vector3(v.x, v.y * squash, v.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(0, idx.size(), 3):
		var a := verts[idx[k]]
		var b := verts[idx[k + 1]]
		var c := verts[idx[k + 2]]
		var n := (c - a).cross(b - a).normalized()
		var shade := lerpf(0.7, 1.05, clampf(((a + b + c) / 3.0).y + 0.5, 0.0, 1.0))
		for v in [a, b, c]:
			st.set_color(Color(color.r * shade, color.g * shade, color.b * shade, 0.0))
			st.set_normal(n)
			st.add_vertex(v + Vector3.UP * 0.3 * squash)
	return st.commit()
