class_name SummaryScreen
extends CanvasLayer
## The session summary, from session_finished (sent after Kotlin saved the ride): each
## segment's result and stars, the totals and any bests. "Done" (or Android back) calls
## request_exit. Circuit mode (#37) adds its own sections with `add_section`.

signal done_pressed

const LAYER := 40

var _title: Label
var _rows: VBoxContainer
var _totals: Label
var _total_stars: StarRow
var _bests: Label
var _extra: VBoxContainer
var done_button: Button


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.12, 0.97)
	bg.size = Vector2(HudTheme.W, HudTheme.H)
	add_child(bg)

	var m := HudTheme.MARGIN * 2
	var column := VBoxContainer.new()
	column.position = Vector2(m, m * 0.75)
	column.size = Vector2(HudTheme.W - 2 * m, HudTheme.H - m * 1.5)
	column.add_theme_constant_override("separation", 18)
	add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 40)
	column.add_child(head)
	_title = HudTheme.label("Session complete", HudTheme.BIG)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_total_stars = StarRow.new(0, 80.0)
	_total_stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_total_stars)

	_totals = HudTheme.label("", HudTheme.MEDIUM, HudTheme.WARN)
	column.add_child(_totals)
	_bests = HudTheme.label("", HudTheme.BODY, HudTheme.GOOD)
	column.add_child(_bests)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)

	_extra = VBoxContainer.new()
	column.add_child(_extra)

	done_button = HudTheme.button("Done", func(): done_pressed.emit(), Color(0.16, 0.45, 0.3))
	done_button.custom_minimum_size = Vector2(420, HudTheme.BUTTON_HEIGHT)
	done_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(done_button)


## Fills and shows the summary. `plan` is the session_started payload, for each segment's role.
func show_summary(summary: Dictionary, plan: Dictionary) -> void:
	for child in _rows.get_children():
		child.queue_free()
	for child in _extra.get_children():
		child.queue_free()
	var results: Array = summary.get("results", [])
	var planned: Array = plan.get("segments", [])
	for i in results.size():
		var role := str(planned[i].get("role", "")) if i < planned.size() else ""
		_rows.add_child(_row(i, results[i], role))
	if results.is_empty():
		_rows.add_child(HudTheme.label("No games finished this time.", HudTheme.BODY, HudTheme.MUTED))

	var totals: Dictionary = summary.get("totals", {})
	var stars := int(totals.get("stars", 0))
	_total_stars.stars = mini(stars, 3) if results.size() <= 1 else 0
	_total_stars.visible = results.size() <= 1
	_totals.text = "%d points   ·   %d %s   ·   %s ridden" % [
		int(totals.get("score", 0)), stars, "star" if stars == 1 else "stars",
		HudTheme.clock(float(totals.get("elapsed_sec", 0)))]
	_bests.text = bests_text(summary.get("bests", {}))
	_bests.visible = not _bests.text.is_empty()
	_title.text = "Circuit complete" if plan.get("kind", "") == "circuit" else "Ride complete"
	visible = true


## A section below the results, for circuit mode (#37) and later additions.
func add_section(section: Control) -> void:
	_extra.add_child(section)


## The bests the summary carries, one line. Kotlin (#35) sends `{"score": true}` and/or
## `{"stars": true}` when the session beat the rider's best at this plan and difficulty; this
## lists whatever keys are truthy ("Personal best: score, stars").
static func bests_text(bests) -> String:
	if not (bests is Dictionary) or bests.is_empty():
		return ""
	var names := PackedStringArray()
	for key in bests:
		var value = bests[key]
		if value is bool:
			if value:
				names.append(str(key).replace("_", " "))
		elif value != null:
			names.append("%s %s" % [str(key).replace("_", " "), str(value)])
	return "" if names.is_empty() else "Personal best: " + ", ".join(names)


func _row(index: int, result: Dictionary, role: String) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", HudTheme.panel_style(Color(1, 1, 1, 0.05), 14))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 32)
	row.add_child(line)
	var game_id := str(result.get("game_id", ""))
	var info := GameRegistry.info(game_id)
	var name_label := HudTheme.label("%d.  %s" % [index + 1, info.title if info else game_id], HudTheme.BODY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	if not role.is_empty():
		line.add_child(HudTheme.label(HudTheme.role_name(role), HudTheme.SMALL, HudTheme.role_color(role)))
	if result.get("skipped", false):
		line.add_child(HudTheme.label("skipped", HudTheme.BODY, HudTheme.MUTED))
	else:
		line.add_child(HudTheme.label("%d" % int(result.get("score", 0)), HudTheme.BODY))
		line.add_child(StarRow.new(int(result.get("stars", 0)), 44.0))
	return row
