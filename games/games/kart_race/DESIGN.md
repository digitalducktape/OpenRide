# Kart Race: the module contract

Kart Race (#43) is a Grand Prix of 3-lap races against seven bots. The rider pedals to drive,
leans in front of the camera to steer, and taps to use items. This file is the module's
contract: the Phase 1 skeleton's interfaces plus everything the Phase 2 agents (handling,
racers, race-systems, presentation) added, folded together in the Phase 3 integration. The
world agent's additions (tracks, `KartWorld`, `KartLook`, the world shaders) land with its merge.
**Change an interface below only with a matching change here** (and say so in your report).
Additions are fine; renames and removals are not.

Everything is original: the game, racers, items and tracks have our own names. Assets must be
original, procedural, CC0 or OFL, each listed in `games/assets/SOURCES.md` in the same commit.
Every new `class_name` starts with `Kart` (they share the project's global namespace).

## Layout and ownership

| Path | What | Phase 2 owner |
| --- | --- | --- |
| `KartRace.tscn`, `KartRace.gd` | The `Game`: lifecycle, the GP flow, the fixed step, wiring | shared: each agent edits only its own `_build_*` function plus a few lines of wiring |
| `logic/KartTrackModel.gd`, `KartTrackPoint.gd` | Track space | world |
| `logic/KartPhysics.gd`, `KartState.gd`, `KartInput.gd` | Handling | handling |
| `logic/KartRaceLogic.gd`, `KartRaceEvents.gd`, `KartGrandPrix.gd` | Race rules, events, the GP | frozen (changes go through the integrator) |
| `logic/KartBotDriver.gd`, `KartScoring.gd`, `KartItemLogic.gd` (new) | Bots, scoring, items | race-systems |
| `tracks/` | `KartTrackDef`, `KartTracks` (the cup), one script per track | world |
| `world/KartWorld.gd` (+ new builders, shaders) | The track's look | world |
| `world/KartView.gd` | One kart on screen | racers |
| `world/KartChaseCamera.gd` | The camera | handling |
| `world/KartItemViews.gd` (new), `world/KartFx.gd` (new) | Item views; effects | race-systems; presentation |
| `racers/KartRoster.gd` (+ models) | The eight racers | racers |
| `ui/` | `KartStatus`, `KartRaceBoard` (placeholders) and the rest of the HUD | presentation |
| `audio/` | Effects and music | presentation |

## Scene tree

```
KartRace (Node2D, KartRace.gd: extends Game)
├─ View3D (SubViewport, 0.62 × 1080p, no MSAA, UPDATE_ALWAYS)
│  └─ World (KartWorld: environment, sun, road, barriers, ground, trees)
│     ├─ ChaseCamera (KartChaseCamera, current)
│     ├─ Kart_<racer> × 8 (KartView: one skinned mesh + outline, shadow, anchors)
│     ├─ Items (KartItemViews: pods, pucks, drones, goo, shields, magnet beams, bursts)
│     ├─ Fx (KartFx: puffs, sparks and flames, hit stars: 3 MultiMeshes)
│     └─ Podium (KartPodium, only while the GP podium shows: plinth and three blocks)
├─ View3DImage (TextureRect: the viewport scaled to 1920×1080 under the HUD)
├─ KartHud (CanvasLayer 8: lap badge, clock, racer list, minimap, ride strip, item button
│           with the drift arc, place, countdown, banners, speed lines)
├─ KartRaceBoard (CanvasLayer 9: the results board and the podium)
└─ KartAudio (music stems, engine/screech/crowd loops, one-shots)
(the framework's Hud, CanvasLayer 10, in Kart Race's skin: clock and score, Recalibrate |
Pause | End at the top right; its ride panel is hidden for KartHud's ride strip)
```

The 3D view renders into the SubViewport at `RENDER_SCALE` (Dodge Ball's pattern; never set
`Viewport.scaling_3d_scale` below 1: it hung the tablet). The HUD stays sharp over it.

## Data flow

Logic never touches nodes; nodes only read logic and listen to `KartRaceEvents`.

```
InputBus ──► KartRace._read_rider() ─┐   (item button tap → use_item edge)
KartBotDriver.think() × 7 ───────────┴─► inputs[] ─► KartRaceLogic.step(1/30)
                                                         │  countdown: rocket start; GO: launch
                                                         │  drafts, KartPhysics.step() per kart
                                                         │  contacts, laps, places, finish
                                                         ▼  then KartItemLogic.step (same inputs)
                                              KartState × 8  +  KartRaceEvents signals
                                                         │             │
     KartView.sync / KartChaseCamera.follow ◄──┘       ├─► KartScoring ─► Game.award()
     KartItemViews.sync / KartFx.step ◄────────┤       │
     KartHud.update (HUD) ◄────────────────────┘       └─► KartRace (GP flow), HUD, audio, fx, camera
```

- **The fixed step.** `_on_frame(delta)` adds delta to an accumulator and runs `_tick(1/30)`
  while it holds a tick (at most `MAX_TICKS` = 4 a frame, 133 ms), then syncs the views once.
  The framework stops `_on_frame` while paused, so pausing freezes the race, the bots and the
  clocks.
- **Drawing between ticks.** The logic steps at 30 Hz (the tablet is bound by the main
  thread; the tracker's lean arrives at 30 Hz anyway) and the views draw every frame. Each
  tick starts with `KartState.snap()`; `_sync_views` fills one draw copy per kart with
  `draw_into(copy, alpha)` (alpha = the accumulator over the tick) and hands the copies to
  `KartView.sync`, the camera and `KartItemViews` (`draw_karts`, `alpha`; shots carry
  `prev_pos`). A kart moved more than 4 m in a tick is drawn where it is. Puck, goo and pod
  contacts are swept over the tick's movement (`KartItemLogic.passes_within`). Tests that
  need exactly one tick step `KartRace.TICK`.
- **Per race**, `_begin_race()` builds a fresh `KartRaceLogic` (with its own `events`),
  rebuilds the world only when the track or direction changes, and emits
  `race_began(race)`. **Hook a race's events in a `race_began` handler** connected from your
  builder; don't edit `_begin_race`.
- `sim_time` counts simulated seconds; `test_input` (a `KartInput`) replaces the rider's input
  in tests.
- **Per frame** (`_sync_views`): views, then the camera (or the fly-over before GO), then other
  karts within `CAMERA_CLEAR` (4.2 m) of the lens are hidden so none fills the screen (not
  while the camera is held), then item views, effects, audio and the HUD.

## Track space

- `s`: metres along the centre line from the start/finish line, in the driving direction,
  `0..length`, wrapping. `d`: metres across, horizontal, **+ = the driver's right**.
- The surface at (s, d) is the centre point + d × the horizontal right, raised by `d·tan(bank)`
  (+ banking = the right edge higher).
- Curvature: **+ turns left**. Lean: **+1 = right**. Yaw (`heading`, `yaw_at`): Godot's
  `rotation.y`, 0 faces −Z, + turns left; forward = `(-sin yaw, 0, -cos yaw)`.
- Surfaces across the road: ROAD up to the half-width, KERB for `KERB_WIDTH` (0.8 m) beyond,
  OFFROAD to `half_width + verge`, WALL beyond.
- Reversed mode drives the same loop backwards: the start line stays put, s runs the other
  way, d, curvature, grade, banking and zone `d` flip sign, and zone spans are mirrored.
- A def's zone `s0`/`s1` are metres from `points[0]` driving forward; the model re-bases them
  on the start line. A zone with `s1 < s0` wraps past the line. A zone with `dir` ("forward" or
  "reversed") holds in that direction only: every track has one climb per direction (a climb
  driven backwards is a descent).
- Every track is laid out with `KartTrackShape` (Meadow Ring too, since polish pass 3), a turtle of straights and arcs
  (exact radii), sampled every 4 m into control points. Climbs stay under about 6%: the bike
  model stalls weak riders on steeper ones.
- **Drift corners** (polish pass 3). Drifting is the skill: the charge runs at full rate in any
  corner tighter than 1/`DRIFT_CHARGE_K` (125 m), tiers at `TIER_SEC` 0.9 / 2.0 / 3.4 s. Every
  track, both ways round, has at least two corners tighter than 40 m and long enough for a
  tier-2 mini-turbo at 20 m/s (a strong rider; 0.3 s lost to the entry), and one long enough
  for tier 3, each with at least 50 m of straight after it to spend the boost
  (`kart_tracks_test`: `corners()`, `tier_for()`). Tightest radii: Meadow 23.5 m (the crest
  hairpin), Canyon 22.5 (the summit hairpin), Harbor 18.3 (the chicane), Frost 28.1.
- **Landmarks** (`KartTrackDef.landmarks`, `KartWorld.landmarks(type)`): Meadow's windmill and
  barn, Canyon's arches (one marked `hero`) and spire, Harbor's shore and lighthouse, Frost's
  lakes (the start tarn is `hero`). The dresser places its hero piece first
  (`KartDress.dress_hero`, setting `KartDress.hero`), then `KartWorld.solve_grid_shot()`
  searches camera spots round the grid for the title shot (`grid_shot`: the piece on a third,
  clear of the HUD's title band and top-right cluster, not hidden by land or the stand; no kart
  under the band or the lens inside one; as many whole karts as it can, big enough to read),
  and the scatter keeps out of its sight line (`KartDress.in_hero_sight`). `KartRace` hands it
  to the camera (`camera.shot`); `flyover` holds on it with a slow push in for
  `KartChaseCamera.SHOT_HOLD` of the fly-over while the title card reads, then swings onto the
  chase spot. Solved once per build (about 20 ms on the desktop).

## Interfaces (frozen)

```gdscript
class_name KartTrackDef extends Resource
@export var id: String
@export var title: String
@export var theme: String                   # "meadow" | "canyon" | "harbor" | "frost"
@export var points: PackedVector3Array      # closed loop control points, metres, y up
@export var half_widths: PackedFloat32Array # per control point (interpolated), road half-width
@export var banking: PackedFloat32Array     # per control point, radians, + = right edge higher
@export var verge: float = 4.0              # off-road band beyond the road before the wall
@export var zones: Array[Dictionary]        # {type: "climb"|"boost"|"items"|"start", s0, s1, d?, w?, dir?}
@export var start_s: float = 0.0

class_name KartTrackPoint extends RefCounted
var s: float; var d: float; var position: Vector3; var height: float
var tangent: Vector3; var right: Vector3; var normal: Vector3

class_name KartTrackModel extends RefCounted
enum Surface { ROAD, KERB, OFFROAD, WALL }
const KERB_WIDTH := 0.8
var length: float
var def: KartTrackDef; var reversed: bool; var verge: float
var zones: Array[Dictionary]                       # re-based on the start line (and mirrored)
var curve: Curve3D                                 # the centre line, for views (its offsets aren't s)
func _init(def: KartTrackDef, reversed := false) -> void
func sample(s: float) -> KartTrackPoint            # centre line at s (d = 0)
func position_at(s: float, d: float) -> Vector3
func project(pos: Vector3, hint_s := -1.0) -> KartTrackPoint  # windowed (±25 m) near hint_s when given
func half_width(s: float) -> float
func surface(s: float, d: float) -> int
func curvature(s: float) -> float                  # signed 1/m, + = turning left
func grade(s: float) -> float                      # dy/ds
func racing_line(s: float) -> float                # target d: inside of corners, smoothed, ≥ 1.5 m inside the edge
func yaw_at(s: float) -> float                     # the driving direction as a yaw
func banking(s: float) -> float
func zones_at(s: float) -> Array[Dictionary]
static func in_span(s: float, s0: float, s1: float) -> bool
func wrap(s: float) -> float
func delta(from_s: float, to_s: float) -> float    # signed shortest distance along the loop

class_name KartTracks extends RefCounted           # the cup
const CUP := ["meadow_ring", "canyon_dash", "harbor_lights", "frost_pass"]   # GP order
const SCRIPTS := {"meadow_ring": "res://games/kart_race/tracks/meadow_ring.gd", ...}
static func build(track_id: String) -> KartTrackDef   # each track script has `static func build() -> KartTrackDef`
static func length_of(track_id: String) -> float      # cached
static func average_length() -> float

class_name KartInput extends RefCounted
var power_w := 0.0; var cadence := 0.0; var lean := 0.0   # -1 left .. +1 right
var resistance := 0.0; var standing := false; var use_item := false  # use_item is an edge
var tracking := true      # false while the tracker has lost the face: no drift starts, full assist

class_name KartState extends RefCounted
var id: int; var racer_id: String; var weight := 1.0          # 0.85 light .. 1.15 heavy
var pos: Vector3; var heading := 0.0                          # yaw, radians
var speed := 0.0                                               # kart m/s (world)
var v_bike := 0.0                                              # virtual bike m/s
var s := 0.0; var d := 0.0; var lap := 0; var surface := 0
var normal := Vector3.UP                                       # road normal under the kart (views)
var steer := 0.0                                               # -1..1, + = right, for visuals
var drift_dir := 0; var drift_charge := 0.0; var drift_tier := 0; var knob_boosting := false
var boost_time := 0.0; var spin_time := 0.0; var shield_time := 0.0
var hop := 0.0                                                 # visual hop height
var item := ""; var roulette_time := 0.0
var finished := false; var finish_time := 0.0; var place := 0
var draft := 0.0                                               # 0..1 this tick
# Handling (physics-written; views may read):
var slide := 0.0          # the drift's body yaw, radians, + = nose left (a right drift: < 0)
var lean_smooth := 0.0    # the lean after the steering response lag
var drift_time := 0.0     # seconds into the drift (the hop is its start)
var boost_kind := ""      # the latest boost: "drift" | "pad" | "item" | "start"
var boost_tier := 0       # the latest drift boost's tier
var climbing := false; var standing_bonus := false; var on_pad := false
var rocket_hold := 0.0    # countdown seconds at cadence >= 70 in the "2" window
var drift_hold := 0.0; var drift_hold_dir := 0; var drift_release := 0.0
var drift_res0 := 0.0; var drift_cool := 0.0
func forward() -> Vector3

class_name KartPhysics extends RefCounted
const SPEED_SCALE := 2.4
const SPIN_SEC := 1.0; const KART_RADIUS := 0.95; const DEAD_ZONE := 0.06   # (and the tuning constants)
const DRIFT_LEAN := 0.65; const DRIFT_HOLD := 0.12; const RELEASE_LEAN := 0.3; const RELEASE_HOLD := 0.15
const DRIFT_WIDE_LEAN := 0.35; const DRIFT_WORTH_K := 1.0 / 70.0
const TIER_SEC := [0.9, 2.0, 3.4]; const TURBO_SEC := [0.5, 0.9, 1.4]   # spark tiers, mini-turbos
const ROCKET_CADENCE := 70.0; const ROCKET_WINDOW := Vector2(1.0, 2.0); const ROCKET_HOLD := 0.3
var assist := 1.0        # 0 off, 0.5 low, 1 high (curvature feed-forward and alignment share)
var drift_resistance := 40.0
var top_speed := 20.0    # m/s the drift thresholds are shares of (KartRace: reference_speed(ftp))
static func drive_power(power_w: float, cadence: float) -> float   # watts + spin_watts(cadence)
static func reference_speed(ftp_w: float) -> float   # kart m/s: 0.6 FTP at 85 rpm, flat
var events: KartRaceEvents = null                  # set by KartRaceLogic
static func steady_bike_speed(power_w: float, grade: float, draft := 0.0) -> float   # m/s
static func bike_resistance(v: float, grade: float, draft := 0.0, crr_mult := 1.0) -> float
static func shape_lean(lean: float) -> float
static func lean_for_steer(steer: float) -> float
static func max_yaw_rate(speed: float) -> float
func lean_for_yaw_rate(k: KartState, track: KartTrackModel, yaw_rate: float) -> float
func assist_yaw_rate(k: KartState, track: KartTrackModel) -> float
func step(k: KartState, inp: KartInput, track: KartTrackModel, dt: float) -> void
func countdown_step(k: KartState, inp: KartInput, countdown: float, dt: float) -> void  # rocket start
func launch(k: KartState) -> void                  # GO: emits boost_started(id, "start", 1) if earned
func apply_boost(k: KartState, seconds: float, push := BOOST_PUSH, kind := "item") -> void  # emits nothing
func apply_spinout(k: KartState) -> bool          # false when a shield absorbed it
func apply_pull(k: KartState, track: KartTrackModel, want_speed: float, accel: float, to_d: float,
		lateral: float, dt: float) -> void          # the magnet: speed up, slide across, full draft
static func resolve_contacts(karts: Array) -> Array   # [[a_id, b_id, strength], ...]
static func update_drafts(karts: Array) -> void       # once a tick, before the karts step
func wants_drift(k: KartState, track: KartTrackModel) -> int            # bots: the dir a corner is worth, or 0
func drift_curvature(k: KartState, track: KartTrackModel, lean: float) -> float   # the arc a lean gives
func lean_for_drift(k: KartState, track: KartTrackModel, curvature: float) -> float  # bots: hold an arc
# _update_drift(k, inp, track, dt) -> float: the drift (extra yaw rate, + = left); emits
# drift_started / drift_tier / boost_started("drift", tier) through `events`.

class_name KartRaceEvents extends RefCounted      # see "Signal map"

class_name KartRaceLogic extends RefCounted
enum Phase { GRID, COUNTDOWN, RACING, FINISHED }
const RIDER := 0
var events := KartRaceEvents.new(); var physics := KartPhysics.new()
var track: KartTrackModel; var karts: Array = []     # Array[KartState]; index == id; 0 is the rider
var laps := 3; var phase := Phase.GRID; var time := 0.0; var countdown := 0.0
func setup(track: KartTrackModel, racers: Array, laps: int) -> void   # racers: [{racer_id, weight, grid?}]
func start_countdown(seconds := 3.0) -> void
func step(dt: float, inputs: Array) -> void          # inputs: Array[KartInput], one per kart
func order() -> Array                               # kart ids by race position
func place_of(kart_id: int) -> int                   # 1-based
func progress(kart_id: int) -> float                 # lap * length + s
func race_length() -> float

class_name KartGrandPrix extends RefCounted
const POINTS := [15, 12, 10, 8, 6, 4, 2, 1]
const RACE_OVERHEAD_SEC := 25.0
var results: Array                                    # each race's order
func _init(duration_sec: float, track_ids: Array, racer_count := 8) -> void   # -1 = open-ended
static func estimate_lap_sec(track_length: float, ftp_w: float) -> float     # at reference_speed
func next_race(time_left_sec: float, est_lap_sec: float) -> Dictionary       # {track_id, reversed, laps, is_final, index}
func record(order: Array) -> void
func races_run() -> int
func standings() -> Array                            # [{kart_id, points, wins, best_place_last}] sorted
func champion() -> int
func place_of(kart_id: int) -> int

class_name KartView extends Node3D
const ANCHORS := ["exhaust_l","exhaust_r","wheel_fl","wheel_fr","wheel_rl","wheel_rr","driver_head","item_hold","shadow"]
var slide := 0.0                                     # copied from KartState.slide in sync
var boost_glow := 0.0                                # 0-1, set by KartFx
var look_target := Vector3.ZERO; var look_weight := 0.0   # a glance (items, bots), weight 0-1
func setup(racer: Dictionary) -> void                # a KartRoster entry
func sync(k: KartState, dt: float) -> void           # pose: spin, slide, roll, pitch, hop, cheer
func anchor(name: String) -> Node3D
func bone_pose(bone: String) -> Transform3D          # KartModels.BONES, for tests and effects
static func model_mesh(racer: Dictionary) -> ArrayMesh; static func head_mesh(racer: Dictionary) -> ArrayMesh
# Models: racers/KartModels (one mesh a kart, rigged in the vertex shader: rig.gdshaderinc).

class_name KartPortraits extends RefCounted       # a racer's head rendered once (UPDATE_ONCE)
static func texture(parent: Node, racer: Dictionary, size := 160) -> ViewportTexture
static func framing(mesh: Mesh) -> Dictionary      # {eye, at, fov}: the face centred, ears in

class_name KartBotDriver extends RefCounted
const PERSONAS := [...]   # seven: {line_offset, drift_skill, item_skill, aggression, cadence, rocket}
enum Mode { CRUISE, PASS, DODGE }
var items: KartItemLogic = null                      # set by KartRace's _build_items per race
var mode; var drifting: int; var lane: float         # readable state (tests, debugging)
var cadence: float; var rocket: bool                 # its own cadence (rpm); manages the rocket start
func _init(profile: Dictionary, ftp_w: float, rng_seed: int) -> void   # {power_pct, line_offset, drift_skill, item_skill, aggression, cadence?, rocket?}
static func profile_for(index: int, pct: float) -> Dictionary          # PERSONAS[index] at pct of FTP
func power_at(t: float) -> float
func think(k: KartState, race: KartRaceLogic, dt: float) -> KartInput  # may return the same instance each call

class_name KartScoring extends RefCounted
signal awarded(points: float, reason: String)        # KartRace passes it to Game.award()
const STAR_THRESHOLDS := {"easy": [110, 195, 330], "standard": [120, 205, 330], "hard": [130, 215, 350]}  # points/min
var rider_id := 0
func begin_race(race: KartRaceLogic) -> void
func step(dt: float, power_w: float) -> void
func stats(gp: KartGrandPrix) -> Dictionary          # the result's stats (below)

class_name KartRoster extends RefCounted
const RACERS := [{id, name, species, color, accent, weight}, ...]   # eight, kart id order = lineup()
static func ids() -> Array; static func names() -> Array
static func racer(racer_id: String) -> Dictionary
static func lineup(rider_racer_id: String, count := 8) -> Array      # the rider's pick first
# Entries also carry suit, eyes, helmet?, kart ("light"|"medium"|"heavy"), number, horn
# ({hz, ratio, beeps, wave}), tagline.
static func option_labels() -> Array; static func kart_class(r: Dictionary) -> String
static func horn_preset(racer_id: String) -> SfxPreset   # KartSfx registers it as "horn_<id>"

class_name KartWorld extends Node3D
var tuning := {}                                     # dev switches: road, walls, ground, scenery
func build(track: KartTrackModel) -> void            # (re)build for a track or direction

class_name KartChaseCamera extends Camera3D
var mode := "chase"                                  # "chase" | "close" (the Camera option)
var hold := false; var held := Transform3D.IDENTITY   # pin the camera (screenshots, cut-scenes)
var kart_id := 0
func watch(events: KartRaceEvents, id := 0) -> void  # boosts kick, bumps and hits shake (per race)
func snap(k: KartState) -> void
func follow(k: KartState, dt: float) -> void         # yaw/distance/height springs, FOV with speed, drift roll
func flyover(k: KartState, t: float, track: KartTrackModel) -> void   # t 0..1 before GO, ends on the chase spot
func kick(amount := 1.0) -> void; func shake(amount: float) -> void; func trauma() -> float

class_name KartItemLogic extends RefCounted        # one per race, stepped right after the race
signal pod_broken(pod_index: int, kart_id: int)
const ITEMS := ["turbo", "puck", "drone", "goo", "shield", "magnet"]   # ids (HUD icons match them)
const NAMES := {...}; const ODDS := {...}            # display names; odds by position bucket
var race: KartRaceLogic; var rider_id := 0; var auto_rider := false   # the Auto items option
var pods: Array[Pod]; var shots: Array[Shot]; var goos: Array[Goo]    # inner classes, for the views
var magnet_time: PackedFloat32Array; var magnet_target: PackedInt32Array
func _init(race: KartRaceLogic, rng_seed := 0) -> void   # pod rows from the track's "items" zones
static func odds(place: int, racers: int) -> Dictionary; static func roll(place, racers, rng) -> String
func add_pod(s: float, d: float) -> Pod
func step(dt: float, inputs: Array) -> void          # roulette, use on the use_item edge, pickups, shots, goo, magnets
func give(kart_id: int, item: String) -> void; func use(kart_id: int) -> bool
func hit(k: KartState, by_id: int, item: String) -> void   # spin-out or shield_blocked
func wants_use(kart_id: int, skill: float) -> bool   # the policy (bots, Auto items)
func dodge_d(s, d, ahead) -> float; func pod_d(s, d, ahead) -> float; func threatened(id) -> bool  # for bots
func live_shots() -> int; func live_goos() -> int

class_name KartItemViews extends Node3D            # draws KartItemLogic's state; no logic
func bind(logic: KartItemLogic, race: KartRaceLogic) -> void
func sync(dt: float) -> void

class_name KartFx extends Node3D                   # effects; only reads KartState and events
var views: Array; var camera: KartChaseCamera
func begin(kart_views: Array) -> void; func listen(events: KartRaceEvents) -> void
func step(race: KartRaceLogic, dt: float) -> void   # sparks from drift_dir/drift_tier, flames from boosts
func boost(id: int, seconds := BOOST_SEC, color := FLAME) -> void
func draft_screen(race, cam, hud) -> float           # the draft streaks' strength and screen point

class_name KartStatus extends PanelContainer         # placeholder HUD widget
func set_state(place: int, racers: int, lap: int, laps: int, race_text: String) -> void
static func ordinal(n: int) -> String

class_name KartRaceBoard extends CanvasLayer         # placeholder boards
func show_board(title: String, rows: Array) -> void  # rows: [{name, detail}]
func hide_board() -> void
```

`KartRace.gd` (the `Game`): `signal race_began(race)`, `enum Flow { IDLE, COUNTDOWN, RACING,
RESULTS, PODIUM, DONE }`, and the members `race`, `gp`, `scoring`, `track`, `world`, `camera`,
`views`, `bots`, `items`, `lineup`, `flow`, `current`, `ftp_w`, `sim_time`, `test_input`. Builders:
`_build_world()`, `_build_camera()`, `_build_racers()`, `_build_items()`, `_build_hud()`,
`_build_audio()`, `_build_fx()`.

## Signal map

All on the race's `KartRaceEvents` (`race.events`). Kart ids index `race.karts`; places are
1-based.

| Signal | Emitted by | Listened to by (now / Phase 2) |
| --- | --- | --- |
| `race_started()` | KartRaceLogic, when the countdown ends | KartRace (flow → RACING, "GO!"), audio |
| `lap_completed(kart_id, lap, lap_time)` | KartRaceLogic, the first time a kart completes `lap` | KartScoring (+30, best lap), HUD lap banner, audio |
| `final_lap(kart_id)` | KartRaceLogic, when a kart starts its last lap | KartRace (banner), audio (fanfare, final-lap music) |
| `kart_finished(kart_id, place, time)` | KartRaceLogic (karts still running when the rider finishes get projected times) | audio (cheer, the rider's horn) |
| `race_finished(order)` | KartRaceLogic, once, when the rider finishes | KartRace (GP record, results board), KartScoring (points × 20) |
| `position_changed(kart_id, old, new)` | KartRaceLogic, once per change of place | KartScoring (overtakes) |
| `drift_started(kart_id, dir)` | KartPhysics | (tests; bots read `drift_dir`) |
| `drift_tier(kart_id, tier)` | KartPhysics | KartFx (tier bursts), audio (tier pings) |
| `boost_started(kart_id, kind, tier)` | KartPhysics (`drift`, `pad`, `start`); KartItemLogic (`item`, once per Turbo Can) | KartScoring (boosts; mini-turbos +10/20/35), KartFx (flames, tier colour), camera (kick), audio |
| `item_picked(kart_id, item)` | KartItemLogic, when the item lands (after the rider's roulette) | audio |
| `item_used(kart_id, item)` | KartItemLogic | audio |
| `kart_hit(kart_id, by_id, item)` | KartItemLogic | KartScoring (+25 when by the rider), KartFx (stars), camera (shake), audio |
| `shield_blocked(kart_id)` | KartItemLogic | KartFx, audio |
| `wall_bump(kart_id, strength)` | KartPhysics, on hitting the barrier (not while grinding along it) | camera shake, KartFx, audio |
| `kart_bump(a_id, b_id, strength)` | KartRaceLogic, from `resolve_contacts` | camera shake, KartFx, audio |

`KartItemLogic.pod_broken(pod_index, kart_id)` (on the item logic, not the race's events) fires
when a kart breaks a pod: KartItemViews bursts it.

## The race and the Grand Prix

- **Grid**: staggered slots, alternately left and right of the centre (±2.5 m), 6 m behind the
  line then 4.5 m apart. By default the bots fill it in id order (kart 1 on pole, the
  strongest) and the rider starts last.
- **Countdown**: the karts stay put; `KartPhysics.countdown_step` reads each input's cadence for
  the rocket start, and `launch` boosts the karts that earned it at GO. **Laps**: `lap`
  counts start-line crossings (0 on the grid, 1 on lap 1, laps + 1 at the finish), down on a
  backward wrap, so `progress = lap × length + s` is continuous. Lap events fire only for a lap
  never reached before.
- **Finish**: the race ends when the rider finishes; karts still running are placed by
  progress. Karts drive on through the results board.
- **The pick** (Games hub plan phase C, rider request 2026-10-20: "after calibration it takes
  you to the get ready screen then drops you in the course selection"): the kart and the
  starting track are chosen in the Games hub before Start, not in the game. They are the
  `driver` and `track` options with `where: hub` and `kind: cards` (docs/GAMES.md "Game
  options"): eight kart cards (the baked portrait, name, class, the kart's colour on the edge;
  the chosen one wears the rider's name) and four track cards (the baked thumbnail, masked to
  the card's rounded outline, title and lap length). Gameplay goes loading → calibration → the
  intro card's "Get ready" → the title fly-over → 3-2-1-GO. `_on_prepare` builds the chosen
  track once, behind the intro card; nothing else is ever built first, so there's no loading
  card or rebuild. The flow has no `PICK` or `LOADING` state.
  - The portraits are each racer's head (`KartPortraits`, as the HUD renders it) over the round
    backdrop in the kart's colour with a white ring, baked by `tests/capture_kart_portraits.gd`
    (windowed) into `ui/portraits/<racer>.png` (256 px, transparent outside the disc): rerun it
    when a racer's look changes. The hub never loads Kart Race's 3D.
  - The track thumbnails are each track's title shot, rendered by the game
    (`tests/capture_track_thumbs.gd`, windowed) into `ui/tracks/<id>.png`: rerun it when a
    track's look changes.
  - Rejected: keeping an in-game picker. It ran on the session clock (hence its 20 s
    auto-start), sat between the intro card and the race, and could make the game build a second
    track; the hub runs on no clock and knows the track before the world is built.
- **GP**: `next_race(time_left, est_lap)` before each race. The cup starts at the picked track
  (`KartGrandPrix.cup_from`), the others following in cup order. Timed: the final race is the one
  that starts with under 1.6 × (3 laps + 25 s) left, with `clamp(round(time_left / est_lap), 1,
  5)` laps. Open-ended: 3-lap races until the rider ends. The cup goes in order, reversed the
  second time round (a one-track cup alternates). The estimate uses the cup's average length at
  `KartPhysics.reference_speed` (0.6 × FTP at 85 rpm) on the flat.
- **`request_finish`** (Kotlin's 1.5× hard stop, or End): the race in progress counts as it
  stands, and the game ends at once.

## Handling (KartPhysics)

- **Drive power** (rider feedback 2026-10-19: "100 RPM barely moved the kart"; the bike read
  16-20 W at 93-105 rpm and 0-8% resistance, a crawl, while the bots rode at 68-113 W). The
  rider chose cadence plus resistance: the bike is driven by `drive_power(watts, cadence) =
  watts + spin_watts(cadence)`, where `spin_watts` is 0 below 30 rpm, rises linearly to 80 W at
  100 rpm and stops at 92 W (115 rpm). Spinning alone cruises; resistance adds on top through the
  watts; both are monotonic; no pedalling is 0 W and coasts to a stop. The bots feed the same
  model (their watts and their own cadence, 74-96 rpm), the bike's inertia smooths the sensors'
  jitter, and `KartScoring`'s `avg_power` and `Effort` still use the measured watts.
  `reference_speed(ftp)` (0.6 FTP at 85 rpm on the flat) sets `top_speed` (the drift
  thresholds; speed lines from 1.15×) and the GP's lap estimate. The fields were retuned so an
  ordinary ride (80-90 rpm at 30-40%, 100-150 W) sits mid-pack at the default 150 W FTP: easy
  0.40→0.85, standard 0.50→1.00, hard 0.60→1.15 of FTP. Steady speeds on the flat, standard
  field at a 150 W FTP (69-85 km/h), a Peloton-like watts curve (100 rpm at 5% ≈ 19 W, the
  ride's reading):

  | rpm \ resistance | 0% | 20% | 40% | 60% |
  | --- | --- | --- | --- | --- |
  | 60 | 43 km/h, 8th (was 18) | 52, 8th (36) | 69, 7th (61) | 87, 1st (82) |
  | 80 | 53, 8th (22) | 62, 8th (42) | 79, 3rd (69) | 98, 1st (92) |
  | 100 | 61, 8th (25) | 69, 7th (47) | 87, 1st (75) | 107, 1st (99) |

  Places are steady-state only: drafting, items (which favour the back) and mini-turbos keep a
  spinning rider in the pack. A 5-minute ride stays one race (`FINAL_FACTOR` 1.5 → 1.6 for the
  quicker laps).
- **The bike → the kart**: the drive power drives a virtual bike (85 kg, Crr 0.005, CdA 0.32, half the
  road's grade, light inertia, a coast brake; on a climb the climbing force is capped at what the
  watts push at `CLIMB_CRAWL` (2.5 m/s), so a 60 W rider crawls up 7% instead of stalling).
  The kart's target speed is the bike's × `SPEED_SCALE`, times surface (off-road 55%), boost
  (×1.35) and drift (×0.97) shares.
- **Steering**: lean → dead zone and curve → yaw rate; the assist adds the road's curvature, a
  pull parallel to it and an edge guard. With the face lost (`tracking` false) the assist is
  full and no drift starts.
- **Drift**: |lean| ≥ 0.65 held 0.12 s at ≥ 40% of `top_speed` hops into a slide; leaning in
  tightens the arc. The charge runs at full rate in a corner (× 1.6 with the knob up: the
  resistance at `drift_resistance` or risen 5 since the drift began), a quarter on a straight.
  Tiers at `TIER_SEC`; easing below 0.3 for 0.15 s releases a mini-turbo (`TURBO_SEC` by tier).
  The views read `slide`, `hop`, `drift_dir`, `drift_tier`; the HUD's drift arc (on the item
  button) reads the charge and `knob_boosting`.
- **Boosts**: mini-turbo, pad (the track's `boost` zones, once a visit), rocket start (cadence ≥
  70 for 0.3 s while "2" shows), the Turbo Can (`apply_boost` + the items' event). **Climbs**:
  standing on a `climb` zone cuts the drag 20%. **Drafting**: CdA −30% 1.5-8 m behind a kart.
- **Contacts**: circles of `KART_RADIUS`, the lighter kart pushed further, velocities traded.

## Bots (KartBotDriver)

- **Power**: their share of the rider's FTP (`bot_pcts`), wandering ±4% over minutes; never
  rubber-banded. **Cadence**: each persona's own (74-96 rpm), wandering ±4 rpm; only the
  `rocket` personas (three of seven) spin up for the rocket start.
- **Line**: pure pursuit of a lane ahead on the racing line plus the persona's offset (faded in
  sharp corners), the lane moving at a capped rate. An enum FSM picks the lane: DODGE (goo or a
  puck ahead) → PASS (a slower kart in its lane: a side, held) → CRUISE (its line, drawn to pods
  when it holds no item); side-by-side karts push the lane apart.
- **Drift**, deliberate only: outside a drift the lean stays under 0.6 (below the physics'
  entry). Where `wants_drift` says the corner is worth it and its drift skill says yes, it
  pulses a 0.8 lean until the physics starts the drift (giving up after 0.35 s); then
  `lean_for_drift` holds the arc pure pursuit wants, and it releases on the corner's exit, near
  the inside edge, or (with a tier) when even `drift_curvature`'s widest arc is too tight.
- **Items**: `KartItemLogic.wants_use(id, item_skill)`; hazards and pods from the same logic.

## Items (KartItemLogic, KartItemViews)

- Pod rows sit on the track's `items` zones; a pod respawns in 3 s. A bot's item lands at once;
  the rider's after a 0.9 s roulette (the button spins through the icons, then lands).
- The rider fires on the `use_item` edge (the item button, 260 px, bottom right; a tap during the
  roulette does nothing), or through the bots' policy with Auto items on.
- Odds by position (the back gets more turbo, drone and magnet). Effects go only through
  `KartPhysics` (`apply_boost`, `apply_spinout`, `apply_pull`) and out through the race's events.

| Item id | Name | Effect |
| --- | --- | --- |
| `turbo` | Turbo Can | a 1.2 s boost; one `boost_started(id, "item", 0)` |
| `puck` | Bumper Puck | fired forward, bounces off walls 3 times, spins out the first kart it hits |
| `drone` | Seeker Drone | flies to the kart one place ahead and spins it out |
| `goo` | Goo Puddle | dropped behind; the first kart through spins out |
| `shield` | Shield Bubble | 8 s, absorbs one hit (`shield_blocked`) |
| `magnet` | Draft Magnet | 3 s pull toward the kart ahead (`apply_pull`: up to its speed + 4 m/s, onto its line) |

## Scoring (KartScoring)

- Live awards through `award()` (the effort multiplier applies): an overtake +15 (only a place
  better than any reached this race), a mini-turbo +10/20/35 by tier (at most one per 4 s), an
  item hit +25, a lap +30; at each finish the race's points × 20.
- **Stars per minute**, tuned in simulation with the merged physics, bots and items (a
  bot-driven rider against each field, one 3-lap race and the 14.5 s around it, 3 seeds a
  point; points a minute at 1.0×). Re-validated in polish pass 3 (2026-10-16) over the whole
  cup, after every track gained corners that pay tier-2 and tier-3 mini-turbos: the cup's
  average barely moved (standard mid-pack 141 → 138, a win 240 → 237), but Meadow Ring, the old
  calibration track, rose from 114 to 141, and the cup had always sat above the old
  Meadow-only thresholds (Harbor's mid-pack took two stars). The thresholds rose to match.
  Re-validated again on 2026-10-19 for the drive power and the retuned fields (the whole cup,
  4 tracks × 2 seeds, a 150 W FTP): every place now earns about 1.3× the points a minute (the
  laps are quicker), and the thresholds rose with it:

| difficulty | thresholds (1, 2, 3 stars) | mid-pack | podium | winning at 1.0× |
| --- | --- | --- | --- | --- |
| easy | 110, 195, 330 | 0.60 FTP, 4th-5th: 160-199 | 0.75, 3rd: 199-235 | 1.15: 247-294 |
| standard | 120, 205, 330 | 0.75, 3rd-5th: 155-208 | 0.90, 3rd: 208-230 | 1.15, 1st-2nd: 236-300 |
| hard | 130, 215, 350 | 0.75, 4th-5th: 172-199 | 1.15, 2nd-3rd: 214-270 | - |

  Before the drive power (2026-10-16):

| difficulty | thresholds (1, 2, 3 stars) | mid-pack (0.6 FTP) | podium (0.75 FTP, 1st-2nd) | winning at 1.0× (0.95 FTP) |
| --- | --- | --- | --- | --- |
| easy | 80, 140, 275 | places 2nd: Meadow 163-175, Harbor 192-214 | - | Meadow 226-253, Harbor 248-271 |
| standard | 90, 155, 270 | 4th-5th: Meadow 138-147, cup 110-196 (mean 138) | Meadow 179-181, cup 177-218 | Meadow 224-257, cup 200-277 |
| hard | 100, 165, 300 | 5th-7th: Meadow 104-121, Harbor 169-182 | - | Meadow 205-246, Harbor 255-282 |

  A mid-pack ride earns one star and a podium two; three take podiums plus effort (up to 1.5×):
  a win at 1.0× stays under the third star unless the rider is far above the field. The tracks
  still differ (Harbor's short, technical lap pays most a minute). Provisional until the bike.

## Kotlin, options and the result

- `GameCatalog.KART_RACE` mirrors `info()`: `minutes` and `open`, 300-3600 s, no roles, camera
  on, effort in Just Rides, `timedEndMode = GAME` (`GameInfo.timed_end_mode = "game"`).
- `params`: `ftp_watts` (default 150), `bot_pcts` (seven ascending FTP shares: easy
  0.40→0.85, standard 0.50→1.00, hard 0.60→1.15 since the drive power; the bots' power wanders
  ±4% over time),
  `drift_resistance` (35 / 40 / 45).
- **Tracker mode `lean_stand`.** The head tracker reports `standing` in every camera mode
  (`HeadTrackingEngine` runs `StandingDetector` whatever the mode; 0.5 s to stand, 1.5 s to sit),
  so `InputBus.standing` works here; the simulator toggles it with Space. Calibration is the
  `lean_x` one.
- Options (`GameOptions`, per rider): `driver` (the roster) and `track` (the starting track),
  both picture cards in the hub only; `assist` (off / low / high, default high), `camera`
  (chase / close) and `auto_items` (off / on: `KartItemLogic.auto_rider`), segmented, under the
  hub's "More options" and on the pause screen. The rider's kart carries their profile
  name (`session_started`'s optional `rider_name`, `KartRoster.rider_label`).
- Result `stats`: `position` (GP standing), `races`, `wins`, `podiums`, `best_lap` (s),
  `race_time` (s), `boosts`, `items_hit`, `avg_power` (W), `ghost_trace` (the rider's distance
  in metres every `ghost_interval` s, at most 3,600 points), plus the framework's
  `effort_avg` and `played_sec`. `won` is true when the rider is the GP champion.

## Tablet budget

- 3D in the SubViewport at 0.62; no MSAA. Road and terrain unshaded (hand-made light and fog);
  scenery lit per vertex, repeats through MultiMesh; blob shadows; at most 120 draw calls,
  ~250k triangles, ~3k triangles and 1-2 materials per kart and driver.
- The skeleton draws about 4 calls for the world and 5 per kart (8 karts: ~45 in 3D).
- Allocate nothing per tick in the hot path: `KartTrackModel` queries use scratch fields
  (`_locate`), bots return a reused `KartInput`, the input list is reused.
- HUD labels change only when their value changes.
- `DEV_TUNING` in `KartRace.gd` (off in every build): reads `user://kart_tuning.cfg`
  (`[render] scale=0.62 msaa=0`, `[world] road=false walls=false ground=false scenery=false`)
  and logs `OPENRIDE_GAMES kart_race perf game_ms=… process_ms=… fps=… draw_calls=… objects=…
  primitives=… karts=…` every 5 s.

### Measured on the tablet (Phase 1 skeleton)

2026-10-13, mock build (`installDebug`), a 20-minute standard Just Ride of Meadow Ring, 8 box
karts, `DEV_TUNING` on, 20 perf lines (100 s) of racing. **The camera was off**: nobody was on
the bike, so calibration found no face twice and ended unavailable (tracker 0). Re-measure with
a rider and the camera tracking.

| fps | game_ms (the whole `_on_frame`) | process_ms (frame time) | draw calls (3D + HUD) | primitives |
| --- | --- | --- | --- | --- |
| 59-61, avg 60.4 | 1.2-2.5, avg 2.1 | 16.1-18.5 (one 40 at the start) | 58-88, avg 74 | ~17.9k |

`game_ms` covers the fixed step (8 karts with bots: ~0.12 ms a tick on the Mac), the view sync
and the HUD. Keep the hot path allocation-free, and watch it as Phase 2 adds drift, items and
smarter bots.

### Desktop draw calls after the Phase 2 merge (2026-10-14, before the world merge)

The tablet ran Meadow at about 51 fps with about 200 draw calls, the kart HUD about 75 of them.
The HUD now bakes its slow widgets (`KartBaked`, below) and draws the speed lines in one call.
`tests/measure_kart_hud.gd` (KartHud alone, a race of bots, the order changing, an item held,
speed lines on; the mean over 300 frames, bake renders included): **74.0 → 15.4** draw calls.
From the captures, racing with both HUDs is about 94 on the desktop (3D about 57, the framework
HUD about 15). The results board was about 185 on screen.

The boards now bake too: the title, subtitle, pill, every row and every podium block are
`KartBaked` (tweens move the baked rects). `tests/measure_kart_board.gd` (the board alone,
eight rows, confetti raining; the mean over 300 frames): results **122 → 13**, podium
**102 → 16** draw calls. In the game (`capture_kart_hud.gd`, the whole frame with the race
behind): results 171 → 76, podium 145 → 60.

## Tests

- `tests/unit/` (GdUnit4): `kart_track_model_test`, `kart_physics_test`, `kart_handling_test`,
  `kart_chase_camera_test`, `kart_race_logic_test`, `kart_grand_prix_test`, `kart_race_scene_test`,
  `kart_bot_driver_test`, `kart_item_logic_test`, `kart_item_views_test`, `kart_scoring_test`,
  `kart_racers_test`, `kart_presentation_test`, `kart_tracks_test`, `kart_world_test`; the hub's
  `hub_options_test` covers the kart and track cards. Shared tracks:
  `preload("res://tests/kart_fixtures.gd")` (circle, oval, meadow).
- `tests/sim_kart_check.gd`: a 5-minute local GP at 4× with the keys; must end on the finish
  line and show the summary (`PASS sim kart`). The keys steer on the kart's position half a
  second ahead (its heading against the road's): steering on where it is held a full lean
  until the line, which started tight drifts that ran 2-3 m into the inside verge. The capture
  scripts drive the same way.
- Windowed screenshots: `tests/capture_kart.gd` (per track, forward and reversed;
  `--compose` for the hero shots; `--play=SECONDS` for a recording), `capture_kart_hud.gd` (the
  HUD and flow screens), `capture_kart_items.gd` (each item), `capture_racers.gd` (the roster),
  `capture_world.gd` (every track: the grid, chase shots, drone views),
  `measure_kart_hud.gd` and `measure_kart_board.gd` (the kart HUD's and the boards' draw calls).
  Drifts in the captures are real ones (an arrow key held into a corner).
- Run the full unit suite, `sim_demo_check` and `sim_kart_check` before every commit.

## GDScript gotchas met so far

- A method can't be called `_set`, `_input`, `_get` or other `Object`/`Node` virtuals (a test
  suite is a Node): `_input(...)` in a test failed to parse.
- Inside a class, calling a method named like a global function (`wrap`) resolves to the global:
  `KartTrackModel` keeps `wrap()` public but uses `_wrap()` inside.
- Type inference from a Variant is an error in this project (`var x := dict.key` fails): type it.
- `Array(typed_array)` returns the same array, not a copy: appending to it mutates the source.
- A `-s` script compiles before the autoloads exist: keep it untyped where it touches them.

## Presentation (HUD, effects, audio)

The HUD follows the web slice's layout.

- **Framework skin hook** (`Hud.set_skin`): new keys `ride_panel: false`, `clock_value_size`,
  `reserve_right`, `recalibrate_top`, `recalibrate_button`, `status_width`, `reserve_bottom`, and
  `Hud.set_status_area` (docs/GAMES.md "HUD kit"). Kart Race's skin is `KartHud.hud_skin()`:
  the framework ride panel is hidden for this game only (the ride strip replaces it),
  Recalibrate moves up beside Pause | End as an outline pill (the bottom right is the item
  button's), and the camera strip sits between the minimap and the item button, above the ride
  strip; while a board shows (`KartHud.status_area(true)`) it takes the bottom band, under the
  board's rows and pill.
- **KartStatus** (the lap badge, `set_state` unchanged) now sits top left in KartHud, not in the
  framework's top-centre slot.
- `ui/`: `KartHud` (composition: `status`, `racer_list`, `minimap`, `ride_strip`, `item_button`,
  `setup(racers, track)` on a new lineup, `set_track(track)` every race (the
  minimap redraws for a new track or direction), `update(race, delta)`, `banner(text, sec, subtitle, final)`, `hud_skin()`,
  `draft`/`draft_point`), `KartItemButton` (round, 260 px, bottom right, fires on press, a hit
  circle 1.25× the disc, roulette from `KartState.item`/`roulette_time`, an idle pulse after 2 s;
  the drift meter as a three-segment arc on a dark band round its upper-left edge, the tiers
  `KartPhysics.TIER_SEC`, redrawn in 24 charge steps, the knob glyph from `knob_boosting`), `KartItemIcons` (icons by item-id keyword:
  turbo, puck, drone, goo, shield, magnet: `KartItemLogic.ITEMS`),   `KartMinimap`, `KartRacerList`, `KartRideStrip`, `KartDraw` (batched vector drawing: one draw
  call per widget), `KartRaceBoard.show_podium(title, rows, …, stage)` and `mode` (with
  `stage`, `KartPodium.screen_points()`: plates over the 3D podium; without, 2D blocks).
  `world/KartPodium`: the GP podium on the start straight (`KartRace._stage_podium`), the top
  three's `KartView`s landing on its blocks in turn (`kart_state(i)`, a KartState that never
  races) under a held camera.
  `KartBaked` (a widget moved into its own small transparent SubViewport that renders only when
  something in it redraws, moves or shows/hides, drawn as one premultiplied TextureRect: the lap
  badge, the racer list, the ride strip (at most 5 Hz) and the place badge; the place badge's
  pop tweens the bake). Portraits (`KartPortraits.texture`) are baked into one atlas with one shared material, so
  lists draw in one batch; the boards make theirs through `KartHud.portrait_rect`.
- `world/KartFx.gd`: reads drift/boost/spin/draft from each KartState and `listen(events)`:
  tier bursts, tier-coloured drift-boost flames, hit stars, shield and bump sparks;
  `draft_screen()` feeds the HUD's draft streaks. The views take their drift slide from
  `KartState.slide`; KartFx only sets `boost_glow`.
- `audio/`: `KartAudio` (music: each track's produced theme, rendered offline by
  `tools/kart_music/render_kart_music.py` to `music/*.ogg` and indexed in `KartMusicIndex`, played
  as AudioDirector `stem_files` with the intro once and the rest looping; the final lap crossfades
  to a version a tone up with double-time hats and an extra lead; a results loop and a podium
  sting; the rider's engine as two synth layers pitched by speed
  (`engine_mix`), the nearest two bots' engines (`nearest_rivals`, `rival_db`, a pass-by bend),
  tyres, a spark sizzle per drift tier, the crowd; one-shots from the events and the HUD's
  `place_popped`, each on the frame its pop shows; a -1 dB limiter on Master, the music ducked
  3 dB under the countdown and banners, the engine dipped under priority cues) and `KartSfx`
  (single-voice SfxSynth presets, layered one-shots and the synth loops, all rendered once on a
  worker thread at load; plus each racer's horn as `horn_<racer id>`, the rider's at their
  finish).
  `tests/render_kart_audio.gd` renders all of it offline to WAVs with a timeline, for analysis.
- **Times are whole seconds** (rider feedback 2026-10-19: the milliseconds were distracting).
  `KartTheme.race_time` gives `m:ss`, rounded down like a stopwatch, for the HUD clock and the
  winner's time; `KartTheme.race_gap` gives `+m:ss`, rounded up so a racer behind never reads
  "+0:00". Nothing the rider sees shows milliseconds.
- HUD draw calls: see "Desktop draw calls after the Phase 2 merge" under the tablet budget.
- Tests: `tests/unit/kart_presentation_test.gd`; screenshots: `tests/capture_kart_hud.gd`.
