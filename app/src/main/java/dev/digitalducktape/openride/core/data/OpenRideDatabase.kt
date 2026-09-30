package dev.digitalducktape.openride.core.data

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import dev.digitalducktape.openride.core.content.ContentSource
import dev.digitalducktape.openride.core.content.ContentSourceDao

@Database(
    entities = [Profile::class, Ride::class, RideSample::class, ContentSource::class, GameResult::class],
    version = 6,
    exportSchema = true,
)
abstract class OpenRideDatabase : RoomDatabase() {
    abstract fun profileDao(): ProfileDao
    abstract fun rideDao(): RideDao
    abstract fun contentSourceDao(): ContentSourceDao
    abstract fun gameResultDao(): GameResultDao

    companion object {
        const val DATABASE_NAME = "openride.db"
    }
}

/**
 * Adds BLE heart-rate support (PRD P1-4, T17): a per-rider paired-strap address on
 * [Profile], and a per-second optional heart rate reading on [RideSample]. Both are nullable
 * columns with no default-value backfill needed — every existing row simply reads back
 * `null` (no strap paired / no HR recorded), which is exactly the "not paired yet" state for
 * data that predates this feature.
 */
val MIGRATION_1_2 = object : androidx.room.migration.Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE profiles ADD COLUMN pairedHrDeviceAddress TEXT")
        db.execSQL("ALTER TABLE ride_samples ADD COLUMN heartRateBpm INTEGER")
    }
}

/**
 * Records which class a ride played ([Ride.videoId], v2 in-app player) so the Classes tab
 * can badge already-taken videos. Nullable with no backfill: every pre-existing ride —
 * including v1 rides that launched the YouTube app, where the app never knew when playback
 * ended — reads back `null`, i.e. "no class attached".
 */
val MIGRATION_2_3 = object : androidx.room.migration.Migration(2, 3) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE rides ADD COLUMN videoId TEXT")
    }
}

/**
 * Adds camera profile photos ([Profile.avatarPhotoPath]): the absolute path of the rider's
 * cropped avatar photo on disk. Nullable with no backfill — every existing profile reads back
 * `null`, i.e. "still using the emoji avatar".
 */
val MIGRATION_3_4 = object : androidx.room.migration.Migration(3, 4) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE profiles ADD COLUMN avatarPhotoPath TEXT")
    }
}

/**
 * Adds the rider-manageable Classes catalog (`content_sources`): the channel list moves out
 * of the hard-coded `ChannelConfig` object so channels and playlists can be added and hidden
 * at runtime. The table is created empty and seeded on first access by
 * [dev.digitalducktape.openride.core.content.ContentSourceRepository.seedIfEmpty], so an
 * upgrading install gets the same catalog a fresh one does — including channels added to the
 * seed list in later app versions, for anyone whose table is still empty.
 */
val MIGRATION_4_5 = object : androidx.room.migration.Migration(4, 5) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS `content_sources` (" +
                "`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                "`sourceType` TEXT NOT NULL, `youtubeId` TEXT NOT NULL, " +
                "`displayName` TEXT NOT NULL, `category` TEXT NOT NULL, " +
                "`builtIn` INTEGER NOT NULL, `hidden` INTEGER NOT NULL, " +
                "`position` INTEGER NOT NULL)",
        )
        db.execSQL(
            "CREATE UNIQUE INDEX IF NOT EXISTS `index_content_sources_youtubeId` " +
                "ON `content_sources` (`youtubeId`)",
        )
    }
}

/**
 * Mini-games recording (#35, with #33's head tracker): a session records as one ride plus one
 * `game_results` row per segment.
 * - [Ride.gamePlan]: which session plan a ride recorded; `null` for every existing ride.
 * - [Profile.headCalibration]: the rider's camera lean extremes as JSON; `null` until the
 *   first calibration, which is exactly "not calibrated yet".
 * - `game_results`, created empty, cascading with its ride.
 */
val MIGRATION_5_6 = object : androidx.room.migration.Migration(5, 6) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE rides ADD COLUMN gamePlan TEXT")
        db.execSQL("ALTER TABLE profiles ADD COLUMN headCalibration TEXT")
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS `game_results` (" +
                "`rideId` INTEGER NOT NULL, `segmentIndex` INTEGER NOT NULL, " +
                "`gameId` TEXT NOT NULL, `role` TEXT NOT NULL, `difficulty` TEXT NOT NULL, " +
                "`startSec` INTEGER NOT NULL, `durationSec` INTEGER NOT NULL, " +
                "`score` REAL NOT NULL, `stars` INTEGER NOT NULL, `won` INTEGER, " +
                "`skipped` INTEGER NOT NULL, `statsJson` TEXT NOT NULL, " +
                "PRIMARY KEY(`rideId`, `segmentIndex`), FOREIGN KEY(`rideId`) REFERENCES " +
                "`rides`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )",
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_game_results_gameId` ON `game_results` (`gameId`)")
    }
}
