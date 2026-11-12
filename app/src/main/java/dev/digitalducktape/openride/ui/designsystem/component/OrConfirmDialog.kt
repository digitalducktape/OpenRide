package dev.digitalducktape.openride.ui.designsystem.component

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrShapes
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType

/**
 * A yes/no confirmation in the design system's look (End ride?): a dismiss button ([dismissText],
 * "Cancel" by default) and a confirm button of the ordinary sizes, the confirm one red when
 * [destructive].
 */
@Composable
fun OrConfirmDialog(
    title: String,
    text: String,
    confirmText: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    destructive: Boolean = true,
    dismissText: String = "Cancel",
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = OrColors.Surface,
        shape = OrShapes.Medium,
        title = { OrLabel(text = title, style = OrType.Title, color = OrColors.OnBackground) },
        text = { Text(text = text, style = OrType.Body, color = OrColors.OnSurfaceMuted) },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(OrSpacing.md)) {
                OrSecondaryButton(text = dismissText, onClick = onDismiss)
                if (destructive) {
                    OrDangerButton(text = confirmText, onClick = onConfirm)
                } else {
                    OrAccentButton(text = confirmText, onClick = onConfirm)
                }
            }
        },
    )
}
