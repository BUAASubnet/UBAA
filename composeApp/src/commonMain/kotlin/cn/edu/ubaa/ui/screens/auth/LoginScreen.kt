package cn.edu.ubaa.ui.screens.auth

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.CaptchaInfo
import coil3.compose.AsyncImage
import coil3.compose.LocalPlatformContext
import coil3.request.ImageRequest
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

/**
 * 登录界面 Composable 函数。 提供用户名、密码、验证码（可选）输入以及记住密码、自动登录选项。
 *
 * @param loginFormState 包含当前输入的表单数据。
 * @param onUsernameChange 用户名改变回调。
 * @param onPasswordChange 密码改变回调。
 * @param onCaptchaChange 验证码改变回调。
 * @param onRememberPasswordChange “记住密码”开关回调。
 * @param onAutoLoginChange “自动登录”开关回调。
 * @param onLoginClick 点击登录按钮回调。
 * @param onRefreshCaptcha 点击验证码图片刷新回调。
 * @param isLoading 是否处于正在登录的加载状态。
 * @param isRefreshingCaptcha 是否正在刷新验证码图片。
 * @param captchaRequired 是否需要展示验证码输入框。
 * @param captchaInfo 验证码详细信息（含 Base64 图片）。
 * @param error 错误信息提示（若有）。
 */
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
  isRefreshingCaptcha: Boolean,
  captchaRequired: Boolean,
  captchaInfo: CaptchaInfo?,
  error: String?,
  modifier: Modifier = Modifier,
) {
  Column(
    modifier = modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(32.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.Center,
  ) {
    Text(
      text = "UBAA 登录",
      style = MaterialTheme.typography.headlineMedium,
      modifier = Modifier.padding(bottom = 32.dp),
    )

    OutlinedTextField(
      value = loginFormState.username,
      onValueChange = onUsernameChange,
      label = { Text("学号") },
      singleLine = true,
      enabled = !isLoading,
      modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
    )

    OutlinedTextField(
      value = loginFormState.password,
      onValueChange = onPasswordChange,
      label = { Text("密码") },
      singleLine = true,
      visualTransformation = PasswordVisualTransformation(),
      keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
      enabled = !isLoading,
      modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
    )

    if (captchaRequired && captchaInfo != null) {
      Row(
        modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        OutlinedTextField(
          value = loginFormState.captcha,
          onValueChange = onCaptchaChange,
          label = { Text("验证码") },
          singleLine = true,
          enabled = !isLoading,
          modifier = Modifier.weight(1f).padding(end = 8.dp),
        )
        CaptchaImage(
          captchaInfo = captchaInfo,
          onClick = onRefreshCaptcha,
          isRefreshing = isRefreshingCaptcha,
          modifier = Modifier.height(56.dp).width(120.dp),
        )
      }
      Text(
        text = "点击图片刷新验证码",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(bottom = 8.dp),
      )
    }

    Row(
      modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.SpaceBetween,
    ) {
      Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.clickable { onRememberPasswordChange(!loginFormState.rememberPassword) },
      ) {
        Checkbox(
          checked = loginFormState.rememberPassword,
          onCheckedChange = onRememberPasswordChange,
          enabled = !isLoading,
        )
        Text("记住密码", style = MaterialTheme.typography.bodyMedium)
      }
      Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.clickable { onAutoLoginChange(!loginFormState.autoLogin) },
      ) {
        Checkbox(
          checked = loginFormState.autoLogin,
          onCheckedChange = onAutoLoginChange,
          enabled = !isLoading,
        )
        Text("自动登录", style = MaterialTheme.typography.bodyMedium)
      }
    }

    Button(
      onClick = onLoginClick,
      enabled =
        !isLoading &&
          loginFormState.username.isNotBlank() &&
          loginFormState.password.isNotBlank() &&
          (!captchaRequired || loginFormState.captcha.isNotBlank()),
      modifier = Modifier.fillMaxWidth().height(48.dp),
    ) {
      if (isLoading)
        CircularProgressIndicator(
          modifier = Modifier.size(20.dp),
          strokeWidth = 2.dp,
          color = MaterialTheme.colorScheme.onPrimary,
        )
      else Text("登录")
    }

    error?.let { msg ->
      Card(
        modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
      ) {
        Text(
          text = msg,
          color = MaterialTheme.colorScheme.onErrorContainer,
          modifier = Modifier.padding(16.dp),
        )
      }
    }

    Spacer(modifier = Modifier.height(32.dp))
    val uriHandler = LocalUriHandler.current
    Text(
      text = "开源项目: https://github.com/BUAASubnet/UBAA",
      style = MaterialTheme.typography.bodySmall,
      color = MaterialTheme.colorScheme.primary,
      modifier = Modifier.clickable { uriHandler.openUri("https://github.com/BUAASubnet/UBAA") },
    )
  }
}

/** 内部验证码展示组件。 */
@Composable
private fun CaptchaImage(
  captchaInfo: CaptchaInfo,
  onClick: () -> Unit,
  isRefreshing: Boolean,
  modifier: Modifier = Modifier,
) {
  @OptIn(ExperimentalEncodingApi::class)
  val imageBytes =
    remember(captchaInfo.base64Image) {
      captchaInfo.base64Image
        ?.substringAfter("base64,", "")
        ?.takeIf { it.isNotBlank() }
        ?.let { Base64.decode(it) }
    }

  Card(
    modifier = modifier.clickable(enabled = !isRefreshing, onClick = onClick),
    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
  ) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
      if (isRefreshing)
        CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
      else if (imageBytes != null)
        AsyncImage(
          model = ImageRequest.Builder(LocalPlatformContext.current).data(imageBytes).build(),
          contentDescription = null,
          modifier = Modifier.fillMaxSize(),
          contentScale = ContentScale.Fit,
        )
      else
        Text(
          text = "加载失败",
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.error,
        )
    }
  }
}
