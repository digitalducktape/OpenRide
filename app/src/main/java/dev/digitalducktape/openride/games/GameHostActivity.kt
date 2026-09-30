package dev.digitalducktape.openride.games

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import dev.digitalducktape.openride.appContainer
import dev.digitalducktape.openride.games.bridge.GameBridge
import dev.digitalducktape.openride.games.bridge.OpenRideBridgePlugin
import dev.digitalducktape.openride.games.session.GameSessionManager
import dev.digitalducktape.openride.games.session.JustRideMode
import dev.digitalducktape.openride.games.session.SessionRequest
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.plugin.GodotPlugin

/**
 * Hosts the embedded Godot engine for game sessions (mini-games, #32): runs the exported
 * `games/` project (`res://games.pck`, packed into the APK's assets by `exportGamesPack`) and
 * connects it to the app through the `OpenRideBridge` plugin.
 *
 * Kotlin owns each session: the app-scoped [GameSessionManager] runs the [SessionRequest] this
 * activity was started with (and records its ride), and when the game calls `request_exit()`
 * after its summary the rider goes back to the Compose app.
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

    private val sessions: GameSessionManager
        get() = appContainer.gameSessionManager

    override fun onCreate(savedInstanceState: Bundle?) {
        // Attach before the engine starts so its first frame poll finds the session.
        startSession(intent)
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        Log.i(TAG, "game host created")
    }

    /** Entering games again: the engine is already running, so only the session is new. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        Log.i(TAG, "game host re-entered")
        startSession(intent)
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
        bridge.detach(sessions)
        super.onDestroy()
    }

    override fun getCommandLine(): MutableList<String> =
        (super.getCommandLine() + listOf("--main-pack", GAMES_PACK)).toMutableList()

    /** Only consulted on the engine's first start in this process. */
    override fun getHostPlugins(engine: Godot): Set<GodotPlugin> = setOf(OpenRideBridgePlugin(engine, bridge))

    private fun startSession(intent: Intent) {
        val request = SessionRequest.fromJson(intent.getStringExtra(EXTRA_REQUEST)) ?: DEFAULT_REQUEST
        Log.i(TAG, "game session: $request")
        // A session still running (the rider left without its summary) is finished and saved.
        sessions.begin(request, onExit = ::exitToApp)
        bridge.attach(sessions)
    }

    /** Back to the app, keeping the engine alive: never `finish()` (see the class comment). */
    private fun exitToApp() {
        // The session saves its ride app-scoped, so leaving never cuts that short.
        bridge.detach(sessions)
        moveTaskToBack(true)
        Log.i(TAG, "game host moved to back")
    }

    companion object {
        private const val TAG = "OpenRideGames"

        /** Exported by the `exportGamesPack` Gradle task into the APK's assets. */
        private const val GAMES_PACK = "res://games.pck"

        private const val EXTRA_REQUEST = "dev.digitalducktape.openride.games.SESSION_REQUEST"

        /** Until the Games hub (#38) picks: a 20-minute Just Ride of the demo. */
        val DEFAULT_REQUEST: SessionRequest = SessionRequest.JustRide("demo", JustRideMode.Timed(20))

        fun intent(context: Context, request: SessionRequest = DEFAULT_REQUEST): Intent =
            Intent(context, GameHostActivity::class.java).putExtra(EXTRA_REQUEST, request.toJson())
    }
}
