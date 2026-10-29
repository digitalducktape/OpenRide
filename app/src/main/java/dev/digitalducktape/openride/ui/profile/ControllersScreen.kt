package dev.digitalducktape.openride.ui.profile

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.digitalducktape.openride.core.controller.ControllerAction
import dev.digitalducktape.openride.core.controller.ControllerStatus
import dev.digitalducktape.openride.core.controller.ControllerTransport
import dev.digitalducktape.openride.core.controller.PairedController
import dev.digitalducktape.openride.core.heartrate.BlePermissionState
import dev.digitalducktape.openride.core.heartrate.reduceBlePermissionState
import dev.digitalducktape.openride.core.heartrate.requiredBlePermissions
import dev.digitalducktape.openride.core.sensor.ConnectionState
import dev.digitalducktape.openride.ui.designsystem.BikePreview
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrShapes
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrAccentButton
import dev.digitalducktape.openride.ui.designsystem.component.OrEyebrow
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton
import dev.digitalducktape.openride.ui.designsystem.component.OrSettingsDivider
import dev.digitalducktape.openride.ui.designsystem.component.OrSettingsGroup
import dev.digitalducktape.openride.ui.designsystem.component.OrSettingsRow
import dev.digitalducktape.openride.ui.designsystem.component.OrSpinner
import dev.digitalducktape.openride.ui.designsystem.component.OrTile
import dev.digitalducktape.openride.ui.designsystem.component.OrTopBar
import dev.digitalducktape.openride.ui.theme.OpenRideTheme

/**
 * OpenBikeControl controllers (issue #68) connected to their [ControllersViewModel]: the Route
 * half, which owns the Bluetooth permission ask (as [HrPairingRoute] does) and starts a search
 * as the screen opens, since the network half needs no permission.
 */
@Composable
fun ControllersRoute(
    viewModel: ControllersViewModel,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val permissions = remember { requiredBlePermissions() }
    var everRequested by remember { mutableStateOf(false) }

    fun refreshPermissionState() {
        viewModel.onPermissionState(
            reduceBlePermissionState(
                permissions = permissions,
                granted = { ContextCompat.checkSelfPermission(context, it) == android.content.pm.PackageManager.PERMISSION_GRANTED },
                shouldShowRationale = { permission ->
                    val activity = context as? android.app.Activity
                    activity != null && androidx.core.app.ActivityCompat.shouldShowRequestPermissionRationale(activity, permission)
                },
                everRequested = everRequested,
            ),
        )
    }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        everRequested = true
        refreshPermissionState()
        // Search again, now with Bluetooth if it was granted.
        viewModel.startScan()
    }

    LaunchedEffect(Unit) {
        refreshPermissionState()
        viewModel.startScan()
    }
    DisposableEffect(Unit) { onDispose { viewModel.stopScan() } }

    ControllersScreen(
        uiState = uiState,
        onRequestPermission = { permissionLauncher.launch(permissions) },
        onOpenAppSettings = {
            context.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)),
            )
        },
        onStartScan = viewModel::startScan,
        onStopScan = viewModel::stopScan,
        onPair = viewModel::pair,
        onForget = viewModel::forget,
        onDone = onDone,
        modifier = modifier,
    )
}

/**
 * Controllers, stateless. On the left the paired controllers (each with its connection and
 * Forget), the last button pressed, and the search; on the right what the search found, one tap
 * to pair, under the Bluetooth permission ask while it's missing.
 */
@Composable
fun ControllersScreen(
    uiState: ControllersViewModel.UiState,
    onRequestPermission: () -> Unit,
    onOpenAppSettings: () -> Unit,
    onStartScan: () -> Unit,
    onStopScan: () -> Unit,
    onPair: (PairedController) -> Unit,
    onForget: (PairedController) -> Unit,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize().background(OrColors.Background)) {
        OrTopBar(
            title = "Controllers",
            actions = { OrSecondaryButton(text = "Done", onClick = onDone) },
        )
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(start = OrSpacing.ScreenGutter, end = OrSpacing.ScreenGutter, top = OrSpacing.sm, bottom = OrSpacing.lg),
            horizontalArrangement = Arrangement.spacedBy(OrSpacing.lg),
        ) {
            Column(
                modifier = Modifier.weight(2f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(OrSpacing.lg),
            ) {
                OrSettingsGroup(title = "Paired controllers") {
                    if (uiState.paired.isEmpty()) {
                        OrSettingsRow(title = "No controller paired", value = "Pick one from the search to pair it")
                    }
                    uiState.paired.forEachIndexed { index, controller ->
                        if (index > 0) OrSettingsDivider()
                        val status = uiState.statusOf(controller)
                        OrSettingsRow(
                            title = ControllersLabels.title(controller),
                            value = ControllersLabels.status(controller, status),
                            valueColor = if (ControllersLabels.live(status)) OrColors.Success else OrColors.OnSurfaceMuted,
                            trailing = { OrSecondaryButton(text = "Forget", onClick = { onForget(controller) }) },
                        )
                    }
                }
                if (uiState.paired.isNotEmpty()) {
                    OrTile(modifier = Modifier.fillMaxWidth()) {
                        Text(text = ControllersLabels.lastPress(uiState.lastPress), style = OrType.Body, color = OrColors.OnBackground)
                    }
                }
                OrTile(modifier = Modifier.fillMaxWidth()) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(OrSpacing.md)) {
                        OrAccentButton(
                            text = ControllersLabels.scanAction(uiState.isScanning),
                            onClick = { if (uiState.isScanning) onStopScan() else onStartScan() },
                        )
                        if (uiState.isScanning) {
                            OrSpinner()
                            Text(text = "Searching…", style = OrType.Body, color = OrColors.OnSurfaceMuted)
                        }
                    }
                    uiState.error?.let {
                        Text(text = it, style = OrType.Body, color = OrColors.Warning, modifier = Modifier.padding(top = OrSpacing.md))
                    }
                }
            }

            Column(modifier = Modifier.weight(3f), verticalArrangement = Arrangement.spacedBy(OrSpacing.md)) {
                OrEyebrow(text = "Nearby controllers", modifier = Modifier.padding(start = OrSpacing.md))
                ControllersLabels.permissionPrompt(uiState.permissionState)?.let { prompt ->
                    OrTile(modifier = Modifier.fillMaxWidth()) {
                        Text(text = prompt.message, style = OrType.Body, color = OrColors.OnBackground)
                        OrSecondaryButton(
                            text = prompt.actionLabel,
                            onClick = if (prompt.opensAppSettings) onOpenAppSettings else onRequestPermission,
                            modifier = Modifier.padding(top = OrSpacing.md),
                        )
                    }
                }
                val emptyHint = ControllersLabels.emptyHint(uiState)
                when {
                    uiState.nearby.isNotEmpty() -> LazyColumn(
                        modifier = Modifier.fillMaxWidth().clip(OrShapes.Medium).background(OrColors.Surface),
                    ) {
                        itemsIndexed(uiState.nearby, key = { _, c -> "${c.transport}:${c.id}" }) { index, controller ->
                            if (index > 0) OrSettingsDivider()
                            OrSettingsRow(
                                title = ControllersLabels.title(controller),
                                value = ControllersLabels.found(controller),
                                onClick = { onPair(controller) },
                                trailing = { OrSecondaryButton(text = "Pair", onClick = { onPair(controller) }) },
                            )
                        }
                    }
                    emptyHint != null -> OrTile(modifier = Modifier.fillMaxWidth()) {
                        Text(text = emptyHint, style = OrType.Body, color = OrColors.OnSurfaceMuted)
                    }
                }
            }
        }
    }
}

@BikePreview
@Composable
private fun ControllersScreenPreview() {
    val phone = PairedController(ControllerTransport.NETWORK, "BikeControl Pixel", "BikeControl Pixel")
    OpenRideTheme {
        ControllersScreen(
            uiState = ControllersViewModel.UiState(
                permissionState = BlePermissionState.Granted,
                isScanning = true,
                paired = listOf(phone),
                statuses = listOf(ControllerStatus(phone, ConnectionState.Connected, 80)),
                lastPress = ControllerAction.RESISTANCE_UP,
                found = listOf(PairedController(ControllerTransport.BLUETOOTH, "D1:22:33:44:55:66", "SB200")),
            ),
            onRequestPermission = {},
            onOpenAppSettings = {},
            onStartScan = {},
            onStopScan = {},
            onPair = {},
            onForget = {},
            onDone = {},
        )
    }
}
