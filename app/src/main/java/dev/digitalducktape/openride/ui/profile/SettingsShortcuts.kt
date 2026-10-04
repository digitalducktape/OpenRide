package dev.digitalducktape.openride.ui.profile

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

/**
 * Quick access to stock Android settings from within the app (PRD user story: "I want to
 * still reach stock Android settings (WiFi, volume) from within the app so that basic
 * device maintenance doesn't require re-running OpenPelo"; PRD P1-5). Relevant once
 * MainActivity is the tablet's launcher (T12's opt-in HOME alias) and the stock Settings
 * app icon may not be easily reachable otherwise.
 */
@Composable
fun SettingsShortcutsRow(modifier: Modifier = Modifier) {
    val context = LocalContext.current

    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        OutlinedButton(onClick = { launchSettings(context, Settings.ACTION_WIFI_SETTINGS) }) {
            Text("Wi-Fi Settings")
        }
        OutlinedButton(onClick = { launchSettings(context, Settings.ACTION_SETTINGS) }) {
            Text("Device Settings")
        }
    }
}

/** Launches a stock Android settings screen by [action] (e.g. [Settings.ACTION_WIFI_SETTINGS]). */
fun launchSettings(context: Context, action: String) {
    context.startActivity(Intent(action))
}
