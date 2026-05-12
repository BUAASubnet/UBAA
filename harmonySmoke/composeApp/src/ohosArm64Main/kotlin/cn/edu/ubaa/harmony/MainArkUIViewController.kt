package cn.edu.ubaa.harmony

import androidx.compose.ui.window.ComposeArkUIViewController
import kotlin.experimental.ExperimentalNativeApi
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.coroutines.initMainHandler
import platform.ohos.napi_env
import platform.ohos.napi_value

@OptIn(ExperimentalForeignApi::class, ExperimentalNativeApi::class)
@CName("MainArkUIViewController")
fun MainArkUIViewController(env: napi_env): napi_value {
  initMainHandler(env)
  return ComposeArkUIViewController(env) { HarmonySmokeApp() }
}
