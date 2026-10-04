package dev.digitalducktape.openride.ui.games

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import dev.digitalducktape.openride.games.GameHostActivity
import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.session.GameMusicMode
import dev.digitalducktape.openride.games.session.SessionRequest
import dev.digitalducktape.openride.ui.theme.OpenRideColors

/**
 * The Games tab (#38; in beta): circuits, a Just Ride card per game, the rider's bests, an FTP
 * nudge and the game settings. Starting one launches the games host. Camera games ask for the
 * camera permission first (once; if it's refused, circuits play camera-free games instead).
 */
@Composable
fun GamesScreen(viewModel: GamesViewModel, onEditProfile: () -> Unit, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var pendingStart by remember { mutableStateOf<((Boolean) -> Unit)?>(null) }
    var cameraRefused by remember { mutableStateOf(false) }
    val askCamera = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        cameraRefused = !granted
        pendingStart?.invoke(granted)
        pendingStart = null
    }

    /** Starts [request]; when it needs the camera and the permission is missing, asks first. */
    fun launch(needsCamera: Boolean, build: (cameraAvailable: Boolean) -> SessionRequest?) {
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        if (!needsCamera || granted) {
            build(true)?.let { context.startActivity(GameHostActivity.intent(context, it)) }
        } else {
            pendingStart = { ok -> build(ok)?.let { context.startActivity(GameHostActivity.intent(context, it)) } }
            askCamera.launch(Manifest.permission.CAMERA)
        }
    }

    Surface(modifier = modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(horizontal = 48.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Row(Modifier.padding(top = 32.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text("\uD83C\uDFAE GAMES", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                    BetaBadge()
                }
                Text(
                    "Workouts that play like games. Pedal, steer, and keep pace.",
                    style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (state.ftpMissing) {
                item {
                    Card {
                        Text("Set your FTP for the right targets", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        Text(
                            "Games scale their power targets to your FTP. Until you set it, they assume 150 W.",
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        OutlinedButton(onClick = onEditProfile) { Text("Edit profile") }
                    }
                }
            }
            if (cameraRefused) {
                item {
                    Card {
                        Text("The camera isn't allowed", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        Text(
                            "Camera games steer with a lean of your head. Circuits play a game without the camera instead.",
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            item { SectionTitle("CIRCUITS") }
            item { DifficultyChips(state.circuitDifficulty, viewModel::setCircuitDifficulty) }
            items(state.circuits, key = { it.id }) { circuit ->
                Card {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(circuit.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                            Text("${circuit.totalLabel} · ${circuit.lineup}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            circuit.best?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = OpenRideColors.Success) }
                        }
                        Button(onClick = {
                            launch(needsCamera = state.cameraGames) { ok -> viewModel.circuitRequest(circuit.id, cameraAvailable = ok) }
                        }) { Text("Start") }
                    }
                }
            }
            item { SectionTitle("JUST RIDE") }
            items(state.games, key = { it.id }) { game ->
                Card {
                    Text(game.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    if (game.usesCamera) {
                        Text("Steers with your head: uses the camera", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Chips(game.kinds, game.kind, { kindLabel(it) }) { viewModel.setKind(game.id, it) }
                    when (game.kind) {
                        RideKind.TIMED -> Chips(game.minutesOptions, game.minutes, { "$it min" }) { viewModel.setMinutes(game.id, it) }
                        RideKind.ROUNDS -> Chips(game.roundsOptions, game.rounds, { if (it == 1) "1 round" else "$it rounds" }) { viewModel.setRounds(game.id, it) }
                        RideKind.OPEN -> Text("Until you end it", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    DifficultyChips(game.difficulty) { viewModel.setGameDifficulty(game.id, it) }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            if (game.unavailable) "Camera games are off" else game.best ?: "No best yet",
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (game.unavailable) OpenRideColors.Warning else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.weight(1f),
                        )
                        Button(enabled = !game.unavailable, onClick = {
                            launch(needsCamera = game.usesCamera) { ok -> if (ok) viewModel.justRideRequest(game.id) else null }
                        }) { Text("Start") }
                    }
                }
            }
            item { SectionTitle("SETTINGS") }
            item {
                Card {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("Camera games", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                            Text(
                                "Dodge Ball steers by leaning your head. The camera only looks for your head position; nothing is recorded.",
                                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(checked = state.cameraGames, onCheckedChange = viewModel::setCameraGames)
                    }
                    Text("Game music", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Chips(GameMusicMode.entries, state.audio.music, { musicLabel(it) }) { viewModel.setMusicMode(it) }
                    Text("Auto turns game music off while your own music is playing.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Music volume", style = MaterialTheme.typography.bodyMedium)
                    Slider(value = state.audio.musicVolume.toFloat(), onValueChange = { viewModel.setMusicVolume(it.toDouble()) })
                    Text("Effects volume", style = MaterialTheme.typography.bodyMedium)
                    Slider(value = state.audio.sfxVolume.toFloat(), onValueChange = { viewModel.setEffectsVolume(it.toDouble()) })
                }
            }
            item { Text("", modifier = Modifier.padding(bottom = 24.dp)) }
        }
    }
}

/** The small "BETA" tag shown wherever the games are advertised. */
@Composable
fun BetaBadge(modifier: Modifier = Modifier) {
    Text(
        "BETA",
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.Bold,
        color = OpenRideColors.Background,
        modifier = modifier.background(OpenRideColors.Warning, RoundedCornerShape(8.dp)).padding(horizontal = 10.dp, vertical = 4.dp),
    )
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 8.dp))
}

@Composable
private fun Card(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface, RoundedCornerShape(20.dp)).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) { content() }
}

@Composable
private fun DifficultyChips(selected: Difficulty, onSelect: (Difficulty) -> Unit) {
    Chips(Difficulty.entries, selected, { it.name.lowercase().replaceFirstChar(Char::uppercase) }, onSelect)
}

@Composable
private fun <T> Chips(options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        options.forEach { option ->
            FilterChip(selected = option == selected, onClick = { onSelect(option) }, label = { Text(label(option)) })
        }
    }
}

private fun kindLabel(kind: RideKind) = when (kind) {
    RideKind.TIMED -> "Timed"
    RideKind.ROUNDS -> "Rounds"
    RideKind.OPEN -> "Open-ended"
}

private fun musicLabel(mode: GameMusicMode) = when (mode) {
    GameMusicMode.AUTO -> "Auto"
    GameMusicMode.ON -> "On"
    GameMusicMode.OFF -> "Off"
}
