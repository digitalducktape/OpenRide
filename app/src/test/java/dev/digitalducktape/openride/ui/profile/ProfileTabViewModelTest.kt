package dev.digitalducktape.openride.ui.profile

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.backup.BackupRepository
import dev.digitalducktape.openride.core.data.OpenRideDatabase
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.data.RideRepository
import java.time.Instant
import java.time.ZoneOffset
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.telemetry.BackupExport
import dev.digitalducktape.openride.core.telemetry.BackupRestore
import dev.digitalducktape.openride.core.telemetry.Consent
import dev.digitalducktape.openride.core.telemetry.HistoryImport
import dev.digitalducktape.openride.core.telemetry.ImportResult
import dev.digitalducktape.openride.core.telemetry.ImportedBucket
import dev.digitalducktape.openride.core.telemetry.RestoreResult
import dev.digitalducktape.openride.core.telemetry.SuccessResult
import dev.digitalducktape.openride.core.telemetry.ConsentSource
import dev.digitalducktape.openride.core.telemetry.InMemoryTelemetryConsentStore
import dev.digitalducktape.openride.core.telemetry.RecordingTelemetry
import dev.digitalducktape.openride.core.telemetry.TelemetryEnabled
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProfileTabViewModelTest {

    private lateinit var db: OpenRideDatabase
    private lateinit var profileRepository: ProfileRepository
    private lateinit var activeProfileHolder: ActiveProfileHolder
    private lateinit var backupRepository: BackupRepository
    private lateinit var rideRepository: RideRepository
    private lateinit var viewModel: ProfileTabViewModel
    private val telemetry = RecordingTelemetry()
    private val consentStore = InMemoryTelemetryConsentStore(Consent.Declined)

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        db = Room.inMemoryDatabaseBuilder(context, OpenRideDatabase::class.java).build()
        profileRepository = ProfileRepository(db.profileDao())
        activeProfileHolder = ActiveProfileHolder(context)
        backupRepository = BackupRepository(db, db.profileDao(), db.rideDao())
        rideRepository = RideRepository(db, db.rideDao())
        viewModel = ProfileTabViewModel(activeProfileHolder, profileRepository, backupRepository, rideRepository, telemetry, consentStore) { ZoneOffset.UTC }
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun `activeProfile resolves the currently active profile`() = runTest {
        val id = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(id)

        val active = viewModel.activeProfile.first { it != null }

        assertEquals("Ed", active?.name)
    }

    @Test
    fun `switchRider clears the active profile`() = runTest {
        val id = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(id)

        viewModel.switchRider()

        assertNull(activeProfileHolder.activeProfileId.value)
    }

    // --- Backup & restore (T15/#15) -----------------------------------------------------------

    @Test
    fun `createBackupContent produces parseable JSON containing the current profiles`() = runTest {
        profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )

        val json = viewModel.createBackupContent()
        val snapshot = backupRepository.parse(json)

        assertEquals(1, snapshot.profiles.size)
        assertEquals("Ed", snapshot.profiles.single().name)
    }

    @Test
    fun `restoreFromContent replaces the database and clears the active profile`() = runTest {
        val originalId = profileRepository.createProfile(
            Profile(name = "Original", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(originalId)

        // A backup created from a separate, throwaway DB — simulating "restore a file from
        // somewhere else" rather than round-tripping this same database.
        val otherDb = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            OpenRideDatabase::class.java,
        ).build()
        val otherProfileRepo = ProfileRepository(otherDb.profileDao())
        val otherBackupRepo = BackupRepository(otherDb, otherDb.profileDao(), otherDb.rideDao())
        otherProfileRepo.createProfile(
            Profile(name = "Restored", avatarEmoji = "🔥", avatarColor = 0xFFAA0000.toInt(), weightKg = null, ftp = null),
        )
        val backupJson = otherBackupRepo.exportJson()
        otherDb.close()

        val result = viewModel.restoreFromContent(backupJson)

        assertTrue(result.isSuccess)
        assertNull(activeProfileHolder.activeProfileId.value)
        val profiles = profileRepository.observeProfiles().first()
        assertEquals(1, profiles.size)
        assertEquals("Restored", profiles.single().name)
    }

    @Test
    fun `restoreFromContent returns failure for malformed content and leaves the database untouched`() = runTest {
        val id = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(id)

        val result = viewModel.restoreFromContent("not valid json")

        assertTrue(result.isFailure)
        assertEquals(id, activeProfileHolder.activeProfileId.value)
        assertEquals(1, profileRepository.observeProfiles().first().size)
    }

    private val historyCsv = listOf(
        "Workout Timestamp,Live/On-Demand,Instructor Name,Length (minutes),Fitness Discipline,Type,Title,Class Timestamp," +
            "Total Output,Avg. Watts,Avg. Resistance,Avg. Cadence (RPM),Avg. Speed (mph),Distance (mi),Calories Burned," +
            "Avg. Heartrate,Avg. Incline,Avg. Pace (min/mi)",
        "2021-02-07 21:10 (PST),On Demand,Sam Example,20,Cycling,Beginner,20 min Beginner Ride,2019-03-21 23:11 (PST),122,101,40%,75,15.88,5.29,165,,,",
        "2021-03-02 19:52 (-08),On Demand,Alex Example,5,Stretching,Stretch,5 min Stretch,2021-02-26 06:00 (-08),,,,,,,13,,,",
        "2021-03-04 07:00 (-08),On Demand,Sam Example,45,Cycling,Climb,45 min Climb Ride,2021-02-26 06:00 (-08),410,152,48%,71,17.2,12.9,520,,,",
    ).joinToString("\n")

    private suspend fun activeRider(name: String = "Ed"): Long {
        val id = profileRepository.createProfile(
            Profile(name = name, avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(id)
        return id
    }

    @Test
    fun `importing a workout history adds its rides to the active rider only`() = runTest {
        val otherId = activeRider("Alex")
        val edId = activeRider("Ed")

        val summary = viewModel.importWorkoutHistory(historyCsv).getOrThrow()

        assertEquals(WorkoutImportSummary(imported = 2, alreadyThere = 0, otherWorkouts = 1, unreadableRows = 0), summary)
        val rides = rideRepository.observeHistory(edId).first()
        assertEquals(listOf(410.0, 122.0), rides.map { it.outputKj })
        assertEquals(Instant.parse("2021-02-08T05:10:00Z").toEpochMilli(), rides.last().startEpochMs)
        assertEquals(1200, rides.last().durationSec)
        assertEquals(165, rides.last().calories)
        assertTrue(rideRepository.observeHistory(otherId).first().isEmpty())
    }

    @Test
    fun `importing the same file again adds nothing`() = runTest {
        val edId = activeRider()
        viewModel.importWorkoutHistory(historyCsv).getOrThrow()

        val again = viewModel.importWorkoutHistory(historyCsv).getOrThrow()

        assertEquals(WorkoutImportSummary(imported = 0, alreadyThere = 2, otherWorkouts = 1, unreadableRows = 0), again)
        assertEquals(2, rideRepository.observeHistory(edId).first().size)
    }

    @Test
    fun `a file that isn't a workout history fails and changes nothing`() = runTest {
        val edId = activeRider()

        assertTrue(viewModel.importWorkoutHistory("date,duration_sec").isFailure)
        assertTrue(rideRepository.observeHistory(edId).first().isEmpty())
    }

    @Test
    fun `importing with no rider selected fails`() = runTest {
        activeProfileHolder.clear()

        assertTrue(viewModel.importWorkoutHistory(historyCsv).isFailure)
    }

    @Test
    fun settingsSwitchOnTracksSettingsSource() {
        viewModel.setSharing(true)
        assertEquals(Consent.Granted, consentStore.consent.value)
        assertEquals(listOf(TelemetryEnabled(ConsentSource.SETTINGS)), telemetry.events)
    }

    @Test
    fun settingsSwitchOffTracksNothing() {
        consentStore.set(Consent.Granted)
        viewModel.setSharing(false)
        assertEquals(Consent.Declined, consentStore.consent.value)
        assertTrue(telemetry.events.isEmpty())
    }

    @Test
    fun `creating a backup reports backup_export success`() = runTest {
        viewModel.createBackupContent()

        assertEquals(listOf(BackupExport(SuccessResult.SUCCESS)), telemetry.events)
    }

    @Test
    fun `a successful manual restore reports success`() = runTest {
        val id = profileRepository.createProfile(
            Profile(name = "Restored", avatarEmoji = "🚴", avatarColor = 1, weightKg = null, ftp = null),
        )
        val backup = backupRepository.exportJson()
        telemetry.clear()

        viewModel.restoreFromContent(backup)

        assertEquals(listOf(BackupRestore(RestoreResult.SUCCESS)), telemetry.events)
    }

    @Test
    fun `restoring an unparseable file reports bad_file`() = runTest {
        viewModel.restoreFromContent("not valid json")

        assertEquals(listOf(BackupRestore(RestoreResult.BAD_FILE)), telemetry.events)
    }

    @Test
    fun `restoring a backup from a newer app reports failed`() = runTest {
        viewModel.restoreFromContent("""{"version":999,"exportedAtEpochMs":1,"profiles":[],"rides":[],"samples":[]}""")

        assertEquals(listOf(BackupRestore(RestoreResult.FAILED)), telemetry.events)
    }

    @Test
    fun `a history import reports its bucket and no duplicates`() = runTest {
        activeRider()

        viewModel.importWorkoutHistory(historyCsv)

        assertEquals(listOf(HistoryImport(ImportResult.SUCCESS, ImportedBucket.N1_10, duplicates = false)), telemetry.events)
    }

    @Test
    fun `importing the same history again reports duplicates`() = runTest {
        activeRider()
        viewModel.importWorkoutHistory(historyCsv)
        telemetry.clear()

        viewModel.importWorkoutHistory(historyCsv)

        assertEquals(listOf(HistoryImport(ImportResult.SUCCESS, ImportedBucket.ZERO, duplicates = true)), telemetry.events)
    }

    @Test
    fun `importing a file that is not a workout history reports wrong_file`() = runTest {
        activeRider()

        viewModel.importWorkoutHistory("date,duration_sec")

        assertEquals(listOf(HistoryImport(ImportResult.WRONG_FILE, ImportedBucket.ZERO, duplicates = false)), telemetry.events)
    }

    @Test
    fun `importing with no rider reports no_rider`() = runTest {
        activeProfileHolder.clear()

        viewModel.importWorkoutHistory(historyCsv)

        assertEquals(listOf(HistoryImport(ImportResult.NO_RIDER, ImportedBucket.ZERO, duplicates = false)), telemetry.events)
    }
}
