package cn.edu.ubaa.ui.screens.bykc

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.BykcApi
import cn.edu.ubaa.model.dto.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** BYKC课程列表UI状态 */
data class BykcCoursesUiState(
        val isLoading: Boolean = false,
        val courses: List<BykcCourseDto> = emptyList(),
        val total: Int = 0,
        val error: String? = null,
        val profile: BykcUserProfileDto? = null
)

/** BYKC课程详情UI状态 */
data class BykcCourseDetailUiState(
        val isLoading: Boolean = false,
        val course: BykcCourseDetailDto? = null,
        val error: String? = null,
        val operationInProgress: Boolean = false,
        val operationMessage: String? = null
)

/** 已选BYKC课程UI状态 */
data class BykcChosenCoursesUiState(
        val isLoading: Boolean = false,
        val courses: List<BykcChosenCourseDto> = emptyList(),
        val error: String? = null
)

/** BYKC统计信息UI状态 */
data class BykcStatisticsUiState(
        val isLoading: Boolean = false,
        val statistics: BykcStatisticsDto? = null,
        val error: String? = null
)

/** 管理博雅课程相关状态与操作的ViewModel */
class BykcViewModel : ViewModel() {
        private val bykcApi = BykcApi()

        private val _coursesState = MutableStateFlow(BykcCoursesUiState())
        val coursesState: StateFlow<BykcCoursesUiState> = _coursesState.asStateFlow()

        private val _courseDetailState = MutableStateFlow(BykcCourseDetailUiState())
        val courseDetailState: StateFlow<BykcCourseDetailUiState> = _courseDetailState.asStateFlow()

        private val _chosenCoursesState = MutableStateFlow(BykcChosenCoursesUiState())
        val chosenCoursesState: StateFlow<BykcChosenCoursesUiState> =
                _chosenCoursesState.asStateFlow()

        private val _statisticsState = MutableStateFlow(BykcStatisticsUiState())
        val statisticsState: StateFlow<BykcStatisticsUiState> = _statisticsState.asStateFlow()

        init {
                loadProfile()
                loadCourses()
                loadChosenCourses()
                loadStatistics()
        }

        fun loadStatistics() {
                viewModelScope.launch {
                        _statisticsState.value =
                                _statisticsState.value.copy(isLoading = true, error = null)

                        bykcApi
                                .getStatistics()
                                .onSuccess { stats ->
                                        _statisticsState.value =
                                                _statisticsState.value.copy(
                                                        isLoading = false,
                                                        statistics = stats,
                                                        error = null
                                                )
                                }
                                .onFailure { exception ->
                                        _statisticsState.value =
                                                _statisticsState.value.copy(
                                                        isLoading = false,
                                                        error = exception.message ?: "加载统计信息失败"
                                                )
                                }
                }
        }

        fun loadProfile() {
                viewModelScope.launch {
                        bykcApi
                                .getProfile()
                                .onSuccess { profile ->
                                        _coursesState.value =
                                                _coursesState.value.copy(profile = profile)
                                }
                                .onFailure { exception ->
                                        // 个人信息可选，失败不提示
                                        println("Failed to load BYKC profile: ${exception.message}")
                                }
                }
        }

        fun loadCourses(page: Int = 1, size: Int = 200, includeExpired: Boolean = false) {
                viewModelScope.launch {
                        _coursesState.value =
                                _coursesState.value.copy(isLoading = true, error = null)

                        bykcApi
                                .getCourses(page, size, includeExpired)
                                .onSuccess { response ->
                                        _coursesState.value =
                                                _coursesState.value.copy(
                                                        isLoading = false,
                                                        courses = response.courses,
                                                        total = response.total,
                                                        error = null
                                                )
                                }
                                .onFailure { exception ->
                                        _coursesState.value =
                                                _coursesState.value.copy(
                                                        isLoading = false,
                                                        error = exception.message ?: "加载课程列表失败"
                                                )
                                }
                }
        }

        fun loadCourseDetail(courseId: Long) {
                viewModelScope.launch {
                        _courseDetailState.value = BykcCourseDetailUiState(isLoading = true)

                        bykcApi
                                .getCourseDetail(courseId)
                                .onSuccess { course ->
                                        _courseDetailState.value =
                                                BykcCourseDetailUiState(
                                                        isLoading = false,
                                                        course = course,
                                                        error = null
                                                )
                                }
                                .onFailure { exception ->
                                        _courseDetailState.value =
                                                BykcCourseDetailUiState(
                                                        isLoading = false,
                                                        error = exception.message ?: "加载课程详情失败"
                                                )
                                }
                }
        }

        fun loadChosenCourses() {
                viewModelScope.launch {
                        _chosenCoursesState.value =
                                _chosenCoursesState.value.copy(isLoading = true, error = null)

                        bykcApi
                                .getChosenCourses()
                                .onSuccess { courses ->
                                        _chosenCoursesState.value =
                                                _chosenCoursesState.value.copy(
                                                        isLoading = false,
                                                        courses = courses,
                                                        error = null
                                                )
                                }
                                .onFailure { exception ->
                                        _chosenCoursesState.value =
                                                _chosenCoursesState.value.copy(
                                                        isLoading = false,
                                                        error = exception.message ?: "加载已选课程失败"
                                                )
                                }
                }
        }

        fun selectCourse(courseId: Long, onComplete: (Boolean, String) -> Unit) {
                viewModelScope.launch {
                        _courseDetailState.value =
                                _courseDetailState.value.copy(operationInProgress = true)

                        bykcApi
                                .selectCourse(courseId)
                                .onSuccess { response ->
                                        _courseDetailState.value =
                                                _courseDetailState.value.copy(
                                                        operationInProgress = false,
                                                        operationMessage = response.message
                                                )
                                        onComplete(true, response.message)
                                        // 操作成功后刷新详情和已选课程
                                        loadCourseDetail(courseId)
                                        loadChosenCourses()
                                        loadCourses() // 刷新列表状态
                                }
                                .onFailure { exception ->
                                        val message = exception.message ?: "选课失败"
                                        _courseDetailState.value =
                                                _courseDetailState.value.copy(
                                                        operationInProgress = false,
                                                        operationMessage = message
                                                )
                                        onComplete(false, message)
                                }
                }
        }

        fun deselectCourse(courseId: Long, onComplete: (Boolean, String) -> Unit) {
                viewModelScope.launch {
                        _courseDetailState.value =
                                _courseDetailState.value.copy(operationInProgress = true)

                        bykcApi
                                .deselectCourse(courseId)
                                .onSuccess { response ->
                                        _courseDetailState.value =
                                                _courseDetailState.value.copy(
                                                        operationInProgress = false,
                                                        operationMessage = response.message
                                                )
                                        onComplete(true, response.message)
                                        // 操作成功后刷新详情和已选课程
                                        loadCourseDetail(courseId)
                                        loadChosenCourses()
                                        loadCourses() // 刷新列表状态
                                }
                                .onFailure { exception ->
                                        val message = exception.message ?: "退选失败"
                                        _courseDetailState.value =
                                                _courseDetailState.value.copy(
                                                        operationInProgress = false,
                                                        operationMessage = message
                                                )
                                        onComplete(false, message)
                                }
                }
        }

        fun signCourse(
                courseId: Long,
                lat: Double? = null,
                lng: Double? = null,
                signType: Int,
                onComplete: (Boolean, String) -> Unit
        ) {
                viewModelScope.launch {
                        _courseDetailState.value =
                                _courseDetailState.value.copy(operationInProgress = true)

                        bykcApi
                                .signCourse(courseId, lat, lng, signType)
                                .onSuccess { response ->
                                        _courseDetailState.value =
                                                _courseDetailState.value.copy(
                                                        operationInProgress = false,
                                                        operationMessage = response.message
                                                )
                                        onComplete(true, response.message)
                                        // 签到/签退后刷新详情和已选课程
                                        loadCourseDetail(courseId)
                                        loadChosenCourses()
                                }
                                .onFailure { exception ->
                                        val message = exception.message ?: "签到/签退失败"
                                        _courseDetailState.value =
                                                _courseDetailState.value.copy(
                                                        operationInProgress = false,
                                                        operationMessage = message
                                                )
                                        onComplete(false, message)
                                }
                }
        }

        fun clearOperationMessage() {
                _courseDetailState.value = _courseDetailState.value.copy(operationMessage = null)
        }
}
