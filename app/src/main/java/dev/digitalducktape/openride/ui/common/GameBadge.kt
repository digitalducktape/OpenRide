package dev.digitalducktape.openride.ui.common

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.digitalducktape.openride.ui.theme.OpenRideColors

/** A pill marking a mini-games ride (#35), e.g. "Demo · 20 min", in History and the summary. */
@Composable
fun GameBadge(text: String, modifier: Modifier = Modifier) {
    Text(
        text = "🎮 $text",
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onBackground,
        modifier = modifier
            .background(color = OpenRideColors.Accent.copy(alpha = 0.35f), shape = RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 4.dp),
    )
}
