package cn.edu.ubaa.ui.common.util

import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.LocalOnBackPressedDispatcherOwner
import androidx.compose.runtime.*
import androidx.lifecycle.compose.LocalLifecycleOwner

@Composable
actual fun BackHandlerCompat(enabled: Boolean, onBack: () -> Unit) {
  val backDispatcher = LocalOnBackPressedDispatcherOwner.current?.onBackPressedDispatcher
  val lifecycleOwner = LocalLifecycleOwner.current
  val currentOnBack by rememberUpdatedState(onBack)

  val backCallback = remember {
    object : OnBackPressedCallback(enabled) {
      override fun handleOnBackPressed() {
        currentOnBack()
      }
    }
  }

  SideEffect { backCallback.isEnabled = enabled }

  DisposableEffect(lifecycleOwner, backDispatcher) {
    backDispatcher?.addCallback(lifecycleOwner, backCallback)
    onDispose { backCallback.remove() }
  }
}
