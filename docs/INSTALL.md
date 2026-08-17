# Installing OpenRide on the Peloton Bike (Gen 2 / Bike+) tablet

This covers sideloading OpenRide onto the bike's stock tablet (Android 11 on the
Gen 2, Android 10 on the Bike+) via
[OpenPelo](https://github.com/doudar/Openpelo), enabling it as the tablet's home-screen
launcher, blocking OTA updates (so a firmware push can't undo any of this), and reverting
back to stock if you ever need to.

**Read this fully before starting**, especially the OTA section — the sequencing matters
(block updates *before* you're relying on anything here staying in place).

## 0. Prerequisites

- The bike's tablet, with USB debugging accessible per OpenPelo's own setup instructions.
- A computer with `adb` installed (part of the Android SDK platform-tools).
- OpenPelo itself set up per [its own docs](https://github.com/doudar/Openpelo) — this guide
  picks up *after* OpenPelo has ADB access working, it doesn't replace OpenPelo's setup.
- This repo built to a debug APK (`./gradlew assembleDebug`), or a release APK if you've set
  up signing — the output lands at `app/build/outputs/apk/debug/app-debug.apk` (or
  `.../release/app-release.apk`).

## 1. Sideload the APK

With the tablet connected (USB or wireless ADB per OpenPelo's instructions) and reachable as
an `adb devices` target:

```sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

`-r` allows reinstalling over a previous build without uninstalling first (keeps your Room
database — profiles/ride history — intact across updates, since app data isn't touched by a
reinstall over the same package, only by `adb uninstall`).

Launch it once manually to confirm it installed cleanly (app drawer icon, or):

```sh
adb shell am start -n dev.digitalducktape.openride/.MainActivity
```

You should land on profile select. If it crashes or won't launch, check `adb logcat` before
going further — no point enabling the launcher alias (next section) against a broken build.

## 2. Enable the HOME launcher (opt-in, off by default)

The app ships with an **opt-in** launcher alias (`.HomeLauncherAlias`, an
`<activity-alias>` targeting `MainActivity` with `HOME`/`DEFAULT` intent-filter categories)
that is **disabled by default** — installing the app never hijacks the tablet's home screen
on its own. You enable it explicitly:

```sh
adb shell pm enable dev.digitalducktape.openride/.HomeLauncherAlias
```

Then either reboot the tablet or press the physical/software Home button — Android will
either switch straight to OpenRide (if it's now the only enabled HOME app) or prompt you to
choose a default launcher (if the stock Peloton launcher is still enabled alongside it; see
OpenPelo's own notes on disabling/uninstalling the stock launcher and "Device Management"
app if you want OpenRide to take over without that prompt each time).

Once enabled, OpenRide is what boots after the tablet powers on, landing on profile select —
there's no separate "boot receiver" needed for this, since being launched as HOME already
starts `MainActivity`, whose nav graph always starts at profile select (PRD P0-8).

**To revert** (stop OpenRide from being offered as a home screen, without uninstalling it):

```sh
adb shell pm disable dev.digitalducktape.openride/.HomeLauncherAlias
```

## 3. Block OTA updates

**Do this before you start relying on any of the above** — a Peloton OTA update could
reinstate the stock launcher, re-enable the stock "Device Management" app, or (in the worst
case for this whole project) patch away whatever internal system service P0-2's live sensor
reading depends on. Per OpenPelo's own setup guidance:

- Disable auto-update checks/downloads for the stock Peloton app and system update
  component, following whatever specific steps OpenPelo's current documentation lists for
  the tablet's Android 11 build (this varies slightly by firmware version, so defer to
  OpenPelo's own up-to-date instructions rather than a copy pasted here that could go stale).
- Never accept an update prompt if one appears despite the above.
- Record the exact firmware/build number you've verified everything against
  (`Settings > About tablet`, or `adb shell getprop ro.build.display.id`) so you have a
  reference point if something changes unexpectedly later.
- Consider keeping the tablet off Wi-Fi (or on a network without internet access) except
  when you specifically want the YouTube RSS content (T9) to refresh, if you want to be
  extra conservative about update checks reaching the device at all. Not required — just an
  option if you'd rather not rely solely on in-OS update toggles.

## 4. In-app settings shortcuts

Once OpenRide is the launcher, the stock Settings app icon may not be one tap away anymore.
The Profile tab has two buttons for this (T12, PRD P1-5):

- **Wi-Fi Settings** — opens Android's Wi-Fi settings screen directly.
- **Device Settings** — opens Android's top-level Settings screen.

Both just fire a standard `Settings.ACTION_*` intent at whatever Settings app is installed —
no special permission or Peloton-specific hook involved.

## 5. Reverting to stock

To fully back out of everything above, roughly in reverse order:

1. Disable the launcher alias: `adb shell pm disable dev.digitalducktape.openride/.HomeLauncherAlias`
   (or skip straight to step 2, which removes it entirely anyway).
2. Uninstall OpenRide: `adb uninstall dev.digitalducktape.openride` — this also removes its
   local database (profiles/ride history), so back up first if you want to keep that (see
   the PRD's P1-8 local backup/restore, once that Phase 2 item exists — until then, the Room
   database itself lives under the app's data directory and could be pulled via `adb backup`/
   `run-as` if you're comfortable with that route).
3. Re-enable/reinstall whatever OpenPelo disabled or removed (stock launcher, "Device
   Management" app) per OpenPelo's own restore instructions.
4. Re-allow OTA updates if you'd disabled them, understanding that doing so re-introduces the
   risk that a firmware update could change or remove the on-device sensor service this app
   depends on.

Reverting network-level OTA blocks and any OpenPelo-side launcher/app removal is outside this
app's scope — those are OpenPelo setup steps, not something OpenRide's own APK controls.

## In-app updates (T22 / #22)

Once OpenRide is on the tablet, it updates itself from this repository's **GitHub Releases**
instead of you re-running `adb install` every time. There is nothing to configure — the app
checks the latest release on launch, and you can also check manually from **Profile tab → App
updates**. (Because the check hits GitHub's public API unauthenticated, the repository must stay
**public**.)

### Publishing a release

1. Bump `versionCode` (and `versionName`) in `app/build.gradle.kts`, commit, and tag.
2. Build the bike APK: `./gradlew :app:assembleDebugReal`.
3. Create a GitHub release for the tag and attach the APK **named exactly**
   `openride-real-<versionCode>.apk` — e.g. `openride-real-2.apk`. Put the changelog in the
   release body; it's shown to the rider before they update.

That filename is the whole contract: the trailing integer is the version the app compares
against, so there's no separate manifest to maintain.

### What the rider sees

On the next launch, if the latest release's `versionCode` is higher than what's installed, Home
shows a dismissible **"OpenRide `<version>` is available"** banner. Tapping **Update** (or going
to **Profile → App updates → Check for updates**) reveals a **Download** button, and once that
finishes an **Install** button that hands the APK to Android's own package installer.

Notes:

- The `<versionCode>` in the asset filename is the only thing compared — the release tag/name is
  display-only and never used for ordering.
- The asset's download URL **must** be `https://` (GitHub's are); a non-https URL is rejected
  rather than downloaded, since the payload is something you're about to be asked to install.
- Nothing installs itself. Check, Download and Install are three separate taps, and the last one
  just opens the platform installer's own confirmation screen.
- The first install this way will prompt you to allow OpenRide to "install unknown apps"
  (Android's `REQUEST_INSTALL_PACKAGES` gate) — a one-time per-app system setting.
- The published APK must be signed with the **same key** as the installed build or Android will
  refuse the update; if you're sideloading debug builds, keep using the same debug keystore.
- The dev (mock-sensor) build looks for an `openride-mock-<versionCode>.apk` asset, which normal
  releases don't carry, so it simply never finds an update — the updater targets the bike build.

## Bluetooth headphones (T19 / P1-9)

Class content plays through the YouTube app (OpenRide launches it via an intent) and OpenRide
never overrides audio routing, so Bluetooth-headphone audio "just works" through Android's own
routing: pair the headphones once in **Android Settings → Connected devices → Bluetooth** (you
can reach Android settings from OpenRide's Profile tab), and audio follows them automatically
whenever they're connected, falling back to the bike's speakers when they're not. There is no
OpenRide-side setting for this by design — the OS owns it.
