extends RefCounted
## Evening Current: the game's rendered music and effects (#55). Written by
## games/tools/music/render_music.py from songs/power_grid.py; don't edit by hand.

const TITLE := "Evening Current"
const BPM := 132.0
const KEY := 8  ## the key's pitch class (0 = C)
const LOOP_FROM := 7.2727  ## seconds: the intro plays once, the rest loops
## The stems: the bed always plays; harmony and lead are gated by the game.
const STEM_FILES := {
	"bed": "res://games/power_grid/music/evening_current_bed.ogg",
	"harmony": "res://games/power_grid/music/evening_current_harmony.ogg",
	"lead": "res://games/power_grid/music/evening_current_lead.ogg",
}
const SOUNDS := {
	"grid_hum": "res://games/power_grid/music/sfx/grid_hum.ogg",
	"grid_rain": "res://games/power_grid/music/sfx/grid_rain.ogg",
	"grid_on_0": "res://games/power_grid/music/sfx/grid_on_0.ogg",
	"grid_on_1": "res://games/power_grid/music/sfx/grid_on_1.ogg",
	"grid_on_2": "res://games/power_grid/music/sfx/grid_on_2.ogg",
	"grid_on_3": "res://games/power_grid/music/sfx/grid_on_3.ogg",
	"grid_crackle": "res://games/power_grid/music/sfx/grid_crackle.ogg",
	"grid_out": "res://games/power_grid/music/sfx/grid_out.ogg",
	"grid_relit": "res://games/power_grid/music/sfx/grid_relit.ogg",
	"grid_thunder": "res://games/power_grid/music/sfx/grid_thunder.ogg",
	"grid_strike": "res://games/power_grid/music/sfx/grid_strike.ogg",
	"grid_restored": "res://games/power_grid/music/sfx/grid_restored.ogg",
	"grid_crew_fixed": "res://games/power_grid/music/sfx/grid_crew_fixed.ogg",
	"grid_full_town": "res://games/power_grid/music/sfx/grid_full_town.ogg",
	"grid_firework": "res://games/power_grid/music/sfx/grid_firework.ogg",
	"grid_bell": "res://games/power_grid/music/sfx/grid_bell.ogg",
}
