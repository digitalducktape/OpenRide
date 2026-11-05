class_name IntroCard
extends CanvasLayer
## The card before each segment (epic #31, "Intro card between games"): "Up next: <game>", the
## role, a one-line how-to, the target, the previous result and a countdown ending 3-2-1.
## Its "Skip this game" button asks to skip (`skip_requested`) when there is a next segment.
## A touch anywhere else does nothing: the card and the shade around it take it, so no stray touch reaches
## the game or the HUD below, or skips. On the bike a touch on the countdown skipped the only
## segment of a timed Just Ride, which ended the workout (#35).

signal skip_requested

const LAYER := 20
const CARD_SIZE := Vector2(1320, 760)
const SHADE := Color(0, 0, 0, 0.55)
const SHADE_CORNER := 32.0  ## the card's corner radius

var can_skip := false
## `_shown_count` while "Get ready" shows (the game counts its own start down).
const OWN_COUNTDOWN_SHOWN := -2

var own_countdown := false  ## the game counts its own start down: no 3-2-1 here

var _title: Label
var _role: Label
var _how_to: Label
## Holds the game's own small picture or animation (`Game.intro_visual()`), e.g. Dodge Ball's mode.
var _visual_slot: CenterContainer
var _target: Label
var _count: Label
var _previous: Label
var _previous_stars: StarRow
## The deliberate way to skip, shown only when skipping leaves a segment to play.
var skip_button: Button
## The game's look (`Game.ui_theme()`), or null for the kit's plain card.
var theme: GameTheme

var _card: PanelContainer
var _shown_count := -1


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var card_rect := Rect2((Vector2(HudTheme.W, HudTheme.H) - CARD_SIZE) / 2, CARD_SIZE)
	_add_shade(card_rect)

	var card := PanelContainer.new()
	_card = card
	card.add_theme_stylebox_override("panel", HudTheme.panel_style(HudTheme.CARD, 32))
	card.position = card_rect.position
	card.size = CARD_SIZE
	# The card takes the touches over it, the shade the rest: none reaches the game or skips.
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	_role = _centred(box, HudTheme.SMALL, HudTheme.MUTED)
	_title = _centred(box, HudTheme.BIG)
	_visual_slot = CenterContainer.new()
	_visual_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_visual_slot)
	_how_to = _centred(box, HudTheme.BODY)
	_how_to.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target = _centred(box, HudTheme.BODY, HudTheme.GOOD)
	_target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_count = _centred(box, HudTheme.HUGE, HudTheme.WARN)
	var previous_row := HBoxContainer.new()
	previous_row.alignment = BoxContainer.ALIGNMENT_CENTER
	previous_row.add_theme_constant_override("separation", 24)
	previous_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(previous_row)
	_previous = HudTheme.label("", HudTheme.SMALL, HudTheme.MUTED)
	previous_row.add_child(_previous)
	_previous_stars = StarRow.new(0, 40.0)
	previous_row.add_child(_previous_stars)
	skip_button = HudTheme.button("Skip this game", _on_skip_pressed, Color(0.3, 0.3, 0.36))
	skip_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(skip_button)


## Styles the card in a game's look (`Game.ui_theme()`): the card, the display face, the title
## in the accent's gradient, the target in TARGET gold and the countdown digits slamming in.
## null puts the kit's plain card back. The layout and every text stay the same.
func apply_theme(new_theme: GameTheme) -> void:
	theme = new_theme
	_shown_count = -1
	if theme:
		_card.add_theme_stylebox_override("panel", theme.card_style())
		theme.style_label(_role, HudTheme.SMALL, null, true)
		theme.style_label(_title, HudTheme.BIG, GameTheme.INK)
		theme.set_gradient(_title)
		theme.style_label(_how_to, HudTheme.BODY, GameTheme.INK, true)
		theme.style_label(_target, HudTheme.BODY, GameTheme.TARGET, true)
		theme.style_label(_count, HudTheme.HUGE, GameTheme.INK, true)
		theme.style_label(_previous, HudTheme.SMALL, GameTheme.MUTED, true)
		theme.style_button(skip_button, GameTheme.SECONDARY)
	else:
		_card.add_theme_stylebox_override("panel", HudTheme.panel_style(HudTheme.CARD, 32))
		HudTheme.style_label(_role, HudTheme.SMALL, _role.get_theme_color("font_color"))
		HudTheme.style_label(_title, HudTheme.BIG)
		HudTheme.style_label(_how_to, HudTheme.BODY)
		HudTheme.style_label(_target, HudTheme.BODY, HudTheme.GOOD)
		HudTheme.style_label(_count, HudTheme.HUGE, HudTheme.WARN)
		HudTheme.style_label(_previous, HudTheme.SMALL, HudTheme.MUTED)
		HudTheme.style_button(skip_button, Color(0.3, 0.3, 0.36))
	_count.scale = Vector2.ONE
	_count.modulate.a = 1.0


## Shows the card for a segment. `previous` is the last result (or empty), with its title.
## `how_to` replaces the game's static how-to line (`Game.how_to_text`), and `visual` is the
## game's own small picture for the card, or null.
func show_segment(info: GameInfo, segment: Dictionary, target: String, previous: Dictionary, previous_title: String,
		skippable: bool, how_to := "", visual: Control = null) -> void:
	var role := str(segment.get("role", "free"))
	var count := int(segment.get("count", 1))
	_role.text = HudTheme.role_name(role).to_upper()
	if count > 1:
		_role.text += "  ·  %d OF %d" % [int(segment.get("index", 0)) + 1, count]
	_role.add_theme_color_override("font_color", HudTheme.role_color(role))
	_title.text = "Up next: %s" % info.title
	own_countdown = info.own_countdown
	_how_to.text = how_to if not how_to.is_empty() else info.how_to
	for child in _visual_slot.get_children():
		child.queue_free()
	if visual:
		_visual_slot.add_child(visual)
	_visual_slot.visible = visual != null
	_target.text = target
	_target.visible = not target.is_empty()
	var has_previous := not previous.is_empty()
	_previous.visible = has_previous
	_previous_stars.visible = has_previous and not previous.get("skipped", false)
	if has_previous:
		if previous.get("skipped", false):
			_previous.text = "Previous game: %s (skipped)" % previous_title
		else:
			_previous.text = "Previous game: %s · %d points" % [previous_title, int(previous.get("score", 0))]
			_previous_stars.stars = int(previous.get("stars", 0))
	can_skip = skippable
	skip_button.visible = skippable
	_shown_count = -1
	set_time_left(float(segment.get("intro_sec", 0)))
	visible = true


## The countdown: whole seconds, then a big 3-2-1 ("Get ready" when the game counts down itself).
func set_time_left(seconds: float) -> void:
	# Called every frame of the intro: the label is touched only when what it shows changes
	# (each theme override re-shapes the text and re-sorts the card).
	if own_countdown:
		if _shown_count == OWN_COUNTDOWN_SHOWN:
			return
		_shown_count = OWN_COUNTDOWN_SHOWN
		_count.text = "Get ready"
		_count.add_theme_font_size_override("font_size", HudTheme.BIG)
		_count.add_theme_color_override("font_color", HudTheme.MUTED)
		if theme:
			theme.set_gradient(_count, [], true)
		return
	var whole := ceili(seconds)
	if theme:
		_themed_count(whole)
		return
	if whole == _shown_count:
		return
	_shown_count = whole
	_count.text = str(whole) if whole > 0 else "Go!"
	_count.add_theme_font_size_override("font_size", HudTheme.HUGE if whole <= 3 else HudTheme.BIG)
	_count.add_theme_color_override("font_color", HudTheme.WARN if whole <= 3 else HudTheme.MUTED)


func _on_skip_pressed() -> void:
	if visible and can_skip:
		skip_requested.emit()



## Dims the game around the card, not under it: the card is 96% opaque, and on the tablet's
## fill-bound GPU a full-screen blend under it costs about half a screen of pixels every intro
## frame. Four strips frame the card; a patch in each corner fills behind its rounded edge.
func _add_shade(card_rect: Rect2) -> void:
	var full := Stage.bleed_rect()  # the whole window, past the centred stage (#57)
	var strips: Array[Rect2] = [
		Rect2(full.position, Vector2(full.size.x, card_rect.position.y - full.position.y)),
		Rect2(Vector2(full.position.x, card_rect.end.y), Vector2(full.size.x, full.end.y - card_rect.end.y)),
		Rect2(Vector2(full.position.x, card_rect.position.y), Vector2(card_rect.position.x - full.position.x, card_rect.size.y)),
		Rect2(Vector2(card_rect.end.x, card_rect.position.y), Vector2(full.end.x - card_rect.end.x, card_rect.size.y)),
	]
	for strip in strips:
		_shade_rect(strip, Control.MOUSE_FILTER_STOP)
	var c := Vector2.ONE * SHADE_CORNER
	for corner in [card_rect.position, Vector2(card_rect.end.x - c.x, card_rect.position.y),
			Vector2(card_rect.position.x, card_rect.end.y - c.y), card_rect.end - c]:
		_shade_rect(Rect2(corner, c), Control.MOUSE_FILTER_IGNORE)


func _shade_rect(r: Rect2, filter: Control.MouseFilter) -> void:
	var shade := ColorRect.new()
	shade.name = "Shade%d" % get_child_count()
	shade.color = SHADE
	shade.position = r.position
	shade.size = r.size
	shade.mouse_filter = filter
	add_child(shade)

func _centred(box: Container, font_size: int, color := HudTheme.INK) -> Label:
	var label := HudTheme.label("", font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return label


## The themed countdown: whole seconds in the accent, then 3-2-1 and "Go!" in gold, each
## slamming in. Touches the label only when the number changes.
func _themed_count(whole: int) -> void:
	if whole == _shown_count:
		return
	_shown_count = whole
	var close := whole <= 3
	_count.text = str(whole) if whole > 0 else "Go!"
	theme.style_label(_count, HudTheme.HUGE if close else HudTheme.BIG, GameTheme.INK, true)
	theme.set_gradient(_count, GameTheme.GOLD_GRADIENT if close else [])
	if close:
		GameTheme.slam(_count, 1.8)
