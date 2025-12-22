package cn.edu.ubaa.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.ui.screens.auth.LoginFormState
import coil3.compose.AsyncImage
import coil3.compose.LocalPlatformContext
import coil3.request.ImageRequest
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

// 登录界面
@Composable
fun LoginScreen(
    loginFormState: LoginFormState,
    onUsernameChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    onCaptchaChange: (String) -> Unit,
    onRememberPasswordChange: (Boolean) -> Unit,
    onAutoLoginChange: (Boolean) -> Unit,
    onLoginClick: () -> Unit,
    onRefreshCaptcha: () -> Unit,
    isLoading: Boolean,
    isPreloading: Boolean,
    isRefreshingCaptcha: Boolean,
    captchaRequired: Boolean,
    captchaInfo: cn.edu.ubaa.model.dto.CaptchaInfo?,
    error: String?,
    modifier: Modifier = Modifier
) {
        // 预加载状态显示
        if (isPreloading) {
                Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                CircularProgressIndicator()
                                Spacer(modifier = Modifier.height(16.dp))
                                Text("正在加载...")
                        }
                }
                return
        }

        Column(
                modifier = modifier.fillMaxSize().padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
        ) {
                Text(
                        text = "UBAA 登录",
                        style = MaterialTheme.typography.headlineMedium,
                        modifier = Modifier.padding(bottom = 32.dp)
                )

                OutlinedTextField(
                        value = loginFormState.username,
                        onValueChange = onUsernameChange,
                        label = { Text("学号") },
                        singleLine = true,
                        enabled = !isLoading,
                        modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp)
                )

                OutlinedTextField(
                        value = loginFormState.password,
                        onValueChange = onPasswordChange,
                        label = { Text("密码") },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        enabled = !isLoading,
                        modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp)
                )

                // 验证码区域（仅在需要时显示）
                if (captchaRequired && captchaInfo != null) {
                        Row(
                                modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
                                verticalAlignment = Alignment.CenterVertically
                        ) {
                                OutlinedTextField(
                                        value = loginFormState.captcha,
                                        onValueChange = onCaptchaChange,
                                        label = { Text("验证码") },
                                        singleLine = true,
                                        enabled = !isLoading,
                                        modifier = Modifier.weight(1f).padding(end = 8.dp)
                                )

                                // 验证码图片
                                CaptchaImage(
                                        captchaInfo = captchaInfo,
                                        onClick = onRefreshCaptcha,
                                        isRefreshing = isRefreshingCaptcha,
                                        modifier = Modifier.height(56.dp).width(120.dp)
                                )
                        }

                        Text(
                                text = "点击图片刷新验证码",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(bottom = 8.dp)
                        )
                }

                Row(
                        modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                ) {
                        Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier =
                                        Modifier.clickable {
                                                onRememberPasswordChange(
                                                        !loginFormState.rememberPassword
                                                )
                                        }
                        ) {
                                Checkbox(
                                        checked = loginFormState.rememberPassword,
                                        onCheckedChange = onRememberPasswordChange,
                                        enabled = !isLoading
                                )
                                Text("记住密码", style = MaterialTheme.typography.bodyMedium)
                        }
                        Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier =
                                        Modifier.clickable {
                                                onAutoLoginChange(!loginFormState.autoLogin)
                                        }
                        ) {
                                Checkbox(
                                        checked = loginFormState.autoLogin,
                                        onCheckedChange = onAutoLoginChange,
                                        enabled = !isLoading
                                )
                                Text("自动登录", style = MaterialTheme.typography.bodyMedium)
                        }
                }

                Spacer(modifier = Modifier.height(8.dp))

                Button(
                        onClick = onLoginClick,
                        enabled =
                                !isLoading &&
                                        loginFormState.username.isNotBlank() &&
                                        loginFormState.password.isNotBlank() &&
                                        (!captchaRequired || loginFormState.captcha.isNotBlank()),
                        modifier = Modifier.fillMaxWidth().height(48.dp)
                ) {
                        if (isLoading) {
                                CircularProgressIndicator(
                                        modifier = Modifier.size(20.dp),
                                        strokeWidth = 2.dp,
                                        color = MaterialTheme.colorScheme.onPrimary
                                )
                        } else {
                                Text("登录")
                        }
                }

                error?.let { errorMessage ->
                        Card(
                                modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
                                colors =
                                        CardDefaults.cardColors(
                                                containerColor =
                                                        MaterialTheme.colorScheme.errorContainer
                                        )
                        ) {
                                Text(
                                        text = errorMessage,
                                        color = MaterialTheme.colorScheme.onErrorContainer,
                                        modifier = Modifier.padding(16.dp)
                                )
                        }
                }
        }
}

@Composable
private fun CaptchaImage(
        captchaInfo: cn.edu.ubaa.model.dto.CaptchaInfo,
        onClick: () -> Unit,
        isRefreshing: Boolean,
        modifier: Modifier = Modifier
) {
        // 从 base64 解码为 ByteArray，Kamel 支持加载 ByteArray
        @OptIn(ExperimentalEncodingApi::class)
        val imageBytes: ByteArray? =
                remember(captchaInfo.base64Image) {
                        captchaInfo
                                .base64Image
                                ?.trim()
                                ?.substringAfter("base64,", "")
                                ?.takeIf { it.isNotBlank() }
                                ?.let { payload ->
                                        runCatching { Base64.decode(payload) }.getOrNull()
                                }
                }

        Card(
                modifier = modifier.clickable(enabled = !isRefreshing, onClick = onClick),
                colors =
                        CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceVariant
                        )
        ) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        when {
                                isRefreshing -> {
                                        CircularProgressIndicator(
                                                modifier = Modifier.size(24.dp),
                                                strokeWidth = 2.dp
                                        )
                                }
                                imageBytes != null -> {
                                        val context = LocalPlatformContext.current
                                        AsyncImage(
                                                model =
                                                        ImageRequest.Builder(context)
                                                                .data(imageBytes)
                                                                .build(),
                                                contentDescription = "验证码图片，点击刷新",
                                                modifier = Modifier.fillMaxSize(),
                                                contentScale = ContentScale.Fit
                                        )
                                }
                                else -> {
                                        Text(
                                                text = "验证码加载失败",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.error
                                        )
                                }
                        }
                }
        }
}
