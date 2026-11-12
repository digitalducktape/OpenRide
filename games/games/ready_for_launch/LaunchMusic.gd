extends RefCounted
## Moon Shot: the game's rendered music and effects (#55). Written by
## games/tools/music/render_music.py from songs/ready_for_launch.py; don't edit by hand.

const TITLE := "Moon Shot"
const BPM := 156.0
const KEY := 9  ## the key's pitch class (0 = C)
const LOOP_FROM := 6.1538  ## seconds: the intro plays once, the rest loops
## The stems: the bed always plays; harmony and lead are gated by the game.
const STEM_FILES := {
	"bed": "res://games/ready_for_launch/music/moon_shot_bed.ogg",
	"harmony": "res://games/ready_for_launch/music/moon_shot_harmony.ogg",
	"lead": "res://games/ready_for_launch/music/moon_shot_lead.ogg",
}
const SOUNDS := {
	"rfl_hiss": "res://games/ready_for_launch/music/sfx/rfl_hiss.ogg",
	"rfl_engine": "res://games/ready_for_launch/music/sfx/rfl_engine.ogg",
	"rfl_count": "res://games/ready_for_launch/music/sfx/rfl_count.ogg",
	"rfl_count_final": "res://games/ready_for_launch/music/sfx/rfl_count_final.ogg",
	"rfl_count_start": "res://games/ready_for_launch/music/sfx/rfl_count_start.ogg",
	"rfl_ignition": "res://games/ready_for_launch/music/sfx/rfl_ignition.ogg",
	"rfl_liftoff": "res://games/ready_for_launch/music/sfx/rfl_liftoff.ogg",
	"rfl_stage": "res://games/ready_for_launch/music/sfx/rfl_stage.ogg",
	"rfl_milestone": "res://games/ready_for_launch/music/sfx/rfl_milestone.ogg",
	"rfl_moon": "res://games/ready_for_launch/music/sfx/rfl_moon.ogg",
	"rfl_touchdown": "res://games/ready_for_launch/music/sfx/rfl_touchdown.ogg",
	"rfl_tank_full": "res://games/ready_for_launch/music/sfx/rfl_tank_full.ogg",
	"rfl_cutoff": "res://games/ready_for_launch/music/sfx/rfl_cutoff.ogg",
	"rfl_scrub": "res://games/ready_for_launch/music/sfx/rfl_scrub.ogg",
	"rfl_result": "res://games/ready_for_launch/music/sfx/rfl_result.ogg",
}
