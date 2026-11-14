package dev.digitalducktape.openride.core.content

import android.content.Context
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.withContext

/** Classes shorter than this aren't a meaningful ride, so they never reach the catalog. */
const val MIN_CLASS_DURATION_SEC = 600

/**
 * Content layer for the Classes browser: for each configured source it fetches the public
 * channel/playlist page and the RSS feed, merges them, applies the catalog filters, and
 * caches the result — falling back to the last-known cache (flagged via
 * [ChannelSection.refreshFailed]) when nothing can be reached, so a network blip degrades to
 * stale content rather than an empty screen.
 *
 * Why two sources rather than one:
 * - The **page** ([YouTubePageParser]) is the only key-free source of *duration* and the only
 *   listing that carries the members-only signal (a per-tile badge the feed has no equivalent
 *   of), so both catalog filters depend on it. It also carries roughly twice as many videos
 *   as the feed.
 * - The **feed** ([AtomFeedParser]) is the only source of exact publish timestamps (the page
 *   only says "4 months ago"), and it still works if YouTube changes its page internals.
 *
 * Page entries win on content; feed entries contribute their exact timestamps where the ids
 * match. If the page can't be read, the feed alone drives the row with durations unknown —
 * degraded filtering, but a working catalog. Only when both fail does the row go stale.
 */
class YouTubeContentRepository(
    context: Context,
    private val sourceRepository: ContentSourceRepository,
    private val fetcher: FeedFetcher = HttpUrlFeedFetcher(),
    private val feedParser: AtomFeedParser = AtomFeedParser(),
    private val pageParser: YouTubePageParser = YouTubePageParser(),
    private val cache: ContentCache = ContentCache(context),
) {

    /**
     * One [ChannelSection] per visible configured source, in display order.
     *
     * Sources are fetched concurrently, not one at a time: each is a page fetch (~1 MB of
     * HTML) plus a feed fetch, each retried once on failure, so a dozen configured sources
     * fetched sequentially is plausibly 20-40s of blank spinner on the bike's Wi-Fi.
     * `async`-ing each [fetchSection] call runs them in parallel on [Dispatchers.IO]'s thread
     * pool while `.map { }.awaitAll()` still returns results in the same order the sources
     * were requested in — i.e. the configured display order — regardless of which fetch
     * happens to finish first.
     */
    suspend fun channelSections(): List<ChannelSection> = withContext(Dispatchers.IO) {
        sourceRepository.seedIfEmpty()
        sourceRepository.visibleOnce()
            .map { source -> async { fetchSection(source) } }
            .awaitAll()
    }

    /** The creator page's payload, or `null` if [sourceId] isn't a configured source. */
    suspend fun creatorContent(sourceId: Long): CreatorContent? = withContext(Dispatchers.IO) {
        val source = sourceRepository.getById(sourceId) ?: return@withContext null
        val section = fetchSection(source)
        CreatorContent(
            sourceId = source.id,
            channelId = source.youtubeId,
            sourceType = source.sourceType,
            category = source.category,
            displayName = source.displayName,
            latest = section.videos,
            playlists = fetchPlaylists(source),
            refreshFailed = section.refreshFailed,
        )
    }

    /**
     * One playlist's rideable videos, filtered like any other row. Writes the filtered result
     * back under [playlistId] on success so a later failure — even for a playlist only ever
     * reached from a creator's page, never its own `content_sources` row — has a cache entry
     * to fall back to instead of an empty list.
     */
    suspend fun playlistVideos(playlistId: String, displayName: String): List<Video> =
        withContext(Dispatchers.IO) {
            val videos = fetchVideos(ContentSourceType.PLAYLIST, playlistId, displayName)
            if (videos == null) {
                cache.read(playlistId).orEmpty()
            } else {
                val filtered = rideable(videos)
                cache.write(playlistId, filtered)
                filtered
            }
        }

    private fun fetchSection(source: ContentSource): ChannelSection {
        val videos = fetchVideos(source.sourceType, source.youtubeId, source.displayName)
        val cached = cache.read(source.youtubeId)
        return if (videos == null) {
            ChannelSection(
                sourceId = source.id,
                channelId = source.youtubeId,
                channelName = source.displayName,
                category = source.category,
                sourceType = source.sourceType,
                videos = cached.orEmpty(),
                refreshFailed = true,
            )
        } else {
            val filtered = rideable(videos)
            if (filtered.isEmpty() && !cached.isNullOrEmpty()) {
                // A successful fetch that filters down to nothing is exactly as ambiguous as a
                // markup change that silently broke parsing (Finding 1a): both present as "this
                // source has zero rideable videos right now," and there is no way to tell them
                // apart from here. Overwriting a known-good cache with an empty list on the
                // strength of that ambiguity would destroy the offline fallback for good, so
                // once something is already cached, keep showing it — even on the rare day a
                // source genuinely posts nothing over ten minutes, one row quietly showing
                // yesterday's classes for a cycle is a better rider experience than a row that
                // goes blank. Not writing the cache here (rather than writing the stale list
                // back unchanged) also keeps a later two-in-a-row "genuinely empty" fetch from
                // ever looking any different from this one.
                ChannelSection(
                    sourceId = source.id,
                    channelId = source.youtubeId,
                    channelName = source.displayName,
                    category = source.category,
                    sourceType = source.sourceType,
                    videos = cached,
                    refreshFailed = true,
                )
            } else {
                cache.write(source.youtubeId, filtered)
                ChannelSection(
                    sourceId = source.id,
                    channelId = source.youtubeId,
                    channelName = source.displayName,
                    category = source.category,
                    sourceType = source.sourceType,
                    videos = filtered,
                    refreshFailed = false,
                )
            }
        }
    }

    /** Merged page+feed videos, or `null` when neither source could be read. */
    private fun fetchVideos(
        type: ContentSourceType,
        youtubeId: String,
        displayName: String,
    ): List<Video>? {
        val pageVideos = tryFetch {
            pageParser.parseVideos(fetcher.fetchText(contentPageUrl(type, youtubeId)), displayName)
        }
        val feedVideos = tryFetch {
            fetcher.fetch(feedUrl(type, youtubeId)).use { feedParser.parse(it, displayName) }
        }

        return when {
            // Page listing is authoritative: [YouTubePageParser] has already dropped its
            // members-only tiles, so an id the feed knows about that the parsed page doesn't is
            // either members-only or too new to matter, and must not be unioned back in. (The
            // feed itself has no members-only marker — see feedVideos below for why the
            // page-failed fallback can't filter, only degrade.)
            pageVideos != null -> {
                val publishedById = feedVideos.orEmpty().associate { it.id to it.publishedEpochMs }
                pageVideos.map { video ->
                    publishedById[video.id]?.let { video.copy(publishedEpochMs = it) } ?: video
                }
            }
            // Page fetch failed: the feed is all we have, but it carries no members-only marker,
            // so these videos can't be verified as public. Show them (the row isn't empty) but
            // mark them non-startable — a later successful page fetch re-verifies and clears it.
            feedVideos != null -> feedVideos.map { it.copy(startable = false) }
            else -> null
        }
    }

    private fun fetchPlaylists(source: ContentSource): List<PlaylistSummary> {
        if (source.sourceType != ContentSourceType.CHANNEL) return emptyList()
        return tryFetch {
            pageParser.parsePlaylists(
                fetcher.fetchText("https://www.youtube.com/channel/${source.youtubeId}/playlists"),
            )
        }.orEmpty()
            .filter { ClassRelevance.isCyclingTitle(it.title) }
            // Same reasoning as rideable()'s dedup: the Creator screen keys its playlist
            // LazyColumn by `playlist.id`, so a page listing a playlist twice would crash
            // Compose with "Key ... was already used". Collapse duplicates by id, first wins.
            .distinctBy { it.id }
    }

    /**
     * Keeps only videos worth showing as a class: long enough to be a real ride (unknown
     * duration is kept — it's the feed-fallback case, not a short) and whose title reads as a
     * cycling class. The relevance check is what keeps a creator's *other* content — sculpt
     * and strength classes, vlogs — out of a cycling catalog; see [ClassRelevance].
     */
    private fun rideable(videos: List<Video>): List<Video> =
        videos.filter { video ->
            (video.durationSec == null || video.durationSec >= MIN_CLASS_DURATION_SEC) &&
                ClassRelevance.isCyclingTitle(video.title)
        }
            // A page can list the same video more than once (a pinned tile that also appears in
            // the grid, a video in two spots of a playlist). Two Video objects sharing an id
            // collide the `key = { it.id }` in the Creator screen's LazyRow and crash Compose
            // ("Key ... was already used"), so collapse duplicates here — the single choke point
            // every displayed list (latest shelf and each playlist) passes through. distinctBy
            // keeps the first occurrence, preserving page order.
            .distinctBy { it.id }

    /**
     * Runs a fetch with one retry, converting *any* failure — network error, malformed XML,
     * unreadable page JSON — into `null`. One bad response must never crash the Classes tab.
     *
     * [CancellationException] must be rethrown, not converted to `null`: it means the calling
     * coroutine was cancelled, not that the fetch failed, and swallowing it here would turn a
     * cancellation into a silent "fetch failed, use the cache" — defeating the same rethrow
     * that [retryingOnce] already does, and breaking structured concurrency. Do not fold this
     * back into the generic catch below.
     */
    private fun <T> tryFetch(block: () -> T): T? = try {
        retryingOnce(block)
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (e: Exception) {
        null
    }

    private fun contentPageUrl(type: ContentSourceType, youtubeId: String) = when (type) {
        ContentSourceType.CHANNEL -> "https://www.youtube.com/channel/$youtubeId/videos"
        ContentSourceType.PLAYLIST -> "https://www.youtube.com/playlist?list=$youtubeId"
    }

    private fun feedUrl(type: ContentSourceType, youtubeId: String) = when (type) {
        ContentSourceType.CHANNEL -> "https://www.youtube.com/feeds/videos.xml?channel_id=$youtubeId"
        ContentSourceType.PLAYLIST -> "https://www.youtube.com/feeds/videos.xml?playlist_id=$youtubeId"
    }
}
