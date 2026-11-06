extends RefCounted
## Clear Round: the game's rendered music and effects (#55). Written by
## games/tools/music/render_music.py from songs/gate_crasher.py; don't edit by hand.

const TITLE := "Clear Round"
const BPM := 138.0
const KEY := 7  ## the key's pitch class (0 = C)
const LOOP_FROM := 6.9565  ## seconds: the intro plays once, the rest loops
## The stems: the bed always plays; harmony and lead are gated by the game.
const STEM_FILES := {
	"bed": "res://games/gate_crasher/music/clear_round_bed.ogg",
	"harmony": "res://games/gate_crasher/music/clear_round_harmony.ogg",
	"lead": "res://games/gate_crasher/music/clear_round_lead.ogg",
}
const SOUNDS := {
	"hoof_canter": "res://games/gate_crasher/music/sfx/hoof_canter.ogg",
	"count_tick": "res://games/gate_crasher/music/sfx/count_tick.ogg",
	"line_chime": "res://games/gate_crasher/music/sfx/line_chime.ogg",
	"take_chime": "res://games/gate_crasher/music/sfx/take_chime.ogg",
	"lift_off": "res://games/gate_crasher/music/sfx/lift_off.ogg",
	"landing": "res://games/gate_crasher/music/sfx/landing.ogg",
	"rail_clatter": "res://games/gate_crasher/music/sfx/rail_clatter.ogg",
	"applause": "res://games/gate_crasher/music/sfx/applause.ogg",
	"clear_round": "res://games/gate_crasher/music/sfx/clear_round.ogg",
	"rein_warn": "res://games/gate_crasher/music/sfx/rein_warn.ogg",
}
