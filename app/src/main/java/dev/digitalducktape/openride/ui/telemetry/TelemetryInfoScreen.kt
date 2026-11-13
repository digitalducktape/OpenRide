package dev.digitalducktape.openride.ui.telemetry

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import dev.digitalducktape.openride.ui.designsystem.BikePreview
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrEyebrow
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton
import dev.digitalducktape.openride.ui.designsystem.component.OrTile
import dev.digitalducktape.openride.ui.designsystem.component.OrTopBar
import dev.digitalducktape.openride.ui.theme.OpenRideTheme

/** "What's collected" (#85): the usage-data notice in full. Reached from the prompt and from Profile. */
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
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(OrSpacing.md),
            ) {
                TelemetryLabels.notice.forEach { (heading, body) ->
                    Column {
                        OrEyebrow(text = heading)
                        Text(
                            text = body,
                            style = OrType.Body,
                            color = OrColors.OnBackground,
                            modifier = Modifier.padding(top = OrSpacing.xs),
                        )
                    }
                }
            }
        }
    }
}

@BikePreview
@Composable
private fun TelemetryInfoScreenPreview() {
    OpenRideTheme { TelemetryInfoScreen(onDone = {}) }
}
