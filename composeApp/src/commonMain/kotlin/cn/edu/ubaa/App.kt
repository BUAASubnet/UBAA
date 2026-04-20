package cn.edu.ubaa

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import cn.edu.ubaa.api.AppVersionCheckResponse
import cn.edu.ubaa.api.ConnectionMode
import cn.edu.ubaa.api.ConnectionRuntime
import cn.edu.ubaa.api.UpdateService
import cn.edu.ubaa.ui.navigation.MainAppScreen
import cn.edu.ubaa.ui.screens.auth.AuthViewModel
import cn.edu.ubaa.ui.screens.auth.ConnectionModeSelectionScreen
import cn.edu.ubaa.ui.screens.auth.LoginScreen
import cn.edu.ubaa.ui.screens.splash.SplashScreen
import cn.edu.ubaa.ui.theme.PreloadFonts
import cn.edu.ubaa.ui.theme.UBAATheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

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
    val appScope = rememberCoroutineScope()
    val availableConnectionModes = remember { ConnectionRuntime.availableModes() }
    var selectedConnectionMode by remember { mutableStateOf<ConnectionMode?>(null) }
    var modeResolved by remember { mutableStateOf(false) }

    // 启动流程控制状态
    var isSplashFinished by remember { mutableStateOf(false) }

    // 更新检测逻辑
    val updateService = remember { UpdateService() }
    var updateInfo by remember { mutableStateOf<AppVersionCheckResponse?>(null) }
    val uriHandler = LocalUriHandler.current

    suspend fun bootstrapForMode(mode: ConnectionMode) {
      selectedConnectionMode = mode
      updateInfo = updateService.checkUpdate()
      authViewModel.initializeApp()
    }

    LaunchedEffect(Unit) {
      selectedConnectionMode = ConnectionRuntime.resolveSelectedMode()
      modeResolved = true
      selectedConnectionMode?.let { bootstrapForMode(it) }
    }

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
      val releaseNotes = release.releaseNotes?.takeIf { it.isNotBlank() } ?: "点击下方按钮下载最新客户端。"
      val updateMessage = buildString {
        append("当前客户端版本：")
        append(AppInfo.version)
        append('\n')
        append("最新客户端版本：")
        append(release.latestVersion)
        append("\n\n")
        append(releaseNotes)
      }

      AlertDialog(
          onDismissRequest = { updateInfo = null },
          title = { Text("发现新版本") },
          text = {
            Box(Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState())) {
              Text(updateMessage)
            }
          },
          confirmButton = {
            TextButton(
                onClick = {
                  uriHandler.openUri(release.downloadUrl)
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
      !modeResolved -> SplashScreen(modifier = Modifier.fillMaxSize())
      selectedConnectionMode == null ->
          ConnectionModeSelectionScreen(
              availableModes = availableConnectionModes,
              onConfirm = { mode ->
                appScope.launch { bootstrapForMode(mode.also(ConnectionRuntime::switchMode)) }
              },
              modifier = Modifier.fillMaxSize(),
          )
      !isSplashFinished -> SplashScreen(modifier = Modifier.fillMaxSize())
      uiState.isLoggedIn && uiState.userData != null -> {
        val userData = uiState.userData!!
        MainAppScreen(
            userData = userData,
            userInfo = uiState.userInfo,
            connectionMode = selectedConnectionMode ?: ConnectionMode.SERVER_RELAY,
            availableConnectionModes = availableConnectionModes,
            onEnsureUserInfo = { authViewModel.ensureUserInfoLoaded() },
            onConnectionModeSelected = { mode ->
              selectedConnectionMode = mode
              authViewModel.switchConnectionMode(mode)
              appScope.launch { updateInfo = updateService.checkUpdate() }
            },
            onLogoutClick = { authViewModel.logout() },
            modifier = Modifier.fillMaxSize(),
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
            modifier = Modifier.background(MaterialTheme.colorScheme.background).fillMaxSize(),
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
