package cn.edu.ubaa.ui.common.util

import androidx.compose.runtime.Composable

/** No-op back handler for iOS. */
@Composable
actual fun BackHandlerCompat(enabled: Boolean, onBack: () -> Unit) {
    /* no-op */
}
