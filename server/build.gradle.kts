import org.gradle.api.file.DuplicatesStrategy
import org.gradle.api.tasks.testing.Test
import org.gradle.jvm.tasks.Jar

plugins {
  // 引入 Kotlin JVM, Ktor, 序列化及 GraalVM 原生镜像插件
  alias(libs.plugins.kotlinJvm)
  alias(libs.plugins.ktor)
  alias(libs.plugins.kotlinSerialization)
  application
}

group = "cn.edu.ubaa"

version = project.property("project.version").toString()

val serverVersion = version.toString()

application {
  mainClass.set("cn.edu.ubaa.ApplicationKt")
  val isDevelopment: Boolean = project.ext.has("development")
  applicationDefaultJvmArgs =
      listOf(
          "-Dio.ktor.development=$isDevelopment",
          "-Dubaa.server.version=$serverVersion",
          "-Djava.awt.headless=true",
      )
}

kotlin {
  jvmToolchain(21)
  compilerOptions { freeCompilerArgs.add("-Xmulti-platform") }
  sourceSets {
    val main by getting {
      kotlin.srcDir("src/main/kotlin")
      resources.srcDir("src/main/resources")
    }
  }
}

tasks.processResources { duplicatesStrategy = DuplicatesStrategy.EXCLUDE }

tasks.withType<Jar>().configureEach {
  manifest.attributes["Implementation-Version"] = serverVersion
}

tasks.withType<Test>().configureEach { systemProperty("ubaa.server.version", serverVersion) }

dependencies {
  // 依赖 shared 模块获取 DTO 和基础逻辑
  implementation(project(":shared"))
  implementation(libs.logback)
  implementation(libs.dotenv.kotlin)

  // Ktor Server 核心及插件
  implementation(libs.ktor.serverCore)
  implementation(libs.ktor.serverNetty)
  implementation(libs.ktor.server.call.logging)
  implementation(libs.ktor.server.call.id)
  implementation(libs.ktor.server.content.negotiation)
  implementation(libs.ktor.server.cors)
  implementation(libs.ktor.server.forwarded.header)
  implementation(libs.ktor.server.status.pages)
  implementation(libs.ktor.server.metrics.micrometer)
  implementation(libs.micrometer.registry.prometheus)
  implementation(libs.ktor.serialization.kotlinx.json)

  // 内部抓取使用的 Ktor Client
  implementation(libs.ktor.client.core)
  implementation(libs.ktor.client.cio)
  implementation(libs.ktor.client.content.negotiation)

  // 其他实用工具库
  implementation(libs.kotlinx.datetime)
  implementation(libs.kotlinx.serialization.json)
  implementation(libs.jsoup) // HTML 抓取
  implementation(libs.bouncycastle) // BYKC 加密支持
  implementation(libs.ktor.server.auth)
  implementation(libs.ktor.server.auth.jwt) // JWT 认证
  implementation(libs.java.jwt)
  implementation(libs.redis.kotlin) // Redis 缓存支持

  testImplementation(libs.ktor.serverTestHost)
  testImplementation(libs.ktor.client.mock)
  testImplementation(libs.kotlin.testJunit)
}
