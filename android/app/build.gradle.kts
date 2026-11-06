plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// tashil-dev "Dev Maps Android key" — set locally (see android/README_MAPS_KEYS.md); never commit.
fun loadDevMapsAndroidKey(): String? {
    System.getenv("DEV_MAPS_ANDROID_KEY")?.trim()?.takeIf { it.isNotEmpty() }?.let {
        return it
    }
    val localPropertiesFile = rootProject.file("local.properties")
    if (!localPropertiesFile.exists()) return null
    val p = Properties()
    localPropertiesFile.inputStream().use { p.load(it) }
    return p.getProperty("devMapsAndroidKey")?.trim()?.takeIf { it.isNotEmpty() }
}

android {
    namespace = "com.tashil.delegate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "21"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tashil.delegate"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Production Maps key (must remain byte-for-byte for prod/store builds).
        manifestPlaceholders["GOOGLE_MAPS_ANDROID_API_KEY"] =
            "AIzaSyDQkxCw7YSM1-qUxcjT9oWA9DNZyp3fsOk"
    }

    // Always pass --flavor on Android: `flutter build apk --flavor prod` or
    // `--flavor dev --dart-define=ENV=dev`. (No pubspec default-flavor: it
    // would also apply to iOS, which has no flavor schemes.)
    // "prod" is the default Gradle variant and keeps the store applicationId and the
    // production google-services.json (android/app/google-services.json).
    // "dev" installs beside prod and uses android/app/src/dev/google-services.json
    // (tashil-dev). Build with: flutter build apk --flavor dev --dart-define=ENV=dev
    flavorDimensions += "env"
    productFlavors {
        create("prod") {
            dimension = "env"
            isDefault = true
            manifestPlaceholders["appLabel"] = "Tashil Employee"
        }
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            manifestPlaceholders["appLabel"] = "Tashil Dev"
            manifestPlaceholders["GOOGLE_MAPS_ANDROID_API_KEY"] =
                loadDevMapsAndroidKey().orEmpty()
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
        getByName("debug") {
            val uploadKeystoreFile = file("upload-keystore.jks")
            if (uploadKeystoreFile.exists()) {
                storeFile = uploadKeystoreFile
                storePassword = "android"
                keyAlias = "upload"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

// The flavor and the Dart ENV must agree, otherwise a "Tashil Dev" package
// could talk to prod Firestore (or the store package to tashil-dev).
// Flutter passes --dart-define values as base64 in the "dart-defines" property.
val dartEnv: String = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.filter { it.isNotBlank() }
    ?.map { String(Base64.getDecoder().decode(it)) }
    ?.firstOrNull { it.startsWith("ENV=") }
    ?.removePrefix("ENV=")
    ?: "prod"

gradle.taskGraph.whenReady {
    val names = allTasks.filter { it.project == project }.map { it.name }
    val buildsDev = names.any { Regex("Dev(Debug|Profile|Release)").containsMatchIn(it) }
    val buildsProd = names.any { Regex("Prod(Debug|Profile|Release)").containsMatchIn(it) }
    if (buildsDev && dartEnv != "dev") {
        throw GradleException("Flavor 'dev' requires --dart-define=ENV=dev (got ENV=$dartEnv).")
    }
    if (buildsProd && dartEnv != "prod") {
        throw GradleException("Flavor 'prod' requires ENV=prod or no ENV define (got ENV=$dartEnv).")
    }
    if (buildsDev && loadDevMapsAndroidKey().isNullOrEmpty()) {
        throw GradleException(
            "Flavor 'dev' requires the tashil-dev Android Maps API key. " +
                "Set devMapsAndroidKey in android/local.properties (gitignored) or " +
                "DEV_MAPS_ANDROID_KEY in the environment. See android/README_MAPS_KEYS.md."
        )
    }
}
