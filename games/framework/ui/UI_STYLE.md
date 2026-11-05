# Game UI style guide

How every mini-game's UI looks, moves and stays readable. It distils what made Kart Race feel
polished (`games/kart_race/ART_BIBLE.md` §7 and §10) into rules that every game follows, with
one shared kit, `GameTheme` (`framework/ui/GameTheme.gd`). Kart Race keeps its own
`KartTheme`, which follows the same rules.

**Who reads the screen.** A rider on a bike about 1 m from a 1920x1008 tablet. They glance at
it between pedal strokes, sweating, and tap with one finger. Design for a half-second glance at
50% scale. Capture with `tests/capture_ui_states.gd` (half-size PNGs) and judge it at that size.

## 1. Typography

- **One display face: Lilita One** (SIL OFL 1.1, `assets/fonts/`, listed in
  `assets/SOURCES.md`), from `GameTheme.display_font()` or a theme's `font()`. It's chunky,
  rounded and has wide counters, so its numbers read at a glance. It also means no new licence to
  check. Each game's identity comes from its accent, its ink and its badge lean (§3), not from a
  different face. A second face per game would cost a licence review, a second glyph atlas
  (more draw calls) and a less coherent app.
- **Sizes** (1080p canvas, `HudTheme`): countdown 160 (`HUGE`), glance numbers 96 (`BIG`),
  headings and badges 56 (`MEDIUM`), sentences 44 (`BODY`), captions 34 (`SMALL`).
  **Nothing below 34**, including text drawn with `draw_string` (dial numerals, too). `GameTheme`
  raises anything smaller to 34.
- **Upright** for numbers, buttons and sentences. **Leaning** (a theme with `italic`) only for
  badges and banners.
- Numbers that change must not shift their neighbours. Give the label a `custom_minimum_size`
  for its widest value, or align it right.

## 2. Outline and shadow

- **Every label over a 3D or busy scene has an outline in the game's ink**, `max(6, size/6)` px
  (`GameTheme.outline_for`). Never pure black: the ink is the game's darkest colour.
- **A drop shadow only from 70 px**, in the ink at 55%. Each shadow is another text pass, so
  small labels skip it.
- **Gradient fill (`hero`) only on hero text**: a title, a countdown digit, a result, or the one
  big number a game is about. Each gradient is a material, so it costs its own draw call: **at
  most two gradient labels on screen during play.** Labels with the same size and gradient share
  one material.

## 3. Shapes: panels, badges, buttons

| Shape | Use | Kit |
| --- | --- | --- |
| Panel | HUD panels, status widgets | `panel_style()`: ink fill at 86%, accent edge 3 px with a 6 px bottom edge, soft shadow (4, 6), radius 22, upright |
| Badge | chips, banners, callouts ("WAVE 3", "SURGE!") | `badge_style()`: accent (or a meaning colour) fill, leaning by the theme's `skew`, white edge; `badge_style(fill, true)` is the slim chip for a tight row |
| Card | intro and pause cards | `card_style()`: radius 32, 10 px bottom edge |
| Pill button | every touch target | `button(text, action, kind)`: PRIMARY (accent), SECONDARY (dark, accent outline), GO (green), DANGER (red) |

- No square-cornered panels and no 1 px lines. A bar or gauge has a dark track and a 2-3 px edge.
- Circles for lives, tumbler lights and orbs. Draw them as shapes, not glyphs.

## 4. Colour

**Meaning colours are the same in every game** (`GameTheme`, matching the ride metrics):

| Colour | Means | Constant |
| --- | --- | --- |
| Green | good, in band, won, Resume | `GOOD` (gradient `GOOD_GRADIENT`) |
| Amber | warning, nearly out of band, "pedal up" | `WARN` |
| Red | bad, alarm, lost, End | `BAD` (gradient `BAD_GRADIENT`) |
| Gold | the target to aim for, stars, points | `TARGET` (gradient `GOLD_GRADIENT`) |
| White / lavender | values / captions | `INK` / `MUTED` |

- **Never colour alone.** Each meaning colour comes with a word ("SLOW DOWN"), an icon or a
  shape (the marker's side of the rope). Red and green must not be the only difference.
- **Each game's identity** is its accent and its ink (`GameTheme.new(accent, ink, skew, italic)`).
  The accent goes on panel edges, primary buttons, titles and chips. The ink goes on outlines,
  panel fills and shadows. **An accent is never a meaning colour.** Don't make an accent green or
  red. If a world's colour is close to one (Cadence's recovery green), keep meaning on words.

| Game | Accent | Ink | Skew | Feel |
| --- | --- | --- | --- | --- |
| Kart Race | violet `#8C6BFF` + gold | `#210F3D` | 0.18-0.3 | Saturday-morning cartoon (KartTheme) |
| Dodge Ball | sky cyan `#38B6FF` | navy `#0E1B3D` | 0.18, italic | sports-day arcade, quick |
| Tug of War | rope orange `#FF9F1C` | bark `#2A160B` | 0.12 | rustic fairground, heavy |
| Safe Cracker | brass `#E8B04A` | soot `#14110D` | 0, upright | noir heist, precise and quiet |
| Cadence Karaoke | the world's neon (`CadenceWorld.theme_color`) | deep violet `#12052A` | 0.25, italic | synthwave stage, on the beat |
| Keepy Uppy | sunset coral `#FF7A59` | sky navy `#12233A` | 0.08 | open air, lift |
| House (`GameTheme.house()`) | periwinkle `#7A7CFF` | deep indigo `#17143A` | 0.12 | the app's own: a circuit's summary, and the summary and calibration of a game without a look |

## 5. Hierarchy and layout

- **One hero per screen.** Each game names the one thing the rider must read at a glance (Tug:
  who's winning; Cadence: the target rpm; Safe: the dial's reading against the target; Dodge:
  the shield). It's the biggest and brightest thing on screen. Everything else is a caption.
- The framework HUD owns the corners: the ride panel top left, the clock and score top right,
  and Pause | End under the clock. The game's status widget goes in the top-centre slot
  (`hud.add_widget`). Keep it to two rows at most and above the horizon. **Its budget is
  850 x 120 px** with the longest texts: between the ride panel (590 px wide with the effort
  badge) and the clock panel (363 px wide at a five-digit score). Tug's widget is already 848
  px wide. Add a case for it to `hud_layout_test` before you change its contents.
- **The centre third stays clear during play** (Dodge's road, Tug's rope, Safe's dial, Cadence's
  orb). Brief messages (`hud.show_message`) go there by design. They must not sit on the game's
  own hero widget. If the hero is in the middle (Safe's dial), show the game's callouts in its
  own banner, not the HUD message.
- Overlays (intro, pause, summary) take every touch on their shade. Only End, then its
  confirmation, ends a session.

## 6. Touch targets

- **At least 110 px tall and 220 px wide** (`HudTheme.BUTTON_HEIGHT`). Make the hit area at
  least the drawn shape. A round target gets a hit circle 1.25x its drawn radius.
- **Keep game targets far from End**: at least 120 px between hit rects, ideally across the
  screen. End sits top right, so game buttons go at the bottom (centre or left). Never put two
  same-looking buttons side by side when one of them ends the session.
- No focus on touch buttons (`FOCUS_NONE`: on a desktop, Space is the simulator's stand).
- A pressed state is visible (the kit lightens it) and the action gives feedback within a frame
  (a pop, a sound, a value change).
- Test with real touches, like `intro_touch_test.gd` and `kart_presentation_test.gd`.

## 7. Motion

Motion means something happened. Use tweens on `scale`, `modulate` and the transform, **never a
re-layout** (no size, text or theme change every frame) and never per-frame GDScript for looks.

| Event | Motion | Kit |
| --- | --- | --- |
| Score or streak up, a widget gains | pop 1.2-1.35, 0.3-0.35 s, back-out | `GameTheme.pop(c)` |
| Loss (a life, a hit) | pop down to 0.8, or a flash | `pop(c, 0.8)`, `flash(c)` |
| Countdown digit, banner, result | slam in from 1.8x, 0.35 s | `slam(c)` |
| A state that holds (alarm, empty shield, surge) | breathe 1.0-1.06, 0.9 s period, stopped when it ends | `pulse(c, on)` |
| A widget comes or goes | fade 0.2 s (`keep_layout` keeps its place at alpha 0) | `fade(c, show, sec, keep_layout)` |
| Brief message | pops in when it appears or changes, gone within 1.5-2.5 s | `hud.show_message` with a theme skin |

- Durations are 0.2-0.5 s. Nothing loops forever except a held state, and that stops with it.
- In a container, animate `scale` around the centre (the kit sets the pivot). Scale is visual
  only, so neighbours don't move. Don't tween `position` inside a container.
- `GameTheme.stop(c, motion)` stops one of the kit's motions ("pop", "flash", "pulse", "fade")
  or all of them, without settling.
- A screen's entrance (the summary) staggers its parts: the title slams, then each star in
  turn, then the tiles and the best. It is done within about 1.5 s, and its button works from
  the first frame.
- Juice goes on the events the rider caused: a dodge, a catch, a tumbler, a round won, a streak
  step. Pair it with the sound that already plays.

## 8. Tablet budget

- **Draw calls: at most 120 a frame in play.** The four games measured 50-107 on the desktop
  in the before captures (Cadence 50, Safe 95, Tug 95, Dodge 94-107). The HUD with the kit's
  skin costs no more than the plain one: Dodge measured 96 before and 94 after.
- One font (one glyph atlas) for the whole HUD. Don't mix the engine's default face with the
  display face in one widget: it splits batches.
- At most two gradient labels during play. Use outlines, not stacked duplicate labels.
- Labels change only when their values change. Keep the existing "only on change" checks when
  you restyle.
- `_draw` widgets redraw only on a change (`queue_redraw` on a new value), not every frame. A
  pulsing drawn element animates `modulate` or `scale`, not a redraw.
- On GL Compatibility each `draw_circle`, `draw_line`, `draw_arc` and `draw_colored_polygon`
  is its own draw call. Gather a drawn widget's shapes in a `ShapeBatch` (`framework/hud/`):
  one triangle array, one call (the calibration figure, the star rows).
- Text on a solid card or pill (not over the 3D scene) may skip the outline and the drop
  shadow: each is another text pass. The summary's rows and the pause card's line do.
- Don't add full-screen overlays. A flash uses the game's existing FX layer and hides itself
  when idle (Dodge's `_fx_rect`).
- 3D views keep their SubViewport scale (0.62-0.67). UI work never changes it.

## 9. Do and don't

**Do**

- Make one `GameTheme` per game (or per segment, if the accent follows the world), return it
  from `Game.ui_theme()`, and call `hud.set_skin(theme.hud_skin())` in `_on_prepare`. The intro
  card, the pause screen, the calibration screens and the summary then take the look by
  themselves. If the look changes mid-segment, emit `ui_theme_changed`.
- Restyle existing widgets with `theme.style_label(l)` and `theme.style_button(b, kind)`. Keep
  their "only on change" logic.
- Say things in a few words: "SLOW DOWN", "SURGE!", "Held it!". Use one spelling throughout
  (British: "pedalling").
- Check every state in a capture at 50%: intro, play, the high-tension moment, pause, results.

**Don't**

- Draw text under 34 px, or any text over the 3D scene without the ink outline.
- Put a touch target near End, or a HUD element over the centre third.
- Use colour alone for meaning, or a meaning colour as the accent.
- Use pure black, 1 px lines or square panels.
- Use any franchise's names, logos, HUD layouts, fonts or look-alike art. Fonts are OFL or
  permissive only, each in `assets/SOURCES.md` with its licence file.

## 10. The kit (`GameTheme`)

```gdscript
static var look := GameTheme.new(Color("38b6ff"), Color("0e1b3d"), 0.18, true)  # accent, ink, skew, italic

func ui_theme() -> GameTheme:  # Game hook: styles the intro card and the pause screen
	return look

func _on_prepare(seg: Dictionary) -> void:
	hud.set_skin(look.hud_skin())  # panels, Pause / End / Recalibrate, the message (pops in)
	var wave := look.label("WAVE 1", HudTheme.MEDIUM)  # outlined display face
	var title := look.hero("CRACKED!", HudTheme.BIG, GameTheme.GOLD_GRADIENT)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", look.badge_style())
	var minus := look.button("−5 rpm", func(): adjust_pace(-1), GameTheme.PRIMARY)
	GameTheme.pop(score_label)  # motion: pop, slam, flash, pulse, fade
```

| API | What |
| --- | --- |
| `GameTheme.new(accent, ink, skew := 0.0, italic := false)` | a game's look; `accent_top`, `accent_bottom`, `panel`, `panel_edge` can be set after |
| `display_font(upright := true)` (static), `font(upright := false)` | the shared face |
| `label(text, size, color := INK, upright := false)`, `style_label(l, size := 0, color = null, upright := false)` | outlined labels; restyle an existing one |
| `hero(text, size, gradient := [])`, `set_gradient(l, gradient := [], clear := false)` | gradient hero text |
| `panel_style(fill = null, lean := 0.0, radius := 22)`, `badge_style(fill = null, slim := false)`, `card_style()` | StyleBoxes |
| `button(text, action, kind := PRIMARY)`, `style_button(b, kind)`, `button_style(kind, pressed)` | pill buttons |
| `hud_skin()` | a `Hud.set_skin` dictionary (add layout keys to it) |
| `pop`, `slam`, `flash`, `pulse`, `fade`, `stop` (static) | motion |
| `house()` (static) | the app's own look, for framework screens without a game's |
| `INK`, `MUTED`, `GOOD`, `WARN`, `BAD`, `TARGET`, `*_GRADIENT`, `outline_for(size)` | meaning colours |

`Hud.set_skin` also takes `message_font` and `message_outline_color` (set by `hud_skin()`).
`IntroCard.apply_theme(theme)`, `PauseOverlay.apply_theme(theme)` and
`CalibrationOverlay.apply_theme(theme)` are called by the session from `Game.ui_theme()`, at
each segment and on `Game.ui_theme_changed`. For the intro and pause cards `null` gives the
kit's plain look, which is what the demo gets (Kart Race's `kart_look()` is KartTheme's
palette as a `GameTheme`); the calibration screens and the
summary use the house look instead. The summary takes the look of the game it follows (a
circuit: the house look, each row in its game's accent). The open-ride "Game over" panel stays
neutral. `tests/unit/game_theme_test.gd` covers the kit; `tests/capture_framework_screens.gd`
captures the summary and calibration screens.
