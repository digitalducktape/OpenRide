class_name HubTheme
extends RefCounted
## The Games hub's sizes and colours (spec §8.2), on the shared UI kit (framework/ui/UI_STYLE.md):
## the house look (`GameTheme.house()`: periwinkle on deep indigo), Lilita One, outlined text,
## badge panels and pill buttons, with each game's accent on its own card. Text sizes are
## HudTheme's; the hub's touch rules are stricter than a game's (120 px targets, 24 px apart).

const W := HudTheme.W
const H := HudTheme.H
const MARGIN := 56.0  ## the screen's side margins (as the summary)
const HEADER_H := 150.0
const GAP := 24.0  ## between touch targets, at least
const TARGET := 120.0  ## every touch target's shorter side, at least
const CARD_TARGET := 180.0  ## a card's shorter side, at least
const START_SIZE := Vector2(600, 170)
const BACK_SIZE := Vector2(240, TARGET)

## Text sizes (HudTheme's scale): nothing under SMALL.
const HEADING := HudTheme.MEDIUM  ## 56: a screen's sections
const CARD_TITLE := 44
const BODY := HudTheme.BODY
const SMALL := HudTheme.SMALL

## Game cards on the home screen (spec §8.3): five across.
const GAME_CARD := Vector2(330, 300)
const GAME_PICTURE := Vector2(330, 186)  ## 16:9 (hub_card.png is 512x288)
const CIRCUIT_CARD := Vector2(330, 220)
const CARD_RADIUS := 24
const PICTURE_INSET := 8

## Each game's accent and ink (UI_STYLE.md §4): its card wears it. Cadence Karaoke's accent
## follows its world in play; the hub uses its default neon.
const LOOKS := {
	"kart_race": [Color("8c6bff"), Color("210f3d")],
	"dodge_ball": [Color("38b6ff"), Color("0e1b3d")],
	"tug_of_war": [Color("ff9f1c"), Color("2a160b")],
	"safe_cracker": [Color("e8b04a"), Color("14110d")],
	"cadence_karaoke": [Color(1.0, 0.45, 0.8), Color("12052a")],
	"watt_lane": [Color("f0875a"), Color("0f1a2e")],
}

static var _looks := {}


## The hub's look: the app's own house look.
static func look() -> GameTheme:
	return GameTheme.house()


## A game's look for its card (the house look for an unknown game).
static func game_look(game_id: String) -> GameTheme:
	if not LOOKS.has(game_id):
		return look()
	if not _looks.has(game_id):
		_looks[game_id] = GameTheme.new(LOOKS[game_id][0], LOOKS[game_id][1], 0.12)
	return _looks[game_id]


## The hub's backdrop: the summary's gradient in the house look (one TextureRect, one call).
static func backdrop() -> TextureRect:
	var t := look()
	var g := Gradient.new()
	g.colors = PackedColorArray([t.ink.lerp(t.accent, 0.3), t.ink.darkened(0.35)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 256
	var r := TextureRect.new()
	r.name = "Backdrop"
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Stage.bleed(r)  # the whole window, past the centred stage (#57)
	return r


## A label in the hub's look. Text on a solid card skips the outline (UI_STYLE.md §8): `flat`.
static func label(text: String, size: int, color := GameTheme.INK, flat := false) -> Label:
	var l := look().label(text, size, color, true)
	if flat:
		flatten(l)
	return l


## Drops a label's outline and shadow (text on a solid card or pill).
static func flatten(l: Label) -> Label:
	l.add_theme_constant_override("outline_size", 0)
	l.remove_theme_color_override("font_shadow_color")
	return l


## A section heading ("PLAY A GAME"): leaning, muted, in the display face.
static func heading(text: String) -> Label:
	var l := look().label(text.to_upper(), HEADING, GameTheme.MUTED, false)
	l.add_theme_font_override("font", GameTheme.display_font(false))
	return l


## A pill button in the hub's look, at least TARGET tall.
static func button(text: String, action: Callable, kind := GameTheme.PRIMARY, min_size := Vector2(300, TARGET)) -> Button:
	var b := look().button(text, action, kind)
	b.custom_minimum_size = min_size
	b.disabled = false
	return b


## "12:30" for seconds.
static func clock(seconds: float) -> String:
	return HudTheme.clock(seconds)


## "18:40" or "1:02:00" for a duration, or "Open" for -1.
static func duration(sec: int) -> String:
	return "Open" if sec < 0 else HudTheme.clock(float(sec))


## The rider's name as a card shows it: trimmed (inner runs of spaces folded), at most
## NAME_MAX characters with an ellipsis, or "You" (Kart Race's `KartRoster.rider_label` rule).
const NAME_MAX := 12


static func short_name(profile_name: String) -> String:
	var n := " ".join(Array(profile_name.strip_edges().split(" ", false)))
	if n.is_empty():
		return "You"
	if n.length() > NAME_MAX:
		n = n.left(NAME_MAX - 1).strip_edges() + "…"
	return n


## A game's title for a slot `width` wide: its full title, or its short name ("Cadence") when
## the full one doesn't fit even at SMALL.
static func fit_title(game_id: String, width: float) -> String:
	var info := GameRegistry.info(game_id)
	var full: String = info.title if info else game_id.capitalize()
	if GameTheme.display_font().get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL).x <= width:
		return full
	return LineupStrip.SHORT.get(game_id, full)
