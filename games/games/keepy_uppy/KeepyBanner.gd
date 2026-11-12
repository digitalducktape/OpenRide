class_name KeepyBanner
extends CalloutBanner
## Keepy Uppy's callouts ("Rain: 130 W holds it up", "Downdraft! Push!", "POP! −50", "Shook it
## off!"): the framework's `CalloutBanner` in Keepy's lane (UI_POLISH.md item 1). The HUD's centre
## message sat on the balloon and the column, exactly where the rider looks. The lane is clear of
## every HUD panel and above the balloon at its highest, birds included (keepy_scene_test checks
## both).

## The lane (1920x1080 canvas): under the status widget, between the side panels.
const LANE := Rect2(660, 124, 720, 70)
const SIZE := HudTheme.MEDIUM
const NARROW_SIZE := HudTheme.BODY  ## the longest callout in a lane cut short by the HUD


func _init(look: GameTheme) -> void:
	super(look, LANE, SIZE, NARROW_SIZE)
