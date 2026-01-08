package cn.edu.ubaa

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.lifecycle.viewmodel.compose.viewModel
import cn.edu.ubaa.api.GitHubRelease
import cn.edu.ubaa.api.UpdateService
import cn.edu.ubaa.ui.navigation.MainAppScreen
import cn.edu.ubaa.ui.screens.auth.AuthViewModel
import cn.edu.ubaa.ui.screens.auth.LoginScreen
import cn.edu.ubaa.ui.screens.splash.SplashScreen
import cn.edu.ubaa.ui.theme.PreloadFonts
import cn.edu.ubaa.ui.theme.UBAATheme
import kotlinx.coroutines.delay
import org.jetbrains.compose.ui.tooling.preview.Preview

/**
 * 应用程序顶层入口 Composable。 负责全局状态管理，包括：
 * 1. 字体预加载。
 * 2. 整体主题应用。
 * 3. 认证状态监听与自动登录逻辑。
 * 4. 启动界面 (Splash) 与主界面/登录界面的切换。
 * 5. 软件更新检测与弹窗提示。
 */
@Composable
@Preview
fun App() {
  // 预加载应用所需的中文字体
  PreloadFonts()

  UBAATheme {
    val authViewModel: AuthViewModel = viewModel { AuthViewModel() }
    val uiState by authViewModel.uiState.collectAsState()
    val loginForm by authViewModel.loginForm.collectAsState()

    // 启动流程控制状态
    var isSplashFinished by remember { mutableStateOf(false) }

    // 更新检测逻辑
    val updateService = remember { UpdateService() }
    var updateInfo by remember { mutableStateOf<GitHubRelease?>(null) }
    val uriHandler = LocalUriHandler.current

    LaunchedEffect(Unit) { updateInfo = updateService.checkUpdate() }

    // 核心初始化逻辑：尝试恢复会话
    LaunchedEffect(Unit) { authViewModel.initializeApp() }

    // 根据认证状态和加载进度决定何时隐藏 Splash 界面
    LaunchedEffect(
      uiState.isLoggedIn,
      uiState.error,
      uiState.isLoading,
      uiState.isPreloading,
      uiState.isRefreshingCaptcha,
    ) {
      val shouldEndSplash =
        (uiState.isLoggedIn && uiState.userData != null) ||
          (uiState.error != null &&
            !uiState.isLoading &&
            !uiState.isPreloading &&
            !uiState.isRefreshingCaptcha) ||
          (!uiState.isLoading &&
            !uiState.isPreloading &&
            !uiState.isRefreshingCaptcha &&
            !uiState.isLoggedIn &&
            uiState.error == null &&
            !loginForm.autoLogin)

      if (shouldEndSplash) isSplashFinished = true
    }

    // 版本更新对话框
    if (updateInfo != null) {
      val release = updateInfo!!
      AlertDialog(
        onDismissRequest = { updateInfo = null },
        title = { Text("发现新版本 ${release.tagName}") },
        text = { Text(release.body ?: "点击下方按钮前往下载最新版本。") },
        confirmButton = {
          TextButton(
            onClick = {
              uriHandler.openUri(release.htmlUrl)
              updateInfo = null
            }
          ) {
            Text("前往下载")
          }
        },
        dismissButton = { TextButton(onClick = { updateInfo = null }) { Text("稍后再说") } },
      )
    }

    // 视图切换状态机
    when {
      !isSplashFinished -> SplashScreen(modifier = Modifier.fillMaxSize())
      uiState.isLoggedIn && uiState.userData != null -> {
        val userData = uiState.userData!!
        MainAppScreen(
          userData = userData,
          userInfo = uiState.userInfo,
          onLogoutClick = { authViewModel.logout() },
          modifier = Modifier.safeContentPadding().fillMaxSize(),
        )
      }
      else -> {
        LoginScreen(
          loginFormState = loginForm,
          onUsernameChange = { authViewModel.updateUsername(it) },
          onPasswordChange = { authViewModel.updatePassword(it) },
          onCaptchaChange = { authViewModel.updateCaptcha(it) },
          onRememberPasswordChange = { authViewModel.updateRememberPassword(it) },
          onAutoLoginChange = { authViewModel.updateAutoLogin(it) },
          onLoginClick = { authViewModel.login() },
          onRefreshCaptcha = { authViewModel.refreshCaptcha() },
          isLoading = uiState.isLoading,
          isRefreshingCaptcha = uiState.isRefreshingCaptcha,
          captchaRequired = uiState.captchaRequired,
          captchaInfo = uiState.captchaInfo,
          error = uiState.error,
          modifier =
            Modifier.background(MaterialTheme.colorScheme.background)
              .safeContentPadding()
              .fillMaxSize(),
        )
      }
    }

    // 错误消息自动淡出
    LaunchedEffect(uiState.error) {
      if (uiState.error != null) {
        delay(5000)
        authViewModel.clearError()
      }
    }
  }
}
