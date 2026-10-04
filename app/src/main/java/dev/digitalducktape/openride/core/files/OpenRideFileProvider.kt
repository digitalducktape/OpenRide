package dev.digitalducktape.openride.core.files

import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

/**
 * The app's own [FileProvider], backed by `res/xml/file_paths.xml`: ride exports (share sheet),
 * downloaded update APKs (package installer) and raw avatar captures (camera app).
 *
 * A subclass rather than a plain `androidx.core.content.FileProvider` entry because the Godot
 * engine AAR (mini-games, #32) declares that class itself at `${applicationId}.fileprovider`
 * with its own `@xml/godot_provider_paths`, and Godot's `GodotIO` hard-codes that authority.
 * The manifest merger keys `<provider>` elements by class name, so a distinct class plus a
 * distinct [authority] lets both providers and both paths files coexist.
 */
class OpenRideFileProvider : FileProvider() {
    companion object {
        /** Must match `android:authorities` for this provider in `AndroidManifest.xml`. */
        fun authority(context: Context): String = "${context.packageName}.files"

        /**
         * A `content://` URI for [file], which must sit under one of the `file_paths.xml`
         * roots (throws [IllegalArgumentException] otherwise).
         */
        fun uriFor(context: Context, file: File): Uri =
            getUriForFile(context, authority(context), file)
    }
}
