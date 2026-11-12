class_name SafeDial
extends Node2D
## Safe Cracker's door and dial (#41), centred on the door. The dial runs 0-100 over 270
## degrees, from the lower left round to the lower right; the needle is the live resistance
## reading.
##
## Layers (children; `show_behind_parent` ones draw before this node's own drawing):
##   Vault       behind: the vault in the door's opening (`SafeBody.build_vault`), shown only
##               while the door is open (shut, the door covers it: no pixels spent on it)
##   AlarmGlow   behind: a red glow round the body, shown and faded by `alarm` (no redraw)
##   Spill       behind: the vault's warm light spilling out as the door opens (modulate)
##   Sparkle     behind: gold sparkles rising out of the vault on a crack (one burst)
##   Door        behind: the static door (`SafeDoor`): steel, hardware, bezel, ticks, plate
##   Bolts       behind: five bolt ends on the door's edge, sliding back as tumblers click
##   Numerals    behind: the dial's numbers, static
##   (this node) the live dial: target band, hold ring, tumbler lights, the target's number
##   Reading     the reading's number alone (text only: the one thing that changes as you turn)
##   Needle      a static drawing, turned by `rotation` (no redraw as the reading moves)
##   NextLight   the next tumbler's breathing ring (a looping modulate tween)
##   Cover       the glass, its glint on target, and the KEEP PEDALLING cover when unpowered
##
## Redraws: the door on a place, lights-count or hint change; this node only when its numbers,
## band, ring or lights change. The door swing is `safe_door.gdshader` on the door's layers: a
## uniform, never a redraw.
##
## Type follows framework/ui/UI_STYLE.md: the display face (`GameTheme.display_font`), nothing
## under 34 px, an ink outline under every number. The hero is the reading (96 px, green when on
## the target), in the gap at the bottom of the dial that the needle never sweeps. The target
## number sits on a brass plate above the bezel, out of the needle's reach.

const R := 262.0
const DOOR := Rect2(-440, -320, 880, 640)
const SWEEP_START := 135.0
const SWEEP := 270.0

const INK := Color("14110d")  ## soot: outlines (Safe Cracker's ink)
const NUMERAL_SIZE := 36
const NUMERAL_OUTLINE := 8
const READING_SIZE := 96  ## HudTheme.BIG: the hero
const READING_BASELINE := 182.0
const TARGET_SIZE := 56  ## HudTheme.MEDIUM
## The target's brass plate, above the bezel (radius R + 40) and outside the needle's sweep.
const TARGET_PLATE := Rect2(-92, -R - 118, 184, 80)
## The tumbler lights: a column on the door, right of the bezel, filling from the bottom up.
const LIGHT_X := 371.0
const LIGHT_R := 22.0
const LIGHT_GAP := 58.0
const LIGHT_POP := 0.35  ## the newest light grows by this much at `light_pop` 1
## "KEEP PEDALLING": an amber badge across the dial's lower half, above the reading.
const TEXT_BOX := 600.0  ## the width centred text is laid out in
const PEDAL_BADGE := Rect2(-250, 30, 500, 82)
const NEEDLE_RED := Color(0.95, 0.3, 0.25)
const NUMERAL_COLOUR := Color(0.93, 0.92, 0.86)
## The swing: the door turns this far toward the viewer about its hinge, seen from this far.
const OPEN_ANGLE := deg_to_rad(72.0)
const FOCAL := 3400.0
const THICKNESS := 28.0
## Five bolt ends on the door's right edge; they slide back as the tumblers click.
const BOLT_Y := [-240.0, -120.0, 0.0, 120.0, 240.0]
const BOLT_OUT := 34.0
const BOLT_IN := 6.0
const BOLT_SEC := 0.45
const NEXT_PULSE_SEC := 1.0  ## the next light's breath, each way (at most once a second)

const DoorShader := preload("res://games/safe_cracker/safe_door.gdshader")

var reading := 0.0
var target := 0
var tolerance := 2.0
var target_hidden := false
var hold_frac := 0.0  ## 0-1, how far through the hold
var closeness := 0.0
var powered := true
var tumblers_done := 0
var tumblers_total := 3
## 0 closed, 1 fully open: sets the swing's uniforms at once (tween it).
var door_open := 0.0:
	set(v):
		door_open = v
		_apply_swing()
var alarm := 0.0  ## 0-1, the alarm light
var light_pop := 0.0  ## 0-1, the newest lit tumbler light's pop (tweened by SafeCracker)
var colour := Color(0.5, 0.52, 0.55)
var accent := Color(0.95, 0.75, 0.35)
var place_index := 0  ## the room, for the light the door is shaded by

var door: SafeDoor
var needle: Node2D
var next_light: Node2D
var cover: Node2D
var bolts: Node2D
var numerals: Node2D
var reading_layer: Node2D
var vault: Node2D
var alarm_glow: Node2D
var spill: Node2D
var sparkle: CPUParticles2D

## What each layer showed when last drawn, and what it shows now: fixed-size arrays filled in
## place every frame and compared by value (refresh() runs every frame; no allocation).
var _drawn := []
var _reading_drawn := []
var _door_drawn := []
var _cover_drawn := []
var _now := []
var _reading_now := []
var _door_now := []
var _cover_now := []
var _font: Font
var _queued: Array = []  ## text waiting for `_flush_text`
var _face_mat: ShaderMaterial
var _door_mat: ShaderMaterial
var _bolt_from := [0.0, 0.0, 0.0, 0.0, 0.0]
var _bolt_to := [0.0, 0.0, 0.0, 0.0, 0.0]
var _bolt_ease := 1.0
var _bolt_tween: Tween
var _bolts_shown := -1
var _pulse_tween: Tween
var _mesh := MeshBatch2D.new()


static func angle_for(value: float) -> float:
	return deg_to_rad(SWEEP_START + clampf(value, 0.0, 100.0) * SWEEP / 100.0)


## Where tumbler light `i` of `total` sits (door coordinates).
static func light_at(i: int, total: int) -> Vector2:
	return Vector2(LIGHT_X, (total - 1) * LIGHT_GAP / 2.0 - i * LIGHT_GAP)


## How many of the five bolts have slid back with `done` of `total` tumblers clicked.
static func bolts_back(done: int, total: int) -> int:
	if total <= 0:
		return 0
	return clampi(roundi(float(BOLT_Y.size()) * done / total), 0, BOLT_Y.size())


func _init() -> void:
	_face_mat = ShaderMaterial.new()
	_face_mat.shader = DoorShader
	_door_mat = ShaderMaterial.new()
	_door_mat.shader = DoorShader
	_door_mat.set_shader_parameter("thickness", THICKNESS)
	for m in [_face_mat, _door_mat]:
		m.set_shader_parameter("focal", FOCAL)
	material = _face_mat
	vault = _layer("Vault", _paint_vault, true)
	vault.use_parent_material = false
	vault.visible = false
	alarm_glow = _layer("AlarmGlow", _paint_alarm_glow, true)
	alarm_glow.use_parent_material = false
	alarm_glow.visible = false
	spill = _layer("Spill", _paint_spill, true)
	spill.use_parent_material = false
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spill.material = add
	spill.visible = false
	sparkle = _make_sparkle()
	sparkle.show_behind_parent = true
	add_child(sparkle)
	door = SafeDoor.new()
	door.name = "Door"
	door.dial = self
	door.show_behind_parent = true
	door.material = _door_mat
	add_child(door)
	bolts = _layer("Bolts", _paint_bolts, true)
	numerals = _layer("Numerals", _paint_numerals, true)
	reading_layer = _layer("Reading", _paint_reading, false)
	needle = _layer("Needle", _paint_needle, false)
	next_light = _layer("NextLight", _paint_next_light, false)
	cover = _layer("Cover", _paint_cover, false)


func _layer(layer_name: String, paint: Callable, behind: bool) -> Node2D:
	var l := PaintLayer.new()
	l.name = layer_name
	l.paint = paint
	l.show_behind_parent = behind
	l.use_parent_material = true
	add_child(l)
	return l


func _ready() -> void:
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(next_light, "modulate:a", 1.0, NEXT_PULSE_SEC).from(0.0).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(next_light, "modulate:a", 0.0, NEXT_PULSE_SEC).set_trans(Tween.TRANS_SINE)
	_apply_swing()


## Whether the reading is within the tolerance of a shown target (the reading turns green).
func on_target() -> bool:
	return not target_hidden and absf(reading - float(target)) <= tolerance


## Applies what changed: turns the needle every call, and redraws a layer only when what it
## shows changed.
func refresh() -> void:
	needle.rotation = angle_for(reading)
	_door_now.resize(5)
	_door_now[0] = colour
	_door_now[1] = accent
	_door_now[2] = place_index
	_door_now[3] = tumblers_total
	_door_now[4] = target_hidden
	if _differs(_door_now, _door_drawn):
		door.queue_redraw()
		numerals.queue_redraw()
		vault.queue_redraw()
	_now.resize(9)
	_now[0] = target
	_now[1] = tolerance
	_now[2] = target_hidden
	_now[3] = roundi(hold_frac * 60.0)
	_now[4] = roundi(closeness * 20.0) if target_hidden else 0
	_now[5] = tumblers_done
	_now[6] = tumblers_total
	_now[7] = accent
	_now[8] = roundi(light_pop * 24.0)
	if _differs(_now, _drawn):
		queue_redraw()
	var on := on_target()
	_reading_now.resize(2)
	_reading_now[0] = roundi(reading)
	_reading_now[1] = on
	if _differs(_reading_now, _reading_drawn):
		reading_layer.queue_redraw()
	_cover_now.resize(2)
	_cover_now[0] = powered
	_cover_now[1] = on
	if _differs(_cover_now, _cover_drawn):
		cover.queue_redraw()
	var next := tumblers_done < tumblers_total
	next_light.visible = next
	if next:
		next_light.position = light_at(tumblers_done, tumblers_total)
	alarm_glow.visible = alarm > 0.0
	alarm_glow.modulate.a = 0.35 + 0.65 * alarm
	_set_bolts(bolts_back(tumblers_done, tumblers_total))


## Whether a layer's state `now` differs from what it last drew; `drawn` then takes it.
static func _differs(now: Array, drawn: Array) -> bool:
	if now == drawn:
		return false
	drawn.assign(now)
	return true


## The bolts slide back (or out again, for a new safe) over BOLT_SEC: a small redraw while the
## tween runs, only when a tumbler clicks.
func _set_bolts(back: int) -> void:
	if back == _bolts_shown:
		return
	var instant := _bolts_shown < 0 or not is_inside_tree()
	_bolts_shown = back
	for i in BOLT_Y.size():
		_bolt_from[i] = _bolt_now(i)
		_bolt_to[i] = 1.0 if i < back else 0.0
	if _bolt_tween:
		_bolt_tween.kill()
	if instant:
		_set_bolt_ease(1.0)
		return
	_bolt_tween = create_tween()
	_bolt_tween.tween_method(_set_bolt_ease, 0.0, 1.0, BOLT_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _set_bolt_ease(v: float) -> void:
	_bolt_ease = v
	bolts.queue_redraw()


## 0 out, 1 slid back.
func _bolt_now(i: int) -> float:
	return lerpf(_bolt_from[i], _bolt_to[i], _bolt_ease)


func _apply_swing() -> void:
	if _face_mat == null:
		return
	var angle := clampf(door_open, 0.0, 1.0) * OPEN_ANGLE
	var xf := get_global_transform() if is_inside_tree() else transform
	for m in [_face_mat, _door_mat]:
		m.set_shader_parameter("angle", angle)
		m.set_shader_parameter("hinge_x", (xf * DOOR.position).x)
		m.set_shader_parameter("eye", xf * Vector2.ZERO)
	spill.visible = door_open > 0.0
	vault.visible = door_open > 0.0
	spill.modulate.a = smoothstep(0.0, 0.7, door_open)


## A crack's gold sparkles, rising from the vault (one burst, 18 particles).
func burst_sparkle() -> void:
	sparkle.restart()
	sparkle.emitting = true


func _make_sparkle() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Sparkle"
	p.one_shot = true
	p.emitting = false
	p.amount = 18
	p.lifetime = 2.2
	p.explosiveness = 0.75
	p.local_coords = true
	p.texture = MeshBatch2D.soft_dot()
	p.position = Vector2(160, 200)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(240, 60)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(0, 18)
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 140.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.7, 0.0))
	ramp.set_color(1, Color(1.0, 0.8, 0.3, 0.0))
	ramp.add_point(0.12, Color(1.0, 0.93, 0.6, 1.0))
	ramp.add_point(0.6, Color(1.0, 0.82, 0.35, 0.7))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	return p


func _draw() -> void:
	if _font == null:
		_font = GameTheme.display_font(true)
	var m := _mesh
	# The target: a brass band the width of the tolerance, or a glow that warms as you close in.
	if not target_hidden:
		m.ring(Vector2.ZERO, R - 35.0, R - 9.0, Color(accent, 0.85), angle_for(float(target) - tolerance), angle_for(float(target) + tolerance))
		var ta := angle_for(float(target))
		var dir := Vector2(cos(ta), sin(ta))
		var tip := dir * (R + 6.0)
		var side := dir.orthogonal() * 14.0
		m.fill(PackedVector2Array([tip, tip + dir * 30.0 - side, tip + dir * 30.0 + side]), accent)
	elif closeness > 0.0:
		m.ring(Vector2.ZERO, R + 28.0, R + 38.0, Color(accent, closeness * closeness * 0.9))
	# The hold ring, filling as the needle stays on the target.
	if hold_frac > 0.0:
		m.ring(Vector2.ZERO, R + 27.0, R + 39.0, GameTheme.GOOD, -PI / 2.0, -PI / 2.0 + hold_frac * TAU)
	_add_lights(m)
	m.flush(self)
	var plate_base := Vector2(0, TARGET_PLATE.get_center().y + TARGET_SIZE * 0.36)
	if target_hidden:
		_text("?", plate_base, TARGET_SIZE, Color(0.75, 0.78, 0.85))
	else:
		_text(str(target), plate_base, TARGET_SIZE, accent)
	_flush_text(self)


## The hero: the reading in big numbers, green while it's on a shown target.
func _paint_reading(ci: CanvasItem) -> void:
	if _font == null:
		_font = GameTheme.display_font(true)
	_text(str(roundi(reading)), Vector2(0, READING_BASELINE), READING_SIZE,
		GameTheme.GOOD if on_target() else Color(0.97, 0.96, 0.92))
	_flush_text(ci)


## One light per tumbler: brass when clicked (the newest pops, `light_pop`), an ink socket with
## a faint brass ring for the rest. The next one's breathing ring is `NextLight`.
func _add_lights(m: MeshBatch2D) -> void:
	for i in tumblers_total:
		var at := light_at(i, tumblers_total)
		if i < tumblers_done:
			var grow := 1.0 + LIGHT_POP * light_pop if i == tumblers_done - 1 else 1.0
			var r := LIGHT_R * grow
			m.glow(at, Vector2(r, r) * 2.2, Color(accent, 0.28), 6)
			m.circle(at, r + 4.0, INK)
			m.circle(at, r, accent)
			m.circle(at + Vector2(-0.18, -0.22) * r, r * 0.5, accent.lightened(0.5))
			m.circle(at + Vector2(-0.3, -0.35) * r, r * 0.16, Color(1, 1, 0.95, 0.9))
		else:
			m.circle(at, LIGHT_R + 4.0, Color(INK, 0.75))
			m.ring(at, LIGHT_R - 4.0, LIGHT_R, Color(accent, 0.35))


func _paint_next_light(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	m.ring(Vector2.ZERO, LIGHT_R - 4.0, LIGHT_R, Color(accent, 0.6))
	m.glow(Vector2.ZERO, Vector2(LIGHT_R, LIGHT_R) * 1.6, Color(accent, 0.18), 6, 0.5)
	m.flush(ci)


## The needle along +x (`rotation` turns it): a tapered red pointer with a lit edge, a
## counterweight and a steel hub. Same reach as ever: from 40 behind the hub to R - 12.
func _paint_needle(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var tail := -40.0
	var tip := R - 12.0
	m.fill(PackedVector2Array([Vector2(tail, -7), Vector2(tip - 18, -3.5), Vector2(tip, 0), Vector2(tip - 18, 3.5), Vector2(tail, 7)]), NEEDLE_RED.darkened(0.15))
	m.line(Vector2(tail, -2.0), Vector2(tip - 10, -0.8), 3.0, NEEDLE_RED.lightened(0.3))
	m.circle(Vector2(-30, 0), 13.0, Color(0.2, 0.2, 0.22))
	m.circle(Vector2.ZERO, 30.0, Color(0.55, 0.55, 0.52))
	m.circle(Vector2.ZERO, 27.0, Color(0.85, 0.85, 0.8))
	m.circle(Vector2(-5, -6), 17.0, Color(0.95, 0.95, 0.9))
	m.circle(Vector2.ZERO, 14.0, Color(0.2, 0.2, 0.22))
	m.circle(Vector2(-3, -4), 4.0, Color(1, 1, 1, 0.5))
	m.flush(ci)


## The numbers round the dial: static, so they never redraw with the needle.
func _paint_numerals(ci: CanvasItem) -> void:
	if _font == null:
		_font = GameTheme.display_font(true)
	for i in range(0, 101, 10):
		var a := angle_for(float(i))
		var at := Vector2(cos(a), sin(a)) * (R - 70.0)
		_text(str(i), at + Vector2(0, NUMERAL_SIZE * 0.36), NUMERAL_SIZE, NUMERAL_COLOUR, NUMERAL_OUTLINE)
	_flush_text(ci)


## Five steel bolt ends standing out of the door's right edge over the frame, the first
## `_bolts_shown` slid back (easing over BOLT_SEC).
func _paint_bolts(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var steel := colour.lightened(0.45)
	for i in BOLT_Y.size():
		var length := lerpf(BOLT_OUT, BOLT_IN, _bolt_now(i))
		var y: float = BOLT_Y[i]
		var r := Rect2(DOOR.end.x - 4.0, y - 12.0, length + 4.0, 24.0)
		m.rect_v(Rect2(r.position + Vector2(0, 2), r.size), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0.0))
		m.rect_v(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.5), steel.lightened(0.35), steel)
		m.rect_v(Rect2(r.position.x, r.get_center().y, r.size.x, r.size.y * 0.5), steel, steel.darkened(0.45))
		m.rect_h(Rect2(r.end.x - 3.0, r.position.y, 3.0, r.size.y), steel.darkened(0.2), steel.darkened(0.55))
	m.flush(ci)


## The glass over the dial: a soft highlight band round the upper left (over the ticks, clear of
## the numerals' centres) and a faint one lower right; a glint on it while on target. When
## unpowered, a dark cover with the amber KEEP PEDALLING badge.
func _paint_cover(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	_glass_band(m, deg_to_rad(196.0), deg_to_rad(292.0), R - 50.0, R - 12.0, 0.13)
	_glass_band(m, deg_to_rad(22.0), deg_to_rad(62.0), R - 30.0, R - 18.0, 0.05)
	if on_target():
		var at := Vector2(cos(deg_to_rad(244.0)), sin(deg_to_rad(244.0))) * (R - 31.0)
		m.glow(at, Vector2(30, 30), Color(1, 1, 0.9, 0.35), 6)
		m.line(at - Vector2(18, 0), at + Vector2(18, 0), 2.5, Color(1, 1, 0.95, 0.85))
		m.line(at - Vector2(0, 18), at + Vector2(0, 18), 2.5, Color(1, 1, 0.95, 0.85))
	if not powered:
		m.circle(Vector2.ZERO, R + 40.0, Color(0.02, 0.02, 0.04, 0.6))
	m.flush(ci)
	if not powered:
		if _font == null:
			_font = GameTheme.display_font(true)
		var badge := StyleBoxFlat.new()
		badge.bg_color = Color(GameTheme.WARN, 0.96)
		badge.set_corner_radius_all(14)
		badge.border_color = Color(Color.WHITE, 0.55)
		badge.set_border_width_all(3)
		badge.border_width_bottom = 6
		ci.draw_style_box(badge, PEDAL_BADGE)
		_text("KEEP PEDALLING", Vector2(0, PEDAL_BADGE.get_center().y + 20), 52, Color.WHITE)
		_flush_text(ci)


func _glass_band(m: MeshBatch2D, from: float, to: float, r0: float, r1: float, peak: float) -> void:
	var segs := 28
	var inner := MeshBatch2D.arc_points(Vector2.ZERO, r0, from, to, segs)
	var outer := MeshBatch2D.arc_points(Vector2.ZERO, r1, from, to, segs)
	var mid := MeshBatch2D.arc_points(Vector2.ZERO, (r0 + r1) * 0.5, from, to, segs)
	var edge := PackedColorArray()
	var core := PackedColorArray()
	for k in segs + 1:
		var a := peak * sin(PI * k / segs)
		edge.append(Color(1, 1, 1, 0.0))
		core.append(Color(1, 1, 1, a))
	m.band_colors(inner, mid, edge, core, false)
	m.band_colors(mid, outer, core, edge, false)


func _paint_vault(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	SafeBody.build_vault(m, colour)
	m.flush(ci)


## A red glow round the safe's body (shown, and faded by `alarm`, from `refresh`).
func _paint_alarm_glow(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var body := SafeBody.BODY
	var red := Color(0.95, 0.15, 0.1, 0.85)
	var edge := MeshBatch2D.round_rect_outline(body.grow(-2.0), 30.0)
	m.band(edge, MeshBatch2D.round_rect_outline(body.grow(14.0), 46.0), red, Color(red, 0.55))
	m.band(MeshBatch2D.round_rect_outline(body.grow(14.0), 46.0), MeshBatch2D.round_rect_outline(body.grow(60.0), 92.0), Color(red, 0.55), Color(red, 0.0))
	m.flush(ci)


## The vault's warm light spilling out of the open door, onto the frame and the floor (additive).
func _paint_spill(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	m.glow(Vector2(80, 60), Vector2(820, 560), Color(1.0, 0.72, 0.3, 0.32), 14)
	m.glow(Vector2(120, 380), Vector2(700, 120), Color(1.0, 0.7, 0.3, 0.25), 10)
	m.flush(ci)


## Queues centred text with the ink outline under it (`baseline` is the centre of its baseline).
## `_flush_text` draws every queued outline, then every fill: two batches, not two a string.
func _text(text: String, baseline: Vector2, size: int, color: Color, outline := 0) -> void:
	_queued.append([text, baseline - Vector2(TEXT_BOX / 2.0, 0), size, color,
		outline if outline > 0 else GameTheme.outline_for(size)])


func _flush_text(ci: CanvasItem) -> void:
	for q in _queued:
		ci.draw_string_outline(_font, q[1], q[0], HORIZONTAL_ALIGNMENT_CENTER, TEXT_BOX, q[2], q[4], INK)
	for q in _queued:
		ci.draw_string(_font, q[1], q[0], HORIZONTAL_ALIGNMENT_CENTER, TEXT_BOX, q[2], q[3])
	_queued.clear()
