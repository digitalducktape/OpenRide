class_name BakedBackdrop
extends Node2D
## A painted backdrop baked once into a texture and shown as one opaque sprite (from Safe
## Cracker's room; Keepy Uppy's and Ready for Launch's places use it too). The game adds what it
## paints with `add_painted`; `rebake` renders it once, at the size the canvas is shown on screen
## (2090x1008 for the painted scene on the bike's 1920x1008 panel), so the sprite maps one texel
## to one pixel. It bakes again by itself when the window's size changes, while it's visible.
##
## `canvas` is the stage (1920x1080), `wide` the painted size past the stage's sides (#57) and
## `bleed` how far the painting starts left of the stage: painted nodes sit at x = bleed in the
## bake, and this node's sprite at x = -bleed on the stage.

var bake: SubViewport
var view: Sprite2D
var bakes := 0  ## renders made, for tests

var _canvas: Vector2
var _wide: Vector2


func _init(canvas: Vector2, wide: Vector2, bleed: float, bake_name := "SceneBake", view_name := "Scene") -> void:
	_canvas = canvas
	_wide = wide
	bake = SubViewport.new()
	bake.name = bake_name
	bake.disable_3d = true
	bake.transparent_bg = false
	bake.gui_disable_input = true
	bake.size_2d_override = Vector2i(wide)
	bake.size_2d_override_stretch = true
	bake.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(bake)
	view = Sprite2D.new()
	view.name = view_name
	view.centered = false
	view.position = Vector2(-bleed, 0)
	view.texture = bake.get_texture()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(view)


## Adds a node the bake draws (a painted layer, a vignette), in order.
func add_painted(node: Node) -> void:
	bake.add_child(node)


func _enter_tree() -> void:
	if not get_tree().root.size_changed.is_connected(_on_window_resized):
		get_tree().root.size_changed.connect(_on_window_resized)
	_on_window_resized()


func _exit_tree() -> void:
	if get_tree().root.size_changed.is_connected(_on_window_resized):
		get_tree().root.size_changed.disconnect(_on_window_resized)


func _on_window_resized() -> void:
	if visible:
		rebake()


## Renders the painted nodes once, at the size the canvas is shown on screen.
func rebake() -> void:
	if not is_inside_tree():
		return
	var win := Vector2(get_tree().root.size)
	var s := clampf(minf(win.x / _canvas.x, win.y / _canvas.y), 0.25, 1.0)
	var px := Vector2i((_wide * s).ceil())
	if bake.size != px:
		bake.size = px
	view.scale = _wide / Vector2(px)
	for child in bake.get_children():
		if child is CanvasItem:
			(child as CanvasItem).queue_redraw()
	bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	bakes += 1
