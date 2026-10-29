# Interoperability & legal basis

> Plain-language note, not legal advice. It records *what* OpenRide does and does
> not do at the sensor boundary, so the design intent is on the record.

OpenRide is an independent application for the **Peloton Bike (Gen 2)**. It is
not affiliated with, authorized, or endorsed by Peloton Interactive, Inc. Its
one point of contact with Peloton software is reading the bike's own sensor
values (cadence, resistance, power) so the rider can see their metrics. This
document explains how that is done and why it is designed to stay within the
lines of interoperability.

## What OpenRide does

- Runs as a normal, sideloaded Android app on the bike's tablet (a device the
  user owns). Installation uses ADB via the community
  [OpenPelo](https://github.com/doudar/Openpelo) tool. **No root, no bootloader
  unlock, no firmware modification.**
- Binds a system service that already exists on the tablet
  (`com.onepeloton.affernetservice`) to receive live sensor frames, then renders
  them. See `docs/SENSOR_PROTOCOL.md`.

## Why this is interoperability, not circumvention

1. **No technical protection measure is bypassed.** The affernet service is an
   **exported, unguarded** Android service: it declares no signature permission
   and any installed app may bind it. OpenRide binds it through the ordinary,
   documented Android `bindService` API. Nothing is decrypted, unlocked, jailbroken,
   or defeated to reach it.
2. **No Peloton code is copied.** The AIDL interfaces and the `BikeData`
   Parcelable under `com.onepeloton.affernetservice/` are an **independent
   reconstruction** written to match the service's observed on-device wire
   format. They must carry Peloton's package name and field/transaction ordering
   *because those are the functional interface* an interoperating client is
   required to speak — the same category of functional interface material treated
   as fair use in *Google v. Oracle*. OpenRide copies no implementation.
3. **Only functional facts are used.** Field order in a Parcel and the
   power→speed curve are facts dictated by the hardware/protocol, not creative
   expression; under the merger doctrine there is essentially one way to express
   them correctly.
4. **No servers, accounts, or networks are touched.** OpenRide never contacts
   Peloton's servers, never uses Peloton credentials, and reads only data
   produced locally by hardware the user owns. There is no unauthorized access to
   any computer system.
5. **No Peloton content or brand assets.** OpenRide ships no Peloton source,
   artwork, logos, fonts, audio, video, or class content. "Peloton" appears only
   descriptively (to say what hardware the app runs on) and as functional
   identifiers required by the binder interface.

## Relationship to prior community work

The technique of binding the on-device sensor service was publicly demonstrated
by [grupetto](https://github.com/selalipop/grupetto). grupetto ships **no
license**, so OpenRide treats its code as all-rights-reserved and copies none of
it. OpenRide's sensor path is an independent AIDL-based reimplementation that
also decodes newer struct fields grupetto's decompiled class does not contain.
See `THIRD_PARTY_NOTICES.md`.

## Trademark

"Peloton" and "Peloton Bike" are trademarks of Peloton Interactive, Inc. OpenRide
uses them nominatively — only as needed to identify the compatible hardware — and
does not use Peloton's logos, stylized marks, or trade dress. OpenRide does not
imply sponsorship or endorsement.

## Smart trainers and controllers

Smart trainers and OpenBikeControl controllers (issue #68) involve no Peloton software at all.
OpenRide speaks two published, freely implementable protocols to devices the rider owns: the
Bluetooth SIG's Fitness Machine Service, and the MIT-licensed OpenBikeControl protocol. Both are
reimplemented from their specifications (`core/trainer/`, `core/controller/`).

## Scope

OpenRide exists so an owner can see and keep their own ride data on hardware they
own. It is not a tool for accessing Peloton's subscription content, and it neither
contains nor unlocks any such content.
