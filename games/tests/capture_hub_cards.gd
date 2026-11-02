extends SceneTree
## Bakes each game's hub card picture, `res://games/<id>/hub_card.png` (512x288, spec §8.3): the
## game's own world, rendered by the game itself a few seconds into a local Just Ride, with the
## framework's cards, HUD and calibration hidden. Re-run it when a game's look changes. Not
## headless; needs a window:
##   $GODOT_BIN --path games --resolution 1920x1080 -s res://tests/capture_hub_cards.gd [-- --only=dodge_ball]
## Then re-import (`--import`).

const GAMES := ["kart_race", "dodge_ball", "tug_of_war", "safe_cracker", "cadence_karaoke", "the_pull"]
const SIZE := Vector2i(512, 288)
## Seconds into the intro before the shot (Kart Race builds its world first).
const WAIT := {"kart_race": 9.0}
const DEFAULT_WAIT := 4.0

var _session: Node
var _director: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.get_slice("=", 1)
	_session = root.get_node("Session")
	_director = _session.director
	for id in GAMES:
		if not only.is_empty() and id != only:
			continue
		_session._local.start({"kind": "just_ride", "plan_id": "capture", "difficulty": "standard", "total_sec": 600,
			"segments": [{"game_id": id, "role": "free", "duration_sec": 600}]})
		var left: float = WAIT.get(id, DEFAULT_WAIT)
		while left > 0.0:
			_hide_framework()
			await create_timer(0.1).timeout
			left -= 0.1
		_hide_framework()
		await process_frame
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
		var path := "res://games/%s/hub_card.png" % id
		img.save_png(ProjectSettings.globalize_path(path))
		print("HUB CARD %s" % path)
		_session.request_end()
		await create_timer(5.5).timeout
	quit()


## Everything the framework draws over the game: only the world stays.
func _hide_framework() -> void:
	for layer in [_director.hud, _director.intro_card, _director.calibration, _director.pause_overlay,
			_director.summary_screen, _director.done_panel]:
		if layer is CanvasItem or layer is CanvasLayer:
			layer.visible = false
	var game: Node = _director.game
	if game:
		for c in game.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
