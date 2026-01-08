plugins {
  // 定义所有子项目通用的插件，并设置 apply false
  // 这样做是为了避免插件在每个子项目的类加载器中被多次加载，从而优化构建性能。
  // 子项目会按需应用这些插件。

  // Android 应用程序插件，用于构建最终的 APK
  alias(libs.plugins.androidApplication) apply false
  // Android 库插件，用于构建可重用的 Android 库
  alias(libs.plugins.androidLibrary) apply false
  // Android KMP 库插件
  alias(libs.plugins.androidKotlinMultiplatformLibrary) apply false
  // Compose 热重载支持
  alias(libs.plugins.composeHotReload) apply false
  // Compose Multiplatform 核心插件，支持跨平台 UI
  alias(libs.plugins.composeMultiplatform) apply false
  // Compose 编译器插件
  alias(libs.plugins.composeCompiler) apply false
  // Kotlin JVM 插件，用于纯 Java/Kotlin 后端或工具库
  alias(libs.plugins.kotlinJvm) apply false
  // Kotlin Android 插件
  alias(libs.plugins.kotlinAndroid) apply false
  // Kotlin Multiplatform 插件，用于跨平台共享代码
  alias(libs.plugins.kotlinMultiplatform) apply false
  // BuildKonfig 插件，用于在构建时生成配置代码
  alias(libs.plugins.buildkonfig) apply false
  // Kover 插件，用于测试覆盖率报告
  alias(libs.plugins.kover)
}
