package dev.digitalducktape.openride.core.backup

import dev.digitalducktape.openride.core.telemetry.AutoBackupFailed
import dev.digitalducktape.openride.core.telemetry.NoOpTelemetry
import dev.digitalducktape.openride.core.telemetry.Telemetry
import dev.digitalducktape.openride.core.telemetry.trackSafely
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Keeps a rolling automatic backup of the whole database (feedback: "save user data locally
 * so when the app is updated there is no data loss") — the existing manual Back Up button
 * only helps if someone remembers to press it.
 *
 * On [start]:
 * 1. If the database is completely empty (fresh install / cleared data) and a previous
 *    automatic backup is readable, restore it silently — an update should feel like nothing
 *    happened.
 * 2. Then watch [dataChanges] and rewrite the automatic backup [debounceMs] after things
 *    settle, so every finished ride and profile edit lands in the backup without writing
 *    mid-burst.
 *
 * An empty database never overwrites the stored backup (see [writeBackupUnlessEmpty]) —
 * that one rule is what makes the whole thing safe, since the dangerous case is a launch
 * where the data is missing *and* the restore didn't take (unreadable file, storage
 * hiccup): writing then would replace the last good backup with nothing.
 *
 * Other failures are swallowed by design: an automatic safety net must never crash the app
 * or block a ride; the manual backup/restore path remains for deliberate recovery.
 */
class AutoBackupManager(
    private val backupRepository: BackupRepository,
    private val store: AutoBackupStore,
    private val scope: CoroutineScope,
    private val dataChanges: Flow<Any?>,
    private val isDatabaseEmpty: suspend () -> Boolean,
    private val debounceMs: Long = DEFAULT_DEBOUNCE_MS,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val telemetry: Telemetry = NoOpTelemetry,
) {
    /** `auto_backup_failed` is sent at most once per process (this is a process-wide singleton). */
    private val failureReported = AtomicBoolean(false)

    @OptIn(FlowPreview::class)
    fun start() {
        scope.launch {
            restoreIfEmpty()
            // The first emission describes the state at launch, and is deliberately *not*
            // dropped: it captures data that predates automatic backups, and dropping it
            // would race with changes that land before collection starts (a conflating
            // source folds those into the first emission, losing them entirely).
            dataChanges
                .debounce(debounceMs)
                .collect {
                    val written = try {
                        writeBackupUnlessEmpty()
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Throwable) {
                        false
                    }
                    if (!written) reportFailureOnce()
                }
        }
    }

    private suspend fun restoreIfEmpty() {
        runCatching {
            if (!isDatabaseEmpty()) return
            val latest = withContext(ioDispatcher) { store.readLatest() } ?: return
            backupRepository.restore(backupRepository.parse(latest))
        }
    }

    private fun reportFailureOnce() {
        if (failureReported.compareAndSet(false, true)) telemetry.trackSafely { AutoBackupFailed }
    }

    /** `false` when the store refused (or threw, via the caller); an empty database is not a failure. */
    private suspend fun writeBackupUnlessEmpty(): Boolean {
        if (isDatabaseEmpty()) return true
        // The store reads/writes shared storage, so it's blocking IO — never run it on the
        // container scope's default (CPU-bound) dispatcher.
        val json = backupRepository.exportJson()
        return withContext(ioDispatcher) { store.write(json) }
    }

    companion object {
        const val DEFAULT_DEBOUNCE_MS = 5_000L
    }
}
