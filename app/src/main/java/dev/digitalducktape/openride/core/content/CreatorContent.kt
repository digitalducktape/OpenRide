package dev.digitalducktape.openride.core.content

/**
 * Everything the creator page shows for one configured source: their recent uploads plus the
 * playlists they've curated, which is how creators organize themed sets of classes.
 *
 * @param playlists empty when the creator has none, or when the playlists tab couldn't be
 *   read — either way the page still shows [latest] rather than an error.
 * @param refreshFailed true only when the video list itself is stale/empty.
 */
data class CreatorContent(
    val sourceId: Long,
    val displayName: String,
    val latest: List<Video>,
    val playlists: List<PlaylistSummary>,
    val refreshFailed: Boolean,
    val channelId: String = "",
    val sourceType: ContentSourceType = ContentSourceType.CHANNEL,
    val category: ContentCategory = ContentCategory.Workout,
)
