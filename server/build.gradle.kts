import org.gradle.api.file.DuplicatesStrategy
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    // 引入 Kotlin JVM, Ktor, 序列化及 GraalVM 原生镜像插件
    alias(libs.plugins.kotlinJvm)
    alias(libs.plugins.ktor)
    alias(libs.plugins.kotlinSerialization)
    alias(libs.plugins.graalvm)
    application
}

group = "cn.edu.ubaa"
version = project.property("project.version").toString()

application {
    mainClass.set("cn.edu.ubaa.ApplicationKt")
    val isDevelopment: Boolean = project.ext.has("development")
    applicationDefaultJvmArgs = listOf("-Dio.ktor.development=$isDevelopment")
}

kotlin {
    jvmToolchain(21)
    compilerOptions {
        freeCompilerArgs.add("-Xmulti-platform")
    }
    sourceSets {
        val main by getting {
            kotlin.srcDir("src/main/kotlin")
            resources.srcDir("src/main/resources")
        }
    }
}

tasks.processResources {
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
}

dependencies {
    // 依赖 shared 模块获取 DTO 和基础逻辑
    implementation(project(":shared"))
    implementation(libs.logback)
    implementation(libs.dotenv.kotlin)

    // Ktor Server 核心及插件
    implementation(libs.ktor.serverCore)
    implementation(libs.ktor.serverNetty)
    implementation(libs.ktor.server.call.logging)
    implementation(libs.ktor.server.content.negotiation)
    implementation(libs.ktor.server.cors)
    implementation(libs.ktor.server.metrics.micrometer)
    implementation(libs.micrometer.registry.prometheus)
    implementation(libs.ktor.serialization.kotlinx.json)

    // 内部抓取使用的 Ktor Client
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.cio)
    implementation(libs.ktor.client.content.negotiation)

    // 其他实用工具库
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.jsoup) // HTML 抓取
    implementation(libs.bouncycastle) // BYKC 加密支持
    implementation(libs.ktor.server.auth)
    implementation(libs.ktor.server.auth.jwt) // JWT 认证
    implementation(libs.java.jwt)
    implementation(libs.sqlite.jdbc) // 会话持久化数据库

    testImplementation(libs.ktor.serverTestHost)
    testImplementation(libs.kotlin.testJunit)
}

// GraalVM 配置：生成高性能的原生可执行文件
graalvmNative {
    binaries {
        named("main") {
            imageName.set("ubaa-server")
            mainClass.set("cn.edu.ubaa.ApplicationKt")
            buildArgs.add("--no-fallback")
            if (project.hasProperty("static-musl")) {
                buildArgs.add("--static")
                buildArgs.add("--libc=musl")
            }
        }
    }
    metadataRepository { enabled.set(true) }
    agent { defaultMode.set("standard") }
}