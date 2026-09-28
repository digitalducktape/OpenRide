package dev.digitalducktape.openride.core.update

import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.content.FeedFetcher
import dev.digitalducktape.openride.core.files.FileProviderCache
import java.io.File
import java.io.IOException
import java.io.InputStream
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Fetch/download behaviour of the GitHub-native self-updater (PRD #22/T22) against a fake
 * [FeedFetcher] — no network. Robolectric supplies the [Context] the repository needs for its
 * cache dir and the FileProvider-backed install intent.
 */
@RunWith(AndroidJUnit4::class)
class UpdateRepositoryTest {

    private lateinit var context: Context

    private class FakeFetcher(
        private val responses: MutableMap<String, String> = mutableMapOf(),
        var failWith: IOException? = null,
    ) : FeedFetcher {
        val requested = mutableListOf<String>()

        fun respond(url: String, body: String) { responses[url] = body }

        override fun fetch(url: String): InputStream {
            requested.add(url)
            failWith?.let { throw it }
            val body = responses[url] ?: throw IOException("no fixture for $url")
            return body.byteInputStream()
        }
    }

    // The repository's hardcoded endpoint (kept in sync with UpdateRepository.LATEST_RELEASE_URL).
    private val latestReleaseUrl = "https://api.github.com/repos/digitalducktape/openride/releases/latest"
    private val apkUrl = "https://github.com/digitalducktape/openride/releases/download/v0.7.0/openride-real-7.apk"
    private val releaseBody =
        """{"tag_name":"v0.7.0","body":"New","assets":[{"name":"openride-real-7.apk","browser_download_url":"$apkUrl"}]}"""

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        File(context.cacheDir, "updates").deleteRecursively()
        FileProviderCache.clear()
    }

    @Test
    fun `check reports an available update from the latest release`() = runTest {
        val fetcher = FakeFetcher().apply { respond(latestReleaseUrl, releaseBody) }
        val repository = UpdateRepository(context, fetcher)

        val result = repository.check(currentVersionCode = 1, assetInfix = "real")

        assertTrue(result is UpdateCheckResult.Available)
        assertEquals(7, (result as UpdateCheckResult.Available).update.versionCode)
        assertEquals(listOf(latestReleaseUrl), fetcher.requested)
    }

    @Test
    fun `check reports up to date when the installed build is current`() = runTest {
        val fetcher = FakeFetcher().apply { respond(latestReleaseUrl, releaseBody) }
        val repository = UpdateRepository(context, fetcher)

        val result = repository.check(currentVersionCode = 7, assetInfix = "real")

        assertEquals(UpdateCheckResult.UpToDate(7), result)
    }

    @Test
    fun `check fails gracefully when GitHub can't be reached`() = runTest {
        val fetcher = FakeFetcher(failWith = IOException("no network"))
        val repository = UpdateRepository(context, fetcher)

        val result = repository.check(currentVersionCode = 1, assetInfix = "real")

        assertEquals(UpdateCheckResult.Failed("Couldn't reach GitHub releases"), result)
    }

    @Test
    fun `downloadApk writes the APK into the app's own cache`() = runTest {
        val fetcher = FakeFetcher().apply { respond(apkUrl, "APK-BYTES") }
        val repository = UpdateRepository(context, fetcher)
        val update = AvailableUpdate(versionCode = 7, versionName = "0.7.0", apkUrl = apkUrl)

        val file = repository.downloadApk(update)

        assertNotNull(file)
        assertTrue(file!!.exists())
        assertEquals("APK-BYTES", file.readText())
        assertEquals("openride-7.apk", file.name)
        // Stays inside the app's cache dir — never anywhere the user or another app can swap it.
        assertTrue(file.canonicalPath.startsWith(context.cacheDir.canonicalPath))
    }

    @Test
    fun `a failed download returns null and leaves no partial file behind`() = runTest {
        val fetcher = FakeFetcher(failWith = IOException("connection reset"))
        val repository = UpdateRepository(context, fetcher)
        val update = AvailableUpdate(versionCode = 7, versionName = "0.7.0", apkUrl = apkUrl)

        val file = repository.downloadApk(update)

        assertNull(file)
        assertFalse(File(File(context.cacheDir, "updates"), "openride-7.apk").exists())
    }

    @Test
    fun `installIntentFor targets the package installer and grants read access`() = runTest {
        val fetcher = FakeFetcher().apply { respond(apkUrl, "APK-BYTES") }
        val repository = UpdateRepository(context, fetcher)
        val update = AvailableUpdate(versionCode = 7, versionName = "0.7.0", apkUrl = apkUrl)
        val file = repository.downloadApk(update)!!

        val intent = repository.installIntentFor(file)

        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertEquals("application/vnd.android.package-archive", intent.type)
        assertTrue(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
        // A content:// URI via FileProvider, never a file:// path.
        assertEquals("content", intent.data?.scheme)
        // The app's own provider, not the Godot engine's `.fileprovider` (see OpenRideFileProvider).
        assertEquals("${context.packageName}.files", intent.data?.authority)
    }
}
