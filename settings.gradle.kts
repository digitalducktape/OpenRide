pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // Aptabase telemetry SDK (#85) is only published on JitPack; nothing else may come from it.
        maven("https://www.jitpack.io") {
            content { includeGroup("com.github.aptabase") }
        }
    }
}

rootProject.name = "OpenRide"
include(":app")
