extends Game
## Kart Race (#43): a Grand Prix of 3-lap races against seven bots. Pedal to drive, lean to
## steer (the head tracker), tap to use items. The contract is games/kart_race/DESIGN.md.
##
## The logic lives in plain classes under logic/ (track space, physics, race, Grand Prix, bots,
## scoring), stepped here at a fixed 30 Hz from `_on_frame`; the nodes only draw it, every frame,
## between the last two ticks (`_draw`, KartState.draw_into). This scene
## wires it to the framework: declarations, options, the GP flow, inputs, HUD, audio, the result.
##
## Ownership (Phase 2 agents edit only their own builder plus a few lines of wiring):
##   _build_world()   world agent      the track's look (KartWorld)
##   _build_camera()  handling agent   KartChaseCamera
##   _build_racers()  racers agent     KartView per kart (bots: race-systems agent)
##   _build_items()   race-systems     items and their views
##   _build_hud()     presentation     KartStatus, the boards, countdown, banners
##   _build_audio()   presentation     music and effects
##   _build_fx()      presentation     sparks, flames, dust, speed lines
## Each race's logic is announced by `race_began(race)` before its countdown: hook its `events`
## there rather than editing `_begin_race`.
##
## GP flow (enum FSM, `flow`): IDLE (the grid behind the intro card) → COUNTDOWN (the title
## fly-over, then 3-2-1-GO) → RACING → RESULTS (8 s, karts drive on) → the next race's COUNTDOWN,
## or PODIUM after the final race → DONE (end_segment). `request_finish` ends at once with the
## standings so far. The kart and the starting track are picked in the Games hub before Start
## (the `driver` and `track` options, `where: hub`), so `_on_prepare` builds the chosen track
## once and gameplay opens straight on the fly-over.

signal race_began(race: KartRaceLogic)

enum Flow { IDLE, COUNTDOWN, RACING, RESULTS, PODIUM, DONE }

## The 3D view renders into a SubViewport at this share of 1080p, drawn scaled under the HUD
## (Dodge Ball's pattern: the tablet's GPU is fill-rate bound; scaling_3d_scale < 1 hangs it).
## 0.66 (2026-10-16): the most resolution against aliasing within 2 fps on the tablet (0.72 cost
## about 4; MSAA 2x renders the 3D view black there, and Compatibility has no FXAA).
const RENDER_SCALE := 0.66
## The quality governor's last trim (KartQualityGovernor tier `scale`): no lower than this.
const RENDER_SCALE_TRIMMED := 0.58
const FX_CAP_TRIMMED := 0.5
## The governor goes no lower than this tier: half the effects' caps (their GDScript). Foliage,
## crowd and render scale cost the look and saved nothing measurable on the tablet, which is bound
## by the main thread (tier 0 against tier 4 with the tracker running, the same clocks: 40.4 and
## 41.6 fps, render CPU 9.3 ms both; 2026-10-15). The tuning file can still force any tier.
const GOVERNOR_FLOOR := 1
const MSAA := Viewport.MSAA_DISABLED  ## 2x halved the frame rate on the tablet (Dodge Ball)
## Developer aid, off in every build: set true to read `user://kart_tuning.cfg` ([render]
## scale, msaa, outlines, glow; [world] road, walls, ground, scenery, hud, fx, track, laps; [governor]
## enabled, tier: a fixed tier with the governor off) and log the frame cost every 5 s.
const DEV_TUNING := false
const TUNING_PATH := "user://kart_tuning.cfg"
const PERF_LOG_SEC := 5.0

## The logic's fixed step. 30 Hz: the tablet is bound by the main thread, and the logic was most
## of its GDScript (4-7 ms a tick with the face tracker running, 2026-10-15). The lean arrives at
## the camera's 30 Hz anyway; the views draw at the frame rate between the last two ticks.
const TICK := 1.0 / 30.0
const MAX_TICKS := 4  ## per frame (133 ms), so a stall never snowballs
const RIDER := KartRaceLogic.RIDER
const RACERS := 8
const COUNTDOWN_SEC := 3.0
## Before each countdown the camera flies over the grid under the title card (the race logic's
## countdown runs FLYOVER_SEC + COUNTDOWN_SEC; the numbers show for the last three).
const FLYOVER_SEC := 3.5
const RESULTS_SEC := 8.0
const PODIUM_SEC := 6.0
const PODIUM_S := 12.0  ## the 3D podium stands this far past the start line (the gate behind it)
## Speed lines start at this share of the rider's steady 0.6 FTP speed and are full SPAN later.
const SPEED_LINES_FROM := 1.15
const SPEED_LINES_SPAN := 0.12
## Other karts closer to the camera than this (metres) are hidden, so none fills the screen.
const CAMERA_CLEAR := 4.2
## Karts farther than this from the camera (metres) pose at a third of the frame rate, and
## beyond POSE_CLOSE at half; the rider's kart and those nearer every frame.
const POSE_NEAR := 35.0
const POSE_CLOSE := 18.0
## A kart this far behind the camera's plane (metres) is out of sight: no pose, no exhaust.
const BEHIND_CLEAR := 3.0
const GO_SEC := 0.8
const DEFAULT_FTP := 150.0
## The bots' shares of the rider's FTP, weakest to strongest, by difficulty. Each bot's drive
## adds its cadence's spin watts like the rider's (KartPhysics.drive_power). Retuned 2026-10-19
## with the drive power so an ordinary ride (80-90 rpm at 30-40%, about 100-150 W) sits
## mid-pack at the default 150 W FTP. Kotlin sends `params.bot_pcts`; these are the fallback.
const BOT_PCTS := {
	"easy": [0.40, 0.85],
	"standard": [0.50, 1.00],
	"hard": [0.60, 1.15],
}
const BOT_LINES := [-1.5, 1.5, -0.5, 0.5, -2.0, 2.0, 0.0]
const ASSIST := {"off": 0.0, "low": 0.5, "high": 1.0}
## The hub's card pictures (spec §7.2): the racers' baked portraits
## (tests/capture_kart_portraits.gd) and the tracks' thumbnails (tests/capture_track_thumbs.gd).
const PORTRAITS := "res://games/kart_race/ui/portraits/%s.png"
const THUMBS := "res://games/kart_race/ui/tracks/%s.png"

static var _look: GameTheme

var race: KartRaceLogic
var gp: KartGrandPrix
var scoring: KartScoring
var track: KartTrackModel
var world: KartWorld
var camera: KartChaseCamera
var views: Array[KartView] = []
var bots: Array = []  ## KartBotDriver per kart id; null for the rider
var items: KartItemLogic  ## race-systems: this race's pods, items and projectiles
var lineup: Array = []  ## KartRoster entries per kart id
var flow := Flow.IDLE
var current := {}  ## this race: {track_id, reversed, laps, is_final, index}
var ftp_w := DEFAULT_FTP
var sim_time := 0.0  ## seconds simulated this segment
## Tests: the rider's input, instead of InputBus.
var test_input: KartInput = null

var _view: SubViewport
var _status: KartStatus
var _board: KartRaceBoard
var _kart_hud: KartHud
var _fx: KartFx
var _item_views: KartItemViews  # race-systems
var _podium: KartPodium  ## the Grand Prix podium on the track, while it shows (presentation)
var _podium_ids: Array[int] = []  ## the karts on it, champion first
var _audio: KartAudio  # presentation
var _hud_lineup := ""
var _lights := -1
var _acc := 0.0
var _flow_left := 0.0
var _est_lap := 60.0
var _race_total := 0  ## the races this GP plans (presentation: "Race 2/4"); 0 when open-ended
var _built_track := ""
var _rider_input := KartInput.new()
var _input_list := []  ## reused every tick
## What the views, the camera and the item views draw: each kart between its last two ticks.
var _draw: Array[KartState] = []
var _item_key := false
var _item_edge := false
var _countdown_shown := -1
var _message_left := 0.0
var _lineup_dirty := false
## The adaptive quality for this session (KartQualityGovernor); null when tuning turns it off.
var quality: KartQualityGovernor
var _render_scale := RENDER_SCALE
var _applied_tier := 0
var _music_parallel := true
var _tuning := ConfigFile.new()
var _tuned := false
var _perf_usec := 0
var _perf_frames := 0
var _perf_dc_max := 0  ## the most draw calls in one frame since the last perf line
var _perf_ticks := 0  ## logic ticks since the last perf line, and their time
var _perf_tick_usec := 0
var _perf_sync_usec := 0  ## _sync_views and _update_hud time
var _perf_hud_usec := 0
var _perf_proc_ms := 0.0  ## the engine's process time per frame, summed
var _perf_render_cpu := 0.0  ## every viewport's measured render time, summed
var _perf_render_gpu := 0.0
var _perf_vps: Array[Viewport] = []
## Each viewport's last measured render time: a viewport that didn't render this frame (an idle
## bake) keeps reporting its last render's time, so only a changed value counts.
var _perf_vp_last := {}
var _perf_vp_renders := 0  ## viewport renders counted since the last perf line
var _perf_frame_ms := 0.0
var _perf_frame_max := 0.0
var _perf_game_max := 0
var _perf_first: _PerfProbe
var _perf_last: _PerfProbe


## DEV_TUNING: stamps the time it processes (first and last in the frame, by priority).
class _PerfProbe extends Node:
	var stamp := 0
	var prev := 0

	func _process(_delta: float) -> void:
		prev = stamp
		stamp = Time.get_ticks_usec()
var _perf_left := PERF_LOG_SEC


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "kart_race"
	i.title = "Kart Race"
	i.how_to = "Pedal to drive · lean to steer · lean hard to drift · tap to use items"
	i.supports = ["minutes", "open"]
	i.min_sec = 300
	i.max_sec = 3600
	i.roles = []
	# Lean steers; standing (reported in every camera mode) is for the climbs.
	i.tracker_mode = "lean_stand"
	i.effort_in_just_ride = true
	i.own_countdown = true  # the grid's 3-2-1-GO is the only countdown
	i.timed_end_mode = "game"  # a timed GP ends on the final race's finish line
	i.stars_per_minute = true
	# Points a minute, tuned in simulation (race-systems: KartScoring): about 1 star mid-pack at
	# 1.0×, 3 stars takes podiums and effort. Provisional until the bike.
	i.star_thresholds = KartScoring.STAR_THRESHOLDS
	i.options = [
		# Picked in the Games hub before Start (spec §7.2): a card per racer, then per track. The
		# chosen kart wears the rider's name, as it does on the grid.
		{"key": "driver", "label": "Your kart", "choices": KartRoster.ids(), "labels": KartRoster.option_labels(),
			"default": "fox", "where": "hub", "kind": "cards", "columns": 4, "rider_badge": true, "cards": kart_cards()},
		{"key": "track", "label": "Starting track", "choices": KartTracks.CUP, "labels": KartTracks.titles(),
			"default": KartTracks.CUP[0], "where": "hub", "kind": "cards", "columns": 4, "cards": track_cards()},
		{"key": "assist", "label": "Steering assist", "choices": ["off", "low", "high"],
			"labels": ["Off", "Low", "High"], "default": "high", "kind": "segmented", "group": "More options"},
		{"key": "camera", "label": "Camera", "choices": ["chase", "close"],
			"labels": ["Chase", "Close"], "default": "chase", "kind": "segmented", "group": "More options"},
		{"key": "auto_items", "label": "Auto items", "choices": ["off", "on"],
			"labels": ["Off", "On"], "default": "off", "kind": "segmented", "group": "More options"},
	]
	return i


## The hub's kart cards: portrait, name, class ("Light kart"), the kart's colour.
static func kart_cards() -> Array:
	var out := []
	for r in KartRoster.RACERS:
		out.append({"value": r.id, "title": r.name, "subtitle": "%s kart" % KartRoster.kart_class(r).capitalize(),
			"image": PORTRAITS % r.id, "accent": r.color})
	return out


## The hub's track cards: thumbnail, title, lap length ("1,148 m").
static func track_cards() -> Array:
	var out := []
	var titles := KartTracks.titles()
	for i in KartTracks.CUP.size():
		var id: String = KartTracks.CUP[i]
		out.append({"value": id, "title": titles[i], "subtitle": "%s m" % thousands(roundi(KartTracks.length_of(id))),
			"image": THUMBS % id})
	return out


## "1,148" for 1148.
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Kart Race's look for the framework's screens (intro, pause and its options, calibration, the
## summary): KartTheme's violet night with its leaning badges, so they match the race's own UI.
static func kart_look() -> GameTheme:
	if _look == null:
		_look = GameTheme.new(Color("8c6bff"), Color("210f3d"), 0.18, true)
		_look.panel = KartTheme.PANEL
		_look.panel_edge = KartTheme.PANEL_EDGE
	return _look


func ui_theme() -> GameTheme:
	return kart_look()


func target_text(seg: Dictionary) -> String:
	var duration := float(seg.get("duration_sec", -1))
	if duration < 0.0:
		return "Grand Prix · race as long as you like"
	var p: Dictionary = seg.get("params", {})
	var n := planned_races(duration, KartGrandPrix.estimate_lap_sec(KartTracks.average_length(), _ftp_of(p)))
	return "Grand Prix · %d race%s" % [n, "" if n == 1 else "s"]


## How many races a GP of `duration` seconds plans, if each race takes its estimate.
static func planned_races(duration: float, est_lap: float) -> int:
	var plan := KartGrandPrix.new(duration, KartTracks.CUP)
	var left := duration
	var n := 0
	while n < 60:
		var next := plan.next_race(left, est_lap)
		n += 1
		if next.is_final:
			break
		left -= next.laps * est_lap + KartGrandPrix.RACE_OVERHEAD_SEC
	return n


static func _ftp_of(p: Dictionary) -> float:
	var ftp := float(p.get("ftp_watts", DEFAULT_FTP))
	return ftp if ftp > 0.0 else DEFAULT_FTP


func _ready() -> void:
	# Music renders on one worker thread while Kart Race runs: the parallel render took every
	# core for 1-2.5 s at each tempo change, and the frame rate fell to 16-30 meanwhile (the
	# tablet, 2026-10-15). A render now takes longer and the tempo changes a phrase later.
	_music_parallel = MusicGen.parallel
	MusicGen.parallel = false
	_tuned = DEV_TUNING and _tuning.load(TUNING_PATH) == OK
	var scale := RENDER_SCALE
	if _tuned:
		scale = clampf(float(_tuning.get_value("render", "scale", RENDER_SCALE)), 0.4, 1.0)
	_view = SubViewport.new()
	_view.name = "View3D"
	_render_scale = scale
	_view.size = _view_size(scale)
	_view.msaa_3d = int(_tuning.get_value("render", "msaa", MSAA)) if _tuned else MSAA
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.audio_listener_enable_3d = false
	add_child(_view)
	if DEV_TUNING:
		_perf_first = _PerfProbe.new()
		_perf_first.process_priority = -1000000
		_perf_last = _PerfProbe.new()
		_perf_last.process_priority = 1000000
		get_tree().root.add_child.call_deferred(_perf_first)
		get_tree().root.add_child.call_deferred(_perf_last)
	var shown := TextureRect.new()
	shown.name = "View3DImage"
	shown.texture = _view.get_texture()
	shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shown.stretch_mode = TextureRect.STRETCH_SCALE
	shown.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# No full-screen pass: the colour grade is folded into every world shader, and speed lines
	# are drawn as thin polygons by KartHud (a graded upscaling blit cost about 5 fps).
	KartView.outlines = not _tuned or bool(_tuning.get_value("render", "outlines", true))
	add_child(shown)
	Stage.bleed(shown)  # the whole window, past the centred stage (#57)
	Stage.changed.connect(_fit_view)
	if _tuned:
		print("OPENRIDE_GAMES kart_race render scale=%.2f size=%s msaa=%d" % [scale, _view.size, _view.msaa_3d])


func _exit_tree() -> void:
	MusicGen.parallel = _music_parallel
	for probe in [_perf_first, _perf_last]:
		if probe and is_instance_valid(probe):
			probe.queue_free()


func _on_prepare(seg: Dictionary) -> void:
	ftp_w = _ftp_of(params)
	_new_governor()
	flow = Flow.IDLE
	sim_time = 0.0
	_acc = 0.0
	_built_track = ""
	# The starting track the rider chose in the hub (GameOptions) is the only one built: its
	# grid shows behind the intro card, then the fly-over and 3-2-1-GO.
	gp = KartGrandPrix.new(float(seg.get("duration_sec", -1)), KartGrandPrix.cup_from(KartTracks.CUP, option("track")), RACERS)
	scoring = KartScoring.new()
	scoring.rider_id = RIDER
	scoring.awarded.connect(func(points: float, _why: String): award(points))
	lineup = KartRoster.lineup(option("driver"), RACERS, rider_label())
	_est_lap = KartGrandPrix.estimate_lap_sec(KartTracks.average_length(), ftp_w)
	_build_world()
	_build_camera()
	_build_racers()
	_build_items()
	_build_hud()
	_build_audio()
	_build_fx()
	_apply_quality()
	# The first race's grid shows behind the intro card.
	_begin_race()
	stats = scoring.stats(gp)


func _on_start() -> void:
	_start_countdown()


func _on_option_changed(key: String, _value: String) -> void:
	match key:
		"assist":
			if race:
				race.physics.assist = ASSIST.get(option("assist"), 1.0)
		"camera":
			if camera:
				camera.mode = option("camera")
		"auto_items":  # race-systems
			if items:
				items.auto_rider = option("auto_items") == "on"
		"driver":  # hub-only (`where: hub`): only a test or a later pause card changes it here
			_lineup_dirty = true
			if playing:
				_show_message("New driver from the next race", 2.0)


func _on_finish_requested() -> void:
	# The race in progress counts as it stands.
	if race and race.phase == KartRaceLogic.Phase.RACING and flow == Flow.RACING:
		gp.record(race.order())
	_finish_gp()


# --- Builders: one per Phase 2 agent ---

## World agent: the 3D world for the track (KartWorld builds per track in `_begin_race`).
func _build_world() -> void:
	world = KartWorld.new()
	world.name = "World"
	if _tuned and _tuning.has_section("world"):
		for key in _tuning.get_section_keys("world"):
			if key == "laps":  # measuring: every race this many laps ([world] laps=1)
				continue
			if key == "track":  # world: measure one track ([world] track=canyon_dash)
				KartTracks.dev_track = str(_tuning.get_value("world", key))
			else:
				world.tuning[key] = bool(_tuning.get_value("world", key))
	_view.add_child(world)
	if _tuned and bool(_tuning.get_value("render", "glow", false)):
		world.set_glow(true)


## Handling agent: the chase camera (Chase / Close option), and each race's handling: the camera
## watches the rider's boosts, bumps and hits; the drift thresholds scale with the rider's FTP.
func _build_camera() -> void:
	camera = KartChaseCamera.new()
	camera.name = "ChaseCamera"
	camera.mode = option("camera")
	world.add_child(camera)
	camera.current = true
	race_began.connect(func(r: KartRaceLogic):
		camera.watch(r.events, RIDER)
		r.physics.top_speed = KartPhysics.reference_speed(ftp_w))


## Racers agent (views) and race-systems agent (bots): a KartView per kart, a KartBotDriver per
## bot. Kart id = index in `lineup`; 0 is the rider.
func _build_racers() -> void:
	for v in views:
		v.queue_free()
	views = []
	for i in lineup.size():
		var v := KartView.new()
		v.setup(lineup[i])
		world.add_child(v)
		views.append(v)
	var pcts := _bot_pcts()
	bots = [null]
	for i in range(1, lineup.size()):
		# Kart 1 is on pole and the strongest; the weakest starts just ahead of the rider.
		# race-systems: each bot has its own personality (line, drifting, items, aggression).
		var profile := KartBotDriver.profile_for(i - 1, pcts[clampi(lineup.size() - 1 - i, 0, pcts.size() - 1)])
		bots.append(KartBotDriver.new(profile, ftp_w, rng.randi()))


## Race-systems agent: item pods, the held item and projectiles (and the Auto items option).
## Each race gets its own KartItemLogic (stepped in `_tick` after the race), handed to the bots
## for their item policy and hazards, and drawn by KartItemViews.
func _build_items() -> void:
	_item_views = KartItemViews.new()
	_item_views.name = "Items"
	world.add_child(_item_views)
	race_began.connect(func(r: KartRaceLogic):
		items = KartItemLogic.new(r, rng.randi())
		items.auto_rider = option("auto_items") == "on"
		for b in bots:
			if b:
				b.items = items
		_item_views.bind(items, r))


## Presentation agent: the game HUD (KartHud: lap badge, racer list, minimap, ride strip, item
## button, drift meter, position), the framework HUD's skin (fonts, panels, the ride panel hidden
## for the strip, room for the item button), the boards, and the lap and final-lap banners.
func _build_hud() -> void:
	hud.set_skin(KartHud.hud_skin())
	_kart_hud = KartHud.new()
	add_child(_kart_hud)
	_status = _kart_hud.status
	if _tuned:
		_kart_hud.visible = bool(_tuning.get_value("world", "hud", true))
	_kart_hud.item_pressed.connect(_on_item_pressed)
	if not InputBus.controller_item.is_connected(_on_item_pressed):
		InputBus.controller_item.connect(_on_item_pressed)  # a controller's Use item (#68)
	_board = KartRaceBoard.new()
	_board.portrait_maker = _kart_hud.portrait_rect
	add_child(_board)
	race_began.connect(func(r: KartRaceLogic):
		var key := ",".join(lineup.map(func(x): return str(x.id)))
		if key != _hud_lineup:
			_hud_lineup = key
			_kart_hud.setup(lineup, track)
		_kart_hud.set_track(track)  # a new track (or direction) redraws the minimap
		_kart_hud.set_gameplay_visible(false, false)
		_lights = -1
		# A bound method, not a lambda: a lambda capturing `r` would keep every race alive
		# (race → events → lambda → race).
		r.events.lap_completed.connect(_on_lap_banner))


## Presentation agent: music and effects (KartAudio: each track's rendered theme and its final-lap
## version, engine and tyre loops, every effect through AudioDirector).
func _build_audio() -> void:
	if _audio:
		_audio.queue_free()
	_audio = KartAudio.new()
	_audio.game = self
	add_child(_audio)
	if _kart_hud:  # the place cue lands on the badge's pop
		_kart_hud.place_popped.connect(_audio.on_place_popped)
	race_began.connect(func(r: KartRaceLogic): _audio.listen(r))


## Presentation agent: sparks, flames, dust, speed lines.
func _build_fx() -> void:
	_fx = KartFx.new()
	_fx.name = "Fx"
	_fx.camera = camera
	world.add_child(_fx)
	if _tuned and not bool(_tuning.get_value("world", "fx", true)):
		_fx.visible = false
	race_began.connect(func(r: KartRaceLogic):
		_fx.begin(views)
		_fx.listen(r.events))


# --- The Grand Prix ---

## Sets up the next race on its grid (the countdown starts separately).
func _begin_race() -> void:
	if _lineup_dirty:
		_lineup_dirty = false
		lineup = KartRoster.lineup(option("driver"), RACERS, rider_label())
		_build_racers()
	var time_left := _time_left()
	# The races this GP will run, this one included (a timed ride's plan; 0 when open-ended).
	_race_total = gp.races_run() + planned_races(time_left, _est_lap) if time_left >= 0.0 else 0
	current = gp.next_race(time_left, _est_lap)
	if bool(current.get("is_final", false)):
		_race_total = gp.races_run() + 1
	if _tuned and int(_tuning.get_value("world", "laps", 0)) > 0:  # measuring: short races
		current.laps = int(_tuning.get_value("world", "laps", 0))
	var key := "%s:%s" % [current.track_id, current.reversed]
	if key != _built_track:
		track = KartTrackModel.new(KartTracks.build(current.track_id), current.reversed)
		world.build(track)  # keeps the quality trims in force
		_built_track = key
	camera.shot = world.grid_shot  # the title shot frames this track's landmark
	race = KartRaceLogic.new()
	race.physics.assist = ASSIST.get(option("assist"), 1.0)
	race.physics.drift_resistance = float(params.get("drift_resistance", race.physics.drift_resistance))
	var racers := []
	for r in lineup:
		racers.append({"racer_id": r.id, "weight": r.weight})
	race.setup(track, racers, current.laps)
	_draw.clear()
	for k: KartState in race.karts:
		_draw.append(KartState.new())
	if _item_views:
		_item_views.draw_karts = _draw
	scoring.begin_race(race)
	race.events.race_started.connect(_on_race_started)
	race.events.race_finished.connect(_on_race_finished)
	race.events.final_lap.connect(_on_final_lap)
	flow = Flow.IDLE
	_sync_views(0.0)
	camera.snap(_draw[RIDER])
	race_began.emit(race)


## "Race 2/4" (a timed GP's plan), "Race 2" (open-ended); the last is "Final race" on the lap
## badge (`compact`) and "Final race · 4/4" on the title chip.
func _race_label(compact := false) -> String:
	var n := maxi(gp.races_run() + (0 if flow == Flow.RESULTS or flow == Flow.PODIUM else 1), 1)
	var of := "%d/%d" % [n, _race_total] if _race_total >= n else str(n)
	if bool(current.get("is_final", false)):
		return "Final race" if compact else "Final race · " + of
	return "Race " + of


func _start_countdown() -> void:
	race.start_countdown(COUNTDOWN_SEC + FLYOVER_SEC)
	flow = Flow.COUNTDOWN
	_countdown_shown = -1
	var chip := "Grand Prix · " + _race_label()
	if _kart_hud:
		_kart_hud.show_title(chip, track.def.title + (" (reversed)" if track.reversed else ""),
			FLYOVER_SEC * KartChaseCamera.SHOT_HOLD - 0.5 if not camera.shot.is_empty() else FLYOVER_SEC - 0.6)


func _on_race_started() -> void:
	flow = Flow.RACING
	_kart_hud.go()


## "LAP 2/3"; the last lap has its own banner (_on_final_lap).
func _on_lap_banner(kart_id: int, lap: int, _t: float) -> void:
	if kart_id == RIDER and race and lap + 1 < race.laps:
		_kart_hud.banner("LAP %d/%d" % [lap + 1, race.laps], 1.1)


func _on_final_lap(kart_id: int) -> void:
	if kart_id == RIDER and race.laps > 1:
		_kart_hud.banner("FINAL LAP!", 1.6, "Give it everything", true)


func _on_race_finished(order: Array) -> void:
	gp.record(order)
	stats = scoring.stats(gp)
	won = gp.champion() == RIDER
	flow = Flow.RESULTS
	_flow_left = RESULTS_SEC
	var totals := {}  # presentation: the GP total beside each race result
	for row in gp.standings():
		totals[row.kart_id] = row.points
	var rows := []
	for i in order.size():
		var id: int = order[i]
		var k: KartState = race.karts[id]
		rows.append({"name": _racer_name(id), "detail": "+%d" % KartGrandPrix.POINTS[i] if i < KartGrandPrix.POINTS.size() else "",
			"total": _pts(int(totals.get(id, 0))),
			"racer_id": str(lineup[id].id), "you": id == RIDER,
			# Still racing when the rider finished: a projected time (KartRaceLogic), shown muted.
			"projected": k.finish_time > race.time + 0.001,
			"time": KartTheme.race_time(k.finish_time) if i == 0 else KartTheme.race_gap(k.finish_time - race.karts[order[0]].finish_time)})
	var place := order.find(RIDER) + 1
	var title := "Victory!" if place == 1 else ("On the podium!" if place <= 3 else "Nice drive!")
	var subtitle := "Grand Prix · %s · %s" % [_race_label(), track.def.title]
	_board.show_board(title, rows, subtitle, RESULTS_SEC, "Final standings" if bool(current.get("is_final", false)) else "Next race")
	_status_area(true)  # the camera strip moves under the board's rows
	_kart_hud.set_gameplay_visible(false)
	_status.visible = false


## The board's time is up: the next race, the podium, or the end.
func _after_board() -> void:
	if flow == Flow.RESULTS and bool(current.get("is_final", false)):
		flow = Flow.PODIUM
		_flow_left = PODIUM_SEC
		var rows := []
		for row in gp.standings():
			rows.append({"name": _racer_name(row.kart_id), "detail": _pts(row.points), "points": _pts(row.points),
				"racer_id": str(lineup[row.kart_id].id), "you": row.kart_id == RIDER,
				"time": "%d win%s" % [row.wins, "" if row.wins == 1 else "s"]})
		var champ := gp.champion() == RIDER
		var place := gp.place_of(RIDER)
		var title := "Champion!" if champ else ("Grand Prix podium!" if place <= 3 else "Grand Prix standings")
		_board.show_podium(title, rows, "Final standings · %d race%s" % [gp.races_run(), "" if gp.races_run() == 1 else "s"], PODIUM_SEC, "Ride summary", _stage_podium())
		return
	if flow == Flow.PODIUM:
		_finish_gp()
		if has_ended():
			return
	# Another race (also when a timed slot refused to end early).
	_board.hide_board()
	_clear_podium()
	_status_area(false)
	_status.visible = true
	_begin_race()
	_start_countdown()


func _status_area(board: bool) -> void:
	var area := KartHud.status_area(board)
	hud.set_status_area(area[0], area[1])


## Presentation: stages the 3D podium on the start straight, the top three's own karts landing
## on it under a held camera, and returns where its blocks and karts show on screen for the
## board (KartPodium.screen_points); {} when there's no world to stage it in.
func _stage_podium() -> Dictionary:
	if world == null or track == null or camera == null or _view == null or not camera.is_inside_tree():
		return {}
	_clear_podium()
	var standings := gp.standings()
	for i in mini(3, standings.size()):
		_podium_ids.append(int(standings[i].kart_id))
	var s0 := track.wrap(PODIUM_S)
	var origin := track.position_at(s0, 0.0)
	var ahead := track.position_at(track.wrap(s0 + 2.0), 0.0) - origin
	_podium = KartPodium.new()
	world.add_child(_podium)
	_podium.stage(world.scenery_mat, origin, ahead)
	camera.hold = true
	camera.held = _podium.camera_transform()
	camera.global_transform = camera.held
	camera.fov = KartPodium.CAMERA_FOV
	for v in views:
		v.visible = false
	if _item_views:
		_item_views.visible = false
	if _fx:
		_fx.visible = false
	return _podium.screen_points(camera, Vector2(_view.size))


func _clear_podium() -> void:
	if _podium == null:
		return
	_podium.queue_free()
	_podium = null
	_podium_ids.clear()
	camera.hold = false
	for v in views:
		v.visible = true
	if _item_views:
		_item_views.visible = true
	if _fx:
		_fx.visible = not _tuned or bool(_tuning.get_value("world", "fx", true))


## The podium's frame: the blocks rise, the karts drop on them and cheer, facing the camera.
func _sync_podium(delta: float) -> void:
	_podium.advance(delta)
	var eye := camera.global_position
	for j in _podium_ids.size():
		var v: KartView = views[_podium_ids[j]]
		var shown := _podium.kart_shown(j)
		v.visible = shown
		if shown:
			v.seen = true
			v.pose_every = 1
			v.look_target = eye
			v.look_weight = 0.6
			v.sync(_podium.kart_state(j), delta)
	camera.follow(_draw[RIDER], delta)  # held


func _finish_gp() -> void:
	stats = scoring.stats(gp)
	won = gp.races_run() > 0 and gp.champion() == RIDER
	flow = Flow.DONE
	end_segment()


func _time_left() -> float:
	var duration := float(segment.get("duration_sec", -1))
	if duration < 0.0:
		return -1.0
	if not InputBus.is_simulated() and InputBus.segment_time_left >= 0.0:
		return InputBus.segment_time_left
	return maxf(0.0, duration - played_sec)


func _bot_pcts() -> Array:
	var given = params.get("bot_pcts")
	if given is Array and given.size() == RACERS - 1:
		return given.map(func(v): return float(v))
	var span: Array = BOT_PCTS.get(difficulty, BOT_PCTS.standard)
	var out := []
	for i in RACERS - 1:
		out.append(lerpf(span[0], span[1], float(i) / (RACERS - 2)))
	return out


## "1 pt", "12 pts" (presentation).
static func _pts(n: int) -> String:
	return "%d pt%s" % [n, "" if n == 1 else "s"]


## The name on a kart: the rider's is their profile name (KartRoster.rider_label), the bots'
## their own. The rider's row is told apart by its gold, not a "(you)".
func _racer_name(kart_id: int) -> String:
	return str(lineup[kart_id].name) if kart_id < lineup.size() else "?"


## The rider's name as their kart shows it ("You" without a profile name).
func rider_label() -> String:
	return KartRoster.rider_label(Session.rider_name())


# --- Every frame ---

func _on_frame(delta: float) -> void:
	if not DEV_TUNING:
		_frame(delta)
		return
	var started := Time.get_ticks_usec()
	_frame(delta)
	_perf_usec += Time.get_ticks_usec() - started
	_perf_frames += 1
	_perf_game_max = maxi(_perf_game_max, Time.get_ticks_usec() - started)
	# The whole process step (the first and last _process of the frame, the probes) and the frame
	# (first probe to first probe), both for the frame before this one.
	if _perf_first and _perf_first.prev > 0:
		_perf_proc_ms += (_perf_last.stamp - _perf_first.prev) / 1000.0 if _perf_last.stamp > _perf_first.prev else 0.0
		var frame_ms := (_perf_first.stamp - _perf_first.prev) / 1000.0
		_perf_frame_ms += frame_ms
		_perf_frame_max = maxf(_perf_frame_max, frame_ms)
	for vp: Viewport in _perf_vps:
		if is_instance_valid(vp):
			var rid := vp.get_viewport_rid()
			var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
			var always := vp == _view or vp == get_viewport()
			if always or cpu != float(_perf_vp_last.get(rid, -1.0)):
				_perf_render_cpu += cpu
				_perf_render_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
				_perf_vp_renders += 1
			_perf_vp_last[rid] = cpu
	_perf_dc_max = maxi(_perf_dc_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_perf_left -= delta
	if _perf_left <= 0.0:
		var frames := maxi(_perf_frames, 1)
		print("OPENRIDE_GAMES kart_race perf game_ms=%.2f ticks=%.2f tick_ms=%.2f sync_ms=%.2f hud_ms=%.2f process_ms=%.2f frame_ms=%.2f frame_max_ms=%.1f game_max_ms=%.1f render_cpu_ms=%.2f render_gpu_ms=%.2f viewports=%d vp_renders=%.2f fps=%d draw_calls=%d draw_calls_max=%d objects=%d primitives=%d karts=%d track=%s%s flow=%s tracker=%d tier=%d" % [
			_perf_usec / 1000.0 / frames,
			float(_perf_ticks) / frames,
			_perf_tick_usec / 1000.0 / maxi(_perf_ticks, 1),
			_perf_sync_usec / 1000.0 / frames,
			_perf_hud_usec / 1000.0 / frames,
			_perf_proc_ms / frames,
			_perf_frame_ms / frames,
			_perf_frame_max,
			_perf_game_max / 1000.0,
			_perf_render_cpu / frames,
			_perf_render_gpu / frames,
			_perf_vps.size(),
			float(_perf_vp_renders) / frames,
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			_perf_dc_max,
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			race.karts.size() if race else 0,
			track.def.id if track else "-", "_rev" if track and track.reversed else "",
			Flow.keys()[flow], InputBus.tracker_state, _applied_tier])
		_perf_usec = 0
		_perf_frames = 0
		_perf_ticks = 0
		_perf_tick_usec = 0
		_perf_sync_usec = 0
		_perf_hud_usec = 0
		_perf_proc_ms = 0.0
		_perf_render_cpu = 0.0
		_perf_render_gpu = 0.0
		_perf_frame_ms = 0.0
		_perf_frame_max = 0.0
		_perf_game_max = 0
		# Every viewport that renders (the 3D view, the bakes, the screen), measured.
		_perf_vp_renders = 0
		_perf_vp_last.clear()
		_perf_vps.clear()
		_perf_vps.append(get_viewport())
		for vp: Node in find_children("*", "SubViewport", true, false):
			_perf_vps.append(vp)
		for vp: Viewport in _perf_vps:
			RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
		_perf_dc_max = 0
		_perf_left = PERF_LOG_SEC


func _frame(delta: float) -> void:
	if quality and quality.sample(delta, flow == Flow.RACING and not paused):
		_apply_quality()
		var step: Dictionary = quality.steps.back()
		print("OPENRIDE_GAMES kart_race quality tier=%d (%s) after %.1f fps on %s" % [step.tier, quality.tier_name(), step.fps, track.def.id if track else "-"])
	var key := InputBus.is_simulated() and Input.is_key_pressed(KEY_E)
	_item_edge = _item_edge or (key and not _item_key)
	_item_key = key
	_acc = minf(_acc + delta, TICK * MAX_TICKS)
	var t0 := Time.get_ticks_usec() if DEV_TUNING else 0
	while _acc >= TICK:
		_acc -= TICK
		_tick(TICK)
		if DEV_TUNING:
			_perf_ticks += 1
		if has_ended():
			return
	var t1 := Time.get_ticks_usec() if DEV_TUNING else 0
	_sync_views(delta)
	var t2 := Time.get_ticks_usec() if DEV_TUNING else 0
	_update_hud(delta)
	if DEV_TUNING:
		_perf_tick_usec += t1 - t0
		_perf_sync_usec += t2 - t1
		_perf_hud_usec += Time.get_ticks_usec() - t2


## A session's governor at full quality (the tier never carries over from the last session).
## The tuning file can turn it off and fix a tier: [governor] enabled=false tier=2.
func _new_governor() -> void:
	quality = KartQualityGovernor.new()
	quality.floor_tier = GOVERNOR_FLOOR
	var fixed := 0
	if _tuned:
		fixed = clampi(int(_tuning.get_value("governor", "tier", 0)), 0, KartQualityGovernor.TIERS.size() - 1)
		if not bool(_tuning.get_value("governor", "enabled", true)):
			quality.floor_tier = fixed
			quality.tier = fixed
	_applied_tier = -1


## Puts the governor's tier in force: the world's foliage and crowd, the effects' caps, the
## render scale (the last resort: resizing the view costs one hitch).
func _apply_quality() -> void:
	var g := quality
	if g == null or g.tier == _applied_tier:
		return
	_applied_tier = g.tier
	if world:
		world.set_quality(KartWorld.CELL_RANGE_TRIMMED if g.trims(&"foliage") else KartWorld.CELL_RANGE,
			KartWorld.CROWD_TRIMMED if g.trims(&"crowd") else 1.0)
	if _fx:
		_fx.cap_share = FX_CAP_TRIMMED if g.trims(&"fx") else 1.0
	_fit_view()


## The 3D view's size for the window and the governor's tier.
func _fit_view() -> void:
	var trimmed := quality != null and quality.trims(&"scale")
	var size := _view_size(minf(_render_scale, RENDER_SCALE_TRIMMED) if trimmed else _render_scale)
	if _view.size != size:
		_view.size = size


func _view_size(scale: float) -> Vector2i:
	return Stage.view_size(scale)


## One fixed step of the whole game.
func _tick(dt: float) -> void:
	sim_time += dt
	match flow:
		Flow.IDLE, Flow.DONE:
			return
		Flow.RESULTS, Flow.PODIUM:
			_flow_left -= dt
			if _flow_left <= 0.0:
				_after_board()
				return
	var inputs := _inputs(dt)
	race.step(dt, inputs)
	if items:  # race-systems: pods, items, projectiles
		items.step(dt, inputs)
	scoring.step(dt, inputs[RIDER].power_w)


func _inputs(dt: float) -> Array:
	var inputs := _input_list
	inputs.resize(race.karts.size())
	inputs[RIDER] = _read_rider()
	for id in range(1, race.karts.size()):
		inputs[id] = bots[id].think(race.karts[id], race, dt)
	return inputs


func _read_rider() -> KartInput:
	if test_input:
		return test_input
	_rider_input.power_w = InputBus.power
	_rider_input.cadence = InputBus.cadence
	_rider_input.lean = InputBus.steer_x()  # a steering controller's level, else head lean (#68)
	_rider_input.resistance = InputBus.resistance
	_rider_input.standing = InputBus.standing
	# handling: no drifts on face loss (a steering controller never loses the face)
	_rider_input.tracking = InputBus.controller_steering or InputBus.tracker_state != InputBus.TRACKER_FACE_LOST
	_rider_input.use_item = _item_edge
	_item_edge = false
	return _rider_input


func _sync_views(delta: float) -> void:
	if _podium:
		_sync_podium(delta)
		if _audio:
			_audio.step(race, Flow.keys()[flow], delta)
		return
	# Between the last two ticks: the time since the last one, as a share of a tick.
	var alpha := clampf(_acc / TICK, 0.0, 1.0)
	for i in race.karts.size():
		(race.karts[i] as KartState).draw_into(_draw[i], alpha)
	for i in views.size():
		views[i].sync(_draw[i], delta)
	var k: KartState = _draw[RIDER]
	# The countdown fell a tick at the last step; drawn, it falls smoothly.
	var countdown := race.countdown + TICK * (1.0 - alpha) if race.phase == KartRaceLogic.Phase.COUNTDOWN else race.countdown
	if flow == Flow.IDLE:
		camera.flyover(k, 0.0, track)
	elif flow == Flow.COUNTDOWN and countdown > COUNTDOWN_SEC:
		camera.flyover(k, 1.0 - (countdown - COUNTDOWN_SEC) / FLYOVER_SEC, track)
	else:
		camera.follow(k, delta)
	_cull_views()
	if _item_views:  # race-systems
		_item_views.alpha = alpha
		_item_views.sync(delta)
	if _fx:
		_fx.step(race, delta)
	if _audio:  # presentation
		_audio.step(race, Flow.keys()[flow], delta)
	_sync_screen_fx()


## A bot right at the lens would fill the screen: hide it until it's clear (integration). Far
## karts pose at a lower rate (their position still moves every frame: only the driver's
## breathing, wheels and lean step at 20-30 Hz, too small to see from 18 m).
func _cull_views() -> void:
	var eye := camera.global_position
	var look := -camera.global_transform.basis.z
	for i in range(1, views.size()):
		var v: KartView = views[i]
		var to := v.global_position - eye
		var d2 := to.length_squared()
		v.visible = camera.hold or d2 > CAMERA_CLEAR * CAMERA_CLEAR
		v.seen = v.visible and to.dot(look) > -BEHIND_CLEAR
		v.pose_every = 3 if d2 > POSE_NEAR * POSE_NEAR else (2 if d2 > POSE_CLOSE * POSE_CLOSE else 1)


## The HUD's speed lines and draft streaks (presentation).
func _sync_screen_fx() -> void:
	if not _kart_hud:
		return
	var k: KartState = race.karts[RIDER]
	# Only at a real sprint (top_speed is the rider's steady speed at 0.6 FTP, so cruising sits
	# near 1.0), or on a boost: never streaking across a still sky at cruise.
	var top := maxf(race.physics.top_speed, 1.0)
	var lines := clampf((k.speed / top - SPEED_LINES_FROM) / SPEED_LINES_SPAN, 0.0, 1.0) if flow == Flow.RACING else 0.0
	_kart_hud.speed_lines = maxf(lines, minf(k.boost_time, 1.0))
	_kart_hud.draft = _fx.draft_screen(race, camera, _kart_hud) if _fx and flow == Flow.RACING else 0.0


func _update_hud(delta: float) -> void:
	var k: KartState = race.karts[RIDER]
	var race_text := _race_label(true)
	_status.set_state(k.place, race.karts.size(), k.lap, race.laps, race_text)
	_kart_hud.update(race, delta)
	var lights := 0
	if flow == Flow.COUNTDOWN:
		if race.countdown <= COUNTDOWN_SEC:
			lights = clampi(5 - ceili(race.countdown / (COUNTDOWN_SEC / 5.0)) + 1, 1, 5)
		var n := ceili(race.countdown)
		if n != _countdown_shown and n > 0 and n <= int(COUNTDOWN_SEC):
			_countdown_shown = n
			_kart_hud.countdown(n)
			if n == int(COUNTDOWN_SEC):
				_kart_hud.set_gameplay_visible(true)
	elif flow == Flow.RACING and race.time < 2.0:
		lights = 6
	if lights != _lights:
		_lights = lights
		world.set_start_lights(lights)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			hud.hide_message()


## The item button was tapped: the rider's next KartInput carries `use_item` (an edge that the
## race-systems agent's KartItemLogic reads).
func _on_item_pressed() -> void:
	_item_edge = true


func _show_message(text: String, seconds: float) -> void:
	hud.show_message(text)
	_message_left = seconds
