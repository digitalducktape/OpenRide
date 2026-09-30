package dev.digitalducktape.openride.core.data

import dev.digitalducktape.openride.core.camera.HeadCalibration
import dev.digitalducktape.openride.core.camera.HeadCalibrationStore

/**
 * Keeps each rider's camera lean extremes in [Profile.headCalibration] (#33, column added by
 * [MIGRATION_5_6]). Unreadable JSON reads as no calibration, so the rider just calibrates again.
 * Saving to a deleted profile changes nothing.
 */
class ProfileHeadCalibrationStore(private val profileDao: ProfileDao) : HeadCalibrationStore {
    override suspend fun load(profileId: Long): HeadCalibration? =
        HeadCalibration.fromJson(profileDao.getHeadCalibration(profileId))

    override suspend fun save(profileId: Long, calibration: HeadCalibration) {
        profileDao.setHeadCalibration(profileId, calibration.toJson())
    }
}
