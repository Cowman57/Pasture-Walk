import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties (android/key.properties)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (!keystorePropertiesFile.exists()) {
    throw GradleException("Missing key.properties for release signing.")
}
keystoreProperties.load(FileInputStream(keystorePropertiesFile))

android {
    namespace = "nz.co.kalma.pasturewalk"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        // Debug stays debug-signed automatically; no need to set anything here.
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "nz.co.kalma.pasturewalk"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 2
        versionName = "2.0.0"
    }
}

flutter {
    source = "../.."
}
