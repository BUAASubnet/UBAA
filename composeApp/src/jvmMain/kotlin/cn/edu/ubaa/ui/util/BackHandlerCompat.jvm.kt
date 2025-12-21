package cn.edu.ubaa.ui.util

import androidx.compose.runtime.Composable

/** No-op back handler for JVM targets (desktop/web preview). */
@Composable
actual fun BackHandlerCompat(enabled: Boolean, onBack: () -> Unit) {
    /* no-op */
}
