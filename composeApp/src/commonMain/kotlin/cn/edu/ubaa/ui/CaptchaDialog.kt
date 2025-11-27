package cn.edu.ubaa.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import cn.edu.ubaa.model.dto.CaptchaInfo
import io.kamel.image.KamelImage
import io.kamel.image.asyncPainterResource

@Composable
fun CaptchaDialog(
        captchaInfo: CaptchaInfo,
        captchaValue: String,
        onCaptchaChange: (String) -> Unit,
        onConfirm: () -> Unit,
        onDismiss: () -> Unit,
        isLoading: Boolean = false,
        modifier: Modifier = Modifier
) {
        Dialog(onDismissRequest = onDismiss) {
                Card(
                        modifier = modifier.width(400.dp),
                        colors =
                                CardDefaults.cardColors(
                                        containerColor = MaterialTheme.colorScheme.surface
                                )
                ) {
                        Column(
                                modifier = Modifier.fillMaxWidth().padding(24.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                                Text(
                                        text = "验证码验证",
                                        style = MaterialTheme.typography.headlineSmall,
                                        modifier = Modifier.padding(bottom = 16.dp)
                                )

                                Text(
                                        text = "请输入验证码以继续登录",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(bottom = 16.dp)
                                )

                                Card(
                                        modifier =
                                                Modifier.fillMaxWidth()
                                                        .height(140.dp)
                                                        .padding(bottom = 16.dp),
                                        colors =
                                                CardDefaults.cardColors(
                                                        containerColor =
                                                                MaterialTheme.colorScheme
                                                                        .surfaceVariant
                                                )
                                ) {
                                        Box(
                                                modifier = Modifier.fillMaxSize(),
                                                contentAlignment = Alignment.Center
                                        ) {
                                                KamelImage(
                                                        resource = {
                                                                asyncPainterResource(
                                                                        data = captchaInfo.imageUrl
                                                                )
                                                        },
                                                        contentDescription = "验证码图片",
                                                        modifier = Modifier.fillMaxSize(),
                                                        contentScale = ContentScale.Fit,
                                                        onLoading = { CircularProgressIndicator() },
                                                        onFailure = { error ->
                                                                Column(
                                                                        horizontalAlignment =
                                                                                Alignment
                                                                                        .CenterHorizontally,
                                                                        verticalArrangement =
                                                                                Arrangement
                                                                                        .spacedBy(
                                                                                                8.dp
                                                                                        ),
                                                                        modifier =
                                                                                Modifier.padding(
                                                                                        12.dp
                                                                                )
                                                                ) {
                                                                        Text(
                                                                                text = "验证码加载失败",
                                                                                style =
                                                                                        MaterialTheme
                                                                                                .typography
                                                                                                .bodyMedium,
                                                                                color =
                                                                                        MaterialTheme
                                                                                                .colorScheme
                                                                                                .onSurfaceVariant
                                                                        )
                                                                        error.message
                                                                                ?.takeIf {
                                                                                        it.isNotBlank()
                                                                                }
                                                                                ?.let { message ->
                                                                                        Text(
                                                                                                text =
                                                                                                        message,
                                                                                                style =
                                                                                                        MaterialTheme
                                                                                                                .typography
                                                                                                                .bodySmall,
                                                                                                color =
                                                                                                        MaterialTheme
                                                                                                                .colorScheme
                                                                                                                .onSurfaceVariant
                                                                                        )
                                                                                }
                                                                }
                                                        }
                                                )
                                        }
                                }

                                // CAPTCHA input
                                OutlinedTextField(
                                        value = captchaValue,
                                        onValueChange = onCaptchaChange,
                                        label = { Text("验证码") },
                                        singleLine = true,
                                        keyboardOptions =
                                                KeyboardOptions(keyboardType = KeyboardType.Text),
                                        enabled = !isLoading,
                                        modifier = Modifier.fillMaxWidth().padding(bottom = 24.dp)
                                )

                                // Buttons
                                Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement =
                                                Arrangement.spacedBy(12.dp, Alignment.End)
                                ) {
                                        TextButton(onClick = onDismiss) { Text("取消") }

                                        Button(
                                                onClick = onConfirm,
                                                enabled = captchaValue.isNotBlank() && !isLoading
                                        ) {
                                                if (isLoading) {
                                                        CircularProgressIndicator(
                                                                modifier = Modifier.size(18.dp),
                                                                strokeWidth = 2.dp,
                                                                color =
                                                                        MaterialTheme.colorScheme
                                                                                .onPrimary
                                                        )
                                                } else {
                                                        Text("确认")
                                                }
                                        }
                                }
                        }
                }
        }
}
