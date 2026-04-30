package cn.edu.ubaa.ui.screens.grade

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.GradeApi
import cn.edu.ubaa.model.dto.GradeData
import cn.edu.ubaa.model.dto.Term
import cn.edu.ubaa.repository.GlobalTermRepository
import cn.edu.ubaa.repository.TermRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class GradeViewModel(
    private val gradeApi: GradeApi = GradeApi(),
    private val termRepository: TermRepository = GlobalTermRepository.instance,
) : ViewModel() {
  private var loadedOnce = false

  private val _uiState = MutableStateFlow(GradeUiState())
  val uiState: StateFlow<GradeUiState> = _uiState.asStateFlow()

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
            selectedTerm?.let { loadGrades(it.itemCode) }
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
      loadGrades(term.itemCode)
    }
  }

  private fun loadGrades(termCode: String) {
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isLoading = true, error = null)

      gradeApi
          .getGrades(termCode)
          .onSuccess { gradeData ->
            _uiState.value =
                _uiState.value.copy(isLoading = false, gradeData = gradeData, error = null)
          }
          .onFailure { exception ->
            _uiState.value =
                _uiState.value.copy(isLoading = false, error = exception.message ?: "加载成绩信息失败")
          }
    }
  }
}

data class GradeUiState(
    val isLoading: Boolean = false,
    val terms: List<Term> = emptyList(),
    val selectedTerm: Term? = null,
    val gradeData: GradeData? = null,
    val error: String? = null,
)
