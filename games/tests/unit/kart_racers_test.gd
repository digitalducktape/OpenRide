extends GdUnitTestSuite
## Kart Race's racers (#43): every racer builds inside the tablet budget (about 3k triangles and
## two materials a kart with its driver, four draw calls), the anchors exist, the rig poses
## (wheels, lean, cheer, spin-out, blink, shadow) and the roster's data holds together.

const DT := 1.0 / 60.0
const MAX_TRIS := 3000


func _view(r: Dictionary) -> KartView:
	var v: KartView = auto_free(KartView.new())
	v.setup(r)
	add_child(v)
	return v


func _state(speed := 0.0) -> KartState:
	var k := KartState.new()
	k.speed = speed
	return k


func _angle(b: Basis, axis: Vector3) -> float:
	# How far `b` turns `axis`, radians.
	return (b * axis.normalized()).angle_to(axis.normalized())


func test_every_racer_fits_the_triangle_budget() -> void:
	for r in KartRoster.RACERS:
		var tris := MeshKit3D.tri_count(KartView.model_mesh(r))
		assert_int(tris).override_failure_message("%s: %d triangles" % [r.id, tris]).is_less_equal(MAX_TRIS)
		assert_int(tris).is_greater(1500)
		assert_int(MeshKit3D.tri_count(KartView.head_mesh(r))).is_greater(300)


func test_every_vertex_carries_a_bone_and_its_shader_flags() -> void:
	for r in KartRoster.RACERS:
		var arrays := KartView.model_mesh(r).surface_get_arrays(0)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		assert_int(uv.size()).is_equal(verts.size())
		assert_int(uv2.size()).is_equal(verts.size())
		var used := {}
		for b in uv2:
			assert_bool(b.x >= 0.0 and b.x < KartModels.BONES.size()).is_true()
			used[int(b.x)] = true
		# The body, driver, head, eyes, arms, steering wheel and four wheels all have vertices.
		for bone in [KartModels.BODY, KartModels.DRIVER, KartModels.HEAD, KartModels.EYES, KartModels.ARM_L,
				KartModels.ARM_R, KartModels.STEER, KartModels.WHEEL_FL, KartModels.WHEEL_RR]:
			assert_bool(used.has(bone)).override_failure_message("%s: bone %d unused" % [r.id, bone]).is_true()


func test_a_kart_is_four_draws_and_two_materials() -> void:
	for r in KartRoster.RACERS:
		var v := _view(r)
		var geometry := v.find_children("*", "GeometryInstance3D", true, false)
		assert_int(geometry.size()).is_equal(3)  # model (+ its outline pass), number, shadow: 4 draws
		var model: MeshInstance3D = v.find_child("Model", true, false)
		var mats := 0
		var m: Material = model.material_override
		while m:
			mats += 1
			m = m.next_pass
		assert_int(mats).is_less_equal(2)


func test_every_racer_has_every_anchor() -> void:
	for r in KartRoster.RACERS:
		var v := _view(r)
		for a in KartView.ANCHORS:
			assert_object(v.anchor(a)).override_failure_message("%s: no anchor %s" % [r.id, a]).is_not_null()


func test_the_wheels_spin_with_speed_and_the_front_ones_steer() -> void:
	var v := _view(KartRoster.racer("fox"))
	var k := _state(10.0)
	k.steer = 1.0
	for i in 5:
		v.sync(k, DT)
	var fl := v.bone_pose("wheel_fl").basis
	var rl := v.bone_pose("wheel_rl").basis
	assert_float(_angle(rl, Vector3.UP)).is_greater(0.5)  # spinning about the axle
	# The front wheel's axle turns with the steering; the rear one's doesn't.
	assert_float(_angle(fl, Vector3.RIGHT)).is_greater(0.3)
	assert_float(_angle(rl, Vector3.RIGHT)).is_less(0.01)
	var still := _view(KartRoster.racer("panda"))
	still.sync(_state(0.0), DT)
	assert_float(_angle(still.bone_pose("wheel_rl").basis, Vector3.UP)).is_less(0.01)


func test_the_body_and_driver_lean_into_a_turn() -> void:
	var v := _view(KartRoster.racer("bear"))
	var k := _state(15.0)
	k.steer = 1.0
	for i in 60:
		v.sync(k, DT)
	var body_up := v.bone_pose("body").basis * Vector3.UP
	var driver_up := v.bone_pose("driver").basis * Vector3.UP
	# Steering right: roll to the right (+x), the driver further.
	assert_float(body_up.x).is_greater(0.02)
	assert_float(driver_up.x).is_greater(body_up.x)


func test_the_body_takes_the_physics_drift_slide() -> void:
	var v := _view(KartRoster.racer("bear"))
	var k := _state(15.0)
	k.drift_dir = 1
	k.slide = -0.5  # a right drift: nose right
	v.sync(k, DT)
	assert_float(v.slide).is_equal(-0.5)
	var nose := v.bone_pose("body").basis * Vector3.FORWARD
	assert_float(nose.x).is_greater(0.3)  # turned right
	k.drift_dir = 0
	k.slide = 0.0
	v.sync(k, DT)
	assert_float(v.slide).is_equal(0.0)


func test_a_podium_finisher_cheers_with_both_arms() -> void:
	var v := _view(KartRoster.racer("rabbit"))
	var k := _state(5.0)
	k.finished = true
	k.place = 1
	for i in 40:
		v.sync(k, DT)
	for arm in ["arm_l", "arm_r"]:
		assert_float(v.bone_pose(arm).basis.get_rotation_quaternion().get_angle()).is_greater(1.0)
	# The eyes squint happily.
	assert_float(v.bone_pose("eyes").basis.get_scale().y).is_less(0.5)


func test_a_spin_out_squeezes_the_eyes_shut() -> void:
	var v := _view(KartRoster.racer("otter"))
	var k := _state(8.0)
	k.spin_time = 0.6
	v.sync(k, DT)
	assert_float(v.bone_pose("eyes").basis.get_scale().y).is_less(0.3)
	k.spin_time = 0.0
	for i in 3:
		v.sync(k, DT)
	assert_float(v.bone_pose("eyes").basis.get_scale().y).is_greater(0.3)


func test_the_driver_blinks() -> void:
	var v := _view(KartRoster.racer("frog"))
	var k := _state(0.0)
	var closed := false
	for i in 60 * 7:
		v.sync(k, DT)
		if v.bone_pose("eyes").basis.get_scale().y < 0.5:
			closed = true
	assert_bool(closed).is_true()


func test_the_shadow_stays_on_the_ground_when_hopping() -> void:
	var v := _view(KartRoster.racer("penguin"))
	var k := _state(10.0)
	k.pos = Vector3(3, 2, -4)
	k.hop = 0.4
	v.sync(k, DT)
	assert_float(v.anchor("shadow").global_position.y).is_equal_approx(2.035, 0.01)
	# The body rises with the hop.
	assert_float(v.bone_pose("body").origin.y).is_greater(0.25 + 0.35)


func test_the_roster_is_eight_distinct_racers() -> void:
	var ids := KartRoster.ids()
	assert_int(ids.size()).is_equal(8)
	var seen := {}
	var numbers := {}
	for r in KartRoster.RACERS:
		assert_bool(seen.has(r.id)).is_false()
		seen[r.id] = true
		numbers[r.number] = true
		assert_str(KartRoster.kart_class(r)).is_not_empty()
		assert_bool(KartRoster.kart_class(r) in KartRoster.KART_CLASSES).is_true()
		var w: float = r.weight
		assert_float(w).is_between(0.85, 1.15)
	assert_int(numbers.size()).is_equal(8)
	assert_int(KartRoster.names().size()).is_equal(8)
	assert_int(KartRoster.option_labels().size()).is_equal(8)
	assert_str(KartRoster.option_labels()[0]).contains(KartRoster.names()[0])
	# Every class is used.
	var classes := {}
	for r in KartRoster.RACERS:
		classes[KartRoster.kart_class(r)] = true
	assert_int(classes.size()).is_equal(3)


func test_the_kart_colours_are_far_apart() -> void:
	# The HUD's racer list and minimap tell racers apart by colour.
	var rs := KartRoster.RACERS
	for i in rs.size():
		for j in range(i + 1, rs.size()):
			var a: Color = rs[i].color
			var b: Color = rs[j].color
			var dh := absf(a.h - b.h)
			dh = minf(dh, 1.0 - dh)
			assert_bool(dh > 0.04 or absf(a.v - b.v) > 0.3) \
				.override_failure_message("%s and %s look alike" % [rs[i].id, rs[j].id]).is_true()


func test_the_lineup_puts_the_riders_pick_first() -> void:
	var l := KartRoster.lineup("otter")
	assert_int(l.size()).is_equal(8)
	assert_str(l[0].id).is_equal("otter")
	assert_str(KartRoster.lineup("nobody")[0].id).is_equal("fox")


func test_the_riders_kart_carries_their_profile_name() -> void:
	assert_str(KartRoster.rider_label("  Ed ")).is_equal("Ed")
	assert_str(KartRoster.rider_label("Mary   Jane")).is_equal("Mary Jane")
	assert_str(KartRoster.rider_label("")).is_equal("You")
	assert_str(KartRoster.rider_label("   ")).is_equal("You")
	var long := KartRoster.rider_label("Bartholomew Fitzgerald")
	assert_int(long.length()).is_less_equal(KartRoster.NAME_MAX)
	assert_bool(long.ends_with("…")).is_true()
	assert_str(KartRoster.rider_label("Twelve chars")).is_equal("Twelve chars")
	# The rider's entry is a copy with their name; the animal is the picked kart's, and the
	# bots (and the roster) keep their own names.
	var l := KartRoster.lineup("otter", 8, "Ed")
	assert_str(l[0].name).is_equal("Ed")
	assert_str(l[0].id).is_equal("otter")
	assert_str(l[0].species).is_equal("otter")
	assert_str(KartRoster.racer("otter").name).is_equal("Ripple")
	for r in l.slice(1):
		assert_str(r.name).is_equal(KartRoster.racer(r.id).name)
	# The longest name fits the racer list's chip.
	assert_int(KartRacerList.fit_size("Bartholomew…", 160.0, 36, 22)).is_less(36)
	assert_int(KartRacerList.fit_size("Ed", 160.0, 36, 22)).is_equal(36)


func test_every_horn_renders() -> void:
	for id in KartRoster.ids():
		var samples := SfxSynth.render_samples(KartRoster.horn_preset(id))
		assert_int(samples.size()).is_greater(1000)


func test_the_kart_sounds_register_every_racers_horn() -> void:
	KartSfx.register()
	for id in KartRoster.ids():
		assert_bool(SfxSynth._presets.has(KartSfx.horn(id))).override_failure_message("no horn for %s" % id).is_true()


func test_portrait_framing_fits_the_tallest_ears() -> void:
	var mesh := KartView.head_mesh(KartRoster.racer("rabbit"))
	var f := KartPortraits.framing(mesh)
	var top: float = mesh.get_aabb().end.y
	var eye: Vector3 = f.eye
	var at: Vector3 = f.at
	var half := tan(deg_to_rad(float(f.fov) * 0.5)) * eye.distance_to(at)
	assert_float(at.y + half).is_greater(top)


func test_from_behind_the_helmet_is_the_racer_s_colour() -> void:
	# The chase camera sees the back of the helmet most: in the kart's colour (Juniper's white
	# "egg" is gone), scaled down with the head, with the number above the visor band.
	var fox: Dictionary = KartRoster.RACERS[0]
	var c := KartModels.helmet_color(fox)
	assert_bool(c.is_equal_approx(Color(fox.color.r, fox.color.g, fox.color.b, 1.0))).is_true()
	assert_float(KartModels.HEAD_SCALE).is_less(1.0)
	var hr := KartModels.helmet_radii(fox)
	var axle: float = absf((KartModels.layout("medium").wheels[2] as Vector3).x) * 2.0
	assert_float(hr.x * 2.0).is_less_equal(axle * 0.45)
