class_name GridIntroVisual
extends HBoxContainer
## The intro card's picture: the valley itself, lit (the hub card's render, masked to a rounded
## frame), then the four districts with their icons and the watts each one asks. Every number comes
## from the segment's params through `GridLogic`; nothing is hard-coded. A work ride adds what a
## storm's repair will ask at its peak; an easy ride says it has no storms. Built once, no per-frame cost.

const PICTURE := Vector2(444, 250)
const CORNER := 22.0
const ICON := Vector2(62, 52)
const PICTURE_PATH := "res://games/power_grid/hub_card.png"
const MaskShader := preload("res://framework/ui/shaders/rounded_mask.gdshader")


func _init(theme: GameTheme, logic: GridLogic) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 36)
	add_child(_picture())
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 2)
	add_child(words)
	var grid := GridContainer.new()
	grid.name = "Districts"
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 2)
	words.add_child(grid)
	for i in GridLogic.COUNT:
		grid.add_child(_district(theme, i, logic))
	var line := "No storms tonight" if logic.is_easy() else "Storms: hold %d W more for %d s" % [roundi(logic.storm_watts), roundi(GridLogic.STORM_REPAIR_SEC)]
	var note := theme.label(line, HudTheme.SMALL + 6, GameTheme.MUTED, true)
	note.name = "StormLine"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_child(note)


func _picture() -> Control:
	var pic := TextureRect.new()
	pic.name = "Valley"
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.custom_minimum_size = PICTURE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.texture = load(PICTURE_PATH) as Texture2D
	var mask := ShaderMaterial.new()
	mask.shader = MaskShader
	mask.set_shader_parameter("rect_size", PICTURE)
	mask.set_shader_parameter("radius", CORNER)
	pic.material = mask
	return pic


## A district's icon and the watts it comes on at.
func _district(theme: GameTheme, i: int, logic: GridLogic) -> Control:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	var col: Color = GridStatus.DISTRICT_COLORS[i]
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = ICON
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.draw.connect(func() -> void:
		var b := ShapeBatch.new()
		GridStatus.draw_icon(b, i, ICON * 0.5, 1.0, col)
		b.draw(icon))
	box.add_child(icon)
	var watts := lerpf(logic.lo, logic.hi, float(GridLogic.STEPS[i])) * GridLogic.HEADROOM
	var l := theme.label("%d W" % roundi(watts), HudTheme.BODY, col, true)
	l.name = "Watts%d" % i
	box.add_child(l)
	return box
