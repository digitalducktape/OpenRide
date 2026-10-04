package dev.digitalducktape.openride.ui.profile

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import dev.digitalducktape.openride.core.files.OpenRideFileProvider
import dev.digitalducktape.openride.core.profile.AvatarPhotoStore
import dev.digitalducktape.openride.ui.common.ProfileAvatar
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The profile form (PRD P0-3), shared by "Add rider" and "Edit profile" (via
 * [ProfileEditorViewModel]'s two modes). Laid out as a single non-scrolling page for the
 * bike's landscape screen: avatar (photo/color/emoji) on the left, the text fields and
 * actions on the right.
 *
 * The avatar photo comes from the tablet's built-in camera (TakePicture into a
 * FileProvider'd cache file), which [AvatarPhotoStore.importCapture] then center-crops for
 * the circular avatar. The app declares CAMERA for the mini-games head tracker, and Android
 * refuses ACTION_IMAGE_CAPTURE from an app that declares CAMERA without holding it, so the photo
 * button asks for the permission first when needed.
 */
@Composable
fun ProfileEditorScreen(
    viewModel: ProfileEditorViewModel,
    avatarPhotoStore: AvatarPhotoStore,
    title: String,
    onSaved: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var cameraError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) { viewModel.loadForEdit() }
    LaunchedEffect(uiState.saved) {
        if (uiState.saved) onSaved()
    }

    // One capture target per screen visit; the camera app writes the raw photo here and
    // importCapture deletes it once the cropped avatar is stored.
    val captureFile = remember {
        File(context.cacheDir, "avatar_capture/capture_${System.currentTimeMillis()}.jpg")
            .also { it.parentFile?.mkdirs() }
    }
    val takePicture = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        if (!success) return@rememberLauncherForActivityResult
        scope.launch {
            val storedPath = withContext(Dispatchers.IO) { avatarPhotoStore.importCapture(captureFile) }
            if (storedPath != null) {
                cameraError = null
                viewModel.onPhotoCaptured(storedPath)
            } else {
                cameraError = "Couldn't read the photo from the camera"
            }
        }
    }

    fun launchCamera() {
        try {
            takePicture.launch(OpenRideFileProvider.uriFor(context, captureFile))
        } catch (_: ActivityNotFoundException) {
            cameraError = "No camera app available on this tablet"
        } catch (_: SecurityException) {
            cameraError = "OpenRide needs camera access to take a photo"
        }
    }
    val requestCameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) launchCamera() else cameraError = "OpenRide needs camera access to take a photo"
    }

    Surface(modifier = modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(modifier = Modifier.fillMaxSize().padding(horizontal = 48.dp, vertical = 32.dp)) {
            // Save/Cancel live in the header, not under the fields: the tablet's on-screen
            // keyboard covers the lower half of the screen, and this page deliberately
            // doesn't scroll, so actions below the inputs are hidden while typing. The
            // keyboard's Done key brings them back, so this is about keeping the primary
            // action in view rather than about rescuing an unreachable one.
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.headlineLarge,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onBackground,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TextButton(onClick = onCancel) {
                        Text("Cancel")
                    }
                    Button(onClick = { scope.launch { viewModel.save() } }) {
                        Text("Save")
                    }
                }
            }

            Row(modifier = Modifier.fillMaxWidth().padding(top = 24.dp)) {
                AvatarColumn(
                    uiState = uiState,
                    cameraError = cameraError,
                    onTakePhoto = {
                        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                            PackageManager.PERMISSION_GRANTED
                        if (granted) launchCamera() else requestCameraPermission.launch(Manifest.permission.CAMERA)
                    },
                    onRemovePhoto = viewModel::onPhotoRemoved,
                    onColorSelected = viewModel::onAvatarColorChange,
                    onEmojiSelected = viewModel::onAvatarEmojiChange,
                )

                Column(modifier = Modifier.padding(start = 64.dp)) {
                    OutlinedTextField(
                        value = uiState.name,
                        onValueChange = viewModel::onNameChange,
                        label = { Text("Name") },
                        isError = uiState.nameError != null,
                        supportingText = { uiState.nameError?.let { Text(it) } },
                        singleLine = true,
                        modifier = Modifier.width(360.dp),
                    )

                    OutlinedTextField(
                        value = uiState.weightLbsInput,
                        onValueChange = viewModel::onWeightChange,
                        label = { Text("Weight (lbs) — optional") },
                        isError = uiState.weightError != null,
                        supportingText = { uiState.weightError?.let { Text(it) } },
                        singleLine = true,
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.width(360.dp).padding(top = 8.dp),
                    )

                    OutlinedTextField(
                        value = uiState.ftpInput,
                        onValueChange = viewModel::onFtpChange,
                        label = { Text("FTP (watts) — optional") },
                        isError = uiState.ftpError != null,
                        supportingText = { uiState.ftpError?.let { Text(it) } },
                        singleLine = true,
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.width(360.dp).padding(top = 8.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun AvatarColumn(
    uiState: ProfileEditorUiState,
    cameraError: String?,
    onTakePhoto: () -> Unit,
    onRemovePhoto: () -> Unit,
    onColorSelected: (Int) -> Unit,
    onEmojiSelected: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        ProfileAvatar(
            photoPath = uiState.avatarPhotoPath,
            color = Color(uiState.avatarColor),
            emoji = uiState.avatarEmoji,
            size = 120.dp,
            emojiSize = 48.sp,
        )

        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.padding(top = 12.dp),
        ) {
            OutlinedButton(onClick = onTakePhoto) {
                Text(if (uiState.avatarPhotoPath == null) "Take photo" else "Retake photo")
            }
            if (uiState.avatarPhotoPath != null) {
                TextButton(onClick = onRemovePhoto) {
                    Text("Remove")
                }
            }
        }
        cameraError?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(top = 4.dp),
            )
        }

        Text(
            text = "Avatar color",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 20.dp),
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.padding(top = 8.dp),
        ) {
            AvatarOptions.colors.forEach { colorInt ->
                PickerCircle(
                    selected = uiState.avatarColor == colorInt,
                    background = Color(colorInt),
                    onClick = { onColorSelected(colorInt) },
                )
            }
        }

        Text(
            text = "Avatar icon",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 20.dp),
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.padding(top = 8.dp),
        ) {
            AvatarOptions.emojis.forEach { emoji ->
                PickerCircle(
                    selected = uiState.avatarEmoji == emoji,
                    background = MaterialTheme.colorScheme.surfaceVariant,
                    onClick = { onEmojiSelected(emoji) },
                ) {
                    Text(text = emoji, fontSize = 16.sp)
                }
            }
        }
    }
}

/**
 * One swatch in the color/emoji pickers. `requiredSize` (not `size`) so every circle stays
 * exactly [PICKER_CIRCLE_SIZE] even if a tight parent constraint would otherwise squeeze the
 * trailing ones out of round, and the selection ring is a border drawn *inside* the circle —
 * selection never changes the element's footprint.
 */
@Composable
private fun PickerCircle(
    selected: Boolean,
    background: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit = {},
) {
    val ring = if (selected) {
        Modifier.border(width = 3.dp, color = MaterialTheme.colorScheme.onBackground, shape = CircleShape)
    } else {
        Modifier
    }
    Box(
        modifier = modifier
            .requiredSize(PICKER_CIRCLE_SIZE)
            .background(color = background, shape = CircleShape)
            .then(ring)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        content()
    }
}

private val PICKER_CIRCLE_SIZE = 36.dp
