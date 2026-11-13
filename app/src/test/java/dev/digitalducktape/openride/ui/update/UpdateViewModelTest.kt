package dev.digitalducktape.openride.ui.update

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.content.FeedFetcher
import dev.digitalducktape.openride.core.telemetry.RecordingTelemetry
import dev.digitalducktape.openride.core.telemetry.UpdateAction
import dev.digitalducktape.openride.core.telemetry.UpdatePrompt
import dev.digitalducktape.openride.core.update.UpdateRepository
import java.io.IOException
import java.io.InputStream
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class UpdateViewModelTest {

    private val apkUrl = "https://github.com/digitalducktape/openride/releases/download/v0.7.0/openride-real-7.apk"
    private val releaseBody =
        """{"tag_name":"v0.7.0","body":"New","assets":[{"name":"openride-real-7.apk","browser_download_url":"$apkUrl"}]}"""

    private class Fetcher(val releaseBody: String?, val apk: String? = null) : FeedFetcher {
        override fun fetch(url: String): InputStream = when {
            url.endsWith("/releases/latest") -> (releaseBody ?: throw IOException("offline")).byteInputStream()
            else -> (apk ?: throw IOException("no apk")).byteInputStream()
        }
    }

    private fun viewModel(fetcher: FeedFetcher, telemetry: RecordingTelemetry): UpdateViewModel {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return UpdateViewModel(
            UpdateRepository(context, fetcher),
            currentVersionCode = 1,
            currentVersionName = "0.1.0",
            assetInfix = "real",
            telemetry = telemetry,
        )
    }

    @Test
    fun `an available update reports update_prompt shown`() = runTest {
        val telemetry = RecordingTelemetry()

        viewModel(Fetcher(releaseBody), telemetry).checkForUpdate()

        assertEquals(listOf(UpdatePrompt(UpdateAction.SHOWN)), telemetry.events)
    }

    @Test
    fun `being up to date or offline reports no prompt`() = runTest {
        val telemetry = RecordingTelemetry()

        viewModel(Fetcher(null), telemetry).checkForUpdate()

        assertEquals(emptyList<Any>(), telemetry.events)
    }

    @Test
    fun `tapping install on a downloaded update reports install_tapped`() = runTest {
        val telemetry = RecordingTelemetry()
        val vm = viewModel(Fetcher(releaseBody, apk = "apk"), telemetry)
        vm.checkForUpdate()
        vm.downloadUpdate()
        telemetry.clear()

        vm.installIntent()

        assertEquals(listOf(UpdatePrompt(UpdateAction.INSTALL_TAPPED)), telemetry.events)
    }

    @Test
    fun `install with nothing downloaded reports nothing`() = runTest {
        val telemetry = RecordingTelemetry()

        viewModel(Fetcher(releaseBody), telemetry).installIntent()

        assertEquals(emptyList<Any>(), telemetry.events)
    }
}
