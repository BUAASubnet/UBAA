package cn.edu.ubaa.ui.screens.schedule

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.ScheduleApi
import cn.edu.ubaa.model.dto.*
import cn.edu.ubaa.repository.TermRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 课程表相关业务逻辑的 ViewModel。 负责拉取学期列表、周次列表、周课表详情以及今日课表摘要。 */
class ScheduleViewModel : ViewModel() {
  private val scheduleApi = ScheduleApi()
  private val termRepository = TermRepository()

  private val _uiState = MutableStateFlow(ScheduleUiState())
  /** 周课表选择与展示的状态流。 */
  val uiState: StateFlow<ScheduleUiState> = _uiState.asStateFlow()

  private val _todayScheduleState = MutableStateFlow(TodayScheduleState())
  /** 今日课表简要摘要的状态流。 */
  val todayScheduleState: StateFlow<TodayScheduleState> = _todayScheduleState.asStateFlow()

  init {
    loadTodaySchedule()
    loadTerms()
  }

  /** 加载今日的课程安排摘要。 */
  fun loadTodaySchedule() {
    viewModelScope.launch {
      _todayScheduleState.value = _todayScheduleState.value.copy(isLoading = true, error = null)
      scheduleApi
        .getTodaySchedule()
        .onSuccess {
          _todayScheduleState.value =
            _todayScheduleState.value.copy(isLoading = false, todayClasses = it)
        }
        .onFailure {
          _todayScheduleState.value =
            _todayScheduleState.value.copy(isLoading = false, error = it.message ?: "加载今日课表失败")
        }
    }
  }

  /** 加载学期列表。 */
  fun loadTerms() {
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isLoading = true, error = null)
      termRepository
        .getTerms()
        .onSuccess { terms ->
          val selectedTerm = terms.find { it.selected } ?: terms.firstOrNull()
          _uiState.value =
            _uiState.value.copy(isLoading = false, terms = terms, selectedTerm = selectedTerm)
          selectedTerm?.let { loadWeeks(it) }
        }
        .onFailure {
          _uiState.value = _uiState.value.copy(isLoading = false, error = it.message ?: "加载学期信息失败")
        }
    }
  }

  /** 切换选中的学期。 */
  fun selectTerm(term: Term) {
    _uiState.value =
      _uiState.value.copy(selectedTerm = term, selectedWeek = null, weeklySchedule = null)
    loadWeeks(term)
  }

  /** 加载指定学期的教学周次。 */
  fun loadWeeks(term: Term) {
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isLoading = true, error = null)
      scheduleApi
        .getWeeks(term.itemCode)
        .onSuccess { weeks ->
          val currentWeek = weeks.find { it.curWeek } ?: weeks.firstOrNull()
          _uiState.value =
            _uiState.value.copy(isLoading = false, weeks = weeks, selectedWeek = currentWeek)
          currentWeek?.let { loadWeeklySchedule(term, it) }
        }
        .onFailure {
          _uiState.value = _uiState.value.copy(isLoading = false, error = it.message ?: "加载周信息失败")
        }
    }
  }

  /** 切换选中的周次。 */
  fun selectWeek(week: Week) {
    _uiState.value = _uiState.value.copy(selectedWeek = week)
    _uiState.value.selectedTerm?.let { loadWeeklySchedule(it, week) }
  }

  /** 加载指定学期和周次的完整排课表。 */
  fun loadWeeklySchedule(term: Term, week: Week) {
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isLoading = true, error = null)
      scheduleApi
        .getWeeklySchedule(term.itemCode, week.serialNumber)
        .onSuccess { _uiState.value = _uiState.value.copy(isLoading = false, weeklySchedule = it) }
        .onFailure {
          _uiState.value = _uiState.value.copy(isLoading = false, error = it.message ?: "加载课程表失败")
        }
    }
  }

  /** 清空错误提示。 */
  fun clearError() {
    _uiState.value = _uiState.value.copy(error = null)
    _todayScheduleState.value = _todayScheduleState.value.copy(error = null)
  }
}

/** 周课表界面 UI 状态。 */
data class ScheduleUiState(
  val isLoading: Boolean = false,
  val terms: List<Term> = emptyList(),
  val weeks: List<Week> = emptyList(),
  val selectedTerm: Term? = null,
  val selectedWeek: Week? = null,
  val weeklySchedule: WeeklySchedule? = null,
  val error: String? = null,
)

/** 今日摘要界面 UI 状态。 */
data class TodayScheduleState(
  val isLoading: Boolean = false,
  val todayClasses: List<TodayClass> = emptyList(),
  val error: String? = null,
)
