package cn.edu.ubaa.ui.screens.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.AuthService
import cn.edu.ubaa.api.CaptchaRequiredClientException
import cn.edu.ubaa.api.CredentialStore
import cn.edu.ubaa.api.TokenStore
import cn.edu.ubaa.api.UserService
import cn.edu.ubaa.model.dto.CaptchaInfo
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 认证与用户状态的ViewModel */
class AuthViewModel : ViewModel() {
    private val authService = AuthService()
    private val userService = UserService()

    private val _uiState = MutableStateFlow(AuthUiState())
    val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()

    private val _loginForm = MutableStateFlow(LoginFormState())
    val loginForm: StateFlow<LoginFormState> = _loginForm.asStateFlow()

    init {
        loadSavedCredentials()
        // 注意：不再在init中自动调用restoreSession，而是在启动界面逻辑中调用initializeApp
    }

    private fun loadSavedCredentials() {
        val remember = CredentialStore.isRememberPassword()
        val auto = CredentialStore.isAutoLogin()
        if (remember) {
            val username = CredentialStore.getUsername() ?: ""
            val password = CredentialStore.getPassword() ?: ""
            _loginForm.value =
                    _loginForm.value.copy(
                            username = username,
                            password = password,
                            rememberPassword = true,
                            autoLogin = auto
                    )
        } else {
            _loginForm.value = _loginForm.value.copy(rememberPassword = false, autoLogin = false)
        }
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

    fun updateRememberPassword(enabled: Boolean) {
        _loginForm.value = _loginForm.value.copy(rememberPassword = enabled)
        if (!enabled) {
            _loginForm.value = _loginForm.value.copy(autoLogin = false)
        }
    }

    fun updateAutoLogin(enabled: Boolean) {
        _loginForm.value = _loginForm.value.copy(autoLogin = enabled)
        if (enabled) {
            _loginForm.value = _loginForm.value.copy(rememberPassword = true)
        }
    }

    /** 预加载登录状态：为当前设备创建会话，获取验证码（如果需要） */
    fun preloadLoginState() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isPreloading = true, error = null)

            authService
                    .preloadLoginState()
                    .onSuccess { response ->
                        if (response.token != null && response.userData != null) {
                            // 自动登录成功（SSO 已登录）
                            _uiState.value =
                                    _uiState.value.copy(
                                            isPreloading = false,
                                            isLoggedIn = true,
                                            userData = response.userData,
                                            token = response.token,
                                            captchaRequired = false,
                                            captchaInfo = null,
                                            execution = null,
                                            error = null
                                    )
                            _loginForm.value = LoginFormState()
                            loadUserInfo()
                        } else {
                            _uiState.value =
                                    _uiState.value.copy(
                                            isPreloading = false,
                                            captchaRequired = response.captchaRequired,
                                            captchaInfo = response.captcha,
                                            execution = response.execution,
                                            error = null
                                    )
                            _loginForm.value = _loginForm.value.copy(captcha = "")
                        }
                    }
                    .onFailure { exception ->
                        _uiState.value =
                                _uiState.value.copy(
                                        isPreloading = false,
                                        captchaRequired = false,
                                        error = "加载登录状态失败: ${exception.message}"
                                )
                    }
        }
    }

    /** 刷新验证码：仅重新获取验证码，不触发整页加载 */
    fun refreshCaptcha() {
        viewModelScope.launch {
            // 设置验证码刷新中状态（不设置 isPreloading，避免整页刷新）
            _uiState.value = _uiState.value.copy(isRefreshingCaptcha = true, error = null)

            authService
                    .preloadLoginState()
                    .onSuccess { response ->
                        if (response.token != null && response.userData != null) {
                            // 自动登录成功
                            _uiState.value =
                                    _uiState.value.copy(
                                            isRefreshingCaptcha = false,
                                            isLoggedIn = true,
                                            userData = response.userData,
                                            token = response.token,
                                            captchaRequired = false,
                                            captchaInfo = null,
                                            execution = null,
                                            error = null
                                    )
                            _loginForm.value = LoginFormState()
                            loadUserInfo()
                        } else {
                            _uiState.value =
                                    _uiState.value.copy(
                                            isRefreshingCaptcha = false,
                                            captchaRequired = response.captchaRequired,
                                            captchaInfo = response.captcha,
                                            execution = response.execution,
                                            error = null
                                    )
                            _loginForm.value = _loginForm.value.copy(captcha = "")
                        }
                    }
                    .onFailure { exception ->
                        _uiState.value =
                                _uiState.value.copy(
                                        isRefreshingCaptcha = false,
                                        error = "刷新验证码失败: ${exception.message}"
                                )
                    }
        }
    }

    fun login() {
        val form = _loginForm.value
        val state = _uiState.value
        if (form.username.isBlank() || form.password.isBlank()) {
            _uiState.value = _uiState.value.copy(error = "用户名和密码不能为空")
            return
        }

        // 如果需要验证码但用户未填写
        if (state.captchaRequired && state.captchaInfo != null && form.captcha.isBlank()) {
            _uiState.value = _uiState.value.copy(error = "请输入验证码")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)

            // 使用 preload 时获取的 execution 和用户输入的验证码
            val captcha =
                    if (state.captchaRequired && form.captcha.isNotBlank()) form.captcha else null
            val execution = state.execution // 始终传递 execution（如果有的话）

            authService
                    .login(form.username, form.password, captcha, execution)
                    .onSuccess { loginResponse ->
                        _uiState.value =
                                _uiState.value.copy(
                                        isLoggedIn = true,
                                        isLoading = false,
                                        userData = loginResponse.user,
                                        token = loginResponse.token,
                                        captchaRequired = false,
                                        captchaInfo = null,
                                        execution = null
                                )

                        // 保存凭据设置
                        CredentialStore.setRememberPassword(form.rememberPassword)
                        CredentialStore.setAutoLogin(form.autoLogin)
                        if (form.rememberPassword) {
                            CredentialStore.saveCredentials(form.username, form.password)
                        }

                        // 登录成功后清空表单（如果不记住密码）
                        if (!form.rememberPassword) {
                            _loginForm.value = LoginFormState()
                        } else {
                            _loginForm.value = _loginForm.value.copy(captcha = "")
                        }
                        // 登录后加载用户信息
                        loadUserInfo()
                    }
                    .onFailure { exception ->
                        when (exception) {
                            is CaptchaRequiredClientException -> {
                                // 服务端返回需要验证码，更新 captchaInfo 和 execution
                                // 优先使用 base64Image
                                val updatedCaptchaInfo = exception.captcha

                                _uiState.value =
                                        _uiState.value.copy(
                                                isLoading = false,
                                                captchaRequired = true,
                                                captchaInfo = updatedCaptchaInfo,
                                                execution = exception.execution,
                                                error = null
                                        )
                                _loginForm.value = _loginForm.value.copy(captcha = "")
                            }
                            else -> {
                                _uiState.value =
                                        _uiState.value.copy(
                                                isLoading = false,
                                                error = exception.message ?: "登录失败",
                                                // 登录失败时清除 execution 和验证码状态，确保下次尝试时重新获取
                                                execution = null,
                                                captchaRequired = false,
                                                captchaInfo = null
                                        )
                            }
                        }
                    }
        }
    }

    /** 应用启动时的初始化，用于启动界面期间的自动登录 */
    fun initializeApp() {
        viewModelScope.launch {
            val storedToken = TokenStore.get()
            if (storedToken.isNullOrBlank()) {
                // 没有存储的 token，检查是否开启自动登录
                if (CredentialStore.isAutoLogin()) {
                    login()
                } else {
                    // 没有 token 且不自动登录，预加载登录状态
                    preloadLoginState()
                }
                return@launch
            }

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
                        TokenStore.clear()

                        // 会话恢复失败，检查是否开启自动登录
                        if (CredentialStore.isAutoLogin()) {
                            login()
                        } else {
                            // 不自动登录则预加载登录状态
                            preloadLoginState()
                        }
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
                        // 注销后预加载登录状态
                        preloadLoginState()
                    }
                    .onFailure { exception ->
                        // 登出失败也要清除本地状态
                        _uiState.value =
                                AuthUiState(
                                        error =
                                                "Logout completed with warnings: ${exception.message}"
                                )
                        _loginForm.value = LoginFormState()
                        preloadLoginState()
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
                        // 用户信息加载失败不提示
                        println("Failed to load user info: ${exception.message}")
                    }
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
        _loginForm.value = _loginForm.value.copy(captcha = "")
    }
}

data class AuthUiState(
        val isLoading: Boolean = false,
        val isPreloading: Boolean = false,
        val isRefreshingCaptcha: Boolean = false,
        val isLoggedIn: Boolean = false,
        val userData: UserData? = null,
        val userInfo: UserInfo? = null,
        val token: String? = null,
        val error: String? = null,
        val captchaRequired: Boolean = false,
        val captchaInfo: CaptchaInfo? = null,
        val execution: String? = null
)

data class LoginFormState(
        val username: String = "",
        val password: String = "",
        val captcha: String = "",
        val rememberPassword: Boolean = false,
        val autoLogin: Boolean = false
)
