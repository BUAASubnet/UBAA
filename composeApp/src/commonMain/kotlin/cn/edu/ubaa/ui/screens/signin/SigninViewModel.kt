package cn.edu.ubaa.ui.screens.signin

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.SigninApi
import cn.edu.ubaa.model.dto.SigninClassDto
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SigninUiState(
        val isLoading: Boolean = false,
        val classes: List<SigninClassDto> = emptyList(),
        val error: String? = null,
        val signinResult: String? = null,
        val signingInCourseId: String? = null
)

class SigninViewModel : ViewModel() {
    private val signinApi = SigninApi()

    private val _uiState = MutableStateFlow(SigninUiState())
    val uiState: StateFlow<SigninUiState> = _uiState.asStateFlow()

    init {
        loadTodayClasses()
    }

    fun loadTodayClasses() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            signinApi
                    .getTodayClasses()
                    .onSuccess { response ->
                        _uiState.value =
                                _uiState.value.copy(
                                        isLoading = false,
                                        classes = response.data,
                                        error = null
                                )
                    }
                    .onFailure { exception ->
                        _uiState.value =
                                _uiState.value.copy(
                                        isLoading = false,
                                        error = exception.message ?: "加载课程失败"
                                )
                    }
        }
    }

    fun performSignin(courseId: String) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(signingInCourseId = courseId, signinResult = null)
            signinApi
                    .performSignin(courseId)
                    .onSuccess { response ->
                        _uiState.value =
                                _uiState.value.copy(
                                        signingInCourseId = null,
                                        signinResult =
                                                if (response.success) "签到成功"
                                                else "签到失败: ${response.message}"
                                )
                        if (response.success) {
                            loadTodayClasses() // 刷新状态
                        }
                    }
                    .onFailure { exception ->
                        _uiState.value =
                                _uiState.value.copy(
                                        signingInCourseId = null,
                                        signinResult = "签到异常: ${exception.message}"
                                )
                    }
        }
    }

    fun clearSigninResult() {
        _uiState.value = _uiState.value.copy(signinResult = null)
    }
}
