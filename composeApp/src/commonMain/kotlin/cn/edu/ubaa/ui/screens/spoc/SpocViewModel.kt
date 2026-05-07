package cn.edu.ubaa.ui.screens.spoc

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.feature.SpocApi
import cn.edu.ubaa.model.dto.SpocAssignmentDetailDto
import cn.edu.ubaa.model.dto.SpocAssignmentSummaryDto
import cn.edu.ubaa.model.dto.SpocAssignmentsResponse
import cn.edu.ubaa.model.dto.SpocSubmissionStatus
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

enum class SpocSortField {
  START_TIME,
  DUE_TIME,
}

data class SpocUiState(
    val isLoading: Boolean = false,
    val isRefreshing: Boolean = false,
    val assignmentsResponse: SpocAssignmentsResponse? = null,
    val visibleAssignments: List<SpocAssignmentSummaryDto> = emptyList(),
    val error: String? = null,
    val isDetailLoading: Boolean = false,
    val assignmentDetail: SpocAssignmentDetailDto? = null,
    val detailError: String? = null,
    val searchQuery: String = "",
    val sortField: SpocSortField = SpocSortField.DUE_TIME,
    val sortAscending: Boolean = true,
    val showExpired: Boolean = false,
    val showOnlyUnsubmitted: Boolean = false,
)

/** SPOC 作业查询模块 ViewModel。 */
@OptIn(ExperimentalTime::class)
class SpocViewModel(
    private val spocApi: SpocApi = SpocApi(),
    private val nowProvider: () -> LocalDateTime = {
      Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
    },
) : ViewModel() {
  private var assignmentsLoadedOnce = false
  private val _uiState = MutableStateFlow(SpocUiState())
  val uiState: StateFlow<SpocUiState> = _uiState.asStateFlow()

  fun ensureAssignmentsLoaded(forceRefresh: Boolean = false) {
    if (!forceRefresh && assignmentsLoadedOnce) return
    loadAssignments(refresh = forceRefresh)
  }

  internal fun hasAssignmentsLoaded(): Boolean = assignmentsLoadedOnce

  fun loadAssignments(refresh: Boolean = false) {
    assignmentsLoadedOnce = true
    viewModelScope.launch {
      val hasExistingData = _uiState.value.assignmentsResponse != null
      _uiState.value =
          _uiState.value.copy(
              isLoading = !refresh || !hasExistingData,
              isRefreshing = refresh,
              error = null,
          )

      spocApi
          .getAssignments()
          .onSuccess { response ->
            val currentState = _uiState.value
            _uiState.value =
                currentState.copy(
                    isLoading = false,
                    isRefreshing = false,
                    assignmentsResponse = response,
                    visibleAssignments =
                        buildVisibleAssignments(response.assignments, currentState),
                    error = null,
                )
          }
          .onFailure { exception ->
            _uiState.value =
                _uiState.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    error = exception.message ?: "加载 SPOC 作业失败",
                )
          }
    }
  }

  fun setSearchQuery(query: String) {
    updateVisibleAssignments { copy(searchQuery = query) }
  }

  fun setSortField(field: SpocSortField) {
    updateVisibleAssignments { copy(sortField = field) }
  }

  fun toggleSortDirection() {
    updateVisibleAssignments { copy(sortAscending = !sortAscending) }
  }

  fun setShowExpired(enabled: Boolean) {
    updateVisibleAssignments { copy(showExpired = enabled) }
  }

  fun setShowOnlyUnsubmitted(enabled: Boolean) {
    updateVisibleAssignments { copy(showOnlyUnsubmitted = enabled) }
  }

  fun loadAssignmentDetail(assignmentId: String) {
    viewModelScope.launch {
      _uiState.value =
          _uiState.value.copy(
              isDetailLoading = true,
              assignmentDetail = null,
              detailError = null,
          )

      spocApi
          .getAssignmentDetail(assignmentId)
          .onSuccess { detail ->
            _uiState.value =
                _uiState.value.copy(
                    isDetailLoading = false,
                    assignmentDetail = detail,
                    detailError = null,
                )
          }
          .onFailure { exception ->
            _uiState.value =
                _uiState.value.copy(
                    isDetailLoading = false,
                    assignmentDetail = null,
                    detailError = exception.message ?: "加载作业详情失败",
                )
          }
    }
  }

  fun clearAssignmentDetail() {
    _uiState.value =
        _uiState.value.copy(
            isDetailLoading = false,
            assignmentDetail = null,
            detailError = null,
        )
  }

  private fun updateVisibleAssignments(transform: SpocUiState.() -> SpocUiState) {
    val nextState = _uiState.value.transform()
    _uiState.value =
        nextState.copy(
            visibleAssignments =
                buildVisibleAssignments(
                    nextState.assignmentsResponse?.assignments.orEmpty(),
                    nextState,
                )
        )
  }

  private fun buildVisibleAssignments(
      assignments: List<SpocAssignmentSummaryDto>,
      state: SpocUiState,
  ): List<SpocAssignmentSummaryDto> {
    val query = state.searchQuery.trim().lowercase()

    return assignments
        .asSequence()
        .filter { assignment ->
          query.isBlank() ||
              assignment.courseName.lowercase().contains(query) ||
              assignment.title.lowercase().contains(query)
        }
        .filter { assignment ->
          !state.showOnlyUnsubmitted ||
              assignment.submissionStatus == SpocSubmissionStatus.UNSUBMITTED
        }
        .filter { assignment -> state.showExpired || !isExpired(assignment) }
        .sortedWith(compareAssignments(state.sortField, state.sortAscending))
        .toList()
  }

  private fun compareAssignments(
      sortField: SpocSortField,
      ascending: Boolean,
  ): Comparator<SpocAssignmentSummaryDto> {
    val comparator =
        Comparator<SpocAssignmentSummaryDto> { left, right ->
          val leftTime = parseDateTime(resolveSortValue(left, sortField))
          val rightTime = parseDateTime(resolveSortValue(right, sortField))
          when {
            leftTime == null && rightTime == null ->
                compareValuesBy(left, right, { it.courseName }, { it.title })
            leftTime == null -> 1
            rightTime == null -> -1
            else -> {
              val timeComparison = leftTime.compareTo(rightTime)
              if (timeComparison != 0) {
                timeComparison
              } else {
                compareValuesBy(left, right, { it.courseName }, { it.title })
              }
            }
          }
        }
    return if (ascending) comparator else comparator.reversed()
  }

  private fun resolveSortValue(
      assignment: SpocAssignmentSummaryDto,
      sortField: SpocSortField,
  ): String? =
      when (sortField) {
        SpocSortField.START_TIME -> assignment.startTime
        SpocSortField.DUE_TIME -> assignment.dueTime
      }

  private fun isExpired(assignment: SpocAssignmentSummaryDto): Boolean {
    val dueTime = parseDateTime(assignment.dueTime) ?: return false
    return dueTime < nowProvider()
  }

  private fun parseDateTime(value: String?): LocalDateTime? {
    val normalized = value?.trim()?.takeIf { it.isNotEmpty() }?.replace(" ", "T") ?: return null
    return runCatching { LocalDateTime.parse(normalized) }.getOrNull()
  }
}
