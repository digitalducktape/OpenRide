class_name StageView3D
extends SubViewport
## A 3D game's view (first built for Tug of War; every 3D game but Kart Race uses it): this SubViewport renders
## the world at a fraction of the screen's resolution, and `image` (a MeshInstance2D the game adds
## beside it) draws it scaled up over the whole visible canvas, under the HUD. The vignette is in
## the image's vertex colours, so it costs nothing a pixel. The view follows the wide stage
## (`Stage.changed`) and owns the game's one quality step (`RenderScaleStep`).
##
##   view = StageView3D.new(RENDER_SCALE)
##   add_child(view)            # "View3D"
##   view.add_child(world)
##   add_child(view.image)      # "View3DImage"
##   ...
##   view.reset_quality()                       # in _on_prepare
##   view.sample(delta, a_frame_that_counts, game_id)   # in _on_frame

const COLS := 16
const ROWS := 9

## The share of the screen's resolution the view renders at before any quality step.
var base_scale := 0.62
## The share it renders at now.
var render_scale := 0.62
var image: MeshInstance2D
var governor := RenderScaleStep.new()
## How dark the image's corners go (0 none), and the tint they lean to.
var vignette := 0.32
var vignette_tint := Color(0.75, 0.8, 1.05)


func _init(scale := 0.62) -> void:
	base_scale = scale
	render_scale = scale
	name = "View3D"
	msaa_3d = Viewport.MSAA_DISABLED
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	audio_listener_enable_3d = false
	image = MeshInstance2D.new()
	image.name = "View3DImage"
	image.texture = get_texture()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _ready() -> void:
	fit()
	Stage.changed.connect(fit)


## A new segment starts at full quality (the governor only ever steps down).
func reset_quality() -> void:
	governor = RenderScaleStep.new()
	set_render_scale(base_scale)


## One frame of `delta` seconds, judged only when it `counts` (play, not an intro or a result).
## Steps the render scale down, once, when the frame rate has sagged; logs it for `adb logcat`.
func sample(delta: float, counts: bool, game_id: String) -> void:
	if governor.sample(delta, counts):
		set_render_scale(governor.render_scale(base_scale))
		print("OPENRIDE_GAMES %s quality tier=%d fps=%.1f scale=%.2f" % [game_id, governor.tier, governor.last_fps, render_scale])


## Fits the image and the view to the canvas the window shows.
func fit() -> void:
	image.position = -Stage.pad
	image.mesh = view_image(Stage.visible_size, vignette, vignette_tint)
	set_render_scale(render_scale)


func set_render_scale(scale: float) -> void:
	render_scale = scale
	var px := Stage.view_size(scale)
	if size != px:
		size = px


## The view's multiplier at screen UV `suv`: 1 in the middle, darker and tinted to the corners.
static func vignette_at(suv: Vector2, strength: float, tint_to: Color) -> Color:
	var p := suv * 2.0 - Vector2.ONE
	p.x *= 1.35
	var v := smoothstep(0.7, 1.75, p.length())
	var m := 1.0 - v * strength
	var tint := Color.WHITE.lerp(tint_to, v * 0.5)
	return Color(m * tint.r, m * tint.g, m * tint.b)


## The grid that draws the 3D view's image at `on_screen` pixels, the vignette in its vertex
## colours (display values, so the linear multiplier goes to the power 1/2.2).
static func view_image(on_screen: Vector2, strength: float, tint_to: Color) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for j in ROWS + 1:
		for i in COLS + 1:
			var uv := Vector2(float(i) / COLS, float(j) / ROWS)
			verts.append(uv * on_screen)
			uvs.append(uv)
			var m := vignette_at(uv, strength, tint_to)
			cols.append(Color(pow(m.r, 1.0 / 2.2), pow(m.g, 1.0 / 2.2), pow(m.b, 1.0 / 2.2)))
	for j in ROWS:
		for i in COLS:
			var a := j * (COLS + 1) + i
			var c := a + COLS + 1
			idx.append_array([a, a + 1, c, a + 1, c + 1, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
