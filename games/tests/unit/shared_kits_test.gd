extends GdUnitTestSuite
## The kits more than one game uses (docs/GAMES.md, "Shared game kits"): the HUD's timed message,
## the gauge bar's redraw budget, and the banners' place under the status area.


func test_a_timed_message_hides_by_itself() -> void:
	var hud: Hud = auto_free(Hud.new())
	add_child(hud)
	hud.show_message("Caught it!", HudTheme.INK, 0.5)
	hud._process(0.3)
	assert_bool(hud.is_showing_message()).is_true()
	hud._process(0.3)
	assert_bool(hud.is_showing_message()).is_false()


func test_a_timed_message_waits_while_paused_and_an_untimed_one_stays() -> void:
	var hud: Hud = auto_free(Hud.new())
	add_child(hud)
	hud.show_message("Get set", HudTheme.INK, 0.5)
	hud.set_paused(true)
	hud._process(2.0)
	assert_bool(hud.is_showing_message()).is_true()
	hud.set_paused(false)
	hud._process(0.6)
	assert_bool(hud.is_showing_message()).is_false()
	hud.show_message("Game over")
	hud._process(60.0)
	assert_bool(hud.is_showing_message()).is_true()


func test_the_gauge_bar_redraws_only_when_a_pixel_or_a_colour_changes() -> void:
	var bar: GaugeBar = auto_free(GaugeBar.new(Vector2(400, 40), Color("151336")))
	add_child(bar)
	bar.set_fill(0.5, GameTheme.GOOD)
	bar.set_line(0.7)
	await get_tree().process_frame
	await get_tree().process_frame
	var draws := bar.draws
	for i in 10:
		bar.set_fill(0.5 + 0.0001 * i, GameTheme.GOOD)  # under a pixel
		bar.set_line(0.7)
		await get_tree().process_frame
	assert_int(bar.draws).is_equal(draws)
	bar.set_fill(0.5, GameTheme.WARN)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(bar.draws).is_equal(draws + 1)


func test_banners_sit_under_the_status_area_wherever_it_ends() -> void:
	var banner: CalloutBanner = auto_free(CalloutBanner.new(GameTheme.house(), Rect2(660, 124, 720, 70), HudTheme.MEDIUM))
	assert_float(banner.lane_top(100.0)).is_equal(124.0)
	assert_float(banner.lane_top(200.0)).is_equal(200.0 + CalloutBanner.STATUS_GAP)
	assert_float(SafeBanner.slot_top(100.0)).is_equal(SafeBanner.TOP)
	assert_float(SafeBanner.slot_top(220.0)).is_equal(220.0 + CalloutBanner.STATUS_GAP)
