package dev.digitalducktape.openride.games

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import dev.digitalducktape.openride.appContainer
import dev.digitalducktape.openride.games.bridge.GameBridge
import dev.digitalducktape.openride.games.bridge.OpenRideBridgePlugin
import dev.digitalducktape.openride.games.bridge.TrackerLink
import dev.digitalducktape.openride.games.session.StubGameSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.job
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.plugin.GodotPlugin

/**
 * Hosts the embedded Godot engine for game sessions (mini-games, #32): runs the exported
 * `games/` project (`res://games.pck`, packed into the APK's assets by `exportGamesPack`) and
 * connects it to the app through the `OpenRideBridge` plugin.
 *
 * Kotlin owns each session: the attached [StubGameSession] (the real `GameSessionManager` in
 * #35) walks the plan, and when the game calls `request_exit()` after its summary the rider
 * goes back to the Compose app.
 *
 * **This activity lives as long as the app process.** Godot runs one engine per process and
 * cannot restart it: destroying the host terminates the engine, after which Godot force-quits
 * the whole process (`ProcessPhoenix.forceQuit`), taking the app and its ride with it. So the
 * spec's fallback applies (verified on the bike, see docs/GAMES.md): the host never finishes.
 * It runs in its own task (`taskAffinity`, `singleTask`), leaving games moves that task to the
 * back, and entering again brings the same instance forward through [onNewIntent] with a fresh
 * session. For the same reason Godot itself never quits. Anything that removes that background
 * task (e.g. swiping it out of recents) still ends the process; see docs/GAMES.md.
 */
class GameHostActivity : GodotActivity() {
    private val bridge: GameBridge
        get() = appContainer.gameBridge

    private var session: StubGameSession? = null
    private var sessionScope: CoroutineScope? = null
    private var trackerLink: TrackerLink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Attach before the engine starts so its first frame poll finds the session.
        startSession()
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        Log.i(TAG, "game host created")
    }

    /** Entering games again: the engine is already running, so only the session is new. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.i(TAG, "game host re-entered")
        startSession()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // Same kiosk full-screen as MainActivity: the bike's navigation bar otherwise stays
        // over the game, letterboxing Godot's 1920x1080 viewport. Re-applied on every focus
        // gain, since re-entering games and system dialogs can restore the bars.
        if (hasFocus) hideSystemBars()
    }

    private fun hideSystemBars() {
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    override fun onDestroy() {
        // Only reached when the process is going away anyway (see the class comment).
        Log.w(TAG, "game host destroyed")
        endSession()
        super.onDestroy()
    }

    override fun getCommandLine(): MutableList<String> =
        (super.getCommandLine() + listOf("--main-pack", GAMES_PACK)).toMutableList()

    /** Only consulted on the engine's first start in this process. */
    override fun getHostPlugins(engine: Godot): Set<GodotPlugin> = setOf(OpenRideBridgePlugin(engine, bridge))

    private fun startSession() {
        endSession()
        // A child of the activity's scope per session, so a finished session's clock can be
        // cancelled without touching the (long-lived) activity.
        val scope = CoroutineScope(lifecycleScope.coroutineContext + SupervisorJob(lifecycleScope.coroutineContext.job))
        val log: (String) -> Unit = { Log.i(TAG, it) }
        val tracker = TrackerLink(appContainer.headTracker, bridge, scope, log)
        val newSession = StubGameSession(
            signals = bridge,
            scope = scope,
            onExit = ::exitToApp,
            log = log,
            tracker = tracker,
        )
        session = newSession
        sessionScope = scope
        trackerLink = tracker
        bridge.attach(newSession)
    }

    private fun endSession() {
        session?.let(bridge::detach)
        // The camera never outlives the session that asked for it.
        trackerLink?.stop()
        sessionScope?.cancel()
        session = null
        sessionScope = null
        trackerLink = null
    }

    /** Back to the app, keeping the engine alive: never `finish()` (see the class comment). */
    private fun exitToApp() {
        endSession()
        moveTaskToBack(true)
        Log.i(TAG, "game host moved to back")
    }

    companion object {
        private const val TAG = "OpenRideGames"

        /** Exported by the `exportGamesPack` Gradle task into the APK's assets. */
        private const val GAMES_PACK = "res://games.pck"

        fun intent(context: Context): Intent = Intent(context, GameHostActivity::class.java)
    }
}
