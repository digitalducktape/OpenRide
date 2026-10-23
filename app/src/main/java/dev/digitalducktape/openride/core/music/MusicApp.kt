package dev.digitalducktape.openride.core.music

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Drawable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The rider's music app: a Music button in the top bar opens it, so music can be started or
 * skipped without leaving the bike's screen for a launcher (OpenRide is often the tablet's only
 * home screen, and the stock bike has no recents button). Chosen once on the Profile tab.
 */
interface MusicAppStore {
    /** The chosen app's package name, or `null` for none (no Music button). */
    val packageName: StateFlow<String?>
    fun set(packageName: String?)
}

/** A store that keeps the choice in memory, for tests. */
class InMemoryMusicAppStore(initial: String? = null) : MusicAppStore {
    private val state = MutableStateFlow(initial)
    override val packageName: StateFlow<String?> = state.asStateFlow()
    override fun set(packageName: String?) {
        state.value = packageName
    }
}

/** The real store: SharedPreferences, so the choice survives restarts. */
class SharedPrefsMusicAppStore(context: Context) : MusicAppStore {
    private val prefs = context.applicationContext.getSharedPreferences("music_app", Context.MODE_PRIVATE)
    private val state = MutableStateFlow(prefs.getString(KEY_PACKAGE, null))
    override val packageName: StateFlow<String?> = state.asStateFlow()

    override fun set(packageName: String?) {
        prefs.edit().putString(KEY_PACKAGE, packageName).apply()
        state.value = packageName
    }

    private companion object {
        const val KEY_PACKAGE = "package"
    }
}

/** An app the rider can pick: its package and the name its launcher icon shows. */
data class InstalledApp(val packageName: String, val label: String)

/** Finding, naming and opening the rider's music app. */
object MusicApps {
    /**
     * Well-known music and audio apps, listed first in the picker, in this order. Anything else
     * the tablet can launch follows, so an app missing here can still be chosen.
     */
    val KNOWN: List<String> = listOf(
        "com.apple.android.music",
        "com.spotify.music",
        "com.google.android.apps.youtube.music",
        "com.amazon.mp3",
        "com.aspiro.tidal",
        "deezer.android.app",
        "com.soundcloud.android",
        "com.pandora.android",
        "com.audible.application",
        "au.com.shiftyjelly.pocketcasts",
    )

    /**
     * Known music apps first (in [KNOWN] order), then the rest by name, without [exclude] or apps
     * with no name (the stock bike has a nameless Peloton launcher entry).
     */
    fun order(apps: List<InstalledApp>, exclude: String): List<InstalledApp> {
        val (known, others) = apps
            .filter { it.packageName != exclude && it.label.isNotBlank() }
            .distinctBy { it.packageName }
            .partition { it.packageName in KNOWN }
        return known.sortedBy { KNOWN.indexOf(it.packageName) } + others.sortedBy { it.label.lowercase() }
    }

    /** Every app with a launcher icon, OpenRide itself left out, in picker order. */
    fun installed(context: Context): List<InstalledApp> {
        val pm = context.packageManager
        val launchable = pm.queryIntentActivities(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER),
            0,
        ).map { InstalledApp(it.activityInfo.packageName, it.loadLabel(pm).toString()) }
        return order(launchable, exclude = context.packageName)
    }

    /** [packageName]'s launcher name, or `null` when it's no longer installed. */
    fun label(context: Context, packageName: String): String? = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
    } catch (e: PackageManager.NameNotFoundException) {
        null
    }

    fun icon(context: Context, packageName: String): Drawable? = try {
        context.packageManager.getApplicationIcon(packageName)
    } catch (e: PackageManager.NameNotFoundException) {
        null
    }

    /**
     * Brings [packageName] forward the way a launcher would (its existing task, so music already
     * playing isn't restarted). Returns false when it can't be opened, e.g. it was uninstalled.
     * A ride in progress keeps recording while the music app is in front.
     */
    fun open(context: Context, packageName: String): Boolean {
        val intent = context.packageManager.getLaunchIntentForPackage(packageName) ?: return false
        return try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }
}
