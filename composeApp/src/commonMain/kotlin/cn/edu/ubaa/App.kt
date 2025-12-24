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

@Composable
@Preview
fun App() {
    PreloadFonts()

    UBAATheme {
        val authViewModel: AuthViewModel = viewModel { AuthViewModel() }
        val uiState by authViewModel.uiState.collectAsState()
        val loginForm by authViewModel.loginForm.collectAsState()

        // 检查用户是否有存储凭据（老用户）
        val hasStoredCredentials =
                loginForm.rememberPassword &&
                        loginForm.username.isNotBlank() &&
                        loginForm.password.isNotBlank()

        // 启动状态管理
        var isSplashFinished by remember { mutableStateOf(false) }

        // 检测更新
        val updateService = remember { UpdateService() }
        var updateInfo by remember { mutableStateOf<GitHubRelease?>(null) }
        val uriHandler = LocalUriHandler.current

        LaunchedEffect(Unit) { updateInfo = updateService.checkUpdate() }

        // 启动界面逻辑
        LaunchedEffect(Unit) {
            // 立即开始自动登录流程，不需要延迟
            authViewModel.initializeApp()
        }

        // 监听认证状态变化，决定是否结束启动界面
        LaunchedEffect(
                uiState.isLoggedIn,
                uiState.error,
                uiState.isLoading,
                uiState.isPreloading,
                uiState.isRefreshingCaptcha
        ) {
            // 结束启动界面的情况：
            // 1. 已成功登录且有用户数据
            // 2. 出现错误且没有正在加载（避免错误时的闪烁）
            // 3. 初始化完成但未登录（新用户）
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
                                    uiState.error == null)

            if (shouldEndSplash) {
                isSplashFinished = true
            }
        }

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
                        ) { Text("前往下载") }
                    },
                    dismissButton = { TextButton(onClick = { updateInfo = null }) { Text("稍后再说") } }
            )
        }

        // 根据状态决定显示什么界面
        when {
            !isSplashFinished -> {
                // 显示启动界面
                SplashScreen(modifier = Modifier.fillMaxSize())
            }
            uiState.isLoggedIn && uiState.userData != null -> {
                // 已登录，显示主界面
                val userData = uiState.userData!!
                MainAppScreen(
                        userData = userData,
                        userInfo = uiState.userInfo,
                        onLogoutClick = { authViewModel.logout() },
                        modifier = Modifier.safeContentPadding().fillMaxSize()
                )
            }
            hasStoredCredentials && !uiState.isLoggedIn && uiState.error == null -> {
                // 老用户正在自动登录，显示启动界面直到登录完成或失败
                SplashScreen(modifier = Modifier.fillMaxSize())
            }
            else -> {
                // 新用户或登录失败，显示登录界面
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
                                        .fillMaxSize()
                )
            }
        }

        // 用户操作后自动清除错误
        LaunchedEffect(uiState.error) {
            if (uiState.error != null) {
                delay(5000) // 5秒后清除错误
                authViewModel.clearError()
            }
        }
    }
}
