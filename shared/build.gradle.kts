import org.jetbrains.kotlin.gradle.ExperimentalWasmDsl
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import com.codingfeline.buildkonfig.compiler.FieldSpec
import java.util.Properties

plugins {
    // 引入 KMP、Android 库、序列化及 BuildKonfig 插件
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.androidLibrary)
    alias(libs.plugins.kotlinSerialization)
    alias(libs.plugins.buildkonfig)
}

// 读取根目录下的 .env 文件以配置编译时常量
val env = Properties().apply {
    val envFile = rootProject.file(".env")
    if (envFile.exists()) {
        envFile.inputStream().use { load(it) }
    }
}

// BuildKonfig 配置：生成包含服务器地址和端口的 BuildKonfig 类
buildkonfig {
    packageName = "cn.edu.ubaa"
    objectName = "BuildKonfig"

    defaultConfigs {
        buildConfigField(FieldSpec.Type.STRING, "VERSION", project.property("project.version").toString())
        // 优先从环境变量获取 API 完整地址
        buildConfigField(FieldSpec.Type.STRING, "API_ENDPOINT", env.getProperty("API_ENDPOINT") ?: System.getenv("API_ENDPOINT") ?: "https://ubaa.mofrp.top")
    }
}

kotlin {
    // 配置 JDK 21 工具链
    jvmToolchain(21)
    
    // 配置 Android 目标
    androidTarget {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_21)
        }
    }
    
    // 配置 iOS 目标 (Arm64 及 模拟器)
    iosArm64()
    iosSimulatorArm64()
    
    // 配置 JVM (Desktop) 目标
    jvm()
    
    // 配置 JS 目标
    js {
        browser()
    }
    
    // 配置 Wasm JS 目标 (实验性)
    @OptIn(ExperimentalWasmDsl::class)
    wasmJs {
        browser()
    }
    
    sourceSets {
        // 公共源码集依赖
        commonMain.dependencies {
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.kotlinx.coroutinesCore)
            implementation(libs.ktor.client.core)
            implementation(libs.ktor.client.content.negotiation)
            implementation(libs.ktor.serialization.kotlinx.json)
            implementation(libs.ktor.client.logging)
            implementation(libs.ktor.client.auth)
            implementation(libs.multiplatform.settings)
            implementation(libs.multiplatform.settings.no.arg)
        }
        
        // 平台特定引擎实现
        androidMain.dependencies { implementation(libs.ktor.client.okhttp) }
        iosMain.dependencies { implementation(libs.ktor.client.darwin) }
        jvmMain.dependencies { implementation(libs.ktor.client.cio) }
        jsMain.dependencies { implementation(libs.ktor.client.js) }
        
        commonTest.dependencies {
            implementation(libs.kotlin.test)
            implementation(libs.ktor.client.mock)
            implementation(libs.kotlinx.coroutines.test)
            implementation(libs.multiplatform.settings.test)
        }
    }
}

android {
    namespace = "cn.edu.ubaa.shared"
    compileSdk = libs.versions.android.compileSdk.get().toInt()
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
    defaultConfig {
        minSdk = libs.versions.android.minSdk.get().toInt()
    }
}