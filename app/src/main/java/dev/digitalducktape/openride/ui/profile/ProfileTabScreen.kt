package dev.digitalducktape.openride.ui.profile

import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
import dev.digitalducktape.openride.core.backup.MediaStoreAutoBackupStore
import dev.digitalducktape.openride.core.controller.ControllerStatus
import dev.digitalducktape.openride.core.sensor.ConnectionState
import dev.digitalducktape.openride.core.music.MusicApp
import dev.digitalducktape.openride.core.route.RouteHolder
import dev.digitalducktape.openride.ui.common.ExportShare
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.ui.common.ProfileAvatar
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrConfirmDialog
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton
import dev.digitalducktape.openride.ui.designsystem.component.OrSettingsDivider
import dev.digitalducktape.openride.ui.designsystem.component.OrSettingsGroup
import dev.digitalducktape.openride.ui.designsystem.component.OrSettingsRow
import dev.digitalducktape.openride.ui.music.MusicAppPicker
import kotlinx.coroutines.launch

/** Width of the Profile tab's rider column. */

/**
 * Profile nav tab: shows the active rider, offers "Switch rider" (PRD P0-3/P1-6 — tap-to-
 * confirm before clearing the active profile and returning to profile select, so a stray tap
 * mid-session can't silently log the next ride under the wrong rider), quick shortcuts to
 * stock Android Wi-Fi/device settings (PRD P1-5, T12), the home-screen switch (#47), and whole-database backup/restore
 * (PRD P1-8, T15). Laid out as the rider on the left and grouped settings rows on the right
 * (Ride, Classes, Device, Music, Backup & restore), every row a 72 dp touch target.
 */
@Composable
fun ProfileTabScreen(
    viewModel: ProfileTabViewModel,
    /** The app's always-loaded rider (`AppContainer.activeProfile`), so the first frame has it. */
    activeProfile: Profile?,
    onEditProfile: () -> Unit,
    onRestoreComplete: () -> Unit,
    onManageHeartRateStrap: () -> Unit,
    /** The paired OpenBikeControl controllers and their connections (#68). */
    controllers: List<ControllerStatus>,
    onManageControllers: () -> Unit,
    onManageAppUpdates: () -> Unit,
    onManageContentSources: () -> Unit,
    routeHolder: RouteHolder,
    /** The app the music player's button opens, chosen here; null before one is. */
    musicApp: MusicApp?,
    onMusicAppChosen: (MusicApp) -> Unit,
    /** Whether the rider has given OpenRide Notification access, which the mini player needs. */
    musicControlsOn: Boolean,
    onManageMusicControls: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val activeRoute by routeHolder.activeRoute.collectAsState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    var pendingRestoreContent by remember { mutableStateOf<String?>(null) }
    var restoreError by remember { mutableStateOf<String?>(null) }

    var routeError by remember { mutableStateOf<String?>(null) }
    var pickingMusicApp by remember { mutableStateOf(false) }

    // The home-screen alias (#47, #63). Re-read on resume: the default is picked in a system
    // dialog or the Home settings page, outside this screen.
    var isHome by remember { mutableStateOf(HomeScreenLauncher.isHome(context)) }
    var homeError by remember { mutableStateOf<String?>(null) }
    var confirmHomeOff by remember { mutableStateOf(false) }
    LifecycleResumeEffect(Unit) {
        isHome = HomeScreenLauncher.isHome(context)
        onPauseOrDispose {}
    }
    val chooseDefaultHome = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        isHome = HomeScreenLauncher.settleAfterChoosing(context)
    }

    // GPX route import (PRD #21/T21). GetContent rather than a typed picker because GPX has no
    // reliably-registered MIME type across file providers — "*/*" keeps every provider listing it.
    val pickRouteFile = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val loaded = runCatching {
            context.contentResolver.openInputStream(uri)?.use { routeHolder.load(it) }
        }.getOrNull()
        routeError = if (loaded == null) "Couldn't read that file as a GPX route" else null
    }

    val pickBackupFile = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
        if (text != null) pendingRestoreContent = text
    }

    // One page, no scrolling (the rider's ask, 2026-10-21): three columns of groups under the
    // shared top bar, which carries the rider and Switch rider; Edit profile is a setting like
    // the rest. The tallest column is about 360 dp of the 528 between the bars, leaving room for
    // a notice.
    Row(
        modifier = modifier
            .fillMaxSize()
            .padding(start = OrSpacing.ScreenGutter, end = OrSpacing.ScreenGutter, top = OrSpacing.sm, bottom = OrSpacing.lg),
        horizontalArrangement = Arrangement.spacedBy(OrSpacing.lg),
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(OrSpacing.lg)) {
            OrSettingsGroup(title = "Rider") {
                OrSettingsRow(
                    title = "Edit profile",
                    value = activeProfile?.let(ProfileTabLabels::riderDetails) ?: "Name, weight, FTP, avatar",
                    onClick = onEditProfile,
                )
            }

            OrSettingsGroup(title = "Ride") {
                val paired = activeProfile?.pairedHrDeviceAddress != null
                OrSettingsRow(
                    title = "Heart-rate strap",
                    value = ProfileTabLabels.heartRateStrap(paired),
                    valueColor = if (paired) OrColors.Success else OrColors.OnSurfaceMuted,
                    onClick = onManageHeartRateStrap,
                )
                OrSettingsDivider()
                val controllersLive = controllers.any { it.connection == ConnectionState.Connected }
                OrSettingsRow(
                    title = "Controllers",
                    value = ProfileTabLabels.controllers(controllers.size, controllers.count { it.connection == ConnectionState.Connected }),
                    valueColor = if (controllersLive) OrColors.Success else OrColors.OnSurfaceMuted,
                    onClick = onManageControllers,
                )
                OrSettingsDivider()
                // GPX route import (PRD #21/T21).
                OrSettingsRow(
                    title = "Route (GPX)",
                    value = routeError
                        ?: activeRoute?.let { ProfileTabLabels.routeSummary(it.name, it.totalDistanceMeters) }
                        ?: "No route loaded",
                    valueColor = if (routeError != null) OrColors.Warning else OrColors.OnSurfaceMuted,
                ) {
                    if (activeRoute != null) {
                        OrSecondaryButton(text = "Clear", onClick = {
                            routeHolder.clear()
                            routeError = null
                        })
                    }
                    OrSecondaryButton(
                        text = if (activeRoute == null) "Load route" else "Change",
                        onClick = { pickRouteFile.launch("*/*") },
                    )
                }
            }

            OrSettingsGroup(title = "Classes") {
                OrSettingsRow(
                    title = "Content sources",
                    value = "Your creators and playlists",
                    onClick = onManageContentSources,
                )
            }
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(OrSpacing.lg)) {
            // PRD P1-5 (T12): stock Android settings, for when OpenRide is the tablet's launcher.
            OrSettingsGroup(title = "Device") {
                OrSettingsRow(
                    title = "Wi-Fi",
                    value = "Android Wi-Fi settings",
                    onClick = { launchSettings(context, Settings.ACTION_WIFI_SETTINGS) },
                )
                OrSettingsDivider()
                OrSettingsRow(
                    title = "Device settings",
                    value = "Volume, display, Bluetooth",
                    onClick = { launchSettings(context, Settings.ACTION_SETTINGS) },
                )
                OrSettingsDivider()
                OrSettingsRow(
                    title = "Home screen",
                    value = homeError ?: ProfileTabLabels.homeScreen(isHome),
                    valueColor = when {
                        homeError != null -> OrColors.Warning
                        isHome -> OrColors.Success
                        else -> OrColors.OnSurfaceMuted
                    },
                ) {
                    // One button: two side by side squeezed the title to a word per line.
                    if (isHome) {
                        OrSecondaryButton(text = "Turn off", onClick = {
                            if (HomeScreenLauncher.hasOtherHome(context)) {
                                confirmHomeOff = true
                            } else {
                                homeError = "No other home app to fall back to"
                            }
                        })
                    } else {
                        OrSecondaryButton(text = "Turn on", onClick = {
                            homeError = null
                            HomeScreenLauncher.setEnabled(context, true)
                            isHome = HomeScreenLauncher.isHome(context)
                            if (!isHome) chooseDefaultHome.launch(HomeScreenLauncher.chooseDefaultIntent(context))
                        })
                    }
                }
                OrSettingsDivider()
                OrSettingsRow(title = "App updates", onClick = onManageAppUpdates)
            }
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(OrSpacing.lg)) {
            // The music player's two settings (rider's ask, 2026-10-27): which app its button
            // opens, and the permission that lets it show what's playing. Here, not under Device:
            // with the Home screen row, the middle column outgrew the page.
            OrSettingsGroup(title = "Music") {
                OrSettingsRow(
                    title = "Music app",
                    value = ProfileTabLabels.musicApp(musicApp?.label),
                    onClick = { pickingMusicApp = true },
                )
                OrSettingsDivider()
                // The player reads other apps' media sessions, which Android only allows with
                // Notification access; the row says so before Android's own warning does.
                OrSettingsRow(
                    title = "Now playing",
                    value = ProfileTabLabels.musicControls(musicControlsOn),
                    valueColor = if (musicControlsOn) OrColors.Success else OrColors.OnSurfaceMuted,
                    onClick = onManageMusicControls,
                )
            }

            // Whole-database backup and restore (PRD P1-8, T15).
            OrSettingsGroup(title = "Backup & restore") {
                OrSettingsRow(
                    title = "Back up",
                    value = "Every rider and ride, as a file",
                    onClick = {
                        scope.launch {
                            val backup = viewModel.createBackupContent()
                            ExportShare.share(context, "openride_backup.json", backup, "application/json")
                        }
                    },
                )
                OrSettingsDivider()
                OrSettingsRow(
                    title = "Restore from file",
                    value = restoreError ?: "Replaces everything on this bike",
                    valueColor = if (restoreError != null) OrColors.Warning else OrColors.OnSurfaceMuted,
                    onClick = { pickBackupFile.launch("application/json") },
                )
            }
            Text(
                // The folder only: the full file name wrapped over four lines in the column.
                text = "Also saved after every ride to " + MediaStoreAutoBackupStore.RELATIVE_PATH.trimEnd('/'),
                style = OrType.Caption,
                color = OrColors.OnSurfaceMuted,
                modifier = Modifier.padding(horizontal = OrSpacing.md),
            )
        }
    }

    if (confirmHomeOff) {
        OrConfirmDialog(
            title = "Stop using OpenRide as home?",
            text = "The bike will start into another home app instead. You can turn this back on here.",
            confirmText = "Turn off",
            onDismiss = { confirmHomeOff = false },
            onConfirm = {
                confirmHomeOff = false
                HomeScreenLauncher.setEnabled(context, false)
                isHome = HomeScreenLauncher.isHome(context)
            },
        )
    }

    if (pickingMusicApp) {
        MusicAppPicker(
            selected = musicApp?.packageName,
            onDismiss = { pickingMusicApp = false },
            onPick = {
                pickingMusicApp = false
                onMusicAppChosen(it)
            },
        )
    }

    // Destructive confirmation (tap-to-confirm, matching the End Ride pattern elsewhere in the
    // app) — restoring wipes every profile and ride currently on the device.
    pendingRestoreContent?.let { content ->
        OrConfirmDialog(
            title = "Restore backup?",
            text = "This replaces ALL profiles and ride history on this device with the backup file's contents. This can't be undone.",
            confirmText = "Restore",
            destructive = true,
            onDismiss = { pendingRestoreContent = null },
            onConfirm = {
                pendingRestoreContent = null
                scope.launch {
                    viewModel.restoreFromContent(content).fold(
                        onSuccess = {
                            restoreError = null
                            onRestoreComplete()
                        },
                        onFailure = { error ->
                            restoreError = "Restore failed: ${error.message ?: "invalid backup file"}"
                        },
                    )
                }
            },
        )
    }
}
