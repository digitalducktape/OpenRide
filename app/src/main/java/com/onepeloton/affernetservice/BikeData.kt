package com.onepeloton.affernetservice

import android.os.Parcel
import android.os.Parcelable

/**
 * Reconstructed for OpenRide T3/#3 (interoperability — the owner's own Bike Gen 2 tablet).
 *
 * The sensor-frame Parcelable the affernet system service pushes to a registered
 * [IV1Callback] on every update (transaction `onSensorDataChange`). This class MUST live at
 * this exact fully-qualified name so the AIDL-generated stub and `Parcel.readParcelable`
 * resolve it, and its read order MUST match the service's `writeToParcel` byte-for-byte — a
 * [Parcel] read out of order silently yields garbage rather than throwing, so the field order
 * is the entire contract. Reverse-engineered from the on-device service and cross-checked
 * against grupetto's proven Gen 2 decode. Full field map: docs/SENSOR_PROTOCOL.md.
 *
 * OpenRide only consumes [rpm], [power] and [currentResistance]; the rest of the struct is
 * read purely to keep the parcel in sync. Those three live at the very front of the layout
 * (offsets 1, 2, 5) and are captured before any variable-length field, so even if a future
 * firmware drifts the tail layout, the metrics OpenRide cares about are already safely read
 * (the remainder is parsed defensively and tail failures are swallowed).
 */
class BikeData() : Parcelable {

    // --- Fields OpenRide actually maps to BikeMetrics -----------------------------------
    /** Crank cadence in revolutions per minute. Raw, already in RPM (no scaling). */
    @JvmField var rpm: Long = 0

    /** Instantaneous output. Raw units are centi-watts (watts x 100) — divide by 100. */
    @JvmField var power: Long = 0

    /** Current resistance, already on the 0..100 scale (no scaling). */
    @JvmField var currentResistance: Int = 0

    /** Target/commanded resistance, 0..100. */
    @JvmField var targetResistance: Int = 0

    // --- Remaining struct (read for parcel sync; not surfaced to the app) ---------------
    @JvmField var stepperMotorPosition: Long = 0
    @JvmField var loadCellReading: Long = 0
    @JvmField var calibrationState: Int = 0
    @JvmField var systemState: Int = 0
    @JvmField var powerSource: Int = POWER_SOURCE_SENSOR
    @JvmField var v3BikeData: V3BikeData? = null

    private constructor(parcel: Parcel) : this() {
        // Front of the struct: primitives only, so these three metrics are captured before
        // any string/array/parcelable that could desync on a firmware layout change.
        rpm = parcel.readLong()                          // 1  mRPM
        power = parcel.readLong()                        // 2  mPower
        stepperMotorPosition = parcel.readLong()         // 3  mStepperMotorPosition
        loadCellReading = parcel.readLong()              // 4  mLoadCellReading
        currentResistance = parcel.readInt()             // 5  mCurrentResistance
        targetResistance = parcel.readInt()              // 6  mTargetResistance

        // Everything past here is not consumed by OpenRide. Read it to keep the parcel in
        // sync, but never let a tail-layout surprise cost us the metrics already captured.
        try {
            parcel.readString()                          // 7  mFWVersionNumber
            parcel.createByteArray()                     // 8  mPacketData
            parcel.readString()                          // 9  mPacketTime
            parcel.readInt()                             // 10 mStepperMotorStartPosition
            parcel.readInt()                             // 11 mStepperMotorEndPosition
            calibrationState = parcel.readInt()          // 12 mCalibrationState
            parcel.readInt()                             // 13 mEncoderAngle
            systemState = parcel.readInt()               // 14 mSystemState
            parcel.readInt()                             // 15 mErrorIndex
            parcel.readInt()                             // 16 mError1Code
            parcel.readString()                          // 17 mError1Time
            parcel.readInt()                             // 18 mError2Code
            parcel.readString()                          // 19 mError2Time
            parcel.readInt()                             // 20 mError3Code
            parcel.readString()                          // 21 mError3Time
            parcel.readInt()                             // 22 mError4Code
            parcel.readString()                          // 23 mError4Time
            parcel.readInt()                             // 24 mError5Code
            parcel.readString()                          // 25 mError5Time
            parcel.createIntArray()                      // 26 mErrorMap  (len-prefixed, 15)
            parcel.readString()                          // 27 mLoadCellTable
            parcel.readInt()                             // 28 mLoadCellTableCrc
            parcel.readString()                          // 29 mPSerial
            parcel.readString()                          // 30 mQSerial
            parcel.readString()                          // 31 mBikeFrameSerial
            parcel.readString()                          // 32 mLoadCellSerial
            parcel.readFloat()                           // 33 mLoadCellOffset
            parcel.readInt()                             // 34 mDataWriteCycle
            parcel.readString()                          // 35 mDataWriteDate
            parcel.readString()                          // 36 mDataWriteTime
            parcel.readInt()                             // 37 mLoadCellZeroData
            parcel.readInt()                             // 38 mLoadCellCalSpan
            parcel.readInt()                             // 39 mLoadCellTempCount
            parcel.readFloat()                           // 40 mResistanceOffset
            parcel.readInt()                             // 41 mPositionOffset
            parcel.readInt()                             // 42 mLoadCellTableStatus
            parcel.readFloat()                           // 43 mV1Resistance
            parcel.readString()                          // 44 mLoadCellVersion
            parcel.readInt()                             // 45 mAppliedPositionOffset
            parcel.readInt()                             // 46 mStallThreshold
            parcel.readString()                          // 47 mHardwareVersion
            parcel.readInt()                             // 48 mADValue
            parcel.readInt()                             // 49 mPowerZoneAutoFollowEnabled
            parcel.readInt()                             // 50 mPowerZoneAutoFollowPowerSetPoint
            parcel.readFloat()                           // 51 mPowerZoneAutoFollowTargetResistance
            parcel.readInt()                             // 52 mPowerZoneAutoFollowStatus
            parcel.readInt()                             // 53 mPZAFRampUpRate
            parcel.readInt()                             // 54 mPZAFRampDownRate
            parcel.readInt()                             // 55 mPZAFMaxResistanceSetPoint
            parcel.readInt()                             // 56 mPZAFMinUpdateRPM
            @Suppress("DEPRECATION")                     // readParcelable(ClassLoader) — the
            // typed overload needs API 33; minSdk here is 29, so the older form is required.
            run {
                v3BikeData = parcel.readParcelable(      // 57 mV3BikeData
                    V3BikeData::class.java.classLoader,
                )
            }
            powerSource = parcel.readInt()               // 58 mPowerSource
            parcel.readInt()                             // 59 mIRAFEnabled (0/1)
            parcel.readInt()                             // 60 mIRAFBaseline
            parcel.readInt()                             // 61 systemHealthStatus
            parcel.createIntArray()                      // 62 newErrorMap
        } catch (_: RuntimeException) {
            // Tail-layout drift on some firmware variant. rpm/power/currentResistance are
            // already captured above; the remaining fields are unused, and the transaction
            // parcel is discarded after this call, so a desync here is harmless.
        }
    }

    override fun writeToParcel(parcel: Parcel, flags: Int) {
        // Symmetric with the read order. OpenRide never sends a BikeData over binder (it is
        // always the receiver); this exists only to satisfy the Parcelable contract and to
        // support round-trip unit tests.
        parcel.writeLong(rpm)
        parcel.writeLong(power)
        parcel.writeLong(stepperMotorPosition)
        parcel.writeLong(loadCellReading)
        parcel.writeInt(currentResistance)
        parcel.writeInt(targetResistance)
        parcel.writeString(null)                         // mFWVersionNumber
        parcel.writeByteArray(null)                      // mPacketData
        parcel.writeString(null)                         // mPacketTime
        parcel.writeInt(0)                               // mStepperMotorStartPosition
        parcel.writeInt(0)                               // mStepperMotorEndPosition
        parcel.writeInt(calibrationState)
        parcel.writeInt(0)                               // mEncoderAngle
        parcel.writeInt(systemState)
        parcel.writeInt(0)                               // mErrorIndex
        parcel.writeInt(0); parcel.writeString(null)     // mError1Code / Time
        parcel.writeInt(0); parcel.writeString(null)     // mError2Code / Time
        parcel.writeInt(0); parcel.writeString(null)     // mError3Code / Time
        parcel.writeInt(0); parcel.writeString(null)     // mError4Code / Time
        parcel.writeInt(0); parcel.writeString(null)     // mError5Code / Time
        parcel.writeIntArray(IntArray(BIKE_ERROR_COUNT)) // mErrorMap
        parcel.writeString(null)                         // mLoadCellTable
        parcel.writeInt(0)                               // mLoadCellTableCrc
        parcel.writeString(null)                         // mPSerial
        parcel.writeString(null)                         // mQSerial
        parcel.writeString(null)                         // mBikeFrameSerial
        parcel.writeString(null)                         // mLoadCellSerial
        parcel.writeFloat(0f)                            // mLoadCellOffset
        parcel.writeInt(0)                               // mDataWriteCycle
        parcel.writeString(null)                         // mDataWriteDate
        parcel.writeString(null)                         // mDataWriteTime
        parcel.writeInt(0)                               // mLoadCellZeroData
        parcel.writeInt(0)                               // mLoadCellCalSpan
        parcel.writeInt(0)                               // mLoadCellTempCount
        parcel.writeFloat(0f)                            // mResistanceOffset
        parcel.writeInt(0)                               // mPositionOffset
        parcel.writeInt(0)                               // mLoadCellTableStatus
        parcel.writeFloat(0f)                            // mV1Resistance
        parcel.writeString(null)                         // mLoadCellVersion
        parcel.writeInt(0)                               // mAppliedPositionOffset
        parcel.writeInt(0)                               // mStallThreshold
        parcel.writeString(null)                         // mHardwareVersion
        parcel.writeInt(0)                               // mADValue
        parcel.writeInt(0)                               // mPowerZoneAutoFollowEnabled
        parcel.writeInt(0)                               // mPowerZoneAutoFollowPowerSetPoint
        parcel.writeFloat(0f)                            // mPowerZoneAutoFollowTargetResistance
        parcel.writeInt(0)                               // mPowerZoneAutoFollowStatus
        parcel.writeInt(0)                               // mPZAFRampUpRate
        parcel.writeInt(0)                               // mPZAFRampDownRate
        parcel.writeInt(0)                               // mPZAFMaxResistanceSetPoint
        parcel.writeInt(0)                               // mPZAFMinUpdateRPM
        parcel.writeParcelable(v3BikeData, flags)        // mV3BikeData
        parcel.writeInt(powerSource)
        parcel.writeInt(0)                               // mIRAFEnabled
        parcel.writeInt(0)                               // mIRAFBaseline
        parcel.writeInt(0)                               // systemHealthStatus
        parcel.writeIntArray(null)                       // newErrorMap
    }

    override fun describeContents(): Int = 0

    companion object {
        /** Matches BikeConstants.BIKE_ERROR_COUNT on the device firmware. */
        const val BIKE_ERROR_COUNT = 15

        /** BikeConstants.POWER_SOURCE_SENSOR — the flywheel sensor is the power source. */
        const val POWER_SOURCE_SENSOR = 1

        @JvmField
        val CREATOR = object : Parcelable.Creator<BikeData> {
            override fun createFromParcel(parcel: Parcel): BikeData = BikeData(parcel)
            override fun newArray(size: Int): Array<BikeData?> = arrayOfNulls(size)
        }
    }
}
