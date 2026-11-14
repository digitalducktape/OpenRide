class_name KartRaceInfo
extends RefCounted
## Kart Race's declarations for the framework and the Games hub (#43): its GameInfo (options,
## stars, tracker mode), the hub's kart and track cards, its look for the framework's screens, and
## the plan arithmetic the target text uses. Static: KartRace's `info`, `ui_theme`, `target_text`
## and its static helpers call in here.

const DEFAULT_FTP := 150.0
## The hub's card pictures (spec §7.2): the racers' baked portraits
## (tests/capture_kart_portraits.gd) and the tracks' thumbnails (tests/capture_track_thumbs.gd).
const PORTRAITS := "res://games/kart_race/ui/portraits/%s.png"
const THUMBS := "res://games/kart_race/ui/tracks/%s.png"

static var _look: GameTheme


static func info() -> GameInfo:
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


## The intro card's target for segment `seg`: the planned races, or open-ended.
static func target_text(seg: Dictionary) -> String:
	var duration := float(seg.get("duration_sec", -1))
	if duration < 0.0:
		return "Grand Prix · race as long as you like"
	var p: Dictionary = seg.get("params", {})
	var n := planned_races(duration, KartGrandPrix.estimate_lap_sec(KartTracks.average_length(), ftp_of(p)))
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


## The rider's FTP from the segment's params (DEFAULT_FTP when missing or zero).
static func ftp_of(p: Dictionary) -> float:
	var ftp := float(p.get("ftp_watts", DEFAULT_FTP))
	return ftp if ftp > 0.0 else DEFAULT_FTP
