class_name GridBanner
extends CalloutBanner
## Power Grid's callouts ("Funfair next: hold 130 W", "Line down! Hold 170 W for 10 s"): the
## framework's `CalloutBanner` in a lane over the sky. The HUD's centre message would sit on the
## town, the hero. The lane is clear of every HUD panel and of the moon (grid_layout_test checks
## both). A storm's instruction outranks a district's news (`show_callout`'s priority).

## The lane (1920x1080 canvas): under the status widget, between the side panels.
const LANE := Rect2(650, 150, 830, 70)
const SIZE := HudTheme.BODY + 4  ## 48 px: the longest instruction fits the lane on one line
const NARROW_SIZE := HudTheme.BODY  ## the longest instruction in a lane cut short by the HUD


func _init(look: GameTheme) -> void:
	super(look, LANE, SIZE, NARROW_SIZE)
