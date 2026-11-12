package dev.digitalducktape.openride.ui.ride

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrSize
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrEyebrow
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton
import dev.digitalducktape.openride.ui.designsystem.zoneColor

/**
 * The two-tier in-ride metrics panel (v2 redesign spec's signature element, refined against
 * the bike app's in-class layout):
 *
 * - **Primary row** — the three big numbers: CADENCE / OUTPUT / RESISTANCE, each flanked
 *   left by its running AVG (with an up/down trend arrow vs. the current reading) and right
 *   by its BEST, unit in tracked caps under the value. Resistance has no BEST flank — the
 *   session aggregates deliberately don't track a max for it.
 * - **Secondary strip** — SPEED / DISTANCE / TOTAL OUTPUT (+ HEART RATE once a strap is
 *   paired), smaller, label-and-unit before the value.
 *
 * Over video ([translucent]) the panel sits on a bottom-up black gradient rather than a
 * card, exactly like the class player; on the plain in-ride screen it gets a solid surface.
 * Values follow PRD P0-9: "--" whenever the sensor feed is down, never a fake zero.
 */
@Composable
fun RideMetricsBar(
    uiState: InRideUiState,
    translucent: Boolean,
    modifier: Modifier = Modifier,
    /** A step of a trainer's resistance (#68), from the − and + beside the reading. */
    onStepResistance: (Int) -> Unit = {},
) {
    val background = if (translucent) {
        Modifier.background(
            Brush.verticalGradient(
                0f to Color.Transparent,
                VideoScrimFadeEnd to VideoScrimLabels,
                1f to VideoScrimBottom,
            ),
        )
    } else {
        Modifier.background(OrColors.Surface)
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .then(background)
            .padding(top = if (translucent) OrSpacing.xl else OrSpacing.md, bottom = OrSpacing.md),
    ) {
        PrimaryRow(uiState, onStepResistance)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = OrSpacing.lg, vertical = OrSpacing.sm + OrSpacing.xs)
                .height(1.dp)
                .background(OrColors.Divider),
        )
        SecondaryRow(uiState)
    }
}

/**
 * The gradient behind the bar over video fades in over the bar's top padding only, so the
 * muted labels below it (CADENCE, OUTPUT) sit on 80 % black even over a bright sky or water:
 * a gradient that faded across the whole bar left them unreadable (bike test, 2026-10-27).
 */
private const val VideoScrimFadeEnd = 0.2f
private val VideoScrimLabels = Color(0xCC000000)
private val VideoScrimBottom = Color(0xE6000000)

@Composable
private fun PrimaryRow(uiState: InRideUiState, onStepResistance: (Int) -> Unit, modifier: Modifier = Modifier) {
    val dash = "--"
    val live = uiState.sensorsAvailable

    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        PrimaryMetric(
            label = "CADENCE",
            unit = "RPM",
            current = if (live) "${uiState.metrics.cadenceRpm}" else dash,
            avg = "${uiState.aggregates.avgCadence}",
            avgTrend = trend(live, uiState.metrics.cadenceRpm, uiState.aggregates.avgCadence),
            best = "${uiState.aggregates.maxCadence}",
            modifier = Modifier.weight(1f),
        )
        PrimaryDivider()
        PrimaryMetric(
            label = "OUTPUT",
            unit = "WATTS",
            current = if (live) "${uiState.metrics.powerWatts}" else dash,
            currentColor = uiState.currentZone?.let { zoneColor(it) },
            avg = "${uiState.aggregates.avgPower}",
            avgTrend = trend(live, uiState.metrics.powerWatts, uiState.aggregates.avgPower),
            best = "${uiState.aggregates.maxPower}",
            modifier = Modifier.weight(1f),
        )
        PrimaryDivider()
        PrimaryMetric(
            label = "RESISTANCE",
            unit = "PERCENT",
            current = if (live) "${uiState.metrics.resistancePercent}" else dash,
            avg = "${uiState.aggregates.avgResistance}",
            avgTrend = trend(live, uiState.metrics.resistancePercent, uiState.aggregates.avgResistance),
            best = null,
            modifier = Modifier.weight(1f),
            // A trainer has no knob: its resistance is stepped here, where BEST would be.
            trailing = if (uiState.resistanceAdjustable) {
                { ResistanceStepper(onStep = onStepResistance) }
            } else {
                null
            },
        )
    }
}

/** Direction of the current reading vs. its running average, or `null` when sensors are
 *  down or the two are equal — drives the small arrow beside the AVG flank. */
private fun trend(live: Boolean, current: Int, avg: Int): Boolean? =
    if (!live || current == avg) null else current > avg

@Composable
private fun PrimaryMetric(
    label: String,
    unit: String,
    current: String,
    avg: String,
    avgTrend: Boolean?,
    best: String?,
    modifier: Modifier = Modifier,
    currentColor: Color? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Flank(label = "AVG", value = avg, trend = avgTrend, showsTrend = true)
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(horizontal = OrSpacing.md),
        ) {
            OrEyebrow(label)
            Text(
                text = current,
                style = OrType.MetricPrimary,
                color = currentColor ?: OrColors.OnBackground,
                maxLines = 1,
            )
            OrEyebrow(unit)
        }
        if (trailing != null) {
            trailing()
        } else if (best != null) {
            Flank(label = "BEST", value = best, trend = null)
        } else {
            // Keep the big value optically centered when there's no BEST readout.
            Box(modifier = Modifier.width(FlankWidth))
        }
    }
}

/** + over −, a flank wide: steps a trainer's resistance (#68). */
@Composable
private fun ResistanceStepper(onStep: (Int) -> Unit) {
    Column(modifier = Modifier.width(FlankWidth), verticalArrangement = Arrangement.spacedBy(OrSpacing.xs)) {
        OrSecondaryButton(text = "+", onClick = { onStep(1) }, modifier = Modifier.fillMaxWidth())
        OrSecondaryButton(text = "−", onClick = { onStep(-1) }, modifier = Modifier.fillMaxWidth())
    }
}

/** Wide enough for a four-digit best at [OrType.MetricFlank]. */
private val FlankWidth = 80.dp

@Composable
private fun Flank(
    label: String,
    value: String,
    trend: Boolean?,
    modifier: Modifier = Modifier,
    showsTrend: Boolean = false,
) {
    Column(modifier = modifier.width(FlankWidth), horizontalAlignment = Alignment.CenterHorizontally) {
        // Every flank's label row is the arrow's height, and the AVG one keeps the arrow's place
        // while there is no trend, so AVG and BEST line up and nothing jumps as the arrow comes
        // and goes (bike test, 2026-10-27).
        Row(
            modifier = Modifier.height(OrSize.IconInline),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (showsTrend && trend == null) {
                Box(Modifier.size(OrSize.IconInline))
            } else if (trend != null) {
                // Core icons only ship the down-drop arrow; the up variant is it, flipped. Below
                // average is muted rather than red: Danger is a fill only, and red on the dark
                // ground fails contrast. The arrow's direction carries the meaning.
                Icon(
                    imageVector = Icons.Filled.ArrowDropDown,
                    contentDescription = if (trend) "above average" else "below average",
                    tint = if (trend) OrColors.Success else OrColors.OnSurfaceMuted,
                    modifier = Modifier
                        .size(OrSize.IconInline)
                        .rotate(if (trend) 180f else 0f),
                )
            }
            OrEyebrow(label)
        }
        Text(
            text = value,
            style = OrType.MetricFlank,
            color = OrColors.OnBackground,
            maxLines = 1,
        )
    }
}

@Composable
private fun SecondaryRow(uiState: InRideUiState, modifier: Modifier = Modifier) {
    val dash = "--"
    val live = uiState.sensorsAvailable

    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        SecondaryMetric(
            label = "SPEED",
            unit = "MPH",
            value = if (live) "%.1f".format(uiState.metrics.speedMph) else dash,
            modifier = Modifier.weight(1f),
        )
        SecondaryDivider()
        SecondaryMetric(
            label = "DISTANCE",
            unit = "MI",
            value = if (live) "%.2f".format(uiState.distanceMiles) else dash,
            modifier = Modifier.weight(1f),
        )
        SecondaryDivider()
        SecondaryMetric(
            label = "TOTAL OUTPUT",
            unit = "KJ",
            value = "%.0f".format(uiState.liveOutputKj),
            modifier = Modifier.weight(1f),
        )
        if (uiState.heartRateTileVisible) {
            SecondaryDivider()
            SecondaryMetric(
                label = "HEART RATE",
                unit = "BPM",
                value = uiState.heartRateBpm
                    ?.takeIf { uiState.heartRateConnected }
                    ?.toString() ?: dash,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun SecondaryMetric(label: String, unit: String, value: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        OrEyebrow("$label ($unit)")
        Text(
            text = value,
            style = OrType.MetricSecondary,
            color = OrColors.OnBackground,
            maxLines = 1,
            modifier = Modifier.padding(start = OrSpacing.sm + OrSpacing.xs),
        )
    }
}

@Composable
private fun PrimaryDivider() {
    Box(
        modifier = Modifier
            .width(1.dp)
            .height(104.dp)
            .background(OrColors.Divider),
    )
}

@Composable
private fun SecondaryDivider() {
    Box(
        modifier = Modifier
            .width(1.dp)
            .height(OrSpacing.xl)
            .background(OrColors.Divider),
    )
}
