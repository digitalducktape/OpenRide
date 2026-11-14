class_name KartClouds
extends RefCounted
## Kart Race's sky dressing (#43): soft cumulus cards far away over the hills, one MultiMesh per
## track, built by KartWorld.build. The cloud texture is drawn once and shared.

static var _cloud_tex: ImageTexture


## Soft cumulus cards far away, over the hills, in the theme's tint (`look`, KartLook's values),
## round `centre`.
static func build(parent: Node3D, look: Dictionary, centre: Vector3) -> void:
	var count: int = look.get("clouds", 26)
	if count <= 0:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.albedo_texture = _cloud_texture()
	mat.albedo_color = look.get("cloud", Color(1.0, 0.97, 0.93))
	mat.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 1.0)
	quad.material = mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Fewer, bigger cumulus: each a main card with one or two smaller cards overlapping it, a
	# little higher and to the side, so they read as banks, not rows of sausages (one MultiMesh).
	var xfs := []
	count = maxi(3, roundi(count * 0.6))
	for i in count:
		var a := TAU * i / count + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(600.0, 840.0)
		var sc := rng.randf_range(150.0, 280.0)
		var at := centre + Vector3(cos(a) * r, rng.randf_range(110.0, 240.0), sin(a) * r)
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		xfs.append(Transform3D(Basis().scaled(Vector3(sc, sc * 0.55, sc)), at))
		for j in 1 + int(rng.randf() < 0.5):
			var k := rng.randf_range(0.45, 0.7)
			var shift := tangent * sc * rng.randf_range(-0.7, 0.7) + Vector3.UP * sc * rng.randf_range(0.12, 0.25)
			xfs.append(Transform3D(Basis().scaled(Vector3(sc * k, sc * k * 0.55, sc * k)), at + shift - (at - centre).normalized() * 6.0))
	parent.add_child(MeshKit3D.multimesh_node(quad, xfs, "Clouds"))


static func _cloud_texture() -> ImageTexture:
	if _cloud_tex == null:
		# A cumulus: puffs piled into a dome over a flat base. Each puff is lit on its top and
		# shaded below; the base is a flat, cooler band.
		var img := Image.create(128, 64, true, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var blobs := []
		for i in 8:
			var x := lerpf(18.0, 110.0, i / 7.0) + rng.randf_range(-4, 4)
			var dome := 1.0 - pow((x - 64.0) / 52.0, 2.0)
			var rad := lerpf(11.0, 21.0, dome) * rng.randf_range(0.85, 1.1)
			blobs.append([Vector2(x, 46.0 - dome * 16.0 - rad * 0.35), rad])
		for y in 64:
			for x in 128:
				var a := 0.0
				var lit := 0.0
				for b in blobs:
					var d: Vector2 = Vector2(x, y) - b[0]
					var k: float = clampf(1.25 - d.length() / b[1], 0.0, 1.0)
					if k > a:
						a = k
						lit = clampf(-d.y / b[1], -1.0, 1.0)
				a *= smoothstep(50.0, 46.0, float(y))
				var shade := 0.88 + 0.12 * lit
				shade = lerpf(shade, 0.74, smoothstep(38.0, 47.0, float(y)))
				img.set_pixel(x, y, Color(shade * 0.98, shade * 0.98, shade * 1.04, clampf(a * 1.6, 0.0, 1.0)))
		img.generate_mipmaps()
		_cloud_tex = ImageTexture.create_from_image(img)
	return _cloud_tex
