class_name BuilderScreen
extends HubScreen
## The circuit builder (spec §8.3): the rider adds games and sets each one's length, then saves
## it as "My circuit n" (up to 3, HubPrefs) or just starts it. No keyboard: lengths are −/+,
## names are the place ("My circuit 2"). The rules are CircuitBuilder's (Kotlin's
## SessionPlans.custom mirrored); this screen only draws them.
##
##   BuilderScreen
##   ├ TopBar: Back, "BUILD A CIRCUIT" | "MY CIRCUIT 2"
##   ├ Tiles (OptionCards, "ADD A GAME": one baked tile per game; a tap adds it)
##   ├ List (ScrollContainer, drag or its bar to scroll) → VBox of SlotRow (or the empty note)
##   ├ Difficulty (OptionRow, segmented)
##   ├ Right (VBox): Summary (HubCard bake: the total, the lineup), best, why it can't start,
##   │   spacer, Save (+ Delete for a saved one), Start
##   └ Replace (a panel over the left column when 3 are saved: which to replace)
##
## Args: `index` (the saved place being edited, or -1), `draft` (the lineup being built: kept
## in the nav stack's args, so it survives playing it and coming back).
## Nothing is saved until Save; ✕ isn't confirmed (adding the game again undoes it). Replacing
## and deleting a saved circuit are confirmed, and so is leaving with unsaved changes.

const LEFT_WIDTH := 1280.0
const RIGHT_X := HubTheme.MARGIN + LEFT_WIDTH + 48.0
const RIGHT_W := HubTheme.W - HubTheme.MARGIN - RIGHT_X
const TILES_TOP := 150.0
const BODY_BOTTOM := 1050.0
const TILE_ASPECT := 0.32
const TILE_COLUMNS_MAX := 6  ## more games wrap to a second row of tiles (#75: 11 games, 6 + 5)
const SCROLLBAR_W := 44.0
const ROW_GAP := 24
const SUMMARY_SIZE := Vector2(RIGHT_W, 330)
const START_SIZE := Vector2(RIGHT_W, 170)

var builder: CircuitBuilder
var index := -1
var tiles: OptionCards
var scroll: ScrollContainer
var list: VBoxContainer
var rows: Array[SlotRow] = []
var difficulty_row: OptionRow
var save_button: Button
var delete_button: Button
var start_button: Button
var replace_panel: PanelContainer
var empty_note: Label
var summary_total: Label
var summary_line: Label
var strip: LineupStrip
var best_label: Label
var problem_label: Label
var _title: Label
var _waiting := false


func build() -> void:
	index = int(args.get("index", -1))
	var saved = HubPrefs.custom_circuit(rider_id, index)
	if saved == null:
		index = -1
	var source = args.get("draft")
	if not (source is Dictionary):
		source = saved if saved != null else {"slots": [], "difficulty": str(HubPrefs.get_pick(rider_id, "custom.difficulty", "standard"))}
	builder = CircuitBuilder.new(state.catalog, source.get("slots", []), str(source.get("difficulty", "standard")))
	var bar := top_bar(title_text())
	_title = bar.get_node("Title")

	tiles = OptionCards.new(_tile_spec(), "", LEFT_WIDTH, queue)
	tiles.name = "Tiles"
	tiles.position = Vector2(HubTheme.MARGIN, TILES_TOP)
	tiles.size = Vector2(LEFT_WIDTH, 0)
	tiles.changed.connect(func(_k: String, v: String):
		tiles.clear_pick()
		add_game(v))
	add_child(tiles)

	var list_top := TILES_TOP + tiles.get_combined_minimum_size().y + HubTheme.GAP
	var list_bottom := BODY_BOTTOM - HubTheme.TARGET - HubTheme.GAP
	scroll = ScrollContainer.new()
	scroll.name = "List"
	scroll.position = Vector2(HubTheme.MARGIN, list_top)
	scroll.size = Vector2(LEFT_WIDTH, list_bottom - list_top)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.scroll_deadzone = 12
	_style_scrollbar(scroll.get_v_scroll_bar())
	add_child(scroll)
	list = VBoxContainer.new()
	list.name = "Rows"
	list.add_theme_constant_override("separation", ROW_GAP)
	list.custom_minimum_size = Vector2(LEFT_WIDTH - SCROLLBAR_W - 12, 0)
	list.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(list)
	empty_note = HubTheme.label("Tap a game above to add it. Up to 12 games, 90 minutes in all.", HudTheme.BODY, GameTheme.MUTED)
	empty_note.name = "Empty"
	empty_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_note.custom_minimum_size = Vector2(LEFT_WIDTH - SCROLLBAR_W - 12, HubTheme.TARGET)

	difficulty_row = OptionRow.new({"key": "difficulty", "label": "Difficulty", "kind": "segmented",
		"choices": HubPrefs.DIFFICULTIES, "labels": ["Easy", "Standard", "Hard"]}, builder.difficulty, LEFT_WIDTH)
	difficulty_row.position = Vector2(HubTheme.MARGIN, BODY_BOTTOM - HubTheme.TARGET)
	difficulty_row.changed.connect(func(_k: String, v: String):
		builder.difficulty = v
		HubPrefs.set_pick(rider_id, "custom.difficulty", v)
		_changed(false))
	add_child(difficulty_row)

	_build_right()
	_rebuild_rows()
	_changed(false)


func _ready() -> void:
	# The list starts under the tiles: their height is known once they are in the tree.
	var list_top := TILES_TOP + tiles.get_combined_minimum_size().y + HubTheme.GAP
	scroll.position.y = list_top
	scroll.size.y = BODY_BOTTOM - HubTheme.TARGET - HubTheme.GAP - list_top
	if builder.dropped > 0:
		notice.emit("%d game%s in this circuit %s no longer offered" % [
			builder.dropped, "" if builder.dropped == 1 else "s", "is" if builder.dropped == 1 else "are"])


## "Build a circuit", or the saved one's name.
func title_text() -> String:
	return "Build a circuit" if index < 0 else HubPrefs.custom_name(index)


## The "add a game" tiles: OptionCards with a card per catalog game (its picture, its name,
## the role it plays), flatter than a game screen's.
func _tile_spec() -> Dictionary:
	var games := HubState.games(state)
	var choices: Array = []
	var cards: Array = []
	var columns := clampi(games.size(), 1, TILE_COLUMNS_MAX)
	var width := OptionCards.slot_size(OptionCards.size_for({"columns": columns}, LEFT_WIDTH).x).x - 8
	for e in games:
		var id := str(e.id)
		choices.append(id)
		var sub := HudTheme.role_name(str(e.circuit_role))
		if bool(e.uses_camera) and not bool(state.camera.available):
			sub = "Needs camera" if CircuitBuilder.new(state.catalog).stand_in(id).is_empty() else sub
		cards.append({"value": id, "title": HubTheme.fit_title(id, width), "subtitle": sub,
			"image": HubArt.card_path(id) if HubArt.has_card(id) else "", "accent": HubTheme.game_look(id).accent})
	return {"key": "add", "label": "Add a game", "kind": "cards", "columns": columns,
		"slot_aspect": TILE_ASPECT, "choices": choices, "cards": cards}


func _build_right() -> void:
	var right := VBoxContainer.new()
	right.name = "Right"
	right.position = Vector2(RIGHT_X, 175)
	right.size = Vector2(RIGHT_W, BODY_BOTTOM - 175)
	right.add_theme_constant_override("separation", int(HubTheme.GAP))
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	right.add_child(HubCard.new(_summary(), SUMMARY_SIZE, queue, false))
	best_label = HubTheme.label("", HudTheme.SMALL, GameTheme.TARGET)
	best_label.name = "Best"
	best_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	best_label.custom_minimum_size = Vector2(RIGHT_W, 0)
	right.add_child(best_label)
	problem_label = HubTheme.label("", HudTheme.SMALL, GameTheme.WARN)
	problem_label.name = "Problem"
	problem_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	problem_label.custom_minimum_size = Vector2(RIGHT_W, 0)
	right.add_child(problem_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.name = "SaveRow"
	buttons.add_theme_constant_override("separation", int(HubTheme.GAP))
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(buttons)
	var half := floorf((RIGHT_W - HubTheme.GAP) / 2.0)
	save_button = HubTheme.button("Save", save, GameTheme.PRIMARY, Vector2(half, HubTheme.TARGET))
	save_button.name = "Save"
	buttons.add_child(save_button)
	delete_button = HubTheme.button("Delete", ask_delete, GameTheme.DANGER, Vector2(half, HubTheme.TARGET))
	delete_button.name = "Delete"
	buttons.add_child(delete_button)
	start_button = HubTheme.button("Start", _start, GameTheme.GO, START_SIZE)
	start_button.name = "Start"
	start_button.add_theme_font_size_override("font_size", HudTheme.MEDIUM)
	right.add_child(start_button)


## The total and the lineup at a glance: one bake, re-rendered only when the lineup changes.
func _summary() -> Control:
	var panel := PanelContainer.new()
	var style := HomeScreen.card_style(HubTheme.look())
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 16
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(HubTheme.label("YOUR CIRCUIT", HudTheme.SMALL, GameTheme.MUTED, true))
	summary_total = HubTheme.label("", HudTheme.BIG, GameTheme.INK, true)
	summary_total.name = "Total"
	box.add_child(summary_total)
	summary_line = HubTheme.label("", HudTheme.SMALL, GameTheme.MUTED, true)
	summary_line.name = "Line"
	summary_line.clip_text = true
	box.add_child(summary_line)
	strip = LineupStrip.new([], Vector2(SUMMARY_SIZE.x - 52, 60), true)
	box.add_child(strip)
	return panel


func _style_scrollbar(bar: VScrollBar) -> void:
	# A thick bar: drag it, or drag the list where its names are (the buttons take their taps).
	bar.custom_minimum_size = Vector2(SCROLLBAR_W, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(HubTheme.look().ink, 0.6)
	track.set_corner_radius_all(int(SCROLLBAR_W / 2))
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(GameTheme.MUTED, 0.9)
	grab.set_corner_radius_all(int(SCROLLBAR_W / 2))
	grab.content_margin_left = SCROLLBAR_W / 2
	grab.content_margin_right = SCROLLBAR_W / 2
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	for st in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(st, grab)


# --- Editing ---

func add_game(game_id: String) -> void:
	match builder.add_problem(game_id):
		"full":
			notice.emit("A circuit holds %d games at most" % CircuitBuilder.MAX_SLOTS)
			return
		"too_long":
			notice.emit("A circuit is 90 minutes at most")
			return
		"unknown":
			return
	builder.add(game_id)
	_rebuild_rows()
	_changed(true)
	_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame  # the new row's layout
	if is_instance_valid(scroll):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _rebuild_rows() -> void:
	for r in rows:
		r.visible = false
		r.queue_free()
	rows.clear()
	if empty_note.get_parent() == null:
		list.add_child(empty_note)
	empty_note.visible = builder.is_empty()
	for i in builder.size():
		var s: Dictionary = builder.slots[i]
		var row := SlotRow.new(i, str(s.game_id), builder.role(i), builder.lengths(i), int(s.duration_sec), builder.size(),
			LEFT_WIDTH - SCROLLBAR_W - 12)
		row.length_changed.connect(func(at: int, sec: int):
			builder.set_length(at, sec)
			_changed(false))
		row.moved.connect(func(at: int, delta: int):
			if builder.move(at, delta):
				_rebuild_rows()
				_changed(false))
		row.removed.connect(func(at: int):
			builder.remove(at)
			_rebuild_rows()
			_changed(false))
		list.add_child(row)
		rows.append(row)


## After any edit: the draft into the nav args, then everything that shows the lineup.
func _changed(_scroll := false) -> void:
	args["draft"] = builder.to_saved()
	args["index"] = index
	for i in rows.size():
		rows[i].stepper.set_values(builder.lengths(i), int(builder.slots[i].duration_sec))
	var games := builder.size()
	summary_total.text = HubTheme.clock(float(builder.total_sec())) if games > 0 else "0:00"
	summary_line.text = "%d %s · %s of play" % [games, "game" if games == 1 else "games", HubTheme.clock(float(builder.gameplay_sec()))]
	strip.slots = builder.lineup()
	strip.queue_redraw()
	_show_best()
	_show_buttons()


func _show_best() -> void:
	if builder.is_empty():
		best_label.text = ""
		return
	var best := HubState.plan_best(state, builder.plan_id(), builder.difficulty)
	if best.is_empty():
		best_label.text = "No best yet for this lineup at this difficulty"
		best_label.add_theme_color_override("font_color", GameTheme.MUTED)
	else:
		best_label.text = "Your best: %d points, %d stars" % [best.score, best.stars]
		best_label.add_theme_color_override("font_color", GameTheme.TARGET)


func _show_buttons() -> void:
	var problem := builder.start_problem(bool(state.camera.available))
	if problem.begins_with("camera:"):
		var info := GameRegistry.info(problem.trim_prefix("camera:"))
		problem_label.text = "%s needs the camera" % (info.title if info else "A game")
	else:
		problem_label.text = ""
	if not _waiting:
		start_button.disabled = not problem.is_empty()
	save_button.disabled = not dirty()
	# Faded when they can't act (Stepper's rule): the disabled style alone reads too close.
	start_button.modulate.a = 0.45 if start_button.disabled and not _waiting else 1.0
	save_button.modulate.a = 0.45 if save_button.disabled else 1.0
	delete_button.visible = index >= 0
	save_button.custom_minimum_size.x = floorf((RIGHT_W - HubTheme.GAP) / 2.0) if index >= 0 else RIGHT_W


## Whether Save would change anything: a new lineup, or a saved one edited.
func dirty() -> bool:
	if builder.is_empty():
		return false
	if index < 0:
		return true
	var saved = HubPrefs.custom_circuit(rider_id, index)
	if saved == null:
		return true
	# Against the saved circuit as this catalog reads it: a game that's no longer offered is left
	# out of both, so opening a circuit is never an edit by itself (Save would rewrite it).
	var as_loaded := CircuitBuilder.new(state.catalog, saved.get("slots", []), str(saved.get("difficulty", "standard")))
	return _comparable(as_loaded.to_saved()) != _comparable(builder.to_saved())


static func _comparable(c: Dictionary) -> String:
	return JSON.stringify([c.get("slots", []).map(func(s): return [str(s.game_id), int(s.duration_sec)]), str(c.get("difficulty", ""))])


# --- Save, replace, delete ---

func save() -> void:
	if not dirty():
		return
	var target := index if index >= 0 else HubPrefs.free_custom(rider_id)
	if target < 0:
		open_replace()
		return
	save_to(target)


func save_to(target: int) -> void:
	HubPrefs.save_custom(rider_id, target, builder.to_saved())
	index = target
	_title.text = title_text().to_upper()
	close_replace()
	_changed(false)
	notice.emit("Saved as %s" % HubPrefs.custom_name(target))


## All three places are taken: which to replace (each confirmed).
func open_replace() -> void:
	if replace_panel:
		return
	replace_panel = PanelContainer.new()
	replace_panel.name = "Replace"
	replace_panel.position = Vector2(HubTheme.MARGIN, TILES_TOP)
	replace_panel.size = Vector2(LEFT_WIDTH, BODY_BOTTOM - TILES_TOP)
	replace_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := HomeScreen.card_style(HubTheme.look())
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 20
	style.content_margin_bottom = 30
	replace_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(HubTheme.GAP))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replace_panel.add_child(box)
	box.add_child(HubTheme.heading("Replace which circuit?"))
	box.add_child(HubTheme.label("You have %d saved. Pick one to replace with this one." % HubPrefs.CUSTOM_MAX, HudTheme.BODY, GameTheme.MUTED))
	var saved := HubPrefs.custom_circuits(rider_id)
	for i in saved.size():
		var c: Dictionary = saved[i] if saved[i] != null else {"slots": []}
		var other := CircuitBuilder.new(state.catalog, c.slots)
		var b := HubTheme.button("%s  ·  %s  ·  %d games" % [HubPrefs.custom_name(i), HubTheme.clock(float(other.total_sec())), other.size()],
			ask_replace.bind(i), GameTheme.SECONDARY, Vector2(LEFT_WIDTH - 60, HubTheme.TARGET))
		b.name = "Replace_%d" % i
		box.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var cancel := HubTheme.button("Cancel", close_replace, GameTheme.PRIMARY, Vector2(300, HubTheme.TARGET))
	cancel.name = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(cancel)
	add_child(replace_panel)
	tiles.visible = false
	scroll.visible = false
	difficulty_row.visible = false
	GameTheme.pop(replace_panel, 1.03, 0.25)


func close_replace() -> void:
	if replace_panel == null:
		return
	replace_panel.visible = false
	replace_panel.queue_free()
	replace_panel = null
	tiles.visible = true
	scroll.visible = true
	difficulty_row.visible = true


func ask_replace(target: int) -> void:
	confirm_requested.emit("Replace %s?" % HubPrefs.custom_name(target), "Its lineup is replaced by this one.",
		"Keep it", "Replace", GameTheme.DANGER, save_to.bind(target))


func ask_delete() -> void:
	if index < 0:
		return
	confirm_requested.emit("Delete %s?" % HubPrefs.custom_name(index), "It can't be brought back.",
		"Keep it", "Delete", GameTheme.DANGER, delete_saved)


func delete_saved() -> void:
	if index < 0:
		return
	HubPrefs.delete_custom(rider_id, index)
	notice.emit("%s deleted" % HubPrefs.custom_name(index))
	index = -1
	args.erase("draft")
	back.emit()


# --- Leaving ---

func back_pressed() -> void:
	if not handle_back():
		back.emit()


## Android back (and the top bar's Back): closes the replace panel, or asks before dropping
## unsaved changes; false (the hub pops) when there's nothing to lose.
func handle_back() -> bool:
	if replace_panel:
		close_replace()
		return true
	if dirty():
		confirm_requested.emit("Leave the builder?", "This circuit isn't saved.", "Keep building", "Leave",
			GameTheme.DANGER, func(): back.emit())
		return true
	return false


# --- Start ---

func request() -> Dictionary:
	return builder.request()


func _start() -> void:
	if _waiting or not builder.start_problem(bool(state.camera.available)).is_empty():
		return
	_waiting = true
	start_button.disabled = true
	start_button.text = "Starting…"
	start.emit(request())


func start_answered() -> void:
	_waiting = false
	start_button.text = "Start"
	_show_buttons()


func refresh(hub_state: Dictionary) -> void:
	state = hub_state
	_show_best()
	_show_buttons()


## The screen's touch targets: the tiles, the rows wholly inside the list's view (scrolled-out
## rows aren't on screen), the difficulty, Save, Delete and Start; the replace panel's when open.
func targets() -> Array[Control]:
	var out: Array[Control] = []
	if replace_panel:
		_collect(replace_panel, out)
	else:
		for card in tiles.cards.values():
			out.append((card as HubCard).hit)
		var view := scroll.get_global_rect()
		for r in rows:
			for b in r.buttons():
				if b.is_visible_in_tree() and view.encloses(b.get_global_rect()):
					out.append(b)
		_collect(difficulty_row, out)
	_collect(get_node("TopBar"), out)
	_collect(get_node("Right"), out)
	return out
