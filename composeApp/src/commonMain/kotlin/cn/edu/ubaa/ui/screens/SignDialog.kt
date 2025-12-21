package cn.edu.ubaa.ui.screens

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable

/** Simple info-only dialog: coordinates are auto-randomized; no manual input needed. */
@Composable
fun SignDialog(isSignIn: Boolean, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(
            onDismissRequest = onDismiss,
            confirmButton = {
                TextButton(onClick = { onConfirm() }) { Text(if (isSignIn) "确认签到" else "确认签退") }
            },
            dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
            title = { Text(text = if (isSignIn) "签到" else "签退") },
            text = { Text("无需填写经纬度，系统会在课程配置的签到范围内自动随机坐标。") }
    )
}
