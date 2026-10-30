import groovy.json.JsonSlurper
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 使用 Cargo.lock 实际选中的 Android 证书组件版本，不隐式更新依赖。
val verifierMetadata = providers.exec {
    commandLine("cargo", "metadata", "--locked", "--format-version", "1",
        "--filter-platform", "aarch64-linux-android", "--manifest-path", file("../../../../Cargo.toml").path)
}.standardOutput.asText.get()
val verifierPackage = ((JsonSlurper().parseText(verifierMetadata) as Map<*, *>)["packages"] as List<*>)
    .map { it as Map<*, *> }.single { it["name"] == "rustls-platform-verifier-android" }
repositories {
    // 0.2.0 起 AAR 由上游 Maven archive 分发，Cargo 包只负责版本同步。
    exclusiveContent {
        forRepository {
            maven {
                url = uri("https://github.com/rustls/rustls-platform-verifier/raw/maven-archive/android-release-support/maven/")
            }
        }
        filter { includeModule("org.rustls", "rustls-platform-verifier") }
    }
}

// 平台字段、旧 CI 字段、本机文件按整组选择，防止混用不同证书的密码。
val signingFields = mapOf(
    "storeFile" to "STORE_FILE",
    "storePassword" to "STORE_PASSWORD",
    "keyAlias" to "KEY_ALIAS",
    "keyPassword" to "KEY_PASSWORD",
)
fun signingOverrides(prefix: String) = signingFields.mapValues { (_, field) ->
    val variable = "${prefix}${field}"
    providers.gradleProperty(variable).orElse(providers.environmentVariable(variable)).orNull
}.takeIf { values -> values.values.any { it != null } }
val releaseSigningOverrides = signingOverrides("ANDROID_") ?: signingOverrides("UBAA_RELEASE_")
val signingPropertiesPath = providers.environmentVariable("ANDROID_SIGNING_PROPERTIES").orNull
val signingPropertiesFile = rootProject.file(signingPropertiesPath ?: "../../../.sign/android/signing.properties")
val releaseSigningValues = releaseSigningOverrides ?: run {
    check(signingPropertiesPath == null || signingPropertiesFile.isFile) {
        "ANDROID_SIGNING_PROPERTIES 指定的签名配置文件不存在"
    }
    val properties = Properties()
    if (signingPropertiesFile.isFile) {
        signingPropertiesFile.reader(Charsets.UTF_8).use { properties.load(it) }
    }
    signingFields.mapValues { (_, field) -> properties.getProperty("ANDROID_$field") }
}
val hasReleaseSigning = releaseSigningValues.values.all { !it.isNullOrBlank() }
val hasPartialReleaseSigning = releaseSigningValues.values.any { !it.isNullOrBlank() }
check(!hasPartialReleaseSigning || hasReleaseSigning) {
    "Android 签名必须同时提供 keystore 文件、store/key 密码和 key alias"
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
        applicationId = "cn.edu.ubaa"
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
                val path = releaseSigningValues.getValue("storeFile")!!
                storeFile = if (releaseSigningOverrides != null) file(path) else signingPropertiesFile.parentFile.resolve(path)
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
    implementation("org.rustls:rustls-platform-verifier:${verifierPackage["version"]}")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    // 与锁定Flutter integration_test原生运行时保持一致，避免跨配置强约束冲突。
    androidTestImplementation("androidx.test:runner:1.2.0")
}

flutter {
    source = "../.."
}
