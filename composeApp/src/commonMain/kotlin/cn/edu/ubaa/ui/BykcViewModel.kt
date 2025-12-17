package cn.edu.ubaa.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.BykcService
import cn.edu.ubaa.model.dto.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** UI state for BYKC course list */
data class BykcCoursesUiState(
        val isLoading: Boolean = false,
        val courses: List<BykcCourseDto> = emptyList(),
        val total: Int = 0,
        val error: String? = null,
        val profile: BykcUserProfileDto? = null
)

/** UI state for BYKC course detail */
data class BykcCourseDetailUiState(
        val isLoading: Boolean = false,
        val course: BykcCourseDetailDto? = null,
        val error: String? = null,
        val operationInProgress: Boolean = false,
        val operationMessage: String? = null
)

/** UI state for chosen BYKC courses */
data class BykcChosenCoursesUiState(
        val isLoading: Boolean = false,
        val courses: List<BykcChosenCourseDto> = emptyList(),
        val error: String? = null
)

/** ViewModel managing BYKC (博雅课程) related state and operations */
class BykcViewModel : ViewModel() {
        private val bykcService = BykcService()

        private val _coursesState = MutableStateFlow(BykcCoursesUiState())
        val coursesState: StateFlow<BykcCoursesUiState> = _coursesState.asStateFlow()

        private val _courseDetailState = MutableStateFlow(BykcCourseDetailUiState())
        val courseDetailState: StateFlow<BykcCourseDetailUiState> = _courseDetailState.asStateFlow()

        private val _chosenCoursesState = MutableStateFlow(BykcChosenCoursesUiState())
        val chosenCoursesState: StateFlow<BykcChosenCoursesUiState> =
                _chosenCoursesState.asStateFlow()

        init {
                loadProfile()
                loadCourses()
                loadChosenCourses()
        }

        fun loadProfile() {
                viewModelScope.launch {
                        bykcService
                                .getProfile()
                                .onSuccess { profile ->
                                        _coursesState.value =
                                                _coursesState.value.copy(profile = profile)
                                }
                                .onFailure { exception ->
                                        // Profile is optional, don't show error for this
                                        println("Failed to load BYKC profile: ${exception.message}")
                                }
                }
        }

        fun loadCourses(page: Int = 1, size: Int = 200, includeExpired: Boolean = false) {
                viewModelScope.launch {
                        _coursesState.value =
                                _coursesState.value.copy(isLoading = true, error = null)

                        bykcService
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

                        bykcService
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

                        bykcService
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

                        bykcService
                                .selectCourse(courseId)
                                .onSuccess { response ->
                                        _courseDetailState.value =
                                                _courseDetailState.value.copy(
                                                        operationInProgress = false,
                                                        operationMessage = response.message
                                                )
                                        onComplete(true, response.message)
                                        // Refresh course detail and chosen courses
                                        loadCourseDetail(courseId)
                                        loadChosenCourses()
                                        loadCourses() // Refresh list to update status
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

                        bykcService
                                .deselectCourse(courseId)
                                .onSuccess { response ->
                                        _courseDetailState.value =
                                                _courseDetailState.value.copy(
                                                        operationInProgress = false,
                                                        operationMessage = response.message
                                                )
                                        onComplete(true, response.message)
                                        // Refresh course detail and chosen courses
                                        loadCourseDetail(courseId)
                                        loadChosenCourses()
                                        loadCourses() // Refresh list to update status
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

                        bykcService
                                .signCourse(courseId, lat, lng, signType)
                                .onSuccess { response ->
                                        _courseDetailState.value =
                                                _courseDetailState.value.copy(
                                                        operationInProgress = false,
                                                        operationMessage = response.message
                                                )
                                        onComplete(true, response.message)
                                        // Refresh course detail and chosen courses
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
