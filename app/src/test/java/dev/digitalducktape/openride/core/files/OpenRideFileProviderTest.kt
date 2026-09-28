package dev.digitalducktape.openride.core.files

import android.content.Context
import androidx.core.content.FileProvider
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The Godot AAR declares its own `androidx.core.content.FileProvider` at
 * `${applicationId}.fileprovider` (Godot's `GodotIO` hard-codes that authority). The app's
 * provider is an [OpenRideFileProvider] subclass at its own authority so the manifest merger
 * keeps both, each with its own paths file. These run against the merged manifest, so they
 * fail if either provider (or either paths file) is lost in the merge.
 */
@RunWith(AndroidJUnit4::class)
class OpenRideFileProviderTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Before
    fun setUp() {
        FileProviderCache.clear()
    }

    private fun cacheFile(subdir: String, name: String): File =
        File(File(context.cacheDir, subdir).apply { mkdirs() }, name).apply { writeText("x") }

    @Test
    fun `authority is the app's own, distinct from Godot's`() {
        assertEquals("${context.packageName}.files", OpenRideFileProvider.authority(context))
        assertNotEquals("${context.packageName}.fileprovider", OpenRideFileProvider.authority(context))
    }

    @Test
    fun `ride exports resolve to a content uri`() {
        val uri = OpenRideFileProvider.uriFor(context, cacheFile("exports", "ride.tcx"))

        assertEquals("content", uri.scheme)
        assertEquals(OpenRideFileProvider.authority(context), uri.authority)
        assertEquals("/exports/ride.tcx", uri.path)
    }

    @Test
    fun `downloaded update apks resolve to a content uri`() {
        val uri = OpenRideFileProvider.uriFor(context, cacheFile("updates", "openride-7.apk"))

        assertEquals(OpenRideFileProvider.authority(context), uri.authority)
        assertEquals("/updates/openride-7.apk", uri.path)
    }

    @Test
    fun `avatar captures resolve to a content uri`() {
        val uri = OpenRideFileProvider.uriFor(context, cacheFile("avatar_capture", "raw.jpg"))

        assertEquals("/avatar_capture/raw.jpg", uri.path)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `files outside the app's paths are refused`() {
        // filesDir is only exposed by Godot's paths file, never by the app's.
        val file = File(context.filesDir, "avatars/1.jpg").apply {
            parentFile?.mkdirs()
            writeText("x")
        }
        OpenRideFileProvider.uriFor(context, file)
    }

    @Test
    fun `Godot's provider keeps its own paths at its own authority`() {
        val file = File(context.filesDir, "godot.txt").apply { writeText("x") }

        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)

        assertEquals("${context.packageName}.fileprovider", uri.authority)
        assertEquals("/filesRoot/godot.txt", uri.path)
    }
}
