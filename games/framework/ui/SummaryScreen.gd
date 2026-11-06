class_name SummaryScreen
extends CanvasLayer
## The session summary, from session_finished (sent after Kotlin saved the ride): each
## segment's result and stars, the totals and any bests. "Done" (or Android back) calls
## request_exit. Circuit mode (#37) adds its own sections with `add_section`.
##
## Two shapes, one tree (framework/ui/UI_STYLE.md):
##   - One game (a Just Ride): centred, in that game's look (`Game.ui_theme()`, else the house
##     look). The game's chip, the title, its three stars slamming in one by one, the points
##     and the time as tiles, the best as a badge, and Done.
##   - A circuit: the house look, the title across the top, the tiles, the best and Done on the
##     left, and a card per planned game on the right, each edged in its game's accent (a list
##     that scrolls when it's long).
##
##   SummaryScreen (CanvasLayer 40)
##   ├ backdrop: TextureRect, an opaque gradient (hides the idle scene; takes every touch)
##   └ frame: MarginContainer (full rect)
##     └ column: VBoxContainer
##       ├ header: VBoxContainer   chip row (game / CIRCUIT + kicker), title
##       └ body: HBoxContainer
##         ├ side: VBoxContainer   hero stars, note, tiles, best badge, sections, spacer, Done
##         └ list: VBoxContainer   ScrollContainer → rows (circuit), sections (circuit)
##
## Everything is laid out by containers; the entrance motion only tweens scale and modulate.

signal done_pressed

const LAYER := 40
const MARGIN_X := 56
const MARGIN_Y := 40
const SIDE_WIDTH := 600.0  ## the circuit's left column
const SINGLE_WIDTH := 1120.0  ## the one-game column
const DONE_SIZE := Vector2(560, 120)
const HERO_STAR := 132.0
const TITLE_SINGLE := 120  ## the one-game title: the screen's hero
const ROW_HEIGHT := 104.0
## Entrance timing (s): the title, then the chip, the stars one by one, the tiles, the best,
## the rows in turn. The whole of it lands within about 1.5 s; Done works from the first frame.
const AT_TITLE := 0.0
const AT_CHIP := 0.2
const AT_STARS := 0.4
const STAR_STEP := 0.22
const AT_TILES := 0.75
const TILE_STEP := 0.09
const AT_BEST := 1.1
const AT_ROWS := 0.35
const ROW_STEP := 0.07

## The look on screen: the game's in a one-game summary, else the house look.
var theme: GameTheme

var _backdrop: TextureRect
var _gradient: Gradient
var _column: VBoxContainer
var _header: VBoxContainer
var _chip_row: HBoxContainer
var _chip: PanelContainer
var _chip_label: Label
var _kicker: Label
var _title: Label
var _body: HBoxContainer
var _side: VBoxContainer
var _hero_stars: HBoxContainer
var _stars_note: Label
var _tiles: GridContainer
var _best: PanelContainer
var _best_head: Label
var _best_detail: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _extra: VBoxContainer
var _spacer: Control
var _top_spacer: Control
var done_button: Button
## For the summary_screen_test and the captures: the shape on screen ("single" or "circuit").
var shape := ""
var _entrance: Array[Tween] = []
var _hero_star_nodes: Array[BigStar] = []


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# Opaque: the idle scene ("OpenRide games") must not show through behind the list.
	_gradient = Gradient.new()
	var tex := GradientTexture2D.new()
	tex.gradient = _gradient
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 256
	_backdrop = TextureRect.new()
	_backdrop.texture = tex
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP  # takes every touch: only Done leaves
	Stage.bleed(_backdrop)
	add_child(_backdrop)

	var frame := MarginContainer.new()
	frame.size = Vector2(HudTheme.W, HudTheme.H)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_constant_override("margin_left", MARGIN_X)
	frame.add_theme_constant_override("margin_right", MARGIN_X)
	frame.add_theme_constant_override("margin_top", MARGIN_Y)
	frame.add_theme_constant_override("margin_bottom", MARGIN_Y)
	add_child(frame)
	_column = _vbox(frame, 22)

	_header = _vbox(_column, 6)
	_chip_row = HBoxContainer.new()
	_chip_row.add_theme_constant_override("separation", 22)
	_chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(_chip_row)
	_chip = PanelContainer.new()
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_row.add_child(_chip)
	_chip_label = Label.new()
	_chip.add_child(_chip_label)
	_kicker = Label.new()
	_kicker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_row.add_child(_kicker)
	_title = Label.new()
	_header.add_child(_title)

	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 44)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_body)
	_side = _vbox(_body, 20)
	# A one-game summary centres its column between the title and Done (this and `_spacer`).
	_top_spacer = Control.new()
	_top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(_top_spacer)

	_hero_stars = HBoxContainer.new()
	_hero_stars.alignment = BoxContainer.ALIGNMENT_CENTER
	_hero_stars.add_theme_constant_override("separation", 28)
	_hero_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(_hero_stars)
	for i in 3:
		var star := BigStar.new(HERO_STAR)
		_hero_stars.add_child(star)
		_hero_star_nodes.append(star)
	_stars_note = Label.new()
	_stars_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_side.add_child(_stars_note)

	_tiles = GridContainer.new()
	_tiles.add_theme_constant_override("h_separation", 16)
	_tiles.add_theme_constant_override("v_separation", 16)
	_tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(_tiles)

	_best = PanelContainer.new()
	_best.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(_best)
	var best_box := _vbox(_best, 0)
	_best_head = Label.new()
	_best_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_box.add_child(_best_head)
	_best_detail = Label.new()
	_best_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	best_box.add_child(_best_detail)

	_extra = _vbox(_side, 16)
	_spacer = Control.new()
	_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(_spacer)

	# Done: the screen's only target, big, at the bottom and far from anything else.
	done_button = Button.new()
	done_button.text = "Done"
	done_button.focus_mode = Control.FOCUS_NONE
	done_button.custom_minimum_size = DONE_SIZE
	done_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done_button.pressed.connect(func(): done_pressed.emit())
	_side.add_child(done_button)

	_list = _vbox(_body, 16)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = false
	_list.add_child(_scroll)
	_rows = _vbox(_scroll, 12)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.mouse_filter = Control.MOUSE_FILTER_PASS  # a drag on a row scrolls the list

	apply_theme(null)


## Styles the screen in `new_theme` (null: the house look). show_summary picks it.
func apply_theme(new_theme: GameTheme) -> void:
	theme = new_theme if new_theme else GameTheme.house()
	var top := theme.ink.lerp(theme.accent, 0.3)
	_gradient.colors = PackedColorArray([top, theme.ink.darkened(0.35)])
	_gradient.offsets = PackedFloat32Array([0.0, 1.0])
	_chip.add_theme_stylebox_override("panel", theme.badge_style())
	theme.style_label(_chip_label, HudTheme.BODY)
	theme.style_label(_kicker, HudTheme.SMALL, GameTheme.MUTED, true)
	theme.style_label(_title, HudTheme.BIG, GameTheme.INK, true)
	theme.set_gradient(_title)
	theme.style_label(_stars_note, HudTheme.BODY, GameTheme.MUTED, true)
	theme.style_label(_best_detail, HudTheme.SMALL, GameTheme.INK, true)
	for star in _hero_star_nodes:
		star.ink = theme.ink
	theme.style_button(done_button, GameTheme.PRIMARY)
	var bar := _scroll.get_v_scroll_bar()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(theme.ink, 0.6)
	track.set_corner_radius_all(8)
	track.content_margin_left = 6
	track.content_margin_right = 6
	bar.add_theme_stylebox_override("scroll", track)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(theme.accent, 0.9)
	grab.set_corner_radius_all(8)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(state, grab)


## Fills and shows the summary. `plan` is the session_started payload, for each segment's role.
## `looks` holds each game's `ui_theme()` by game_id (SessionDirector collects them); a game
## without one gets the house look.
func show_summary(summary: Dictionary, plan: Dictionary, looks: Dictionary = {}) -> void:
	_stop_entrance()
	# Freed now, not queued: a summary shown again in the same frame lays out only its own rows.
	for box in [_rows, _tiles]:
		for child in box.get_children():
			child.free()
	for child in _extra.get_children():
		child.queue_free()
	var results: Array = summary.get("results", [])
	var planned: Array = plan.get("segments", [])
	var is_circuit: bool = plan.get("kind", "") == "circuit"
	var single := not is_circuit and results.size() <= 1
	shape = "single" if single else "circuit"
	var first_id := ""
	if not results.is_empty():
		first_id = str(results[0].get("game_id", ""))
	elif not planned.is_empty():
		first_id = str(planned[0].get("game_id", ""))
	apply_theme(looks.get(first_id) if single else null)

	for i in results.size():
		var role := str(planned[i].get("role", "")) if i < planned.size() else ""
		var game_id := str(results[i].get("game_id", ""))
		_rows.add_child(_row(i, results[i], role, looks.get(game_id)))
	# A circuit ended early still lists every game it planned: the ones not reached say so.
	if is_circuit:
		for i in range(results.size(), planned.size()):
			_rows.add_child(_pending_row(i, planned[i], looks.get(str(planned[i].get("game_id", "")))))

	var totals: Dictionary = summary.get("totals", {})
	var stars := int(totals.get("stars", 0))
	var score := int(totals.get("score", 0))
	var elapsed := HudTheme.clock(float(totals.get("elapsed_sec", 0)))
	_title.text = title_for(plan, results.size())

	# The header: the game's chip in a one-game summary, CIRCUIT otherwise.
	var first_info := GameRegistry.info(first_id) if not first_id.is_empty() else null
	var played := results.filter(func(r): return not r.get("skipped", false)).size()
	if single:
		_chip_label.text = (first_info.title if first_info else first_id).to_upper()
		_chip.visible = not _chip_label.text.is_empty()
		var role := str(planned[0].get("role", "free")) if not planned.is_empty() else "free"
		_kicker.text = HudTheme.role_name(role).to_upper()
	else:
		_chip_label.text = "CIRCUIT"
		_chip.visible = true
		_kicker.text = ""  # the games tile says how many were played
	_chip.add_theme_stylebox_override("panel", theme.badge_style())
	_kicker.visible = not _kicker.text.is_empty()
	theme.style_label(_title, TITLE_SINGLE if single else HudTheme.BIG, GameTheme.INK, true)
	theme.set_gradient(_title)

	# The stars: three big ones for one game; the circuit's tally is a tile.
	_hero_stars.visible = single
	var lit := mini(stars, 3)
	for i in 3:
		_hero_star_nodes[i].lit = i < lit
	_stars_note.visible = single and (lit == 0 or results.is_empty())
	_stars_note.text = "No games finished this time." if results.is_empty() else "No stars this time. Next ride!"

	var extra := _stat_tiles(first_info, results) if single else []
	# A game's stat tiles share one row with points and time: a second row pushed Done off the
	# screen with the no-stars note and a best showing (seen on the bike).
	_tiles.columns = 2 + extra.size() if not extra.is_empty() else 2
	_add_tile("%d" % score, "points", GameTheme.TARGET)
	if not single:
		_add_tile("%d" % stars, "star" if stars == 1 else "stars", GameTheme.TARGET)
	_add_tile(elapsed, "ridden", GameTheme.INK)
	if not single:
		_add_tile("%d/%d" % [played, maxi(planned.size(), results.size())], "games", GameTheme.INK)
	for t in extra:
		_add_tile(t[0], t[1], GameTheme.INK)

	_show_best(summary.get("bests", {}))
	_layout(single)
	visible = true
	_play_entrance(single)


## A one-game summary's extra tiles from the game's `summary_stats` and its result's stats:
## [[value text, caption], ...], at most three (a row).
static func _stat_tiles(info: GameInfo, results: Array) -> Array:
	var out: Array = []
	if info == null or results.is_empty() or results[0].get("skipped", false):
		return out
	var stats: Dictionary = results[0].get("stats", {})
	for spec in info.summary_stats:
		if not stats.has(spec.key) or out.size() >= 3:
			continue
		var text := "%d%s" % [roundi(float(stats[spec.key])), str(spec.get("suffix", ""))]
		if spec.has("of") and stats.has(spec.of):
			text = "%d/%d" % [roundi(float(stats[spec.key])), roundi(float(stats[spec.of]))]
		out.append([text, str(spec.label)])
	return out


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
	var parts := best_parts(bests)
	if parts.is_empty():
		return ""
	if parts.beat:
		return "%s (before: %s)" % [parts.head, parts.previous] if not parts.previous.is_empty() else parts.head
	return "Your best: %s" % parts.previous


## The best, in parts for the badge: `{beat, head, previous}`, or {} when there is nothing to say.
static func best_parts(bests) -> Dictionary:
	if not (bests is Dictionary) or bests.is_empty():
		return {}
	var beat := bool(bests.get("score", false)) or bool(bests.get("stars", false))
	var previous := ""
	if bests.has("previous_score"):
		var stars := int(bests.get("previous_stars", 0))
		previous = "%d points, %d %s" % [int(bests.previous_score), stars, "star" if stars == 1 else "stars"]
	if not beat and previous.is_empty():
		return {}
	return {"beat": beat, "head": "New personal best!" if beat else "Your best", "previous": previous}


# --- Layout ---

func _layout(single: bool) -> void:
	_list.visible = not single
	# Shrunk to their text, so the entrance scales them about their own centre.
	var lead := Control.SIZE_SHRINK_CENTER if single else Control.SIZE_SHRINK_BEGIN
	_chip_row.size_flags_horizontal = lead
	_title.size_flags_horizontal = lead
	_body.alignment = BoxContainer.ALIGNMENT_CENTER
	_side.custom_minimum_size = Vector2(SINGLE_WIDTH if single else SIDE_WIDTH, 0)
	_side.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if single else Control.SIZE_FILL
	_tiles.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if single else Control.SIZE_FILL
	_best.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if single else Control.SIZE_FILL
	_best.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	_top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_top_spacer.visible = single
	done_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if single else Control.SIZE_FILL
	done_button.custom_minimum_size = DONE_SIZE if single else Vector2(SIDE_WIDTH, DONE_SIZE.y)
	# A circuit's own sections go under its list; a one-game summary keeps them in its column.
	var host: Container = _side if single else _list
	if _extra.get_parent() != host:
		_extra.reparent(host, false)
		if single:
			_side.move_child(_extra, _spacer.get_index())
	_scroll.scroll_vertical = 0


func _add_tile(value: String, caption: String, color: Color) -> void:
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := theme.panel_style()
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	tile.add_theme_stylebox_override("panel", style)
	tile.custom_minimum_size = Vector2(SIDE_WIDTH / 2 - 8 if _tiles.columns <= 2 else 250.0, 0)
	_tiles.add_child(tile)
	var box := _vbox(tile, 0)
	var v := theme.label(value, HudTheme.MEDIUM + 8, color, true)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(v)
	var c := theme.label(caption, HudTheme.SMALL, GameTheme.MUTED, true)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(c)


func _show_best(bests) -> void:
	var parts := best_parts(bests)
	_best.visible = not parts.is_empty()
	if parts.is_empty():
		return
	if parts.beat:
		# The callout: a gold badge in the ink, the one it beat under it.
		_best.add_theme_stylebox_override("panel", theme.badge_style(Color(GameTheme.TARGET, 0.96)))
		theme.style_label(_best_head, HudTheme.MEDIUM, theme.ink)
		_best_head.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.0))
		_best_head.add_theme_constant_override("outline_size", 0)
		_best_head.text = parts.head.to_upper()
		_best_detail.text = "before: %s" % parts.previous if not parts.previous.is_empty() else ""
		theme.style_label(_best_detail, HudTheme.SMALL, theme.ink, true)
		_best_detail.add_theme_constant_override("outline_size", 0)
	else:
		# What the rider is up against: a quiet panel.
		var style := theme.panel_style(Color(theme.ink, 0.7))
		style.border_color = Color(GameTheme.TARGET, 0.8)
		_best.add_theme_stylebox_override("panel", style)
		theme.style_label(_best_head, HudTheme.SMALL, GameTheme.MUTED, true)
		_best_head.text = parts.head.to_upper()
		theme.style_label(_best_detail, HudTheme.BODY, GameTheme.TARGET, true)
		_best_detail.text = parts.previous
	_best_detail.visible = not _best_detail.text.is_empty()


func _row(index: int, result: Dictionary, role: String, look) -> Control:
	var game_id := str(result.get("game_id", ""))
	var info := GameRegistry.info(game_id)
	var skipped: bool = result.get("skipped", false)
	var row := _card(index, info.title if info else game_id, role, look, false)
	var line: HBoxContainer = row.get_child(0)
	if skipped:
		line.add_child(_flat(theme.label("skipped", HudTheme.BODY, GameTheme.MUTED, true)))
	else:
		var score := _flat(theme.label("%d" % int(result.get("score", 0)), HudTheme.MEDIUM, GameTheme.INK, true))
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(score)
		var row_stars := StarRow.new(int(result.get("stars", 0)), 46.0)
		row_stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(row_stars)
	return row


## A planned game the session never got to: its name and role, and "not played".
func _pending_row(index: int, segment: Dictionary, look) -> Control:
	var game_id := str(segment.get("game_id", ""))
	var info := GameRegistry.info(game_id)
	var row := _card(index, info.title if info else game_id, str(segment.get("role", "")), look, true)
	row.get_child(0).add_child(_flat(theme.label("not played", HudTheme.BODY, GameTheme.MUTED, true)))
	return row


## A game's card: its number in a badge of the game's accent, its name and role, the card's
## edge in the accent too. The name gives way (ellipsis) before anything else does.
func _card(index: int, title: String, role: String, look, pending: bool) -> PanelContainer:
	var accent: Color = look.accent if look is GameTheme else theme.accent
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := theme.panel_style(Color(theme.ink.lerp(accent, 0.1), 0.6 if pending else 0.88))
	style.border_color = Color(accent, 0.35 if pending else 0.95)
	style.content_margin_left = 16
	style.content_margin_right = 26
	row.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 22)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_style := theme.badge_style(Color(accent.darkened(0.2), 0.5 if pending else 0.96))
	badge_style.content_margin_left = 16
	badge_style.content_margin_right = 16
	badge.add_theme_stylebox_override("panel", badge_style)
	badge.custom_minimum_size = Vector2(72, 0)
	line.add_child(badge)
	var number := _flat(theme.label("%d" % (index + 1), HudTheme.BODY, GameTheme.INK, true))
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(number)
	var names := _vbox(line, 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_label := _flat(theme.label(title, HudTheme.BODY, GameTheme.MUTED if pending else GameTheme.INK, true))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(120, 0)
	names.add_child(name_label)
	if not role.is_empty():
		names.add_child(_flat(theme.label(HudTheme.role_name(role), HudTheme.SMALL,
			GameTheme.MUTED if pending else HudTheme.role_color(role), true)))
	return row


## A card's text sits on the card's own solid fill, not on a 3D scene: no outline, so each label
## is one text pass (a long circuit's list stays inside the draw-call budget).
static func _flat(l: Label) -> Label:
	l.add_theme_constant_override("outline_size", 0)
	return l


# --- Motion ---

## The entrance: the title slams, the chip pops, each lit star slams in turn, the tiles and the
## best land, the rows fade in one after another. Scale and modulate only.
func _play_entrance(single: bool) -> void:
	_at(_title, AT_TITLE, "slam")
	_at(_chip_row, AT_CHIP, "pop")
	if single:
		for i in 3:
			var star := _hero_star_nodes[i]
			_at(star, AT_STARS + i * STAR_STEP, "slam" if star.lit else "fade")
	var t := 0
	for tile in _tiles.get_children():
		_at(tile, (AT_TILES if single else AT_ROWS) + t * TILE_STEP, "pop_in")
		t += 1
	if _best.visible:
		_at(_best, AT_BEST, "slam")
	var r := 0
	for row in _rows.get_children():
		_at(row, AT_ROWS + r * ROW_STEP, "fade")
		r += 1


## Runs a motion on `c` after `delay`, starting it hidden (alpha 0) so it doesn't flash first.
func _at(c: Control, delay: float, motion: String) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2.ONE
	var t := c.create_tween()
	t.tween_interval(delay)
	t.tween_callback(_run_motion.bind(c, motion))
	_entrance.append(t)


func _run_motion(c: Control, motion: String) -> void:
	match motion:
		"slam":
			GameTheme.slam(c, 1.7)
		"pop":
			c.modulate.a = 1.0
			GameTheme.pop(c, 1.15)
		"pop_in":
			GameTheme.slam(c, 1.25, 0.3)
		_:
			GameTheme.fade(c, true, 0.25)


## Ends a running entrance (a summary shown again) and settles everything it touched.
func _stop_entrance() -> void:
	for t in _entrance:
		if t.is_valid():
			t.kill()
	_entrance.clear()
	for c in [_title, _chip_row, _best] + _tiles.get_children() + _rows.get_children():
		GameTheme.stop(c)
		(c as Control).modulate.a = 1.0
		(c as Control).scale = Vector2.ONE
	for star in _hero_star_nodes:
		GameTheme.stop(star)
		star.modulate.a = 1.0
		star.scale = Vector2.ONE


## Whether the entrance has finished (for tests and captures).
func is_settled() -> bool:
	for t in _entrance:
		if t.is_valid() and t.is_running():
			return false
	var moving: Array = [_title, _chip_row, _best] + _tiles.get_children() + _rows.get_children() + _hero_star_nodes
	for c in moving:
		for key in [&"_ui_pop", &"_ui_fade"]:
			var t: Tween = c.get_meta(key) if c.has_meta(key) else null
			if t and t.is_valid() and t.is_running():
				return false
	return true


func _vbox(parent: Node, separation: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	return box


## One big star drawn as a shape, with an ink edge: lit gold or a dim socket.
class BigStar:
	extends Control

	var lit := false:
		set(value):
			lit = value
			queue_redraw()
	var ink := Color(0.1, 0.08, 0.25):
		set(value):
			ink = value
			queue_redraw()
	var _size := 120.0

	func _init(size_px: float) -> void:
		_size = size_px
		custom_minimum_size = Vector2(size_px, size_px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var centre := size / 2.0
		var batch := ShapeBatch.new()
		batch.star(centre, _size * 0.5, ink if lit else Color(ink, 0.7))
		batch.star(centre + Vector2(0, 2), _size * 0.5 - 10.0, HudTheme.STAR_ON if lit else Color(1, 1, 1, 0.14))
		if lit:
			# A glint on the upper left arm.
			batch.circle(centre + Vector2(-_size * 0.1, -_size * 0.14), _size * 0.06, Color(1, 1, 1, 0.55))
		batch.draw(self)
