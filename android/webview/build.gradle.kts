plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.splayer.next.web"
    compileSdk = 35

    defaultConfig {
        // 与原生版相同的 applicationId，安装时直接覆盖升级
        applicationId = "com.splayer.next"
        minSdk = 26
        targetSdk = 35
        versionCode = 107
        versionName = "1.1.6"
    }

    // 固定签名：早期每个 CI runner 都会随机生成 debug keystore，导致新包无法覆盖安装（签名冲突）
    signingConfigs {
        create("shared") {
            storeFile = file("splayer-debug.jks")
            storePassword = "splayer2026"
            keyAlias = "splayer"
            keyPassword = "splayer2026"
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("shared")
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("shared")
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        resources.excludes += "META-INF/*"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // Media3 播放内核与系统媒体会话（对应原 Rust 音频引擎的 Android 兼容层）
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-session:1.5.1")
}
