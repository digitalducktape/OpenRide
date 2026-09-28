package dev.digitalducktape.openride

import android.app.Application
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

/**
 * Owns the process-wide [AppContainer], so every activity shares one database, one sensor
 * binding and one ride session. [MainActivity] used to construct the container itself; the
 * mini-games host ([dev.digitalducktape.openride.games.GameHostActivity], #32) is a second
 * activity and must see the same ride and sensors.
 *
 * Unit tests run under a plain [Application] (see `src/test/resources/robolectric.properties`)
 * so this startup never runs inside Robolectric.
 */
class OpenRideApplication : Application() {
    val appContainer: AppContainer by lazy { AppContainer(applicationContext) }

    /** Process-lifetime scope for launch work that used to hang off MainActivity's lifecycle. */
    private val applicationScope: CoroutineScope = MainScope()

    override fun onCreate() {
        super.onCreate()

        // Rolling automatic backup + silent restore-on-empty (see AutoBackupManager) so an
        // app update or reinstall never silently loses profiles and ride history. Once per
        // process: the process can also be (re)started straight into the games host.
        appContainer.autoBackupManager.start()

        // PRD #22/T22: best-effort check for a newer GitHub release on launch. Silent on any
        // failure; if one is found the Home screen shows a dismissible banner. Never installs.
        applicationScope.launch {
            appContainer.refreshUpdateAvailability(
                BuildConfig.VERSION_CODE,
                BuildConfig.UPDATE_APK_ASSET_INFIX,
            )
        }

        // PRD P1-4, T17: eagerly construct (the container property is `by lazy`) so the
        // heart-rate manager starts observing the active profile's paired strap from launch,
        // rather than only whenever a screen happens to reference it first.
        appContainer.heartRateManager
    }
}

/** The process-wide [AppContainer], from any context whose application is [OpenRideApplication]. */
val android.content.Context.appContainer: AppContainer
    get() = (applicationContext as OpenRideApplication).appContainer
