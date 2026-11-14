package dev.digitalducktape.openride.ui.profile

import androidx.lifecycle.ViewModel
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.profile.WeightUnits
import dev.digitalducktape.openride.core.telemetry.NoOpTelemetry
import dev.digitalducktape.openride.core.telemetry.ProfileCreated
import dev.digitalducktape.openride.core.telemetry.Telemetry
import dev.digitalducktape.openride.core.telemetry.trackSafely
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Profile form state (PRD P0-3: name + avatar required; weight/FTP optional — used for
 * calorie estimates, power zones P1-3, and export accuracy P1-1). One state for both the
 * create-rider flow and editing the active rider's existing profile.
 *
 * Weight is entered and displayed in *pounds* (matching the app's miles-first units); it is
 * converted to canonical kilograms only at save time.
 */
data class ProfileEditorUiState(
    val name: String = "",
    val nameError: String? = null,
    val avatarEmoji: String = AvatarOptions.defaultEmoji,
    val avatarColor: Int = AvatarOptions.defaultColor,
    val avatarPhotoPath: String? = null,
    val weightLbsInput: String = "",
    val weightError: String? = null,
    val ftpInput: String = "",
    val ftpError: String? = null,
    val saved: Boolean = false,
)

/**
 * Create-profile flow (PRD P0-3) and profile editing (feedback: "profile tab should allow
 * profile fields to be updated"), differing only in prefill and what [save] writes:
 *
 * - Create (default): starts blank; saving inserts a new profile and makes it active.
 * - Edit ([editActiveProfile] = `true`): [loadForEdit] prefills from the active rider's
 *   row; saving updates that row in place, preserving fields the form doesn't cover
 *   (paired HR strap).
 */
class ProfileEditorViewModel(
    private val profileRepository: ProfileRepository,
    private val activeProfileHolder: ActiveProfileHolder,
    private val editActiveProfile: Boolean = false,
    private val telemetry: Telemetry = NoOpTelemetry,
) : ViewModel() {
    private val _uiState = MutableStateFlow(ProfileEditorUiState())
    val uiState: StateFlow<ProfileEditorUiState> = _uiState.asStateFlow()

    private var loadedForEdit = false

    /**
     * Prefills the form from the active rider's profile when in edit mode. Safe to call
     * repeatedly (LaunchedEffect on the screen); only the first call loads, so in-progress
     * edits are never clobbered by recomposition.
     */
    suspend fun loadForEdit() {
        if (!editActiveProfile || loadedForEdit) return
        val id = activeProfileHolder.activeProfileId.value ?: return
        val profile = profileRepository.getProfile(id) ?: return
        loadedForEdit = true
        _uiState.value = ProfileEditorUiState(
            name = profile.name,
            avatarEmoji = profile.avatarEmoji,
            avatarColor = profile.avatarColor,
            avatarPhotoPath = profile.avatarPhotoPath,
            weightLbsInput = profile.weightKg?.let(WeightUnits::formatLbs) ?: "",
            ftpInput = profile.ftp?.toString() ?: "",
        )
    }

    fun onNameChange(name: String) {
        _uiState.value = _uiState.value.copy(name = name, nameError = null)
    }

    fun onAvatarEmojiChange(emoji: String) {
        _uiState.value = _uiState.value.copy(avatarEmoji = emoji)
    }

    fun onAvatarColorChange(color: Int) {
        _uiState.value = _uiState.value.copy(avatarColor = color)
    }

    /** Sets the cropped camera photo (its stored path) as this rider's avatar. */
    fun onPhotoCaptured(path: String) {
        _uiState.value = _uiState.value.copy(avatarPhotoPath = path)
    }

    /** Drops the photo, falling back to the emoji/color avatar. */
    fun onPhotoRemoved() {
        _uiState.value = _uiState.value.copy(avatarPhotoPath = null)
    }

    fun onWeightChange(weightLbs: String) {
        _uiState.value = _uiState.value.copy(weightLbsInput = weightLbs, weightError = null)
    }

    fun onFtpChange(ftp: String) {
        _uiState.value = _uiState.value.copy(ftpInput = ftp, ftpError = null)
    }

    /**
     * Validates the form and, if valid, persists it and returns `true`: creating inserts a
     * new profile and sets it active; editing updates the active rider's row in place. Name
     * is required (non-blank); weight (lbs, positive decimal) and FTP (watts, positive whole
     * number) are optional but must be well-formed if provided. Returns `false` on the first
     * invalid field, surfacing the relevant `*Error` in [ProfileEditorUiState] without
     * touching the repository.
     *
     * A plain `suspend fun` rather than an internally-launched coroutine, so it can be
     * driven directly from `runTest` in tests and from `rememberCoroutineScope()` in the
     * screen — the same pattern [dev.digitalducktape.openride.core.ride.RideSessionManager.stop]
     * uses, keeping this view model's async work testable without depending on
     * `viewModelScope`'s Main-dispatcher wiring.
     */
    suspend fun save(): Boolean {
        val current = _uiState.value
        val trimmedName = current.name.trim()

        var next = current
        var valid = true

        if (trimmedName.isBlank()) {
            next = next.copy(nameError = "Name is required")
            valid = false
        }

        val weightKg: Double? = when {
            current.weightLbsInput.isBlank() -> null
            else -> current.weightLbsInput.toDoubleOrNull()?.takeIf { it > 0.0 }
                ?.let(WeightUnits::lbsToKg)
                ?: run {
                    next = next.copy(weightError = "Enter a weight in lbs greater than 0")
                    valid = false
                    null
                }
        }

        val ftp: Int? = when {
            current.ftpInput.isBlank() -> null
            else -> current.ftpInput.toIntOrNull()?.takeIf { it > 0 } ?: run {
                next = next.copy(ftpError = "Enter an FTP in watts greater than 0")
                valid = false
                null
            }
        }

        if (!valid) {
            _uiState.value = next
            return false
        }

        if (editActiveProfile) {
            val id = activeProfileHolder.activeProfileId.value ?: return false
            val existing = profileRepository.getProfile(id) ?: return false
            profileRepository.updateProfile(
                existing.copy(
                    name = trimmedName,
                    avatarEmoji = current.avatarEmoji,
                    avatarColor = current.avatarColor,
                    avatarPhotoPath = current.avatarPhotoPath,
                    weightKg = weightKg,
                    ftp = ftp,
                ),
            )
        } else {
            val id = profileRepository.createProfile(
                Profile(
                    name = trimmedName,
                    avatarEmoji = current.avatarEmoji,
                    avatarColor = current.avatarColor,
                    avatarPhotoPath = current.avatarPhotoPath,
                    weightKg = weightKg,
                    ftp = ftp,
                ),
            )
            activeProfileHolder.setActiveProfile(id)
            telemetry.trackSafely { ProfileCreated(hasPhoto = current.avatarPhotoPath != null) }
        }
        _uiState.value = _uiState.value.copy(saved = true)
        return true
    }
}
