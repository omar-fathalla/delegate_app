import java.io.File

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.4.2") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")

// Patrol CLI's second Gradle invocation requests only `assemble*AndroidTest`, which
// prevents Flutter from registering `compileFlutterBuild*`. Append the matching app
// assemble task before :app is configured (Gradle Kotlin DSL forbids mutating
// startParameter from app/build.gradle.kts).
var patrolAssembleCompanionHookApplied = false
gradle.beforeProject {
    if (patrolAssembleCompanionHookApplied || project.path != ":app") return@beforeProject
    patrolAssembleCompanionHookApplied = true

    val requested = gradle.startParameter.taskNames
    if (requested.size != 1) return@beforeProject

    val taskPath = requested.first()
    val sole = taskPath.substringAfterLast(":")
    val match = Regex("^assemble(.+?)(Debug|Release|Profile)AndroidTest$").find(sole) ?: return@beforeProject

    val appAssemble = "assemble${match.groupValues[1]}${match.groupValues[2]}"
    if (requested.any { it.endsWith(appAssemble) }) return@beforeProject

    val prefix = taskPath.substringBeforeLast(":", missingDelimiterValue = "")
    val companion =
        when {
            prefix.isEmpty() -> ":app:$appAssemble"
            else -> "$prefix:$appAssemble"
        }
    gradle.startParameter.setTaskNames(requested + companion)
}
