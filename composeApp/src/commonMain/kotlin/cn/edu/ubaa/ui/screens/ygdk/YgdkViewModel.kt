package cn.edu.ubaa.ui.screens.ygdk

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.feature.YgdkApi
import cn.edu.ubaa.api.storage.YgdkReminderStore
import cn.edu.ubaa.model.dto.YgdkClockinSubmitRequest
import cn.edu.ubaa.model.dto.YgdkOverviewResponse
import cn.edu.ubaa.model.dto.YgdkRecordDto
import cn.edu.ubaa.ui.common.util.PickedImage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.datetime.LocalDateTime

const val YGDK_FORM_HINT = "所有内容选填，未填则自动生成合理内容，自动填充全透明图片"

data class YgdkFormState(
    val itemId: Int? = null,
    val startTime: String = "",
    val endTime: String = "",
    val place: String = "",
    val shareToSquare: Boolean = false,
    val photo: PickedImage? = null,
)

data class YgdkUiState(
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val isSubmitting: Boolean = false,
    val overview: YgdkOverviewResponse? = null,
    val records: List<YgdkRecordDto> = emptyList(),
    val page: Int = 1,
    val pageSize: Int = 20,
    val hasMore: Boolean = false,
    val loadError: String? = null,
    val submitMessage: String? = null,
    val form: YgdkFormState = YgdkFormState(),
    val homeReminderEnabled: Boolean = true,
)

class YgdkViewModel(
    private val ygdkApi: YgdkApi = YgdkApi(),
    private val userKey: String = "",
) : ViewModel() {
  private var loadedOnce = false
  private var overviewLoadedOnce = false
  private val reminderUserKey = userKey.ifBlank { "default" }
  private val _uiState = MutableStateFlow(YgdkUiState())
  val uiState: StateFlow<YgdkUiState> = _uiState.asStateFlow()

  init {
    _uiState.value =
        _uiState.value.copy(
            homeReminderEnabled = YgdkReminderStore.isEnabled(reminderUserKey),
        )
  }

  fun ensureLoaded(forceRefresh: Boolean = false) {
    if (!forceRefresh && loadedOnce) return
    refreshAll()
  }

  fun refreshAll(onComplete: (() -> Unit)? = null) {
    loadedOnce = true
    overviewLoadedOnce = true
    viewModelScope.launch {
      val current = _uiState.value
      _uiState.value = current.copy(isLoading = true, loadError = null)
      val overviewResult = ygdkApi.getOverview()
      val recordsResult = ygdkApi.getRecords(page = 1, size = current.pageSize)
      val nextOverview = overviewResult.getOrNull() ?: current.overview
      val nextRecords = recordsResult.getOrNull()?.content ?: current.records
      val nextHasMore = recordsResult.getOrNull()?.hasMore ?: current.hasMore
      val error =
          overviewResult.exceptionOrNull()?.message ?: recordsResult.exceptionOrNull()?.message
      _uiState.value =
          _uiState.value.copy(
              isLoading = false,
              overview = nextOverview,
              records = nextRecords,
              page = 1,
              hasMore = nextHasMore,
              loadError = error,
          )
      onComplete?.invoke()
    }
  }

  fun ensureOverviewLoaded(forceRefresh: Boolean = false) {
    if (!forceRefresh && overviewLoadedOnce) return
    refreshOverviewOnly()
  }

  internal fun hasOverviewLoaded(): Boolean = overviewLoadedOnce

  fun refreshOverviewOnly() {
    overviewLoadedOnce = true
    viewModelScope.launch {
      val current = _uiState.value
      _uiState.value = current.copy(isLoading = true, loadError = null)
      ygdkApi
          .getOverview()
          .onSuccess { overview ->
            _uiState.value =
                _uiState.value.copy(
                    isLoading = false,
                    overview = overview,
                    loadError = null,
                )
          }
          .onFailure {
            _uiState.value =
                _uiState.value.copy(isLoading = false, loadError = it.message ?: "加载阳光打卡失败")
          }
    }
  }

  fun setHomeReminderEnabled(enabled: Boolean) {
    YgdkReminderStore.setEnabled(reminderUserKey, enabled)
    _uiState.value = _uiState.value.copy(homeReminderEnabled = enabled)
  }

  fun markHomeReminderWeekDone(weekKey: String) {
    YgdkReminderStore.markWeekDone(reminderUserKey, weekKey)
  }

  fun markHomeReminderTermDone(termKey: String) {
    YgdkReminderStore.markTermDone(reminderUserKey, termKey)
  }

  fun isHomeReminderWeekDone(weekKey: String): Boolean =
      YgdkReminderStore.isWeekDone(reminderUserKey, weekKey)

  fun isHomeReminderTermDone(termKey: String): Boolean =
      YgdkReminderStore.isTermDone(reminderUserKey, termKey)

  fun loadMoreRecords() {
    val current = _uiState.value
    if (current.isLoading || current.isLoadingMore || !current.hasMore) return
    viewModelScope.launch {
      _uiState.value = current.copy(isLoadingMore = true, loadError = null)
      ygdkApi
          .getRecords(page = current.page + 1, size = current.pageSize)
          .onSuccess { page ->
            _uiState.value =
                _uiState.value.copy(
                    isLoadingMore = false,
                    records = _uiState.value.records + page.content,
                    page = current.page + 1,
                    hasMore = page.hasMore,
                )
          }
          .onFailure {
            _uiState.value =
                _uiState.value.copy(isLoadingMore = false, loadError = it.message ?: "加载记录失败")
          }
    }
  }

  fun updateItemId(itemId: Int?) {
    _uiState.value = _uiState.value.copy(form = _uiState.value.form.copy(itemId = itemId))
  }

  fun updateStartTime(value: String) {
    _uiState.value = _uiState.value.copy(form = _uiState.value.form.copy(startTime = value))
  }

  fun updateEndTime(value: String) {
    _uiState.value = _uiState.value.copy(form = _uiState.value.form.copy(endTime = value))
  }

  fun updatePlace(value: String) {
    _uiState.value = _uiState.value.copy(form = _uiState.value.form.copy(place = value))
  }

  fun setShareToSquare(enabled: Boolean) {
    _uiState.value = _uiState.value.copy(form = _uiState.value.form.copy(shareToSquare = enabled))
  }

  fun setPhoto(image: PickedImage) {
    _uiState.value = _uiState.value.copy(form = _uiState.value.form.copy(photo = image))
  }

  fun clearPhoto() {
    _uiState.value = _uiState.value.copy(form = _uiState.value.form.copy(photo = null))
  }

  fun clearSubmitMessage() {
    _uiState.value = _uiState.value.copy(submitMessage = null)
  }

  fun showMessage(message: String) {
    _uiState.value = _uiState.value.copy(submitMessage = message)
  }

  fun submitClockin(onSuccess: (() -> Unit)? = null) {
    val current = _uiState.value
    val validationError = validateForm(current.form)
    if (validationError != null) {
      _uiState.value = current.copy(submitMessage = validationError)
      return
    }

    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isSubmitting = true, submitMessage = null)
      val result =
          ygdkApi.submitClockin(
              YgdkClockinSubmitRequest(
                  itemId = current.form.itemId,
                  startTime = current.form.startTime.ifBlank { null },
                  endTime = current.form.endTime.ifBlank { null },
                  place = current.form.place.ifBlank { null },
                  shareToSquare = current.form.shareToSquare,
                  photo =
                      current.form.photo?.let {
                        cn.edu.ubaa.model.dto.YgdkPhotoUpload(
                            bytes = it.bytes,
                            fileName = it.fileName,
                            mimeType = it.mimeType,
                        )
                      },
              )
          )
      result
          .onSuccess { response ->
            _uiState.value =
                _uiState.value.copy(
                    isSubmitting = false,
                    submitMessage = response.message,
                    form = YgdkFormState(),
                    overview =
                        _uiState.value.overview?.let { overview ->
                          response.summary?.let { summary -> overview.copy(summary = summary) }
                              ?: overview
                        },
                )
            refreshAll(onComplete = onSuccess)
          }
          .onFailure { error ->
            _uiState.value =
                _uiState.value.copy(
                    isSubmitting = false,
                    submitMessage = error.message ?: "打卡失败",
                )
          }
    }
  }

  private fun validateForm(form: YgdkFormState): String? {
    val startTime = form.startTime.trim()
    val endTime = form.endTime.trim()
    if (startTime.isBlank() && endTime.isBlank()) return null
    if (startTime.isBlank() || endTime.isBlank()) return "开始时间和结束时间需要同时填写"
    val start = startTime.parseFormDateTime() ?: return "开始时间格式错误，请使用 yyyy-MM-dd HH:mm"
    val end = endTime.parseFormDateTime() ?: return "结束时间格式错误，请使用 yyyy-MM-dd HH:mm"
    if (start.date != end.date) return "当前仅支持同一天内的一小时打卡"
    if (end.toString() <= start.toString()) return "结束时间必须晚于开始时间"
    return null
  }
}

private fun String.parseFormDateTime(): LocalDateTime? {
  return runCatching { LocalDateTime.parse(trim().replace(' ', 'T')) }.getOrNull()
}
