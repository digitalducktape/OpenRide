package dev.digitalducktape.openride.ui.profile

import dev.digitalducktape.openride.core.telemetry.ProfileCreated
import dev.digitalducktape.openride.core.telemetry.RecordingTelemetry
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.data.OpenRideDatabase
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.profile.WeightUnits
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProfileEditorViewModelTest {

    private lateinit var db: OpenRideDatabase
    private lateinit var profileRepository: ProfileRepository
    private lateinit var activeProfileHolder: ActiveProfileHolder
    private lateinit var viewModel: ProfileEditorViewModel

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        db = Room.inMemoryDatabaseBuilder(context, OpenRideDatabase::class.java).build()
        profileRepository = ProfileRepository(db.profileDao())
        activeProfileHolder = ActiveProfileHolder(context)
        // SharedPreferences persist across Robolectric tests in the same run; start clean so
        // "nothing was saved" assertions can't pass/fail on a leftover active id.
        activeProfileHolder.clear()
        viewModel = ProfileEditorViewModel(profileRepository, activeProfileHolder)
    }

    @After
    fun tearDown() {
        db.close()
    }

    // --- Create mode ------------------------------------------------------------------------

    @Test
    fun `blank name is rejected with an error and nothing is saved`() = runTest {
        viewModel.onNameChange("   ")

        val result = viewModel.save()

        assertTrue(!result)
        assertNotNull(viewModel.uiState.value.nameError)
        assertTrue(!viewModel.uiState.value.saved)
        assertNull(activeProfileHolder.activeProfileId.value)
    }

    @Test
    fun `empty name is rejected with an error`() = runTest {
        val result = viewModel.save()

        assertTrue(!result)
        assertNotNull(viewModel.uiState.value.nameError)
    }

    @Test
    fun `changing the name clears a previous error`() = runTest {
        viewModel.save() // triggers the error
        assertNotNull(viewModel.uiState.value.nameError)

        viewModel.onNameChange("Ed")

        assertNull(viewModel.uiState.value.nameError)
    }

    @Test
    fun `valid name is trimmed, saved, and set active`() = runTest {
        viewModel.onNameChange("  Ed  ")

        val result = viewModel.save()

        assertTrue(result)
        assertTrue(viewModel.uiState.value.saved)
        val activeId = activeProfileHolder.activeProfileId.value
        assertNotNull(activeId)
        val saved = profileRepository.getProfile(activeId!!)
        assertNotNull(saved)
        assertEquals("Ed", saved!!.name)
    }

    @Test
    fun `weight and FTP are optional and default to null when left blank`() = runTest {
        viewModel.onNameChange("Ed")

        viewModel.save()

        val saved = profileRepository.getProfile(activeProfileHolder.activeProfileId.value!!)
        assertNull(saved!!.weightKg)
        assertNull(saved.ftp)
    }

    @Test
    fun `a non-numeric weight is rejected with an error and nothing is saved`() = runTest {
        viewModel.onNameChange("Ed")
        viewModel.onWeightChange("not a number")

        val result = viewModel.save()

        assertTrue(!result)
        assertNotNull(viewModel.uiState.value.weightError)
        assertNull(activeProfileHolder.activeProfileId.value)
    }

    @Test
    fun `a zero or negative weight is rejected with an error`() = runTest {
        viewModel.onNameChange("Ed")
        viewModel.onWeightChange("0")

        val result = viewModel.save()

        assertTrue(!result)
        assertNotNull(viewModel.uiState.value.weightError)
    }

    @Test
    fun `a non-numeric FTP is rejected with an error and nothing is saved`() = runTest {
        viewModel.onNameChange("Ed")
        viewModel.onFtpChange("lots")

        val result = viewModel.save()

        assertTrue(!result)
        assertNotNull(viewModel.uiState.value.ftpError)
        assertNull(activeProfileHolder.activeProfileId.value)
    }

    @Test
    fun `weight is entered in lbs and stored as kg`() = runTest {
        viewModel.onNameChange("Ed")
        viewModel.onWeightChange("176.4")
        viewModel.onFtpChange("220")

        val result = viewModel.save()

        assertTrue(result)
        val saved = profileRepository.getProfile(activeProfileHolder.activeProfileId.value!!)
        assertEquals(WeightUnits.lbsToKg(176.4), saved!!.weightKg!!, 0.0001)
        // ~80 kg — checks the conversion direction, not just that the helper round-trips.
        assertEquals(80.0, saved.weightKg!!, 0.05)
        assertEquals(220, saved.ftp)
    }

    @Test
    fun `changing the weight clears a previous weight error`() = runTest {
        viewModel.onNameChange("Ed")
        viewModel.onWeightChange("bad")
        viewModel.save()
        assertNotNull(viewModel.uiState.value.weightError)

        viewModel.onWeightChange("170")

        assertNull(viewModel.uiState.value.weightError)
    }

    @Test
    fun `selecting an avatar color and emoji persists them on the saved profile`() = runTest {
        viewModel.onNameChange("Ed")
        viewModel.onAvatarColorChange(AvatarOptions.colors[2])
        viewModel.onAvatarEmojiChange(AvatarOptions.emojis[3])

        viewModel.save()

        val saved = profileRepository.getProfile(activeProfileHolder.activeProfileId.value!!)
        assertEquals(AvatarOptions.colors[2], saved!!.avatarColor)
        assertEquals(AvatarOptions.emojis[3], saved.avatarEmoji)
    }

    @Test
    fun `a captured photo path persists on the saved profile and can be removed`() = runTest {
        viewModel.onNameChange("Ed")
        viewModel.onPhotoCaptured("/data/avatars/a.jpg")

        viewModel.save()

        val saved = profileRepository.getProfile(activeProfileHolder.activeProfileId.value!!)
        assertEquals("/data/avatars/a.jpg", saved!!.avatarPhotoPath)

        viewModel.onPhotoRemoved()
        assertNull(viewModel.uiState.value.avatarPhotoPath)
    }

    // --- Edit mode --------------------------------------------------------------------------

    private suspend fun seedActiveProfile(): Long {
        val id = profileRepository.createProfile(
            Profile(
                name = "Ed",
                avatarEmoji = "🚴",
                avatarColor = AvatarOptions.colors[1],
                weightKg = 80.0,
                ftp = 220,
                pairedHrDeviceAddress = "AA:BB:CC:DD:EE:FF",
                avatarPhotoPath = "/data/avatars/old.jpg",
            ),
        )
        activeProfileHolder.setActiveProfile(id)
        return id
    }

    private fun editorForActiveProfile() =
        ProfileEditorViewModel(profileRepository, activeProfileHolder, editActiveProfile = true)

    @Test
    fun `loadForEdit prefills the form from the active profile, weight in lbs`() = runTest {
        seedActiveProfile()
        val editor = editorForActiveProfile()

        editor.loadForEdit()

        val state = editor.uiState.value
        assertEquals("Ed", state.name)
        assertEquals("🚴", state.avatarEmoji)
        assertEquals(AvatarOptions.colors[1], state.avatarColor)
        assertEquals("/data/avatars/old.jpg", state.avatarPhotoPath)
        assertEquals(WeightUnits.formatLbs(80.0), state.weightLbsInput)
        assertEquals("220", state.ftpInput)
    }

    @Test
    fun `loadForEdit only loads once so in-progress edits are not clobbered`() = runTest {
        seedActiveProfile()
        val editor = editorForActiveProfile()
        editor.loadForEdit()

        editor.onNameChange("Edward")
        editor.loadForEdit()

        assertEquals("Edward", editor.uiState.value.name)
    }

    @Test
    fun `saving in edit mode updates the profile in place and preserves the HR pairing`() = runTest {
        val id = seedActiveProfile()
        val editor = editorForActiveProfile()
        editor.loadForEdit()

        editor.onNameChange("Edward")
        editor.onWeightChange("165")
        editor.onFtpChange("230")
        val result = editor.save()

        assertTrue(result)
        val updated = profileRepository.getProfile(id)
        assertEquals("Edward", updated!!.name)
        assertEquals(WeightUnits.lbsToKg(165.0), updated.weightKg!!, 0.0001)
        assertEquals(230, updated.ftp)
        // Fields the form doesn't cover survive an edit.
        assertEquals("AA:BB:CC:DD:EE:FF", updated.pairedHrDeviceAddress)
        assertEquals(id, activeProfileHolder.activeProfileId.value)
    }

    @Test
    fun `saving in edit mode can clear the weight by blanking the field`() = runTest {
        val id = seedActiveProfile()
        val editor = editorForActiveProfile()
        editor.loadForEdit()

        editor.onWeightChange("")
        editor.save()

        assertNull(profileRepository.getProfile(id)!!.weightKg)
    }

    @Test
    fun `saving a new profile reports profile_created without a photo`() = runTest {
        val telemetry = RecordingTelemetry()
        val vm = ProfileEditorViewModel(profileRepository, activeProfileHolder, telemetry = telemetry)
        vm.onNameChange("Ed")

        vm.save()

        assertEquals(listOf(ProfileCreated(hasPhoto = false)), telemetry.events)
    }

    @Test
    fun `saving a new profile with a photo reports has_photo`() = runTest {
        val telemetry = RecordingTelemetry()
        val vm = ProfileEditorViewModel(profileRepository, activeProfileHolder, telemetry = telemetry)
        vm.onNameChange("Ed")
        vm.onPhotoCaptured("/data/avatars/a.jpg")

        vm.save()

        assertEquals(listOf(ProfileCreated(hasPhoto = true)), telemetry.events)
    }

    @Test
    fun `an invalid new profile reports nothing`() = runTest {
        val telemetry = RecordingTelemetry()
        val vm = ProfileEditorViewModel(profileRepository, activeProfileHolder, telemetry = telemetry)

        vm.save()

        assertEquals(emptyList<Any>(), telemetry.events)
    }

    @Test
    fun `editing a profile reports nothing`() = runTest {
        val telemetry = RecordingTelemetry()
        seedActiveProfile()
        val vm = ProfileEditorViewModel(profileRepository, activeProfileHolder, editActiveProfile = true, telemetry = telemetry)
        vm.loadForEdit()
        vm.onNameChange("Renamed")

        assertTrue(vm.save())

        assertEquals(emptyList<Any>(), telemetry.events)
    }
}
