# Third-party notices

OpenRide is licensed under Apache-2.0 (see `LICENSE`). It builds on the work
below. This file records attributions and the licenses of bundled/redistributed
dependencies.

## Acknowledged prior work (technique and research, no code copied)

These projects and write-ups documented the facts OpenRide relies on — the
Peloton Bike Gen 2 on-device sensor interface and the power→speed relationship.
OpenRide reimplements the technique from these public descriptions and from
first-hand observation on the project owner's own bike; it does **not** copy
source code from any of them. See `docs/INTEROP.md` for details.

- **grupetto** — https://github.com/selalipop/grupetto
  Demonstrated that live cadence/resistance/power/speed on the Bike Gen 2 are
  reachable by binding an exported on-device system service without root and
  independent of subscription state. **grupetto publishes no license**, so it is
  "all rights reserved"; OpenRide therefore copies **none** of its code and
  relies only on the (uncopyrightable) protocol facts and the general technique.
  OpenRide's sensor binding is an independent AIDL-based reimplementation
  (`app/src/main/aidl/com/onepeloton/affernetservice/`,
  `app/src/main/java/dev/digitalducktape/openride/core/sensor/PelotonBikeDataSource.kt`).

- **PeloMon** — https://ihaque.org/posts/2020/12/25/pelomon-part-ib-computing-speed/
  Ivan Haque's analysis of how the Peloton head unit derives speed from power.
  OpenRide uses the same documented power→speed curve (a mathematical
  relationship, not a copyrightable expression) in
  `app/src/main/java/dev/digitalducktape/openride/core/sensor/PelotonSpeed.kt`.

- **OpenPelo** — https://github.com/doudar/Openpelo
  Community tool used to sideload apps onto the bike tablet over ADB. OpenRide
  does not bundle or redistribute OpenPelo; it is referenced only as an external
  install prerequisite in the README and `docs/INSTALL.md`.

- **1€ (One Euro) filter** — Géry Casiez, Nicolas Roussel and Daniel Vogel,
  "1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input in Interactive
  Systems", CHI 2012. The head tracker's smoothing implements the algorithm from
  the paper's description
  (`app/src/main/java/dev/digitalducktape/openride/core/camera/OneEuroFilter.kt`);
  no code was copied.

## Redistributed runtime dependencies

All runtime dependencies are fetched by Gradle and are under permissive licenses
(Apache-2.0 unless noted). None are copyleft; none impose obligations on
OpenRide's own source beyond attribution. Authoritative versions live in
`gradle/libs.versions.toml`.

| Dependency | Group | License |
|---|---|---|
| AndroidX (core-ktx, lifecycle, activity, fragment, navigation, exifinterface) | `androidx.*` | Apache-2.0 |
| Jetpack Compose (UI, Material 3, tooling) | `androidx.compose.*` | Apache-2.0 |
| Room (runtime, ktx, compiler) | `androidx.room` | Apache-2.0 |
| Kotlin stdlib & Coroutines | `org.jetbrains.kotlin*`, `org.jetbrains.kotlinx` | Apache-2.0 |
| Kotlinx Serialization | `org.jetbrains.kotlinx` | Apache-2.0 |
| Coil | `io.coil-kt` | Apache-2.0 |
| Godot Engine (Android library, mini-games) | `org.godotengine:godot` | MIT |
| CameraX (camera-core, camera-camera2, camera-lifecycle) and lifecycle-process | `androidx.camera`, `androidx.lifecycle` | Apache-2.0 |
| MediaPipe Tasks (`tasks-vision`, `tasks-core`, with native `libmediapipe_tasks_jni.so`) | `com.google.mediapipe` | Apache-2.0 |
| MediaPipe's dependencies: Guava, Flogger, Google Android datatransport, Firebase encoders, `javax.inject` | `com.google.guava`, `com.google.flogger`, `com.google.android.datatransport`, `com.google.firebase`, `javax.inject` | Apache-2.0 |
| Protocol Buffers (Java lite runtime, via MediaPipe) | `com.google.protobuf` | BSD-3-Clause |
| Guava's annotation artifacts (jsr305, error_prone, j2objc, failureaccess) | `com.google.code.findbugs`, `com.google.errorprone`, `com.google.j2objc`, `com.google.guava` | Apache-2.0 |
| checker-compat-qual, animal-sniffer-annotations (via Guava) | `org.checkerframework`, `org.codehaus.mojo` | MIT (checker-compat-qual is dual-licensed GPL-2.0-with-classpath-exception / MIT; used under MIT) |

### Godot Engine

The mini-games (`games/`, see `docs/GAMES.md`) run on the Godot Engine, embedded as the
`org.godotengine:godot` Android library — https://godotengine.org

> Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
> Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software
> and associated documentation files (the "Software"), to deal in the Software without
> restriction, including without limitation the rights to use, copy, modify, merge, publish,
> distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
> Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or
> substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
> BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
> NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
> DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

The engine bundles third-party components under their own permissive licenses (for example
FreeType, zlib, libpng, HarfBuzz and others). They are listed, with their license texts, in
Godot's `COPYRIGHT.txt` (https://github.com/godotengine/godot/blob/4.7.2-stable/COPYRIGHT.txt),
and are available at runtime from the engine itself (`Engine.get_copyright_info()` /
`Engine.get_license_info()`).

### MediaPipe and the BlazeFace model

The mini-games head tracker (`core/camera/`) finds the rider's face with Google's
MediaPipe Tasks Face Detector — https://ai.google.dev/edge/mediapipe — linked as
the prebuilt `com.google.mediapipe:tasks-vision` library (Apache-2.0).

Its model ships unmodified in the APK as
`app/src/main/assets/mediapipe/blaze_face_short_range.tflite`, downloaded from
https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite
(MD5 `a3dd6ec31725290770b97cec0cbf94c9`). It is licensed under the **Apache License,
Version 2.0**, per the "MediaPipe BlazeFace Short Range" model card by Google
(https://storage.googleapis.com/mediapipe-assets/MediaPipe%20BlazeFace%20Model%20Card%20(Short%20Range).pdf).
Citation: V. Bazarevsky et al., "BlazeFace: Sub-millisecond Neural Face Detection on
Mobile GPUs", CVPR Workshop on Computer Vision for AR/VR, 2019.

Camera frames are analysed in memory on the tablet and never stored or sent by
OpenRide. MediaPipe Tasks' `tasks-core` also contains a usage-statistics reporter
that would send the app's id and version, the task, its running mode, and
invocation counts and latencies (never images) to Google through the
datatransport library. OpenRide's manifest unregisters the transport's backend, so
these reports are dropped on the device and never sent (see the comment in
`app/src/main/AndroidManifest.xml`).

### Test-only dependencies

| Dependency | Group | License |
|---|---|---|
| JUnit 4 | `junit` | EPL-1.0 |
| Robolectric | `org.robolectric` | MIT |
| Turbine | `app.cash.turbine` | Apache-2.0 |
| AndroidX Test (junit, core, runner) | `androidx.test*` | Apache-2.0 |
| GdUnit4 6.2.1 (Godot unit tests, vendored in `games/addons/gdUnit4/`) | https://github.com/godot-gdunit-labs/gdUnit4 | MIT |

> Test dependencies are not shipped in the installed APK. GdUnit4 is excluded from the exported
> games pack (`games/export_presets.cfg`).

#### GdUnit4

The Godot tests (`games/tests/unit/`) run on GdUnit4 6.2.1, vendored unmodified, with its
licence, in `games/addons/gdUnit4/` (including the addon's own UI images).

> MIT License
>
> Copyright (c) 2023 Mike Schulze
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software
> and associated documentation files (the "Software"), to deal in the Software without
> restriction, including without limitation the rights to use, copy, modify, merge, publish,
> distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
> Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or
> substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
> BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
> NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
> DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Third-party content at runtime

OpenRide's class library streams **third-party YouTube videos through YouTube's
official IFrame Player API** (`youtube-nocookie.com`). OpenRide does not host,
download, cache, re-encode, or redistribute any video content, and it bundles no
video or audio assets. All such content remains the property of its respective
owners and is subject to YouTube's Terms of Service.
