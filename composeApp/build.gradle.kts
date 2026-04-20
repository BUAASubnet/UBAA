import org.jetbrains.compose.desktop.application.dsl.TargetFormat
import org.jetbrains.kotlin.gradle.ExperimentalWasmDsl

plugins {
  alias(libs.plugins.kotlinMultiplatform)
  // Changed from androidApplication to androidKotlinMultiplatformLibrary
  alias(libs.plugins.androidKotlinMultiplatformLibrary)
  alias(libs.plugins.composeMultiplatform)
  alias(libs.plugins.composeCompiler)
  // alias(libs.plugins.composeHotReload)
}

val composeVersion = libs.versions.composeMultiplatform.get()
val composeMaterial3Version = "1.9.0"
val composeMaterialIconsExtendedVersion = "1.7.3"

kotlin {
  jvmToolchain(21)

  android {
    namespace = "cn.edu.ubaa.compose"
    compileSdk = libs.versions.android.compileSdk.get().toInt()
    minSdk = libs.versions.android.minSdk.get().toInt()
  }

  listOf(iosArm64(), iosSimulatorArm64()).forEach { iosTarget ->
    iosTarget.binaries.framework {
      baseName = "ComposeApp"
      isStatic = true
    }
  }

  jvm()

  js {
    browser()
    binaries.executable()
  }

  @OptIn(ExperimentalWasmDsl::class)
  wasmJs {
    browser()
    binaries.executable()
  }

  sourceSets {
    androidMain.dependencies {
      implementation("org.jetbrains.compose.ui:ui-tooling-preview:$composeVersion")
      implementation(libs.androidx.activity.compose)
    }
    commonMain.dependencies {
      implementation("org.jetbrains.compose.runtime:runtime:$composeVersion")
      implementation("org.jetbrains.compose.foundation:foundation:$composeVersion")
      implementation("org.jetbrains.compose.material:material:$composeVersion")
      implementation("org.jetbrains.compose.material3:material3:$composeMaterial3Version")
      implementation("org.jetbrains.compose.ui:ui:$composeVersion")
      implementation(
          "org.jetbrains.compose.material:material-icons-extended:$composeMaterialIconsExtendedVersion"
      )
      implementation("org.jetbrains.compose.components:components-resources:$composeVersion")
      implementation("org.jetbrains.compose.ui:ui-tooling-preview:$composeVersion")
      implementation(kotlin("reflect"))
      implementation(libs.androidx.lifecycle.viewmodelCompose)
      implementation(libs.androidx.lifecycle.runtimeCompose)
      implementation(libs.kotlinx.coroutinesCore)
      implementation(libs.kotlinx.datetime)
      implementation(libs.kamel.image)
      implementation(libs.coil3.compose)
      implementation(libs.coil3.network.ktor)
      implementation(libs.ktor.serialization.kotlinx.json)
      implementation(projects.shared)
      implementation("org.jetbrains.kotlin:kotlin-metadata-jvm")
    }

    commonTest.dependencies {
      implementation(libs.kotlin.test)
      implementation(libs.kotlinx.coroutines.test)
    }

    jvmMain.dependencies {
      implementation(compose.desktop.currentOs)
      implementation(libs.kotlinx.coroutinesSwing)
    }
  }
}

compose.desktop {
  application {
    mainClass = "cn.edu.ubaa.MainKt"
    nativeDistributions {
      targetFormats(TargetFormat.Dmg, TargetFormat.Msi, TargetFormat.Deb, TargetFormat.Exe)
      packageName = "UBAA"
      packageVersion = project.property("project.version").toString()
      macOS { iconFile = project.file("icons/app.icns") }
      linux { iconFile = project.file("icons/app.png") }

      buildTypes.release.proguard {
        isEnabled.set(false)
        version.set("7.8.2")
        configurationFiles.from("compose-desktop.pro")
      }

      windows {
        iconFile = project.file("icons/app.ico")
        menu = true
        shortcut = true
        perUserInstall = false
      }
    }
  }
}
