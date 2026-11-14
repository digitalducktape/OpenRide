# Usage metrics in OpenRide

OpenRide can send anonymous usage metrics. Sharing is **off until you say yes**. The app asks once, and you can change your answer at any time.

We use it to see which screens and features get used, and where things fail, so we know what to fix. That is all it is for.

## Turning it on or off

Go to **Profile, then Device, then Share usage metrics**. Sending stops right away when you turn it off. Events already handed to the sender are held in memory only and may still be sent until the app closes. Nothing is stored on the tablet.

The choice is **per tablet**. It covers every rider who uses that tablet. The in-app **What's collected** screen shows a short version of this page.

## Who processes it

Usage metrics go to [Aptabase](https://aptabase.com), an analytics service, using its US region. Aptabase says in its [privacy policy](https://aptabase.com/privacy) that US-region data is processed and stored in the United States. It says the IP address and user agent are "only processed in memory and are never stored". They are used to make a daily pseudonymous ID. Aptabase may also derive an approximate location, such as country, from the connection. Its policy does not say. OpenRide has no access to IP addresses.

Events from one visit to the app share a session ID that is not tied to a rider.

**Retention** (checked 2026-11-12): Aptabase's privacy policy says analytics data is stored "for up to 5 years". Its pricing page does not state a retention period. OpenRide does not add any retention of its own.

**Volume** (checked 2026-11-12): Aptabase's pricing page lists a free tier of 20,000 events a month, and paid plans from $10 a month for 200,000 events.

## What is collected

Each event carries the time it happened. Every value below comes from a fixed list or a rough bucket. Nothing is free text, except the channel name described under Classes. Each event also carries what Aptabase adds to every event: the app version and build number, the Android version, the device model, the language setting, the SDK version, and whether it is a debug or release event.

Length values use buckets, not exact numbers. Ride, class and visit lengths: `<5m`, `5–15m`, `15–30m`, `30–45m`, `45–60m`, `60m+`. A single game's play time: `<1m`, `1–3m`, `3–5m`, `5–10m`, `10m+`.

### App

| Event | Properties | Why |
| --- | --- | --- |
| `app_open` | `tablet`: bike, bike_plus, other. `firmware`: RQ.250113.A, QT.250804.A, other. `profiles`: 1, 2, 3+. `flavor`: real, mock | Which tablets and software versions to support |
| `screen_view` | `screen`: profile_select, profile_create, profile_edit, home, classes, games, history, profile, hr_pairing, app_update, about, content_sources, creator, telemetry_info | Which screens get used |
| `telemetry_enabled` | `source`: first_run, settings | Your answer to the prompt, sent when you say yes |
| `profile_created` | `has_photo`: true, false | Whether the photo step is worth keeping |

### Rides

| Event | Properties | Why |
| --- | --- | --- |
| `ride_start` | `type`: just_ride, class, games. `entry`: home_quick_start, classes, creator, games. `route`: true, false | How rides are started |
| `ride_end` | `type`: just_ride, class, games. `duration`: bucket. `outcome`: saved, discarded. `discard_reason`: none, too_short, no_pedalling, not_recording. `hr`: none, connected, dropped, never_connected. `hr_drops`: 0, 1, 2–5, 6+. `sensor`: ok, dropped, never. `music`: own_music, none (Just Ride and classes only; games report music on `games_visit_end`). `music_controls_used`: true, false | Whether rides are saved and whether the heart-rate strap and bike sensors hold up |

### Classes

| Event | Properties | Why |
| --- | --- | --- |
| `class_start` | `channel`, `channel_source`: curated, custom. `category`: scenic, workout. `source`: classes, creator | Which kinds of classes are used |
| `class_end` | `channel`, `channel_source`, `video_length`: bucket, `watched`: bucket, `finished`: true, false. `muted`: never, from_start, during | Whether classes get finished |
| `class_player_error` | `code`: the YouTube player error number, `channel` | Which playback errors happen |
| `content_source_added` | `channel`, `kind`: channel, playlist | Whether adding sources is used |

`channel` is the YouTube handle for a curated channel, such as `@biketheworld`. For a channel you add yourself, it is the channel's title as YouTube lists it, cut to 64 characters. For a playlist, only the word `playlist` is sent.

### Games

| Event | Properties | Why |
| --- | --- | --- |
| `games_plan_start` | `mode`: single, circuit, custom_circuit. `difficulty`: easy, standard, hard. `music`: game_music, own_music, off | Which ways of playing are used |
| `game_finish` | `game`: the game's catalogue id. `difficulty`. `game_difficulty`: game and difficulty together. `outcome`: completed, quit, skipped, no_result. `won`: yes, no, n/a. `stars`: 0, 1, 2, 3. `played`: bucket. `music`: game_music, own_music, off | Which games are fun, and whether the difficulty is right |
| `games_visit_end` | `played`: bucket. `games`: 0, 1, 2, 3, 4, 5+. `reason`: exit, idle, app_resumed. `music`: game_music, own_music, mixed, off. `music_controls_used`: true, false | How long a visit to Games lasts |
| `game_music_switch` | `value`: on, off | Whether Game music is wanted |
| `head_calibration` | `result`: success, cancelled, failed. `mode`: lean_x, lean_2d | Whether head-lean setup works. `failed` means setup ended with no face or camera |

### Music

| Event | Properties | Why |
| --- | --- | --- |
| `music_player_open` | `surface`: top_bar, just_ride, video_ride, games | Where the music player is used. `games` is the first in-game music control in an app run |
| `music_app_chosen` | `app`: spotify, apple_music, pandora, siriusxm, plexamp, other | Which music apps to support |
| `notification_access` | `result`: granted, denied | Whether the music player can be set up |

### Sensors and camera

| Event | Properties | Why |
| --- | --- | --- |
| `hr_strap_selected` | `result`: selected, bt_off, scan_failed | Why strap pairing fails |
| `bike_sensor` | `state`: connected, unavailable. `path`: iv1_interface, bike_interface, polling (not sent when unavailable) | Whether the bike's data arrives, and by which route |
| `camera_permission` | `result`: granted, denied | Whether the camera is allowed |

`bike_sensor` can be sent twice in one app run: `unavailable` after 30 seconds without data, then `connected` if data arrives later. `path` may read `polling` for a late connection.

### Your data

| Event | Properties | Why |
| --- | --- | --- |
| `backup_export` | `result`: success, failed | Whether backups work |
| `backup_restore` | `result`: success, failed, bad_file | Whether restores work |
| `auto_backup_failed` | none | Whether automatic backups fail |
| `history_import` | `result`: success, failed, wrong_file, no_rider. `imported`: 0, 1–10, 11–50, 51–200, 200+. `duplicates`: true, false | Whether importing old rides works |
| `ride_deleted` | `type`: just_ride, class, games | Whether people delete rides. Imported rides count as just_ride |
| `ride_export` | `format`: tcx, csv_ride, csv_history | Which export formats are used |
| `gpx_import` | `result`: success, failed. `points`: <500, 500–2k, 2k–10k, 10k+ | Whether route loading works |
| `gpx_route_cleared` | none | Whether routes are cleared |

Results and rough counts only, never the contents. Failures to open a file before a GPX or history file is read are not reported.

### Updates

| Event | Properties | Why |
| --- | --- | --- |
| `update_prompt` | `action`: shown, install_tapped | Whether the update prompt is seen and used |
| `update_failed` | `stage`: check, download | Whether updates fail. `check` also covers the quiet check at launch |

## What is never sent

Heart rate, power, cadence, speed, resistance, FTP or weight. Scores other than 0 to 3 stars. Rider names or photos. Video IDs or titles. Playlist names. Song, artist or app-playback details. Bluetooth names or addresses. File names or route coordinates. Exact ride or class lengths, or clock times, in event properties. Error messages or stack traces. Advertising IDs or any account details.

## Good to know

- A ride that is abandoned, or that the system closes, shows up only as `ride_start` with no `ride_end`.
- Debug and mock builds send nothing unless a developer turns it on locally. Mock builds report `flavor` as mock.
- The code is open. The list above is built from `TelemetryEvent.kt` and `TelemetryProps.kt` in `app/src/main/java/dev/digitalducktape/openride/core/telemetry/`, and each value can only be one of those fixed options.

Questions or concerns? [Open an issue](https://github.com/digitalducktape/openride/issues/new).
