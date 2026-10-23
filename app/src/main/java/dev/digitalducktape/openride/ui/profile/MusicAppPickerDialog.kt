package dev.digitalducktape.openride.ui.profile

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.core.graphics.drawable.toBitmap
import dev.digitalducktape.openride.core.music.InstalledApp
import dev.digitalducktape.openride.core.music.MusicApps
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrIcons
import dev.digitalducktape.openride.ui.designsystem.OrShapes
import dev.digitalducktape.openride.ui.designsystem.OrSize
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrLabel
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton

/** Size of each app's launcher icon in the picker. */
private val AppIconSize = 48.dp

/**
 * Picks the rider's music app (Profile → Music app): every launchable app, known music apps first,
 * plus "None" to hide the top bar's Music button. The current choice carries a check.
 */
@Composable
fun MusicAppPickerDialog(
    current: String?,
    onPick: (String?) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val apps = remember { MusicApps.installed(context) }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = OrColors.Surface,
        shape = OrShapes.Medium,
        title = { OrLabel(text = "Music app", style = OrType.Title, color = OrColors.OnBackground) },
        text = {
            LazyColumn(modifier = Modifier.heightIn(max = 480.dp)) {
                item { PickerRow(label = ProfileTabLabels.NO_MUSIC_APP, app = null, selected = current == null, onPick = onPick) }
                items(apps, key = { it.packageName }) { app ->
                    PickerRow(label = app.label, app = app, selected = app.packageName == current, onPick = onPick)
                }
            }
        },
        confirmButton = { OrSecondaryButton(text = "Cancel", onClick = onDismiss) },
    )
}

@Composable
private fun PickerRow(label: String, app: InstalledApp?, selected: Boolean, onPick: (String?) -> Unit) {
    val context = LocalContext.current
    val icon = remember(app) { app?.let { MusicApps.icon(context, it.packageName)?.toBitmap()?.asImageBitmap() } }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = OrSize.SettingsRow)
            .clip(OrShapes.Small)
            .background(if (selected) OrColors.SurfaceRaised else OrColors.Surface)
            .clickable(role = Role.RadioButton) { onPick(app?.packageName) }
            .padding(horizontal = OrSpacing.md),
        horizontalArrangement = Arrangement.spacedBy(OrSpacing.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(modifier = Modifier.size(AppIconSize), contentAlignment = Alignment.Center) {
            if (icon != null) Image(bitmap = icon, contentDescription = null, modifier = Modifier.size(AppIconSize))
        }
        OrLabel(text = label, style = OrType.Body, color = OrColors.OnBackground, modifier = Modifier.weight(1f))
        if (selected) Icon(imageVector = OrIcons.Check, contentDescription = "Selected", tint = OrColors.Accent)
    }
}
