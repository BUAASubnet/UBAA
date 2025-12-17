package cn.edu.ubaa.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.AuthService
import cn.edu.ubaa.api.CaptchaRequiredClientException
import cn.edu.ubaa.api.UserService
import cn.edu.ubaa.model.dto.CaptchaInfo
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** ViewModel managing authentication and user state */
class AuthViewModel : ViewModel() {
    private val authService = AuthService()
    private val userService = UserService()

    private val _uiState = MutableStateFlow(AuthUiState())
    val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()

    private val _loginForm = MutableStateFlow(LoginFormState())
    val loginForm: StateFlow<LoginFormState> = _loginForm.asStateFlow()

    init {
        restoreSession()
    }

    fun updateUsername(username: String) {
        _loginForm.value = _loginForm.value.copy(username = username)
    }

    fun updatePassword(password: String) {
        _loginForm.value = _loginForm.value.copy(password = password)
    }

    fun updateCaptcha(captcha: String) {
        _loginForm.value = _loginForm.value.copy(captcha = captcha)
    }

    fun showCaptchaDialog(captchaInfo: CaptchaInfo) {
        _uiState.value =
                _uiState.value.copy(
                        captchaInfo = captchaInfo,
                        showCaptchaDialog = true,
                        isLoading = false,
                        error = null
                )
        _loginForm.value = _loginForm.value.copy(captcha = "")
    }

    fun hideCaptchaDialog(clearInput: Boolean = true) {
        _uiState.value = _uiState.value.copy(showCaptchaDialog = false)
        if (clearInput) {
            _loginForm.value = _loginForm.value.copy(captcha = "")
        }
    }

    fun login() {
        val form = _loginForm.value
        if (form.username.isBlank() || form.password.isBlank()) {
            _uiState.value = _uiState.value.copy(error = "用户名和密码不能为空")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)

            authService
                    .login(form.username, form.password, form.captcha.ifBlank { null })
                    .onSuccess { loginResponse ->
                        _uiState.value =
                                _uiState.value.copy(
                                        isLoggedIn = true,
                                        isLoading = false,
                                        userData = loginResponse.user,
                                        token = loginResponse.token,
                                        showCaptchaDialog = false,
                                        captchaInfo = null
                                )
                        // Clear the form for security
                        _loginForm.value = LoginFormState()
                        // Load user info
                        loadUserInfo()
                    }
                    .onFailure { exception ->
                        when (exception) {
                            is CaptchaRequiredClientException -> {
                                showCaptchaDialog(exception.captchaInfo)
                            }
                            else -> {
                                _uiState.value =
                                        _uiState.value.copy(
                                                isLoading = false,
                                                error = exception.message ?: "登录失败"
                                        )
                            }
                        }
                    }
        }
    }

    /** Try to restore session from stored token and validate with status endpoint. */
    fun restoreSession() {
        viewModelScope.launch {
            val storedToken = cn.edu.ubaa.api.TokenStore.get()
            if (storedToken.isNullOrBlank()) return@launch

            authService.applyStoredToken()
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)

            authService
                    .getAuthStatus()
                    .onSuccess { status ->
                        _uiState.value =
                                _uiState.value.copy(
                                        isLoggedIn = true,
                                        isLoading = false,
                                        userData = status.user,
                                        token = storedToken,
                                        error = null
                                )
                        loadUserInfo()
                    }
                    .onFailure {
                        _uiState.value = _uiState.value.copy(isLoading = false)
                        cn.edu.ubaa.api.TokenStore.clear()
                    }
        }
    }

    fun logout() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)

            authService
                    .logout()
                    .onSuccess {
                        _uiState.value = AuthUiState()
                        _loginForm.value = LoginFormState()
                    }
                    .onFailure { exception ->
                        // Even if logout fails, clear local state
                        _uiState.value =
                                AuthUiState(
                                        error =
                                                "Logout completed with warnings: ${exception.message}"
                                )
                        _loginForm.value = LoginFormState()
                    }
        }
    }

    private fun loadUserInfo() {
        viewModelScope.launch {
            userService
                    .getUserInfo()
                    .onSuccess { userInfo ->
                        _uiState.value = _uiState.value.copy(userInfo = userInfo)
                    }
                    .onFailure { exception ->
                        // Don't show error for user info failure if already logged in
                        println("Failed to load user info: ${exception.message}")
                    }
        }
    }

    fun clearError() {
        _uiState.value =
                _uiState.value.copy(error = null, showCaptchaDialog = false, captchaInfo = null)
        _loginForm.value = _loginForm.value.copy(captcha = "")
    }
}

data class AuthUiState(
        val isLoading: Boolean = false,
        val isLoggedIn: Boolean = false,
        val userData: UserData? = null,
        val userInfo: UserInfo? = null,
        val token: String? = null,
        val error: String? = null,
        val captchaInfo: CaptchaInfo? = null,
        val showCaptchaDialog: Boolean = false
)

data class LoginFormState(
        val username: String = "",
        val password: String = "",
        val captcha: String = ""
)
