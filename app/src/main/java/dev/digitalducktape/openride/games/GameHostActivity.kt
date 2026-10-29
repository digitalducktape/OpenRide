package dev.digitalducktape.openride.games

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import androidx.core.view.WindowCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.launch
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import dev.digitalducktape.openride.R
import dev.digitalducktape.openride.appContainer
import dev.digitalducktape.openride.games.bridge.BridgeMessages
import dev.digitalducktape.openride.games.bridge.GameBridge
import dev.digitalducktape.openride.games.bridge.GameLoadingHost
import dev.digitalducktape.openride.games.bridge.OpenRideBridgePlugin
import dev.digitalducktape.openride.games.session.GameVisitManager
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.plugin.GodotPlugin

/**
 * Hosts the embedded Godot engine for game sessions (mini-games, #32): runs the exported
 * `games/` project (`res://games.pck`, packed into the APK's assets by `exportGamesPack`) and
 * connects it to the app through the `OpenRideBridge` plugin.
 *
 * Kotlin owns each visit: the app-scoped [GameVisitManager] runs the Games hub visit (one
 * ride, any number of plans). The rider picks everything in the Godot hub; the app only opens
 * it (`launchGames`). Exit games saves the visit and the rider goes back to the Compose app.
 * Only dev runs and the headless checks start a plan from outside the hub ([EXTRA_AUTOSTART]).
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
class GameHostActivity : GodotActivity(), GameLoadingHost {
    private var loadingView: View? = null
    private var resistanceButtons: View? = null

    private val bridge: GameBridge
        get() = appContainer.gameBridge

    private val visit: GameVisitManager
        get() = appContainer.gameVisitManager

    override fun onCreate(savedInstanceState: Bundle?) {
        // Before the engine starts: players that exist now are other apps' music, not Godot's.
        appContainer.otherMusicDetector.engineStarting()
        // Attach before the engine starts so its first frame poll finds the session.
        startSession(intent)
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // Edge to edge, like MainActivity: hiding the bars alone leaves the window fitted to the
        // nav-bar inset (1920x1008 on the bike), and Godot's 16:9 "keep" stretch then letterboxes
        // the hub and the games with black bars at the sides and bottom.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.attributes = window.attributes.apply {
            layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            // That alone still left the frame at 1920x1008 on the bike (Android 11): the window's
            // own fit-insets types default to the system bars, hidden or not. Fit none.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) fitInsetsTypes = 0
        }
        hideSystemBars()
        addResistanceButtons()
        showLoadingView(R.string.games_loading)
        Log.i(TAG, "game host created")
    }

    /**
     * The engine's first start takes a few seconds (setup, then the main scene). Its boot
     * splash is turned off in `games/project.godot` (#45), so until the main loop starts this
     * plain OpenRide loading view covers the engine's surface. Re-entry needs none: the engine
     * keeps running, so only [onCreate] adds it.
     */
    private fun showLoadingView(text: Int) {
        if (loadingView != null) return
        val dp = { v: Float -> TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics).toInt() }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            addView(ProgressBar(this@GameHostActivity).apply { isIndeterminate = true }, LinearLayout.LayoutParams(dp(48f), dp(48f)))
            addView(
                TextView(this@GameHostActivity).apply {
                    this.text = getString(text)
                    setTextColor(getColor(R.color.openride_on_surface_variant))
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                    setPadding(0, dp(16f), 0, 0)
                },
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT),
            )
        }
        val overlay = FrameLayout(this).apply {
            setBackgroundColor(getColor(R.color.openride_background))
            // Swallow touches meant for the engine while it loads.
            isClickable = true
            addView(content, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        }
        addContentView(overlay, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        loadingView = overlay
    }

    /**
     * A smart trainer's resistance (#68) has no knob, and the games read resistance as they read a
     * Peloton's: so while the bike source takes targets, + and − sit at the right edge, halfway
     * down, over the engine. A controller's shifters step it too. Native views rather than Godot
     * UI, so every game gets them without knowing about trainers.
     */
    private fun addResistanceButtons() {
        val dp = { v: Float -> TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics).toInt() }
        val bike = appContainer.bikeDataSource
        fun button(label: String, steps: Int) = TextView(this).apply {
            text = label
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f)
            background = GradientDrawable().apply {
                cornerRadius = dp(12f).toFloat()
                setColor(RESISTANCE_BUTTON_FILL)
            }
            contentDescription = if (steps > 0) "Resistance up" else "Resistance down"
            setOnClickListener { bike.stepResistance(steps) }
        }
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            val size = dp(64f)
            addView(button("+", 1), LinearLayout.LayoutParams(size, size))
            addView(button("−", -1), LinearLayout.LayoutParams(size, size).apply { topMargin = dp(12f) })
        }
        addContentView(
            column,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.END or Gravity.CENTER_VERTICAL)
                .apply { marginEnd = dp(24f) },
        )
        resistanceButtons = column
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                bike.adjustable.collect { column.visibility = if (it) View.VISIBLE else View.GONE }
            }
        }
    }

    /** Called on the render thread once the main scene is loaded, just before its first frame. */
    override fun onGodotMainLoopStarted() {
        Log.i(TAG, "engine main loop started")
        runOnUiThread { hideLoadingView() }
    }

    /** From the engine (`show_loading`, on the UI thread): a game is starting, or has drawn. */
    override fun setGameLoading(loading: Boolean) {
        if (loading) showLoadingView(R.string.games_starting) else hideLoadingView()
    }

    private fun hideLoadingView() {
        loadingView?.let { (it.parent as? ViewGroup)?.removeView(it) }
        loadingView = null
        // The loading view was added over them; they stay on top of the engine.
        resistanceButtons?.bringToFront()
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
        bridge.detach(visit)
        super.onDestroy()
    }

    override fun getCommandLine(): MutableList<String> =
        (super.getCommandLine() + listOf("--main-pack", GAMES_PACK)).toMutableList()

    /** Only consulted on the engine's first start in this process. */
    override fun getHostPlugins(engine: Godot): Set<GodotPlugin> = setOf(OpenRideBridgePlugin(engine, bridge))

    private fun startSession(intent: Intent) {
        val autostart = intent.getStringExtra(EXTRA_AUTOSTART)?.let(BridgeMessages::parsePlanRequest)
        Log.i(TAG, "games visit${autostart?.let { ", autostart $it" } ?: ""}")
        // A live visit (the rider left without Exit, and the app never came forward) is kept.
        visit.begin(autostart = autostart, onExit = ::exitToApp)
        visit.permissionRequester = { requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST_CAMERA) }
        bridge.attach(visit)
    }

    /** The hub's `request_camera_permission`: Android's prompt over the engine, then `hub_state`. */
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CAMERA) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        // Refused and Android won't ask again: the hub says "Camera not allowed" instead of asking.
        appContainer.gamesCameraPermissionRefused = !granted && !shouldShowRequestPermissionRationale(Manifest.permission.CAMERA)
        visit.onPermissionResult(granted)
    }

    /**
     * Back to the app, keeping the engine alive: never `finish()` (see the class comment). The
     * visit has saved its ride already; the app shows what comes [next] (`VisitNavigator`).
     */
    private fun exitToApp(next: String) {
        bridge.detach(visit)
        visit.permissionRequester = null
        moveTaskToBack(true)
        Log.i(TAG, "game host moved to back (next: $next)")
    }

    companion object {
        private const val TAG = "OpenRideGames"

        /** Exported by the `exportGamesPack` Gradle task into the APK's assets. */
        private const val GAMES_PACK = "res://games.pck"

        /**
         * Dev and the headless checks: a `start_plan` request (its snake_case JSON) that starts
         * as soon as the hub is up, e.g. `adb shell am start -n <pkg>/dev.digitalducktape.openride.games.GameHostActivity
         * --es dev.digitalducktape.openride.games.AUTOSTART '{"kind":"just_ride","game_id":"kart_race","mode":"minutes","length":5}'`.
         */
        const val EXTRA_AUTOSTART = "dev.digitalducktape.openride.games.AUTOSTART"

        private const val REQUEST_CAMERA = 0x0CA4

        /** The resistance buttons' fill: dark and see-through, readable over any game. */
        private const val RESISTANCE_BUTTON_FILL = 0x99000000.toInt()

        /** Opens the Games hub: a new visit, or the live one (`launchGames`, the app's one way in). */
        fun intent(context: Context): Intent = Intent(context, GameHostActivity::class.java)
    }
}
