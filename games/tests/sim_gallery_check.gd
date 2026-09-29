extends SceneTree
## Headless smoke check of the style gallery (#36): every style renders and plays, and a tempo
## change waits for the next phrase boundary, then switches.
##   $GODOT_BIN --headless --path games -s res://tests/sim_gallery_check.gd
## Prints PASS/FAIL and exits non-zero on failure.

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gallery: Control = load("res://audio/gallery/StyleGallery.tscn").instantiate()
	root.add_child(gallery)
	await process_frame
	gallery._bars.select(0)  # 4 bars: one phrase per loop
	for i in gallery._style_menu.item_count:
		gallery._style_menu.select(i)
		gallery._on_style_selected(i)
		gallery._request(false)
		await _until(func(): return gallery._task == -1, 10.0)
		_expect(gallery._players[gallery._current].playing, "%s plays" % gallery._style_menu.get_item_text(i))

	# A fast tempo, so a phrase is short: 4 bars at 180 bpm = 5.33 s.
	gallery._tempo.value = 180.0
	gallery._scale.value = 1.0
	gallery._request(false)
	await _until(func(): return gallery._task == -1, 10.0)
	var first: AudioStreamPlayer = gallery._players[gallery._current]
	await _until(func(): return first.get_playback_position() > 1.0, 5.0)
	gallery._tempo.value = 170.0
	gallery._request(true)
	await _until(func(): return gallery._task == -1, 10.0)
	_expect(gallery._switch_at_phrase and not gallery._pending.is_empty(), "the new tempo waits for the phrase")
	var phrase := MusicGen.bar_samples(180.0) * 4 / 22050.0
	await _until(func(): return gallery._pending.is_empty(), phrase + 1.0)
	_expect(gallery._pending.is_empty(), "switched within a phrase")
	var second: AudioStreamPlayer = gallery._players[gallery._current]
	_expect(second != first, "the new tempo plays on the other player")
	# The switch happens in the first frame past the boundary, and the new loop starts that far
	# in, so its beat grid starts on the boundary. The old loop had reached the phrase's end.
	var since: float = gallery.last_switch.since_boundary
	print("switched %.1f ms after the boundary (old loop was at %.3f of %.3f s)" % [since * 1000.0,
		gallery.last_switch.phrase_before, phrase])
	_expect(since < 0.1, "the switch lands just after the phrase boundary")
	_expect(gallery.last_switch.phrase_before > phrase - 0.2, "the old loop played its phrase out")
	gallery.queue_free()
	await process_frame

	if _failures.is_empty():
		print("PASS sim gallery")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL ", f)
		quit(1)


func _until(condition: Callable, timeout: float) -> void:
	var start := Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - start < timeout * 1000.0:
		await process_frame


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
