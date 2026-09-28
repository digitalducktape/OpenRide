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

### Test-only dependencies

| Dependency | Group | License |
|---|---|---|
| JUnit 4 | `junit` | EPL-1.0 |
| Robolectric | `org.robolectric` | MIT |
| Turbine | `app.cash.turbine` | Apache-2.0 |
| AndroidX Test (junit, core, runner) | `androidx.test*` | Apache-2.0 |

> Test dependencies are not shipped in the installed APK.

## Third-party content at runtime

OpenRide's class library streams **third-party YouTube videos through YouTube's
official IFrame Player API** (`youtube-nocookie.com`). OpenRide does not host,
download, cache, re-encode, or redistribute any video content, and it bundles no
video or audio assets. All such content remains the property of its respective
owners and is subject to YouTube's Terms of Service.
