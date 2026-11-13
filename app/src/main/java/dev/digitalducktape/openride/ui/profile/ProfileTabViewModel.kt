package dev.digitalducktape.openride.ui.profile

import androidx.lifecycle.ViewModel
import dev.digitalducktape.openride.core.backup.BackupRepository
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.importer.WorkoutHistoryCsv
import java.time.ZoneId
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.telemetry.BackupExport
import dev.digitalducktape.openride.core.telemetry.BackupRestore
import dev.digitalducktape.openride.core.telemetry.Consent
import dev.digitalducktape.openride.core.telemetry.ConsentSource
import dev.digitalducktape.openride.core.telemetry.HistoryImport
import dev.digitalducktape.openride.core.telemetry.ImportResult
import dev.digitalducktape.openride.core.telemetry.ImportedBucket
import dev.digitalducktape.openride.core.telemetry.RestoreResult
import dev.digitalducktape.openride.core.telemetry.SuccessResult
import dev.digitalducktape.openride.core.telemetry.Telemetry
import dev.digitalducktape.openride.core.telemetry.TelemetryBuckets
import dev.digitalducktape.openride.core.telemetry.TelemetryConsentStore
import dev.digitalducktape.openride.core.telemetry.TelemetryEnabled
import dev.digitalducktape.openride.core.telemetry.trackSafely
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine

/**
 * Profile nav tab: shows the active rider and offers "Switch rider" (P0-3: "switch rider"
 * reachable from the Profile tab) and backup/restore (PRD P1-8, T15).
 */
class ProfileTabViewModel(
    private val activeProfileHolder: ActiveProfileHolder,
    profileRepository: ProfileRepository,
    private val backupRepository: BackupRepository,
    private val rideRepository: RideRepository,
    private val telemetry: Telemetry,
    private val consentStore: TelemetryConsentStore,
    private val zone: () -> ZoneId = ZoneId::systemDefault,
) : ViewModel() {
    val activeProfile: Flow<Profile?> =
        combine(activeProfileHolder.activeProfileId, profileRepository.observeProfiles()) { id, profiles ->
            profiles.firstOrNull { it.id == id }
        }

    /** The usage-data answer (#85), for the Device group's switch. */
    val consent: StateFlow<Consent> = consentStore.consent

    /** The switch: on stores Granted then announces it; off stores Declined, and nothing is sent. */
    fun setSharing(on: Boolean) {
        if (on) {
            consentStore.set(Consent.Granted)
            telemetry.track(TelemetryEnabled(ConsentSource.SETTINGS))
        } else {
            consentStore.set(Consent.Declined)
        }
    }

    /** Clears the active profile so the caller can navigate back to profile select. */
    fun switchRider() {
        activeProfileHolder.clear()
    }

    /** JSON content for a full-database backup file (PRD P1-8). */
    suspend fun createBackupContent(): String {
        val json = try {
            backupRepository.exportJson()
        } catch (e: Exception) {
            telemetry.trackSafely { BackupExport(SuccessResult.FAILED) }
            throw e
        }
        telemetry.trackSafely { BackupExport(SuccessResult.SUCCESS) }
        return json
    }

    /**
     * Parses and restores [content] as a backup file, replacing the entire current database.
     * Also clears the active profile — ids may now belong to a different rider than before
     * (e.g. restoring onto a fresh install), so the caller should route back to profile
     * select afterward rather than assume the previously active profile still applies.
     * Returns a [Result] so the caller can show a clear error for a malformed/unreadable file
     * instead of crashing on a bad share/import.
     */
    suspend fun restoreFromContent(content: String): Result<Unit> {
        val snapshot = try {
            backupRepository.parse(content)
        } catch (e: Exception) {
            telemetry.trackSafely { BackupRestore(RestoreResult.BAD_FILE) }
            return Result.failure(e)
        }
        return runCatching {
            backupRepository.restore(snapshot)
            activeProfileHolder.clear()
        }.onSuccess {
            telemetry.trackSafely { BackupRestore(RestoreResult.SUCCESS) }
        }.onFailure {
            telemetry.trackSafely { BackupRestore(RestoreResult.FAILED) }
        }
    }

    /**
     * Reads [content] as a Peloton workout-history CSV and adds its cycling workouts to the
     * active rider's history (#83). Fails, changing nothing, when the file isn't that export or
     * no rider is active; the caller shows why.
     */
    suspend fun importWorkoutHistory(content: String): Result<WorkoutImportSummary> {
        val profileId = activeProfileHolder.activeProfileId.value
        if (profileId == null) {
            reportImport(ImportResult.NO_RIDER)
            return Result.failure(IllegalStateException("no rider selected"))
        }
        val history = try {
            WorkoutHistoryCsv.parse(content, zone())
        } catch (e: Exception) {
            reportImport(ImportResult.WRONG_FILE)
            return Result.failure(e)
        }
        return runCatching {
            val outcome = rideRepository.importRides(profileId, history.rides)
            WorkoutImportSummary(
                imported = outcome.imported,
                alreadyThere = outcome.alreadyThere,
                otherWorkouts = history.otherWorkouts,
                unreadableRows = history.unreadableRows,
            )
        }.onSuccess {
            reportImport(ImportResult.SUCCESS, TelemetryBuckets.imported(it.imported), it.alreadyThere > 0)
        }.onFailure {
            reportImport(ImportResult.FAILED)
        }
    }

    private fun reportImport(
        result: ImportResult,
        imported: ImportedBucket = ImportedBucket.ZERO,
        duplicates: Boolean = false,
    ) = telemetry.trackSafely { HistoryImport(result, imported, duplicates) }
}

/**
 * What a history import did, for the Profile tab's row.
 *
 * @param alreadyThere rides the rider's history already had (the same file imported again).
 * @param otherWorkouts workouts that aren't rides (strength, stretching), left out.
 * @param unreadableRows rides without a usable date or length.
 */
data class WorkoutImportSummary(
    val imported: Int,
    val alreadyThere: Int,
    val otherWorkouts: Int,
    val unreadableRows: Int,
)
