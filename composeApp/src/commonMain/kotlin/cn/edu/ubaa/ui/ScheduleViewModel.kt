package cn.edu.ubaa.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.ScheduleService
import cn.edu.ubaa.model.dto.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * ViewModel managing schedule-related state and operations
 */
class ScheduleViewModel : ViewModel() {
    private val scheduleService = ScheduleService()
    
    private val _uiState = MutableStateFlow(ScheduleUiState())
    val uiState: StateFlow<ScheduleUiState> = _uiState.asStateFlow()
    
    private val _todayScheduleState = MutableStateFlow(TodayScheduleState())
    val todayScheduleState: StateFlow<TodayScheduleState> = _todayScheduleState.asStateFlow()
    
    init {
        loadTodaySchedule()
        loadTerms()
    }
    
    fun loadTodaySchedule() {
        viewModelScope.launch {
            _todayScheduleState.value = _todayScheduleState.value.copy(isLoading = true, error = null)
            
            scheduleService.getTodaySchedule()
                .onSuccess { todayClasses ->
                    _todayScheduleState.value = _todayScheduleState.value.copy(
                        isLoading = false,
                        todayClasses = todayClasses,
                        error = null
                    )
                }
                .onFailure { exception ->
                    _todayScheduleState.value = _todayScheduleState.value.copy(
                        isLoading = false,
                        error = exception.message ?: "加载今日课表失败"
                    )
                }
        }
    }
    
    fun loadTerms() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            
            scheduleService.getTerms()
                .onSuccess { terms ->
                    val selectedTerm = terms.find { it.selected } ?: terms.firstOrNull()
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        terms = terms,
                        selectedTerm = selectedTerm,
                        error = null
                    )
                    // Load weeks for selected term
                    selectedTerm?.let { loadWeeks(it) }
                }
                .onFailure { exception ->
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        error = exception.message ?: "加载学期信息失败"
                    )
                }
        }
    }
    
    fun selectTerm(term: Term) {
        _uiState.value = _uiState.value.copy(selectedTerm = term, selectedWeek = null, weeklySchedule = null)
        loadWeeks(term)
    }
    
    fun loadWeeks(term: Term) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            
            scheduleService.getWeeks(term.itemCode)
                .onSuccess { weeks ->
                    val currentWeek = weeks.find { it.curWeek } ?: weeks.firstOrNull()
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        weeks = weeks,
                        selectedWeek = currentWeek,
                        error = null
                    )
                    // Load schedule for current week
                    currentWeek?.let { loadWeeklySchedule(term, it) }
                }
                .onFailure { exception ->
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        error = exception.message ?: "加载周信息失败"
                    )
                }
        }
    }
    
    fun selectWeek(week: Week) {
        _uiState.value = _uiState.value.copy(selectedWeek = week)
        val selectedTerm = _uiState.value.selectedTerm
        if (selectedTerm != null) {
            loadWeeklySchedule(selectedTerm, week)
        }
    }
    
    fun loadWeeklySchedule(term: Term, week: Week) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            
            scheduleService.getWeeklySchedule(term.itemCode, week.serialNumber)
                .onSuccess { schedule ->
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        weeklySchedule = schedule,
                        error = null
                    )
                }
                .onFailure { exception ->
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        error = exception.message ?: "加载课程表失败"
                    )
                }
        }
    }
    
    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
        _todayScheduleState.value = _todayScheduleState.value.copy(error = null)
    }
}

data class ScheduleUiState(
    val isLoading: Boolean = false,
    val terms: List<Term> = emptyList(),
    val weeks: List<Week> = emptyList(),
    val selectedTerm: Term? = null,
    val selectedWeek: Week? = null,
    val weeklySchedule: WeeklySchedule? = null,
    val error: String? = null
)

data class TodayScheduleState(
    val isLoading: Boolean = false,
    val todayClasses: List<TodayClass> = emptyList(),
    val error: String? = null
)