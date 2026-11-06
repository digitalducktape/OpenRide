extends Node
## The desktop's stand-in for Kotlin's hub visit (GameVisitManager, HubStateBuilder and
## SessionPlans; docs/GAMES.md "Running on a desktop"). A child of LocalSession, which forwards
## the hub's v1.1 calls here. It sends a `hub_state` built from `GameRegistry` and a desktop
## catalog, plays an accepted `start_plan` through LocalSession (with the visit's id, plan
## index and calibration), keeps the visit's results and bests in memory, and ends the visit on
## `exit_hub` (then starts a new one, as re-entering games would) or after IDLE_SAVE_SEC in the
## hub with no touch (`visit_ended` with `next: "hub"`; the next `hub_activity` starts a new
## visit).
##
## It plans only for simulation: Kotlin's SessionPlans stays the source of truth (FTP scaling
## and params are left out here).

const IDLE_SAVE_SEC := 20.0 * 60.0  ## the idle guard (rider decision: 20 min)
const RESTART_SEC := 1.5  ## after visit_ended(next: app), a new visit (the rider re-enters)
const MIN_SAVED_SEC := 60.0  ## a visit with less gameplay is discarded (v1's rule)
## As HubStateBuilder.MINUTE_STEPS.
const MINUTE_STEPS := [5, 10, 15, 20, 30, 45, 60]
## GameCatalog's roundSec, which GameInfo doesn't declare (60 when not listed).
const ROUND_SEC := {"dodge_ball": 90, "tug_of_war": 120, "safe_cracker": 75, "the_pull": 300, "balloon_pump": 125,
	"keepy_uppy": 60, "gate_crasher": 65}
## GameCatalog's usesCamera where it differs from the game's tracker mode (Tug of War's camera
## is an option, decided per segment).
const USES_CAMERA := {"tug_of_war": false}
## The display order of the first games (GameCatalog's, without the demo); every other
## registered game follows, by id (`order()`).
const ORDER := ["kart_race", "dodge_ball", "tug_of_war", "safe_cracker", "cadence_karaoke", "watt_lane", "the_pull",
	"balloon_pump", "keepy_uppy", "gate_crasher"]
## CircuitPresets: warm-up, N blocks, cool-down. Shapes only: each slot's game is drawn from its
## role's pool (`draw_slots`, as Kotlin's CircuitDraw).
const WARMUP := {"role": "warmup", "duration_sec": 180}
const COOLDOWN := {"role": "cooldown", "duration_sec": 180}
const BLOCK := [
	{"role": "work", "duration_sec": 60},
	{"role": "recovery", "duration_sec": 90},
	{"role": "work", "duration_sec": 90},
	{"role": "recovery", "duration_sec": 90},
]
const PRESETS := {"circuit-20": 2, "circuit-30": 4, "circuit-45": 6}
const INTRO_SEC := 10
const CUSTOM_MAX_SLOTS := 12
const CUSTOM_MAX_SEC := 90 * 60
const RIDER_NAME := "Ed"  ## LocalSession.RIDER_NAME

var visit_id := ""
var phase := ""  ## "" (no visit), hub, plan, saving, ended
var settings := {"camera_games": true, "game_music": true, "music_volume": 0.8, "sfx_volume": 1.0}
var permission := "granted"
var camera_failed := false
var calibrated := ""
var rider := {"id": 1, "name": RIDER_NAME, "avatar_png": null, "avatar_color": "#7A7CFF",
	"ftp_watts": 150, "ftp_is_default": true}
## This visit's finished plans: [{plan_id, difficulty, score, stars, game_ids}].
var plans: Array = []
var plan_index := 0
## Seeds this visit's circuit draws: plan n draws with circuit_seed + n (GameVisitManager's).
var circuit_seed := 0
var ride_sec := 0.0
var gameplay_sec := 0.0
## Bests kept for the process (the desktop's "DB"): key "plan_id|difficulty" → {score, stars}.
var plan_bests := {}
## key "game_id|plan_id|difficulty|variant" → {game_id, plan_id, difficulty, variant, score, stars, plays}.
var game_bests := {}
var idle_left := IDLE_SAVE_SEC
var visits_started := 0

var _local: Node
var _session: Node
var _restart_left := -1.0


func _init(local: Node, session: Node) -> void:
	_local = local
	_session = session
	name = "LocalHub"


func is_live() -> bool:
	return phase in ["hub", "plan"]


## A new visit: a new id, no results, no calibration; then the first hub_state.
func begin_visit() -> void:
	visits_started += 1
	visit_id = "v-local-%d" % visits_started
	phase = "hub"
	plans = []
	plan_index = 0
	circuit_seed = randi()
	ride_sec = 0.0
	gameplay_sec = 0.0
	calibrated = ""
	idle_left = IDLE_SAVE_SEC
	_restart_left = -1.0
	send_state()


func send_state() -> void:
	_session._on_hub_state(_wire(state()))


## The hub_state snapshot (spec §3.1).
func state() -> Dictionary:
	return {
		"hub_version": 1,
		"visit_id": visit_id,
		"phase": phase,
		"rider": rider.duplicate(),
		"settings": settings.duplicate(),
		"audio": audio(),
		"camera": {"permission": permission, "available": camera_available(), "calibrated": calibrated,
			"same_day_extremes": _local.has_extremes("lean_x")},
		"catalog": catalog(),
		"circuits": circuits(),
		"bests": {"games": game_bests.values(), "plans": _plan_best_rows()},
		"visit": {"recording": true, "ride_sec": int(ride_sec), "gameplay_sec": int(gameplay_sec),
			"plans": plans.duplicate(true)},
	}


## The settings for playing now (GameAudioPrefs.resolve).
func audio() -> Dictionary:
	return {"music": bool(settings.get("game_music", true)), "music_volume": settings.music_volume,
		"sfx_volume": settings.sfx_volume}


func camera_available() -> bool:
	return permission == "granted" and bool(settings.camera_games) and not camera_failed


## GameCatalog as HubStateBuilder sends it, from each game's GameInfo.
func catalog() -> Array:
	var out: Array = []
	for id in order():
		var info := GameRegistry.info(id)
		if info == null:
			continue
		out.append(entry(info))
	return out


## ORDER, then every other registered game but the demo, by id.
static func order() -> Array:
	var rest: Array = GameRegistry.ids().filter(func(id): return id != "demo" and id not in ORDER)
	rest.sort()
	return ORDER + rest


static func entry(info: GameInfo) -> Dictionary:
	var steps: Array = MINUTE_STEPS.filter(func(m): return m * 60 >= info.min_sec and m * 60 <= info.max_sec)
	if steps.is_empty():
		steps = [info.min_sec / 60]
	return {
		"id": info.id, "title": info.title, "supports": Array(info.supports), "min_sec": info.min_sec,
		"max_sec": info.max_sec, "min_rounds": info.min_rounds, "max_rounds": info.max_rounds,
		"round_sec": ROUND_SEC.get(info.id, 60), "roles": Array(info.roles),
		"uses_camera": USES_CAMERA.get(info.id, info.uses_camera()), "minute_steps": steps,
		"circuit_role": circuit_role(info.roles),
	}


## GameCatalog.circuitRole: work, else recovery, warm-up, cool-down, else free.
static func circuit_role(roles: Array) -> String:
	for role in ["work", "recovery", "warmup", "cooldown"]:
		if role in roles:
			return role
	return "free"


func circuits() -> Array:
	var out: Array = []
	for id in PRESETS:
		var slots := _preset_slots(id)
		var total := 0
		for slot in slots:
			total += int(slot.duration_sec) + INTRO_SEC
		out.append({"id": id, "minutes": int(id.get_slice("-", 1)), "total_sec": total, "slots": slots})
	return out


## The preset's lineup for the next plan (the hub shows the one that plays).
func _preset_slots(id: String) -> Array:
	var shape: Array = [WARMUP]
	for i in PRESETS[id]:
		shape.append_array(BLOCK)
	shape.append(COOLDOWN)
	return draw_slots(shape, catalog(), camera_available(), circuit_seed + plan_index)


## GameCatalog.circuitPool: the catalog entries of `role`, without camera games when off.
static func circuit_pool(entries: Array, role: String, camera: bool) -> Array:
	return entries.filter(func(e): return role in e.roles and (camera or not bool(e.uses_camera)))


static func _fits(e: Dictionary, sec: int) -> bool:
	return sec >= int(e.min_sec) and sec <= int(e.max_sec)


## Kotlin's CircuitDraw: each slot of `shape` ({role, duration_sec}) gets a game from its role's
## pool that fits its length, from a shuffled bag per role (no repeat in a role until every game
## that fits has played), preferring games that fit fewer of the role's lengths, and never the
## slot before's game when another fits; "demo" when nothing fits. Same seed, same lineup (the
## shuffle isn't Kotlin's, so the desktop's mix differs from the bike's for a seed).
static func draw_slots(shape: Array, entries: Array, camera: bool, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lengths := {}  # role → {sec: true}
	for slot in shape:
		var per_role: Dictionary = lengths.get_or_add(slot.role, {})
		per_role[int(slot.duration_sec)] = true
	var bags := {}  # role → Array of entries not yet played this pass
	var last_of_role := {}
	var previous := ""
	var out: Array = []
	for slot in shape:
		var role: String = slot.role
		var sec := int(slot.duration_sec)
		var pool := circuit_pool(entries, role, camera)
		var picked := "demo"
		if pool.any(func(e): return _fits(e, sec)):
			var bag: Array = bags.get_or_add(role, [])
			if not bag.any(func(e): return _fits(e, sec)):
				bag.clear()
				bag.append_array(_shuffled(pool, rng))
				for i in bag.size():
					if bag[i].id == last_of_role.get(role, ""):
						bag.append(bag.pop_at(i))
						break
			var role_lengths: Array = (lengths[role] as Dictionary).keys()
			var ranked := _ranked(bag, sec, role_lengths)
			# Not twice running wins over the bag's round (SessionPlans' CircuitDraw): when the only
			# game left is the one that played the slot before (a game in two pools), the role's
			# next round starts early, that game first in it.
			if ranked.all(func(r): return r[2].id == previous) and pool.any(func(e): return _fits(e, sec) and e.id != previous):
				bag.clear()
				bag.append_array(_shuffled(pool, rng))
				for i in bag.size():
					if bag[i].id == previous:
						bag.push_front(bag.pop_at(i))
						break
				ranked = _ranked(bag, sec, role_lengths)
			var pick: Dictionary = ranked[0][2]
			for r in ranked:
				if r[2].id != previous:
					pick = r[2]
					break
			bag.erase(pick)
			picked = pick.id
			last_of_role[role] = picked
		out.append({"game_id": picked, "role": role, "duration_sec": sec})
		previous = picked if picked != "demo" else ""
	return out


## The bag's games that fit `sec`, as [reach, bag index, entry], sorted by reach (how many of the
## role's lengths the game fits), the bag's order breaking ties.
static func _ranked(bag: Array, sec: int, role_lengths: Array) -> Array:
	var ranked: Array = []
	for i in bag.size():
		if _fits(bag[i], sec):
			ranked.append([role_lengths.filter(func(l): return _fits(bag[i], l)).size(), i, bag[i]])
	ranked.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return ranked


static func _shuffled(items: Array, rng: RandomNumberGenerator) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out


# --- The hub's calls ---

func start_plan(request: Dictionary) -> void:
	_touch()
	if phase != "hub":
		_reject(request, "busy")
		return
	var built := build_plan(request)
	if built.has("reason"):
		_reject(request, built.reason)
		return
	var plan: Dictionary = built.plan
	plan["visit_id"] = visit_id
	plan["plan_index"] = plan_index
	plan["calibrated"] = calibrated
	plan["audio"] = audio()
	plan["rider_id"] = rider.id
	plan["rider_name"] = rider.name
	plan_index += 1
	phase = "plan"
	_local.start(plan)


## {plan} or {reason}, as SessionPlans with PlanRequestMessage.toSessionRequest.
func build_plan(request: Dictionary) -> Dictionary:
	var difficulty := str(request.get("difficulty", "standard"))
	match str(request.get("kind", "")):
		"just_ride":
			return _just_ride(request, difficulty)
		"circuit":
			var id := str(request.get("preset_id", ""))
			if not PRESETS.has(id):
				return {"reason": "unknown_game"}
			var segments: Array = _preset_slots(id)
			return {"plan": {"kind": "circuit", "plan_id": id, "difficulty": difficulty,
				"total_sec": _total(segments), "segments": segments}}
		"custom":
			return _custom(request, difficulty)
	return {"reason": "unsupported_mode"}


func _just_ride(request: Dictionary, difficulty: String) -> Dictionary:
	var id := str(request.get("game_id", ""))
	if id not in order() or GameRegistry.info(id) == null:
		return {"reason": "unknown_game"}
	var e := entry(GameRegistry.info(id))
	if e.uses_camera and not camera_available():
		return {"reason": "camera_unavailable"}
	var mode := str(request.get("mode", "minutes"))
	if mode not in e.supports:
		return {"reason": "unsupported_mode"}
	var length := int(request.get("length", 0))
	var seg := {"game_id": id, "role": "free", "duration_sec": -1}
	var suffix := "open"
	match mode:
		"minutes":
			length = clampi(length, ceili(e.min_sec / 60.0), maxi(1, e.max_sec / 60))
			seg.duration_sec = length * 60
			suffix = "minutes:%d" % length
		"rounds":
			length = clampi(length, e.min_rounds, e.max_rounds)
			seg.duration_sec = length * int(e.round_sec)
			seg["end_mode"] = "game"
			seg["params"] = {"rounds": length}
			suffix = "rounds:%d" % length
	return {"plan": {"kind": "just_ride", "plan_id": "just-ride:%s:%s" % [id, suffix],
		"difficulty": difficulty, "total_sec": _total([seg]), "segments": [seg]}}


func _custom(request: Dictionary, difficulty: String) -> Dictionary:
	var slots: Array = request.get("slots", [])
	if slots.is_empty():
		return {"reason": "empty_circuit"}
	if slots.size() > CUSTOM_MAX_SLOTS:
		return {"reason": "too_long"}
	var segments: Array = []
	var parts: Array = []
	for i in slots.size():
		var id := str(slots[i].get("game_id", ""))
		var info := GameRegistry.info(id) if id in order() else null
		if info == null:
			return {"reason": "unknown_game"}
		var e := entry(info)
		var sec := clampi(int(roundf(int(slots[i].get("duration_sec", 0)) / 30.0)) * 30, e.min_sec, e.max_sec)
		var role: String = e.circuit_role
		if i == 0 and "warmup" in e.roles:
			role = "warmup"
		elif i == slots.size() - 1 and slots.size() > 1 and "cooldown" in e.roles:
			role = "cooldown"
		# Camera off: the first camera-free game of the same circuit role plays it (the id keeps
		# the requested game), as SessionPlans.customGame; none, or a free slot (Kart Race),
		# rejects it.
		var plays := id
		if e.uses_camera and not camera_available():
			plays = ""
			for other_id in (order() if e.circuit_role != "free" else []):
				var other := entry(GameRegistry.info(other_id))
				if not other.uses_camera and other.circuit_role == e.circuit_role:
					plays = other_id
					break
			if plays.is_empty():
				return {"reason": "camera_unavailable"}
		var seg := {"game_id": plays, "role": role, "duration_sec": sec}
		seg["end_mode"] = GameRegistry.info(plays).timed_end_mode
		segments.append(seg)
		parts.append("%s.%d" % [id, sec])
	var gameplay := 0
	for seg in segments:
		gameplay += int(seg.duration_sec)
	if gameplay > CUSTOM_MAX_SEC:
		return {"reason": "too_long"}
	return {"plan": {"kind": "circuit", "plan_id": "custom:" + ",".join(parts), "difficulty": difficulty,
		"total_sec": _total(segments), "segments": segments}}


static func _total(segments: Array) -> int:
	var total := 0
	for seg in segments:
		if int(seg.duration_sec) < 0:
			return -1
		total += int(seg.duration_sec) + INTRO_SEC
	return total


func update_setting(key: String, value: Variant) -> void:
	_touch()
	match key:
		"camera_games":
			settings.camera_games = bool(value)
		"game_music":
			settings.game_music = bool(value)
		"music_volume", "sfx_volume":
			settings[key] = clampf(float(value), 0.0, 1.0)
		_:
			push_warning("LocalHub: unknown setting '%s'" % key)
			return
	send_state()


## As TrackerLink.hubCalibrate: the camera on, a scripted calibration (centre only with
## "same-day" extremes unless `full`), the camera off at its end, then hub_state.
func hub_calibrate(mode: String, full: bool) -> void:
	_touch()
	if phase != "hub" or permission != "granted" or not bool(settings.camera_games):
		return
	_local.start_hub_calibration(mode, full)


func cancel_calibration() -> void:
	_touch()
	if _local.cancel_hub_calibration():
		send_state()


## LocalSession's hub calibration ended: the visit is calibrated (the camera works again).
func hub_calibration_ended(mode: String) -> void:
	if calibrated != "lean_2d":
		calibrated = mode
	camera_failed = false
	send_state()


## The desktop has no permission prompt: it grants at once.
func request_camera_permission() -> void:
	_touch()
	permission = "granted"
	send_state()


func exit_hub(next: String) -> void:
	if phase != "hub":
		return
	_end_visit("exit", next)
	_restart_left = RESTART_SEC


func hub_activity() -> void:
	if phase == "ended" and _restart_left < 0.0:
		begin_visit()  # after the idle save: a tap starts a new visit
		return
	_touch()


func _touch() -> void:
	idle_left = IDLE_SAVE_SEC


func _end_visit(reason: String, next: String) -> void:
	phase = "saving"
	var saved := gameplay_sec >= MIN_SAVED_SEC
	phase = "ended"
	_session._on_visit_ended(_wire({"visit_id": visit_id, "ride_id": 1 if saved else null, "saved": saved,
		"discarded_reason": "" if saved else "too_short", "next": next, "reason": reason}))


func _process(delta: float) -> void:
	if phase == "hub":
		idle_left -= delta
		if idle_left <= 0.0:
			_end_visit("idle", "hub")
	if _restart_left >= 0.0:
		_restart_left -= delta
		if _restart_left < 0.0:
			begin_visit()


# --- From LocalSession ---

## Adds the visit's keys to a plan's session_finished, and its bests against the process's
## earlier runs of the same plan id and difficulty.
func plan_finishing(plan: Dictionary, summary: Dictionary) -> Dictionary:
	var out := summary.duplicate(true)
	out["visit_id"] = plan.visit_id
	out["plan_index"] = plan.plan_index
	out["plan_id"] = plan.plan_id
	out["difficulty"] = plan.difficulty
	var key := "%s|%s" % [plan.plan_id, plan.difficulty]
	var score := int(summary.totals.score)
	var stars := int(summary.totals.stars)
	if plan_bests.has(key):
		var before: Dictionary = plan_bests[key]
		var bests := {"previous_score": before.score, "previous_stars": before.stars}
		if score > int(before.score):
			bests["score"] = true
		if stars > int(before.stars):
			bests["stars"] = true
		out["bests"] = bests
	return out


## The plan is over: its result joins the visit and the bests; back to the hub phase.
func plan_finished(plan: Dictionary, summary: Dictionary) -> void:
	var score := int(summary.totals.score)
	var stars := int(summary.totals.stars)
	var game_ids: Array = []
	for seg in plan.segments:
		game_ids.append(seg.game_id)
	plans.append({"plan_id": plan.plan_id, "difficulty": plan.difficulty, "score": score, "stars": stars,
		"game_ids": game_ids})
	var key := "%s|%s" % [plan.plan_id, plan.difficulty]
	var best: Dictionary = plan_bests.get(key, {"score": -1, "stars": -1})
	plan_bests[key] = {"score": maxi(score, int(best.score)), "stars": maxi(stars, int(best.stars))}
	for r in summary.results:
		if r.get("skipped", false):
			continue
		var gkey := "%s|%s|%s|%s" % [r.game_id, plan.plan_id, plan.difficulty, r.get("variant", "")]
		var row: Dictionary = game_bests.get(gkey, {"game_id": r.game_id, "plan_id": plan.plan_id,
			"difficulty": plan.difficulty, "variant": r.get("variant", ""), "score": 0, "stars": 0, "plays": 0})
		row.score = maxi(int(row.score), int(r.get("score", 0)))
		row.stars = maxi(int(row.stars), int(r.get("stars", 0)))
		row.plays = int(row.plays) + 1
		game_bests[gkey] = row
	var elapsed := float(summary.totals.get("elapsed_sec", 0))
	ride_sec += elapsed
	gameplay_sec += elapsed
	var held: String = _local.calibrated_mode()
	if not held.is_empty():
		calibrated = held
	if phase == "plan":
		phase = "hub"
	_touch()
	send_state()


func _plan_best_rows() -> Array:
	var out: Array = []
	for key in plan_bests:
		out.append({"plan_id": key.get_slice("|", 0), "difficulty": key.get_slice("|", 1),
			"score": plan_bests[key].score, "stars": plan_bests[key].stars})
	return out


func _reject(request: Dictionary, reason: String) -> void:
	_session._on_plan_rejected(_wire({"request": request, "reason": reason}))


func _wire(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))
