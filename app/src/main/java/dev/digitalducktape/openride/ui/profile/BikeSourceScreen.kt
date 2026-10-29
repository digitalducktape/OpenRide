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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import dev.digitalducktape.openride.core.heartrate.BleDevice
import dev.digitalducktape.openride.core.heartrate.BlePermissionState
import dev.digitalducktape.openride.core.heartrate.reduceBlePermissionState
import dev.digitalducktape.openride.core.heartrate.requiredBlePermissions
import dev.digitalducktape.openride.core.sensor.BikeMetrics
import dev.digitalducktape.openride.core.sensor.BikeSource
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
 * The bike source (issue #68) connected to its [BikeSourceViewModel]: the Route half, which owns
 * the Bluetooth permission ask, as [HrPairingRoute] does.
 *
 * @param realBike whether the built-in source is the Peloton's (the real build) or the simulation.
 */
@Composable
fun BikeSourceRoute(
    viewModel: BikeSourceViewModel,
    realBike: Boolean,
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
    }
    LaunchedEffect(Unit) { refreshPermissionState() }

    BikeSourceScreen(
        uiState = uiState,
        realBike = realBike,
        onRequestPermission = { permissionLauncher.launch(permissions) },
        onOpenAppSettings = {
            context.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)),
            )
        },
        onStartScan = viewModel::startScan,
        onStopScan = viewModel::stopScan,
        onUseTrainer = viewModel::useTrainer,
        onUseBuiltin = viewModel::useBuiltin,
        onDone = onDone,
        modifier = modifier,
    )
}

/**
 * The bike source, stateless. On the left the source in use (the built-in one, or the trainer
 * with its live numbers) and the scan; on the right the trainers the scan found, one tap to use.
 */
@Composable
fun BikeSourceScreen(
    uiState: BikeSourceViewModel.UiState,
    realBike: Boolean,
    onRequestPermission: () -> Unit,
    onOpenAppSettings: () -> Unit,
    onStartScan: () -> Unit,
    onStopScan: () -> Unit,
    onUseTrainer: (BleDevice) -> Unit,
    onUseBuiltin: () -> Unit,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val granted = uiState.permissionState == BlePermissionState.Granted
    Column(modifier = modifier.fillMaxSize().background(OrColors.Background)) {
        OrTopBar(title = "Bike", actions = { OrSecondaryButton(text = "Done", onClick = onDone) })
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(start = OrSpacing.ScreenGutter, end = OrSpacing.ScreenGutter, top = OrSpacing.sm, bottom = OrSpacing.lg),
            horizontalArrangement = Arrangement.spacedBy(OrSpacing.lg),
        ) {
            Column(modifier = Modifier.weight(2f), verticalArrangement = Arrangement.spacedBy(OrSpacing.lg)) {
                OrSettingsGroup(title = "Numbers from") {
                    val builtin = uiState.source == BikeSource.Builtin
                    OrSettingsRow(
                        title = BikeSourceLabels.builtinName(realBike),
                        value = BikeSourceLabels.builtinDetail(realBike),
                        valueColor = if (builtin) OrColors.Success else OrColors.OnSurfaceMuted,
                        trailing = if (builtin) null else {
                            { OrSecondaryButton(text = "Use", onClick = onUseBuiltin) }
                        },
                    )
                    (uiState.source as? BikeSource.Trainer)?.let { trainer ->
                        OrSettingsDivider()
                        OrSettingsRow(
                            title = BikeSourceLabels.trainerName(trainer),
                            value = BikeSourceLabels.trainerStatus(uiState.connection, uiState.metrics, uiState.adjustable),
                            valueColor = if (uiState.connection == ConnectionState.Connected) OrColors.Success else OrColors.OnSurfaceMuted,
                        )
                    }
                }
                if (granted) {
                    OrTile(modifier = Modifier.fillMaxWidth()) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(OrSpacing.md)) {
                            OrAccentButton(
                                text = BikeSourceLabels.scanAction(uiState.isScanning),
                                onClick = { if (uiState.isScanning) onStopScan() else onStartScan() },
                            )
                            if (uiState.isScanning) {
                                OrSpinner()
                                Text(text = "Scanning…", style = OrType.Body, color = OrColors.OnSurfaceMuted)
                            }
                        }
                        uiState.error?.let {
                            Text(text = it, style = OrType.Body, color = OrColors.Warning, modifier = Modifier.padding(top = OrSpacing.md))
                        }
                    }
                }
            }

            Column(modifier = Modifier.weight(3f)) {
                OrEyebrow(text = "Nearby smart trainers", modifier = Modifier.padding(start = OrSpacing.md, bottom = OrSpacing.sm))
                val prompt = BikeSourceLabels.permissionPrompt(uiState.permissionState)
                val emptyHint = BikeSourceLabels.emptyHint(uiState)
                when {
                    prompt != null -> OrTile(modifier = Modifier.fillMaxWidth()) {
                        Text(text = prompt.message, style = OrType.Body, color = OrColors.OnBackground)
                        OrAccentButton(
                            text = prompt.actionLabel,
                            onClick = if (prompt.opensAppSettings) onOpenAppSettings else onRequestPermission,
                            modifier = Modifier.padding(top = OrSpacing.lg),
                        )
                    }
                    uiState.nearby.isNotEmpty() -> LazyColumn(
                        modifier = Modifier.fillMaxWidth().clip(OrShapes.Medium).background(OrColors.Surface),
                    ) {
                        itemsIndexed(uiState.nearby, key = { _, device -> device.address }) { index, device ->
                            if (index > 0) OrSettingsDivider()
                            OrSettingsRow(
                                title = BikeSourceLabels.deviceName(device.name),
                                value = device.address,
                                onClick = { onUseTrainer(device) },
                                trailing = { OrSecondaryButton(text = "Use", onClick = { onUseTrainer(device) }) },
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
private fun BikeSourceScreenPreview() {
    OpenRideTheme {
        BikeSourceScreen(
            uiState = BikeSourceViewModel.UiState(
                permissionState = BlePermissionState.Granted,
                source = BikeSource.Trainer("C4:7F:51:0A:22:9E", "KICKR CORE 1A2B"),
                connection = ConnectionState.Connected,
                metrics = BikeMetrics(cadenceRpm = 88, resistancePercent = 35, powerWatts = 182, speedMph = 18.2),
                adjustable = true,
                devices = listOf(BleDevice("E1:02:33:44:55:66", "Tacx Neo 2T")),
            ),
            realBike = true,
            onRequestPermission = {},
            onOpenAppSettings = {},
            onStartScan = {},
            onStopScan = {},
            onUseTrainer = {},
            onUseBuiltin = {},
            onDone = {},
        )
    }
}
