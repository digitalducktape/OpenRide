package dev.digitalducktape.openride.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.ui.common.ProfileAvatar
import dev.digitalducktape.openride.ui.designsystem.BikePreview
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrIcons
import dev.digitalducktape.openride.ui.designsystem.OrShapes
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrPrimaryButton
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton
import dev.digitalducktape.openride.ui.theme.OpenRideTheme

/** Rider select connected to its [ProfileSelectViewModel] (Route half of the Route/Screen split). */
@Composable
fun ProfileSelectRoute(
    viewModel: ProfileSelectViewModel,
    onProfileSelected: () -> Unit,
    onAddRider: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // null until the first database read, so "add your first rider" never flashes past.
    val profiles by viewModel.profiles.collectAsStateWithLifecycle(initialValue = null)
    ProfileSelectScreen(
        profiles = profiles,
        onSelectProfile = { id ->
            viewModel.selectProfile(id)
            onProfileSelected()
        },
        onAddRider = onAddRider,
        modifier = modifier,
    )
}

/**
 * The launch destination (PRD P0-3, P0-8), stateless: the wordmark, "Who's riding?", a centred row
 * of large rider avatars (each one, with its name, a single touch target), and Add rider. With no
 * riders yet, adding the first one is the screen's primary action. Selecting a rider scopes the
 * whole session to them and moves on to Home.
 *
 * @param profiles the riders, or `null` while they load.
 */
@Composable
fun ProfileSelectScreen(
    profiles: List<Profile>?,
    onSelectProfile: (Long) -> Unit,
    onAddRider: () -> Unit,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(OrColors.Background)
            .padding(OrSpacing.xl),
    ) {
        // A phone's landscape screen is about 400 dp tall, not the bike's 1008 px: there the
        // avatars shrink and Add rider follows them, rather than sitting on the riders' names.
        val compact = maxHeight < CompactHeight
        Text(
            text = "OPENRIDE",
            fontSize = 28.sp,
            style = OrType.Eyebrow,
            letterSpacing = 10.sp,
            color = OrColors.OnBackground,
            modifier = Modifier.align(Alignment.TopStart),
        )

        if (profiles != null) {
            Column(
                modifier = Modifier.align(Alignment.Center).fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = if (profiles.isEmpty()) "Welcome to OpenRide" else "Who's riding?",
                    style = OrType.ScreenTitle,
                    color = OrColors.OnBackground,
                )
                if (profiles.isEmpty()) {
                    Text(
                        text = "Add a rider to keep their rides, goals and records apart.",
                        style = OrType.Body,
                        color = OrColors.OnSurfaceMuted,
                        modifier = Modifier.padding(top = OrSpacing.sm),
                    )
                    OrPrimaryButton(
                        text = "Add your first rider",
                        icon = OrIcons.Add,
                        onClick = onAddRider,
                        modifier = Modifier.padding(top = OrSpacing.xxl),
                    )
                } else {
                    LazyRow(
                        modifier = Modifier.fillMaxWidth().padding(top = if (compact) OrSpacing.md else OrSpacing.xxl),
                        horizontalArrangement = Arrangement.spacedBy(OrSpacing.xl, Alignment.CenterHorizontally),
                    ) {
                        items(profiles, key = { it.id }) { profile ->
                            RiderAvatar(profile = profile, compact = compact, onClick = { onSelectProfile(profile.id) })
                        }
                    }
                    if (compact) {
                        OrSecondaryButton(
                            text = "Add rider",
                            icon = OrIcons.Add,
                            onClick = onAddRider,
                            modifier = Modifier.padding(top = OrSpacing.md),
                        )
                    }
                }
            }

            if (profiles.isNotEmpty() && !compact) {
                OrSecondaryButton(
                    text = "Add rider",
                    icon = OrIcons.Add,
                    onClick = onAddRider,
                    modifier = Modifier.align(Alignment.BottomCenter),
                )
            }
        }
    }
}

@Composable
private fun RiderAvatar(profile: Profile, compact: Boolean, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .width(if (compact) CompactRiderCellWidth else RiderCellWidth)
            .clip(OrShapes.Large)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(OrSpacing.md),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        ProfileAvatar(
            profile = profile,
            size = if (compact) CompactAvatarSize else AvatarSize,
            emojiSize = if (compact) 48.sp else 72.sp,
        )
        Text(
            text = profile.name,
            style = OrType.Subtitle,
            color = OrColors.OnBackground,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = OrSpacing.md),
        )
    }
}

private val AvatarSize = 176.dp
private val RiderCellWidth = 208.dp
private val CompactAvatarSize = 112.dp
private val CompactRiderCellWidth = 144.dp

/** Below this the screen is a phone's, not the bike's (about 650 dp tall there). */
private val CompactHeight = 560.dp

private fun previewRider(id: Long, name: String, emoji: String, color: Long) =
    Profile(id = id, name = name, avatarEmoji = emoji, avatarColor = color.toInt(), weightKg = null, ftp = null)

@BikePreview
@Composable
private fun ProfileSelectPreview() {
    OpenRideTheme {
        ProfileSelectScreen(
            profiles = listOf(
                previewRider(1, "Sam", "🚴", 0xFF3D7BD9),
                previewRider(2, "Alex", "🦊", 0xFFEF7D2E),
                previewRider(3, "Jo", "🌵", 0xFF2FA8A0),
            ),
            onSelectProfile = {},
            onAddRider = {},
        )
    }
}

@BikePreview
@Composable
private fun ProfileSelectEmptyPreview() {
    OpenRideTheme {
        ProfileSelectScreen(profiles = emptyList(), onSelectProfile = {}, onAddRider = {})
    }
}
