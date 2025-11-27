plugins {
    alias(libs.plugins.kotlinJvm)
    alias(libs.plugins.ktor)
    alias(libs.plugins.kotlinSerialization)
    application
}

group = "cn.edu.ubaa"
version = "1.0.0"
application {
    mainClass.set("cn.edu.ubaa.ApplicationKt")

    val isDevelopment: Boolean = project.ext.has("development")
    applicationDefaultJvmArgs = listOf("-Dio.ktor.development=$isDevelopment")
}

dependencies {
    implementation(projects.shared)
    implementation(libs.logback)
    implementation("io.ktor:ktor-server-content-negotiation:2.3.4")

    // Ktor Server
    implementation(libs.ktor.serverCore)
    implementation(libs.ktor.serverNetty)
    implementation(libs.ktor.server.content.negotiation)
    implementation(libs.ktor.serialization.kotlinx.json)

    // Ktor Client
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.cio)
    implementation(libs.ktor.client.content.negotiation)

    // Kotlinx Serialization
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")

    // Jsoup
    implementation(libs.jsoup)

    // BouncyCastle for BYKC crypto
    implementation(libs.bouncycastle)

    // JWT
    implementation("io.ktor:ktor-server-auth-jvm:3.3.0")
    implementation("io.ktor:ktor-server-auth-jwt-jvm:3.3.0")
    implementation("com.auth0:java-jwt:4.4.0")

    // Test
    testImplementation(libs.ktor.serverTestHost)
    testImplementation(libs.kotlin.testJunit)
}
