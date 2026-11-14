package dev.digitalducktape.openride.ui.telemetry

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.digitalducktape.openride.ui.designsystem.BikePreview
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrEyebrow
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton
import dev.digitalducktape.openride.ui.designsystem.component.OrTile
import dev.digitalducktape.openride.ui.designsystem.component.OrTopBar
import dev.digitalducktape.openride.ui.theme.OpenRideTheme

/** "What's collected" (#85): the usage-metrics notice as short bulleted sections. Reached from the prompt and from Profile. */
@Composable
fun TelemetryInfoScreen(onDone: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier = modifier.fillMaxSize().background(OrColors.Background)) {
        OrTopBar(
            title = TelemetryLabels.WHATS_COLLECTED,
            actions = { OrSecondaryButton(text = "Done", onClick = onDone) },
        )
        OrTile(
            modifier = Modifier
                .weight(1f)
                .padding(start = OrSpacing.ScreenGutter, end = OrSpacing.ScreenGutter, top = OrSpacing.sm, bottom = OrSpacing.lg),
        ) {
            // Two columns on the wide bike screen: what's sent on the left, the rest on the right.
            Row(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(OrSpacing.xl),
            ) {
                Sections(TelemetryLabels.notice.take(1), Modifier.weight(1f))
                Sections(TelemetryLabels.notice.drop(1), Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun Sections(sections: List<Pair<String, List<String>>>, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(OrSpacing.lg)) {
        sections.forEach { (heading, bullets) ->
            Column(verticalArrangement = Arrangement.spacedBy(OrSpacing.xs)) {
                OrEyebrow(text = heading)
                bullets.forEach { Bullet(it) }
            }
        }
    }
}

/** One notice line: a dot, then the text wrapping under itself rather than under the dot. */
@Composable
private fun Bullet(text: String) {
    Row {
        Text(text = "•", style = OrType.Body, color = OrColors.OnSurfaceMuted, modifier = Modifier.width(24.dp))
        Text(text = text, style = OrType.Body, color = OrColors.OnBackground)
    }
}

@BikePreview
@Composable
private fun TelemetryInfoScreenPreview() {
    OpenRideTheme { TelemetryInfoScreen(onDone = {}) }
}
