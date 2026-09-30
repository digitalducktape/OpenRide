package dev.digitalducktape.openride.core.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface ProfileDao {
    @Query("SELECT * FROM profiles ORDER BY name ASC")
    fun observeAll(): Flow<List<Profile>>

    @Query("SELECT * FROM profiles WHERE id = :id")
    suspend fun getById(id: Long): Profile?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(profile: Profile): Long

    @Update
    suspend fun update(profile: Profile)

    @Delete
    suspend fun delete(profile: Profile)

    /** [Profile.headCalibration] alone, so the head tracker never reads or rewrites other fields. */
    @Query("SELECT headCalibration FROM profiles WHERE id = :id")
    suspend fun getHeadCalibration(id: Long): String?

    @Query("UPDATE profiles SET headCalibration = :json WHERE id = :id")
    suspend fun setHeadCalibration(id: Long, json: String?)

    // --- Backup & restore (PRD P1-8, T15) ---------------------------------------------------

    @Query("SELECT * FROM profiles")
    suspend fun getAllOnce(): List<Profile>

    /**
     * Bulk-inserts [profiles] as-is, preserving each row's existing (non-zero) [Profile.id] —
     * Room only auto-generates a fresh id when the field is 0 — so restoring a backup onto an
     * already-wiped table recreates the exact original ids other tables' foreign keys depend on.
     */
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insertAll(profiles: List<Profile>)

    @Query("DELETE FROM profiles")
    suspend fun deleteAll()
}
