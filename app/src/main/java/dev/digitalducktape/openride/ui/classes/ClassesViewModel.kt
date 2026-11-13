package dev.digitalducktape.openride.ui.classes

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.digitalducktape.openride.core.content.ChannelSection
import dev.digitalducktape.openride.core.content.Video
import dev.digitalducktape.openride.core.content.YouTubeContentRepository
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.telemetry.RideEntry
import kotlin.random.Random
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/**
 * Classes tab (PRD P0-6, T10): loads each configured channel's videos via
 * [YouTubeContentRepository] and exposes them as one row per channel.
 *
 * [refresh] is a plain `suspend fun` driven from the screen's `LaunchedEffect`/
 * `rememberCoroutineScope`, rather than something this class launches on `viewModelScope`
 * itself — the same pattern
 * [dev.digitalducktape.openride.ui.profile.ProfileCreateViewModel.save] uses, so the load
 * can be driven directly from `runTest` in tests without depending on `viewModelScope`'s
 * Main-dispatcher wiring.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ClassesViewModel(
    private val contentRepository: YouTubeContentRepository,
    private val rideSessionManager: RideSessionManager,
    private val activeProfileHolder: ActiveProfileHolder,
    rideRepository: RideRepository,
    private val routeLoaded: () -> Boolean,
    private val random: Random = Random.Default,
) : ViewModel() {

    private val _uiState = MutableStateFlow<ClassesUiState>(ClassesUiState.Loading)
    val uiState: StateFlow<ClassesUiState> = _uiState.asStateFlow()

    private val _filters = MutableStateFlow(ClassFilters())
    val filters: StateFlow<ClassFilters> = _filters.asStateFlow()

    /**
     * One-shot user notices (e.g. a refused non-startable class). `extraBufferCapacity = 1` with
     * no replay lets [startRideForVideo]'s non-suspending `tryEmit` succeed without dropping the
     * message, while a rider who wasn't collecting doesn't later get a stale toast.
     */
    private val _messages = MutableSharedFlow<String>(extraBufferCapacity = 1)
    val messages: SharedFlow<String> = _messages.asSharedFlow()

    /**
     * Bumped whenever Random sort is (re-)selected, so the shuffle is stable while the rider
     * scrolls but reshuffles when they ask for a new order.
     */
    private val shuffleSeed = MutableStateFlow(random.nextLong())

    private val loadedSections: StateFlow<List<ChannelSection>> = _uiState
        .map { state -> (state as? ClassesUiState.Loaded)?.sections.orEmpty() }
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    /**
     * When the active profile last rode each class, keyed by video id (v2 "taken" badges).
     * Live Room flow, so finishing a video ride badges its card as soon as the rider is
     * back on this tab. A `rides` row exists only for a finished, saved ride, so this is
     * exactly the set of *completed* classes the "Hide completed" filter acts on.
     */
    val takenVideos: StateFlow<Map<String, Long>> =
        activeProfileHolder.activeProfileId.flatMapLatest { profileId ->
            if (profileId == null) {
                flowOf(emptyMap())
            } else {
                rideRepository.observeTakenVideos(profileId)
                    .map { taken -> taken.associate { it.videoId to it.lastTakenEpochMs } }
            }
        }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyMap())

    /** Creator rows for browse mode — narrowed to the chosen category and hide-completed state. */
    val rows: StateFlow<List<ChannelSection>> =
        combine(loadedSections, _filters, takenVideos) { sections, filters, taken ->
            ClassFiltering.rows(sections, filters, taken.keys).filter { it.videos.isNotEmpty() }
        }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    /** The flat grid, or `null` while the tab should show creator rows instead. */
    val gridVideos: StateFlow<List<Video>?> =
        combine(loadedSections, _filters, shuffleSeed, takenVideos) { sections, filters, seed, taken ->
            if (filters.isDefaultBrowse) {
                null
            } else {
                ClassFiltering.grid(sections, filters, Random(seed), taken.keys)
            }
        }.stateIn(viewModelScope, SharingStarted.Eagerly, null)

    fun setCategory(category: CategoryFilter) {
        _filters.value = _filters.value.copy(category = category)
    }

    fun setSort(sort: ClassSort) {
        if (sort == ClassSort.Random) shuffleSeed.value = random.nextLong()
        _filters.value = _filters.value.copy(sort = sort)
    }

    fun setLength(length: LengthFilter) {
        _filters.value = _filters.value.copy(length = length)
    }

    fun setHideTaken(hide: Boolean) {
        _filters.value = _filters.value.copy(hideTaken = hide)
    }

    /**
     * A uniformly random class from everything the current filters allow — the Random Ride
     * button. Returns `null` when nothing matches (button is disabled in that state), and
     * deliberately ignores the *sort*, which only affects presentation order. Only [Video.startable]
     * videos are eligible, so Random Ride never lands the rider on a class that won't start.
     */
    fun randomVideo(): Video? =
        ClassFiltering.grid(
            loadedSections.value,
            _filters.value.copy(sort = ClassSort.Newest),
            random,
            takenVideos.value.keys,
        ).filter { it.startable }.randomOrNull(random)

    /**
     * The Random ride button: a [randomVideo] started through [startRideForVideo]. Returns the
     * started video's id to navigate to, or `null` when nothing matched or it didn't start.
     */
    fun startRandomRide(): String? = randomVideo()?.takeIf { startRideForVideo(it) }?.id

    /**
     * Fetches (or re-fetches) all configured channels. Safe to call repeatedly — in particular,
     * every time the rider returns to the Classes tab, since `ClassesScreen`'s
     * `LaunchedEffect(Unit) { refresh() }` re-fires on every recomposition of that effect scope
     * (tab re-entry, returning from a ride, etc.), not just the first.
     *
     * Only resets to [ClassesUiState.Loading] on a cold start — when nothing has loaded yet.
     * Once something is loaded, a re-fetch keeps showing it while the new one is in flight
     * rather than blanking the tab to a full-screen spinner on every single visit; the eventual
     * [ClassesUiState.Loaded] write below still replaces it once the new fetch completes.
     */
    suspend fun refresh() {
        if (_uiState.value !is ClassesUiState.Loaded) {
            _uiState.value = ClassesUiState.Loading
        }
        val sections = contentRepository.channelSections()
        _uiState.value = ClassesUiState.Loaded(
            sections = sections,
            anyRefreshFailed = sections.any { it.refreshFailed },
        )
    }

    /**
     * Starts a ride session for the active profile ahead of navigating to the in-app video
     * player (v2 spec) — same semantics as
     * [dev.digitalducktape.openride.ui.home.HomeViewModel.startQuickRide]: returns `false`
     * (and starts nothing) when no profile is active, and the caller treats that as
     * "not navigable." The video's id is recorded on the persisted ride for the "taken" badges.
     *
     * A non-[Video.startable] video (feed-fallback, unverifiable as public) is refused here with
     * a transient [messages] notice rather than started — starting one would strand the rider on
     * YouTube's members-only wall against a black player. It stays refused until a page fetch
     * re-verifies it.
     */
    fun startRideForVideo(video: Video): Boolean {
        if (!video.startable) {
            _messages.tryEmit("Can't verify this class right now — pull to refresh")
            return false
        }
        val profileId = activeProfileHolder.activeProfileId.value ?: return false
        rideSessionManager.start(profileId, video.id, entry = RideEntry.CLASSES, route = routeLoaded())
        return true
    }
}
