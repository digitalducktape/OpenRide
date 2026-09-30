package dev.digitalducktape.openride.core.data

import android.content.Context
import androidx.room.Room
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Verifies the migrations, starting with [MIGRATION_1_2] (T17/#17 — BLE heart rate: adds `profiles.pairedHrDeviceAddress`
 * and `ride_samples.heartRateBpm`).
 *
 * Drives the migration directly against a real SQLite database built at the version-1 schema,
 * rather than Room's [androidx.room.testing.MigrationTestHelper]. MigrationTestHelper loads the
 * exported schema JSON from *assets*, which Robolectric unit tests (src/test, no device) do not
 * reliably serve; building the v1 tables here and calling `MIGRATION_1_2.migrate` exercises the
 * exact same migration SQL without that packaging dependency.
 */
@RunWith(AndroidJUnit4::class)
class DatabaseMigrationTest {

    private val context: Context = ApplicationProvider.getApplicationContext()
    private var helper: SupportSQLiteOpenHelper? = null

    /**
     * Opens a fresh database created at the version-1 schema (verbatim from 1.json): in memory,
     * or in the file [name].
     */
    private fun openV1Database(name: String? = null): SupportSQLiteDatabase {
        val callback = object : SupportSQLiteOpenHelper.Callback(1) {
            override fun onCreate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `profiles` (`id` INTEGER PRIMARY KEY AUTOINCREMENT " +
                        "NOT NULL, `name` TEXT NOT NULL, `avatarEmoji` TEXT NOT NULL, " +
                        "`avatarColor` INTEGER NOT NULL, `weightKg` REAL, `ftp` INTEGER)",
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `rides` (`id` INTEGER PRIMARY KEY AUTOINCREMENT " +
                        "NOT NULL, `profileId` INTEGER NOT NULL, `startEpochMs` INTEGER NOT NULL, " +
                        "`durationSec` INTEGER NOT NULL, `avgCadence` INTEGER NOT NULL, " +
                        "`maxCadence` INTEGER NOT NULL, `avgPower` INTEGER NOT NULL, " +
                        "`maxPower` INTEGER NOT NULL, `avgResistance` INTEGER NOT NULL, " +
                        "`outputKj` REAL NOT NULL, `calories` INTEGER, " +
                        "FOREIGN KEY(`profileId`) REFERENCES `profiles`(`id`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_rides_profileId` ON `rides` (`profileId`)")
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `ride_samples` (`rideId` INTEGER NOT NULL, " +
                        "`tSec` INTEGER NOT NULL, `cadence` INTEGER NOT NULL, " +
                        "`resistance` INTEGER NOT NULL, `power` INTEGER NOT NULL, " +
                        "PRIMARY KEY(`rideId`, `tSec`), FOREIGN KEY(`rideId`) REFERENCES " +
                        "`rides`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
            }

            override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                // no-op: the test applies MIGRATION_1_2 explicitly
            }
        }
        val config = SupportSQLiteOpenHelper.Configuration.builder(context)
            .name(name) // null: in-memory
            .callback(callback)
            .build()
        return FrameworkSQLiteOpenHelperFactory().create(config)
            .also { helper = it }
            .writableDatabase
    }

    @After
    fun tearDown() {
        helper?.close()
    }

    @Test
    fun `migrate 1 to 2 preserves existing rows and adds the new nullable columns`() {
        val db = openV1Database()
        db.execSQL(
            "INSERT INTO profiles (id, name, avatarEmoji, avatarColor, weightKg, ftp) " +
                "VALUES (1, 'Ed', '🚴', -16711936, 80.0, 220)",
        )
        db.execSQL(
            "INSERT INTO rides (id, profileId, startEpochMs, durationSec, avgCadence, maxCadence, " +
                "avgPower, maxPower, avgResistance, outputKj, calories) " +
                "VALUES (1, 1, 1700000000000, 1800, 85, 100, 150, 300, 45, 270.0, 260)",
        )
        db.execSQL(
            "INSERT INTO ride_samples (rideId, tSec, cadence, resistance, power) " +
                "VALUES (1, 0, 85, 45, 150)",
        )

        MIGRATION_1_2.migrate(db)

        db.query("SELECT name, pairedHrDeviceAddress FROM profiles WHERE id = 1").use {
            assertEquals(true, it.moveToFirst())
            assertEquals("Ed", it.getString(it.getColumnIndexOrThrow("name")))
            assertEquals(true, it.isNull(it.getColumnIndexOrThrow("pairedHrDeviceAddress")))
        }
        db.query("SELECT power, heartRateBpm FROM ride_samples WHERE rideId = 1 AND tSec = 0").use {
            assertEquals(true, it.moveToFirst())
            assertEquals(150, it.getInt(it.getColumnIndexOrThrow("power")))
            assertEquals(true, it.isNull(it.getColumnIndexOrThrow("heartRateBpm")))
        }
    }

    @Test
    fun `migrate 2 to 3 preserves rides and adds a null videoId`() {
        val db = openV1Database()
        MIGRATION_1_2.migrate(db)
        db.execSQL(
            "INSERT INTO profiles (id, name, avatarEmoji, avatarColor, weightKg, ftp) " +
                "VALUES (1, 'Ed', '🚴', -16711936, NULL, NULL)",
        )
        db.execSQL(
            "INSERT INTO rides (id, profileId, startEpochMs, durationSec, avgCadence, maxCadence, " +
                "avgPower, maxPower, avgResistance, outputKj, calories) " +
                "VALUES (1, 1, 1700000000000, 1800, 85, 100, 150, 300, 45, 270.0, 260)",
        )

        MIGRATION_2_3.migrate(db)

        db.query("SELECT outputKj, videoId FROM rides WHERE id = 1").use {
            assertEquals(true, it.moveToFirst())
            assertEquals(270.0, it.getDouble(it.getColumnIndexOrThrow("outputKj")), 0.001)
            assertEquals(true, it.isNull(it.getColumnIndexOrThrow("videoId")))
        }

        db.execSQL(
            "INSERT INTO rides (id, profileId, startEpochMs, durationSec, avgCadence, maxCadence, " +
                "avgPower, maxPower, avgResistance, outputKj, calories, videoId) " +
                "VALUES (2, 1, 1700000100000, 600, 70, 80, 100, 120, 30, 60.0, 58, 'dQw4w9WgXcQ')",
        )
        db.query("SELECT videoId FROM rides WHERE id = 2").use {
            assertEquals(true, it.moveToFirst())
            assertEquals("dQw4w9WgXcQ", it.getString(it.getColumnIndexOrThrow("videoId")))
        }
    }

    @Test
    fun `migrate 3 to 4 preserves profiles and adds a null avatarPhotoPath`() {
        val db = openV1Database()
        MIGRATION_1_2.migrate(db)
        MIGRATION_2_3.migrate(db)
        db.execSQL(
            "INSERT INTO profiles (id, name, avatarEmoji, avatarColor, weightKg, ftp) " +
                "VALUES (1, 'Ed', '🚴', -16711936, 80.0, 220)",
        )

        MIGRATION_3_4.migrate(db)

        db.query("SELECT name, weightKg, avatarPhotoPath FROM profiles WHERE id = 1").use {
            assertEquals(true, it.moveToFirst())
            assertEquals("Ed", it.getString(it.getColumnIndexOrThrow("name")))
            assertEquals(80.0, it.getDouble(it.getColumnIndexOrThrow("weightKg")), 0.001)
            assertEquals(true, it.isNull(it.getColumnIndexOrThrow("avatarPhotoPath")))
        }

        db.execSQL(
            "INSERT INTO profiles (id, name, avatarEmoji, avatarColor, weightKg, ftp, avatarPhotoPath) " +
                "VALUES (2, 'Kid', '🤖', -65536, NULL, NULL, '/data/avatars/kid.jpg')",
        )
        db.query("SELECT avatarPhotoPath FROM profiles WHERE id = 2").use {
            assertEquals(true, it.moveToFirst())
            assertEquals("/data/avatars/kid.jpg", it.getString(it.getColumnIndexOrThrow("avatarPhotoPath")))
        }
    }

    @Test
    fun `migrate 1 to 2 lets new rows populate both new columns`() {
        val db = openV1Database()

        MIGRATION_1_2.migrate(db)

        db.execSQL(
            "INSERT INTO profiles (id, name, avatarEmoji, avatarColor, weightKg, ftp, " +
                "pairedHrDeviceAddress) VALUES (1, 'Ed', '🚴', -16711936, NULL, NULL, " +
                "'AA:BB:CC:DD:EE:FF')",
        )
        db.execSQL(
            "INSERT INTO rides (id, profileId, startEpochMs, durationSec, avgCadence, maxCadence, " +
                "avgPower, maxPower, avgResistance, outputKj, calories) " +
                "VALUES (1, 1, 0, 60, 90, 90, 150, 150, 50, 9.0, 9)",
        )
        db.execSQL(
            "INSERT INTO ride_samples (rideId, tSec, cadence, resistance, power, heartRateBpm) " +
                "VALUES (1, 0, 90, 50, 150, 142)",
        )

        db.query("SELECT pairedHrDeviceAddress FROM profiles WHERE id = 1").use {
            assertEquals(true, it.moveToFirst())
            assertEquals("AA:BB:CC:DD:EE:FF", it.getString(it.getColumnIndexOrThrow("pairedHrDeviceAddress")))
        }
        db.query("SELECT heartRateBpm FROM ride_samples WHERE rideId = 1 AND tSec = 0").use {
            assertEquals(true, it.moveToFirst())
            assertEquals(142, it.getInt(it.getColumnIndexOrThrow("heartRateBpm")))
        }
    }

    @Test
    fun `migration 4 to 5 creates an empty content_sources table`() {
        val db = openV1Database()
        MIGRATION_1_2.migrate(db)
        MIGRATION_2_3.migrate(db)
        MIGRATION_3_4.migrate(db)

        MIGRATION_4_5.migrate(db)

        db.query("SELECT COUNT(*) FROM content_sources").use { cursor ->
            cursor.moveToFirst()
            assertEquals(0, cursor.getInt(0))
        }
        db.query("PRAGMA table_info(content_sources)").use { cursor ->
            val columns = buildList {
                while (cursor.moveToNext()) add(cursor.getString(cursor.getColumnIndexOrThrow("name")))
            }
            assertEquals(
                listOf("id", "sourceType", "youtubeId", "displayName", "category", "builtIn", "hidden", "position"),
                columns,
            )
        }
    }

    @Test
    fun `migrate 5 to 6 adds the game columns and an empty game_results table`() {
        val db = openV1Database()
        MIGRATION_1_2.migrate(db)
        MIGRATION_2_3.migrate(db)
        MIGRATION_3_4.migrate(db)
        MIGRATION_4_5.migrate(db)
        db.execSQL(
            "INSERT INTO profiles (id, name, avatarEmoji, avatarColor, weightKg, ftp) " +
                "VALUES (1, 'Ed', '🚴', -16711936, 80.0, 220)",
        )
        db.execSQL(
            "INSERT INTO rides (id, profileId, startEpochMs, durationSec, avgCadence, maxCadence, " +
                "avgPower, maxPower, avgResistance, outputKj, calories, videoId) " +
                "VALUES (1, 1, 1700000000000, 1800, 85, 100, 150, 300, 45, 270.0, 260, 'abc')",
        )

        MIGRATION_5_6.migrate(db)

        db.query("SELECT ftp, headCalibration FROM profiles WHERE id = 1").use {
            assertEquals(true, it.moveToFirst())
            assertEquals(220, it.getInt(it.getColumnIndexOrThrow("ftp")))
            assertEquals(true, it.isNull(it.getColumnIndexOrThrow("headCalibration")))
        }
        db.query("SELECT videoId, gamePlan FROM rides WHERE id = 1").use {
            assertEquals(true, it.moveToFirst())
            assertEquals("abc", it.getString(it.getColumnIndexOrThrow("videoId")))
            assertEquals(true, it.isNull(it.getColumnIndexOrThrow("gamePlan")))
        }
        db.query("PRAGMA table_info(game_results)").use { cursor ->
            val columns = buildList {
                while (cursor.moveToNext()) add(cursor.getString(cursor.getColumnIndexOrThrow("name")))
            }
            assertEquals(
                listOf(
                    "rideId", "segmentIndex", "gameId", "role", "difficulty", "startSec", "durationSec",
                    "score", "stars", "won", "skipped", "statsJson",
                ),
                columns,
            )
        }

        // A result cascades away with its ride.
        db.execSQL("PRAGMA foreign_keys = ON")
        db.execSQL(
            "INSERT INTO game_results (rideId, segmentIndex, gameId, role, difficulty, startSec, " +
                "durationSec, score, stars, won, skipped, statsJson) " +
                "VALUES (1, 0, 'demo', 'free', 'standard', 0, 1200, 900.0, 2, NULL, 0, '{}')",
        )
        db.execSQL("DELETE FROM rides WHERE id = 1")
        db.query("SELECT COUNT(*) FROM game_results").use {
            it.moveToFirst()
            assertEquals(0, it.getInt(0))
        }
    }

    @Test
    fun `a version-1 database migrates to the schema Room expects at version 6`() = runTest {
        val name = "migration-chain-test.db"
        context.deleteDatabase(name)
        openV1Database(name).execSQL(
            "INSERT INTO profiles (id, name, avatarEmoji, avatarColor, weightKg, ftp) " +
                "VALUES (1, 'Ed', '🚴', -16711936, 80.0, 220)",
        )
        helper?.close()
        helper = null

        // Room validates every table against its entities on open, so a migration that misses
        // a column, an index or a foreign key fails here.
        val room = Room.databaseBuilder(context, OpenRideDatabase::class.java, name)
            .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6)
            .allowMainThreadQueries()
            .build()
        try {
            val profile = room.profileDao().getById(1)
            assertEquals("Ed", profile?.name)
            assertNull(profile?.headCalibration)
            assertEquals(emptyList<GameResult>(), room.gameResultDao().getAllOnce())
        } finally {
            room.close()
            context.deleteDatabase(name)
        }
    }
}
