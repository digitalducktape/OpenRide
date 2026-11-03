class_name HomeScreen
extends HubScreen
## The hub's home (spec §8.3): the header (rider, ride so far, live metrics, camera, Settings,
## Exit games), the FTP nudge when the rider's FTP is the default, a card per game and a card
## per circuit. Every card is baked (one draw call), and a tap opens the game's or circuit's
## screen. A game that needs the camera while it's off is dimmed and says so; a tap explains.
##
##   HomeScreen
##   ├ HubHeader
##   ├ Nudge (HubCard, not a target) + Set FTP (Button)   only when ftp_is_default
##   ├ Games: heading, HBox of HubCard ×5
##   └ Circuits: heading, HBox of HubCard: the presets, My circuits, Build your own

signal camera_explain(game_id: String)  ## a dimmed card was tapped
signal calibrate_requested  ## the header's camera chip (calibrate, recalibrate, or allow)

const NUDGE_SIZE := Vector2(1400, 104)
## Up to ROW_MAX games share one row; more page through PAGE_SIZE at a time between two page
## buttons (#75: 11 games). Paging, not a scroll: every card is a full tap target (a drag on a
## card is its tap), and a 120 px button is easy to hit while pedalling.
const ROW_MAX := 5
const PAGE_SIZE := 4

var header: HubHeader
var game_cards: Dictionary = {}  ## game_id → HubCard (every game; off-page cards are hidden)
var game_page := 0  ## the games page shown (kept across rebuilds)
var page_left: IconButton  ## null when every game fits one row
var page_right: IconButton
var circuit_cards: Dictionary = {}  ## circuit id → HubCard
var _column: VBoxContainer
var _signature := ""


func build() -> void:
	header = HubHeader.new(queue)
	header.settings_pressed.connect(func(): open.emit(HubNav.SETTINGS, {}))
	header.exit_pressed.connect(func(): exit_requested.emit())
	header.camera_pressed.connect(func(): calibrate_requested.emit())
	header.music_pressed.connect(func(): Session.director.music_panel.open())
	add_child(header)
	header.set_state(state)
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.position = Vector2(HubTheme.MARGIN, HubTheme.HEADER_H)
	_column.size = Vector2(HubTheme.W - 2 * HubTheme.MARGIN, HubTheme.H - HubTheme.HEADER_H - 40)
	_column.add_theme_constant_override("separation", 14)
	_column.alignment = BoxContainer.ALIGNMENT_CENTER  # without the nudge, the rows sit mid-screen
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_fill()


func refresh(hub_state: Dictionary) -> void:
	state = hub_state
	header.set_state(state)
	if _content_signature() != _signature:
		for c in _column.get_children():
			c.queue_free()
		game_cards.clear()
		circuit_cards.clear()
		_fill()


## What the cards show: rebuilt only when it changes (bests, the camera, the catalog).
func _content_signature() -> String:
	return JSON.stringify([state.catalog, state.circuits, state.bests, state.camera.available,
		state.rider.ftp_is_default, state.rider.ftp_watts])


func _fill() -> void:
	_signature = _content_signature()
	if bool(state.rider.get("ftp_is_default", false)):
		_column.add_child(_nudge())
	_column.add_child(HubTheme.heading("Play a game"))
	var entries: Array = HubState.games(state)
	var paged := entries.size() > ROW_MAX
	var games := HBoxContainer.new()
	games.name = "Games"
	games.add_theme_constant_override("separation", int(_gap(5, HubTheme.GAME_CARD.x)))
	games.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if paged:
		# More games than fit a row (#75): pages of PAGE_SIZE between two page buttons.
		var row := HBoxContainer.new()
		row.name = "GamesRow"
		row.add_theme_constant_override("separation", int(HubTheme.GAP))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_column.add_child(row)
		page_left = _page_button("left", -1)
		row.add_child(page_left)
		games.add_theme_constant_override("separation", int(_paged_gap()))
		games.custom_minimum_size = Vector2(_paged_width(), HubTheme.GAME_CARD.y)
		row.add_child(games)
		page_right = _page_button("right", 1)
		row.add_child(page_right)
		game_page = clampi(game_page, 0, page_count() - 1)
	else:
		page_left = null
		page_right = null
		_column.add_child(games)
	for e in entries:
		var card := HubCard.new(game_card(e), HubTheme.GAME_CARD, queue)
		card.name = "Game_" + str(e.id)
		var playable := HubState.playable(state, e)
		card.set_dimmed(not playable)
		var id := str(e.id)
		card.pressed.connect(func():
			if HubState.playable(state, HubState.entry(state, id)):
				open.emit(HubNav.GAME, {"game_id": id})
			else:
				camera_explain.emit(id))
		games.add_child(card)
		game_cards[id] = card
	if paged:
		_show_page()
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(spacer)
	_column.add_child(HubTheme.heading("Circuits"))
	var circuits := HBoxContainer.new()
	circuits.name = "Circuits"
	circuits.add_theme_constant_override("separation", int(_gap(5, HubTheme.CIRCUIT_CARD.x)))
	circuits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(circuits)
	for c in state.circuits:
		var card := HubCard.new(circuit_card(c), HubTheme.CIRCUIT_CARD, queue)
		var id := str(c.id)
		card.name = "Circuit_" + id
		card.pressed.connect(func(): open.emit(HubNav.CIRCUIT, {"circuit_id": id}))
		circuits.add_child(card)
		circuit_cards[id] = card
	# The rider's own: "My circuits" (the saved ones), then "Build your own" (spec §8.3).
	var mine := HubCard.new(my_circuits_card(), HubTheme.CIRCUIT_CARD, queue)
	mine.name = "Circuit_mine"
	mine.pressed.connect(func(): open.emit(HubNav.MY_CIRCUITS, {}))
	circuits.add_child(mine)
	circuit_cards["mine"] = mine
	var build_card := HubCard.new(build_card_content(), HubTheme.CIRCUIT_CARD, queue)
	build_card.name = "Circuit_build"
	build_card.pressed.connect(func(): open.emit(HubNav.BUILDER, {"index": -1}))
	circuits.add_child(build_card)
	circuit_cards["build"] = build_card


## The game pages (1 when every game fits one row).
func page_count() -> int:
	var n: int = HubState.games(state).size()
	return 1 if n <= ROW_MAX else ceili(float(n) / PAGE_SIZE)


## Shows page `page` of the games (clamped), and enables the page buttons that lead somewhere.
func show_page(page: int) -> void:
	game_page = clampi(page, 0, page_count() - 1)
	_show_page()


func _show_page() -> void:
	if page_left == null:
		return
	var i := 0
	for card in game_cards.values():  # in catalog order (inserted so)
		(card as HubCard).visible = i / PAGE_SIZE == game_page
		i += 1
	page_left.set_enabled(game_page > 0)
	page_right.set_enabled(game_page < page_count() - 1)


func _page_button(which: String, step: int) -> IconButton:
	var b := IconButton.new(which, func(): show_page(game_page + step))
	b.name = "Page" + which.capitalize()
	b.custom_minimum_size = Vector2(HubTheme.TARGET, HubTheme.GAME_CARD.y)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## The paged row's card area: the column less the two page buttons and their gaps.
static func _paged_width() -> float:
	return HubTheme.W - 2 * HubTheme.MARGIN - 2 * (HubTheme.TARGET + HubTheme.GAP)


## The gap that spreads a page's cards across the paged row's card area.
static func _paged_gap() -> float:
	return floorf((_paged_width() - PAGE_SIZE * HubTheme.GAME_CARD.x) / (PAGE_SIZE - 1))


## The gap that spreads `count` cards of `width` across the column.
static func _gap(count: int, width: float) -> float:
	return floorf((HubTheme.W - 2 * HubTheme.MARGIN - count * width) / (count - 1))


func _nudge() -> Control:
	var row := HBoxContainer.new()
	row.name = "Nudge"
	row.add_theme_constant_override("separation", int(HubTheme.GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	var nudge_style := HubTheme.look().panel_style(Color(HubTheme.look().ink, 0.86), 0.0, 22)
	nudge_style.border_color = GameTheme.WARN
	panel.add_theme_stylebox_override("panel", nudge_style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 20)
	panel.add_child(line)
	var mark := PanelContainer.new()  # "!" on an amber disc: the warning's shape, not just its colour
	var disc := StyleBoxFlat.new()
	disc.bg_color = GameTheme.WARN
	disc.set_corner_radius_all(30)
	disc.content_margin_left = 22
	disc.content_margin_right = 22
	mark.add_theme_stylebox_override("panel", disc)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.add_child(HubTheme.label("!", HudTheme.BODY, HubTheme.look().ink, true))
	line.add_child(mark)
	var text := HubTheme.label("Set your FTP for the right targets. Games assume %d W." % int(state.rider.get("ftp_watts", 150)),
		HudTheme.BODY, GameTheme.INK, true)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	row.add_child(HubCard.new(panel, NUDGE_SIZE, queue, false))
	var set_ftp := HubTheme.button("Set FTP", func(): set_ftp_requested.emit(), GameTheme.PRIMARY,
		Vector2(HubTheme.W - 2 * HubTheme.MARGIN - NUDGE_SIZE.x - HubTheme.GAP, HubTheme.TARGET))
	set_ftp.name = "SetFtp"
	set_ftp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(set_ftp)
	return row


## A game's card: its picture inset evenly, its title, then its best or why it can't start.
func game_card(e: Dictionary) -> Control:
	var id := str(e.id)
	var look := HubTheme.game_look(id)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", card_style(look))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var inset := HubTheme.PICTURE_INSET
	var pic_size := Vector2(HubTheme.GAME_CARD.x - 2 * inset, (HubTheme.GAME_CARD.x - 2 * inset) * 9.0 / 16.0)
	box.add_child(HubArt.picture(id, pic_size, HubTheme.CARD_RADIUS - inset))
	# Never blocks: the title comes from hub_state until the declarations load in the background.
	var info := GameRegistry.cached_info(id)
	var title_text: String = info.title if info else str(e.get("title", id.capitalize()))
	var title := HubTheme.label(title_text, fit_size(title_text, HubTheme.CARD_TITLE, pic_size.x), GameTheme.INK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.custom_minimum_size = Vector2(pic_size.x, 0)
	box.add_child(title)
	box.add_child(_best_line(e))
	return panel


func _best_line(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	if not HubState.playable(state, e):
		row.add_child(HubTheme.label("Needs the camera", HudTheme.SMALL, GameTheme.WARN, true))
		return row
	var best := HubState.game_best(state, str(e.id))
	if best.is_empty():
		row.add_child(HubTheme.label("Not played yet", HudTheme.SMALL, GameTheme.MUTED, true))
		return row
	row.add_child(HubTheme.label("Best %d" % best.score, HudTheme.SMALL, GameTheme.TARGET, true))
	var stars := StarRow.new(int(best.stars), 30.0)
	stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(stars)
	return row


## The largest text size, from `size` down to HudTheme.SMALL, at which `text` fits `width`.
static func fit_size(text: String, size: int, width: float) -> int:
	var font := GameTheme.display_font()
	var s := size
	while s > HudTheme.SMALL and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > width:
		s -= 2
	return s


## A circuit's card: its length, its time, its lineup as pills, and its best.
func circuit_card(c: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := card_style(HubTheme.look())
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 12
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	box.add_child(top)
	var minutes := HubTheme.look().label("%d MIN" % int(c.get("minutes", 0)), HudTheme.MEDIUM, GameTheme.INK, false)
	top.add_child(minutes)
	var strip := LineupStrip.new(c.get("slots", []), Vector2(HubTheme.CIRCUIT_CARD.x - 48, 30))
	box.add_child(strip)
	# The time on its own line: beside "20 MIN" it would widen the card past its bake.
	var line := HubTheme.label("%s · %d games" % [HubTheme.duration(int(c.get("total_sec", -1))),
		(c.get("slots", []) as Array).size()], HudTheme.SMALL, GameTheme.MUTED, true)
	line.clip_text = true
	box.add_child(line)
	var best := HubState.circuit_best(state, str(c.id))
	var best_row := HBoxContainer.new()
	best_row.add_theme_constant_override("separation", 12)
	box.add_child(best_row)
	if best.is_empty():
		best_row.add_child(HubTheme.label("Not ridden yet", HudTheme.SMALL, GameTheme.MUTED, true))
	else:
		best_row.add_child(HubTheme.label("Best %d" % best.score, HudTheme.SMALL, GameTheme.TARGET, true))
	return panel


## "My circuits": how many are saved, and the first one's lineup.
func my_circuits_card() -> Control:
	var panel := PanelContainer.new()
	var style := card_style(HubTheme.look())
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 12
	style.border_color = GameTheme.TARGET
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := "MY CIRCUITS"
	box.add_child(HubTheme.look().label(title, fit_size(title, HudTheme.MEDIUM, HubTheme.CIRCUIT_CARD.x - 56), GameTheme.INK, false))
	var saved := HubPrefs.custom_circuits(rider_id).filter(func(c): return c != null)
	var first: Array = CircuitBuilder.new(state.catalog, saved[0].slots).lineup() if not saved.is_empty() else []
	box.add_child(LineupStrip.new(first, Vector2(HubTheme.CIRCUIT_CARD.x - 48, 30)))
	box.add_child(HubTheme.label("%d of %d saved" % [saved.size(), HubPrefs.CUSTOM_MAX] if not saved.is_empty() else "None saved yet",
		HudTheme.SMALL, GameTheme.INK if not saved.is_empty() else GameTheme.MUTED, true))
	box.add_child(HubTheme.label("Play or edit" if not saved.is_empty() else "Build one", HudTheme.SMALL, GameTheme.MUTED, true))
	return panel


## "+ Build your own".
func build_card_content() -> Control:
	var panel := PanelContainer.new()
	var style := card_style(HubTheme.look())
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 12
	style.bg_color = style.bg_color.lerp(HubTheme.look().accent, 0.25)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var plus := HubTheme.look().label("+ BUILD", HudTheme.MEDIUM, GameTheme.INK, false)
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(plus)
	var line := HubTheme.label("your own circuit", HudTheme.SMALL, GameTheme.INK, true)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)
	return panel


## A card's panel: the look's ink, an accent edge and a thicker bottom edge, upright.
static func card_style(look: GameTheme) -> StyleBoxFlat:
	var s := look.panel_style(Color(look.ink.lerp(look.accent, 0.16), 0.97), 0.0, HubTheme.CARD_RADIUS)
	s.set_border_width_all(4)
	s.border_width_bottom = 10
	s.content_margin_left = HubTheme.PICTURE_INSET
	s.content_margin_right = HubTheme.PICTURE_INSET
	s.content_margin_top = HubTheme.PICTURE_INSET
	s.content_margin_bottom = 10
	s.shadow_size = 0  # baked: the shadow would be clipped by the bake's edge
	return s


func targets() -> Array[Control]:
	var out: Array[Control] = []
	out.append_array(header.targets())
	for card in game_cards.values():
		if card.is_visible_in_tree():  # this page's games
			out.append(card.hit)
	if page_left:
		out.append_array([page_left, page_right])
	for card in circuit_cards.values():
		out.append(card.hit)
	var nudge := _column.get_node_or_null("Nudge/SetFtp")
	if nudge:
		out.append(nudge)
	return out
