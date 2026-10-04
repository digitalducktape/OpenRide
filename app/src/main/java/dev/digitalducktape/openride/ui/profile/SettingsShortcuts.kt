package dev.digitalducktape.openride.ui.profile

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.digitalducktape.openride.games.GameHostActivity
import dev.digitalducktape.openride.games.session.JustRideMode
import dev.digitalducktape.openride.games.session.SessionRequest

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
        // Mini-games (#32, #35): a way into the Godot host until the Games hub (#38) replaces
        // it with a real tab. Each session records a ride.
        Box {
            var open by remember { mutableStateOf(false) }
            OutlinedButton(onClick = { open = true }) { Text("Mini-games (preview)") }
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                PREVIEW_RIDES.forEach { (label, request) ->
                    DropdownMenuItem(
                        text = { Text(label) },
                        onClick = {
                            open = false
                            context.startActivity(GameHostActivity.intent(context, request))
                        },
                    )
                }
            }
        }
    }
}

/** The preview's Just Rides (#35), until the Games hub (#38) replaces them. */
private val PREVIEW_RIDES = listOf(
    "Dodge Ball · 20 min" to SessionRequest.JustRide("dodge_ball", JustRideMode.Timed(20)),
    "Dodge Ball · open-ended" to SessionRequest.JustRide("dodge_ball", JustRideMode.Open),
    "Tug of War · 20 min" to SessionRequest.JustRide("tug_of_war", JustRideMode.Timed(20)),
    "Tug of War · open-ended" to SessionRequest.JustRide("tug_of_war", JustRideMode.Open),
    "Demo · 20 min" to SessionRequest.JustRide("demo", JustRideMode.Timed(20)),
    "Demo · open-ended" to SessionRequest.JustRide("demo", JustRideMode.Open),
)

/** Launches a stock Android settings screen by [action] (e.g. [Settings.ACTION_WIFI_SETTINGS]). */
fun launchSettings(context: Context, action: String) {
    context.startActivity(Intent(action))
}
