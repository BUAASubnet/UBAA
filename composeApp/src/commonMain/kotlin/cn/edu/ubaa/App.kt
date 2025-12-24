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

        // 检测更新
        val updateService = remember { UpdateService() }
        var updateInfo by remember { mutableStateOf<GitHubRelease?>(null) }
        val uriHandler = LocalUriHandler.current

        LaunchedEffect(Unit) { updateInfo = updateService.checkUpdate() }

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

        val userData = uiState.userData
        if (uiState.isLoggedIn && userData != null) {
            // 已登录，显示主界面
            MainAppScreen(
                    userData = userData,
                    userInfo = uiState.userInfo,
                    onLogoutClick = { authViewModel.logout() },
                    modifier = Modifier.safeContentPadding().fillMaxSize()
            )
        } else {
            // 未登录，显示登录界面
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
                    isPreloading = uiState.isPreloading,
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

        // 用户操作后自动清除错误
        LaunchedEffect(uiState.error) {
            if (uiState.error != null) {
                delay(5000) // 5秒后清除错误
                authViewModel.clearError()
            }
        }
    }
}
