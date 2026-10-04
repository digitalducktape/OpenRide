package dev.digitalducktape.openride.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.digitalducktape.openride.core.ride.RideGoal
import dev.digitalducktape.openride.ui.common.ProfileAvatar
import dev.digitalducktape.openride.ui.games.BetaBadge
import dev.digitalducktape.openride.ui.theme.MetricTextStyles

/**
 * Home tab (PRD P0-7): greeting with the active rider and a prominent Quick Start button.
 * The curated-classes browser (PRD P0-6) lives in the Classes tab (T10) rather than
 * duplicated here — see [dev.digitalducktape.openride.ui.classes.ClassesScreen].
 */
@Composable
fun HomeScreen(
    viewModel: HomeViewModel,
    onQuickStart: () -> Unit,
    onOpenProfile: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenGames: () -> Unit = {},
    updateVersionName: String? = null,
    onOpenUpdate: () -> Unit = {},
    onDismissUpdate: () -> Unit = {},
) {
    val activeProfile by viewModel.activeProfile.collectAsState(initial = null)
    val goal by viewModel.goal.collectAsState()
    var showGoalDialog by remember { mutableStateOf(false) }

    Surface(modifier = modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(modifier = Modifier.fillMaxSize().padding(horizontal = 48.dp, vertical = 36.dp)) {
            // PRD #22/T22: launch-time update check surfaces here as a dismissible banner that
            // taps through to the App updates screen. Nothing installs without an explicit tap.
            if (updateVersionName != null) {
                UpdateBanner(
                    versionName = updateVersionName,
                    onUpdate = onOpenUpdate,
                    onDismiss = onDismissUpdate,
                    modifier = Modifier.padding(bottom = 24.dp),
                )
            }

            // Bike-app-style header: greeting on the left, the rider's avatar chip on the
            // right (v2 redesign spec).
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "WELCOME BACK",
                        style = MetricTextStyles.SectionEyebrow,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = activeProfile?.name ?: "Rider",
                        style = MaterialTheme.typography.headlineLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onBackground,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
                // Tapping the rider's own face is the natural "go to my profile" gesture.
                ProfileAvatar(
                    profile = activeProfile,
                    size = 56.dp,
                    emojiSize = 26.sp,
                    modifier = Modifier.clickable(onClick = onOpenProfile),
                )
            }

            // Hero card: the one big action on this screen.
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 32.dp)
                    .background(
                        color = MaterialTheme.colorScheme.surface,
                        shape = RoundedCornerShape(20.dp),
                    )
                    .padding(28.dp),
            ) {
                Text(
                    text = "JUST RIDE",
                    style = MetricTextStyles.SectionEyebrow,
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(
                    text = "Quick Start",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onBackground,
                    modifier = Modifier.padding(top = 6.dp),
                )
                Text(
                    text = "Free ride with live cadence, resistance, and output",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp),
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 24.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Button(
                        onClick = { if (viewModel.startQuickRide()) onQuickStart() },
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
                        modifier = Modifier.height(56.dp),
                    ) {
                        Text(
                            text = "Start ride",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(horizontal = 24.dp),
                        )
                    }
                    Text(
                        text = goalSummaryLabel(goal),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f).padding(start = 24.dp),
                    )
                    OutlinedButton(onClick = { showGoalDialog = true }) {
                        Text(if (goal == RideGoal.None) "Set goal" else "Change goal")
                    }
                }
            }

            // Games (beta): workouts that play like games, advertised right under the quick start.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 20.dp)
                    .background(color = MaterialTheme.colorScheme.surface, shape = RoundedCornerShape(20.dp))
                    .clickable(onClick = onOpenGames)
                    .padding(horizontal = 28.dp, vertical = 22.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "GAMES",
                            style = MetricTextStyles.SectionEyebrow,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        BetaBadge(modifier = Modifier.padding(start = 12.dp))
                    }
                    Text(
                        text = "Play your workout",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onBackground,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                    Text(
                        text = "Circuits and games for every ride, from warm-up to cool-down. New, and still being tuned.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
                OutlinedButton(onClick = onOpenGames) { Text("Open Games") }
            }
        }
    }

    if (showGoalDialog) {
        GoalDialog(
            currentGoal = goal,
            onDismiss = { showGoalDialog = false },
            onSave = { newGoal ->
                viewModel.setGoal(newGoal)
                showGoalDialog = false
            },
        )
    }
}

/**
 * Non-blocking "an update is available" banner (PRD #22/T22). "Update" opens the App updates
 * screen (the actual download/install still happens there, behind explicit taps); "Dismiss"
 * hides it for this session.
 */
@Composable
private fun UpdateBanner(
    versionName: String,
    onUpdate: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(
                color = MaterialTheme.colorScheme.primaryContainer,
                shape = RoundedCornerShape(16.dp),
            )
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "OpenRide $versionName is available",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onPrimaryContainer,
            modifier = Modifier.weight(1f),
        )
        TextButton(onClick = onDismiss) {
            Text("Dismiss", color = MaterialTheme.colorScheme.onPrimaryContainer)
        }
        Button(
            onClick = onUpdate,
            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
            modifier = Modifier.padding(start = 8.dp),
        ) {
            Text("Update", fontWeight = FontWeight.Bold)
        }
    }
}
