extends RefCounted
## Candy Stripe March: the game's rendered music and effects (#55). Written by
## games/tools/music/render_music.py from songs/balloon_pump.py; don't edit by hand.

const TITLE := "Candy Stripe March"
const BPM := 126.0
const KEY := 5  ## the key's pitch class (0 = C)
const LOOP_FROM := 7.6191  ## seconds: the intro plays once, the rest loops
## The stems: the bed always plays; harmony and lead are gated by the game.
const STEM_FILES := {
	"bed": "res://games/balloon_pump/music/candy_stripe_march_bed.ogg",
	"harmony": "res://games/balloon_pump/music/candy_stripe_march_harmony.ogg",
	"lead": "res://games/balloon_pump/music/candy_stripe_march_lead.ogg",
}
const SOUNDS := {
	"pump_chuff": "res://games/balloon_pump/music/sfx/pump_chuff.ogg",
	"pump_squeak": "res://games/balloon_pump/music/sfx/pump_squeak.ogg",
	"pump_tie": "res://games/balloon_pump/music/sfx/pump_tie.ogg",
	"pump_hiss": "res://games/balloon_pump/music/sfx/pump_hiss.ogg",
	"pump_gold": "res://games/balloon_pump/music/sfx/pump_gold.ogg",
	"pump_heat_start": "res://games/balloon_pump/music/sfx/pump_heat_start.ogg",
	"pump_won": "res://games/balloon_pump/music/sfx/pump_won.ogg",
	"pump_lost": "res://games/balloon_pump/music/sfx/pump_lost.ogg",
	"pump_tick": "res://games/balloon_pump/music/sfx/pump_tick.ogg",
}
