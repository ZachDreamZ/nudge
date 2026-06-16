plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nudge.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Unique application identifier published to the Play Store.
        applicationId = "com.nudge.app"
        // WorkManager + notification APIs require API 23+; POST_NOTIFICATIONS
        // is API 33+. We pin minSdk to 23 for predictable runtime behaviour.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Replace this with a real release signingConfig before publishing
            // to the Play Store. See https://developer.android.com/studio/publish/app-signing.
            signingConfig = signingConfigs.getByName("debug")
            // R8 / ProGuard keep rules so reflection-based libraries
            // (androidx.work, androidx.startup, google_fonts) survive
            // minification.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
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
    implementation("androidx.work:work-runtime:2.9.1")
    implementation("androidx.core:core:1.13.1")
    implementation("androidx.annotation:annotation:1.8.2")
}
