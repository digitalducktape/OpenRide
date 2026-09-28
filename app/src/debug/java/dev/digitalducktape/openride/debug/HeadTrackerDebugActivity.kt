package dev.digitalducktape.openride.debug

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import dev.digitalducktape.openride.AppContainer
import dev.digitalducktape.openride.core.camera.CameraXFaceSource
import dev.digitalducktape.openride.core.camera.DefaultHeadTracker
import dev.digitalducktape.openride.core.camera.HeadTrackerState
import dev.digitalducktape.openride.core.camera.InMemoryHeadCalibrationStore
import dev.digitalducktape.openride.core.camera.TrackerMode
import java.io.File
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Debug builds only: exercises the production head tracker on the bike and records fixtures.
 * Not reachable from the app's UI. Launch with
 *
 *     adb shell am start -n <pkg>/dev.digitalducktape.openride.debug.HeadTrackerDebugActivity \
 *         [--es mode lean_x|lean_2d|lean_stand] [--ez calibrate true] [--ez record true]
 *
 * "Record protocol" prompts the rider through centre, leans, sprint, knob glance, stand/sit and
 * lean in/back, writing a numbers-only CSV fixture to `files/headtracker/`. A once-a-second
 * summary goes to logcat under tag `HeadTracker` (`adb shell setprop log.tag.HeadTracker VERBOSE`).
 */
class HeadTrackerDebugActivity : ComponentActivity() {

    private data class Step(val slug: String, val prompt: String, val seconds: Int)

    private val protocol: List<Step> = buildList {
        add(Step("setup", "Sit, pedal easy, look at the screen", 10))
        add(Step("easy_centre", "Easy, CENTRE", 10))
        repeat(2) {
            add(Step("lean_left", "Lean LEFT", 5)); add(Step("return_centre", "CENTRE", 5))
            add(Step("lean_right", "Lean RIGHT", 5)); add(Step("return_centre", "CENTRE", 5))
        }
        add(Step("sprint_centre", "SPRINT 100+ rpm, stay CENTRE", 20))
        add(Step("sprint_lean_left", "SPRINT + lean LEFT", 5)); add(Step("sprint_return_centre", "SPRINT, CENTRE", 5))
        add(Step("sprint_lean_right", "SPRINT + lean RIGHT", 5)); add(Step("sprint_return_centre", "SPRINT, CENTRE", 5))
        add(Step("easy_centre", "Easy, CENTRE", 10))
        add(Step("knob_glance", "Look DOWN at the knob, turn it", 8)); add(Step("easy_centre", "Easy, CENTRE", 7))
        repeat(2) { add(Step("stand", "STAND UP, keep pedalling", 10)); add(Step("sit", "SIT, keep pedalling", 10)) }
        repeat(2) {
            add(Step("lean_in", "Lean IN towards the screen", 5)); add(Step("return_centre", "CENTRE", 5))
            add(Step("sit_back", "SIT BACK", 5)); add(Step("return_centre", "CENTRE", 5))
        }
    }

    private val container by lazy { AppContainer(applicationContext) }
    private val cameraSource by lazy { CameraXFaceSource(applicationContext) }
    @Volatile private var logger: HeadFixtureLogger? = null
    private val prompt = MutableStateFlow("Idle")
    private var protocolJob: Job? = null
    private val tone by lazy { ToneGenerator(AudioManager.STREAM_MUSIC, 90) }

    private val tracker by lazy {
        DefaultHeadTracker(
            faceSource = RecordingFaceSource(cameraSource) { t, face -> logger?.record(t, face) },
            calibrationStore = InMemoryHeadCalibrationStore(),
            activeProfileId = MutableStateFlow(null),
            hasCameraPermission = ::hasCameraPermission,
            scope = lifecycleScope,
        )
    }

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { tracker.refreshPermission() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (!hasCameraPermission()) permissionLauncher.launch(Manifest.permission.CAMERA)

        val mode = intent.getStringExtra("mode")?.let(TrackerMode::fromWireName) ?: TrackerMode.LEAN_X
        if (intent.getBooleanExtra("calibrate", false)) tracker.calibrate(mode, force = true) else tracker.setMode(mode)
        if (intent.getBooleanExtra("record", false)) startProtocol()

        lifecycleScope.launch {
            while (isActive) {
                delay(1_000)
                val s = tracker.state.value
                val stats = cameraSource.stats.value
                Log.i(
                    CameraXFaceSource.TAG,
                    "mode=${s.mode.wireName} state=${s.trackerState} lean=%.2f depth=%.2f standing=${s.standing} ".format(s.leanX, s.leanDepth) +
                        "cal=${s.calibration?.let { "${it.step.wireName}:%.2f#${it.attempt}${it.retryReason?.let { r -> "/" + r.wireName } ?: ""}".format(it.fraction) }} " +
                        "unavailable=${s.unavailable?.wireName} fps=%.1f detect=%.1fms rpm=${container.bikeDataSource.metrics.value.cadenceRpm} step=${prompt.value}".format(stats.fps, stats.detectMs),
                )
                logger?.flush()
            }
        }

        setContent { DebugScreen() }
    }

    override fun onDestroy() {
        super.onDestroy()
        tracker.setMode(TrackerMode.OFF)
        stopRecording()
    }

    private fun hasCameraPermission() =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    private fun startProtocol() {
        protocolJob?.cancel()
        stopRecording()
        val newLogger = HeadFixtureLogger(File(filesDir, "headtracker")) { container.bikeDataSource.metrics.value.cadenceRpm }
        logger = newLogger
        Log.i(CameraXFaceSource.TAG, "recording fixture to ${newLogger.file.absolutePath}")
        protocolJob = lifecycleScope.launch {
            for (step in protocol) {
                newLogger.step = step.slug
                prompt.value = step.prompt
                tone.startTone(ToneGenerator.TONE_PROP_BEEP, 150)
                delay(step.seconds * 1_000L)
            }
            prompt.value = "Done — fixture saved"
            stopRecording()
        }
    }

    private fun stopRecording() {
        protocolJob?.cancel()
        logger?.let {
            logger = null
            it.flush()
            it.close()
            Log.i(CameraXFaceSource.TAG, "fixture saved: ${it.file.absolutePath}")
        }
    }

    @Composable
    private fun DebugScreen() {
        val state by tracker.state.collectAsState()
        val stats by cameraSource.stats.collectAsState()
        val step by prompt.collectAsState()
        Column(
            Modifier.fillMaxSize().background(Color.Black).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(step, color = Color.Yellow, fontSize = 44.sp, fontWeight = FontWeight.Bold)
            Bar("lean x", state.leanX)
            Bar("depth", state.leanDepth)
            Text(summary(state, stats), color = Color.White, fontSize = 20.sp, fontFamily = FontFamily.Monospace)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (mode in TrackerMode.entries) {
                    OutlinedButton(onClick = { tracker.setMode(mode) }) { Text(mode.wireName) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = { tracker.calibrate(currentOrDefault(state)) }) { Text("Calibrate") }
                Button(onClick = { tracker.calibrate(currentOrDefault(state), force = true) }) { Text("Full calibrate") }
                Button(onClick = ::startProtocol) { Text("Record protocol") }
                OutlinedButton(onClick = { stopRecording(); prompt.value = "Idle" }) { Text("Stop recording") }
            }
        }
    }

    private fun currentOrDefault(state: HeadTrackerState) =
        if (state.mode == TrackerMode.OFF) TrackerMode.LEAN_X else state.mode

    private fun summary(s: HeadTrackerState, stats: CameraXFaceSource.Stats): String = buildString {
        appendLine("mode ${s.mode.wireName}   state ${s.trackerState} (${s.trackerState.code})   standing ${s.standing}")
        s.calibration?.let {
            appendLine("calibrating ${it.step.wireName} ${it.stepIndex + 1}/${it.stepCount}  %.0f%%  attempt ${it.attempt}  ${it.retryReason?.wireName ?: ""}".format(it.fraction * 100))
        }
        s.unavailable?.let { appendLine("unavailable: ${it.wireName}") }
        append("analysis %.1f fps   detect %.1f ms/frame   recording ${logger != null}".format(stats.fps, stats.detectMs))
    }

    @Composable
    private fun Bar(label: String, value: Double) {
        val v = value.toFloat().coerceIn(-1f, 1f)
        Box(Modifier.fillMaxWidth().height(44.dp).background(Color.DarkGray)) {
            Box(
                Modifier.fillMaxWidth(0.5f + v / 2f).height(44.dp)
                    .background(if (v == 0f) Color.Gray else Color(0xFF3DDC84)),
            )
            Text("$label %.2f".format(value), color = Color.White, fontSize = 22.sp, modifier = Modifier.align(Alignment.Center))
        }
    }
}
