import android.databinding.tool.ext.capitalizeUS
import org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
  alias(libs.plugins.kotlinMultiplatform)
  alias(libs.plugins.androidApplication)
  alias(libs.plugins.composeMultiplatform)
  alias(libs.plugins.composeCompiler)
}

kotlin {
  androidTarget {
    @OptIn(ExperimentalKotlinGradlePluginApi::class)
    compilerOptions { jvmTarget.set(JvmTarget.JVM_11) }
  }

  ohosArm64 {
    binaries.sharedLib {
      baseName = "kn"
      export(libs.compose.multiplatform.export)
    }
  }

  sourceSets {
    androidMain.dependencies { implementation(libs.androidx.activity.compose) }
    commonMain.dependencies {
      implementation(compose.runtime)
      implementation(compose.foundation)
      implementation(compose.material)
      implementation(compose.ui)
      implementation(compose.components.resources)
      implementation(compose.components.uiToolingPreview)
      implementation(libs.kotlinx.coroutines.core)
      implementation(libs.atomicFu)
    }
    val ohosArm64Main by getting { dependencies { api(libs.compose.multiplatform.export) } }
  }
}

android {
  namespace = "cn.edu.ubaa.harmony"
  compileSdk = libs.versions.android.compileSdk.get().toInt()

  defaultConfig {
    applicationId = "cn.edu.ubaa.harmony"
    minSdk = libs.versions.android.minSdk.get().toInt()
    targetSdk = libs.versions.android.targetSdk.get().toInt()
    versionCode = 1
    versionName = "1.0"
  }
}

arrayOf("debug", "release").forEach { type ->
  tasks.register<Copy>("publish${type.capitalizeUS()}BinariesToHarmonyApp") {
    group = "harmony"
    dependsOn("link${type.capitalizeUS()}SharedOhosArm64")
    into(rootProject.file("harmonyApp"))
    from("build/bin/ohosArm64/${type}Shared/libkn_api.h") { into("entry/src/main/cpp/include/") }
    from(project.file("build/bin/ohosArm64/${type}Shared/libkn.so")) {
      into("entry/libs/arm64-v8a/")
    }
  }
}
