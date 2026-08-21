package dev.digitalducktape.openride.core.backup

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.MediaStore

/**
 * [AutoBackupStore] backed by shared storage: `Download/OpenRide/` via
 * [MediaStore.Downloads] (the scoped-storage-sanctioned way to write there on the tablet's
 * Android 10/11 — no storage permission needed for the app's own files). MediaStore.Downloads
 * and RELATIVE_PATH/IS_PENDING all arrived in API 29, so this works on the oldest firmware
 * the app supports.
 *
 * Downloads is deliberately chosen over the app's private dirs because it survives an
 * uninstall (feedback: "no data loss when the app is updated"). Two recovery paths:
 *
 * - Same install (app data cleared, in-place update gone wrong): [readLatest] finds the
 *   file through MediaStore and [AutoBackupManager] restores silently on launch.
 * - Full uninstall/reinstall: MediaStore ownership of the old row is severed, so
 *   [readLatest] comes back empty — but the file itself is still sitting in Downloads,
 *   where the Profile tab's existing "Restore from file" picker (SAF) can open it.
 *
 * The file name carries the package id ([fileNameFor]) because MediaStore scopes Downloads
 * queries to the *owning* app: the mock and `.real` sensor builds coexist on the tablet, and
 * with one shared name the second one can neither see nor overwrite the first's file — it
 * silently gets `openride-autobackup (1).json` instead, so the backups become
 * indistinguishable from each other. One file per package keeps each build's history its own
 * and still stable across that package's reinstalls.
 */
class MediaStoreAutoBackupStore(context: Context) : AutoBackupStore {
    private val resolver = context.applicationContext.contentResolver
    private val fileName = fileNameFor(context.applicationContext.packageName)

    override fun write(json: String): Boolean = runCatching {
        val uri = findExisting() ?: insertNew() ?: return false
        resolver.openOutputStream(uri, "wt")?.use { out ->
            out.write(json.toByteArray(Charsets.UTF_8))
        } ?: return false
        // Clear IS_PENDING unconditionally: cheap, and correct for both fresh rows and
        // overwrites (where it's already 0).
        resolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
        true
    }.getOrDefault(false)

    override fun readLatest(): String? = runCatching {
        findExisting()?.let { uri ->
            resolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
        }
    }.getOrNull()

    private fun findExisting(): Uri? = resolver.query(
        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
        arrayOf(MediaStore.Downloads._ID),
        "${MediaStore.Downloads.DISPLAY_NAME} = ?",
        arrayOf(fileName),
        null,
    )?.use { cursor ->
        if (cursor.moveToFirst()) {
            ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cursor.getLong(0))
        } else {
            null
        }
    }

    private fun insertNew(): Uri? = resolver.insert(
        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
        ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, "application/json")
            put(MediaStore.Downloads.RELATIVE_PATH, RELATIVE_PATH)
            put(MediaStore.Downloads.IS_PENDING, 1)
        },
    )

    companion object {
        const val RELATIVE_PATH = "Download/OpenRide/"

        /** Backup file name for [packageName] — see the class doc for why it's namespaced. */
        fun fileNameFor(packageName: String) = "openride-autobackup-$packageName.json"
    }
}
