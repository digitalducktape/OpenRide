package dev.digitalducktape.openride.ui.sources

import androidx.lifecycle.ViewModel
import dev.digitalducktape.openride.core.content.ChannelHandleResolver
import dev.digitalducktape.openride.core.content.ContentCategory
import dev.digitalducktape.openride.core.content.ContentSource
import dev.digitalducktape.openride.core.content.ContentSourceRepository
import dev.digitalducktape.openride.core.content.HttpStatusException
import dev.digitalducktape.openride.core.content.ContentSourceType
import dev.digitalducktape.openride.core.content.ResolvedSource
import dev.digitalducktape.openride.core.telemetry.ContentSourceAdded
import dev.digitalducktape.openride.core.telemetry.NoOpTelemetry
import dev.digitalducktape.openride.core.telemetry.SourceKind
import dev.digitalducktape.openride.core.telemetry.Telemetry
import dev.digitalducktape.openride.core.telemetry.channelFor
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Where the "add a source" flow currently is. */
sealed interface AddSourceState {
    data object Idle : AddSourceState

    data object Resolving : AddSourceState

    /** Resolved and awaiting the rider's category choice — nothing has been saved yet. */
    data class Resolved(val source: ResolvedSource) : AddSourceState

    data class Failed(val message: String) : AddSourceState
}

/**
 * The Content Sources settings screen: which creators and playlists the Classes tab draws
 * from.
 *
 * Adding is deliberately two-step — resolve, then confirm with a category — because a pasted
 * link resolves to a name the rider should see before it becomes a row on their Classes tab,
 * and because a failed resolution must never leave a half-configured source behind.
 */
class ContentSourcesViewModel(
    private val sourceRepository: ContentSourceRepository,
    private val resolver: ChannelHandleResolver,
    private val telemetry: Telemetry = NoOpTelemetry,
) : ViewModel() {

    val sources: Flow<List<ContentSource>> = sourceRepository.observeAll()

    private val _addState = MutableStateFlow<AddSourceState>(AddSourceState.Idle)
    val addState: StateFlow<AddSourceState> = _addState.asStateFlow()

    suspend fun resolve(input: String) {
        _addState.value = AddSourceState.Resolving
        _addState.value = resolver.resolve(input).fold(
            onSuccess = { AddSourceState.Resolved(it) },
            onFailure = { error ->
                AddSourceState.Failed(
                    when (error) {
                        // Checked before the plain IOException branch below: a non-2xx
                        // response is a subtype of IOException, so a 404 for a mistyped
                        // handle would otherwise be misreported as a connectivity problem
                        // (see HttpStatusException's KDoc for why that's actively misleading).
                        is HttpStatusException -> "Couldn't find that channel or playlist"
                        is java.io.IOException -> "No connection — try again"
                        else -> "Couldn't find that channel or playlist"
                    },
                )
            },
        )
    }

    suspend fun confirmAdd(category: ContentCategory) {
        val resolved = (_addState.value as? AddSourceState.Resolved)?.source ?: return
        sourceRepository.add(resolved, category)
        // Only after the add went through. The name is YouTube's page title for the source,
        // never the text the rider typed.
        runCatching {
            telemetry.track(
                ContentSourceAdded(
                    channelFor(resolved.youtubeId, resolved.sourceType, resolved.displayName).first,
                    if (resolved.sourceType == ContentSourceType.PLAYLIST) SourceKind.PLAYLIST else SourceKind.CHANNEL,
                ),
            )
        }
        _addState.value = AddSourceState.Idle
    }

    fun cancelAdd() {
        _addState.value = AddSourceState.Idle
    }

    suspend fun setHidden(id: Long, hidden: Boolean) = sourceRepository.setHidden(id, hidden)

    suspend fun deleteCustom(id: Long) = sourceRepository.deleteCustom(id)
}
