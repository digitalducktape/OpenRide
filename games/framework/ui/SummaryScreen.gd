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
	var is_circuit: bool = plan.get("kind", "") == "circuit"
	for i in results.size():
		var role := str(planned[i].get("role", "")) if i < planned.size() else ""
		_rows.add_child(_row(i, results[i], role))
	# A circuit ended early still lists every game it planned: the ones not reached say so.
	if is_circuit:
		for i in range(results.size(), planned.size()):
			_rows.add_child(_pending_row(i, planned[i]))
	if results.is_empty() and not is_circuit:
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
	_title.text = title_for(plan, results.size())
	visible = true


## The heading: a circuit that played every game is complete; one ended early says so.
static func title_for(plan: Dictionary, played: int) -> String:
	if plan.get("kind", "") != "circuit":
		return "Ride complete"
	return "Circuit complete" if played >= plan.get("segments", []).size() else "Session ended early"


## A section below the results, for circuit mode (#37) and later additions.
func add_section(section: Control) -> void:
	_extra.add_child(section)


## The line about the rider's best. Kotlin (#35) sends `{"score": true}` and/or `{"stars": true}`
## when the session beat the rider's best at this plan and difficulty, and `previous_score` and
## `previous_stars` for the best before it. So: "New personal best!" (with the one it beat), or
## "Your best: 5400 points, 2 stars" when this session didn't beat it, or nothing on a first play
## that scored nothing.
static func bests_text(bests) -> String:
	if not (bests is Dictionary) or bests.is_empty():
		return ""
	var beat := bool(bests.get("score", false)) or bool(bests.get("stars", false))
	var has_previous: bool = bests.has("previous_score")
	var previous := ""
	if has_previous:
		var stars := int(bests.get("previous_stars", 0))
		previous = "%d points, %d %s" % [int(bests.previous_score), stars, "star" if stars == 1 else "stars"]
	if beat:
		return "New personal best! (before: %s)" % previous if has_previous else "New personal best!"
	return "Your best: %s" % previous if has_previous else ""


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


## A planned game the session never got to: its name and role, and "not played".
func _pending_row(index: int, segment: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", HudTheme.panel_style(Color(1, 1, 1, 0.025), 14))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 32)
	row.add_child(line)
	var game_id := str(segment.get("game_id", ""))
	var info := GameRegistry.info(game_id)
	var name_label := HudTheme.label("%d.  %s" % [index + 1, info.title if info else game_id], HudTheme.BODY, HudTheme.MUTED)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var role := str(segment.get("role", ""))
	if not role.is_empty():
		line.add_child(HudTheme.label(HudTheme.role_name(role), HudTheme.SMALL, HudTheme.MUTED))
	line.add_child(HudTheme.label("not played", HudTheme.BODY, HudTheme.MUTED))
	return row
