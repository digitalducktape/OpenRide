class_name LaunchBanner
extends CalloutBanner
## Ready for Launch's callouts ("Hold 120 W to fill the tank", "Push past 210 W!", "Orbit! 412 km"):
## the framework's `CalloutBanner` in a lane under the status widget, above the rocket's tip and
## between the side panels (`launch_scene_test` checks both). Every callout tells the rider what to
## do, with a number the rules use.

const LANE := Rect2(640, 132, 810, 72)
const SIZE := 48
const NARROW_SIZE := HudTheme.BODY  ## the longest callout in a lane cut short by the HUD


func _init(look: GameTheme) -> void:
	super(look, LANE, SIZE, NARROW_SIZE)
