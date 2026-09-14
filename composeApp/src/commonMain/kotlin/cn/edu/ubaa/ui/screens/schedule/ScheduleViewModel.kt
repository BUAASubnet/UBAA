package cn.edu.ubaa.ui.screens.schedule

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.feature.GraduateScheduleLoadException
import cn.edu.ubaa.api.feature.ScheduleApi
import cn.edu.ubaa.model.dto.*
import cn.edu.ubaa.repository.ScheduleRepository
import cn.edu.ubaa.repository.ScheduleStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 浏览与首页仅读取本地课表；仅 updateSchedule 联网导入整个学期。 */
class ScheduleViewModel(
    scheduleApi: ScheduleApi = ScheduleApi(),
    private val repository: ScheduleRepository = ScheduleRepository(scheduleApi),
) : ViewModel() {
  private var todayLoadedOnce = false
  private var scheduleLoadedOnce = false
  private var currentWeekLoadedOnce = false
  private val _uiState = MutableStateFlow(ScheduleUiState())
  val uiState: StateFlow<ScheduleUiState> = _uiState.asStateFlow()
  private val _todayScheduleState = MutableStateFlow(TodayScheduleState())
  val todayScheduleState: StateFlow<TodayScheduleState> = _todayScheduleState.asStateFlow()

  fun ensureTodayLoaded(forceRefresh: Boolean = false) = loadTodaySchedule()

  internal fun hasTodayLoaded(): Boolean = todayLoadedOnce

  internal fun hasCurrentWeekLoaded(): Boolean = currentWeekLoadedOnce

  fun ensureCurrentWeekLoaded(forceRefresh: Boolean = false) {
    repository.terms().onSuccess { terms ->
      val term = terms.firstOrNull { it.selected } ?: terms.firstOrNull() ?: return@onSuccess
      repository.weeks(term.itemCode).onSuccess { weeks ->
        _uiState.value = _uiState.value.copy(currentWeek = weeks.firstOrNull { it.curWeek })
        currentWeekLoadedOnce = true
      }
    }
  }

  fun ensureScheduleLoaded(forceRefresh: Boolean = false) {
    if (!forceRefresh && scheduleLoadedOnce) return
    loadTerms()
  }

  fun resetLoadedState() {
    todayLoadedOnce = false
    scheduleLoadedOnce = false
    currentWeekLoadedOnce = false
    _uiState.value = ScheduleUiState()
    _todayScheduleState.value = TodayScheduleState()
  }

  fun loadTodaySchedule() {
    todayLoadedOnce = true
    repository
        .todayClasses()
        .onSuccess { _todayScheduleState.value = TodayScheduleState(todayClasses = it) }
        .onFailure { _todayScheduleState.value = TodayScheduleState(error = it.message) }
  }

  fun loadTerms(forceRefresh: Boolean = false) {
    scheduleLoadedOnce = true
    repository
        .terms()
        .onSuccess { terms ->
          val selected =
              terms.firstOrNull { it.itemCode == _uiState.value.selectedTerm?.itemCode }
                  ?: terms.firstOrNull { it.selected }
                  ?: terms.firstOrNull()
          _uiState.value = _uiState.value.copy(terms = terms, selectedTerm = selected, error = null)
          selected?.let(::loadWeeks)
        }
        .onFailure { _uiState.value = _uiState.value.copy(error = it.message) }
  }

  fun selectTerm(term: Term) {
    if (_uiState.value.isUpdating) return
    _uiState.value =
        _uiState.value.copy(
            selectedTerm = term,
            selectedWeek = null,
            weeklySchedule = null,
            weeks = emptyList(),
            weekSchedules = emptyMap(),
            diagnosticResponse = null,
            updatedAt = repository.updatedAt(term.itemCode),
        )
    loadWeeks(term)
  }

  fun loadWeeks(term: Term) {
    repository
        .weeks(term.itemCode)
        .onSuccess { weeks ->
          val selected =
              weeks.firstOrNull {
                it.serialNumber == _uiState.value.selectedWeek?.serialNumber &&
                    it.term == _uiState.value.selectedWeek?.term
              } ?: weeks.firstOrNull { it.curWeek } ?: weeks.firstOrNull()
          _uiState.value =
              _uiState.value.copy(
                  weeks = weeks,
                  weekSchedules = repository.schedules(term.itemCode).getOrDefault(emptyMap()),
                  selectedWeek = selected,
                  weeklySchedule = null,
                  updatedAt = repository.updatedAt(term.itemCode),
                  error = null,
              )
          selected?.let { loadWeeklySchedule(term, it) }
        }
        .onFailure { _uiState.value = _uiState.value.copy(error = it.message) }
  }

  fun selectWeek(week: Week) {
    _uiState.value = _uiState.value.copy(selectedWeek = week)
    _uiState.value.selectedTerm?.let { loadWeeklySchedule(it, week) }
  }

  fun loadWeeklySchedule(term: Term, week: Week) {
    repository
        .weekly(term.itemCode, week.serialNumber)
        .onSuccess { _uiState.value = _uiState.value.copy(weeklySchedule = it, error = null) }
        .onFailure {
          _uiState.value = _uiState.value.copy(weeklySchedule = null, error = it.message)
        }
  }

  fun updateSchedule(currentTerm: Boolean = false) {
    if (_uiState.value.isUpdating) return
    val code = if (currentTerm) null else _uiState.value.selectedTerm?.itemCode
    val owner = ScheduleStore.account()
    _uiState.value = _uiState.value.copy(isUpdating = true, error = null, diagnosticResponse = null)
    viewModelScope.launch {
      try {
        repository
            .update(code)
            .onSuccess { snapshot ->
              _uiState.value =
                  _uiState.value.copy(
                      selectedTerm = snapshot.terms.first { it.itemCode == snapshot.termCode }
                  )
              loadTerms()
              loadTodaySchedule()
              ensureCurrentWeekLoaded()
            }
            .onFailure {
              if (ScheduleStore.account() != owner) return@onFailure
              _uiState.value =
                  _uiState.value.copy(
                      diagnosticResponse =
                          (it.cause as? GraduateScheduleLoadException)?.responseBody,
                      error =
                          "更新失败：${it.message}" +
                              if (_uiState.value.updatedAt != null) "。已保存的课表仍可查看。" else "",
                  )
            }
      } finally {
        _uiState.value = _uiState.value.copy(isUpdating = false)
      }
    }
  }

  fun clearError() {
    _uiState.value = _uiState.value.copy(error = null, diagnosticResponse = null)
    _todayScheduleState.value = _todayScheduleState.value.copy(error = null)
  }
}

/** 周课表界面 UI 状态。 */
data class ScheduleUiState(
    val isLoading: Boolean = false,
    val isUpdating: Boolean = false,
    val updatedAt: String? = null,
    val terms: List<Term> = emptyList(),
    val weeks: List<Week> = emptyList(),
    val currentWeek: Week? = null,
    val selectedTerm: Term? = null,
    val selectedWeek: Week? = null,
    val weeklySchedule: WeeklySchedule? = null,
    val weekSchedules: Map<Int, WeeklySchedule> = emptyMap(),
    val error: String? = null,
    val diagnosticResponse: String? = null,
)

/** 今日摘要界面 UI 状态。 */
data class TodayScheduleState(
    val isLoading: Boolean = false,
    val todayClasses: List<TodayClass> = emptyList(),
    val error: String? = null,
)
