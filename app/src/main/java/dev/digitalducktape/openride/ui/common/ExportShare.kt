package dev.digitalducktape.openride.ui.common

import android.content.Context
import android.content.Intent
import dev.digitalducktape.openride.core.files.OpenRideFileProvider
import java.io.File

/**
 * Writes exported file content (TCX/CSV, PRD P1-1/P1-2) to a cache file and hands it to
 * Android's share sheet via a `content://` URI from the app's [OpenRideFileProvider] — plain `file://`
 * URIs are blocked by `StrictMode`/`FileUriExposedException` on the app's target API level, so
 * a provider is required for any cross-app share. See `res/xml/file_paths.xml` and the
 * `<provider>` entry in `AndroidManifest.xml` for the backing config.
 */
object ExportShare {
    private const val EXPORTS_SUBDIR = "exports"

    /**
     * Writes [content] to a cache file named [fileName] (overwriting any previous export of
     * the same name) and launches the system share chooser for it as [mimeType].
     */
    fun share(context: Context, fileName: String, content: String, mimeType: String) {
        val exportsDir = File(context.cacheDir, EXPORTS_SUBDIR).apply { mkdirs() }
        val file = File(exportsDir, fileName)
        file.writeText(content)

        val uri = OpenRideFileProvider.uriFor(context, file)
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(sendIntent, "Export ride").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK.takeIf { context !is android.app.Activity } ?: 0)
        })
    }
}
