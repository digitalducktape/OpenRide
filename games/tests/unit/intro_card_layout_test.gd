extends GdUnitTestSuite
## Rider feedback (2026-11): Balloon Pump's intro card clipped when the countdown reached 3-2-1
## and grew to HUGE. Every registered game's card, in its own look, with its picture, how-to,
## target, a previous result and the skip button, must fit the card at both countdown sizes, and
## the countdown must not move the card's contents when it grows.

const SEGMENT := {"role": "work", "intro_sec": 6, "count": 3, "index": 1, "difficulty": "standard",
	"duration_sec": 120, "params": {"ftp_watts": 200.0, "ftp_is_default": false, "target_watts": 210}}
const PREVIOUS := {"game_id": "demo", "score": 12345, "stars": 2}


func _check(game_id: String, card: IntroCard, label: String) -> void:
	# Containers sort on the next frames (an autowrapped label learns its width first).
	for i in 3:
		await get_tree().process_frame
	var inner := Rect2(Vector2.ZERO, IntroCard.CARD_SIZE)
	var ok := card._card.size.is_equal_approx(IntroCard.CARD_SIZE)
	for child in card._card.get_child(0).get_children():
		var c := child as Control
		if c.visible:
			ok = ok and inner.encloses(Rect2(c.position + card._card.get_child(0).position, c.size))
	assert_bool(ok).override_failure_message("%s (%s): the card is %s for %s of contents" % [game_id, label,
		card._card.size, card._card.get_combined_minimum_size()]).is_true()


func _game(game_id: String) -> Game:
	var game: Game = GameRegistry.instantiate(game_id)
	game.hud = auto_free(load("res://framework/hud/Hud.gd").new())
	add_child(game.hud)
	add_child(game)
	var seg := SEGMENT.duplicate(true)
	seg["game_id"] = game_id
	seg["seed"] = 3
	if not GameRegistry.info(game_id).roles.has("work"):
		seg["role"] = "free"
	game.prepare(seg)
	return game


func test_every_game_s_card_fits_at_both_countdown_sizes() -> void:
	for game_id in GameRegistry.ids():
		var game := _game(game_id)
		var card: IntroCard = auto_free(IntroCard.new())
		add_child(card)
		var info := GameRegistry.info(game_id)
		card.apply_theme(game.ui_theme())
		card.show_segment(info, SEGMENT, game.target_text(SEGMENT), PREVIOUS, "Demo", true,
			game.how_to_text(SEGMENT), game.intro_visual())
		card.set_time_left(6.0)
		await _check(game_id, card, "whole seconds")
		var y_before := card._title.global_position.y
		card.set_time_left(2.5)
		await _check(game_id, card, "3-2-1")
		assert_float(card._title.global_position.y).override_failure_message("%s: the 3-2-1 moved the card" % game_id) \
			.is_equal_approx(y_before, 0.5)
		card.queue_free()
		game.queue_free()
		game.hud.queue_free()
