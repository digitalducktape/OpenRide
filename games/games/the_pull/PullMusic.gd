extends RefCounted
## Heavy Haul: the game's rendered music and effects (#55). Written by
## games/tools/music/render_music.py from songs/the_pull.py; don't edit by hand.

const TITLE := "Heavy Haul"
const BPM := 116.0
const KEY := 4  ## the key's pitch class (0 = C)
const LOOP_FROM := 8.2759  ## seconds: the intro plays once, the rest loops
## The stems: the bed always plays; harmony and lead are gated by the game.
const STEM_FILES := {
	"bed": "res://games/the_pull/music/heavy_haul_bed.ogg",
	"harmony": "res://games/the_pull/music/heavy_haul_harmony.ogg",
	"lead": "res://games/the_pull/music/heavy_haul_lead.ogg",
}
const SOUNDS := {
	"engine_drone": "res://games/the_pull/music/sfx/engine_drone.ogg",
	"chain_strain": "res://games/the_pull/music/sfx/chain_strain.ogg",
	"box_scrape": "res://games/the_pull/music/sfx/box_scrape.ogg",
	"crowd_swell": "res://games/the_pull/music/sfx/crowd_swell.ogg",
	"pull_horn": "res://games/the_pull/music/sfx/pull_horn.ogg",
	"stall_horn": "res://games/the_pull/music/sfx/stall_horn.ogg",
	"dig_in": "res://games/the_pull/music/sfx/dig_in.ogg",
	"board_pass": "res://games/the_pull/music/sfx/board_pass.ogg",
	"best_pass": "res://games/the_pull/music/sfx/best_pass.ogg",
	"full_pull": "res://games/the_pull/music/sfx/full_pull.ogg",
}
