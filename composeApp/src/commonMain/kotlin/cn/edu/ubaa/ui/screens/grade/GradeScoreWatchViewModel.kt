package cn.edu.ubaa.ui.screens.grade

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.storage.GradeScoreCacheStore
import cn.edu.ubaa.api.storage.StoredGradeScoreCache
import cn.edu.ubaa.api.storage.StoredGradeScoreEntry
import cn.edu.ubaa.model.dto.Grade
import cn.edu.ubaa.model.dto.GradeData
import cn.edu.ubaa.model.dto.Term
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

internal interface GradeScoreCache {
  fun get(userKey: String): StoredGradeScoreCache?

  fun save(userKey: String, cache: StoredGradeScoreCache)
}

internal object PersistentGradeScoreCache : GradeScoreCache {
  override fun get(userKey: String): StoredGradeScoreCache? = GradeScoreCacheStore.get(userKey)

  override fun save(userKey: String, cache: StoredGradeScoreCache) {
    GradeScoreCacheStore.save(userKey, cache)
  }
}

class GradeScoreWatchViewModel
internal constructor(
    private val userKey: String,
    private val gradeSource: GradeDataSource = ApiGradeDataSource(),
    private val termsSource: GradeTermsSource = RepositoryGradeTermsSource(),
    private val cache: GradeScoreCache = PersistentGradeScoreCache,
) : ViewModel() {
  private var loadedOnce = false

  private val _uiState = MutableStateFlow(GradeScoreWatchUiState())
  val uiState: StateFlow<GradeScoreWatchUiState> = _uiState.asStateFlow()

  fun hasChecked(): Boolean = loadedOnce

  fun ensureChecked(forceRefresh: Boolean = false) {
    if (!forceRefresh && loadedOnce) return
    checkForUpdates(forceRefresh)
  }

  fun resetLoadedState() {
    loadedOnce = false
    _uiState.value = GradeScoreWatchUiState()
  }

  fun consumeNotice() {
    _uiState.value = _uiState.value.copy(notice = null)
  }

  fun checkForUpdates(forceRefresh: Boolean = false) {
    loadedOnce = true
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isLoading = true, error = null)

      val terms =
          termsSource.getTerms(forceRefresh).getOrElse { exception ->
            _uiState.value =
                _uiState.value.copy(
                    isLoading = false,
                    error = exception.message ?: "检查成绩更新失败",
                )
            return@launch
          }

      val currentTerm = terms.currentTermOrNull()
      if (currentTerm == null) {
        _uiState.value = _uiState.value.copy(isLoading = false, error = null)
        return@launch
      }

      val gradeData =
          gradeSource.getGrades(currentTerm.itemCode).getOrElse { exception ->
            _uiState.value =
                _uiState.value.copy(
                    isLoading = false,
                    error = exception.message ?: "检查成绩更新失败",
                )
            return@launch
          }

      val latestCache = gradeData.toScoreCache(currentTerm)
      if (latestCache.scores.isEmpty()) {
        _uiState.value = _uiState.value.copy(isLoading = false, error = null)
        return@launch
      }

      val previousCache = cache.get(userKey)
      cache.save(userKey, latestCache)

      val changedScores = previousCache?.changedScoresComparedWith(latestCache).orEmpty()
      _uiState.value =
          _uiState.value.copy(
              isLoading = false,
              error = null,
              notice =
                  if (changedScores.isNotEmpty()) {
                    GradeScoreUpdateNotice(
                        termCode = latestCache.termCode,
                        termName = latestCache.termName ?: currentTerm.itemName,
                        changedScores = changedScores,
                    )
                  } else {
                    _uiState.value.notice
                  },
          )
    }
  }
}

data class GradeScoreWatchUiState(
    val isLoading: Boolean = false,
    val error: String? = null,
    val notice: GradeScoreUpdateNotice? = null,
)

data class GradeScoreUpdateNotice(
    val termCode: String,
    val termName: String,
    val changedScores: List<ChangedGradeScore>,
) {
  val changedCount: Int
    get() = changedScores.size
}

data class ChangedGradeScore(
    val courseName: String,
    val oldScore: String?,
    val newScore: String?,
)

private fun List<Term>.currentTermOrNull(): Term? = find { it.selected } ?: firstOrNull()

private fun GradeData.toScoreCache(term: Term): StoredGradeScoreCache =
    StoredGradeScoreCache(
        termCode = term.itemCode,
        termName = term.itemName,
        scores = grades.mapNotNull { it.toScoreEntry() }.sortedBy { it.key },
    )

private fun Grade.toScoreEntry(): StoredGradeScoreEntry? {
  val key = scoreIdentityKey() ?: return null
  return StoredGradeScoreEntry(
      key = key,
      courseName = courseName?.trim()?.takeIf { it.isNotEmpty() },
      courseCode = courseCode?.trim()?.takeIf { it.isNotEmpty() },
      score = score?.trim()?.takeIf { it.isNotEmpty() },
  )
}

private fun Grade.scoreIdentityKey(): String? =
    id?.trim()?.takeIf { it.isNotEmpty() }?.let { "id:$it" }
        ?: courseCode?.trim()?.takeIf { it.isNotEmpty() }?.let { "code:$it" }
        ?: courseName?.trim()?.takeIf { it.isNotEmpty() }?.let { "name:$it" }

private fun StoredGradeScoreCache.changedScoresComparedWith(
    latest: StoredGradeScoreCache
): List<ChangedGradeScore> {
  if (termCode != latest.termCode) return emptyList()
  val previousByKey = scores.associateBy { it.key }
  return latest.scores.mapNotNull { latestEntry ->
    val previousEntry = previousByKey[latestEntry.key]
    if (previousEntry?.score == latestEntry.score) return@mapNotNull null
    if (previousEntry == null && latestEntry.score == null) return@mapNotNull null
    ChangedGradeScore(
        courseName =
            latestEntry.courseName
                ?: previousEntry?.courseName
                ?: latestEntry.courseCode
                ?: previousEntry?.courseCode
                ?: "未命名课程",
        oldScore = previousEntry?.score,
        newScore = latestEntry.score,
    )
  }
}
