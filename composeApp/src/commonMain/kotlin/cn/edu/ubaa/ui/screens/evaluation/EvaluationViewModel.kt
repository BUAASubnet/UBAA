package cn.edu.ubaa.ui.screens.evaluation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.ApiClient
import cn.edu.ubaa.api.EvaluationService
import cn.edu.ubaa.model.evaluation.EvaluationCourse
import cn.edu.ubaa.model.evaluation.EvaluationProgress
import cn.edu.ubaa.model.evaluation.EvaluationResult
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 自动评教业务逻辑 ViewModel。 负责管理待评教课程列表、处理用户选择以及执行分批次评教提交。 */
class EvaluationViewModel : ViewModel() {
    private val evaluationService = EvaluationService(ApiClient())

    private val _uiState = MutableStateFlow(EvaluationUiState())
    /** 评教界面的 UI 状态流。 */
    val uiState: StateFlow<EvaluationUiState> = _uiState.asStateFlow()

    init {
        loadPendingCourses()
    }

    /** 加载当前用户的评教课程列表（包括已评教和未评教）。 未评教课程默认全选，已评教课程不可选。 */
    fun loadPendingCourses() {
        viewModelScope.launch {
            _uiState.value =
                    _uiState.value.copy(
                            isLoading = true,
                            error = null,
                            submissionResults = emptyList()
                    )
            val response = evaluationService.getAllEvaluations()
            val courses = response.courses
            _uiState.value =
                    _uiState.value.copy(
                            isLoading = false,
                            // 未评教的课程默认选中，已评教的课程不选中（且不可选）
                            courses = courses.map { it to !it.isEvaluated },
                            progress = response.progress,
                            error =
                                    if (courses.isEmpty() && !uiState.value.isLoading) "暂无评教课程"
                                    else null
                    )
        }
    }

    /**
     * 切换指定课程的选中状态。 注意：已评教的课程不可切换。
     * @param course 需要切换状态的课程对象。
     */
    fun toggleCourseSelection(course: EvaluationCourse) {
        // 已评教的课程不可选中
        if (course.isEvaluated) return

        val currentCourses = _uiState.value.courses.toMutableList()
        val index = currentCourses.indexOfFirst { it.first.id == course.id }
        if (index != -1) {
            val (c, selected) = currentCourses[index]
            currentCourses[index] = c to !selected
            _uiState.value = _uiState.value.copy(courses = currentCourses)
        }
    }

    /** 提交选中课程的评教任务。 采用逐个提交的方式，以便在前端展示精确的进度条。 */
    fun submitEvaluations() {
        val selectedCourses =
                _uiState.value.courses.filter { it.second && !it.first.isEvaluated }.map {
                    it.first
                }
        if (selectedCourses.isEmpty()) return

        viewModelScope.launch {
            _uiState.value =
                    _uiState.value.copy(
                            isSubmitting = true,
                            submissionResults = emptyList(),
                            progressCurrent = 0,
                            progressTotal = selectedCourses.size
                    )

            val results = mutableListOf<EvaluationResult>()

            selectedCourses.forEachIndexed { index, course ->
                // 逐个提交以更新进度
                val batchResult = evaluationService.submitEvaluations(listOf(course))
                results.addAll(batchResult)

                _uiState.value =
                        _uiState.value.copy(
                                progressCurrent = index + 1,
                                submissionResults = results.toList() // 实时更新结果列表（可选）
                        )
            }

            _uiState.value = _uiState.value.copy(isSubmitting = false, submissionResults = results)
        }
    }

    /** 清空评教结果并重置部分状态。 通常在用户关闭结果对话框后调用。 */
    fun clearResults() {
        _uiState.value =
                _uiState.value.copy(
                        submissionResults = emptyList(),
                        progressCurrent = 0,
                        progressTotal = 0
                )
    }
}

/**
 * 自动评教界面的 UI 状态数据类。
 *
 * @property isLoading 是否正在加载课程列表。
 * @property isSubmitting 是否正在执行评教提交。
 * @property courses 课程列表及其选中状态。
 * @property progress 评教进度信息。
 * @property submissionResults 评教提交后的结果列表。
 * @property progressCurrent 当前已处理的课程数量。
 * @property progressTotal 需要处理的总课程数量。
 * @property error 错误信息提示。
 */
data class EvaluationUiState(
        val isLoading: Boolean = false,
        val isSubmitting: Boolean = false,
        val courses: List<Pair<EvaluationCourse, Boolean>> = emptyList(),
        val progress: EvaluationProgress = EvaluationProgress(0, 0, 0),
        val submissionResults: List<EvaluationResult> = emptyList(),
        val progressCurrent: Int = 0,
        val progressTotal: Int = 0,
        val error: String? = null
)
