package cn.edu.ubaa

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import cn.edu.ubaa.ui.AuthViewModel
import cn.edu.ubaa.ui.LoginScreen
import cn.edu.ubaa.ui.MainAppScreen
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
            // Show main app when logged in
            MainAppScreen(
                userData = userData,
                userInfo = uiState.userInfo,
                onLogoutClick = { authViewModel.logout() },
                modifier = Modifier
                    .background(MaterialTheme.colorScheme.background)
                    .safeContentPadding()
                    .fillMaxSize()
            )
        } else {
            // Show login screen when not logged in
            LoginScreen(
                loginFormState = loginForm,
                onUsernameChange = { authViewModel.updateUsername(it) },
                onPasswordChange = { authViewModel.updatePassword(it) },
                onLoginClick = { authViewModel.login() },
                isLoading = uiState.isLoading,
                error = uiState.error,
                modifier = Modifier
                    .background(MaterialTheme.colorScheme.background)
                    .safeContentPadding()
                    .fillMaxSize()
            )
        }

        // Clear error when the user interacts
        LaunchedEffect(uiState.error) {
            if (uiState.error != null) {
                delay(5000) // Clear error after 5 seconds
                authViewModel.clearError()
            }
        }
    }
}