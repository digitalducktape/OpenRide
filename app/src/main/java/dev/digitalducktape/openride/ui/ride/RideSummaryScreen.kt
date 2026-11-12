package dev.digitalducktape.openride.ui.ride

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.core.data.RideSample
import dev.digitalducktape.openride.games.session.GameLabels
import dev.digitalducktape.openride.ui.common.ExportShare
import dev.digitalducktape.openride.ui.common.GameBadge
import dev.digitalducktape.openride.ui.designsystem.BikePreview
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrIcons
import dev.digitalducktape.openride.ui.designsystem.OrShapes
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrAccentButton
import dev.digitalducktape.openride.ui.designsystem.component.OrChip
import dev.digitalducktape.openride.ui.designsystem.component.OrConfirmDialog
import dev.digitalducktape.openride.ui.designsystem.component.OrIconButton
import dev.digitalducktape.openride.ui.designsystem.component.OrEmptyState
import dev.digitalducktape.openride.ui.designsystem.component.OrEyebrow
import dev.digitalducktape.openride.ui.designsystem.component.OrLabel
import dev.digitalducktape.openride.ui.designsystem.component.OrPrimaryButton
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton
import dev.digitalducktape.openride.ui.designsystem.component.OrStarRating
import dev.digitalducktape.openride.ui.designsystem.component.OrStatBand
import dev.digitalducktape.openride.ui.theme.OpenRideTheme
import kotlinx.coroutines.launch

/**
 * Ride summary connected to its [RideSummaryViewModel] (the Route half of the Route/Screen
 * split): loads the ride by id, writes the TCX / CSV exports to a share sheet, applies the FTP
 * suggestion, and resets a just-finished session on Done before leaving.
 */
@Composable
fun RideSummaryRoute(
    viewModel: RideSummaryViewModel,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val ride by viewModel.ride.collectAsStateWithLifecycle()
    val samples by viewModel.samples.collectAsStateWithLifecycle()
    val suggestedFtp by viewModel.suggestedFtp.collectAsStateWithLifecycle()
    val ftpApplied by viewModel.ftpApplied.collectAsStateWithLifecycle()
    val gameBadge by viewModel.gameBadge.collectAsStateWithLifecycle()
    val gameResults by viewModel.gameResults.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    LaunchedEffect(Unit) { viewModel.load() }

    RideSummaryScreen(
        uiState = RideSummaryUiState(ride, samples, gameBadge, gameResults, suggestedFtp, ftpApplied),
        onExportTcx = {
            val id = ride?.id
            viewModel.tcxContent()?.let { tcx ->
                ExportShare.share(context, "ride_$id.tcx", tcx, "application/vnd.garmin.tcx+xml")
            }
        },
        onExportCsv = {
            val id = ride?.id
            viewModel.sampleCsvContent()?.let { csv -> ExportShare.share(context, "ride_$id.csv", csv, "text/csv") }
        },
        onApplyFtp = { scope.launch { viewModel.applySuggestedFtp() } },
        onDelete = {
            scope.launch {
                viewModel.deleteRide()
                onDismiss()
            }
        },
        onDone = {
            viewModel.dismiss()
            onDismiss()
        },
        modifier = modifier,
    )
}

/**
 * Post-ride summary and history detail (PRD P0-5, v2 metrics spec), stateless. One screen, no
 * scrolling (the rider's ask, 2026-10-21): a header with the exports and Done, then the metric
 * chips, the selected metric's TOTAL / AVG / MAX band and its graph on the left and, when there
 * is any, the games and the FTP suggestion on the right. Only a very long circuit's game list
 * scrolls, inside its column. The same screen serves a ride just stopped and one from History.
 * The trash icon in the header asks "Are you sure…?" before [onDelete] removes the ride.
 */
@Composable
fun RideSummaryScreen(
    uiState: RideSummaryUiState,
    onExportTcx: () -> Unit,
    onExportCsv: () -> Unit,
    onApplyFtp: () -> Unit,
    onDelete: () -> Unit,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedMetric by remember { mutableStateOf(RideMetric.Output) }
    var confirmDelete by remember { mutableStateOf(false) }
    val current = uiState.ride
    if (current == null) {
        OrEmptyState(message = "Loading…", modifier = modifier.background(OrColors.Background))
        return
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(OrColors.Background)
            .padding(horizontal = OrSpacing.ScreenGutter, vertical = OrSpacing.lg),
        verticalArrangement = Arrangement.spacedBy(OrSpacing.md),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(OrSpacing.md)) {
                    OrLabel(text = "Ride complete", style = OrType.ScreenTitle, color = OrColors.OnBackground)
                    uiState.gameBadge?.let { GameBadge(it) }
                }
                OrLabel(text = RideSummaryUiState.subtitle(current), style = OrType.Body, color = OrColors.OnSurfaceMuted)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(OrSpacing.md), verticalAlignment = Alignment.CenterVertically) {
                OrIconButton(
                    icon = OrIcons.Delete,
                    contentDescription = "Delete ride",
                    onClick = { confirmDelete = true },
                    tint = OrColors.OnSurfaceMuted,
                )
                OrSecondaryButton(text = "Export TCX", onClick = onExportTcx)
                OrSecondaryButton(text = "Export CSV", onClick = onExportCsv)
                OrPrimaryButton(text = "Done", onClick = onDone)
            }
        }

        Row(modifier = Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(OrSpacing.xl)) {
            Column(modifier = Modifier.weight(3f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(OrSpacing.md)) {
                Row(horizontalArrangement = Arrangement.spacedBy(OrSpacing.sm)) {
                    uiState.metrics.forEach { metric ->
                        OrChip(text = metric.chipLabel, selected = metric == selectedMetric, onClick = { selectedMetric = metric })
                    }
                }
                OrStatBand(
                    stats = RideSummaryUiState.stats(selectedMetric, current, uiState.samples),
                    labelColor = OrColors.Accent,
                    spacing = OrSpacing.xxl,
                )
                MetricGraph(
                    points = RideMetricStats.points(selectedMetric, uiState.samples),
                    modifier = Modifier.fillMaxWidth().weight(1f),
                )
            }
            if (uiState.hasSideColumn) {
                Column(modifier = Modifier.weight(2f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(OrSpacing.lg)) {
                    if (uiState.gameResults.isNotEmpty()) {
                        GameResultsList(rows = uiState.gameResults, modifier = Modifier.fillMaxWidth().weight(1f, fill = false))
                    }
                    uiState.suggestedFtp?.let { ftp ->
                        FtpSuggestionCard(
                            suggestedFtp = ftp,
                            applied = uiState.ftpApplied,
                            onApply = onApplyFtp,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
        }
    }

    if (confirmDelete) {
        OrConfirmDialog(
            title = "Delete ride?",
            text = "Are you sure you want to delete this ride?",
            confirmText = "Yes",
            dismissText = "No",
            onDismiss = { confirmDelete = false },
            onConfirm = {
                confirmDelete = false
                onDelete()
            },
        )
    }
}

/** "OUTPUT" as a chip label: "Output", "Heart rate". */
private val RideMetric.chipLabel: String
    get() = label.lowercase().replaceFirstChar { it.uppercase() }

/** A game session's segments (#35): each game, its role and difficulty, score and stars. */
@Composable
private fun GameResultsList(rows: List<GameLabels.ResultRow>, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(OrSpacing.sm)) {
        OrEyebrow(text = "Games")
        LazyColumn(verticalArrangement = Arrangement.spacedBy(OrSpacing.sm)) {
            items(rows) { row ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(color = OrColors.Surface, shape = OrShapes.Small)
                        .padding(horizontal = OrSpacing.md, vertical = OrSpacing.sm + OrSpacing.xs),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        OrLabel(text = row.title, style = OrType.Subtitle, color = OrColors.OnBackground)
                        OrLabel(text = row.detail, style = OrType.Caption, color = OrColors.OnSurfaceMuted)
                    }
                    if (!row.skipped) OrStarRating(stars = row.stars)
                }
            }
        }
    }
}

/**
 * Shown once a ride's per-second series spans at least 20 minutes (PRD P1-3): 95% of the
 * ride's best 20-minute average power, offered as an FTP update for the rider who logged it.
 */
@Composable
private fun FtpSuggestionCard(
    suggestedFtp: Int,
    applied: Boolean,
    onApply: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.background(OrColors.Surface, OrShapes.Small).padding(OrSpacing.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            OrLabel(text = "Estimated FTP: $suggestedFtp W", style = OrType.Subtitle, color = OrColors.OnBackground)
            Text(text = "95% of your best 20 minutes", style = OrType.Caption, color = OrColors.OnSurfaceMuted)
        }
        if (applied) {
            OrLabel(text = "FTP updated", style = OrType.Button, color = OrColors.Success)
        } else {
            OrAccentButton(text = "Update FTP", onClick = onApply)
        }
    }
}

@BikePreview
@Composable
private fun RideSummaryScreenPreview() {
    val ride = Ride(
        id = 7, profileId = 1, startEpochMs = 0, durationSec = 25 * 60, avgCadence = 82, maxCadence = 104,
        avgPower = 168, maxPower = 312, avgResistance = 41, outputKj = 252.0, calories = null,
    )
    val samples = (0..1500 step 10).map { t ->
        RideSample(rideId = 7, tSec = t, cadence = 80 + (t / 10) % 15, resistance = 40, power = 140 + (t / 7) % 90)
    }
    OpenRideTheme {
        RideSummaryScreen(
            uiState = RideSummaryUiState(
                ride = ride,
                samples = samples,
                gameBadge = "Demo · 20 min",
                gameResults = listOf(
                    GameLabels.ResultRow("Tug of War", "Work · Normal · 1,240", 2, skipped = false),
                    GameLabels.ResultRow("Safe Cracker", "Recovery · Easy · 860", 3, skipped = false),
                ),
                suggestedFtp = 214,
            ),
            onExportTcx = {},
            onExportCsv = {},
            onApplyFtp = {},
            onDelete = {},
            onDone = {},
        )
    }
}
