package cn.edu.ubaa.ui.screens.grade

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.feature.GradeApi
import cn.edu.ubaa.model.dto.GradeData
import cn.edu.ubaa.model.dto.Term
import cn.edu.ubaa.repository.GlobalTermRepository
import cn.edu.ubaa.repository.TermRepository
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

internal interface GradeDataSource {
  suspend fun getGrades(termCode: String): Result<GradeData>
}

internal interface GradeTermsSource {
  suspend fun getTerms(forceRefresh: Boolean): Result<List<Term>>
}

private class ApiGradeDataSource(private val gradeApi: GradeApi = GradeApi()) : GradeDataSource {
  override suspend fun getGrades(termCode: String): Result<GradeData> = gradeApi.getGrades(termCode)
}

private class RepositoryGradeTermsSource(
    private val termRepository: TermRepository = GlobalTermRepository.instance
) : GradeTermsSource {
  override suspend fun getTerms(forceRefresh: Boolean): Result<List<Term>> =
      termRepository.getTerms(forceRefresh)
}

class GradeViewModel
internal constructor(
    private val gradeSource: GradeDataSource = ApiGradeDataSource(),
    private val termsSource: GradeTermsSource = RepositoryGradeTermsSource(),
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
      val hasExistingContent = _uiState.value.gradeData != null
      _uiState.value =
          _uiState.value.copy(
              isLoading = !hasExistingContent,
              isRefreshing = forceRefresh && hasExistingContent,
              isSummaryLoading = false,
              gradeData = if (hasExistingContent) _uiState.value.gradeData else null,
              termGrades = if (hasExistingContent) _uiState.value.termGrades else emptyMap(),
              error = null,
          )

      termsSource
          .getTerms(forceRefresh)
          .onSuccess { terms ->
            val selectedTerm = terms.find { it.selected } ?: terms.firstOrNull()
            _uiState.value =
                _uiState.value.copy(
                    isLoading = selectedTerm != null && _uiState.value.gradeData == null,
                    terms = terms,
                    selectedTerm = selectedTerm,
                    error = null,
                )
            if (selectedTerm == null) {
              _uiState.value = _uiState.value.copy(isLoading = false, isRefreshing = false)
            } else {
              loadAllGrades(terms, selectedTerm)
            }
          }
          .onFailure { exception ->
            _uiState.value =
                _uiState.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    error = exception.message ?: "加载学期信息失败",
                )
          }
    }
  }

  fun selectTerm(term: Term) {
    if (_uiState.value.selectedTerm != term) {
      val cachedGradeData = _uiState.value.termGrades[term.itemCode]
      _uiState.value =
          _uiState.value.copy(
              selectedTerm = term,
              gradeData = cachedGradeData,
              isLoading = cachedGradeData == null,
              error = null,
          )
      if (cachedGradeData == null) {
        loadGrades(term.itemCode)
      }
    }
  }

  private suspend fun loadAllGrades(terms: List<Term>, selectedTerm: Term) = coroutineScope {
    _uiState.value = _uiState.value.copy(isSummaryLoading = terms.size > 1)
    val orderedTerms =
        listOf(selectedTerm) + terms.filterNot { it.itemCode == selectedTerm.itemCode }
    val requests =
        orderedTerms.map { term -> term to async { gradeSource.getGrades(term.itemCode) } }
    val selectedRequest = requests.first()
    val remainingRequests = requests.drop(1)

    val selectedResult = selectedRequest.second.await()
    val selectedGradeData = selectedResult.getOrNull()
    if (selectedGradeData == null) {
      remainingRequests.forEach { (_, request) -> request.cancel() }
      val exception = selectedResult.exceptionOrNull()
      val isSelectedTerm = selectedRequest.first.itemCode == _uiState.value.selectedTerm?.itemCode
      _uiState.value =
          if (isSelectedTerm) {
            _uiState.value.copy(
                isLoading = false,
                isRefreshing = false,
                isSummaryLoading = false,
                error = exception?.message ?: "加载成绩信息失败",
            )
          } else {
            _uiState.value.copy(isRefreshing = false, isSummaryLoading = false)
          }
      return@coroutineScope
    }

    val isSelectedTerm = selectedRequest.first.itemCode == _uiState.value.selectedTerm?.itemCode
    _uiState.value =
        _uiState.value.copy(
            isLoading = if (isSelectedTerm) false else _uiState.value.isLoading,
            isRefreshing = false,
            isSummaryLoading = remainingRequests.isNotEmpty(),
            gradeData = if (isSelectedTerm) selectedGradeData else _uiState.value.gradeData,
            termGrades =
                _uiState.value.termGrades + (selectedRequest.first.itemCode to selectedGradeData),
            error = null,
        )

    remainingRequests.forEachIndexed { index, (term, request) ->
      val result = request.await()
      val gradeData = result.getOrNull()
      if (gradeData == null) {
        val isCurrentSelectedTerm = term.itemCode == _uiState.value.selectedTerm?.itemCode
        _uiState.value =
            if (isCurrentSelectedTerm) {
              val exception = result.exceptionOrNull()
              _uiState.value.copy(
                  isLoading = false,
                  isRefreshing = false,
                  isSummaryLoading = false,
                  error = exception?.message ?: "加载成绩信息失败",
              )
            } else {
              _uiState.value.copy(isRefreshing = false, isSummaryLoading = false)
            }
        return@coroutineScope
      }

      val isCurrentSelectedTerm = term.itemCode == _uiState.value.selectedTerm?.itemCode
      _uiState.value =
          _uiState.value.copy(
              isLoading = if (isCurrentSelectedTerm) false else _uiState.value.isLoading,
              isRefreshing = false,
              isSummaryLoading = index < remainingRequests.lastIndex,
              gradeData = if (isCurrentSelectedTerm) gradeData else _uiState.value.gradeData,
              termGrades = _uiState.value.termGrades + (term.itemCode to gradeData),
              error = null,
          )
    }
    _uiState.value = _uiState.value.copy(isRefreshing = false, isSummaryLoading = false)
  }

  private fun loadGrades(termCode: String) {
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isLoading = true, error = null)

      gradeSource
          .getGrades(termCode)
          .onSuccess { gradeData ->
            _uiState.value =
                _uiState.value.copy(
                    isLoading = false,
                    gradeData = gradeData,
                    termGrades = _uiState.value.termGrades + (termCode to gradeData),
                    error = null,
                )
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
    val isRefreshing: Boolean = false,
    val isSummaryLoading: Boolean = false,
    val terms: List<Term> = emptyList(),
    val selectedTerm: Term? = null,
    val gradeData: GradeData? = null,
    val termGrades: Map<String, GradeData> = emptyMap(),
    val error: String? = null,
)
