package cn.edu.ubaa

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import cn.edu.ubaa.ui.screens.auth.AuthViewModel
import cn.edu.ubaa.ui.screens.auth.LoginScreen
import cn.edu.ubaa.ui.navigation.MainAppScreen
import kotlinx.coroutines.delay
import org.jetbrains.compose.ui.tooling.preview.Preview

@Composable
@Preview
fun App() {
    MaterialTheme {
        val authViewModel: AuthViewModel = viewModel()
        val uiState by authViewModel.uiState.collectAsState()
        val loginForm by authViewModel.loginForm.collectAsState()

        val userData = uiState.userData
        if (uiState.isLoggedIn && userData != null) {
            // 已登录，显示主界面
            MainAppScreen(
                    userData = userData,
                    userInfo = uiState.userInfo,
                    onLogoutClick = { authViewModel.logout() },
                    modifier =
                            Modifier.background(MaterialTheme.colorScheme.background)
                                    .safeContentPadding()
                                    .fillMaxSize()
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
