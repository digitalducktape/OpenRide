class_name KartRoadMeshes
extends RefCounted
## Kart Race's road surface meshes (#43), built once per track by KartWorld.build: the road
## (one unshaded mesh painted from track-space UVs), the boost pads and item rows painted over
## it, the barriers, and the skirt from the barriers' feet under the land. Pure builders: no
## nodes, no state.

const ROAD_STEP := 2.0  ## metres between mesh rows along the track
const SKIRT := 8.0  ## the skirt from the barrier's foot out and down under the land
const WALL_HEIGHT := 0.95


## Rows every ROAD_STEP metres, columns at the road edges, kerbs and barrier feet. UV = (d, s),
## UV2.x = half-width, COLOR = (racing line, corner strength).
static func road(track: KartTrackModel) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := maxi(8, roundi(track.length / ROAD_STEP))
	var step := track.length / rows
	var kerb := KartTrackModel.KERB_WIDTH
	var cols := []  # per row: [s, hw, [d...], color]
	for i in rows + 1:
		var s := i * step
		var hw := track.half_width(s)
		var edge := hw + track.verge
		var line := clampf(track.racing_line(s), -10.0, 10.0)
		var corner := clampf(absf(track.curvature(s)) * 45.0, 0.0, 1.0)
		cols.append([s, hw, [-edge, -hw - kerb, -hw, 0.0, hw, hw + kerb, edge],
			Color((line + 10.0) / 20.0, corner, 0.0)])
	for i in rows:
		var a: Array = cols[i]
		var b: Array = cols[i + 1]
		for c in 6:
			var p := [[a, c], [b, c], [b, c + 1], [a, c], [b, c + 1], [a, c + 1]]
			for v in p:
				var row: Array = v[0]
				var d: float = row[2][v[1]]
				var s: float = row[0]
				st.set_color(row[3])
				st.set_uv(Vector2(d, s))
				st.set_uv2(Vector2(row[1], 0.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(track.position_at(fmod(s, track.length), d))
	return st.commit()


## Boost pads and item rows: quads 3 cm over the road, painted by pads.gdshader. UV = (across,
## along) 0-1; COLOR.r = kind (0 pad, 1 item row), COLOR.g = length / 20 m.
static func paint(track: KartTrackModel) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for z in track.zones:
		var kind := -1.0
		var d0 := 0.0
		var d1 := 0.0
		var s0 := float(z.s0)
		var s1 := float(z.s1)
		if z.type == "boost":
			kind = 0.0
			var c := float(z.get("d", 0.0))
			var w := float(z.get("w", 1.4))
			d0 = c - w
			d1 = c + w
		elif z.type == "items":
			kind = 1.0
			var mid := s0 + track.delta(s0, s1) * 0.5
			s0 = mid - 1.1
			s1 = mid + 1.1
			var hw := track.half_width(track.wrap(mid))
			d0 = -hw + 0.4
			d1 = hw - 0.4
		if kind < 0.0:
			continue
		any = true
		var length := track.delta(s0, s1)
		if length < 0.0:
			length += track.length
		var steps := maxi(1, ceili(length / 2.0))
		for k in steps:
			var a := s0 + length * k / steps
			var b := s0 + length * (k + 1) / steps
			var va := float(k) / steps
			var vb := float(k + 1) / steps
			var col := Color(kind, length / 20.0, 0.0)
			var quad := [[a, d0, 0.0, va], [b, d0, 0.0, vb], [b, d1, 1.0, vb], [a, d0, 0.0, va], [b, d1, 1.0, vb], [a, d1, 1.0, va]]
			for q in quad:
				st.set_color(col)
				st.set_uv(Vector2(q[2], q[3]))
				st.set_normal(Vector3.UP)
				st.add_vertex(track.position_at(track.wrap(q[0]), q[1]) + Vector3.UP * 0.03)
	return st.commit() if any else null


## The barrier: one mesh in props_mat, lit by the sun like scenery (a 0.08 self-glow only). Its
## profile from the road: a dark foot (AO, or tyres), panels alternating in the theme's two
## colours with dark seams every row, the rail as a stripe, a chamfered lighter cap, and a shaded
## back. Per theme (`wall_style` in `look`, KartLook's values): Meadow's foot is a row of tyres,
## Canyon's panels are timber planks, Harbor's quay wall is stone-footed, and Frost's cap is a
## fat lip of snow.
static func walls(track: KartTrackModel, look: Dictionary) -> ArrayMesh:
	var kit := MeshKit3D.new()
	var rows := maxi(8, roundi(track.length / ROAD_STEP))
	var step := track.length / rows
	var style := str(look.get("wall_style", ""))
	var h := WALL_HEIGHT + 0.14
	var cap: Color = look.get("wall_cap", Color(0.9, 0.9, 0.92))
	var foot_c: Color = look.get("wall_foot", Color(0.2, 0.2, 0.22))
	var rail: Color = look.wall_rail
	var lip := 0.1 if style == "snow" else 0.0
	# (out, up) from the barrier's face at the road edge, outward; one colour per segment
	# (null: the panel's colour). The foot runs to 0.2 m, the stripe sits under the cap.
	var prof := [Vector2(0.0, 0.0), Vector2(0.0, 0.2), Vector2(0.0, h - 0.17), Vector2(0.0, h - 0.07),
		Vector2(0.07 - lip, h + lip * 0.6), Vector2(0.38 + lip, h + lip * 0.6), Vector2(0.45, h - 0.07), Vector2(0.45, 0.0)]
	var seg_cols := [foot_c, null, rail, cap.darkened(0.06), cap, cap.darkened(0.2), null]
	for i in rows:
		var s0 := i * step
		var s1 := fmod((i + 1) * step, track.length)
		var panel: Color = look.wall_a if (i >> 1) & 1 == 0 else look.wall_b
		for side: float in [-1.0, 1.0]:
			var e0 := track.half_width(s0) + track.verge
			var e1 := track.half_width(s1) + track.verge
			for j in seg_cols.size():
				var c: Color = panel if seg_cols[j] == null else seg_cols[j]
				if j == seg_cols.size() - 1:
					c = panel.darkened(0.4)
				c.a = 0.08
				var p0: Vector2 = prof[j]
				var p1: Vector2 = prof[j + 1]
				var a0 := track.position_at(s0, side * (e0 + p0.x)) + Vector3.UP * p0.y
				var a1 := track.position_at(s0, side * (e0 + p1.x)) + Vector3.UP * p1.y
				var b0 := track.position_at(s1, side * (e1 + p0.x)) + Vector3.UP * p0.y
				var b1 := track.position_at(s1, side * (e1 + p1.x)) + Vector3.UP * p1.y
				# Wound so each face's front looks out of the barrier's profile (the old wall's were
				# inside out: the road saw its shaded back).
				if side > 0.0:
					kit.quad(b0, b1, a1, a0, c)
				else:
					kit.quad(a0, a1, b1, b0, c)
			# Painted detail on the face, a centimetre proud: a seam at the row's start, and the
			# theme's bands (tyres' treads, timber's plank joints).
			var lines: Array = []  # [up0, up1, s_len (0 = the whole row), colour]
			lines.append([0.2, h - 0.17, 0.08, panel.darkened(0.45)])
			match style:
				"tyres":
					lines.append([0.08, 0.11, 0.0, Color(0.32, 0.32, 0.35)])
				"timber":
					for k in [0.43, 0.66]:
						lines.append([k - 0.012, k + 0.012, 0.0, panel.darkened(0.35)])
				"snow":
					lines.append([0.2, 0.26, 0.0, foot_c.lightened(0.25)])
			for ln: Array in lines:
				var len: float = ln[2] if ln[2] > 0.0 else step
				var sa := s0
				var sb := fmod(s0 + len, track.length)
				var col: Color = ln[3]
				col.a = 0.08
				var ea := track.half_width(sa) + track.verge - 0.01
				var eb := track.half_width(sb) + track.verge - 0.01
				var lo := Vector3.UP * float(ln[0])
				var hi := Vector3.UP * float(ln[1])
				var a := track.position_at(sa, side * ea)
				var b := track.position_at(sb, side * eb)
				if side > 0.0:
					kit.quad(b + lo, b + hi, a + hi, a + lo, col)
				else:
					kit.quad(a + lo, a + hi, b + hi, b + lo, col)
	return kit.commit()


## From the barrier's foot out and down under the land, so the land never shows a seam.
static func skirt(track: KartTrackModel, terrain: KartTerrain) -> ArrayMesh:
	var rows := maxi(8, roundi(track.length / ROAD_STEP))
	var step := track.length / rows
	var ends := []
	for i in rows:
		var s := i * step
		var row := []
		for side: float in [-1.0, 1.0]:
			var e := track.half_width(s) + track.verge + 0.45
			var foot := track.position_at(s, side * e)
			var end := track.position_at(s, side * (e + SKIRT))
			end.y = minf(foot.y - 0.5, terrain.height_at(end.x, end.z) - 0.35)
			row.append([foot, end])
		ends.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rows:
		var a: Array = ends[i]
		var b: Array = ends[(i + 1) % rows]
		for side in 2:
			var p0: Vector3 = a[side][0]
			var p1: Vector3 = b[side][0]
			var p2: Vector3 = b[side][1]
			var p3: Vector3 = a[side][1]
			# Lit as land: the normal faces up whichever way the quad winds.
			var n := (p1 - p0).cross(p3 - p0).normalized()
			if n.y < 0.0:
				n = -n
			for v in [p0, p1, p2, p0, p2, p3]:
				st.set_color(Color.WHITE)
				st.set_normal(n)
				st.add_vertex(v)
	return st.commit()
