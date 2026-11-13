package dev.digitalducktape.openride.ui.ride

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioManager
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import dev.digitalducktape.openride.core.ride.RideSessionState
import dev.digitalducktape.openride.core.telemetry.ClassRideTelemetry
import dev.digitalducktape.openride.core.telemetry.NoOpTelemetry
import dev.digitalducktape.openride.ui.classes.YouTubeEmbed
import dev.digitalducktape.openride.ui.common.TimeFormat
import dev.digitalducktape.openride.ui.designsystem.OrColors
import dev.digitalducktape.openride.ui.designsystem.OrShapes
import dev.digitalducktape.openride.ui.designsystem.OrSpacing
import dev.digitalducktape.openride.ui.designsystem.OrType
import dev.digitalducktape.openride.ui.designsystem.component.OrAccentButton
import dev.digitalducktape.openride.ui.designsystem.component.OrConfirmDialog
import dev.digitalducktape.openride.ui.designsystem.component.OrEyebrow
import dev.digitalducktape.openride.ui.designsystem.component.OrSecondaryButton
import dev.digitalducktape.openride.core.telemetry.MusicSurface
import dev.digitalducktape.openride.ui.music.MiniPlayer
import kotlinx.coroutines.launch

/**
 * The in-app class player (v2 spec, superseding the T10 YouTube-app handoff): a full-bleed
 * WebView streaming the class through YouTube's own embedded player, with live ride metrics
 * overlaid — timer and ride controls along the top scrim, [RideMetricsBar] along the bottom.
 *
 * The overlay is dismissible (tap the video) so YouTube's native player controls are always
 * reachable and never permanently covered — part of the app's deliberate YouTube ToS stance.
 * The "Ride controls" pill brings it back, and nothing else does: it stays away until the rider
 * asks for it (rider, 2026-11-12).
 *
 * Ride state comes from the same [InRideViewModel] as the plain in-ride screen, and the
 * video tracks it: pausing the ride (Pause button or freewheel auto-pause) pauses the video
 * through the player API, resuming resumes it, and the video reaching its end finishes the
 * workout automatically.
 *
 * The rider can mute the class's own audio (#72) to ride to their music instead, which matters
 * most for scenic rides. It's a choice for this ride, not a setting: a class starts with its
 * sound on, so a coached class is never silent by surprise, unless the rider's music is already
 * playing as it opens, when it starts muted and the music carries on. While the class is muted
 * the top strip carries the music player.
 *
 * The mute is the WebView's own (`WebViewCompat.setAudioMuted`) where it has one: the video
 * plays on untouched, and the WebView lets go of the sound, which Android gives to one app at a
 * time, so the music app can play without the class pausing. Unmuting takes the sound back, as
 * starting any class does. An older WebView falls back to the page's `openrideSetMuted`
 * ([YouTubeEmbed]), which has to restart the video where it was (a few seconds of black).
 */
@Composable
fun VideoRideScreen(
    viewModel: InRideViewModel,
    videoId: String,
    onRideEnded: (rideId: Long) -> Unit,
    modifier: Modifier = Modifier,
    classTelemetry: ClassRideTelemetry = remember { ClassRideTelemetry(NoOpTelemetry) },
) {
    val uiState by viewModel.uiState.collectAsState(initial = InRideUiState())
    val scope = rememberCoroutineScope()
    var overlayVisible by remember { mutableStateOf(true) }
    var showEndConfirmation by remember { mutableStateOf(false) }
    // A class started over the rider's own music starts muted: they chose the music first
    // (rider, 2026-11-12). Asked once, as the screen opens, before the class makes any sound.
    val context = LocalContext.current
    var classMuted by rememberSaveable { mutableStateOf(riderMusicPlaying(context)) }

    // Shared by the End Ride dialog and the video-completion auto-end. endRide() returns
    // null if the ride is already over, so the two paths can't double-fire navigation.
    val currentElapsedSec by rememberUpdatedState(uiState.elapsedSec)
    LaunchedEffect(classMuted) { classTelemetry.muteState(classMuted) }
    // Any other way the class ends still closes it out, once (ClassRideTelemetry.end is idempotent):
    // the ride finishing or stopping without our buttons (sensor-driven or elsewhere), and the
    // screen being left (back, navigation). Disposal during a configuration change is
    // recreation, not leaving, so it is skipped; the new composition carries on with the same
    // ride and the same ClassRideTelemetry.
    val activity = context as? android.app.Activity
    var sawLive by remember { mutableStateOf(false) }
    LaunchedEffect(uiState.sessionState) {
        when (uiState.sessionState) {
            RideSessionState.Active, RideSessionState.Paused -> sawLive = true
            is RideSessionState.Finished -> classTelemetry.end(currentElapsedSec.toLong(), false)
            RideSessionState.Idle -> if (sawLive) classTelemetry.end(currentElapsedSec.toLong(), false)
        }
    }
    DisposableEffect(Unit) {
        onDispose {
            if (activity?.isChangingConfigurations != true) {
                classTelemetry.end(currentElapsedSec.toLong(), false)
            }
        }
    }
    val endRideAndShowSummary: (finished: Boolean) -> Unit = { finished ->
        // class_end fires once however the ride ends (End ride button, or the video finishing):
        // ClassRideTelemetry ignores the second call.
        classTelemetry.end(currentElapsedSec.toLong(), finished)
        scope.launch {
            val ride = viewModel.endRide()
            if (ride != null) onRideEnded(ride.id)
        }
    }

    Box(modifier = modifier.fillMaxSize().background(Color.Black)) {
        ClassPlayer(
            videoId = videoId,
            paused = uiState.isPaused,
            muted = classMuted,
            onVideoEnded = { endRideAndShowSummary(true) },
            onDuration = classTelemetry::videoDuration,
            onPlayerError = classTelemetry::playerError,
            modifier = Modifier.fillMaxSize(),
        )

        if (overlayVisible) {
            // Full-screen tap catcher: any tap on the video area tucks the overlay away so
            // YouTube's own controls become reachable. Sits *under* the overlay rows so the
            // ride controls and metrics stay tappable themselves.
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { overlayVisible = false },
            )

            TopScrimRow(
                uiState = uiState,
                classMuted = classMuted,
                onToggleMute = { classMuted = !classMuted },
                onPauseResume = { if (uiState.isPaused) viewModel.resume() else viewModel.pause() },
                onEndRide = { showEndConfirmation = true },
                modifier = Modifier.align(Alignment.TopCenter),
            )

            RideMetricsBar(
                uiState = uiState,
                translucent = true,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        } else {
            RideControlsPill(
                onClick = { overlayVisible = true },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(OrSpacing.md),
            )
        }
    }

    if (showEndConfirmation) {
        OrConfirmDialog(
            title = "End ride?",
            text = "This will stop and save your ride.",
            confirmText = "End ride",
            // The rider's colour, not red (rider's ask, 2026-10-21).
            destructive = false,
            onConfirm = {
                showEndConfirmation = false
                endRideAndShowSummary(false)
            },
            onDismiss = { showEndConfirmation = false },
        )
    }
}

/**
 * The WebView hosting YouTube's embedded player. Created once per [videoId]. [paused]
 * mirrors the *ride's* paused state into the player (see [YouTubeEmbed] for the page-side
 * functions), [muted] silences the class's own audio (#72), and [onVideoEnded] fires — already
 * on the UI thread — when playback completes.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun ClassPlayer(
    videoId: String,
    paused: Boolean,
    muted: Boolean,
    onVideoEnded: () -> Unit,
    onDuration: (Double) -> Unit,
    onPlayerError: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    var webView by remember { mutableStateOf<WebView?>(null) }
    val currentOnVideoEnded by rememberUpdatedState(onVideoEnded)
    val currentOnDuration by rememberUpdatedState(onDuration)
    val currentOnPlayerError by rememberUpdatedState(onPlayerError)

    AndroidView(
        modifier = modifier,
        factory = { context ->
            WebView(context).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
                setBackgroundColor(android.graphics.Color.BLACK)
                settings.javaScriptEnabled = true
                // The class should start without the rider reaching for the screen mid-mount.
                settings.mediaPlaybackRequiresUserGesture = false
                webViewClient = WebViewClient()
                webChromeClient = WebChromeClient()
                addJavascriptInterface(
                    // JS-interface methods arrive on a WebView-internal thread; hop to the
                    // UI thread before touching Compose/navigation state.
                    VideoEndBridge(
                        onEnded = { post { currentOnVideoEnded() } },
                        onDuration = { seconds -> post { currentOnDuration(seconds) } },
                        onError = { code -> post { currentOnPlayerError(code) } },
                    ),
                    YouTubeEmbed.BRIDGE_NAME,
                )
                // H.264 for the class (#73), set before the page loads so it is in place when
                // the player first asks what the tablet can decode. A WebView too old for
                // document-start scripts plays as before.
                if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                    WebViewCompat.addDocumentStartJavaScript(
                        this,
                        YouTubeEmbed.H264_PREFERENCE_SCRIPT,
                        YouTubeEmbed.PLAYER_ORIGINS,
                    )
                }
                // Silent before the first frame when the class starts muted, so it never
                // takes the sound from the rider's music.
                val webViewMute = WebViewFeature.isFeatureSupported(WebViewFeature.MUTE_AUDIO)
                if (webViewMute) WebViewCompat.setAudioMuted(this, muted)
                loadDataWithBaseURL(
                    YouTubeEmbed.BASE_URL,
                    YouTubeEmbed.html(videoId, startMuted = muted && !webViewMute),
                    "text/html",
                    "utf-8",
                    null,
                )
                webView = this
            }
        },
    )

    LaunchedEffect(webView, paused) {
        webView?.evaluateJavascript(if (paused) "openridePause()" else "openrideResume()", null)
    }

    LaunchedEffect(webView, muted) {
        val view = webView ?: return@LaunchedEffect
        if (WebViewFeature.isFeatureSupported(WebViewFeature.MUTE_AUDIO)) {
            WebViewCompat.setAudioMuted(view, muted)
        } else {
            view.evaluateJavascript(YouTubeEmbed.muteScript(muted), null)
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            webView?.apply {
                // Stop audio immediately on navigation away (End Ride → summary) rather
                // than whenever the view happens to be garbage collected.
                loadUrl("about:blank")
                destroy()
            }
        }
    }
}

/** Whether something is already playing music as the class opens: the rider's own app. */
private fun riderMusicPlaying(context: Context): Boolean =
    (context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager)?.isMusicActive == true

/** Page → app callback surface injected as `window.OpenRideBridge` (see [YouTubeEmbed]). */
private class VideoEndBridge(
    private val onEnded: () -> Unit,
    private val onDuration: (Double) -> Unit,
    private val onError: (Int) -> Unit,
) {
    @JavascriptInterface
    fun onVideoEnded() = onEnded()

    /** The video's length in seconds, once the player knows it. */
    @JavascriptInterface
    fun onDuration(seconds: Double) = onDuration.invoke(seconds)

    /** YouTube's numeric IFrame error code; nothing else crosses over. */
    @JavascriptInterface
    fun onPlayerError(code: Int) = onError(code)
}

@Composable
private fun TopScrimRow(
    uiState: InRideUiState,
    classMuted: Boolean,
    onToggleMute: () -> Unit,
    onPauseResume: () -> Unit,
    onEndRide: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        // Goal progress runs across the very top edge, the way the class player runs the
        // class timeline there.
        uiState.goalProgress?.let { GoalHairline(it) }
        TopStripContent(
            uiState = uiState,
            classMuted = classMuted,
            onToggleMute = onToggleMute,
            onPauseResume = onPauseResume,
            onEndRide = onEndRide,
        )
    }
}

@Composable
private fun TopStripContent(
    uiState: InRideUiState,
    classMuted: Boolean,
    onToggleMute: () -> Unit,
    onPauseResume: () -> Unit,
    onEndRide: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(
                Brush.verticalGradient(0f to VideoScrimTop, VideoScrimHoldEnd to VideoScrimTop, 1f to Color.Transparent),
            )
            .padding(horizontal = OrSpacing.lg, vertical = OrSpacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column {
            Text(
                text = TimeFormat.elapsed(uiState.elapsedSec),
                style = OrType.MetricTimerCompact,
                color = OrColors.OnBackground,
            )
            OrEyebrow("Elapsed")
        }

        val statusText = when {
            !uiState.sensorsAvailable -> "Sensors not detected"
            uiState.autoPaused -> "Auto-paused. Pedal to resume"
            uiState.isPaused -> "Ride paused"
            else -> null
        }
        if (statusText != null) {
            Text(
                text = statusText,
                style = OrType.Subtitle,
                color = if (uiState.sensorsAvailable) OrColors.OnBackground else OrColors.Warning,
                maxLines = 1,
            )
        } else if (classMuted) {
            // The rider's music in the class's place (#72). A status line takes the slot when
            // there is one: the strip has room for either, not both.
            MiniPlayer(surface = MusicSurface.VIDEO_RIDE)
        }

        Row(horizontalArrangement = Arrangement.spacedBy(OrSpacing.md)) {
            // Raised fill behind the outlined buttons: they sit on video.
            OrSecondaryButton(
                text = YouTubeEmbed.muteLabel(classMuted),
                onClick = onToggleMute,
                modifier = Modifier.background(OrColors.SurfaceRaised, OrShapes.Small),
            )
            OrSecondaryButton(
                text = if (uiState.isPaused) "Resume" else "Pause",
                onClick = onPauseResume,
                modifier = Modifier.background(OrColors.SurfaceRaised, OrShapes.Small),
            )
            OrAccentButton(text = "End ride", onClick = onEndRide)
        }
    }
}

/**
 * The strip over video holds [VideoScrimTop] down past the ELAPSED label before it fades, so the
 * label stays readable over bright cloud (bike test, 2026-10-27).
 */
private val VideoScrimTop = Color(0xCC000000)
private const val VideoScrimHoldEnd = 0.8f

/** Brings the overlay back once it's been tucked away. Raised fill: it sits on video. */
@Composable
private fun RideControlsPill(onClick: () -> Unit, modifier: Modifier = Modifier) {
    OrSecondaryButton(
        text = "Ride controls",
        onClick = onClick,
        modifier = modifier.background(OrColors.SurfaceRaised, OrShapes.Small),
    )
}
