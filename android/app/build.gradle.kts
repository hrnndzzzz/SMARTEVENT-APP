import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release signing key, read from android/key.properties.
//
// ## Why this file is not in the repository
//
// Two people building the same app on two laptops produced APKs that
// would not install over each other: `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
// Android refuses an update signed by a different key than the installed
// copy, and a debug keystore is generated per machine — so "release"
// builds were really signed by whoever built them.
//
// One key, shared privately between us, fixes that: every build updates
// every earlier one, on anybody's phone. It is a credential, so it lives
// outside the repository and `key.properties` names where. README says
// how to make it.
//
// Absent the file, this falls back to the debug key exactly as before,
// so a fresh clone still builds and `flutter run --release` still works.
// Two places, because this checkout is not the only one. Worktrees get
// their own android/ and key.properties is untracked, so a release built
// inside one would quietly fall back to the debug key and nobody would
// know until a phone refused the update. A copy in the home directory
// serves every checkout on the machine at once; the one beside the
// build still wins, so a single project can override it.
val keyPropertiesFile = listOf(
    rootProject.file("key.properties"),
    File(System.getProperty("user.home"), ".smartevent/key.properties"),
).firstOrNull { it.exists() }

val keyProperties = Properties().apply {
    keyPropertiesFile?.inputStream()?.use { load(it) }
}
val hasReleaseKey = keyProperties.getProperty("storeFile") != null

if (hasReleaseKey) {
    logger.lifecycle("SmartEvent: signing releases with the key named in $keyPropertiesFile")
} else {
    logger.lifecycle(
        "SmartEvent: no key.properties in android/ or ~/.smartevent/, so a " +
        "release build is signed with this machine's debug key. It will not " +
        "install over a build made anywhere else. See README before handing " +
        "the APK to anybody. This line only prints when Gradle configures " +
        "from cold, so to be certain, read the APK: " +
        "apksigner verify --print-certs <apk>"
    )
}

android {
    namespace = "com.lcup.smartevent.smartevent"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications needs it, for the phone notifications.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lcup.smartevent.smartevent"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                // Absolute paths come back unchanged; a relative one is read
                // against this checkout's android/, which is only right when
                // key.properties sits beside it. The README asks for absolute.
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The shared release key when this machine has it, and the
            // machine's own debug key when it does not. An unsigned
            // release build cannot be installed at all, so falling back
            // beats failing — but an APK anyone else will install has to
            // be built with the real key. A build that configures from
            // cold says which it used; a cached configuration does not,
            // so README is the thing to trust.
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKey) "release" else "debug"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
