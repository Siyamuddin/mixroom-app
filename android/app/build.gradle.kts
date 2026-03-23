import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    FileInputStream(localPropertiesFile).use { localProperties.load(it) }
}

val flutterVersionCode =
    (localProperties.getProperty("flutter.versionCode") ?: "1").toInt()
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0.0"
val kakaoNativeAppKey =
    localProperties.getProperty("kakao.nativeAppKey")
        ?: "a70f53b706f3290cd916615b82b3feea"

android {
    namespace = "com.mixroom.mixroomapp"
    compileSdk = 36 // Ensure this matches the latest Flutter-supported version
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.mixroom.mixroomapp"
        minSdk = 29
        targetSdk = 36
        versionCode = flutterVersionCode
        versionName = flutterVersionName
        multiDexEnabled = true
        
        // Add FFmpeg config
        ndk {
            // abiFilters.addAll(setOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")) // Corrected line 31
            // abiFilters = "arm64-v8a" // Corrected line 31
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }

        // for OAuth (youtube upload)
        manifestPlaceholders["appAuthRedirectScheme"] = "com.mixroom.mixroomapp"
        manifestPlaceholders["kakaoNativeAppKey"] = kakaoNativeAppKey
        manifestPlaceholders["kakaoCustomScheme"] =
            if (kakaoNativeAppKey.isBlank()) "kakao" else "kakao$kakaoNativeAppKey"
    }

    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
        }
        pickFirst("lib/**/libc++_shared.so")
    }

    val keystoreProperties = Properties()
    val keystoreFile = rootProject.file("key.properties")
    if (keystoreFile.exists()) {
        keystoreProperties.load(FileInputStream(keystoreFile))
    }

   signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as? String
            keyPassword = keystoreProperties["keyPassword"] as? String
            storeFile = file(keystoreProperties["storeFile"] as? String ?: "my-release-key.jks")
            storePassword = keystoreProperties["storePassword"] as? String
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isShrinkResources = true // Enable for release
            isMinifyEnabled = true   // Enable for release
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        getByName("debug") {
            // Debug build type configuration
        }
    }
}

dependencies {
    // implementation(project(":ffmpeg_kit_flutter_full_gpl"))
    // ... your other deps
    implementation("com.arthenica:smart-exception-java:0.2.1")
    // Its required common module
    implementation("com.arthenica:smart-exception-common:0.2.1")
}


flutter {
    source = "../.."
}
