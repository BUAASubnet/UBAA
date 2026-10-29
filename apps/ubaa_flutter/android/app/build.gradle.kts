import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 使用Cargo.lock实际选中的Android证书组件，验证过程不隐式更新依赖。
val verifierMetadata = providers.exec {
    commandLine("cargo", "metadata", "--locked", "--format-version", "1",
        "--filter-platform", "aarch64-linux-android", "--manifest-path", file("../../../../Cargo.toml").path)
}.standardOutput.asText.get()
val verifierPackage = ((JsonSlurper().parseText(verifierMetadata) as Map<*, *>)["packages"] as List<*>)
    .map { it as Map<*, *> }.single { it["name"] == "rustls-platform-verifier-android" }
repositories {
    maven { url = uri(File(file(verifierPackage["manifest_path"] as String).parentFile, "maven")) }
}

// Release 证书只从 Gradle 属性或环境变量读取，仓库不保存密钥材料。
// 未配置完整证书时生成无签名 release；debug 构建继续使用 Flutter/Android 默认配置。
val releaseSigningValues = mapOf(
    "storeFile" to "UBAA_RELEASE_STORE_FILE",
    "storePassword" to "UBAA_RELEASE_STORE_PASSWORD",
    "keyAlias" to "UBAA_RELEASE_KEY_ALIAS",
    "keyPassword" to "UBAA_RELEASE_KEY_PASSWORD",
).mapValues { (_, variable) ->
    providers.gradleProperty(variable).orElse(providers.environmentVariable(variable)).orNull
}
val hasReleaseSigning = releaseSigningValues.values.all { !it.isNullOrBlank() }
val hasPartialReleaseSigning = releaseSigningValues.values.any { !it.isNullOrBlank() }
check(!hasPartialReleaseSigning || hasReleaseSigning) {
    "UBAA_RELEASE_* 必须同时提供 keystore 文件、store/key 密码和 key alias"
}

android {
    namespace = "cn.edu.ubaa.ubaa_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cn.edu.ubaa.ubaa_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasReleaseSigning) {
        signingConfigs {
            create("release") {
                storeFile = file(releaseSigningValues.getValue("storeFile")!!)
                storePassword = releaseSigningValues.getValue("storePassword")
                keyAlias = releaseSigningValues.getValue("keyAlias")
                keyPassword = releaseSigningValues.getValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // 没有受控证书时保持无签名 release，禁止退回 debug 密钥。
                signingConfig = null
            }
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    implementation("rustls:rustls-platform-verifier:${verifierPackage["version"]}")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    // 与锁定Flutter integration_test原生运行时保持一致，避免跨配置强约束冲突。
    androidTestImplementation("androidx.test:runner:1.2.0")
}

flutter {
    source = "../.."
}
