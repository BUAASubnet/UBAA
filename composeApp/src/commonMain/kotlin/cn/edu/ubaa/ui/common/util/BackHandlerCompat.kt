package cn.edu.ubaa.ui.common.util

import androidx.compose.runtime.Composable

/**
 * Cross-platform back handler. On Android it delegates to androidx.activity.compose.BackHandler; on
 * other targets it is a no-op.
 */
@Composable expect fun BackHandlerCompat(enabled: Boolean = true, onBack: () -> Unit)
