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

kotlin {
  jvmToolchain(21)

  androidLibrary {
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
      implementation(compose.preview)
      implementation(libs.androidx.activity.compose)
    }
    commonMain.dependencies {
      implementation(compose.runtime)
      implementation(compose.foundation)
      implementation(compose.material)
      implementation(compose.material3)
      implementation(compose.ui)
      implementation(compose.materialIconsExtended)
      implementation(compose.components.resources)
      implementation(compose.components.uiToolingPreview)
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

      buildTypes.release.proguard {
        isEnabled.set(false)
        version.set("7.8.2")
        configurationFiles.from("compose-desktop.pro")
      }

      windows {
        menu = true
        shortcut = true
        perUserInstall = false
      }
    }
  }
}
