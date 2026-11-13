package dev.digitalducktape.openride.ui.music

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.core.graphics.drawable.toBitmap
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import coil.compose.AsyncImage
import dev.digitalducktape.openride.appContainer
import dev.digitalducktape.openride.core.music.MusicApp
import dev.digitalducktape.openride.core.music.MusicApps
import dev.digitalducktape.openride.core.music.NowPlaying
import dev.digitalducktape.openride.core.music.NowPlayingMonitor
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrIcons
import dev.digitalducktape.openride.ui.designsystem.OrShapes
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrLabel
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton

/** Provided by MainActivity so any screen can show the player without threading it through. */
val LocalNowPlaying = compositionLocalOf<NowPlayingMonitor?> { null }

/**
 * The rider's music in the top bar, from whatever app is playing it (Android's media sessions;
 * no per-service integration): art, song and artist, with previous / play-pause / next. Tapping
 * the song brings the app forward, to change playlist there; Spotify, Apple Music and Pandora
 * don't let another app browse their libraries (bike test, 2026-10-27).
 *
 * With nothing playing it is a button that opens the rider's music app (Profile → Music). Just
 * Ride has the larger [NowPlayingPanel]; a class video has this one
 * only while the rider has muted the class (#72), since otherwise its own sound is the point.
 */
@Composable
fun MiniPlayer(modifier: Modifier = Modifier, monitor: NowPlayingMonitor? = LocalNowPlaying.current) {
    if (monitor == null) return
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { monitor.refresh() }
    val playing by monitor.nowPlaying.collectAsState()

    val current = playing
    if (current == null) {
        OpenMusicAppButton(monitor, modifier)
        return
    }
    // A fixed width, so the controls stay put as titles change length; long ones scroll.
    Row(
        modifier = modifier
            .width(CompactWidth)
            .clip(OrShapes.Small)
            .background(OrColors.Surface),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .clickable(onClickLabel = "Open the music app", onClick = monitor::openApp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(OrSpacing.sm + OrSpacing.xs),
        ) {
            AlbumArt(current, CompactArt)
            Column(modifier = Modifier.weight(1f)) {
                ScrollingText(current.title, OrType.Subtitle, OrColors.OnBackground)
                if (current.artist.isNotBlank()) ScrollingText(current.artist, OrType.Body, OrColors.OnSurfaceMuted)
            }
        }
        TransportButtons(current, monitor, CompactArt, CompactIcon)
    }
}

/**
 * Just Ride's music, beside the output: the [MiniPlayer] at a size read from the saddle, with
 * large art and controls. With nothing playing it keeps its place and size, offering the
 * rider's music app, so the screen doesn't shift when a song starts or an app lets go.
 */
@Composable
fun NowPlayingPanel(modifier: Modifier = Modifier, monitor: NowPlayingMonitor? = LocalNowPlaying.current) {
    if (monitor == null) return
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { monitor.refresh() }
    val hasAccess by monitor.hasAccess.collectAsState()
    val playing by monitor.nowPlaying.collectAsState()

    val current = playing
    Row(
        modifier = modifier
            .width(PanelWidth)
            .clip(OrShapes.Medium)
            .background(OrColors.Surface)
            .padding(OrSpacing.md),
        horizontalArrangement = Arrangement.spacedBy(OrSpacing.md),
    ) {
        if (current != null) {
            Box(modifier = Modifier.clickable(onClickLabel = "Open the music app", onClick = monitor::openApp)) {
                AlbumArt(current, PanelArt)
            }
            Column(modifier = Modifier.weight(1f).height(PanelArt)) {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .clickable(onClickLabel = "Open the music app", onClick = monitor::openApp),
                ) {
                    ScrollingText(current.title, OrType.Title, OrColors.OnBackground)
                    if (current.artist.isNotBlank()) ScrollingText(current.artist, OrType.Subtitle, OrColors.OnSurfaceMuted)
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TransportButtons(current, monitor, PanelButton, PanelIcon)
                }
            }
        } else {
            ArtPlaceholder(PanelArt)
            Column(modifier = Modifier.weight(1f).height(PanelArt)) {
                Text(text = "Music", style = OrType.Title, color = OrColors.OnBackground)
                Text(
                    // Without access it can't know; with it, every app has let go of its session.
                    text = if (hasAccess) "Nothing playing" else "Turn on Now playing in Profile to see the song here",
                    style = OrType.Caption,
                    color = OrColors.OnSurfaceMuted,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(modifier = Modifier.weight(1f))
                OpenMusicAppButton(monitor, Modifier.fillMaxWidth())
            }
        }
    }
}

/** One line that scrolls sideways, again and again, when it's longer than its space. */
@Composable
private fun ScrollingText(text: String, style: TextStyle, color: Color) {
    Text(
        text = text,
        style = style,
        color = color,
        maxLines = 1,
        modifier = Modifier.basicMarquee(iterations = Int.MAX_VALUE, repeatDelayMillis = MarqueePauseMs),
    )
}

@Composable
private fun AlbumArt(playing: NowPlaying, size: Dp) {
    Box(modifier = Modifier.size(size).clip(OrShapes.Small).background(OrColors.SurfaceRaised)) {
        AsyncImage(
            model = playing.art ?: playing.artUri,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(size),
        )
    }
}

@Composable
private fun ArtPlaceholder(size: Dp) {
    Box(
        modifier = Modifier.size(size).clip(OrShapes.Small).background(OrColors.SurfaceRaised),
        contentAlignment = Alignment.Center,
    ) {
        Icon(imageVector = OrIcons.MusicNote, contentDescription = null, tint = OrColors.Outline, modifier = Modifier.size(size / 2))
    }
}

/**
 * Previous, play/pause and next. Previous and next stay in place when an app doesn't offer them
 * (Pandora has no previous, and greys out next after its skip limit), so nothing shifts under a thumb.
 */
@Composable
private fun TransportButtons(playing: NowPlaying, monitor: NowPlayingMonitor, buttonSize: Dp, iconSize: Dp) {
    val tracker = LocalContext.current.appContainer.rideTelemetryTracker
    fun controlled(action: () -> Unit): () -> Unit = {
        tracker.markMusicControl()
        action()
    }
    TransportButton(OrIcons.SkipPrevious, "Previous", playing.canPrevious, buttonSize, iconSize, controlled(monitor::previous))
    TransportButton(
        icon = if (playing.isPlaying) OrIcons.Pause else OrIcons.Play,
        label = if (playing.isPlaying) "Pause" else "Play",
        enabled = true,
        buttonSize = buttonSize,
        iconSize = iconSize,
        onClick = controlled(monitor::playPause),
    )
    TransportButton(OrIcons.SkipNext, "Next", playing.canNext, buttonSize, iconSize, controlled(monitor::next))
}

@Composable
private fun TransportButton(
    icon: ImageVector,
    label: String,
    enabled: Boolean,
    buttonSize: Dp,
    iconSize: Dp,
    onClick: () -> Unit,
) {
    IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.size(buttonSize)) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            tint = if (enabled) OrColors.OnBackground else OrColors.Outline,
            modifier = Modifier.size(iconSize),
        )
    }
}

/**
 * Nothing playing: opens the rider's music app ("Open Spotify"), or, before one is chosen or
 * once it's gone, asks which with [MusicAppPicker] and remembers the answer.
 */
@Composable
private fun OpenMusicAppButton(monitor: NowPlayingMonitor, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val defaultApp by monitor.defaultApp.collectAsState()
    val app = remember(defaultApp) { defaultApp?.let { MusicApps.find(context, it) } }
    var picking by remember { mutableStateOf(false) }

    OrSecondaryButton(
        text = app?.let { "Open ${it.label}" } ?: "Music",
        icon = OrIcons.MusicNote,
        onClick = { if (app == null || !MusicApps.open(context, app.packageName)) picking = true },
        modifier = modifier,
    )
    if (picking) {
        MusicAppPicker(
            selected = defaultApp,
            onDismiss = { picking = false },
            onPick = { picked ->
                picking = false
                monitor.setDefaultApp(picked.packageName)
                MusicApps.open(context, picked.packageName)
            },
        )
    }
}

/**
 * The rider's music app, chosen from the tablet's music apps as icon tiles; tapping one picks it.
 * Opened from Profile → Music, and from the player's button before an app is chosen.
 */
@Composable
fun MusicAppPicker(selected: String?, onDismiss: () -> Unit, onPick: (MusicApp) -> Unit) {
    val context = LocalContext.current
    val apps = remember { MusicApps.installed(context) }
    Dialog(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .width(PickerWidth)
                .clip(OrShapes.Medium)
                .background(OrColors.Surface)
                .padding(OrSpacing.lg),
            verticalArrangement = Arrangement.spacedBy(OrSpacing.md),
        ) {
            OrLabel(text = "Music app", style = OrType.Title, color = OrColors.OnBackground)
            Text(
                text = if (apps.isEmpty()) {
                    "No music apps on this tablet yet. Install one from the Play Store."
                } else {
                    "OpenRide opens it for you to pick music. What it plays shows in the ride."
                },
                style = OrType.Body,
                color = OrColors.OnSurfaceMuted,
            )
            apps.chunked(PickerColumns).forEach { row ->
                // Tiles share the dialog's width; a short last row keeps their size.
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(OrSpacing.md)) {
                    row.forEach { app -> AppTile(app, app.packageName == selected, Modifier.weight(1f)) { onPick(app) } }
                    repeat(PickerColumns - row.size) { Spacer(modifier = Modifier.weight(1f)) }
                }
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                OrSecondaryButton(text = "Cancel", onClick = onDismiss)
            }
        }
    }
}

@Composable
private fun AppTile(app: MusicApp, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val context = LocalContext.current
    val icon = remember(app.packageName) { appIcon(context, app.packageName) }
    Column(
        modifier = modifier
            .clip(OrShapes.Small)
            .background(OrColors.SurfaceRaised)
            .border(OrSpacing.xs / 2, if (selected) OrColors.Accent else OrColors.SurfaceRaised, OrShapes.Small)
            .clickable(onClick = onClick)
            .padding(vertical = OrSpacing.md, horizontal = OrSpacing.sm),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(OrSpacing.sm),
    ) {
        if (icon != null) {
            Image(bitmap = icon, contentDescription = null, modifier = Modifier.size(TileIcon))
        } else {
            ArtPlaceholder(TileIcon)
        }
        Text(
            text = app.label,
            style = OrType.Body,
            color = if (selected) OrColors.Accent else OrColors.OnBackground,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** The app's launcher icon, or null if it can't be drawn. */
private fun appIcon(context: Context, packageName: String): ImageBitmap? = runCatching {
    context.packageManager.getApplicationIcon(packageName).toBitmap(IconPx, IconPx).asImageBitmap()
}.getOrNull()

/**
 * Android's Notification access screen, where the rider turns the player on: straight to
 * OpenRide's own switch where the tablet has that page (Android 11+), else the list of apps.
 */
fun openMusicAccessSettings(context: Context, listener: ComponentName) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val detail = Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
            .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, listener.flattenToString())
        try {
            context.startActivity(detail)
            return
        } catch (e: ActivityNotFoundException) {
            // Falls through to the list.
        }
    }
    context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
}

/** Top bar: art, title and artist with room for a long title, plus three 56 dp controls. */
private val CompactWidth = 440.dp
private val CompactArt = 56.dp
private val CompactIcon = 32.dp

/**
 * Just Ride: 392 dp from the left gutter ends clear of the output and its widest line under it
 * (the set-an-FTP hint, about 400 dp centred on the 1280 dp screen); 64 dp controls.
 */
private val PanelWidth = 392.dp
private val PanelArt = 128.dp
private val PanelButton = 64.dp
private val PanelIcon = 40.dp

/** Three tiles a row in the picker, at the widest a form dialog gets. */
private val PickerWidth = 560.dp
private const val PickerColumns = 3
private val TileIcon = 64.dp
private const val IconPx = 144

private const val MarqueePauseMs = 2_000
