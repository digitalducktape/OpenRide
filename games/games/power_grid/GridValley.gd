class_name GridValley
extends RefCounted
## The valley town at dusk (#81; ART_BIBLE.md): one illustrated scene, drawn in code into a
## `MeshBatch2D` batch (Safe Cracker's batcher, read only). `paint` draws everything that doesn't
## move, twice: once in the dusk palette and once in the night palette, and `GridStage` bakes both
## and blends them in one shader as the evening goes on. Every window, lamp and bulb sits dark in
## the bake; `lights` lists the same layout for the additive light mesh (`GridLights`), so a
## district coming on is one uniform, not a redraw.
##
## Depth, back to front: sky, far mountains, forested hills, the valley floor and the river, the
## stadium, the funfair, the houses, the road and its lamps, the pylons, the near hillside. The
## generator shed on the hillside is `GridShed`'s. Names are plain descriptions: nothing here
## refers to any real town, fair, stadium or maker.
##
## The layout and the entry points live here; the painting is GridValleyPaint's and the lights
## GridValleyLights'.

const SIZE := Vector2(1920, 1080)
## The scene is painted this far past each side of the stage (#57: the bike shows 68 px more each
## side). Props stay on the 1920 stage.
const BLEED := 160.0
const WIDE := Vector2(SIZE.x + 2.0 * BLEED, SIZE.y)
const LEFT := -BLEED
const RIGHT := SIZE.x + BLEED

const FLOOR_Y := 556.0  ## where the valley floor meets the hills
const SUN := Vector2(1210, 470)  ## the sun's glow, behind the mountains
## The far ridge's highest point: nothing tall stands under the HUD's side panels.
const RIDGE_TOP := 352.0

## The road, left to right: the southern edge of the town (cars and lamps are never hidden).
const ROAD := [Vector2(-160, 960), Vector2(420, 950), Vector2(690, 912), Vector2(860, 884), Vector2(1060, 866), Vector2(1280, 860),
	Vector2(1500, 868), Vector2(1760, 892), Vector2(2080, 932)]
## The river's centre line and half width, from the far hills to the near bank.
const RIVER := [[Vector2(1262, 556), 5.0], [Vector2(1306, 612), 9.0], [Vector2(1290, 680), 14.0], [Vector2(1344, 760), 21.0],
	[Vector2(1332, 858), 32.0], [Vector2(1404, 930), 50.0], [Vector2(1490, 1010), 78.0], [Vector2(1570, 1100), 118.0]]
const BRIDGE_AT := Vector2(1333, 860)

## The pylons, near to far: [foot, height]. The first stands by the shed; they march down the
## valley behind the town, smaller as they go.
const PYLONS := [[Vector2(716, 880), 300.0], [Vector2(934, 690), 172.0], [Vector2(1268, 640), 124.0], [Vector2(1470, 620), 100.0],
	[Vector2(1668, 604), 84.0]]
const SHED_FEED := Vector2(624, 560)  ## where the line leaves the shed's gable
## Each district's feeder: which pylon it leaves, and where it lands in the district.
const FEEDERS := [[1, Vector2(836, 690)], [1, Vector2(1040, 856)], [2, Vector2(1160, 640)], [4, Vector2(1664, 690)]]

const WHEEL_AT := Vector2(1150, 652)  ## the funfair's big wheel
const WHEEL_R := 106.0
const WHEEL_SPOKES := 12
const STADIUM_AT := Vector2(1646, 772)
const STADIUM_R := Vector2(226, 76)
const MASTS := [Vector2(1442, 760), Vector2(1546, 714), Vector2(1746, 714), Vector2(1850, 760)]
const MAST_H := 128.0
const CAROUSEL_AT := Vector2(1062, 822)
const TENTS := [[Vector2(1250, 800), 54.0, 0], [Vector2(1000, 742), 44.0, 1]]
const CHURCH_AT := Vector2(806, 776)

## [dusk, night] for every colour in the scene.
const PALETTE := {
	"sky_top": [Color("23306a"), Color("050a1e")],
	"sky_mid": [Color("6a4f8f"), Color("0c1536")],
	"sky_low": [Color("e07f72"), Color("1a2452")],
	"horizon": [Color("ffc677"), Color("2f3a72")],
	"sun": [Color(1.0, 0.86, 0.55, 0.85), Color(0.4, 0.5, 0.8, 0.0)],
	"cloud": [Color("8a5f8c"), Color("131c40")],
	"cloud_rim": [Color(1.0, 0.72, 0.5, 0.75), Color(0.4, 0.5, 0.75, 0.16)],
	"far": [Color("8d6c9e"), Color("1a2148")],
	"far_low": [Color("c98f8c"), Color("232c58")],
	"snow": [Color("ffd9c0"), Color("56649a")],
	"mid": [Color("5a4a7e"), Color("121838")],
	"mid_low": [Color("80607f"), Color("182046")],
	"hill": [Color("394560"), Color("0d1330")],
	"hill_low": [Color("4c5868"), Color("111a38")],
	"tree": [Color("2c3a4e"), Color("0a1028")],
	"tree_hi": [Color("4a5f60"), Color("121a38")],
	"floor": [Color("5e6c5c"), Color("141e34")],
	"floor_low": [Color("46584e"), Color("0f182c")],
	"field_a": [Color(0.62, 0.62, 0.38, 0.5), Color(0.12, 0.16, 0.26, 0.5)],
	"field_b": [Color(0.32, 0.44, 0.34, 0.5), Color(0.06, 0.11, 0.2, 0.5)],
	"hedge": [Color("2e4040"), Color("0b1226")],
	"road": [Color("6d6068"), Color("20233a")],
	"road_edge": [Color("8a7b78"), Color("2b2f4a")],
	"river_far": [Color("ffc98e"), Color("2c3770")],
	"river_near": [Color("8a6a96"), Color("111a40")],
	"river_bank": [Color("3d4a48"), Color("0c1428")],
	"wall_a": [Color("c9a78e"), Color("2c2f4c")],
	"wall_b": [Color("b58f84"), Color("272a46")],
	"wall_c": [Color("a8a39a"), Color("2a2f4a")],
	"wall_shade": [Color("6d5868"), Color("171a32")],
	"roof_a": [Color("7a4150"), Color("1c1a33")],
	"roof_b": [Color("54506e"), Color("15172e")],
	"roof_c": [Color("8a5a48"), Color("201c33")],
	"roof_hi": [Color(1.0, 0.76, 0.55, 0.5), Color(0.5, 0.58, 0.8, 0.14)],
	"glass": [Color("3a3a58"), Color("0c0e20")],
	"stone": [Color("9a8a88"), Color("262a44")],
	"stone_dark": [Color("665866"), Color("171a30")],
	"steel": [Color("3a3648"), Color("0b0e20")],
	"steel_hi": [Color("7a6a78"), Color("232a48")],
	"wire": [Color(0.12, 0.1, 0.16, 0.85), Color(0.03, 0.04, 0.09, 0.9)],
	"stand": [Color("6a5f70"), Color("181c34")],
	"stand_lo": [Color("4a4358"), Color("11142a")],
	"pitch": [Color("5e8058"), Color("14283a")],
	"pitch_alt": [Color("6b8d60"), Color("183040")],
	"line": [Color(0.95, 0.92, 0.85, 0.6), Color(0.5, 0.56, 0.7, 0.3)],
	"tent_a": [Color("c0525c"), Color("2c1c38")],
	"tent_b": [Color("e8d4b4"), Color("383a56")],
	"tent_c": [Color("4d6d9a"), Color("1a2444")],
	"yard": [Color("7c6a60"), Color("1a1c30")],
	"near": [Color("35463f"), Color("0c1424")],
	"near_low": [Color("212f30"), Color("070c18")],
	"near_hi": [Color("6e7a50"), Color("182638")],
	"grass": [Color("4e6248"), Color("101c2c")],
	"grass_hi": [Color("8a8f58"), Color("1c2c3c")],
	"fence": [Color("4a3c3c"), Color("0e101e")],
	"vignette": [Color(0.09, 0.05, 0.14, 0.62), Color(0.01, 0.01, 0.05, 0.72)],
}

const NIGHT_LIFT := Color("3a4c86")

static var _layout_cache := {}


## The palette for a bake: `night` 0 is dusk, 1 is night.
static func palette(night: int) -> Dictionary:
	var out := {}
	for key in PALETTE:
		var col: Color = PALETTE[key][night]
		# Moonlight lifts the whole night a little, so the land still reads under the lights.
		out[key] = Color(col.lerp(NIGHT_LIFT, 0.13), col.a) if night == 1 else col
	return out


## The road's y at `x`, and points along it (shared by the lamps, the cars and the bake).
static func road_y(x: float) -> float:
	for k in ROAD.size() - 1:
		var a: Vector2 = ROAD[k]
		var b: Vector2 = ROAD[k + 1]
		if x <= b.x:
			return lerpf(a.y, b.y, smoothstep(a.x, b.x, x) * 0.5 + inverse_lerp(a.x, b.x, x) * 0.5)
	return (ROAD[ROAD.size() - 1] as Vector2).y


## Width of the road at `y`: it's nearer, so wider, toward the bottom of the frame.
static func road_w(y: float) -> float:
	return lerpf(16.0, 40.0, clampf((y - 860.0) / 100.0, 0.0, 1.0))


## A pylon's top (the arm's centre).
static func pylon_top(i: int) -> Vector2:
	var p: Array = PYLONS[i]
	return (p[0] as Vector2) - Vector2(0, float(p[1]))


## The points of a wire from `a` to `b` sagging by `sag` px at the middle.
static func catenary(a: Vector2, b: Vector2, sag: float, segs := 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in segs + 1:
		var t := float(k) / segs
		out.append(a.lerp(b, t) + Vector2(0, sag * 4.0 * t * (1.0 - t)))
	return out


## Every wire: {points, channel}: channel 0 is the trunk, 1-4 are the feeders of districts 0-3.
static func wires() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var prev := SHED_FEED
	for i in PYLONS.size():
		var top := pylon_top(i)
		var span := prev.distance_to(top)
		for side in [-1.0, 1.0]:
			var w: float = float(PYLONS[i][1]) * 0.15 * side
			var from := prev + (Vector2(0, 0) if i == 0 else Vector2(float(PYLONS[i - 1][1]) * 0.15 * side, 0))
			out.append({"points": catenary(from, top + Vector2(w, 0), span * 0.05), "channel": 0})
		prev = top
	for d in FEEDERS.size():
		var from := pylon_top(int(FEEDERS[d][0])) + Vector2(0, 6)
		var to: Vector2 = FEEDERS[d][1]
		out.append({"points": catenary(from, to, from.distance_to(to) * 0.05, 10), "channel": d + 1})
	return out


## The houses, back row first: {at (foot centre), w, h, roof, wall, kind, windows: [Rect2]}.
static func houses() -> Array:
	if _layout_cache.has("houses"):
		return _layout_cache.houses
	var rng := RandomNumberGenerator.new()
	rng.seed = 81
	var out := []
	# Rows from the back of the town to the road, each a little larger and wider.
	var rows := [[636.0, 790.0, 1020.0, 32.0], [664.0, 762.0, 1020.0, 38.0], [698.0, 738.0, 960.0, 46.0], [738.0, 716.0, 950.0, 54.0],
		[784.0, 700.0, 960.0, 62.0], [836.0, 690.0, 980.0, 72.0]]
	for row in rows:
		var y: float = row[0]
		var x: float = row[1] + rng.randf_range(0.0, 14.0)
		var w0: float = row[3]
		while x < row[2]:
			var w := w0 * rng.randf_range(0.85, 1.2)
			var front := rng.randf() < 0.55
			var at := Vector2(x + w * 0.5, y + rng.randf_range(-3.0, 3.0))
			x += w * rng.randf_range(1.1, 1.42)
			if absf(at.x - CHURCH_AT.x - 8.0) < 86.0 and at.y > CHURCH_AT.y - 62.0 and at.y < CHURCH_AT.y + 8.0:
				continue
			var h := w * rng.randf_range(0.62, 0.82)
			out.append({"at": at, "w": w, "h": h, "roof": w * rng.randf_range(0.42, 0.56), "front": front,
				"wall": ["wall_a", "wall_b", "wall_c"][rng.randi_range(0, 2)],
				"tile": ["roof_a", "roof_b", "roof_c"][rng.randi_range(0, 2)],
				"windows": _windows(rng, at, w, h, front), "chimney": rng.randf() < 0.6, "flip": rng.randf() < 0.5})
	_layout_cache.houses = out
	return out


static func _windows(rng: RandomNumberGenerator, at: Vector2, w: float, h: float, front: bool) -> Array:
	var out := []
	var ww := clampf(w * 0.17, 5.0, 12.0)
	var wh := ww * 1.3
	var floors := 2 if h > 30.0 else 1
	var across := 2 if front else 3
	for f in floors:
		for k in across:
			if f == 0 and k == across / 2 and h > 30.0:
				continue  # the door
			var cx := at.x + (float(k) + 0.5 - across * 0.5) * (w / across)
			var cy := at.y - h * (0.28 + 0.44 * f)
			out.append(Rect2(cx - ww * 0.5, cy - wh * 0.5, ww, wh))
	return out


## The farm on the near bank, right of the river: its windows light with the houses.
static func cottages() -> Array:
	if _layout_cache.has("cottages"):
		return _layout_cache.cottages
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var out := []
	for c in [[Vector2(1742, 1010), 118.0, 76.0, "wall_a", "roof_a", false], [Vector2(1860, 998), 84.0, 58.0, "wall_c", "roof_b", true]]:
		var at: Vector2 = c[0]
		out.append({"at": at, "w": c[1], "h": c[2], "roof": float(c[1]) * 0.44, "front": c[5], "wall": c[3], "tile": c[4],
			"windows": _windows(rng, at, c[1], c[2], c[5]), "chimney": true, "flip": true})
	_layout_cache.cottages = out
	return out


## The street lamps along the road, left to right.
static func lamps() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var x := 800.0
	while x < 1880.0:
		if absf(x - BRIDGE_AT.x) > 50.0:
			out.append(Vector2(x, road_y(x)))
		x += 84.0
	return out


## Everything that doesn't move, in the palette `night` (0 dusk, 1 night), stage coordinates
## (GridValleyPaint).
static func paint(m: MeshBatch2D, night: int) -> void:
	GridValleyPaint.paint(m, night)


## The corners pulled in toward the town. Painted last, over the shed too (GridValleyPaint).
static func vignette(m: MeshBatch2D, night: int) -> void:
	GridValleyPaint.vignette(m, night)


## The river's two banks at `k`, for the bake and the shimmer mesh.
static func river_edges() -> Array[PackedVector2Array]:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for k in RIVER.size() - 1:
		var a: Array = RIVER[k]
		var b: Array = RIVER[k + 1]
		for s in 6:
			var t := s / 6.0
			var e := t * t * (3.0 - 2.0 * t)
			var c := (a[0] as Vector2).lerp(b[0], e)
			var w: float = lerpf(a[1], b[1], t)
			left.append(c - Vector2(w, 0))
			right.append(c + Vector2(w, 0))
	var last: Array = RIVER[RIVER.size() - 1]
	left.append((last[0] as Vector2) - Vector2(last[1], 0))
	right.append((last[0] as Vector2) + Vector2(last[1], 0))
	return [left, right]


## A stall's foot.
static func stall_at(k: int) -> Vector2:
	return Vector2(1140 + k * 52.0, 846.0)


static func church_windows() -> Array[Rect2]:
	var c := CHURCH_AT
	var out: Array[Rect2] = [Rect2(c + Vector2(-33, -72), Vector2(14, 22))]
	for k in 4:
		out.append(Rect2(c + Vector2(4 + k * 15, -36), Vector2(8, 20)))
	return out


static func lamp_head(at: Vector2) -> Vector2:
	var foot: Vector2 = at + Vector2(0, road_w(at.y) * 0.5 + 3.0)
	var h := lerpf(38.0, 52.0, clampf((at.y - 860.0) / 90.0, 0.0, 1.0))
	return foot + Vector2(-8, -h - 1.0)


## The near hill's crest: high under the shed, down to the bottom of the frame by the river.
static func near_y(x: float) -> float:
	if x < 640.0:
		return 886.0 + 8.0 * sin(x * 0.012)
	var t := clampf((x - 640.0) / 860.0, 0.0, 1.0)
	return lerpf(886.0 + 8.0 * sin(640.0 * 0.012), 1040.0, t * t * (3.0 - 2.0 * t) * 0.3 + t * 0.7) + 5.0 * sin(x * 0.017)


## Every light in the town (`m` is a `GridLights`), each on its district's channel (GridValleyLights).
static func lights(m: GridLights) -> void:
	GridValleyLights.lights(m)


## The wheel's lamps, on the rim, for the wheel's own light mesh (GridValleyLights).
static func wheel_lights(m: GridLights) -> void:
	GridValleyLights.wheel_lights(m)


## The wheel's frame, for either palette: `ink` is its colour (GridValleyPaint).
static func paint_wheel(m: MeshBatch2D, ink: Color) -> void:
	GridValleyPaint.paint_wheel(m, ink)
