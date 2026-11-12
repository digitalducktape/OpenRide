package dev.digitalducktape.openride.ui.ride

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.unit.dp
import dev.digitalducktape.openride.core.ride.PowerZone
import dev.digitalducktape.openride.core.ride.RideGoal
import dev.digitalducktape.openride.core.route.RoutePosition
import dev.digitalducktape.openride.ui.common.TimeFormat
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrShapes
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrAccentButton
import dev.digitalducktape.openride.ui.designsystem.component.OrBanner
import dev.digitalducktape.openride.ui.designsystem.component.OrBannerTone
import dev.digitalducktape.openride.ui.designsystem.component.OrConfirmDialog
import dev.digitalducktape.openride.ui.designsystem.component.OrEyebrow
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton
import dev.digitalducktape.openride.ui.designsystem.zoneColor
import dev.digitalducktape.openride.ui.music.NowPlayingPanel
import kotlinx.coroutines.launch

/**
 * The core screen (PRD P0-7/P0-9/P0-10, v2 redesign spec): bike-app arrangement — elapsed
 * timer top-left with the goal hairline across the top edge, the huge zone-colored
 * current-output numeral in the middle, and the shared [RideMetricsBar] pinned along the bottom
 * edge. Keep-screen-on is driven from [dev.digitalducktape.openride.MainActivity] observing
 * [dev.digitalducktape.openride.core.ride.RideSessionManager.isRideActive] directly, not
 * from this screen, so the flag can't be left dangling across navigation/recomposition.
 */
@Composable
fun InRideScreen(
    viewModel: InRideViewModel,
    onRideEnded: (rideId: Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState(initial = InRideUiState())
    val scope = rememberCoroutineScope()
    var showEndConfirmation by remember { mutableStateOf(false) }

    Column(modifier = modifier.fillMaxSize().background(OrColors.Background)) {
        // Goal progress runs across the very top edge (matching the video ride's strip).
        uiState.goalProgress?.let { GoalHairline(it) }

        // Sensors down and auto-pause each get a one-line notice above the timer.
        if (!uiState.sensorsAvailable) {
            RideNotice("Sensors not detected. Check the bike's connection")
        }
        if (uiState.autoPaused) {
            RideNotice("Auto-paused. Pedal to resume")
        }

        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(top = OrSpacing.md, start = OrSpacing.ScreenGutter),
            ) {
                Text(
                    text = TimeFormat.elapsed(uiState.elapsedSec),
                    style = OrType.MetricTimer,
                    color = OrColors.OnBackground,
                )
                OrEyebrow(
                    if (uiState.goal != RideGoal.None) "Elapsed · ${goalShortLabel(uiState.goal)}" else "Elapsed",
                )
            }

            Row(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = OrSpacing.lg, end = OrSpacing.ScreenGutter),
                horizontalArrangement = Arrangement.spacedBy(OrSpacing.md),
            ) {
                OrSecondaryButton(
                    text = if (uiState.isPaused) "Resume" else "Pause",
                    onClick = { if (uiState.isPaused) viewModel.resume() else viewModel.pause() },
                )
                OrAccentButton(text = "End ride", onClick = { showEndConfirmation = true })
            }

            // The rider's music, beside the output: the space either side of it is otherwise
            // empty, so the panel can be read and tapped from the saddle (rider's ask, 2026-10-27).
            NowPlayingPanel(
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .padding(start = OrSpacing.ScreenGutter),
            )

            OutputHero(
                uiState = uiState,
                modifier = Modifier.align(Alignment.Center),
            )

            uiState.routePosition?.let { position ->
                RouteProgressRow(
                    routeName = uiState.route?.name,
                    position = position,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(horizontal = OrSpacing.ScreenGutter, vertical = OrSpacing.md),
                )
            }
        }

        RideMetricsBar(uiState = uiState, translucent = false, onStepResistance = viewModel::stepResistance)
    }

    if (showEndConfirmation) {
        OrConfirmDialog(
            title = "End ride?",
            text = "This will stop and save your ride.",
            confirmText = "End ride",
            // The rider's colour, not red (rider's ask, 2026-10-21).
            destructive = false,
            onConfirm = {
                showEndConfirmation = false
                scope.launch {
                    val ride = viewModel.endRide()
                    if (ride != null) onRideEnded(ride.id)
                }
            },
            onDismiss = { showEndConfirmation = false },
        )
    }
}

/** The goal's progress as a hairline along the top edge, in the rider's colour. */
@Composable
internal fun GoalHairline(progress: Double, modifier: Modifier = Modifier) {
    LinearProgressIndicator(
        progress = { progress.toFloat() },
        modifier = modifier.fillMaxWidth().height(OrSpacing.xs),
        color = OrColors.Accent,
        trackColor = OrColors.Divider,
        drawStopIndicator = {},
        gapSize = 0.dp,
    )
}

/** A ride's warning (sensors down, auto-paused), inset from the screen's edges. */
@Composable
private fun RideNotice(text: String) {
    OrBanner(
        text = text,
        tone = OrBannerTone.Warning,
        modifier = Modifier.padding(start = OrSpacing.ScreenGutter, end = OrSpacing.ScreenGutter, top = OrSpacing.md),
    )
}

/**
 * The screen's centerpiece: current output in watts, zone-colored once the rider has an
 * FTP set, with the zone named beneath. "--" (never a fake zero, P0-9) while sensors are down.
 */
@Composable
private fun OutputHero(uiState: InRideUiState, modifier: Modifier = Modifier) {
    val zone = uiState.currentZone
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        OrEyebrow("Output (W)")
        Text(
            text = if (uiState.sensorsAvailable) "${uiState.metrics.powerWatts}" else "--",
            style = OrType.MetricHero,
            color = if (zone != null) zoneColor(zone) else OrColors.OnBackground,
        )
        if (zone != null) {
            ZoneChip(zone)
        } else if (uiState.ftp == null) {
            Text(
                text = "Set an FTP in your profile to see power zones",
                style = OrType.Body,
                color = OrColors.OnSurfaceMuted,
            )
        }
    }
}

/**
 * The current zone: its colour as a swatch and its name in text colour, since zones 1, 2 and 7
 * are too dark to read as text on the ground (see [dev.digitalducktape.openride.ui.designsystem.OrZoneColors]).
 */
@Composable
private fun ZoneChip(zone: PowerZone, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .background(OrColors.Surface, OrShapes.Pill)
            .padding(horizontal = OrSpacing.md, vertical = OrSpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(OrSpacing.sm + OrSpacing.xs),
    ) {
        Box(Modifier.size(OrSpacing.md).background(zoneColor(zone), CircleShape))
        Text(
            text = "Zone ${zone.number} · ${zone.label}",
            style = OrType.Subtitle,
            color = OrColors.OnBackground,
        )
    }
}

/**
 * Progress along the loaded GPX route (PRD #21/T21) — grade, percent complete and distance
 * remaining, advancing purely with accumulated ride distance. Display-only: Gen 2 has no
 * auto-resistance, so nothing here drives the bike.
 */
@Composable
private fun RouteProgressRow(
    routeName: String?,
    position: RoutePosition,
    modifier: Modifier = Modifier,
) {
    val remainingMiles = position.remainingMeters / METERS_PER_MILE
    Column(modifier = modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = routeName ?: "Route",
                style = OrType.Body,
                color = OrColors.OnSurfaceMuted,
                maxLines = 1,
            )
            Text(
                text = "%+.1f%% grade  •  %.2f mi to go".format(position.gradePercent, remainingMiles),
                style = OrType.Body,
                color = OrColors.OnSurfaceMuted,
                maxLines = 1,
            )
        }
        LinearProgressIndicator(
            progress = { position.progressFraction.toFloat() },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = OrSpacing.sm)
                .height(OrSpacing.xs),
            color = OrColors.Info,
            trackColor = OrColors.Divider,
            drawStopIndicator = {},
            gapSize = 0.dp,
        )
    }
}

/** Miles are the app's display unit; routes are measured in metres. */
private const val METERS_PER_MILE = 1609.344

/** Compact goal readout for the timer's sub-label (PRD P1-3) — the top-edge hairline
 *  carries the progress itself. */
private fun goalShortLabel(goal: RideGoal): String = when (goal) {
    is RideGoal.Duration -> "Goal ${TimeFormat.elapsed(goal.targetSec)}"
    is RideGoal.Output -> "Goal %.0f kJ".format(goal.targetKj)
    RideGoal.None -> ""
}
