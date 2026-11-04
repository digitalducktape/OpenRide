extends RefCounted
## Updraft: the game's rendered music and effects (#55). Written by
## games/tools/music/render_music.py from songs/keepy_uppy.py; don't edit by hand.

const TITLE := "Updraft"
const BPM := 118.0
const KEY := 10  ## the key's pitch class (0 = C)
const LOOP_FROM := 8.1356  ## seconds: the intro plays once, the rest loops
## The stems: the bed always plays; harmony and lead are gated by the game.
const STEM_FILES := {
	"bed": "res://games/keepy_uppy/music/updraft_bed.ogg",
	"harmony": "res://games/keepy_uppy/music/updraft_harmony.ogg",
	"lead": "res://games/keepy_uppy/music/updraft_lead.ogg",
}
const SOUNDS := {
	"keepy_fan_hum": "res://games/keepy_uppy/music/sfx/keepy_fan_hum.ogg",
	"keepy_rain": "res://games/keepy_uppy/music/sfx/keepy_rain.ogg",
	"keepy_squeak": "res://games/keepy_uppy/music/sfx/keepy_squeak.ogg",
	"keepy_pop": "res://games/keepy_uppy/music/sfx/keepy_pop.ogg",
	"keepy_bird_flutter": "res://games/keepy_uppy/music/sfx/keepy_bird_flutter.ogg",
	"keepy_birds_shaken": "res://games/keepy_uppy/music/sfx/keepy_birds_shaken.ogg",
	"keepy_gust": "res://games/keepy_uppy/music/sfx/keepy_gust.ogg",
	"keepy_downdraft_warn": "res://games/keepy_uppy/music/sfx/keepy_downdraft_warn.ogg",
	"keepy_rain_warn": "res://games/keepy_uppy/music/sfx/keepy_rain_warn.ogg",
	"keepy_new_balloon": "res://games/keepy_uppy/music/sfx/keepy_new_balloon.ogg",
	"keepy_high_chime": "res://games/keepy_uppy/music/sfx/keepy_high_chime.ogg",
}
