extends Game
## Power Grid (#81): your bike turns the generator for a small valley town at dusk. Keep up with
## demand as the evening goes on: houses, streetlights, the funfair and the stadium come online,
## and falling short dims the newest of them. A warm-up, a recovery, a cool-down or a work ride.
##
## Rules: `GridLogic` (tested headless; DESIGN.md is the design record). View: `GridStage` (2D,
## drawn in code on the full canvas, Safe Cracker's way; ART_BIBLE.md), with `GridValley`, `GridShed`
## and `GridLights`. HUD: `GridStatus`, `GridBanner`. Audio: `GridAudio`. This scene wires them to the
## framework: declarations, scoring through award(), the result's stats.

const GridAudioScript := preload("res://games/power_grid/GridAudio.gd")

## The look (framework/ui/UI_STYLE.md §4): an arc's pale blue on deep dusk indigo, against the
## warm town. Clear of Dodge's cyan, the house periwinkle and every meaning colour.
static var look := GameTheme.new(Color("8fd8ff"), Color("151336"), 0.06)

## The bar's and the meter's scale ends this far past the most the ride will ask.
const SCALE_HEADROOM := 1.3
const BAND_STEP := 5.0  ## the ride panel's tick moves in steps this big (a re-layout each time)
## Short names for the callouts, so the longest still fits the lane.
const NAMES := ["Houses", "Street lamps", "Funfair", "Stadium"]
const REST_LINES := ["", "Street lamps off for the night", "The funfair's closing up", "The stadium's emptying"]
const LANE_MUSIC_GAP := 8.0  ## px kept between the callouts' lane and the Music button
## Which callouts may cut in on which (GridBanner): a storm's instruction outranks all news.
const NEWS := 0
const WARNING := 2
const STORM := 3

var logic: GridLogic
var world: GridStage
var banner: GridBanner

var _status: GridStatus
var _audio = GridAudioScript.new()
var _scale := 200.0
var _band_shown := -1.0


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "power_grid"
	i.title = "Power Grid"
	i.how_to = "Your bike turns the town's generator. Keep up with demand as the evening goes on"
	i.supports = ["minutes", "open"]
	i.min_sec = 60
	i.max_sec = 3600
	i.roles = ["warmup", "work", "recovery", "cooldown"]
	i.tracker_mode = "off"
	i.effort_in_just_ride = true
	i.stars_per_minute = true
	# Points a minute (DESIGN.md §4; grid_logic_test checks them): demand scales with difficulty, so
	# the stars don't. A perfect ride at 1.0× is about 860, short of 3 stars; 1.3× effort reaches it.
	i.star_thresholds = {
		"easy": [200, 600, 1000],
		"standard": [200, 600, 1000],
		"hard": [200, 600, 1000],
	}
	i.summary_stats = [
		{"key": "lit_pct", "label": "town lit", "suffix": "%"},
		{"key": "districts_max", "label": "districts", "of": "districts_total"},
		{"key": "storms_restored", "label": "lines fixed", "of": "storms"},
	]
	return i


func ui_theme() -> GameTheme:
	return look


## A logic for the segment, for the numbers on the intro card and for play.
func _logic_for(seg: Dictionary) -> GridLogic:
	return GridLogic.new(int(seg.get("seed", 1)), seg.get("params", {}), str(seg.get("role", "free")),
		float(seg.get("duration_sec", -1)), str(seg.get("difficulty", "standard")))


func how_to_text(seg: Dictionary) -> String:
	match str(seg.get("role", "free")):
		"warmup":
			return "Your bike turns the town's generator.\nEase in as the lights come on"
		"cooldown":
			return "The town is going to bed.\nEase off with it, one district at a time"
		"recovery":
			return "A quiet evening in the valley.\nKeep the lights on and rest your legs"
	return declared().how_to


## The intro card's target line, from the segment's params.
func target_text(seg: Dictionary) -> String:
	var l := _logic_for(seg)
	var low := roundi(l.lo * GridLogic.HEADROOM)
	var high := roundi(l.hi * GridLogic.HEADROOM)
	if l.is_easy():
		return "Keep it easy: %d to %d W, never over %d W" % [low, high, roundi(l.cap)]
	return "Meet demand: %d W rising to %d W" % [low, high]


## The intro card's picture: the valley lit, and what each district asks.
func intro_visual() -> Control:
	return GridIntroVisual.new(look, _logic_for(segment))


func _ready() -> void:
	GridAudioScript.register()
	world = GridStage.new()
	world.name = "Stage"
	add_child(world)
	banner = GridBanner.new(look)
	banner.name = "Banner"
	add_child(banner)
	add_child(_audio_node())


func _audio_node() -> Node:
	var holder := Node.new()
	holder.name = "Loops"
	_audio.attach(holder)
	return holder


func _on_prepare(seg: Dictionary) -> void:
	logic = _logic_for(seg)
	_scale = (logic.hi * GridLogic.HEADROOM + logic.storm_watts) * SCALE_HEADROOM
	hud.set_skin(look.hud_skin())
	_status = GridStatus.new(look)
	hud.add_widget(_status)
	# One watts reading on screen: the ride panel shows the same smoothed supply the rules use, its
	# gauge ticked at what meets demand, and its rpm gauge at the "pedalling" floor.
	hud.metrics.set_power_source(func() -> float: return logic.supply)
	hud.metrics.set_cadence_band(GridLogic.PEDAL_RPM)
	_update_band()
	GridAudioScript.start_music()
	_update_status()
	_status.resized.connect(_fit_lane)
	hud.top_bar_moved.connect(_fit_lane)
	hud.ride_panel.resized.connect(_fit_lane)
	hud.music_button.visibility_changed.connect(_fit_lane)
	_fit_lane()
	world.pose(_levels(), logic.night(), 0.0, logic.need() / _scale)
	world.prewarm()


func _on_start() -> void:
	_audio.start()


func _on_pause() -> void:
	_audio.set_paused(true)


func _on_resume() -> void:
	_audio.set_paused(false)


func _on_frame(delta: float) -> void:
	var events := logic.step(delta, InputBus.power, InputBus.cadence, InputBus.sensors_ok)
	if logic.earned > 0.0:
		award(logic.earned)
	for event in events:
		_handle(event)
		_audio.on_event(event)
	_audio.step(delta, logic)
	AudioDirector.set_intensity(GridAudioScript.intensity(logic))
	world.update_view(delta, _levels(), logic.night(), logic.supply / _scale, logic.target() / _scale, InputBus.cadence, logic.pedalling)
	_update_band()
	_update_status()


func _levels() -> Vector4:
	return Vector4(logic.level(0), logic.level(1), logic.level(2), logic.level(3))


func _handle(event: Dictionary) -> void:
	match event.type:
		"district_soon":
			banner.show_callout("%s next: hold %d W" % [NAMES[event.index], roundi(event.need)], GameTheme.TARGET, 3.0, NEWS)
		"district_on":
			banner.show_callout("%s on!" % NAMES[event.index], GameTheme.GOOD, 1.6, NEWS)
		"district_missed":
			banner.show_callout("%d W lights the %s" % [roundi(event.need), str(NAMES[event.index]).to_lower()], GameTheme.WARN, 2.5, WARNING)
		"dimming":
			banner.show_callout("Pedal to %d W: %s fading" % [roundi(event.need), str(NAMES[event.index]).to_lower()], GameTheme.WARN, 2.8, WARNING)
		"district_out":
			banner.show_callout("%d W brings the %s back" % [roundi(event.need), str(NAMES[event.index]).to_lower()], GameTheme.WARN, 2.8, WARNING)
		"relit":
			banner.show_callout("%s back on!" % NAMES[event.index], GameTheme.GOOD, 1.6, 1)
		"district_rest":
			banner.show_callout(REST_LINES[event.index], GameTheme.MUTED, 2.2, NEWS)
		"full_town":
			banner.show_callout("The whole town's lit!", GameTheme.TARGET, 2.2, 1)
			world.celebrate()
		"evening":
			banner.show_callout("Evening %d" % event.number, GameTheme.INK, 2.2, 1)
		"storm_warn":
			world.storm_warning(event.sec)
			banner.show_callout("Storm coming: get ready for %d W" % roundi(event.need), GameTheme.WARN, event.sec, STORM)
		"strike":
			world.strike(event.index)
			banner.show_callout("Line down! Hold %d W for %d s" % [roundi(event.need), roundi(event.sec)], GameTheme.WARN, 5.0, STORM)
		"restored":
			var counted := award(event.bonus)
			world.storm_over()
			banner.show_callout("Line fixed! +%d" % roundi(counted), GameTheme.TARGET, 2.4, STORM)
		"crew_fixed":
			world.storm_over()
			banner.show_callout("The line crew fixed it", GameTheme.MUTED, 2.2, 1)


## The result's stats, built once at the end.
func finish() -> Dictionary:
	if logic == null:
		return super.finish()
	stats = {
		"lit_pct": logic.lit_pct(),
		"districts_max": logic.districts_max,
		"districts_total": GridLogic.COUNT,
		"avg_power": roundi(logic.avg_power()),
		"evenings": logic.evening,
	}
	# Storms only come in work; an easy ride has no tile for them.
	if logic.storms_on:
		stats["storms"] = logic.storms
		stats["storms_restored"] = logic.storms_restored
	return super.finish()


## The hub card's picture (tests/capture_hub_cards.gd): the whole town lit, deep in the evening.
func pose_for_card() -> void:
	world.pose(Vector4.ONE, 0.82, 0.7, 0.62)


## Keeps the callouts' lane under the status area, clear of a ride panel a heart strap widens and,
## when a circuit's strip brings it down beside the Music button, short of the button.
func _fit_lane() -> void:
	if not is_instance_valid(_status):
		return
	var lane := GridBanner.LANE
	lane.position.y = lane_top(_status.get_global_rect().end.y)
	var left := maxf(lane.position.x, hud.ride_panel.get_global_rect().end.x + LANE_MUSIC_GAP)
	var right := lane.end.x
	var music := hud.music_button.get_global_rect().grow(LANE_MUSIC_GAP)
	if hud.music_button.visible and lane.intersects(music):
		right = music.position.x
	banner.set_lane(Rect2(left, lane.position.y, right - left, lane.size.y))


## The callout lane's top, a little under a status area ending at `status_bottom`.
func lane_top(status_bottom: float) -> float:
	return maxf(GridBanner.LANE.position.y, status_bottom + 4.0)


## The ride panel's gauge ticks at what meets demand (the repair in a storm), moved in steps; an
## easy role's band has the cap as its top, so the watts turn amber over it.
func _update_band() -> void:
	var at := snappedf(logic.target(), BAND_STEP)
	if at == _band_shown:
		return
	_band_shown = at
	if logic.is_easy():
		hud.metrics.set_power_band(at, logic.cap)
	else:
		hud.metrics.set_power_band(at)


func _update_status() -> void:
	_status.set_state(logic.supply / _scale, logic.target() / _scale, _state_name())
	var states := PackedInt32Array()
	for i in GridLogic.COUNT:
		states.append(_district_state(i))
	_status.set_districts(states)
	_update_note()


func _state_name() -> String:
	if not logic.pedalling and playing:
		return "pedal"
	if logic.storm == GridLogic.Storm.DOWN:
		return "repair"
	if logic.is_easy() and logic.over_cap():
		return "easy"
	return "powered" if logic.meeting or not playing else "short"


## Each district for the status widget (GridStatus.set_districts).
func _district_state(i: int) -> int:
	if i == logic.down_index:
		return 4
	if i >= logic.online:
		return 0
	if i >= logic.powered:
		return 3
	return 2 if i == logic.powered - 1 and logic.dim > 0.0 else 1


func _update_note() -> void:
	if logic.storm == GridLogic.Storm.WARNING:
		_status.set_note("STORM COMING", GameTheme.WARN)
	elif logic.storm == GridLogic.Storm.DOWN:
		_status.set_note("REPAIR: %d s TO GO" % ceili(GridLogic.STORM_REPAIR_SEC - logic.repair), GameTheme.TARGET)
	elif logic.is_easy() and logic.over_cap():
		_status.set_note("EASE OFF: NO NEED", GridStatus.CALM)
	elif logic.powered < logic.online or logic.dim > 0.0:
		_status.set_note("CATCH UP", GameTheme.WARN)
	elif logic.lit() >= GridLogic.COUNT:
		_status.set_note("WHOLE TOWN LIT", GameTheme.GOOD)
	elif logic.online < GridLogic.COUNT and not _falling():
		_status.set_note("NEXT: %s" % str(NAMES[logic.online]).to_upper(), GameTheme.TARGET)
	else:
		_status.set_note("ALL LIT", GameTheme.GOOD)


## Whether demand is on its way down (a cool-down, an evening's end).
func _falling() -> bool:
	return logic.u_at(logic.t + 2.0) < logic.u_at(logic.t) - 0.0001
