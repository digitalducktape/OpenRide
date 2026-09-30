package dev.digitalducktape.openride.ui.history

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.digitalducktape.openride.ui.common.ExportShare
import dev.digitalducktape.openride.ui.common.GameBadge
import dev.digitalducktape.openride.ui.common.TimeFormat
import dev.digitalducktape.openride.ui.theme.MetricTextStyles
import java.time.YearMonth
import kotlinx.coroutines.launch

/**
 * History tab (PRD P0-5): the active profile's rides, newest first (date, duration, output
 * kJ, avg cadence). Tapping a row opens the same [dev.digitalducktape.openride.ui.ride.RideSummaryScreen]
 * used right after a ride, loading that ride's samples from Room only when opened — the list
 * itself never touches per-ride sample data, which is what keeps 100+ rows smooth.
 */
@Composable
fun HistoryScreen(
    viewModel: HistoryViewModel,
    onRideSelected: (rideId: Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    val rows by viewModel.rows.collectAsState(initial = emptyList())
    val stats by viewModel.stats.collectAsState(initial = HistoryStats.from(emptyList()))
    val rideDates by viewModel.rideDates.collectAsState(initial = emptySet())
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var month by remember { mutableStateOf(YearMonth.now()) }

    Surface(modifier = modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(modifier = Modifier.fillMaxSize().padding(horizontal = 48.dp, vertical = 32.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "History",
                    style = MaterialTheme.typography.headlineLarge,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onBackground,
                )
                if (rows.isNotEmpty()) {
                    OutlinedButton(onClick = {
                        scope.launch {
                            val csv = viewModel.historyCsvContent()
                            ExportShare.share(context, "ride_history.csv", csv, "text/csv")
                        }
                    }) {
                        Text("Export CSV")
                    }
                }
            }

            if (rows.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = "No rides yet — finish a ride to see it here",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                StatsBand(stats = stats, modifier = Modifier.fillMaxWidth().padding(top = 20.dp))

                // Below the band: ride list on the left, calendar + records on the right —
                // the landscape split of the profile-overview references.
                Row(modifier = Modifier.fillMaxSize().padding(top = 20.dp)) {
                    LazyColumn(modifier = Modifier.weight(1f)) {
                        items(rows, key = { it.rideId }) { row ->
                            RideHistoryListItem(row = row, onClick = { onRideSelected(row.rideId) })
                        }
                    }
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .padding(start = 40.dp),
                    ) {
                        RideCalendar(
                            month = month,
                            rideDates = rideDates,
                            onMonthChange = { month = it },
                        )
                        RecordsBand(stats = stats, modifier = Modifier.fillMaxWidth().padding(top = 24.dp))
                    }
                }
            }
        }
    }
}

/** Lifetime totals band: rides / time / total output, big-number-small-eyebrow style. */
@Composable
private fun StatsBand(stats: HistoryStats, modifier: Modifier = Modifier) {
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(56.dp)) {
        StatBlock(label = "TOTAL RIDES", value = "${stats.totalRides}", unit = null)
        StatBlock(label = "TOTAL TIME", value = TimeFormat.elapsed(stats.totalDurationSec.toInt()), unit = null)
        StatBlock(label = "TOTAL OUTPUT", value = "%.0f".format(stats.totalOutputKj), unit = "KJ")
    }
}

/** Personal records: best ride output, best avg power, longest ride. */
@Composable
private fun RecordsBand(stats: HistoryStats, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        Text(
            text = "PERSONAL RECORDS",
            style = MetricTextStyles.SectionEyebrow,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(40.dp),
        ) {
            StatBlock(label = "BEST RIDE", value = "%.0f".format(stats.bestOutputKj ?: 0.0), unit = "KJ")
            StatBlock(label = "BEST AVG", value = "${stats.bestAvgPower ?: 0}", unit = "WATTS")
            StatBlock(label = "LONGEST", value = TimeFormat.elapsed(stats.longestRideSec ?: 0), unit = null)
        }
    }
}

@Composable
private fun StatBlock(label: String, value: String, unit: String?, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        Text(
            text = label,
            style = MetricTextStyles.TileLabel,
            color = MaterialTheme.colorScheme.primary,
        )
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = value,
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground,
            )
            if (unit != null) {
                Text(
                    text = unit,
                    style = MetricTextStyles.UnitLabel,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 5.dp, bottom = 5.dp),
                )
            }
        }
    }
}

@Composable
private fun RideHistoryListItem(row: RideHistoryRow, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 12.dp)
            .background(color = MaterialTheme.colorScheme.surface, shape = RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(20.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column {
            Text(
                text = row.dateLabel,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Text(
                text = row.durationLabel,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            row.gameBadge?.let { GameBadge(it, modifier = Modifier.padding(top = 6.dp)) }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                text = row.outputKjLabel,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Text(
                text = row.avgCadenceLabel,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
