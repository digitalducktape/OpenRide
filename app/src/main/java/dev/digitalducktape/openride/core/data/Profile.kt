package dev.digitalducktape.openride.core.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * A household rider. Every [Ride] is scoped to exactly one profile (PRD P0-3: multi-user
 * profiles are a first-class requirement, not an afterthought).
 *
 * @param weightKg optional, used for calorie estimation / export accuracy (P1-1, P1-3)
 * @param ftp optional functional threshold power in watts, used for power-zone display (P1-3)
 * @param pairedHrDeviceAddress optional BLE MAC address of this rider's paired heart-rate
 *   strap (PRD P1-4, T17) — "remember strap per profile" so each household member doesn't
 *   have to re-pair every ride. Added in schema version 2
 *   ([dev.digitalducktape.openride.core.data.MIGRATION_1_2]); `null` until a strap is paired.
 * @param avatarPhotoPath optional absolute path of a camera photo (already center-cropped,
 *   see [dev.digitalducktape.openride.core.profile.AvatarPhotoStore]) shown in place of the
 *   emoji/color avatar wherever the rider's circle appears. Added in schema version 4
 *   ([dev.digitalducktape.openride.core.data.MIGRATION_3_4]); `null` means emoji avatar.
 * @param headCalibration the rider's camera lean extremes for the mini-games (#33), as
 *   [dev.digitalducktape.openride.core.camera.HeadCalibration] JSON, reused while fresh (the
 *   same day). Added in schema version 6 ([MIGRATION_5_6]); `null` until the first calibration.
 */
@Entity(tableName = "profiles")
data class Profile(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val avatarEmoji: String,
    val avatarColor: Int,
    val weightKg: Double?,
    val ftp: Int?,
    val pairedHrDeviceAddress: String? = null,
    val avatarPhotoPath: String? = null,
    val headCalibration: String? = null,
)
