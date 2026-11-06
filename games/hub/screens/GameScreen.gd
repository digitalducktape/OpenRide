class_name GameScreen
extends HubScreen
## One game's screen (spec §8.3): Back and the game's name on top, the game's own options on the
## left (GameInfo.options with `where` hub or both), Length, Difficulty and Start on the right,
## Start at the bottom right. Every tap is saved at once (HubPrefs for the hub's picks,
## GameOptions for the game's, per rider). There's no auto-start: Start sends `start_plan`, and
## it waits for the answer.
##
## Two layouts, by the game's options:
## - **Cards** (a `kind: cards` option, Kart Race's kart and track): the left column is the card
##   grids, in declaration order; the rider's best moves under Difficulty. The intro card still
##   shows how to play before the game.
## - **Poster** (every other game): the left column is the poster (picture, how to play, the
##   best), then the ungrouped options as rows (OptionRow: `segmented` or `cycle`).
## Grouped options (`group` other than "") fold under "More options" (top right), a panel over
## the left column with Done.
##
##   GameScreen
##   ├ TopBar: Back, title (the game's gradient), spacer, More options
##   ├ Left (VBox): OptionCards … | Poster (HubCard, baked), YOUR GAME, OptionRow …
##   ├ MoreOptions (over Left, while open)
##   └ Right (VBox): LENGTH, LengthPicker, DIFFICULTY, Segmented, (best,) spacer, Start

const LEFT_WIDTH := 1040.0
const RIGHT_X := 1180.0
const BODY_TOP := 175.0
## The card layout starts higher: two card grids fill the column.
const CARDS_TOP := 150.0
const BODY_BOTTOM := 1050.0
const POSTER := Vector2(1040, 300)
const MORE_SIZE := Vector2(380, HubTheme.TARGET)

var game_id := ""
var entry: Dictionary = {}
var info: GameInfo
var look: GameTheme
var pick: Dictionary = {}
var length_picker: LengthPicker
var difficulty: Segmented
var start_button: Button
var left: VBoxContainer
## The game's options on screen, by key: OptionCards or OptionRow (More options' rows too).
var option_controls: Dictionary = {}
var more_button: Button
var more_panel: MoreOptions
var _grouped: Array = []
var _best_label: Label
var _stars: StarRow
var _waiting := false


func build() -> void:
	game_id = str(args.get("game_id", ""))
	entry = HubState.entry(state, game_id)
	info = GameRegistry.info(game_id)
	look = HubTheme.game_look(game_id)
	pick = HubPrefs.game_pick(rider_id, entry)
	var bar := top_bar(info.title if info else str(entry.get("title", game_id)), look)
	var options: Array[Dictionary] = info.hub_options() if info else []
	var card_options := options.filter(func(o): return GameInfo.option_kind(o) == "cards")
	var rows := options.filter(func(o): return GameInfo.option_kind(o) != "cards" and str(o.get("group", "")) == "")
	_grouped = options.filter(func(o): return GameInfo.option_kind(o) != "cards" and str(o.get("group", "")) != "")
	if not _grouped.is_empty():
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(spacer)
		more_button = HubTheme.button("More options  ›", open_more, GameTheme.SECONDARY, MORE_SIZE)
		more_button.name = "MoreOptionsButton"
		bar.add_child(more_button)

	var top := CARDS_TOP if not card_options.is_empty() else BODY_TOP
	left = VBoxContainer.new()
	left.name = "Left"
	left.position = Vector2(HubTheme.MARGIN, top)
	left.size = Vector2(LEFT_WIDTH, BODY_BOTTOM - top)
	left.add_theme_constant_override("separation", int(HubTheme.GAP))
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	if card_options.is_empty():
		left.add_child(HubCard.new(_poster(), POSTER, queue, false))
		if not rows.is_empty():
			left.add_child(HubTheme.heading("Your game"))
	for spec in card_options:
		var cards := OptionCards.new(spec, _value(spec), LEFT_WIDTH, queue, look, str(state.rider.get("name", "")))
		cards.changed.connect(_save)
		left.add_child(cards)
		option_controls[str(spec.key)] = cards
	for spec in rows:
		var row := OptionRow.new(spec, _value(spec), LEFT_WIDTH, look)
		row.changed.connect(_save)
		left.add_child(row)
		option_controls[str(spec.key)] = row

	var right := VBoxContainer.new()
	right.name = "Right"
	right.position = Vector2(RIGHT_X, BODY_TOP)
	right.size = Vector2(HubTheme.W - HubTheme.MARGIN - RIGHT_X, BODY_BOTTOM - 10 - BODY_TOP)
	right.add_theme_constant_override("separation", 18)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	right.add_child(HubTheme.heading("Length"))
	length_picker = LengthPicker.new(entry, pick)
	length_picker.changed.connect(func(mode: String, length: int):
		pick.mode = mode
		pick.length = length
		HubPrefs.set_game_pick(rider_id, game_id, pick)
		_show_best())
	right.add_child(length_picker)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(gap)
	right.add_child(HubTheme.heading("Difficulty"))
	difficulty = difficulty_picker(str(pick.difficulty))
	difficulty.changed.connect(func(d: String):
		pick.difficulty = d
		HubPrefs.set_game_pick(rider_id, game_id, pick)
		_show_best())
	right.add_child(difficulty)
	if not card_options.is_empty():
		right.add_child(_best_row())
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(spacer)
	start_button = look.button("Start", _start, GameTheme.GO)
	start_button.name = "Start"
	start_button.custom_minimum_size = HubTheme.START_SIZE
	start_button.add_theme_font_size_override("font_size", HudTheme.MEDIUM)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(start_button)
	_show_best()


## The option's current value for the hub's rider.
func _value(spec: Dictionary) -> String:
	return GameOptions.get_value(info, str(spec.key), rider_id)


## A pick on any option: saved at once, per rider.
func _save(key: String, value: String) -> void:
	GameOptions.set_value(info, key, value, rider_id)


## Opens "More options" over the left column (its cards or poster hide under it: no taps, no
## bakes).
func open_more() -> void:
	if _grouped.is_empty() or more_panel:
		return
	more_panel = MoreOptions.new(_grouped, func(k: String): return GameOptions.get_value(info, k, rider_id),
		Vector2(LEFT_WIDTH, BODY_BOTTOM - BODY_TOP), look)
	more_panel.position = Vector2(HubTheme.MARGIN, BODY_TOP)
	more_panel.changed.connect(_save)
	more_panel.done.connect(close_more)
	add_child(more_panel)
	for k in more_panel.rows:
		option_controls[k] = more_panel.rows[k]
	left.visible = false
	more_button.visible = false
	GameTheme.pop(more_panel, 1.03, 0.25)


func close_more() -> void:
	if more_panel == null:
		return
	for k in more_panel.rows:
		option_controls.erase(k)
	more_panel.visible = false  # freed at the frame's end; hidden, it takes no taps meanwhile
	more_panel.queue_free()
	more_panel = null
	left.visible = true
	more_button.visible = true


## Android back closes "More options" first.
func handle_back() -> bool:
	if more_panel:
		close_more()
		return true
	return false


## The rider's best at the picked length and difficulty, under Difficulty (the card layout).
func _best_row() -> HBoxContainer:
	var best_row := HBoxContainer.new()
	best_row.name = "Best"
	best_row.add_theme_constant_override("separation", 14)
	best_row.custom_minimum_size = Vector2(0, 50)
	_best_label = HubTheme.label("", HudTheme.SMALL, GameTheme.TARGET)
	best_row.add_child(_best_label)
	_stars = StarRow.new(0, 34.0)
	_stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	best_row.add_child(_stars)
	return best_row


## The poster: the picture, how to play and the best at the picked length and difficulty.
func _poster() -> Control:
	var panel := PanelContainer.new()
	var style := HomeScreen.card_style(look)
	style.content_margin_right = 30
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	panel.add_child(row)
	var pic_h := POSTER.y - HubTheme.PICTURE_INSET - 10 - 4
	row.add_child(HubArt.picture(game_id, Vector2(pic_h * 16.0 / 9.0, pic_h), HubTheme.CARD_RADIUS - HubTheme.PICTURE_INSET))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	row.add_child(col)
	var how := HubTheme.label(info.how_to if info else "", HudTheme.BODY, GameTheme.INK, true)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(POSTER.x - pic_h * 16.0 / 9.0 - 70, 0)
	col.add_child(how)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 14)
	col.add_child(chips)
	if bool(entry.get("uses_camera", false)):
		var info := GameRegistry.cached_info(str(entry.get("id", "")))
		chips.add_child(_chip("Stand to jump" if info and info.tracker_mode == "lean_stand" else "Lean to steer"))
	var best_row := HBoxContainer.new()
	best_row.add_theme_constant_override("separation", 14)
	col.add_child(best_row)
	_best_label = HubTheme.label("", HudTheme.SMALL, GameTheme.TARGET, true)
	best_row.add_child(_best_label)
	_stars = StarRow.new(0, 34.0)
	_stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	best_row.add_child(_stars)
	return panel


func _chip(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", look.badge_style(null, true))
	chip.add_child(HubTheme.label(text, HudTheme.SMALL, GameTheme.INK, true))
	return chip


## The plan id Kotlin will give this pick (SessionPlans.justRide), for its best.
static func plan_id(game: String, mode: String, length: int) -> String:
	match mode:
		"minutes":
			return "just-ride:%s:minutes:%d" % [game, length]
		"rounds":
			return "just-ride:%s:rounds:%d" % [game, length]
	return "just-ride:%s:open" % game


func _show_best() -> void:
	if _best_label == null:
		return
	var best := HubState.just_ride_best(state, game_id, plan_id(game_id, str(pick.mode), int(pick.length)), str(pick.difficulty))
	if best.is_empty():
		_best_label.text = "No best yet at this length"
		_best_label.add_theme_color_override("font_color", GameTheme.MUTED)
		_stars.visible = false
	else:
		_best_label.text = "Your best here: %d" % best.score
		_best_label.add_theme_color_override("font_color", GameTheme.TARGET)
		_stars.stars = mini(3, best.stars)
		_stars.visible = true


func refresh(hub_state: Dictionary) -> void:
	state = hub_state
	_show_best()


## The start_plan request for the current pick.
func request() -> Dictionary:
	var r := {"kind": "just_ride", "game_id": game_id, "mode": str(pick.mode), "difficulty": str(pick.difficulty)}
	if str(pick.mode) != "open":
		r["length"] = int(pick.length)
	return r


func _start() -> void:
	if _waiting:
		return
	_waiting = true
	start_button.disabled = true
	start_button.text = "Starting…"
	start.emit(request())


func start_answered() -> void:
	_waiting = false
	start_button.disabled = false
	start_button.text = "Start"
