// Reconstructed for OpenRide — interoperability reconstruction of the callback interface the
// Peloton affernet service invokes to push live sensor frames to a client registered through
// IBikeInterface. This is the sibling of IV1Callback: same BikeData payload, different binder.
//
// Transaction codes read directly out of the on-device APK's IBikeCallback$Stub
// (`apkanalyzer dex code`), not inferred:
//
//     onSensorDataChange     -> transaction 1   (carries a BikeData frame)
//     onSensorError          -> transaction 2
//     onCalibrationStatus    -> transaction 3
//     onOTAUpdateStatus      -> transaction 4   (not declared — never fired at OpenRide)
//     onDiagnosticDataChange -> transaction 5   (not declared)
//     onMBSerial             -> transaction 6   (not declared)
//     onLogDataChange        -> transaction 7   (not declared)
//
// Only 1..3 are declared, matching IV1Callback. The service fires the undeclared ones only in
// response to requests OpenRide never makes; if one did arrive, the generated Stub returns
// false from onTransact and the oneway call is dropped harmlessly.
//
// The interface is `oneway`: the on-device proxy issues
// `transact(code, data, null, IBinder.FLAG_ONEWAY)` with a null reply parcel, so the generated
// Stub must not try to write a reply. See docs/SENSOR_PROTOCOL.md.
package com.onepeloton.affernetservice;

import com.onepeloton.affernetservice.BikeData;

oneway interface IBikeCallback {
    // Transaction 1. Wire form: [int nonNullFlag][BikeData if flag != 0] — the on-device proxy
    // marshals it with writeTypedObject, which is exactly AIDL's nullable-parcelable framing.
    void onSensorDataChange(in BikeData bikeData);

    // Transaction 2.
    void onSensorError(long errorCode);

    // Transaction 3. Not used by OpenRide (we never trigger calibration) but declared to keep
    // transaction codes 1 and 2 correctly assigned.
    void onCalibrationStatus(int status, boolean success, long timestamp);
}
