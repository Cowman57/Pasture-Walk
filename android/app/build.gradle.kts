import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is configured from android/key.properties.
// That file is intentionally NOT in version control, so debug and profile
// builds must work without it. Only release builds require it (see below).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "nz.co.kalma.pasturewalk"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

defaultConfig {
        applicationId = "nz.co.kalma.pasturewalk"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
        }
        getByName("release") {
            signingConfigs.findByName("release")?.let { signingConfig = it }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

// Fail release builds with a helpful message when key.properties is absent,
// instead of silently producing an unsigned APK.
val checkReleaseKeystore by tasks.registering {
    doFirst {
        if (!hasReleaseKeystore) {
            throw GradleException(
                "Missing android/key.properties, which is required to sign release builds.\n" +
                    "Create android/key.properties with:\n" +
                    "  storePassword=<password>\n" +
                    "  keyPassword=<password>\n" +
                    "  keyAlias=pasturewalk\n" +
                    "  storeFile=../../pasturewalk.keystore\n" +
                    "Debug and profile builds do not need this file."
            )
        }
    }
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(checkReleaseKeystore)
}

flutter {
    source = "../.."
}
