package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.core.data.GameResult
import dev.digitalducktape.openride.core.data.GameResultDao
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.ride.RideSessionState
import dev.digitalducktape.openride.core.telemetry.DiscardReason
import dev.digitalducktape.openride.core.telemetry.RideEntry
import dev.digitalducktape.openride.games.bridge.BridgeMessages
import dev.digitalducktape.openride.games.bridge.CameraPermission
import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.GameSession
import dev.digitalducktape.openride.games.bridge.GameSignals
import dev.digitalducktape.openride.games.bridge.HubPhase
import dev.digitalducktape.openride.games.bridge.PlanRejectReason
import dev.digitalducktape.openride.games.bridge.PlanRejectedMessage
import dev.digitalducktape.openride.games.bridge.PlanRequestMessage
import dev.digitalducktape.openride.games.bridge.SegmentRole
import dev.digitalducktape.openride.games.bridge.SessionSummary
import dev.digitalducktape.openride.games.bridge.SessionTotals
import dev.digitalducktape.openride.games.bridge.SettingUpdate
import dev.digitalducktape.openride.games.bridge.TrackerLink
import dev.digitalducktape.openride.games.bridge.VisitEndedMessage
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive

/**
 * A Games hub visit (spec 2026-10-19 §4-§5, §10): the bridge's session from entering games to
 * leaving them. One visit records as **one ride**, however many plans the rider plays.
 *
 * Phases: `IDLE → WAITING (attached, waiting for the poll) → HUB ⇄ PLAN → SAVING → ENDED`, an
 * enum FSM (few states with simple enter actions).
 *
 * - [begin] readies a visit for the next frame poll ([onGameReady]), which sends `hub_state`.
 *   A visit still live (the host came forward again) is kept and its `hub_state` resent.
 * - `start_plan` (valid in the hub only, otherwise `plan_rejected: busy`) maps the request,
 *   builds the plan with the rider's FTP and hands it to the plan runner ([GameSessionManager]).
 *   The ride starts with the visit's first plan (nothing is recorded with no plan) and is
 *   resumed before each later one. When a plan finishes the ride is paused *manually*, so
 *   menu time records no seconds and no samples; then `session_finished` (with `ride_id` null
 *   and bests that include this visit's earlier runs) and the hub again.
 * - Results stay in memory with their `planId`, `planRun` (the plan's index in the visit) and a
 *   visit-wide `segmentIndex`, until the visit ends.
 * - The visit ends on `exit_hub` / `request_exit` (then the host leaves, [begin]'s `onExit`),
 *   on [endIfLive] (the app came back: no visit stays live behind it), or on the idle guard (20
 *   min in the hub with no touch and no pedalling; Godot stays put and a tap starts a new visit).
 *   A plan in progress is ended first. The ride is kept with at least a minute of gameplay and
 *   some pedalling, else discarded; then `visit_ended` and [finishedRideId].
 * - If the process dies mid-visit the visit is lost, as any unsaved ride is (spec §10).
 *
 * Every entry point hops onto [scope] (the main thread in the app), so all state is touched on
 * one thread; only [segmentTimeLeftSec] is read from Godot's thread.
 */
class GameVisitManager(
    private val signals: GameSignals,
    private val scope: CoroutineScope,
    private val runner: GameSessionManager,
    private val rideSessionManager: RideSessionManager,
    /** A GPX route is loaded: `ride_start`'s `route`. */
    private val routeLoaded: () -> Boolean,
    private val gameResultDao: GameResultDao,
    private val activeProfileId: () -> Long?,
    private val profile: suspend (profileId: Long) -> Profile?,
    private val settings: GamesSettingsStore,
    private val cameraPermission: () -> CameraPermission = { CameraPermission.GRANTED },
    /** The camera can't be used right now (no face found, no camera): `hub_state.camera.available`. */
    private val cameraFailed: () -> Boolean = { false },
    /** The rider's lean extremes are from today, so a first calibration takes the centre only. */
    private val sameDayExtremes: (Profile) -> Boolean = { false },
    /** The camera head tracker; null runs visits without a camera. */
    private val tracker: TrackerLink? = null,
    /** The rider is pedalling now: keeps the idle guard from firing. */
    private val pedalling: () -> Boolean = { false },
    /** Renders the rider's avatar PNG for the hub, or null. */
    private val avatar: suspend (Profile) -> String? = { null },
    private val catalog: GameCatalog = GameCatalog.DEFAULT,
    private val clock: () -> Long = System::currentTimeMillis,
    /** A visit's circuit seed (#75); tests pin it. */
    private val seedSource: () -> Long = { kotlin.random.Random.nextLong() },
    /** Where the app goes when the rider leaves (the ride summary, or the profile editor). */
    private val navigator: VisitNavigator = VisitNavigator(),
    private val log: (String) -> Unit = {},
) : GameSession {
    private enum class Phase { IDLE, WAITING, HUB, PLAN, SAVING, ENDED }

    /** Why and where to the visit ends, once a plan in progress has finished. */
    private data class Ending(val reason: String, val next: String, val leave: Boolean)

    private var phase = Phase.IDLE
    private var generation = 0
    private var visitId = ""
    private var onExit: (String) -> Unit = {}
    private var autostart: PlanRequestMessage? = null
    private var rider: Profile? = null
    private var avatarPng: String? = null
    private var rideDecided = false
    private var recording = false
    private var planIndex = 0
    /** Seeds this visit's circuit draws (#75): plan n draws with [circuitSeed]. */
    private var visitSeed = 0L
    private var segmentIndex = 0
    private var gameplaySec = 0
    private var pending: Ending? = null
    private var lastEnd: Ending? = null
    private var lastRideId: Long? = null
    private var idleSec = 0
    private val rows = mutableListOf<GameResult>()
    private val visitResults = mutableListOf<VisitResult>()
    private val visitPlans = mutableListOf<VisitPlan>()
    private var hubJob: Job? = null
    private var idleJob: Job? = null
    private var savingJob: Job? = null

    /** The host's camera permission prompt (`request_camera_permission`); set while a host is attached. */
    var permissionRequester: (() -> Unit)? = null

    override val segmentTimeLeftSec: Double get() = runner.segmentTimeLeftSec

    private val _finishedRideId = MutableStateFlow<Long?>(null)

    /** The ride the last visit saved, once `visit_ended` is sent: the app opens its summary (consume once). */
    val finishedRideId: StateFlow<Long?> = _finishedRideId.asStateFlow()

    private val _saving = MutableStateFlow(false)

    /** A visit's ride is being saved (from the end of the visit until `visit_ended`): the Games launcher says so. */
    val saving: StateFlow<Boolean> = _saving.asStateFlow()

    /** The app has shown [finishedRideId]'s summary. */
    fun consumeFinishedRide() {
        _finishedRideId.value = null
    }

    /**
     * Readies a visit for the next frame poll. [autostart] (dev, and the Compose tab until the
     * hub replaces it) starts that plan as soon as the hub is up. [onExit] runs with `next` when
     * the rider leaves games. A live visit is kept. Call on [scope]'s thread, before attaching.
     */
    fun begin(autostart: PlanRequestMessage? = null, onExit: (next: String) -> Unit) {
        this.onExit = onExit
        this.autostart = autostart
        if (phase in LIVE) {
            log("visit $visitId: re-entered, keeping it")
            return
        }
        newVisit()
    }

    private fun newVisit() {
        generation++
        visitId = "v-${clock()}"
        phase = Phase.WAITING
        rider = null
        avatarPng = null
        rideDecided = false
        recording = false
        planIndex = 0
        visitSeed = seedSource()
        segmentIndex = 0
        gameplaySec = 0
        pending = null
        lastEnd = null
        lastRideId = null
        idleSec = 0
        rows.clear()
        visitResults.clear()
        visitPlans.clear()
        log("visit $visitId begins")
    }

    override fun onGameReady() = post {
        when (phase) {
            Phase.WAITING -> openHub(generation)
            Phase.HUB, Phase.PLAN -> {
                sendHubStateNow()
                if (phase == Phase.HUB) runAutostart()
            }
            else -> Unit
        }
    }

    private fun openHub(gen: Int) = scope.launch {
        // A visit still saving must finish before this one can start a ride.
        savingJob?.join()
        if (gen != generation || phase != Phase.WAITING) return@launch
        rider = activeProfileId()?.let { loadProfile(it) }
        avatarPng = rider?.let { runCatching { avatar(it) }.getOrNull() }
        tracker?.setCameraGamesEnabled(settings.settings.value.cameraGames)
        tracker?.startVisit()
        tracker?.onHubCalibrationEnded = ::requestHubState
        enterHub()
        sendHubState()
        runAutostart()
    }

    private fun runAutostart() {
        val request = autostart ?: return
        autostart = null
        log("autostart $request")
        startPlan(request, BridgeMessages.requestEcho("{}"))
    }

    // --- Godot → Kotlin: the hub -----------------------------------------------------------

    override fun onStartPlan(requestJson: String) = post {
        touched()
        if (phase != Phase.HUB) return@post reject(BridgeMessages.requestEcho(requestJson), PlanRejectReason.BUSY)
        val request = BridgeMessages.parsePlanRequest(requestJson)
            ?: return@post reject(BridgeMessages.requestEcho(requestJson), PlanRejectReason.UNKNOWN_GAME)
        startPlan(request, BridgeMessages.requestEcho(requestJson))
    }

    override fun onUpdateSetting(key: String, valueJson: String) = post {
        touched()
        when (val update = BridgeMessages.parseSetting(key, valueJson)) {
            null -> log("update_setting: ignoring $key = $valueJson")
            is SettingUpdate.CameraGames -> {
                settings.update { it.copy(cameraGames = update.on) }
                tracker?.setCameraGamesEnabled(update.on)
            }
            is SettingUpdate.GameMusic -> settings.update { it.copy(audio = it.audio.copy(gameMusic = update.on)) }
            is SettingUpdate.MusicVolume -> settings.update { it.copy(audio = it.audio.copy(musicVolume = update.volume)) }
            is SettingUpdate.SfxVolume -> settings.update { it.copy(audio = it.audio.copy(sfxVolume = update.volume)) }
        }
        requestHubState()
    }

    override fun onHubCalibrate(mode: String, full: Boolean) = post {
        touched()
        if (phase != Phase.HUB) return@post log("hub_calibrate outside the hub: ignored")
        log("hub_calibrate $mode full=$full")
        tracker?.hubCalibrate(mode, full)
    }

    override fun onCancelCalibration() = post {
        touched()
        if (phase == Phase.HUB) tracker?.cancelCalibration()
    }

    override fun onRequestCameraPermission() = post {
        touched()
        if (phase != Phase.HUB) return@post
        permissionRequester?.invoke() ?: log("request_camera_permission: no host attached")
    }

    /** The host's answer to the camera permission prompt. */
    fun onPermissionResult(granted: Boolean) = post {
        log("camera permission ${if (granted) "granted" else "refused"}")
        tracker?.refreshPermission()
        requestHubState()
    }

    override fun onExitHub(next: String) = post {
        touched()
        end(Ending("exit", if (next == "edit_profile") next else "app", leave = true))
    }

    override fun onHubActivity() = post {
        touched()
        // After the idle guard saved the visit, the rider's tap keeps playing: a new visit.
        if (phase == Phase.ENDED && lastEnd?.next == NEXT_HUB) {
            newVisit()
            openHub(generation)
        }
    }

    // --- Godot → Kotlin: within a plan (the runner's) ----------------------------------------

    override fun onSegmentFinished(resultJson: String) = post { if (phase == Phase.PLAN) runner.segmentFinished(resultJson) }
    override fun onRequestCalibration(mode: String) = post { if (phase == Phase.PLAN) runner.requestCalibration(mode) }
    override fun onSetTrackerMode(mode: String) = post { if (phase == Phase.PLAN) runner.setTrackerMode(mode) }
    override fun onRequestPause() = post { if (phase == Phase.PLAN) runner.requestPause() }
    override fun onRequestResume() = post { if (phase == Phase.PLAN) runner.requestResume() }
    override fun onRequestEnd() = post { if (phase == Phase.PLAN) runner.requestEnd() }

    /** v1's `request_exit`: in the hub, Exit games; during a plan it ends the plan, then the visit. */
    override fun onRequestExit() = post {
        touched()
        end(Ending("exit", "app", leave = true))
    }

    /**
     * Saves a live visit as Exit does, without leaving (the host is already behind the app, or
     * it's the idle guard). The app calls it on resume: no visit stays live behind the app.
     */
    fun endIfLive(reason: String) = post {
        end(Ending(reason, if (reason == REASON_IDLE) NEXT_HUB else "app", leave = false))
    }

    // --- Plans ------------------------------------------------------------------------------

    private fun startPlan(request: PlanRequestMessage, echo: JsonElement) {
        val cameraGames = cameraAvailable()
        val mapped = request.toSessionRequest(cameraGames, catalog)
        if (mapped is RequestMapping.Rejected) return reject(echo, mapped.reason)
        val sessionRequest = (mapped as RequestMapping.Ok).request
        phase = Phase.PLAN
        stopIdleGuard()
        hubJob?.cancel()
        val gen = generation
        val index = planIndex
        scope.launch {
            // The FTP may have changed since the visit began.
            rider = activeProfileId()?.let { loadProfile(it) } ?: rider
            val plan = SessionPlans.forRequest(sessionRequest, FtpBasis.of(rider?.ftp), catalog, circuitSeed(index))
            if (gen != generation || phase != Phase.PLAN) return@launch
            if (plan == null) {
                enterHub()
                return@launch reject(echo, PlanRejectReason.UNKNOWN_GAME)
            }
            pending?.let { ending ->
                pending = null
                return@launch finishVisit(ending)
            }
            planIndex++
            val ride = rideFor(plan.planId)
            runner.run(
                plan,
                ride,
                PlanStart(rider?.id, rider?.name, visitId, index, calibrated()),
            ) { outcome -> onPlanFinished(gen, index, outcome) }
        }
    }

    /** Starts the ride with the visit's first plan, or resumes it for a later one. */
    private fun rideFor(planId: String): PlanRide {
        if (!rideDecided) {
            rideDecided = true
            recording = startRide(planId)
        } else if (recording) {
            rideSessionManager.resume()
        }
        return if (recording) RideSessionPlanRide(rideSessionManager) else NoRide
    }

    private fun startRide(planId: String): Boolean {
        val pid = rider?.id
        if (pid == null) {
            log("no active rider: this visit isn't recorded")
            return false
        }
        // A finished ride nobody dismissed (e.g. a summary still open) must not block this one.
        if (rideSessionManager.state.value is RideSessionState.Finished) rideSessionManager.reset()
        if (rideSessionManager.state.value != RideSessionState.Idle) {
            log("another ride is in progress: this visit isn't recorded")
            return false
        }
        rideSessionManager.start(pid, gamePlan = planId, entry = RideEntry.GAMES, route = routeLoaded())
        return true
    }

    private fun onPlanFinished(gen: Int, index: Int, outcome: PlanOutcome) {
        if (gen != generation) return
        // Menu time isn't riding: a manual pause, so pedalling in the hub doesn't resume it.
        if (recording) rideSessionManager.pause()
        tracker?.planEnded()
        val plan = outcome.plan
        val difficulty = wire(Difficulty.serializer(), plan.difficulty)
        val previousRuns = visitPlans.toList()
        for (played in outcome.results) {
            val row = GameResult(
                rideId = 0,
                segmentIndex = segmentIndex++,
                gameId = played.segment.gameId,
                role = wire(SegmentRole.serializer(), played.segment.role),
                difficulty = difficulty,
                startSec = played.startSec,
                durationSec = played.playedSec,
                score = played.result.score,
                stars = played.result.stars,
                won = played.result.won,
                skipped = played.result.skipped,
                statsJson = played.result.stats.toString(),
                variant = played.result.variant,
                planId = plan.planId,
                planRun = index,
            )
            rows += row
            visitResults += VisitResult(plan.planId, index, row.gameId, difficulty, row.variant, row.score, row.stars, row.skipped, row.durationSec)
        }
        gameplaySec += outcome.gameplaySec
        val counted = outcome.results.filterNot { it.result.skipped }
        val run = VisitPlan(
            planId = plan.planId,
            difficulty = plan.difficulty,
            variant = counted.map { it.result.variant }.distinct().singleOrNull(),
            score = counted.sumOf { it.result.score },
            stars = counted.sumOf { it.result.stars },
            gameIds = outcome.results.map { it.segment.gameId }.distinct(),
        )
        visitPlans += run
        scope.launch {
            val bests = bests(run, previousRuns)
            val summary = SessionSummary(
                rideId = null,
                results = outcome.results.map { it.result },
                totals = SessionTotals(
                    score = outcome.results.sumOf { it.result.score },
                    stars = outcome.results.sumOf { it.result.stars },
                    segments = outcome.results.size,
                    elapsedSec = outcome.elapsedSec,
                ),
                bests = bests,
                visitId = visitId,
                planIndex = index,
                planId = plan.planId,
                difficulty = plan.difficulty,
            )
            log("session_finished ${plan.planId}: ${outcome.results.size} results")
            signals.sessionFinished(BridgeMessages.encode(summary))
            if (gen != generation) return@launch
            val ending = pending
            pending = null
            if (ending != null) return@launch finishVisit(ending)
            enterHub()
            requestHubState()
        }
    }

    /**
     * `bests`: `{"score": true}` and/or `{"stars": true}` when this run beat the rider's best at
     * the same plan and difficulty, saved or earlier in this visit (a first scoring run counts),
     * plus `previous_score` / `previous_stars`. Empty when the visit isn't recording.
     */
    private suspend fun bests(run: VisitPlan, earlier: List<VisitPlan>): JsonObject {
        val pid = rider?.id
        if (!recording || pid == null) return EMPTY
        val saved = try {
            gameResultDao.planBest(pid, run.planId, wire(Difficulty.serializer(), run.difficulty), excludeRideId = -1, variant = run.variant)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log("reading bests failed: $e")
            return EMPTY
        }
        val same = earlier.filter { it.planId == run.planId && it.difficulty == run.difficulty && (run.variant == null || it.variant == run.variant) }
        val previousScore = (listOfNotNull(saved.bestScore) + same.map { it.score }).maxOrNull()
        val previousStars = (listOfNotNull(saved.bestStars) + same.map { it.stars }).maxOrNull()
        val flags = buildMap {
            if (run.score > 0 && run.score > (previousScore ?: 0.0)) put("score", JsonPrimitive(true))
            if (run.stars > 0 && run.stars > (previousStars ?: 0)) put("stars", JsonPrimitive(true))
            previousScore?.let { put("previous_score", JsonPrimitive(it.toInt())) }
            previousStars?.let { put("previous_stars", JsonPrimitive(it)) }
        }
        return JsonObject(flags)
    }

    // --- Ending -----------------------------------------------------------------------------

    private fun end(ending: Ending) {
        when (phase) {
            Phase.WAITING, Phase.HUB -> finishVisit(ending)
            Phase.PLAN -> {
                // The plan ends first (session_finished), then the visit.
                pending = ending
                runner.finishNow()
            }
            Phase.ENDED -> leaveAfterIdleSave(ending)
            else -> Unit
        }
    }

    /**
     * The idle guard saved the visit while Godot kept showing the hub; the rider now leaves
     * without playing again. The ride is saved already (and `visit_ended` sent), so just leave.
     */
    private fun leaveAfterIdleSave(ending: Ending) {
        if (!ending.leave || lastEnd?.next != NEXT_HUB) return
        lastEnd = ending
        navigator.visitEnded(lastRideId, ending.next)
        onExit(ending.next)
    }

    private fun finishVisit(ending: Ending) {
        phase = Phase.SAVING
        lastEnd = ending
        stopIdleGuard()
        hubJob?.cancel()
        tracker?.endVisit()
        val gen = generation
        val id = visitId
        val keepRows = rows.toList()
        // One plan played: its id, as History reads today. Several (two runs of one plan too): "visit".
        val plans = visitPlans.map { it.planId }
        val outcome = when {
            !recording && rideDecided -> SaveOutcome.Discard("not_recording")
            !rideDecided -> SaveOutcome.Discard(if (rider == null || !canRecord()) "not_recording" else "too_short")
            gameplaySec < MIN_GAMEPLAY_SEC -> SaveOutcome.Discard("too_short")
            !pedalled() -> SaveOutcome.Discard("no_pedalling")
            else -> SaveOutcome.Keep
        }
        if (recording && outcome is SaveOutcome.Discard) {
            log("discarding the visit's ride: ${gameplaySec}s of gameplay, pedalled=${pedalled()}")
            rideSessionManager.discard(
                when ((outcome as SaveOutcome.Discard).reason) {
                    "no_pedalling" -> DiscardReason.NO_PEDALLING
                    "not_recording" -> DiscardReason.NOT_RECORDING
                    else -> DiscardReason.TOO_SHORT
                },
            )
        }
        if (recording && outcome is SaveOutcome.Keep) {
            rideSessionManager.setGamePlan(plans.singleOrNull() ?: GameLabels.VISIT_PLAN)
        }
        _saving.value = true
        savingJob = scope.launch {
            val rideId = try {
                if (outcome is SaveOutcome.Keep) saveRide(keepRows) else null
            } finally {
                _saving.value = false
            }
            val message = VisitEndedMessage(
                visitId = id,
                rideId = rideId,
                saved = rideId != null,
                discardedReason = (outcome as? SaveOutcome.Discard)?.reason ?: "",
                next = ending.next,
                reason = ending.reason,
            )
            log("visit_ended $id: ride $rideId (${ending.reason})")
            signals.visitEnded(BridgeMessages.encode(message))
            // The rider re-entered games while the ride was written: a new visit is live, so
            // stay in it (no leaving, no summary over it). The ride is saved all the same.
            if (gen != generation) return@launch
            phase = Phase.ENDED
            lastRideId = rideId
            if (rideId != null) _finishedRideId.value = rideId
            navigator.visitEnded(rideId, ending.next)
            if (ending.leave) onExit(ending.next)
        }
    }

    private sealed interface SaveOutcome {
        data object Keep : SaveOutcome
        data class Discard(val reason: String) : SaveOutcome
    }

    /** The ride through the normal recording path, then every result. Null if nothing was saved. */
    private suspend fun saveRide(results: List<GameResult>): Long? {
        val ride = try {
            rideSessionManager.stop()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log("saving the ride failed: $e")
            null
        } ?: return null
        try {
            if (results.isNotEmpty()) gameResultDao.insertAll(results.map { it.copy(rideId = ride.id) })
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log("saving the game results failed: $e")
        }
        // Back to Idle so the app's next ride can start; the summary loads by ride id.
        rideSessionManager.reset()
        return ride.id
    }

    private fun pedalled(): Boolean = rideSessionManager.liveAggregates.value.let { it.maxCadence > 0 || it.maxPower > 0 }

    // --- The hub ----------------------------------------------------------------------------

    private fun enterHub() {
        phase = Phase.HUB
        startIdleGuard()
    }

    private fun reject(echo: JsonElement, reason: PlanRejectReason) {
        log("plan_rejected $reason: $echo")
        signals.planRejected(BridgeMessages.encode(PlanRejectedMessage(echo, reason)))
    }

    /** A `hub_state` within [HUB_COALESCE_MS], however many changes ask for one meanwhile. */
    private fun requestHubState() {
        if (phase !in LIVE || hubJob?.isActive == true) return
        hubJob = scope.launch {
            delay(HUB_COALESCE_MS)
            sendHubState()
        }
    }

    private fun sendHubStateNow() {
        hubJob?.cancel()
        hubJob = scope.launch { sendHubState() }
    }

    private suspend fun sendHubState() {
        val pid = rider?.id
        val gameBests = pid?.let { runCatching { gameResultDao.observePersonalBests(it).first() }.getOrNull() }.orEmpty()
        val planBests = pid?.let { runCatching { gameResultDao.planBests(it) }.getOrNull() }.orEmpty()
        val state = HubStateBuilder.build(
            HubInputs(
                visitId = visitId,
                phase = when (phase) {
                    Phase.PLAN -> HubPhase.PLAN
                    Phase.SAVING -> HubPhase.SAVING
                    Phase.ENDED -> HubPhase.ENDED
                    else -> HubPhase.HUB
                },
                profile = rider,
                avatarPng = avatarPng,
                settings = settings.settings.value,
                permission = cameraPermission(),
                cameraFailed = cameraFailed(),
                calibrated = calibrated(),
                sameDayExtremes = rider?.let(sameDayExtremes) ?: false,
                catalog = catalog,
                gameBests = gameBests,
                planBests = planBests,
                recording = if (rideDecided) recording else rider != null && canRecord(),
                rideSec = if (recording) rideSessionManager.elapsedSec.value else 0,
                visitResults = visitResults.toList(),
                visitPlans = visitPlans.toList(),
                circuitSeed = circuitSeed(planIndex),
            ),
        )
        signals.hubState(BridgeMessages.encode(state))
    }

    /**
     * The seed plan [index] of this visit draws a preset circuit with (#75): a fresh mix each
     * ride and each circuit, and the hub's lineup is the one that plays.
     */
    private fun circuitSeed(index: Int): Long = visitSeed + index

    /** Whether a ride could start now: the recorder is free (or holds a finished ride). */
    private fun canRecord(): Boolean = rideSessionManager.state.value.let { it == RideSessionState.Idle || it is RideSessionState.Finished }

    private fun cameraAvailable(): Boolean =
        HubStateBuilder.cameraAvailable(cameraPermission(), settings.settings.value.cameraGames, cameraFailed())

    /** What this visit's calibration covers: `""`, `lean_x` or `lean_2d`. */
    private fun calibrated(): String = tracker?.calibratedMode() ?: ""

    // --- The idle guard ---------------------------------------------------------------------

    private fun touched() {
        idleSec = 0
    }

    private fun startIdleGuard() {
        idleJob?.cancel()
        idleSec = 0
        idleJob = scope.launch {
            while (isActive) {
                delay(IDLE_TICK_MS)
                if (pedalling()) idleSec = 0 else idleSec += (IDLE_TICK_MS / 1_000).toInt()
                if (idleSec >= IDLE_LIMIT_SEC && phase == Phase.HUB) {
                    log("the hub has been idle for ${IDLE_LIMIT_SEC / 60} min: saving the visit")
                    finishVisit(Ending(REASON_IDLE, NEXT_HUB, leave = false))
                    return@launch
                }
            }
        }
    }

    private fun stopIdleGuard() {
        idleJob?.cancel()
        idleJob = null
    }

    // --- Helpers ----------------------------------------------------------------------------

    private suspend fun loadProfile(id: Long): Profile? = try {
        profile(id)
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        log("loading profile $id failed: $e")
        null
    }

    private fun post(block: () -> Unit) {
        scope.launch { block() }
    }

    private fun <T> wire(serializer: KSerializer<T>, value: T): String =
        Json.encodeToJsonElement(serializer, value).jsonPrimitive.content

    companion object {
        /** The shortest visit saved as a ride: a game's shortest timed length (`min_sec`). */
        const val MIN_GAMEPLAY_SEC = 60

        /** The hub idle guard (spec §10): no touch and no pedalling for this long saves the visit. */
        const val IDLE_LIMIT_SEC = 20 * 60
        private const val IDLE_TICK_MS = 5_000L
        private const val HUB_COALESCE_MS = 250L
        private const val REASON_IDLE = "idle"

        /** `visit_ended.next` when Godot stays in the hub (the idle guard). */
        const val NEXT_HUB = "hub"
        private val EMPTY = JsonObject(emptyMap())

        /** A visit that [begin] keeps rather than replacing. */
        private val LIVE = setOf(Phase.WAITING, Phase.HUB, Phase.PLAN)
    }
}
