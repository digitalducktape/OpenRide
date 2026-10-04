package dev.digitalducktape.openride

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import dev.digitalducktape.openride.ui.navigation.OpenRideNavHost
import dev.digitalducktape.openride.ui.theme.OpenRideTheme
import kotlinx.coroutines.launch

/**
 * The activity for the whole Compose app (per project scaffold ticket). All screens are
 * destinations within [OpenRideNavHost] rather than separate Activities; the one exception is
 * the mini-games host (`games.GameHostActivity`), which embeds the Godot engine.
 *
 * The [AppContainer] and the app-wide startup (auto-backup, update check, heart-rate manager)
 * belong to [OpenRideApplication], so they are shared with the games host and run once per
 * process rather than once per activity instance.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        hideSystemBars()

        // The WebView class player can make the system re-show the bars on its first video
        // play (media playback tickles the system UI without any window-focus change, so
        // onWindowFocusChanged never fires) — leaving the nav bar parked over the metrics
        // bar. Watching the insets catches every "bars became visible" path and re-hides.
        ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { _, insets ->
            if (insets.isVisible(WindowInsetsCompat.Type.systemBars())) hideSystemBars()
            insets
        }

        // PRD P0-10: keep the screen on for the duration of an active ride, and let normal
        // display timeout resume the instant it isn't. Driven from the activity (rather than
        // a screen-local effect) so the flag can't be left dangling by screen
        // navigation/recomposition while a ride is still active.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                appContainer.rideSessionManager.isRideActive.collect { active ->
                    if (active) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                }
            }
        }

        setContent {
            OpenRideTheme {
                OpenRideNavHost(appContainer = appContainer)
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // Bars can be restored by the system (dialogs, app switches); re-hide whenever the
        // window regains focus so the app stays truly full-screen on the bike.
        if (hasFocus) hideSystemBars()
    }

    /**
     * Full-screen kiosk mode: the tablet's OS navigation bar otherwise overlays the app's
     * own bottom UI (the in-ride metrics bar especially — the app is edge-to-edge and
     * deliberately doesn't inset for a bar the rider never needs mid-ride). Immersive
     * sticky: a swipe from the screen edge shows the system bars transiently, over the
     * app, then they auto-hide again.
     */
    private fun hideSystemBars() {
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }
}
