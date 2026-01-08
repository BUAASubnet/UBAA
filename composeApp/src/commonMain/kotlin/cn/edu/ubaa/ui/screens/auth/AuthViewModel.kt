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

/** 身份认证与用户信息管理的 ViewModel。 负责处理登录流程（含预加载和验证码）、自动登录逻辑、用户信息加载以及会话状态同步。 */
class AuthViewModel : ViewModel() {
  private val authService = AuthService()
  private val userService = UserService()

  private val _uiState = MutableStateFlow(AuthUiState())
  /** 整体认证状态流。 */
  val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()

  private val _loginForm = MutableStateFlow(LoginFormState())
  /** 登录表单输入状态流。 */
  val loginForm: StateFlow<LoginFormState> = _loginForm.asStateFlow()

  init {
    loadSavedCredentials()
  }

  /** 从本地持久化存储加载保存的凭据。 */
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
          autoLogin = auto,
        )
    } else {
      _loginForm.value = _loginForm.value.copy(rememberPassword = false, autoLogin = false)
    }
  }

  /** 更新表单中的用户名。 */
  fun updateUsername(username: String) {
    _loginForm.value = _loginForm.value.copy(username = username)
  }

  /** 更新表单中的密码。 */
  fun updatePassword(password: String) {
    _loginForm.value = _loginForm.value.copy(password = password)
  }

  /** 更新表单中的验证码。 */
  fun updateCaptcha(captcha: String) {
    _loginForm.value = _loginForm.value.copy(captcha = captcha)
  }

  /** 更新“记住密码”勾选状态。 */
  fun updateRememberPassword(enabled: Boolean) {
    _loginForm.value = _loginForm.value.copy(rememberPassword = enabled)
    if (!enabled) _loginForm.value = _loginForm.value.copy(autoLogin = false)
  }

  /** 更新“自动登录”勾选状态。 */
  fun updateAutoLogin(enabled: Boolean) {
    _loginForm.value = _loginForm.value.copy(autoLogin = enabled)
    if (enabled) _loginForm.value = _loginForm.value.copy(rememberPassword = true)
  }

  /** 预加载登录状态。 访问服务端探测当前 SSO 是否已登录，并获取登录所需的执行标识（execution）或验证码。 */
  fun preloadLoginState() {
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isPreloading = true, error = null)
      authService
        .preloadLoginState()
        .onSuccess { response ->
          if (response.token != null && response.userData != null) {
            // SSO 已登录，执行自动登录逻辑
            _uiState.value =
              _uiState.value.copy(
                isPreloading = false,
                isLoggedIn = true,
                userData = response.userData,
                token = response.token,
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
              )
            _loginForm.value = _loginForm.value.copy(captcha = "")
          }
        }
        .onFailure {
          _uiState.value =
            _uiState.value.copy(isPreloading = false, error = "加载登录状态失败: ${it.message}")
        }
    }
  }

  /** 仅刷新验证码图片，不重置其他表单状态。 */
  fun refreshCaptcha() {
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isRefreshingCaptcha = true, error = null)
      authService
        .preloadLoginState()
        .onSuccess { response ->
          _uiState.value =
            _uiState.value.copy(
              isRefreshingCaptcha = false,
              captchaRequired = response.captchaRequired,
              captchaInfo = response.captcha,
              execution = response.execution,
            )
        }
        .onFailure {
          _uiState.value =
            _uiState.value.copy(isRefreshingCaptcha = false, error = "刷新验证码失败: ${it.message}")
        }
    }
  }

  /** 执行登录提交。 */
  fun login() {
    val form = _loginForm.value
    val state = _uiState.value
    if (form.username.isBlank() || form.password.isBlank()) {
      _uiState.value = _uiState.value.copy(error = "用户名和密码不能为空")
      return
    }
    if (state.captchaRequired && form.captcha.isBlank()) {
      _uiState.value = _uiState.value.copy(error = "请输入验证码")
      return
    }

    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isLoading = true, error = null)
      val captcha = if (state.captchaRequired) form.captcha else null
      authService
        .login(form.username, form.password, captcha, state.execution)
        .onSuccess { loginResponse ->
          _uiState.value =
            _uiState.value.copy(
              isLoggedIn = true,
              isLoading = false,
              userData = loginResponse.user,
              token = loginResponse.token,
            )
          CredentialStore.setRememberPassword(form.rememberPassword)
          CredentialStore.setAutoLogin(form.autoLogin)
          if (form.rememberPassword) CredentialStore.saveCredentials(form.username, form.password)
          if (!form.rememberPassword) _loginForm.value = LoginFormState()
          loadUserInfo()
        }
        .onFailure { exception ->
          if (exception is CaptchaRequiredClientException) {
            _uiState.value =
              _uiState.value.copy(
                isLoading = false,
                captchaRequired = true,
                captchaInfo = exception.captcha,
                execution = exception.execution,
              )
          } else {
            _uiState.value =
              _uiState.value.copy(isLoading = false, error = exception.message ?: "登录失败")
          }
        }
    }
  }

  /** 应用全局初始化入口。 用于检查本地 Token 是否有效，若失效则根据设置决定跳转登录页或尝试自动登录。 */
  fun initializeApp() {
    viewModelScope.launch {
      val storedToken = TokenStore.get()
      if (storedToken.isNullOrBlank()) {
        if (CredentialStore.isAutoLogin()) login() else preloadLoginState()
        return@launch
      }

      authService.applyStoredToken()
      _uiState.value = _uiState.value.copy(isLoading = true)
      authService
        .getAuthStatus()
        .onSuccess { status ->
          _uiState.value =
            _uiState.value.copy(
              isLoggedIn = true,
              isLoading = false,
              userData = status.user,
              token = storedToken,
            )
          loadUserInfo()
        }
        .onFailure {
          _uiState.value = _uiState.value.copy(isLoading = false)
          TokenStore.clear()
          if (CredentialStore.isAutoLogin()) login() else preloadLoginState()
        }
    }
  }

  /** 注销登录，清理所有本地状态。 */
  fun logout() {
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isLoading = true)
      authService
        .logout()
        .onSuccess {
          _uiState.value = AuthUiState()
          _loginForm.value = LoginFormState()
          preloadLoginState()
        }
        .onFailure {
          _uiState.value = AuthUiState(error = "注销完成但有警告: ${it.message}")
          preloadLoginState()
        }
    }
  }

  /** 加载用户的详细档案信息。 */
  private fun loadUserInfo() {
    viewModelScope.launch {
      userService.getUserInfo().onSuccess { info ->
        _uiState.value = _uiState.value.copy(userInfo = info)
      }
    }
  }

  /** 清除当前的错误提示。 */
  fun clearError() {
    _uiState.value = _uiState.value.copy(error = null)
  }
}

/** 认证模块 UI 状态模型。 */
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
  val execution: String? = null,
)

/** 登录表单本地交互状态模型。 */
data class LoginFormState(
  val username: String = "",
  val password: String = "",
  val captcha: String = "",
  val rememberPassword: Boolean = false,
  val autoLogin: Boolean = false,
)
