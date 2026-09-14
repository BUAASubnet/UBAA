package cn.edu.ubaa.ui.screens.schedule

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.feature.GraduateScheduleLoadException
import cn.edu.ubaa.api.feature.ScheduleApi
import cn.edu.ubaa.model.dto.*
import cn.edu.ubaa.repository.ScheduleRepository
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 默认在线浏览；只有用户手动本地化才保存整学期。离线入口显式禁止联网。 */
class ScheduleViewModel(
    scheduleApi: ScheduleApi = ScheduleApi(),
    private val repository: ScheduleRepository = ScheduleRepository(scheduleApi),
    private val offlineOnly: Boolean = false,
) : ViewModel() {
  private var todayLoadedOnce = false
  private var scheduleLoadedOnce = false
  private var currentWeekLoadedOnce = false
  private var todayJob: Job? = null
  private var currentWeekJob: Job? = null
  private var scheduleJob: Job? = null
  private var weekJob: Job? = null
  private var updateJob: Job? = null
  private var generation = 0
  private val _uiState = MutableStateFlow(ScheduleUiState())
  val uiState: StateFlow<ScheduleUiState> = _uiState.asStateFlow()
  private val _todayScheduleState = MutableStateFlow(TodayScheduleState())
  val todayScheduleState: StateFlow<TodayScheduleState> = _todayScheduleState.asStateFlow()

  fun ensureTodayLoaded(forceRefresh: Boolean = false) {
    if (!forceRefresh && (todayLoadedOnce || todayJob?.isActive == true)) return
    loadTodaySchedule()
  }

  internal fun hasTodayLoaded(): Boolean = todayLoadedOnce

  internal fun hasCurrentWeekLoaded(): Boolean = currentWeekLoadedOnce

  fun ensureCurrentWeekLoaded(forceRefresh: Boolean = false) {
    if (!forceRefresh && (currentWeekLoadedOnce || currentWeekJob?.isActive == true)) return
    currentWeekJob?.cancel()
    val request = generation
    currentWeekJob =
        viewModelScope.launch(start = CoroutineStart.UNDISPATCHED) {
          repository.loadTerms(offlineOnly).onSuccess { terms ->
            val term = terms.firstOrNull { it.selected } ?: terms.firstOrNull() ?: return@onSuccess
            val weeks =
                repository.loadWeeks(term.itemCode, offlineOnly).getOrNull() ?: return@onSuccess
            if (generation != request) return@onSuccess
            _uiState.value = _uiState.value.copy(currentWeek = weeks.firstOrNull { it.curWeek })
            currentWeekLoadedOnce = true
          }
        }
  }

  fun ensureScheduleLoaded(forceRefresh: Boolean = false) {
    if (!forceRefresh && (scheduleLoadedOnce || scheduleJob?.isActive == true)) return
    loadTerms(forceRefresh)
  }

  fun resetLoadedState() {
    generation++
    listOf(todayJob, currentWeekJob, scheduleJob, weekJob, updateJob).forEach { it?.cancel() }
    todayLoadedOnce = false
    scheduleLoadedOnce = false
    currentWeekLoadedOnce = false
    _uiState.value = ScheduleUiState()
    _todayScheduleState.value = TodayScheduleState()
  }

  fun loadTodaySchedule() {
    todayJob?.cancel()
    val request = generation
    _todayScheduleState.value = _todayScheduleState.value.copy(isLoading = true, error = null)
    todayJob =
        viewModelScope.launch(start = CoroutineStart.UNDISPATCHED) {
          val result = repository.loadTodayClasses(offlineOnly)
          if (generation != request) return@launch
          todayLoadedOnce = result.isSuccess
          result
              .onSuccess { _todayScheduleState.value = TodayScheduleState(todayClasses = it) }
              .onFailure { _todayScheduleState.value = TodayScheduleState(error = it.message) }
        }
  }

  fun loadTerms(forceRefresh: Boolean = false) {
    scheduleJob?.cancel()
    weekJob?.cancel()
    val request = generation
    _uiState.value = _uiState.value.copy(isLoading = true, error = null, diagnosticResponse = null)
    scheduleJob =
        viewModelScope.launch(start = CoroutineStart.UNDISPATCHED) {
          val result = repository.loadTerms(offlineOnly)
          if (generation != request) return@launch
          result
              .onSuccess { terms ->
                val selected =
                    terms.firstOrNull { it.itemCode == _uiState.value.selectedTerm?.itemCode }
                        ?: terms.firstOrNull { it.selected }
                        ?: terms.firstOrNull()
                val changedTerm = selected?.itemCode != _uiState.value.selectedTerm?.itemCode
                _uiState.value =
                    _uiState.value.copy(
                        terms = terms,
                        selectedTerm = selected,
                        weeks = if (changedTerm) emptyList() else _uiState.value.weeks,
                        selectedWeek = if (changedTerm) null else _uiState.value.selectedWeek,
                        weeklySchedule = if (changedTerm) null else _uiState.value.weeklySchedule,
                        weekSchedules =
                            if (changedTerm) emptyMap() else _uiState.value.weekSchedules,
                    )
                if (selected != null) fetchWeeks(selected, forceRefresh)
                else {
                  scheduleLoadedOnce = true
                  _uiState.value =
                      _uiState.value.copy(
                          isLoading = false,
                          weeks = emptyList(),
                          weekSchedules = emptyMap(),
                          selectedWeek = null,
                          weeklySchedule = null,
                          updatedAt = null,
                      )
                }
              }
              .onFailure { showLoadError(it) }
        }
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
    scheduleJob?.cancel()
    weekJob?.cancel()
    _uiState.value = _uiState.value.copy(isLoading = true, error = null)
    scheduleJob = viewModelScope.launch(start = CoroutineStart.UNDISPATCHED) { fetchWeeks(term) }
  }

  private suspend fun fetchWeeks(term: Term, forceRefresh: Boolean = false) {
    val request = generation
    val result = repository.loadWeeks(term.itemCode, offlineOnly)
    if (generation != request || _uiState.value.selectedTerm?.itemCode != term.itemCode) return
    result
        .onSuccess { weeks ->
          val selected =
              weeks.firstOrNull {
                it.serialNumber == _uiState.value.selectedWeek?.serialNumber &&
                    it.term == _uiState.value.selectedWeek?.term
              } ?: weeks.firstOrNull { it.curWeek } ?: weeks.firstOrNull()
          _uiState.value =
              _uiState.value.copy(
                  weeks = weeks,
                  weekSchedules =
                      if (offlineOnly) repository.schedules(term.itemCode).getOrDefault(emptyMap())
                      else if (forceRefresh) emptyMap() else _uiState.value.weekSchedules,
                  selectedWeek = selected,
                  weeklySchedule = null,
                  updatedAt = repository.updatedAt(term.itemCode),
                  error = null,
                  isLoading = false,
              )
          scheduleLoadedOnce = true
          selected?.let { loadWeeklySchedule(term, it) }
        }
        .onFailure { showLoadError(it) }
  }

  fun selectWeek(week: Week) {
    _uiState.value = _uiState.value.copy(selectedWeek = week)
    _uiState.value.selectedTerm?.let { loadWeeklySchedule(it, week) }
  }

  fun loadWeeklySchedule(term: Term, week: Week) {
    weekJob?.cancel()
    val cached = _uiState.value.weekSchedules[week.serialNumber]
    _uiState.value =
        _uiState.value.copy(weeklySchedule = cached, isLoading = cached == null, error = null)
    if (cached != null) return
    val request = generation
    weekJob =
        viewModelScope.launch(start = CoroutineStart.UNDISPATCHED) {
          val result = repository.loadWeekly(term.itemCode, week.serialNumber, offlineOnly)
          if (
              generation != request ||
                  _uiState.value.selectedTerm?.itemCode != term.itemCode ||
                  _uiState.value.selectedWeek?.serialNumber != week.serialNumber
          )
              return@launch
          result
              .onSuccess {
                scheduleLoadedOnce = true
                _uiState.value =
                    _uiState.value.copy(
                        weeklySchedule = it,
                        weekSchedules = _uiState.value.weekSchedules + (week.serialNumber to it),
                        isLoading = false,
                        error = null,
                    )
              }
              .onFailure { showLoadError(it) }
        }
  }

  private fun showLoadError(error: Throwable) {
    scheduleLoadedOnce = false
    _uiState.value =
        _uiState.value.copy(
            isLoading = false,
            error = error.message,
            diagnosticResponse = (error.cause as? GraduateScheduleLoadException)?.responseBody,
        )
  }

  fun updateSchedule(currentTerm: Boolean = false) {
    if (offlineOnly || _uiState.value.isUpdating) return
    scheduleJob?.cancel()
    weekJob?.cancel()
    val code = if (currentTerm) null else _uiState.value.selectedTerm?.itemCode
    val request = generation
    _uiState.value =
        _uiState.value.copy(
            isUpdating = true,
            isLoading = false,
            error = null,
            diagnosticResponse = null,
        )
    updateJob =
        viewModelScope.launch {
          try {
            val result = repository.update(code)
            if (generation != request) return@launch
            result
                .onSuccess { snapshot ->
                  val selectedWeek =
                      snapshot.weeks.firstOrNull {
                        it.term == _uiState.value.selectedWeek?.term &&
                            it.serialNumber == _uiState.value.selectedWeek?.serialNumber
                      } ?: snapshot.weeks.firstOrNull { it.curWeek } ?: snapshot.weeks.firstOrNull()
                  _uiState.value =
                      _uiState.value.copy(
                          terms = snapshot.terms,
                          selectedTerm = snapshot.terms.first { it.itemCode == snapshot.termCode },
                          weeks = snapshot.weeks,
                          selectedWeek = selectedWeek,
                          weekSchedules = snapshot.schedules,
                          weeklySchedule = snapshot.schedules[selectedWeek?.serialNumber],
                          updatedAt = snapshot.updatedAt,
                      )
                  scheduleLoadedOnce = true
                  loadTodaySchedule()
                  ensureCurrentWeekLoaded(forceRefresh = true)
                }
                .onFailure {
                  _uiState.value =
                      _uiState.value.copy(
                          diagnosticResponse =
                              (it.cause as? GraduateScheduleLoadException)?.responseBody,
                          error =
                              "本地化失败：${it.message}" +
                                  if (_uiState.value.updatedAt != null) "。已保存的课表仍可查看。" else "",
                      )
                }
          } finally {
            if (generation == request) _uiState.value = _uiState.value.copy(isUpdating = false)
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
