extends RefCounted
## Live Wire: the game's rendered music and effects (#55). Written by
## games/tools/music/render_music.py from songs/watt_lane.py; don't edit by hand.

const TITLE := "Live Wire"
const BPM := 112.0
const KEY := 3  ## the key's pitch class (0 = C)
const LOOP_FROM := 8.5714  ## seconds: the intro plays once, the rest loops
## The stems: the bed always plays; harmony and lead are gated by the game.
const STEM_FILES := {
	"bed": "res://games/watt_lane/music/live_wire_bed.ogg",
	"harmony": "res://games/watt_lane/music/live_wire_harmony.ogg",
	"lead": "res://games/watt_lane/music/live_wire_lead.ogg",
}
const SOUNDS := {
	"jump_chime": "res://games/watt_lane/music/sfx/jump_chime.ogg",
	"count_tick": "res://games/watt_lane/music/sfx/count_tick.ogg",
	"lane_shift": "res://games/watt_lane/music/sfx/lane_shift.ogg",
	"caught": "res://games/watt_lane/music/sfx/caught.ogg",
	"missed": "res://games/watt_lane/music/sfx/missed.ogg",
	"off_buzz": "res://games/watt_lane/music/sfx/off_buzz.ogg",
	"streak_up": "res://games/watt_lane/music/sfx/streak_up.ogg",
}
