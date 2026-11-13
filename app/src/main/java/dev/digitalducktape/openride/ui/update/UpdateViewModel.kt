package dev.digitalducktape.openride.ui.update

import androidx.lifecycle.ViewModel
import dev.digitalducktape.openride.core.update.AvailableUpdate
import dev.digitalducktape.openride.core.update.UpdateCheckResult
import dev.digitalducktape.openride.core.update.UpdateRepository
import dev.digitalducktape.openride.core.telemetry.NoOpTelemetry
import dev.digitalducktape.openride.core.telemetry.Telemetry
import dev.digitalducktape.openride.core.telemetry.UpdateAction
import dev.digitalducktape.openride.core.telemetry.UpdatePrompt
import dev.digitalducktape.openride.core.telemetry.trackSafely
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Drives the self-updater screen (PRD #22/T22): check the latest GitHub release against the
 * installed build, download the APK, and hand it to the system installer. There is no URL to
 * configure — the release source is fixed and the check hits GitHub directly.
 *
 * The check → download → install steps are separate `suspend` functions, each triggered by its
 * own explicit user tap (the screen calls them from a `rememberCoroutineScope`, matching
 * [dev.digitalducktape.openride.ui.profile.ProfileCreateViewModel]'s suspend-rather-than-
 * viewModelScope convention). Nothing chains automatically — that's what keeps the ticket's
 * "no auto-install without user tap" guarantee.
 */
class UpdateViewModel(
    private val updateRepository: UpdateRepository,
    private val currentVersionCode: Int,
    private val currentVersionName: String,
    private val assetInfix: String,
    private val telemetry: Telemetry = NoOpTelemetry,
) : ViewModel() {

    data class UiState(
        val isBusy: Boolean = false,
        val status: String? = null,
        val available: AvailableUpdate? = null,
        val downloadedApk: File? = null,
        val currentVersionName: String = "",
        val currentVersionCode: Int = 0,
    )

    private val _uiState = MutableStateFlow(
        UiState(
            currentVersionName = currentVersionName,
            currentVersionCode = currentVersionCode,
        ),
    )
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    /** Fetches the latest release and evaluates it against the installed build. */
    suspend fun checkForUpdate() {
        _uiState.value = _uiState.value.copy(isBusy = true, status = "Checking…", available = null, downloadedApk = null)

        when (val result = updateRepository.check(currentVersionCode, assetInfix)) {
            is UpdateCheckResult.Available -> {
                _uiState.value = _uiState.value.copy(
                    isBusy = false,
                    available = result.update,
                    status = "Version ${result.update.versionName} is available",
                )
                telemetry.trackSafely { UpdatePrompt(UpdateAction.SHOWN) }
            }
            is UpdateCheckResult.UpToDate -> _uiState.value = _uiState.value.copy(
                isBusy = false,
                available = null,
                status = "You're up to date",
            )
            is UpdateCheckResult.Failed -> _uiState.value = _uiState.value.copy(
                isBusy = false,
                available = null,
                status = result.reason,
            )
        }
    }

    /** Downloads the available APK. Does *not* install it — see [installIntent]. */
    suspend fun downloadUpdate() {
        val update = _uiState.value.available ?: return
        _uiState.value = _uiState.value.copy(isBusy = true, status = "Downloading…")

        val file = updateRepository.downloadApk(update)
        _uiState.value = if (file == null) {
            _uiState.value.copy(isBusy = false, status = "Download failed", downloadedApk = null)
        } else {
            _uiState.value.copy(
                isBusy = false,
                status = "Downloaded — tap Install to continue",
                downloadedApk = file,
            )
        }
    }

    /** The intent to hand the downloaded APK to the system installer, or `null` if none is ready. */
    fun installIntent() = _uiState.value.downloadedApk?.let {
        telemetry.trackSafely { UpdatePrompt(UpdateAction.INSTALL_TAPPED) }
        updateRepository.installIntentFor(it)
    }
}
