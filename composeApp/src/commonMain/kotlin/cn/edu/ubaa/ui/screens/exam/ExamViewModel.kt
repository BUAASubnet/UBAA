package cn.edu.ubaa.ui.screens.exam

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.feature.ScheduleApi
import cn.edu.ubaa.model.dto.ExamArrangementData
import cn.edu.ubaa.model.dto.Term
import cn.edu.ubaa.repository.GlobalTermRepository
import cn.edu.ubaa.repository.TermRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ExamViewModel(
    private val scheduleApi: ScheduleApi = ScheduleApi(),
    private val termRepository: TermRepository = GlobalTermRepository.instance,
) : ViewModel() {
  private var loadedOnce = false

  private val _uiState = MutableStateFlow(ExamUiState())
  val uiState: StateFlow<ExamUiState> = _uiState.asStateFlow()

  fun ensureLoaded(forceRefresh: Boolean = false) {
    if (!forceRefresh && loadedOnce) return
    loadTerms(forceRefresh)
  }

  fun loadTerms(forceRefresh: Boolean = false) {
    loadedOnce = true
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isLoading = true, error = null)

      termRepository
          .getTerms(forceRefresh)
          .onSuccess { terms ->
            val selectedTerm = terms.find { it.selected } ?: terms.firstOrNull()
            _uiState.value =
                _uiState.value.copy(
                    isLoading = false,
                    terms = terms,
                    selectedTerm = selectedTerm,
                    error = null,
                )
            selectedTerm?.let { loadExams(it.itemCode) }
          }
          .onFailure { exception ->
            _uiState.value =
                _uiState.value.copy(isLoading = false, error = exception.message ?: "加载学期信息失败")
          }
    }
  }

  fun selectTerm(term: Term) {
    if (_uiState.value.selectedTerm != term) {
      _uiState.value = _uiState.value.copy(selectedTerm = term)
      loadExams(term.itemCode)
    }
  }

  private fun loadExams(termCode: String) {
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isLoading = true, error = null)

      scheduleApi
          .getExamArrangement(termCode)
          .onSuccess { examData ->
            _uiState.value =
                _uiState.value.copy(isLoading = false, examData = examData, error = null)
          }
          .onFailure { exception ->
            _uiState.value =
                _uiState.value.copy(isLoading = false, error = exception.message ?: "加载考试信息失败")
          }
    }
  }
}

data class ExamUiState(
    val isLoading: Boolean = false,
    val terms: List<Term> = emptyList(),
    val selectedTerm: Term? = null,
    val examData: ExamArrangementData? = null,
    val error: String? = null,
)
