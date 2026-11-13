package dev.digitalducktape.openride.ui.telemetry

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.digitalducktape.openride.ui.designsystem.ComponentPreview
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrShapes
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrAccentButton
import dev.digitalducktape.openride.ui.designsystem.component.OrLabel
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton
import dev.digitalducktape.openride.ui.theme.OpenRideTheme

/**
 * The one-time usage-data question (#85), in the design system's dialog look. Dismissing it
 * (tapping outside, Back) is a No thanks, so it never nags.
 */
@Composable
fun TelemetryConsentDialog(
    onShare: () -> Unit,
    onDecline: () -> Unit,
    onShowWhatsCollected: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDecline,
        containerColor = OrColors.Surface,
        shape = OrShapes.Medium,
        title = { OrLabel(text = TelemetryLabels.PROMPT_TITLE, style = OrType.Title, color = OrColors.OnBackground) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(OrSpacing.md)) {
                Text(text = TelemetryLabels.PROMPT_BODY, style = OrType.Body, color = OrColors.OnSurfaceMuted)
                OrSecondaryButton(text = TelemetryLabels.WHATS_COLLECTED, onClick = onShowWhatsCollected)
            }
        },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(OrSpacing.md)) {
                OrSecondaryButton(text = TelemetryLabels.DECLINE, onClick = onDecline)
                OrAccentButton(text = TelemetryLabels.SHARE, onClick = onShare)
            }
        },
    )
}

@ComponentPreview
@Composable
private fun TelemetryConsentDialogPreview() {
    OpenRideTheme {
        TelemetryConsentDialog(onShare = {}, onDecline = {}, onShowWhatsCollected = {})
    }
}
