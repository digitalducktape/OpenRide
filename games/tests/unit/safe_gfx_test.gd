extends GdUnitTestSuite
## Safe Cracker's graphics (games/safe_cracker/ART_BIBLE.md, GFX_POLISH.md): the door's hardware
## stays clear of the dial, the lights and the plate; every batch is well formed and its size
## bounded; the needle and the door swing never redraw a layer; each place has one key light and
## only its own ambient life; the lab's accent isn't the on-target green.

const SEGMENT := {"game_id": "safe_cracker", "role": "recovery", "difficulty": "standard", "duration_sec": -1,
	"end_mode": "timer", "seed": 11, "params": {"power_cap_watts": 120.0}}
const MAX_VERTICES := 60000  ## a static batch, rebuilt only on a place change

var _rider := ""
var _saved_plan := {}


func before_test() -> void:
	_rider = "test%d" % Time.get_ticks_usec()
	_saved_plan = Session.plan
	Session.plan = {"rider_id": _rider}


func after_test() -> void:
	GameOptions.forget_rider(_rider)
	Session.plan = _saved_plan


func _game() -> Game:
	var game: Game = auto_free(load("res://games/safe_cracker/SafeCracker.tscn").instantiate())
	game.hud = auto_free(Hud.new())
	add_child(game.hud)
	add_child(game)
	game.prepare(SEGMENT)
	game.start()
	return game


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _assert_batch(m: MeshBatch2D, what: String) -> void:
	assert_int(m.indices.size() % 3).override_failure_message("%s: not whole triangles" % what).is_equal(0)
	assert_int(m.colors.size()).is_equal(m.points.size())
	assert_int(m.uvs.size()).is_equal(m.points.size())
	var top := 0
	for i in m.indices:
		top = maxi(top, i)
	assert_int(top).override_failure_message("%s: an index past the vertices" % what).is_less(m.points.size())
	assert_int(m.points.size()).override_failure_message("%s: %d vertices" % [what, m.points.size()]).is_less(MAX_VERTICES)


func test_the_handle_rivets_and_plate_stay_clear_of_the_dial_and_lights() -> void:
	var door := SafeDial.DOOR.grow(-8)
	var handle := Rect2(SafeDoor.HANDLE - Vector2.ONE * (SafeDoor.HANDLE_R + 8), Vector2.ONE * (SafeDoor.HANDLE_R + 8) * 2.0)
	assert_bool(door.encloses(handle)).override_failure_message("the handle leaves the door").is_true()
	assert_float(SafeDoor.HANDLE.length() - SafeDoor.HANDLE_R - 8).is_greater(SafeDial.R + 40.0)
	var light_r := SafeDial.LIGHT_R * (1.0 + SafeDial.LIGHT_POP) + 4.0
	for total in range(3, 7):
		for i in total:
			var gap := SafeDial.light_at(i, total).distance_to(SafeDoor.HANDLE) - light_r - SafeDoor.HANDLE_R - 8
			assert_float(gap).override_failure_message("light %d/%d touches the handle" % [i, total]).is_greater(0.0)
	var dial: SafeDial = auto_free(SafeDial.new())
	var sd: SafeDoor = dial.door
	for p in sd._rivets():
		var label := "the rivet at %s" % p
		assert_bool(door.has_point(p)).override_failure_message(label + " leaves the door").is_true()
		assert_float(p.length()).override_failure_message(label + " is on the bezel").is_greater(SafeDial.R + 40.0 + 12.0)
		assert_float(p.distance_to(SafeDoor.HANDLE)).override_failure_message(label + " is on the handle").is_greater(SafeDoor.HANDLE_R + 20.0)
		assert_bool(SafeDial.TARGET_PLATE.grow(14).has_point(p)).override_failure_message(label + " is under the plate").is_false()


func test_bolts_slide_back_with_the_tumblers() -> void:
	for total in range(3, 7):
		assert_int(SafeDial.bolts_back(0, total)).is_equal(0)
		assert_int(SafeDial.bolts_back(total, total)).is_equal(SafeDial.BOLT_Y.size())
		var prev := 0
		for done in range(total + 1):
			var back := SafeDial.bolts_back(done, total)
			assert_int(back).is_greater_equal(prev)
			prev = back
	# The bolts stand clear of the lights and the handle, on the door's edge.
	for y: float in SafeDial.BOLT_Y:
		assert_float(absf(y)).is_less(SafeDial.DOOR.size.y / 2.0 - 30.0)


func test_every_place_has_one_key_light_and_a_well_formed_room() -> void:
	for i in SafePlaces.count():
		var l := SafePlaces.light(i)
		var at: Vector2 = l.at
		assert_bool(Rect2(Vector2.ZERO, SafePlaces.SIZE).has_point(at)).override_failure_message("place %d's light is off screen" % i).is_true()
		assert_float(SafePlaces.to_light(i).length()).is_equal_approx(1.0, 0.001)
		assert_float(float(l.strength)).is_between(0.05, 0.5)
		var m := MeshBatch2D.new()
		SafePlaces.build_room(m, i)
		_assert_batch(m, "room %s" % SafePlaces.place(i).id)
		var body: SafeBody = auto_free(SafeBody.new())
		body.place_index = i
		m.clear()
		body.build(m)
		_assert_batch(m, "body %d" % i)


func test_the_lab_accent_is_not_the_on_target_green() -> void:
	var lab: Color = SafePlaces.place(SafePlaces.index_of("lab")).accent
	var good := GameTheme.GOOD
	var d := Vector3(lab.r - good.r, lab.g - good.g, lab.b - good.b).length()
	assert_float(d).override_failure_message("the lab's accent %s reads as GOOD %s" % [lab, good]).is_greater(0.2)


func test_the_mesh_feathers_and_closes_its_shapes() -> void:
	var m := MeshBatch2D.new()
	m.circle(Vector2.ZERO, 20.0, Color.WHITE)
	_assert_batch(m, "circle")
	var clear := 0
	for c in m.colors:
		if c.a == 0.0:
			clear += 1
	assert_int(clear).override_failure_message("no feather").is_greater(0)
	m.clear()
	m.round_rect(Rect2(0, 0, 100, 60), 10.0, Color.WHITE, Color.BLACK)
	m.bevel(Rect2(0, 0, 100, 60), 10.0, 4.0, Vector2.UP, Color.WHITE, Color.BLACK)
	m.glow(Vector2.ZERO, Vector2(400, 300), Color.WHITE)
	m.ring(Vector2.ZERO, 10.0, 20.0, Color.WHITE, 0.0, PI)
	m.line(Vector2.ZERO, Vector2(10, 10), 3.0, Color.WHITE)
	m.glow(Vector2.ZERO, Vector2(300, 300), Color.WHITE, 10, 0.5, 200.0)
	m.holed_round_rect(Rect2(-100, -80, 200, 160), 12.0, Color.WHITE, Color.BLACK, Vector2.ZERO, 60.0)
	m.round_frame(Rect2(-100, -80, 200, 160), 20.0, Rect2(-80, -60, 160, 120), 12.0, Color.WHITE, Color.BLACK)
	m.soft_shadow(Rect2(-100, -80, 200, 160), 12.0, 20.0, Color.BLACK, 30.0)
	_assert_batch(m, "shapes")
	# A hollow glow leaves its middle empty: no triangle reaches the centre.
	m.clear()
	m.glow(Vector2.ZERO, Vector2(300, 300), Color.WHITE, 10, 0.5, 200.0)
	for p in m.points:
		assert_float(p.length()).is_greater(150.0)
	assert_int(MeshBatch2D.round_rect_outline(Rect2(0, 0, 10, 10), 3.0).size()).is_equal(MeshBatch2D.round_rect_outline(Rect2(0, 0, 90, 50), 20.0).size())


func test_the_needle_and_the_swing_never_redraw_the_door_or_dial() -> void:
	var dial: SafeDial = auto_free(SafeDial.new())
	dial.position = Vector2(960, 645)
	add_child(dial)
	dial.target = 70
	dial.reading = 40.1
	dial.refresh()
	await _frames(3)
	var draws := {"door": 0, "dial": 0, "numerals": 0}
	dial.door.draw.connect(func() -> void: draws.door += 1)
	dial.draw.connect(func() -> void: draws.dial += 1)
	dial.numerals.draw.connect(func() -> void: draws.numerals += 1)
	# The reading moves within one whole number: the needle turns, nothing redraws.
	for k in 8:
		dial.reading = 40.1 + k * 0.04
		dial.refresh()
		await _frames(1)
	assert_float(dial.needle.rotation).is_equal_approx(SafeDial.angle_for(dial.reading), 0.0001)
	assert_int(draws.dial).override_failure_message("the dial redrew %d times for the needle" % draws.dial).is_equal(0)
	# The door swings: uniforms only.
	for k in 6:
		dial.door_open = k / 5.0
		dial.refresh()
		await _frames(1)
	assert_int(draws.door).override_failure_message("the door redrew %d times" % draws.door).is_equal(0)
	assert_int(draws.numerals).is_equal(0)
	var mat := dial.door.material as ShaderMaterial
	assert_float(float(mat.get_shader_parameter("angle"))).is_equal_approx(SafeDial.OPEN_ANGLE, 0.0001)
	assert_bool(dial.spill.visible).is_true()
	assert_bool(dial.vault.visible).is_true()
	dial.door_open = 0.0
	assert_float(float(mat.get_shader_parameter("angle"))).is_equal(0.0)
	assert_bool(dial.spill.visible).is_false()
	# Shut, the door covers the vault: it isn't drawn at all.
	assert_bool(dial.vault.visible).is_false()


func test_each_place_shows_only_its_own_ambient_life() -> void:
	var game := _game()
	var backdrop: SafeBackdrop = game.get("_backdrop")
	var own := {"office": ["rain"], "cabin": ["sea", "lantern"], "lab": ["flasks"]}
	for i in SafePlaces.count():
		var id: String = SafePlaces.place(i).id
		backdrop.set_place(i)
		var shows: Array = own.get(id, [])
		for part in ["rain", "sea", "lantern", "flasks"]:
			var node: CanvasItem = backdrop.get(part)
			assert_bool(node.visible).override_failure_message("%s in the %s" % [part, id]).is_equal(part in shows)
		assert_int(backdrop.dust.amount).is_less_equal(40)
		assert_bool(backdrop.dust.emitting).is_true()


func test_the_alarm_washes_the_room_and_glows_round_the_safe() -> void:
	var game := _game()
	var dial: SafeDial = game.get("_dial")
	var wash: CanvasItem = game.get("_wash")
	var logic: SafeLogic = game.get("logic")
	assert_bool(wash.visible).is_false()
	logic.alarm_left = 2.0
	game._handle({"type": "alarm"})
	await _frames(3)
	await await_millis(300)
	assert_bool(wash.visible).is_true()
	assert_float(wash.modulate.a).is_greater(0.0)
	assert_bool(dial.alarm_glow.visible).is_true()
	logic.alarm_left = 0.0
	await await_millis(500)
	assert_bool(wash.visible).is_false()
	assert_bool(dial.alarm_glow.visible).is_false()


## The tablet pays for every blended pixel: the room and its vignette are one baked texture,
## rendered once per place, never a frame.
func test_the_room_is_baked_once_per_place() -> void:
	var game := _game()
	var backdrop: SafeBackdrop = game.get("_backdrop")
	await _frames(3)
	assert_int(backdrop.bake.render_target_update_mode).is_not_equal(SubViewport.UPDATE_ALWAYS)
	assert_bool(backdrop.bake.transparent_bg).is_false()
	assert_object(backdrop.view.texture).is_same(backdrop.bake.get_texture())
	var before := backdrop.bakes
	var draws := [0]
	backdrop.room.draw.connect(func() -> void: draws[0] += 1)
	await _frames(5)
	assert_int(draws[0]).override_failure_message("the room redrew with nothing changed").is_equal(0)
	backdrop.set_place(2)
	await _frames(2)
	assert_int(backdrop.bakes).is_equal(before + 1)
	assert_int(draws[0]).is_equal(1)


## A place's room and body are built once, and the next safe's while the cracked door stands
## open, so the frame it slides in on builds nothing big.
func test_the_next_place_is_built_while_the_door_stands_open() -> void:
	var game := _game()
	MeshBatch2D.forget_built()
	game._handle({"type": "vault_open", "points": 1000.0})
	var next: int = game.get("_next_place")
	assert_int(next).is_not_equal(game.get("_place"))
	assert_bool(MeshBatch2D.is_built("room:%d" % next)).is_false()
	await await_millis(int((_door_sec() + 0.6) * 1000.0))
	assert_bool(MeshBatch2D.is_built("room:%d" % next)).override_failure_message("the next room wasn't built ahead").is_true()
	assert_bool(MeshBatch2D.is_built("body:%d" % next)).is_true()
	game._handle({"type": "new_vault"})
	assert_int(game.get("_place")).is_equal(next)
	assert_int(game.get("_next_place")).is_equal(-1)


static func _door_sec() -> float:
	return load("res://games/safe_cracker/SafeCracker.gd").DOOR_SEC
