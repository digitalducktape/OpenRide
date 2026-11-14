package dev.digitalducktape.openride.ui.telemetry

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
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
 * The one-time usage-metrics question (#85), in the design system's dialog look. Dismissing it
 * (tapping outside, Back) is a No thanks, so it never nags.
 *
 * A plain [Dialog], not AlertDialog: AlertDialog caps the width at 560 dp and puts extra buttons in
 * the text slot, which put What's collected on its own line. Here all three share one row.
 */
@Composable
fun TelemetryConsentDialog(
    onShare: () -> Unit,
    onDecline: () -> Unit,
    onShowWhatsCollected: () -> Unit,
) {
    Dialog(onDismissRequest = onDecline, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(
            color = OrColors.Surface,
            shape = OrShapes.Medium,
            modifier = Modifier.widthIn(max = 760.dp).padding(horizontal = OrSpacing.lg),
        ) {
            Column(
                modifier = Modifier.padding(OrSpacing.lg),
                verticalArrangement = Arrangement.spacedBy(OrSpacing.md),
            ) {
                OrLabel(text = TelemetryLabels.PROMPT_TITLE, style = OrType.Title, color = OrColors.OnBackground)
                Text(text = TelemetryLabels.PROMPT_BODY, style = OrType.Body, color = OrColors.OnSurfaceMuted)
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = OrSpacing.sm),
                    horizontalArrangement = Arrangement.spacedBy(OrSpacing.md),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    OrSecondaryButton(text = TelemetryLabels.WHATS_COLLECTED, onClick = onShowWhatsCollected)
                    Spacer(Modifier.weight(1f))
                    OrSecondaryButton(text = TelemetryLabels.DECLINE, onClick = onDecline)
                    OrAccentButton(text = TelemetryLabels.SHARE, onClick = onShare)
                }
            }
        }
    }
}

@ComponentPreview
@Composable
private fun TelemetryConsentDialogPreview() {
    OpenRideTheme {
        TelemetryConsentDialog(onShare = {}, onDecline = {}, onShowWhatsCollected = {})
    }
}
