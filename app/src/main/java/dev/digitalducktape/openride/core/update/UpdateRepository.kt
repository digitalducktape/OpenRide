package dev.digitalducktape.openride.core.update

import android.content.Context
import android.content.Intent
import dev.digitalducktape.openride.core.content.FeedFetcher
import dev.digitalducktape.openride.core.content.HttpUrlFeedFetcher
import dev.digitalducktape.openride.core.files.OpenRideFileProvider
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Fetches the latest GitHub release, downloads its APK, and builds the install intent (PRD #22/T22).
 *
 * **Nothing here installs anything.** [downloadApk] only writes a file into the app's own cache;
 * handing it to the system package installer is a separate, explicitly user-tapped step
 * ([installIntentFor]), and the actual install is then the platform installer's own confirmation
 * UI. That keeps the ticket's "no auto-install without user tap" property structural rather than
 * a UI convention.
 *
 * Reuses [FeedFetcher] (the same narrow HTTP seam the content layer uses) so tests can supply a
 * fixture manifest without a network.
 */
class UpdateRepository(
    private val context: Context,
    private val fetcher: FeedFetcher = HttpUrlFeedFetcher(),
    private val checker: UpdateChecker = UpdateChecker(),
) {

    /**
     * Fetches the latest GitHub release and evaluates it against [currentVersionCode] for this
     * build's [assetInfix] (`real`/`mock`). Never throws — a network failure is a [UpdateCheckResult.Failed].
     */
    suspend fun check(currentVersionCode: Int, assetInfix: String): UpdateCheckResult =
        withContext(Dispatchers.IO) {
            val body = try {
                fetcher.fetch(LATEST_RELEASE_URL).use { it.bufferedReader().readText() }
            } catch (e: Exception) {
                return@withContext UpdateCheckResult.Failed("Couldn't reach GitHub releases")
            }
            checker.evaluate(currentVersionCode, assetInfix, body)
        }

    /**
     * Downloads [update]'s APK into the app's cache and returns the file, or `null` if the
     * download failed. A partial download is deleted rather than left behind for the installer
     * to choke on.
     */
    suspend fun downloadApk(update: AvailableUpdate): File? = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, UPDATES_DIR).apply { mkdirs() }
        val target = File(dir, "openride-${update.versionCode}.apk")
        try {
            fetcher.fetch(update.apkUrl).use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            target
        } catch (e: Exception) {
            target.delete()
            null
        }
    }

    /**
     * Builds the intent that hands [apk] to the system package installer. Launching it shows the
     * platform's own install confirmation — the user still has to accept there.
     */
    fun installIntentFor(apk: File): Intent {
        val uri = OpenRideFileProvider.uriFor(context, apk)
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, APK_MIME_TYPE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private companion object {
        const val UPDATES_DIR = "updates"
        const val APK_MIME_TYPE = "application/vnd.android.package-archive"

        /** The public repo's latest-release endpoint. Unauthenticated — the repo must stay public. */
        const val LATEST_RELEASE_URL =
            "https://api.github.com/repos/digitalducktape/openride/releases/latest"
    }
}
