package cn.edu.ubaa.ui.screens.signin

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.SigninApi
import cn.edu.ubaa.model.dto.SigninClassDto
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 课堂签到模块 UI 状态。 */
data class SigninUiState(
        val isLoading: Boolean = false,
        val classes: List<SigninClassDto> = emptyList(),
        val error: String? = null,
        /** 签到操作的结果提示（如“签到成功”）。 */
        val signinResult: String? = null,
        /** 当前正在执行签到的课程 ID（用于显示局部加载状态）。 */
        val signingInCourseId: String? = null
)

/**
 * 管理课堂签到功能的 ViewModel。
 */
class SigninViewModel : ViewModel() {
    private val signinApi = SigninApi()

    private val _uiState = MutableStateFlow(SigninUiState())
    /** 签到状态流。 */
    val uiState: StateFlow<SigninUiState> = _uiState.asStateFlow()

    init {
        loadTodayClasses()
    }

    /** 拉取今日所有可签到的课堂。 */
    fun loadTodayClasses() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            signinApi.getTodayClasses()
                    .onSuccess { _uiState.value = _uiState.value.copy(isLoading = false, classes = it.data) }
                    .onFailure { _uiState.value = _uiState.value.copy(isLoading = false, error = it.message ?: "加载课程失败") }
        }
    }

    /** 提交签到请求。 */
    fun performSignin(courseId: String) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(signingInCourseId = courseId, signinResult = null)
            signinApi.performSignin(courseId)
                    .onSuccess { response ->
                        _uiState.value = _uiState.value.copy(
                                signingInCourseId = null,
                                signinResult = if (response.success) "签到成功" else "签到失败: ${response.message}"
                        )
                        if (response.success) loadTodayClasses()
                    }
                    .onFailure { _uiState.value = _uiState.value.copy(signingInCourseId = null, signinResult = "签到异常: ${it.message}") }
        }
    }

    /** 清除当前的签到结果提示。 */
    fun clearSigninResult() { _uiState.value = _uiState.value.copy(signinResult = null) }
}