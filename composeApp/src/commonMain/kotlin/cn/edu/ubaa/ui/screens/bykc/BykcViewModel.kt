package cn.edu.ubaa.ui.screens.bykc

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.BykcApi
import cn.edu.ubaa.model.dto.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 博雅课程列表 UI 状态。 */
data class BykcCoursesUiState(
        val isLoading: Boolean = false,
        val isLoadingMore: Boolean = false,
        val courses: List<BykcCourseDto> = emptyList(),
        val total: Int = 0,
        val totalPages: Int = 0,
        val currentPage: Int = 0,
        val pageSize: Int = 20,
        val hasMorePages: Boolean = true,
        val error: String? = null,
        val profile: BykcUserProfileDto? = null
)

/** 博雅课程详情 UI 状态。 */
data class BykcCourseDetailUiState(
        val isLoading: Boolean = false,
        val course: BykcCourseDetailDto? = null,
        val error: String? = null,
        /** 是否正在执行操作（如选课或签到）。 */
        val operationInProgress: Boolean = false,
        /** 操作执行结果的消息提示。 */
        val operationMessage: String? = null
)

/** 已选博雅课程列表 UI 状态。 */
data class BykcChosenCoursesUiState(
        val isLoading: Boolean = false,
        val courses: List<BykcChosenCourseDto> = emptyList(),
        val error: String? = null
)

/** 博雅修读统计 UI 状态。 */
data class BykcStatisticsUiState(
        val isLoading: Boolean = false,
        val statistics: BykcStatisticsDto? = null,
        val error: String? = null
)

/**
 * 管理博雅课程功能模块状态的 ViewModel。
 * 负责课程浏览、选课退选、签到以及统计数据的拉取。
 */
class BykcViewModel : ViewModel() {
        private val bykcApi = BykcApi()

        private val _coursesState = MutableStateFlow(BykcCoursesUiState())
        /** 课程列表状态流。 */
        val coursesState: StateFlow<BykcCoursesUiState> = _coursesState.asStateFlow()

        private val _courseDetailState = MutableStateFlow(BykcCourseDetailUiState())
        /** 课程详情状态流。 */
        val courseDetailState: StateFlow<BykcCourseDetailUiState> = _courseDetailState.asStateFlow()

        private val _chosenCoursesState = MutableStateFlow(BykcChosenCoursesUiState())
        /** 已选课程状态流。 */
        val chosenCoursesState: StateFlow<BykcChosenCoursesUiState> = _chosenCoursesState.asStateFlow()

        private val _statisticsState = MutableStateFlow(BykcStatisticsUiState())
        /** 统计数据状态流。 */
        val statisticsState: StateFlow<BykcStatisticsUiState> = _statisticsState.asStateFlow()

        init {
                loadProfile()
                loadCourses()
                loadChosenCourses()
                loadStatistics()
        }

        /** 加载用户的博雅修读次数统计。 */
        fun loadStatistics() {
                viewModelScope.launch {
                        _statisticsState.value = _statisticsState.value.copy(isLoading = true, error = null)
                        bykcApi.getStatistics()
                                .onSuccess { _statisticsState.value = _statisticsState.value.copy(isLoading = false, statistics = it) }
                                .onFailure { _statisticsState.value = _statisticsState.value.copy(isLoading = false, error = it.message ?: "加载统计信息失败") }
                }
        }

        /** 加载用户的博雅基本资料。 */
        fun loadProfile() {
                viewModelScope.launch {
                        bykcApi.getProfile().onSuccess { _coursesState.value = _coursesState.value.copy(profile = it) }
                }
        }

        /**
         * 加载（或重新加载）博雅课程列表。
         * @param page 页码。
         * @param size 每页数量。
         * @param includeExpired 是否包含已过期课程。
         */
        fun loadCourses(page: Int = 1, size: Int = 20, includeExpired: Boolean = false) {
                viewModelScope.launch {
                        _coursesState.value = _coursesState.value.copy(isLoading = true, error = null)
                        bykcApi.getCourses(page, size, includeExpired)
                                .onSuccess { resp ->
                                        _coursesState.value = _coursesState.value.copy(
                                                isLoading = false, courses = resp.courses, total = resp.total,
                                                totalPages = resp.totalPages, currentPage = resp.currentPage,
                                                hasMorePages = resp.currentPage < resp.totalPages
                                        )
                                }
                                .onFailure { _coursesState.value = _coursesState.value.copy(isLoading = false, error = it.message ?: "加载课程列表失败") }
                }
        }

        /** 分页加载更多课程。 */
        fun loadMoreCourses(includeExpired: Boolean = false) {
                val current = _coursesState.value
                if (current.isLoadingMore || !current.hasMorePages) return
                viewModelScope.launch {
                        _coursesState.value = current.copy(isLoadingMore = true)
                        bykcApi.getCourses(current.currentPage + 1, current.pageSize, includeExpired)
                                .onSuccess { resp ->
                                        _coursesState.value = current.copy(
                                                isLoadingMore = false, courses = current.courses + resp.courses,
                                                currentPage = resp.currentPage, hasMorePages = resp.currentPage < resp.totalPages
                                        )
                                }
                                .onFailure { _coursesState.value = current.copy(isLoadingMore = false, error = it.message ?: "加载更多失败") }
                }
        }

        /** 获取指定课程的详细数据。 */
        fun loadCourseDetail(courseId: Long) {
                viewModelScope.launch {
                        _courseDetailState.value = BykcCourseDetailUiState(isLoading = true)
                        bykcApi.getCourseDetail(courseId)
                                .onSuccess { _courseDetailState.value = BykcCourseDetailUiState(isLoading = false, course = it) }
                                .onFailure { _courseDetailState.value = BykcCourseDetailUiState(isLoading = false, error = it.message ?: "详情加载失败") }
                }
        }

        /** 获取当前已报名的课程列表。 */
        fun loadChosenCourses() {
                viewModelScope.launch {
                        _chosenCoursesState.value = _chosenCoursesState.value.copy(isLoading = true, error = null)
                        bykcApi.getChosenCourses()
                                .onSuccess { _chosenCoursesState.value = _chosenCoursesState.value.copy(isLoading = false, courses = it) }
                                .onFailure { _chosenCoursesState.value = _chosenCoursesState.value.copy(isLoading = false, error = it.message ?: "加载已选失败") }
                }
        }

        /** 选课操作。成功后会自动刷新关联的状态。 */
        fun selectCourse(courseId: Long, onComplete: (Boolean, String) -> Unit) {
                viewModelScope.launch {
                        _courseDetailState.value = _courseDetailState.value.copy(operationInProgress = true)
                        bykcApi.selectCourse(courseId)
                                .onSuccess {
                                        _courseDetailState.value = _courseDetailState.value.copy(operationInProgress = false, operationMessage = it.message)
                                        onComplete(true, it.message); loadCourseDetail(courseId); loadChosenCourses(); loadCourses()
                                }
                                .onFailure {
                                        _courseDetailState.value = _courseDetailState.value.copy(operationInProgress = false, operationMessage = it.message)
                                        onComplete(false, it.message ?: "选课失败")
                                }
                }
        }

        /** 退选操作。 */
        fun deselectCourse(courseId: Long, onComplete: (Boolean, String) -> Unit) {
                viewModelScope.launch {
                        _courseDetailState.value = _courseDetailState.value.copy(operationInProgress = true)
                        bykcApi.deselectCourse(courseId)
                                .onSuccess {
                                        _courseDetailState.value = _courseDetailState.value.copy(operationInProgress = false, operationMessage = it.message)
                                        onComplete(true, it.message); loadCourseDetail(courseId); loadChosenCourses(); loadCourses()
                                }
                                .onFailure {
                                        _courseDetailState.value = _courseDetailState.value.copy(operationInProgress = false, operationMessage = it.message)
                                        onComplete(false, it.message ?: "退选失败")
                                }
                }
        }

        /** 签到/签退操作。 */
        fun signCourse(courseId: Long, lat: Double?, lng: Double?, signType: Int, onComplete: (Boolean, String) -> Unit) {
                viewModelScope.launch {
                        _courseDetailState.value = _courseDetailState.value.copy(operationInProgress = true)
                        bykcApi.signCourse(courseId, lat, lng, signType)
                                .onSuccess {
                                        _courseDetailState.value = _courseDetailState.value.copy(operationInProgress = false, operationMessage = it.message)
                                        onComplete(true, it.message); loadCourseDetail(courseId); loadChosenCourses()
                                }
                                .onFailure {
                                        _courseDetailState.value = _courseDetailState.value.copy(operationInProgress = false, operationMessage = it.message)
                                        onComplete(false, it.message ?: "签到失败")
                                }
                }
        }

        /** 清除当前的操作提示消息。 */
        fun clearOperationMessage() { _courseDetailState.value = _courseDetailState.value.copy(operationMessage = null) }
}