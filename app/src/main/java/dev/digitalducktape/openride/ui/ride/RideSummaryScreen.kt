package dev.digitalducktape.openride.ui.ride

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.digitalducktape.openride.games.session.GameLabels
import dev.digitalducktape.openride.ui.common.ExportShare
import dev.digitalducktape.openride.ui.common.GameBadge
import dev.digitalducktape.openride.ui.common.TimeFormat
import dev.digitalducktape.openride.ui.theme.MetricTextStyles
import dev.digitalducktape.openride.ui.theme.OpenRideColors
import kotlinx.coroutines.launch

/**
 * Post-ride summary and history detail (PRD P0-5, v2 metrics spec): a metric tab row
 * (Output / Cadence / Resistance / Heart-Rate-when-recorded) selecting which per-second
 * series the graph draws and which headline stats sit above it — after the original bike
 * UI's per-ride view. Reused unmodified as history's detail view (T8) — [viewModel] loads
 * by ride id from Room either way, so this screen never needs to know whether it's showing
 * a ride just stopped or one from history.
 */
@Composable
fun RideSummaryScreen(
    viewModel: RideSummaryViewModel,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val ride by viewModel.ride.collectAsState()
    val samples by viewModel.samples.collectAsState()
    val suggestedFtp by viewModel.suggestedFtp.collectAsState()
    val ftpApplied by viewModel.ftpApplied.collectAsState()
    val gameBadge by viewModel.gameBadge.collectAsState()
    val gameResults by viewModel.gameResults.collectAsState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var selectedMetric by remember { mutableStateOf(RideMetric.Output) }

    LaunchedEffect(Unit) { viewModel.load() }

    Surface(modifier = modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 48.dp, vertical = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            val current = ride
            if (current == null) {
                Text(
                    text = "Loading…",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 32.dp),
                )
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column {
                        Text(
                            text = "Ride complete",
                            style = MaterialTheme.typography.headlineLarge,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onBackground,
                        )
                        Text(
                            text = "${TimeFormat.elapsed(current.durationSec)} · " +
                                (current.calories?.let { "$it kcal" } ?: "%.0f kJ".format(current.outputKj)),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                        gameBadge?.let { GameBadge(it, modifier = Modifier.padding(top = 8.dp)) }
                    }
                }

                Column(modifier = Modifier.fillMaxWidth().padding(top = 24.dp)) {
                    MetricTabRow(
                        metrics = RideMetric.available(samples),
                        selected = selectedMetric,
                        onSelect = { selectedMetric = it },
                    )

                    StatBand(
                        stats = RideMetricStats.stats(selectedMetric, current, samples),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 24.dp),
                    )

                    MetricGraph(
                        points = RideMetricStats.points(selectedMetric, samples),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 20.dp),
                    )

                    if (gameResults.isNotEmpty()) {
                        GameResultsList(
                            rows = gameResults,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 24.dp),
                        )
                    }

                    ExportRow(
                        onExportTcx = {
                            viewModel.tcxContent()?.let { tcx ->
                                ExportShare.share(context, "ride_${current.id}.tcx", tcx, "application/vnd.garmin.tcx+xml")
                            }
                        },
                        onExportCsv = {
                            viewModel.sampleCsvContent()?.let { csv ->
                                ExportShare.share(context, "ride_${current.id}.csv", csv, "text/csv")
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 24.dp),
                    )

                    if (suggestedFtp != null) {
                        FtpSuggestionCard(
                            suggestedFtp = suggestedFtp!!,
                            applied = ftpApplied,
                            onApply = { scope.launch { viewModel.applySuggestedFtp() } },
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 24.dp),
                        )
                    }
                }
            }

            Button(
                onClick = {
                    viewModel.dismiss()
                    onDismiss()
                },
                modifier = Modifier.padding(top = 40.dp),
            ) {
                Text("Done")
            }
        }
    }
}

/** A game session's segments (#35): each game, its role and difficulty, score and stars. */
@Composable
private fun GameResultsList(rows: List<GameLabels.ResultRow>, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = "Games",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onBackground,
        )
        rows.forEach { row ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(color = MaterialTheme.colorScheme.surface, shape = RoundedCornerShape(12.dp))
                    .padding(horizontal = 20.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text(
                        text = row.title,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onBackground,
                    )
                    Text(
                        text = row.detail,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (!row.skipped) {
                    Text(
                        text = "★".repeat(row.stars) + "☆".repeat(3 - row.stars),
                        style = MaterialTheme.typography.titleLarge,
                        color = OpenRideColors.Accent,
                    )
                }
            }
        }
    }
}

/**
 * Export actions (PRD P1-1/P1-2, T14): a TCX file (with the full per-second series, for
 * Apple Health via a third-party bridge app) and a plain per-second CSV, both handed to the
 * Android share sheet via [ExportShare].
 */
@Composable
private fun ExportRow(
    onExportTcx: () -> Unit,
    onExportCsv: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        OutlinedButton(onClick = onExportTcx) { Text("Export TCX") }
        OutlinedButton(onClick = onExportCsv) { Text("Export CSV") }
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
    Column(modifier = modifier) {
        Text(
            text = "Estimated FTP: ${suggestedFtp}W",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onBackground,
        )
        Text(
            text = "95% of your best 20-minute average power this ride",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (applied) {
            Text(
                text = "FTP updated",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(top = 8.dp),
            )
        } else {
            Button(onClick = onApply, modifier = Modifier.padding(top = 8.dp)) {
                Text("Update my FTP")
            }
        }
    }
}

/** Pill tab row selecting the graphed metric, after the original bike UI's tab strip. */
@Composable
private fun MetricTabRow(
    metrics: List<RideMetric>,
    selected: RideMetric,
    onSelect: (RideMetric) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        metrics.forEach { metric ->
            val isSelected = metric == selected
            Box(
                modifier = Modifier
                    .background(
                        color = if (isSelected) OpenRideColors.Accent else MaterialTheme.colorScheme.surface,
                        shape = RoundedCornerShape(20.dp),
                    )
                    .clickable { onSelect(metric) }
                    .padding(horizontal = 18.dp, vertical = 8.dp),
            ) {
                Text(
                    text = metric.label,
                    style = MetricTextStyles.TileLabel,
                    color = if (isSelected) {
                        MaterialTheme.colorScheme.onBackground
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
        }
    }
}

/** TOTAL / AVG / MAX headline stats for the selected metric. */
@Composable
private fun StatBand(stats: List<MetricStat>, modifier: Modifier = Modifier) {
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(48.dp)) {
        stats.forEach { stat ->
            Column {
                Text(
                    text = stat.label,
                    style = MetricTextStyles.TileLabel,
                    color = MaterialTheme.colorScheme.primary,
                )
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        text = stat.value,
                        style = MetricTextStyles.TileValueLarge,
                        color = MaterialTheme.colorScheme.onBackground,
                    )
                    Text(
                        text = stat.unit,
                        style = MetricTextStyles.UnitLabel,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 6.dp, bottom = 10.dp),
                    )
                }
            }
        }
    }
}
