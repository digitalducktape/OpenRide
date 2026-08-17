// Reconstructed for OpenRide — interoperability reconstruction of the bike-board binder
// interface exposed by the Peloton affernet system service.
//
// Bound via: Intent(action = "com.onepeloton.affernetservice.IBikeInterface"),
//            package = "com.onepeloton.affernetservice"
// (the same exported, unguarded AffernetService that serves IV1Interface — any app may bind,
// no signature permission).
//
// WHY THIS EXISTS ALONGSIDE IV1Interface
//
// On the Bike Gen 2 (`RB1VQ`, Android 11) the service streams BikeData frames to a client
// registered through IV1Interface. On the Bike+ (`topaz`, Android 10) it does not: the bind
// succeeds and registerCallback is accepted, but no frame ever arrives, verified on-device
// with a rider actively pedaling. On that board the stock software registers through
// IBikeInterface instead, and that is the interface that streams. Both carry the SAME BikeData
// parcelable, so only the wrapper differs — see docs/SENSOR_PROTOCOL.md.
//
// Method ORDER is load-bearing: AIDL assigns transaction codes 1..N in declaration order.
// These codes were read directly out of the on-device APK's IBikeInterface$Stub
// TRANSACTION_* constants (`apkanalyzer dex code`), not inferred from a guessed ordering:
//
//     1 getRPM                      10 getPacketTime
//     2 getPower                    11 getStepperMotorStartPosition
//     3 getStepperMotorPosition     12 getStepperMotorEndPosition
//     4 getLoadCellVolume           13 getCalibrationState
//     5 getCurrentResistance        14 getBikeData
//     6 getTargetResistance         15 registerCallback
//     7 setResistance               16 unregisterCallback
//     8 getFWVersion                17 setEnableFakeDataMode
//     9 getPacketData
//
// The real interface continues past 17 (calibration, bootloader, serial-number and
// power-zone-auto-follow calls OpenRide never makes). Declaration stops at 17 because every
// method OpenRide uses sits at or below it, and declaring more only risks signature drift.
//
// Methods 3, 4, 7..13 are declared purely to hold the numbering. OpenRide never calls them,
// so their signatures affect nothing but their own generated proxy code — they are reproduced
// accurately anyway, from the same dex dump.
package com.onepeloton.affernetservice;

import com.onepeloton.affernetservice.BikeData;
import com.onepeloton.affernetservice.IBikeCallback;

interface IBikeInterface {
    // 1..6 — individual metric getters. OpenRide reads metrics from the pushed BikeData frame
    // rather than polling these, but getRPM/getPower/getCurrentResistance are a useful
    // independent cross-check when diagnosing a board (see PelotonBikeInterfaceDataSource).
    long getRPM();
    long getPower();
    long getStepperMotorPosition();
    long getLoadCellVolume();
    int getCurrentResistance();
    int getTargetResistance();

    // 7..13 — placeholders, never called by OpenRide.
    void setResistance(int resistance);
    String getFWVersion();
    byte[] getPacketData();
    String getPacketTime();
    int getStepperMotorStartPosition();
    int getStepperMotorEndPosition();
    int getCalibrationState();

    // Transaction 14. Synchronous poll of the same BikeData struct the callback pushes. This is
    // the fallback path when a board accepts registerCallback but never pushes.
    BikeData getBikeData();

    // Transaction 15. `identifier` is a free-form client tag the service logs.
    void registerCallback(IBikeCallback callback, String identifier);

    // Transaction 16.
    void unregisterCallback(IBikeCallback callback, String identifier);

    // Transaction 17. Synthetic-frame mode for on-device pipeline verification only, never
    // production. Note the int parameter — IV1Interface's equivalent takes a boolean, and this
    // interface splits enable/disable into two calls (setDisableFakeDataMode is transaction 18).
    boolean setEnableFakeDataMode(int mode);
}
