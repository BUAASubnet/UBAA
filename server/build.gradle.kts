plugins {
    alias(libs.plugins.kotlinJvm)
    alias(libs.plugins.ktor)
    alias(libs.plugins.kotlinSerialization)
    alias(libs.plugins.graalvm)
    application
}

import org.gradle.api.file.DuplicatesStrategy
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

group = "cn.edu.ubaa"
version = project.property("project.version").toString()
application {
    mainClass.set("cn.edu.ubaa.ApplicationKt")

    val isDevelopment: Boolean = project.ext.has("development")
    applicationDefaultJvmArgs = listOf("-Dio.ktor.development=$isDevelopment")
}

kotlin {
    compilerOptions {
        freeCompilerArgs.add("-Xmulti-platform")
        jvmTarget.set(JvmTarget.JVM_21)
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

tasks.withType<JavaExec> {
    workingDir = rootProject.projectDir
}

dependencies {
    implementation(project(":shared"))
    implementation(libs.logback)
    implementation(libs.dotenv.kotlin)

    // Ktor Server
    implementation(libs.ktor.serverCore)
    implementation(libs.ktor.serverNetty)
    implementation(libs.ktor.server.content.negotiation)
    implementation(libs.ktor.server.cors)
    implementation(libs.ktor.serialization.kotlinx.json)

    // Ktor Client
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.cio)
    implementation(libs.ktor.client.content.negotiation)

    // Kotlinx Serialization
    implementation(libs.kotlinx.serialization.json)

    // Jsoup
    implementation(libs.jsoup)

    // BouncyCastle for BYKC crypto
    implementation(libs.bouncycastle)

    // JWT
    implementation(libs.ktor.server.auth)
    implementation(libs.ktor.server.auth.jwt)
    implementation(libs.java.jwt)

    // SQLite for persistent sessions
    implementation(libs.sqlite.jdbc)

    // Test
    testImplementation(libs.ktor.serverTestHost)
    testImplementation(libs.kotlin.testJunit)
}

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
    metadataRepository {
        enabled.set(true)
    }
    agent {
        defaultMode.set("standard")
    }
}
