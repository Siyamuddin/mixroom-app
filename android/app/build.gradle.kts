import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
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
    assetPacks += listOf(
        ":assetpacks:instruments",
        ":assetpacks:sample_packs",
    )

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
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
            abiFilters.clear()
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))
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

val isBundleReleaseBuild =
    gradle.startParameter.taskNames.any { taskName ->
        val normalized = taskName.lowercase()
        normalized.contains("bundle") && normalized.contains("release")
    }

if (isBundleReleaseBuild) {
    tasks.matching { task ->
        (
            task.name.contains("Release") &&
                task.name.startsWith("merge") &&
                task.name.endsWith("Assets")
        ) ||
            task.name == "copyFlutterAssetsRelease"
    }.configureEach {
        doLast {
            this.outputs.files.files
                .filter { it.isDirectory }
                .forEach { outDir: File ->
                    delete(File(outDir, "assets/instruments"))
                    delete(File(outDir, "assets/sample_packs"))
                    delete(File(outDir, "flutter_assets/assets/instruments"))
                    delete(File(outDir, "flutter_assets/assets/sample_packs"))
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.activity:activity-ktx:1.9.0")
    // implementation(project(":ffmpeg_kit_flutter_full_gpl"))
    // ... your other deps
    implementation("com.arthenica:smart-exception-java:0.2.1")
    // Its required common module
    implementation("com.arthenica:smart-exception-common:0.2.1")
}


flutter {
    source = "../.."
}
