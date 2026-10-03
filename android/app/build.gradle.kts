import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名配置（android/key.properties 不入版本库）
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.eets.e_ets_helper"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.eets.e_ets_helper"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 只保留 arm64 真机 + x86_64 模拟器：
        // 三个 ABI 各自带一份完整引擎（libmpv 视频库约 11-15MB/份），
        // 去掉 32 位 armeabi-v7a 省约 13MB（2026 年该类设备基本绝迹）
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    // 预编译 AAR 里的 so（libmpv 等）不受 abiFilters 约束，需打包期排除
    packaging {
        jniLibs {
            excludes += listOf("lib/armeabi-v7a/**")
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 有正式 keystore 时用正式签名，否则回退 debug 签名
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
    // Root 提权（libsu）
    implementation("com.github.topjohnwu.libsu:core:5.2.2")
    // Shizuku 提权（真机免 root）
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
}

flutter {
    source = "../.."
}
