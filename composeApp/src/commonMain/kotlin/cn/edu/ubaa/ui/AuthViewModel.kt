package cn.edu.ubaa.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.AuthService
import cn.edu.ubaa.api.UserService
import cn.edu.ubaa.model.dto.LoginResponse
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * ViewModel managing authentication and user state
 */
class AuthViewModel : ViewModel() {
    private val authService = AuthService()
    private val userService = UserService()
    
    private val _uiState = MutableStateFlow(AuthUiState())
    val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()
    
    private val _loginForm = MutableStateFlow(LoginFormState())
    val loginForm: StateFlow<LoginFormState> = _loginForm.asStateFlow()
    
    fun updateUsername(username: String) {
        _loginForm.value = _loginForm.value.copy(username = username)
    }
    
    fun updatePassword(password: String) {
        _loginForm.value = _loginForm.value.copy(password = password)
    }
    
    fun login() {
        val form = _loginForm.value
        if (form.username.isBlank() || form.password.isBlank()) {
            _uiState.value = _uiState.value.copy(error = "用户名和密码不能为空")
            return
        }
        
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            
            authService.login(form.username, form.password)
                .onSuccess { loginResponse ->
                    _uiState.value = _uiState.value.copy(
                        isLoggedIn = true,
                        isLoading = false,
                        userData = loginResponse.user,
                        token = loginResponse.token
                    )
                    // Clear the password for security
                    _loginForm.value = _loginForm.value.copy(password = "")
                    // Load user info
                    loadUserInfo()
                }
                .onFailure { exception ->
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        error = exception.message ?: "登录失败"
                    )
                }
        }
    }
    
    fun logout() {
        authService.logout()
        _uiState.value = AuthUiState()
        _loginForm.value = LoginFormState()
    }
    
    private fun loadUserInfo() {
        viewModelScope.launch {
            userService.getUserInfo()
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
        _uiState.value = _uiState.value.copy(error = null)
    }
}

data class AuthUiState(
    val isLoading: Boolean = false,
    val isLoggedIn: Boolean = false,
    val userData: UserData? = null,
    val userInfo: UserInfo? = null,
    val token: String? = null,
    val error: String? = null
)

data class LoginFormState(
    val username: String = "",
    val password: String = ""
)