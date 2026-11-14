package dev.digitalducktape.openride.ui.creator

import androidx.lifecycle.ViewModel
import dev.digitalducktape.openride.core.content.CreatorContent
import dev.digitalducktape.openride.core.content.YouTubeContentRepository
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.telemetry.ClassRideTelemetry
import dev.digitalducktape.openride.core.telemetry.ClassSource
import dev.digitalducktape.openride.core.telemetry.NoOpTelemetry
import dev.digitalducktape.openride.core.telemetry.RideEntry
import dev.digitalducktape.openride.core.telemetry.channelFor
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map

/**
 * A creator's own page: their recent classes plus each playlist they've curated.
 *
 * Playlists are how creators organize themed sets of classes — a single row on the Classes
 * tab can only ever show recent uploads, so this is the way to reach the rest of what a
 * creator has published without an API key or a full back-catalog crawl.
 *
 * Like [dev.digitalducktape.openride.ui.classes.ClassesViewModel], the loads here are plain
 * `suspend fun`s driven from the screen rather than launched on `viewModelScope`, so tests
 * can drive them directly from `runTest`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class CreatorViewModel(
    private val contentRepository: YouTubeContentRepository,
    private val rideSessionManager: RideSessionManager,
    private val activeProfileHolder: ActiveProfileHolder,
    rideRepository: RideRepository,
    private val sourceId: Long,
    private val routeLoaded: () -> Boolean,
    private val classTelemetry: ClassRideTelemetry = ClassRideTelemetry(NoOpTelemetry),
) : ViewModel() {

    /** The source behind this page, once loaded: what `class_start` names as the channel. */
    private var source: CreatorContent? = null

    private val _uiState = MutableStateFlow<CreatorUiState>(CreatorUiState.Loading)
    val uiState: StateFlow<CreatorUiState> = _uiState.asStateFlow()

    /** Same "already ridden" badges the Classes tab shows, so they don't vanish on this screen. */
    val takenVideos: Flow<Map<String, Long>> =
        activeProfileHolder.activeProfileId.flatMapLatest { profileId ->
            if (profileId == null) {
                flowOf(emptyMap())
            } else {
                rideRepository.observeTakenVideos(profileId)
                    .map { taken -> taken.associate { it.videoId to it.lastTakenEpochMs } }
            }
        }

    suspend fun load() {
        _uiState.value = CreatorUiState.Loading
        val content = contentRepository.creatorContent(sourceId)
        source = content
        _uiState.value = if (content == null) {
            CreatorUiState.NotFound
        } else {
            CreatorUiState.Loaded(
                displayName = content.displayName,
                latest = content.latest,
                playlistRows = content.playlists.map { PlaylistRow(playlist = it) },
                refreshFailed = content.refreshFailed,
            )
        }
    }

    /**
     * Fetches one playlist's videos. Safe to call for a playlist that isn't on this page.
     *
     * If the shelf scrolls out of the `LazyColumn` (or the rider navigates away and back to a
     * retained view model) while [contentRepository.playlistVideos] is still suspended, the
     * driving `LaunchedEffect` gets cancelled and the `updateRow` call below never runs — the
     * row would stay `isLoading = true` forever, and the screen's `!row.isLoading` guard would
     * then refuse to ever retry it. The `finally` clears the flag on that path too, without
     * suppressing the cancellation itself (nothing here catches or swallows it — the `finally`
     * block runs during the normal unwind and then the exception keeps propagating).
     */
    suspend fun loadPlaylist(playlistId: String) {
        val loaded = _uiState.value as? CreatorUiState.Loaded ?: return
        val row = loaded.playlistRows.firstOrNull { it.playlist.id == playlistId } ?: return

        updateRow(playlistId) { it.copy(isLoading = true, loadFailed = false) }
        try {
            val videos = contentRepository.playlistVideos(playlistId, row.playlist.title)
            updateRow(playlistId) {
                // An empty list means either the fetch failed or the playlist genuinely has no
                // rideable classes (e.g. everything in it was under the minimum length). Both
                // are treated as "couldn't load" on purpose: either way there's nothing to
                // ride, and the shelf shows the same honest message rather than a misleading
                // "empty" state.
                it.copy(videos = videos, isLoading = false, loadFailed = videos.isEmpty())
            }
        } finally {
            // Only touch the flag if it's still set: a successful completion above has already
            // turned it off, so this is a no-op on that path today — but clobbering a
            // just-written successful result here would be a landmine the moment this code
            // ever races with a second load of the same row.
            updateRow(playlistId) { if (it.isLoading) it.copy(isLoading = false) else it }
        }
    }

    // Safe only because every call lands on Compose's single-threaded Main dispatcher: this
    // read-modify-write of _uiState.value has no suspension point in between, and loadPlaylist
    // is only ever driven from a LaunchedEffect, with playlistVideos doing its I/O inside
    // withContext(Dispatchers.IO) and resuming back on the caller's dispatcher. If these loads
    // were ever launched on Dispatchers.Default, two shelves finishing at once could race and
    // one update could clobber the other.
    private fun updateRow(playlistId: String, transform: (PlaylistRow) -> PlaylistRow) {
        val loaded = _uiState.value as? CreatorUiState.Loaded ?: return
        _uiState.value = loaded.copy(
            playlistRows = loaded.playlistRows.map { row ->
                if (row.playlist.id == playlistId) transform(row) else row
            },
        )
    }

    /** Same contract as [dev.digitalducktape.openride.ui.classes.ClassesViewModel.startRideForVideo]. */
    fun startRideForVideo(videoId: String): Boolean {
        val profileId = activeProfileHolder.activeProfileId.value ?: return false
        // A ride already running is left alone (start is a no-op), and so is its class_start.
        if (rideSessionManager.start(profileId, videoId, entry = RideEntry.CREATOR, route = routeLoaded())) {
            reportClassStart()
        }
        return true
    }

    /**
     * `class_start` names the creator whose page this is. Their playlists' videos count as theirs,
     * and the category is the creator's own, which is all the page knows.
     */
    private fun reportClassStart() {
        runCatching {
            val creator = source ?: return
            val (channel, channelSource) = channelFor(creator.channelId, creator.sourceType, creator.displayName)
            classTelemetry.start(channel, channelSource, creator.category, ClassSource.CREATOR)
        }
    }
}
