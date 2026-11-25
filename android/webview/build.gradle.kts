plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// 版本策略：versionName 为唯一语义版本源；versionCode = major*10000+minor*100+patch，
// 保证版本号单调递增，Android 才会接受覆盖安装。CI 直接读取 appVersionName 生成 tag 与 APK 名。
val appVersionName = "1.1.7"

fun versionCodeOf(name: String): Int {
    val parts = name.split('.')
    return (parts.getOrNull(0)?.toIntOrNull() ?: 0) * 10000 +
        (parts.getOrNull(1)?.toIntOrNull() ?: 0) * 100 +
        (parts.getOrNull(2)?.toIntOrNull() ?: 0)
}

// Release 签名：优先本地 keystore（不入库）；CI 通过环境变量注入已解码的 keystore。
val localKeystore = file("splayer-debug.jks")
val envKeystore = System.getenv("SIGNING_KEYSTORE_PATH")?.let { file(it) }
val signingFile = when {
    localKeystore.exists() -> localKeystore
    envKeystore?.exists() == true -> envKeystore
    else -> null
}

android {
    namespace = "com.splayer.next.web"
    compileSdk = 35

    defaultConfig {
        // 与原生版相同的 applicationId，安装时直接覆盖升级
        applicationId = "com.splayer.next"
        minSdk = 26
        targetSdk = 35
        versionName = appVersionName
        versionCode = versionCodeOf(appVersionName)
    }

    buildFeatures {
        // BuildConfig.VERSION_NAME / VERSION_CODE 供更新检查比较版本
        buildConfig = true
    }

    // 固定签名：早期每个 CI runner 都会随机生成 debug keystore，导致新包无法覆盖安装（签名冲突）
    signingConfigs {
        if (signingFile != null) {
            create("shared") {
                storeFile = signingFile
                storePassword = System.getenv("SIGNING_STORE_PASSWORD") ?: "splayer2026"
                keyAlias = System.getenv("SIGNING_KEY_ALIAS") ?: "splayer"
                keyPassword = System.getenv("SIGNING_KEY_PASSWORD") ?: "splayer2026"
            }
        }
    }

    buildTypes {
        val shared = signingConfigs.findByName("shared")
        getByName("debug") {
            if (shared != null) signingConfig = shared
        }
        getByName("release") {
            // 无 keystore 时不签名（仍可产出 unsigned APK），避免 CI 因缺文件直接失败
            if (shared != null) signingConfig = shared
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
