class_name LaunchPad
extends Node2D
## What stands on the ground and moves or changes (#82; ART_BIBLE.md §6): the service tower with
## its swing arms and fuel hose, the mission clock, the steam at the pad, the smoke bank at
## ignition, beacons and the place's foreground. Scrolls down with the ground when the camera
## rides up. Everything is painted once per mark or place; a frame moves nodes and sets uniforms.
##
## `back` draws behind the rocket, this node's own children in front of it.
##
## Silhouette: the smoke is a low, wide bank spreading left and right, and steam is short flat
## wisps. Neither ever forms a ball with a tail.

const CLOCK_RECT := Rect2(130, 372, 380, 176)  ## the mission clock's board
const TOWER_HALF := 48.0  ## the lattice, either side of LaunchPlaces.TOWER_X
const ARM_RETRACT_AT := 5  ## seconds on the count when the arms swing back
const HOSE_DROP_AT := 3  ## and when the fuel hose lets go

static var _puff: Texture2D
static var _dot: Texture2D

var back: Node2D  ## behind the rocket
var tower: Node2D
var hose: Node2D
var arms: Array[Node2D] = []
var clock_text: Label
var clock_caption: Label
var steam: Array[CPUParticles2D] = []
var smoke: Array[CPUParticles2D] = []
var trench_glow: Node2D
var foreground: Node2D
var snow: CPUParticles2D
var dust: CPUParticles2D
var lights: Node2D
var _mark := 0
var _place := 0
var _t := 0.0
var _clock_shown := -1


func _init() -> void:
	name = "Pad"
	back = Node2D.new()
	back.name = "PadBack"
	tower = PaintLayer.new()
	tower.name = "Tower"
	tower.paint = func(ci: CanvasItem) -> void: _tower_mesh().draw_on(ci)
	back.add_child(tower)
	for i in 2:
		var arm: Node2D = PaintLayer.new()
		arm.name = "Arm%d" % i
		arm.paint = _paint_arm.bind(i)
		back.add_child(arm)
		arms.append(arm)
	lights = PaintLayer.new()
	lights.name = "Beacons"
	lights.paint = _paint_lights
	back.add_child(lights)
	_build_clock()
	hose = PaintLayer.new()
	hose.name = "Hose"
	hose.paint = _paint_hose
	var flow := ShaderMaterial.new()
	flow.shader = preload("res://games/ready_for_launch/shaders/rfl_flow.gdshader")
	hose.material = flow
	back.add_child(hose)
	foreground = PaintLayer.new()
	foreground.name = "Foreground"
	foreground.paint = _paint_foreground
	for i in 2:
		var s := _steam_emitter(i)
		add_child(s)
		steam.append(s)
	trench_glow = PaintLayer.new()
	trench_glow.name = "TrenchGlow"
	trench_glow.paint = func(ci: CanvasItem) -> void:
		var m := MeshBatch2D.new()
		m.glow(Vector2(LaunchPlaces.PAD_X, LaunchPlaces.PAD_Y + 44.0), Vector2(520.0, 150.0), Color(1.0, 0.68, 0.3, 0.85), 10)
		m.flush(ci)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	trench_glow.material = add
	trench_glow.modulate.a = 0.0
	add_child(trench_glow)
	for side in [-1.0, 1.0]:
		var b := _smoke_emitter(side)
		add_child(b)
		smoke.append(b)
	add_child(foreground)
	snow = _weather("Snow", 60, Vector2(-14.0, 80.0), Color(1, 1, 1, 0.85), 0.5, Rect2(960, 480, 1120, 460))
	dust = _weather("Dust", 30, Vector2(60.0, -3.0), Color(1.0, 0.86, 0.68, 0.34), 0.3, Rect2(960, 860, 1120, 130))


## A new launch: mark `mark` on place `place`, everything back where it stands before fuelling.
func set_stage(mark: int, place: int) -> void:
	_mark = mark
	_place = place
	tower.queue_redraw()
	foreground.queue_redraw()
	hose.queue_redraw()
	for i in arms.size():
		arms[i].queue_redraw()
		arms[i].position = Vector2.ZERO
		arms[i].scale = Vector2.ONE
		arms[i].visible = i < 2
	lights.queue_redraw()
	hose.rotation = 0.0
	hose.visible = true
	hose.modulate.a = 1.0
	var id: String = LaunchPlaces.place(place).id
	snow.emitting = id == "polar"
	snow.visible = snow.emitting
	dust.emitting = id == "desert"
	dust.visible = dust.emitting
	var cold: Color = Color(1, 1, 1, 0.3).lerp(LaunchPlaces.place(place).sun_col, 0.25)
	for s in steam:
		s.color_ramp = ramp([Color(cold, 0.0), Color(cold, cold.a), Color(cold, 0.0)])
		s.emitting = true
	var tint: Color = (LaunchPlaces.place(place).cloud as Color)
	for b in smoke:
		b.emitting = false
		var g := ramp([Color(1.0, 0.8, 0.55, 0.95), Color(tint.lightened(0.3), 0.95), Color(tint, 0.85), Color(tint.darkened(0.14), 0.0)])
		g.offsets = PackedFloat32Array([0.0, 0.14, 0.6, 1.0])
		b.color_ramp = g
	trench_glow.modulate.a = 0.0
	set_clock(-1, 0)


## How much fuel is going through the hose: 0 none, 1 full flow.
func set_flow(flow: float) -> void:
	(hose.material as ShaderMaterial).set_shader_parameter("flow", flow)


## The count's moving parts, at `n` seconds to go.
func on_count(n: int) -> void:
	if n == ARM_RETRACT_AT:
		var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		for a in arms:
			t.tween_property(a, "scale:x", 0.22, 1.6)
	if n == HOSE_DROP_AT:
		var t := create_tween().set_parallel()
		t.tween_property(hose, "rotation", deg_to_rad(-13.0), 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(hose, "modulate:a", 0.0, 0.8).set_delay(0.4)
	if n <= 3:
		GameTheme.pop(clock_text, 1.18)


## Ignition: the smoke bank rolls out both ways and the trench lights up.
func ignite(power: float) -> void:
	for b in smoke:
		b.emitting = power > 0.0
	for s in steam:
		s.emitting = false
	trench_glow.modulate.a = clampf(power, 0.0, 1.0)


## The mission clock: "T-0:37" while fuelling, "T-7" on the count, "LIFTOFF" at zero. `seconds`
## under 0 blanks it. Text only changes when the figure does.
func set_clock(seconds: int, phase: int) -> void:
	var key := seconds * 10 + phase
	if key == _clock_shown:
		return
	_clock_shown = key
	if seconds < 0:
		clock_text.text = "T-0:45"
		return
	match phase:
		LaunchLogic.Phase.FUEL:
			clock_text.text = "T-%d:%02d" % [seconds / 60, seconds % 60]
			clock_caption.text = tr("TO LIFTOFF")
		LaunchLogic.Phase.COUNT:
			clock_text.text = "T-%d" % seconds
			clock_caption.text = tr("GET READY")
		_:
			clock_text.text = tr("GO!")
			clock_caption.text = tr("PUSH")


## One frame on the ground: beacons blink.
func step(delta: float) -> void:
	_t += delta
	lights.modulate.a = 0.45 + 0.55 * step_wave(_t)


static func step_wave(t: float) -> float:
	return 1.0 if fmod(t, 1.4) < 0.5 else 0.0


## The rect of everything tall in this mark's tower, for the frame check.
static func tower_rect(mark: int) -> Rect2:
	var top := _tower_top(mark)
	return Rect2(LaunchPlaces.TOWER_X - 58.0, top - 30.0, 116.0, LaunchPlaces.PAD_Y - top + 30.0)


static func _tower_top(mark: int) -> float:
	return LaunchPlaces.PAD_Y - LaunchRocket.height_of(mark) + 30.0


func _tower_mesh() -> MeshBatch2D:
	var mark := _mark
	var place := _place
	return MeshBatch2D.built("rfl:tower:%d:%d" % [mark, place], func(m: MeshBatch2D) -> void: paint_tower(m, mark, place))


## The service tower: a square steel lattice with decks and a stair, red and white at the top.
static func paint_tower(m: MeshBatch2D, mark: int, place: int) -> void:
	var p := LaunchPlaces.place(place)
	var x := LaunchPlaces.TOWER_X
	var top := _tower_top(mark)
	var base := LaunchPlaces.PAD_Y + 26.0
	var half := TOWER_HALF
	var steel := Color("5b6275").lerp(p.dark, 0.25)
	var lit := steel.lerp(p.sun_col, 0.5)
	_floods(m, mark, p)
	m.soft_shadow(Rect2(x - 80.0, base - 6.0, 170.0, 20.0), 8.0, 14.0, Color(p.dark, 0.4))
	# The far legs, darker, then the bracing.
	m.line(Vector2(x - half + 16.0, top), Vector2(x - half + 16.0, base), 6.0, steel.darkened(0.3))
	m.line(Vector2(x + half - 16.0, top), Vector2(x + half - 16.0, base), 6.0, steel.darkened(0.3))
	var bay := 62.0
	var y := top
	var k := 0
	while y < base - 4.0:
		var y2 := minf(y + bay, base)
		var from := Vector2(x - half, y) if k % 2 == 0 else Vector2(x + half, y)
		var to := Vector2(x + half, y2) if k % 2 == 0 else Vector2(x - half, y2)
		m.line(from, to, 4.0, steel)
		m.line(Vector2(x - half, y2), Vector2(x + half, y2), 5.0, steel.lightened(0.1))
		# A deck every other bay, its edge catching the light.
		if k % 2 == 1:
			m.rect(Rect2(x - half - 8.0, y2 - 3.0, 2.0 * half + 16.0, 8.0), steel.lightened(0.14))
			m.line(Vector2(x - half - 8.0, y2 - 3.0), Vector2(x + half + 8.0, y2 - 3.0), 2.0, Color(lit, 0.8))
			m.circle(Vector2(x, y2 + 16.0), 5.0, Color(p.lit, 0.9), false)
		y = y2
		k += 1
	m.line(Vector2(x - half, top), Vector2(x - half, base), 9.0, steel.darkened(0.1))
	m.line(Vector2(x + half, top), Vector2(x + half, base), 9.0, steel.lightened(0.05))
	m.line(Vector2(x + half + 4.0, top), Vector2(x + half + 4.0, base), 2.5, Color(lit, 0.75))
	# The cap: a hazard-painted housing and a stiff lightning mast.
	var cap := Rect2(x - half - 10.0, top - 30.0, 2.0 * half + 20.0, 34.0)
	m.round_rect(cap, 5.0, Color("c8452f"), Color("9e3524"))
	m.rect(Rect2(cap.position.x, cap.position.y + 11.0, cap.size.x, 11.0), Color("efe7d8"))
	# The tower's foot on the apron, and the hose reel.
	m.rect_v(Rect2(x - half - 18.0, base - 18.0, 2.0 * half + 36.0, 28.0), steel.lightened(0.15), steel.darkened(0.22))


## The rocket's contact shadow on the deck, and two floodlight cones up its sides from the table's
## corners (faint at dawn, strong in the dark): what ties the hero to its place.
static func _floods(m: MeshBatch2D, mark: int, p: Dictionary) -> void:
	var cx := LaunchPlaces.PAD_X
	var deck := LaunchPlaces.PAD_Y
	var top := deck - LaunchRocket.height_of(mark) * 0.8
	var strength: float = p.flood
	for s in [-1.0, 1.0]:
		var lamp := Vector2(cx + s * 262.0, deck - 4.0)
		var clear := Color(p.lit, 0.0)
		var col := Color(p.lit, strength)
		m.quad4(lamp + Vector2(-8.0, 0.0), lamp + Vector2(8.0, 0.0), Vector2(cx + s * 30.0, top), Vector2(cx + s * 170.0, top), col, col, clear, clear)
	var half := LaunchRocket.half_width_of(mark)
	m.glow(Vector2(cx, deck + 4.0), Vector2(half + 20.0, 16.0), Color(p.dark, 0.6), 6)


## A swing arm from the tower to the rocket: a boxed truss with a hand rail.
func _paint_arm(ci: CanvasItem, i: int) -> void:
	var m := MeshBatch2D.new()
	var height := LaunchRocket.height_of(_mark)
	var y := LaunchPlaces.PAD_Y - height * (0.42 if i == 0 else 0.74)
	var from := LaunchPlaces.TOWER_X + TOWER_HALF
	# The arm reaches the hull at its height.
	var to := LaunchPlaces.PAD_X - (86.0 if i == 0 else 70.0) - _mark * (8.0 if i == 0 else 3.0)
	var steel := Color("6a7186")
	(ci as Node2D).position = Vector2(from, 0)
	var length := to - from
	m.rect_v(Rect2(0, y - 15.0, length, 6.0), steel.lightened(0.2), steel)
	m.rect_v(Rect2(0, y + 9.0, length, 8.0), steel, steel.darkened(0.25))
	var bays := 5
	for k in bays:
		var a := length * k / bays
		var b := length * (k + 1) / bays
		m.line(Vector2(a, y + 10.0 if k % 2 == 0 else y - 10.0), Vector2(b, y - 10.0 if k % 2 == 0 else y + 10.0), 3.0, steel.lightened(0.05))
		m.line(Vector2(b, y - 10.0), Vector2(b, y + 10.0), 3.0, steel.darkened(0.1))
	m.round_rect(Rect2(length - 12.0, y - 24.0, 22.0, 50.0), 5.0, Color("c8452f"), Color("9e3524"))
	m.flush(ci)


## The fuel hose: a sagging line from the tower to the booster's filler; UV.x runs along it, for
## the flow shader's dashes.
func _paint_hose(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var start := Vector2(LaunchPlaces.TOWER_X + TOWER_HALF - 4.0, LaunchPlaces.PAD_Y - 170.0)
	var end := Vector2(LaunchPlaces.PAD_X - LaunchRocket.MARKS[_mark].sections[0].w * 0.5, LaunchPlaces.PAD_Y - 150.0)
	(ci as Node2D).position = start
	var n := 18
	var prev := Vector2.ZERO
	for k in range(1, n + 1):
		var t := float(k) / n
		var p := (end - start) * t + Vector2(0, sin(t * PI) * 34.0)
		var d := (p - prev).normalized().orthogonal() * 6.0
		m.depth = float(k - 1) / n
		var i := m.vert(prev - d, Color("2c3040"))
		m.vert(prev + d, Color("596074"))
		m.depth = t
		m.vert(p + d, Color("596074"))
		m.vert(p - d, Color("2c3040"))
		m.tri(i, i + 1, i + 2)
		m.tri(i, i + 2, i + 3)
		prev = p
	m.depth = 0.0
	m.flush(ci)


## The beacons: red lamps on the tower's cap and the lightning mast's foot.
func _paint_lights(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var top := _tower_top(_mark)
	for at: Vector2 in [Vector2(LaunchPlaces.TOWER_X - 52.0, top - 34.0), Vector2(LaunchPlaces.TOWER_X + 52.0, top - 34.0),
			Vector2(LaunchPlaces.PAD_X - 262.0, LaunchPlaces.PAD_Y - 6.0), Vector2(LaunchPlaces.PAD_X + 262.0, LaunchPlaces.PAD_Y - 6.0)]:
		m.glow(at, Vector2(26, 26), Color(1.0, 0.25, 0.15, 0.6), 5)
		m.circle(at, 6.0, Color("ff4a30"))
	m.flush(ci)


## The near ground in front of the pad: dune grass, rocks or snow drifts, wide of the table.
func _paint_foreground(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var p := LaunchPlaces.place(_place)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91 + _place
	var dark: Color = (p.near2 as Color).darkened(0.32)
	match str(p.id):
		"coast":
			var x := -LaunchPlaces.BLEED
			while x < LaunchPlaces.SIZE.x + LaunchPlaces.BLEED:
				if absf(x - LaunchPlaces.PAD_X) > 640.0:
					for blade in 4:
						var lean := rng.randf_range(-20.0, 14.0)
						var bx := x + blade * 8.0
						var h := rng.randf_range(44.0, 92.0)
						m.fill(PackedVector2Array([Vector2(bx - 4.0, 1084.0), Vector2(bx + 4.0, 1084.0), Vector2(bx + lean, 1084.0 - h)]), dark.lerp(p.near, rng.randf_range(0.0, 0.3)), false)
				x += rng.randf_range(16.0, 36.0)
		"desert":
			for s in [-1.0, 1.0]:
				var cx: float = LaunchPlaces.PAD_X + s * 860.0
				m.fill(PackedVector2Array([Vector2(cx - 150.0, 1084.0), Vector2(cx - 90.0, 1022.0), Vector2(cx + 20.0, 1000.0), Vector2(cx + 140.0, 1036.0), Vector2(cx + 190.0, 1084.0)]), dark)
				m.line(Vector2(cx - 90.0, 1022.0), Vector2(cx + 20.0, 1000.0), 3.0, Color(p.lit, 0.35))
		"polar":
			for s in [-1.0, 1.0]:
				var cx: float = LaunchPlaces.PAD_X + s * 830.0
				m.fill(PackedVector2Array([Vector2(cx - 240.0, 1084.0), Vector2(cx - 120.0, 1030.0), Vector2(cx + 60.0, 1012.0), Vector2(cx + 230.0, 1050.0), Vector2(cx + 280.0, 1084.0)]), (p.near as Color).lightened(0.2))
	m.flush(ci)


func _build_clock() -> void:
	var board: Node2D = PaintLayer.new()
	board.name = "ClockBoard"
	board.paint = _paint_board
	back.add_child(board)
	var look := GameTheme.new(Color("35c8d8"), Color("0a1a30"), 0.1)
	clock_text = look.label("T-0:45", 96, GameTheme.TARGET, true)
	clock_text.name = "ClockText"
	clock_text.position = CLOCK_RECT.position + Vector2(0, 8)
	clock_text.size = Vector2(CLOCK_RECT.size.x, 108)
	clock_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_text.pivot_offset = clock_text.size * 0.5
	back.add_child(clock_text)
	clock_caption = look.label(tr("TO LIFTOFF"), 40, GameTheme.INK, true)
	clock_caption.name = "ClockCaption"
	clock_caption.position = CLOCK_RECT.position + Vector2(0, 118)
	clock_caption.size = Vector2(CLOCK_RECT.size.x, 48)
	clock_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.add_child(clock_caption)


## The mission clock's board on its two legs, lit along the top.
func _paint_board(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var r := CLOCK_RECT
	var steel := Color("3a4054")
	for x in [r.position.x + 70.0, r.end.x - 70.0]:
		m.rect_v(Rect2(x - 9.0, r.end.y, 18.0, 300.0), steel.lightened(0.12), steel.darkened(0.3))
		m.line(Vector2(x, r.end.y + 40.0), Vector2(x + (60.0 if x < r.get_center().x else -60.0), r.end.y + 150.0), 5.0, steel.darkened(0.1))
	m.soft_shadow(r, 16.0, 16.0, Color(0, 0, 0, 0.3))
	m.round_rect(r, 16.0, Color("1a2030"), Color("0d1120"))
	m.bevel(r, 16.0, 6.0, Vector2(0.6, -0.8), Color(1, 1, 1, 0.3), Color(0, 0, 0, 0.45))
	m.flush(ci)


func _steam_emitter(i: int) -> CPUParticles2D:
	var s := CPUParticles2D.new()
	s.name = "Steam%d" % i
	s.amount = 12
	s.lifetime = 2.8
	s.preprocess = 3.0
	s.texture = puff_texture()
	s.position = Vector2(LaunchPlaces.PAD_X + (-218.0 if i == 0 else 218.0), LaunchPlaces.PAD_Y + 26.0)
	s.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	s.emission_rect_extents = Vector2(40.0, 6.0)
	s.direction = Vector2(-1.0 if i == 0 else 1.0, -0.35)
	s.spread = 16.0
	s.gravity = Vector2(0, -8.0)
	s.initial_velocity_min = 30.0
	s.initial_velocity_max = 70.0
	s.scale_amount_min = 0.4
	s.scale_amount_max = 0.7
	s.scale_amount_curve = _grow_curve(1.7)
	return s


func _smoke_emitter(side: float) -> CPUParticles2D:
	var b := CPUParticles2D.new()
	b.name = "Smoke%s" % ("L" if side < 0.0 else "R")
	b.amount = 34
	b.lifetime = 2.6
	b.emitting = false
	b.texture = puff_texture()
	b.position = Vector2(LaunchPlaces.PAD_X + side * 90.0, LaunchPlaces.PAD_Y + 72.0)
	b.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	b.emission_rect_extents = Vector2(70.0, 16.0)
	b.direction = Vector2(side, -0.12)
	b.spread = 12.0
	b.gravity = Vector2(0, -14.0)
	b.initial_velocity_min = 300.0
	b.initial_velocity_max = 560.0
	b.damping_min = 90.0
	b.damping_max = 150.0
	b.scale_amount_min = 1.5
	b.scale_amount_max = 2.6
	b.scale_amount_curve = _grow_curve(2.2)
	return b


## Snow or dust over the place: wide, slow and small.
func _weather(node_name: String, amount: int, velocity: Vector2, col: Color, scale_min: float, area: Rect2) -> CPUParticles2D:
	var w := CPUParticles2D.new()
	w.name = node_name
	w.amount = amount
	w.lifetime = 9.0
	w.preprocess = 9.0
	w.texture = dot_texture()
	w.position = area.position
	w.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	w.emission_rect_extents = area.size
	w.direction = velocity.normalized()
	w.spread = 14.0
	w.gravity = Vector2.ZERO
	w.initial_velocity_min = velocity.length() * 0.7
	w.initial_velocity_max = velocity.length() * 1.2
	w.scale_amount_min = scale_min
	w.scale_amount_max = scale_min * 1.7
	w.color = col
	w.emitting = false
	w.visible = false
	add_child(w)
	return w


static func _grow_curve(end: float) -> Curve:
	var c := Curve.new()
	c.max_value = 4.0
	c.add_point(Vector2(0.0, 0.5))
	c.add_point(Vector2(1.0, end))
	return c


static func ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(cols)
	var offsets := PackedFloat32Array()
	for i in cols.size():
		offsets.append(float(i) / (cols.size() - 1))
	g.offsets = offsets
	return g


## A soft round dot, 12 px: snow and dust.
static func dot_texture() -> Texture2D:
	if _dot:
		return _dot
	var g := GradientTexture2D.new()
	g.gradient = ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 12
	g.height = 12
	_dot = g
	return _dot


## A soft lumpy puff, drawn into an image once: several overlapping blobs, not a clean circle.
static func puff_texture() -> Texture2D:
	if _puff:
		return _puff
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var blobs: Array[Vector3] = []
	for i in 7:
		var a := rng.randf() * TAU
		blobs.append(Vector3(0.5 + cos(a) * 0.2, 0.5 + sin(a) * 0.2, rng.randf_range(0.18, 0.27)))
	blobs.append(Vector3(0.5, 0.5, 0.3))
	for y in size:
		for x in size:
			var u := Vector2((x + 0.5) / size, (y + 0.5) / size)
			var a := 0.0
			for b in blobs:
				var d := u.distance_to(Vector2(b.x, b.y)) / b.z
				a = maxf(a, 1.0 - smoothstep(0.55, 1.0, d))
			# Lit from above, so a bank of puffs has volume rather than one flat colour.
			var v := lerpf(1.0, 0.68, u.y)
			img.set_pixel(x, y, Color(v, v, v, a))
	_puff = ImageTexture.create_from_image(img)
	return _puff
