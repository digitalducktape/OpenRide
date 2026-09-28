import java.io.ByteArrayOutputStream
import java.util.Properties
import javax.inject.Inject

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
}

android {
    namespace = "dev.digitalducktape.openride"
    compileSdk = 34

    defaultConfig {
        applicationId = "dev.digitalducktape.openride"
        // Android 10 (API 29). The reference tablet runs Android 11, but some Gen 2 bikes are
        // still on an Android 10 firmware and cannot be updated. Nothing in the app calls an
        // API above 29 — see the audit note in docs/DEVICE.md.
        minSdk = 29
        targetSdk = 34
        versionCode = 4
        versionName = "0.4.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // T3 / #3: toggle between MockBikeDataSource and the real (unverified-on-hardware)
        // Gen 2 sensor binding in AppContainer. Defaults to false (Mock) — flip only when
        // building for the actual bike tablet, see PelotonBikeDataSource's TODOs.
        buildConfigField("boolean", "USE_REAL_BIKE_SENSOR", "false")

        // T22 / #22: which release APK asset this build updates itself from. The self-updater
        // matches `openride-<infix>-<versionCode>.apk` in the latest GitHub release, so a mock
        // dev build never offers to install the real bike APK over itself. Only the `real`
        // asset is published, so the mock build simply finds nothing and stays quiet.
        buildConfigField("String", "UPDATE_APK_ASSET_INFIX", "\"mock\"")
    }

    buildTypes {
        // Mini-games (#32): the Godot engine ships one native library per ABI (~23 MB compressed
        // each). The bike tablets are arm64, so the builds that reach a bike carry only that;
        // the mock debug build also keeps x86_64 so it still runs games on an x86 emulator.
        debug {
            ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        }

        release {
            isMinifyEnabled = false
            ndk { abiFilters += "arm64-v8a" }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        // T3/#3: the real-sensor build. Identical to debug but flips USE_REAL_BIKE_SENSOR on
        // so AppContainer wires PelotonBikeDataSource (the live Gen 2 affernet binding) instead
        // of MockBikeDataSource. Installs alongside the mock build via a .real applicationId
        // suffix so both can coexist on the tablet. Build/install the real-sensor APK with:
        //     ./gradlew :app:installDebugReal
        create("debugReal") {
            initWith(getByName("debug"))
            applicationIdSuffix = ".real"
            versionNameSuffix = "-real"
            buildConfigField("boolean", "USE_REAL_BIKE_SENSOR", "true")
            // This is the build published to the bike, so it updates from the `real` asset.
            buildConfigField("String", "UPDATE_APK_ASSET_INFIX", "\"real\"")
            matchingFallbacks += "debug"
            // Bike-only build: arm64 alone (initWith copied debug's emulator ABI too).
            ndk {
                abiFilters.clear()
                abiFilters += "arm64-v8a"
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
        // T3/#3: the real Gen 2 sensor binding talks to Peloton's affernet system service
        // through a reconstructed AIDL interface (app/src/main/aidl/com/onepeloton/...),
        // so the AIDL toolchain generates the Stub/proxy with the correct transaction codes
        // and Parcel marshalling instead of hand-rolled Parcel.transact() guesses.
        aidl = true
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            isReturnDefaultValues = true
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
        // Mini-games (#32): store native libraries compressed (extracted at install) rather
        // than page-aligned and uncompressed, so the Godot engine adds ~23 MB to the APK the
        // self-updater downloads instead of ~69 MB.
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

/**
 * Mini-games (#32): exports the Godot project in `games/` to `games.pck`, which lands at the
 * root of the APK's assets where GameHostActivity loads it (`--main-pack res://games.pck`).
 * Needs the Godot editor whose version matches the `org.godotengine:godot` library: set
 * `GODOT_BIN` (or `godot.bin` in local.properties) to its binary. See docs/GAMES.md.
 */
abstract class ExportGamesPackTask @Inject constructor(
    private val execOperations: ExecOperations,
) : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val projectFiles: ConfigurableFileCollection

    @get:Internal
    abstract val projectDir: DirectoryProperty

    @get:Input
    @get:Optional
    abstract val godotBin: Property<String>

    /** The `org.godotengine:godot` version; the editor must be the same release. */
    @get:Input
    abstract val godotVersion: Property<String>

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun export() {
        val bin = godotBin.orNull?.takeIf { it.isNotBlank() }
            ?: throw GradleException("GODOT_BIN is not set. ${installHelp()}")
        if (!File(bin).canExecute()) {
            throw GradleException("GODOT_BIN=$bin is not an executable file. ${installHelp()}")
        }
        val version = godot(bin, "--version").trim()
        if (!version.startsWith(godotVersion.get())) {
            throw GradleException(
                "GODOT_BIN is Godot $version, but the app embeds Godot ${godotVersion.get()}; " +
                    "the pack must be exported by the same release. ${installHelp()}",
            )
        }
        val games = projectDir.get().asFile.path
        val pack = outputDir.get().asFile.apply { deleteRecursively(); mkdirs() }.resolve("games.pck")
        // Import first: a fresh checkout has no .godot/ import cache, and export needs it.
        godot(bin, "--headless", "--path", games, "--import")
        godot(bin, "--headless", "--path", games, "--export-pack", "Android", pack.path)
        if (!pack.isFile || pack.length() == 0L) {
            throw GradleException("Godot did not write $pack; see its output above.")
        }
    }

    private fun godot(vararg args: String): String {
        val out = ByteArrayOutputStream()
        execOperations.exec {
            commandLine(*args)
            standardOutput = out
        }
        return out.toString()
    }

    private fun installHelp() =
        "The mini-games need the Godot ${godotVersion.get()} editor to export games/: install it " +
            "(`brew install --cask godot`, or https://godotengine.org/download/archive/), then " +
            "`export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot` (or add " +
            "`godot.bin=...` to local.properties). See docs/GAMES.md."
}

val exportGamesPack = tasks.register<ExportGamesPackTask>("exportGamesPack") {
    group = "build"
    description = "Exports the Godot project in games/ to games.pck for the APK's assets."
    val games = rootProject.layout.projectDirectory.dir("games")
    projectDir.set(games)
    projectFiles.from(fileTree(games) { exclude(".godot/**", "tests/**") })
    val localGodotBin = rootProject.file("local.properties").takeIf { it.isFile }?.let { file ->
        Properties().apply { file.inputStream().use { load(it) } }.getProperty("godot.bin")
    }
    godotBin.set(providers.environmentVariable("GODOT_BIN").orElse(provider { localGodotBin }))
    godotVersion.set(libs.versions.godot.get())
}

// Every variant's assets include the pack, so asset merging runs exportGamesPack first.
androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(exportGamesPack, ExportGamesPackTask::outputDir)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.coil.compose)
    implementation(libs.androidx.exifinterface)

    // Mini-games (#32): the Godot engine as an Android library; GameHostActivity embeds it.
    // Must match the editor version that exports games/ (checked by exportGamesPack).
    implementation(libs.godot)
    implementation(libs.androidx.fragment)

    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)

    debugImplementation(libs.androidx.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.turbine)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.junit)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.androidx.room.testing)
    testImplementation(platform(libs.androidx.compose.bom))

    // Instrumented (on-device) tests. Used by SensorBindingInstrumentedTest to verify the
    // real Gen 2 affernet bind/decode pipeline on the physical bike tablet (T3/#3).
    androidTestImplementation(libs.androidx.test.junit)
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation("androidx.test:runner:1.6.1")
}
