package cn.edu.ubaa.ui.screens.cgyy

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.CgyyApi
import cn.edu.ubaa.api.CgyyReservationFormStore
import cn.edu.ubaa.api.StoredCgyyReservationForm
import cn.edu.ubaa.model.dto.CgyyDayInfoResponse
import cn.edu.ubaa.model.dto.CgyyLockCodeResponse
import cn.edu.ubaa.model.dto.CgyyOrdersPageResponse
import cn.edu.ubaa.model.dto.CgyyPurposeTypeDto
import cn.edu.ubaa.model.dto.CgyyReservationSelectionDto
import cn.edu.ubaa.model.dto.CgyyReservationSubmitRequest
import cn.edu.ubaa.model.dto.CgyyVenueSiteDto
import kotlin.math.abs
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

data class CgyyReservationSummary(
    val siteLabel: String,
    val reservationDate: String,
    val spaceName: String,
    val slotLabels: List<String>,
)

data class CgyyUiState(
    val isInitialLoading: Boolean = false,
    val isDayInfoLoading: Boolean = false,
    val isSubmitting: Boolean = false,
    val isOrdersLoading: Boolean = false,
    val isLockCodeLoading: Boolean = false,
    val sites: List<CgyyVenueSiteDto> = emptyList(),
    val purposeTypes: List<CgyyPurposeTypeDto> = emptyList(),
    val dayInfo: CgyyDayInfoResponse? = null,
    val selectedCampus: String = "",
    val reserveSearchQuery: String = "",
    val selectedSiteId: Int? = null,
    val selectedDate: String = "",
    val selections: List<CgyyReservationSelectionDto> = emptyList(),
    val reservationSummary: CgyyReservationSummary? = null,
    val phone: String = "",
    val theme: String = "",
    val purposeType: Int? = null,
    val joinerNum: String = "1",
    val activityContent: String = "",
    val joiners: String = "",
    val isPhilosophySocialSciences: Boolean = false,
    val isOffSchoolJoiner: Boolean = false,
    val hasTriedSubmitReservation: Boolean = false,
    val orders: CgyyOrdersPageResponse = CgyyOrdersPageResponse(),
    val lockCode: CgyyLockCodeResponse? = null,
    val initialError: String? = null,
    val dayInfoError: String? = null,
    val ordersError: String? = null,
    val lockCodeError: String? = null,
    val actionMessage: String? = null,
)

@OptIn(ExperimentalTime::class)
class CgyyViewModel(
    private val cgyyApi: CgyyApi = CgyyApi(),
    private val currentDateProvider: () -> String = {
      val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
      val month = (now.month.ordinal + 1).toString().padStart(2, '0')
      val day = now.day.toString().padStart(2, '0')
      "${now.year}-$month-$day"
    },
) : ViewModel() {
  companion object {
    const val ALL_CAMPUSES = "全部"
  }

  private var initialLoadedOnce = false
  private var ordersLoadedOnce = false
  private var lockCodeLoadedOnce = false
  private val _uiState = MutableStateFlow(createInitialState())
  val uiState: StateFlow<CgyyUiState> = _uiState.asStateFlow()

  fun ensureInitialDataLoaded(forceRefresh: Boolean = false) {
    if (!forceRefresh && initialLoadedOnce) return
    loadInitialData()
  }

  fun loadInitialData() {
    initialLoadedOnce = true
    viewModelScope.launch {
      _uiState.value =
          _uiState.value.copy(
              isInitialLoading = true,
              initialError = null,
              dayInfoError = null,
          )

      val sitesResult = cgyyApi.getVenueSites()
      val purposeTypesResult = cgyyApi.getPurposeTypes()

      val sites = sitesResult.getOrNull().orEmpty()
      val purposeTypes = purposeTypesResult.getOrNull().orEmpty()
      val currentPurposeType = _uiState.value.purposeType
      val siteId = _uiState.value.selectedSiteId ?: sites.firstOrNull()?.id

      _uiState.value =
          _uiState.value.copy(
              isInitialLoading = false,
              sites = sites,
              selectedCampus = _uiState.value.selectedCampus.ifBlank { ALL_CAMPUSES },
              purposeTypes = purposeTypes,
              selectedSiteId = siteId,
              purposeType =
                  when {
                    purposeTypes.isEmpty() -> currentPurposeType
                    currentPurposeType != null &&
                        purposeTypes.any { it.key == currentPurposeType } -> currentPurposeType
                    else -> purposeTypes.firstOrNull()?.key
                  },
              initialError =
                  sitesResult.exceptionOrNull()?.message
                      ?: purposeTypesResult.exceptionOrNull()?.message,
          )

      if (siteId != null) {
        loadDayInfo(siteId, _uiState.value.selectedDate.ifBlank { currentDateProvider() })
      }
    }
  }

  fun ensureOrdersLoaded(forceRefresh: Boolean = false) {
    if (!forceRefresh && ordersLoadedOnce) return
    loadOrders()
  }

  fun ensureLockCodeLoaded(forceRefresh: Boolean = false) {
    if (!forceRefresh && lockCodeLoadedOnce) return
    loadLockCode()
  }

  fun setDefaultPhone(phone: String?) {
    if (phone.isNullOrBlank()) return
    if (_uiState.value.phone.isBlank()) {
      _uiState.value = _uiState.value.copy(phone = phone)
    }
  }

  fun setReserveCampus(campus: String) {
    val current = _uiState.value
    val campusSites =
        if (campus == ALL_CAMPUSES) current.sites
        else current.sites.filter { it.campusName == campus }
    val nextSiteId =
        current.selectedSiteId?.takeIf { selectedId -> campusSites.any { it.id == selectedId } }
            ?: campusSites.firstOrNull()?.id
    _uiState.value =
        current.copy(
            selectedCampus = campus,
            selectedSiteId = nextSiteId,
            selections = emptyList(),
            reservationSummary = null,
            actionMessage = null,
        )
    if (nextSiteId != null) {
      loadDayInfo(nextSiteId, current.selectedDate.ifBlank { currentDateProvider() })
    }
  }

  fun updateReserveSearchQuery(query: String) {
    _uiState.value = _uiState.value.copy(reserveSearchQuery = query)
  }

  fun selectSite(siteId: Int) {
    _uiState.value =
        _uiState.value.copy(
            selectedSiteId = siteId,
            selections = emptyList(),
            reservationSummary = null,
            actionMessage = null,
        )
    loadDayInfo(siteId, _uiState.value.selectedDate.ifBlank { currentDateProvider() })
  }

  fun selectDate(date: String) {
    val siteId = _uiState.value.selectedSiteId ?: return
    _uiState.value =
        _uiState.value.copy(
            selectedDate = date,
            selections = emptyList(),
            reservationSummary = null,
            actionMessage = null,
        )
    loadDayInfo(siteId, date)
  }

  fun toggleSlot(spaceId: Int, timeId: Int, venueSpaceGroupId: Int?) {
    val currentState = _uiState.value
    val tappedSelection =
        CgyyReservationSelectionDto(
            spaceId = spaceId,
            timeId = timeId,
            venueSpaceGroupId = venueSpaceGroupId,
        )
    val orderedTimeIds =
        currentState.dayInfo?.timeSlots?.mapIndexed { index, slot -> slot.id to index }?.toMap()
    val existingSelections =
        currentState.selections.sortedBy { orderedTimeIds?.get(it.timeId) ?: Int.MAX_VALUE }
    val nextSelections =
        when {
          existingSelections.any { it.spaceId == spaceId && it.timeId == timeId } ->
              existingSelections.filterNot { it.spaceId == spaceId && it.timeId == timeId }
          existingSelections.isEmpty() -> listOf(tappedSelection)
          existingSelections.any { it.spaceId != spaceId } -> listOf(tappedSelection)
          existingSelections.size == 1 &&
              areAdjacent(existingSelections.first().timeId, timeId, orderedTimeIds) ->
              listOf(existingSelections.first(), tappedSelection).sortedBy {
                orderedTimeIds?.get(it.timeId) ?: Int.MAX_VALUE
              }
          else -> listOf(tappedSelection)
        }
    val nextState = _uiState.value.copy(selections = nextSelections, actionMessage = null)
    _uiState.value = nextState.copy(reservationSummary = buildReservationSummary(nextState))
  }

  fun updatePhone(value: String) {
    _uiState.value = _uiState.value.copy(phone = value)
  }

  fun updateTheme(value: String) {
    _uiState.value = _uiState.value.copy(theme = value)
  }

  fun updatePurposeType(value: Int) {
    _uiState.value = _uiState.value.copy(purposeType = value)
  }

  fun updateJoinerNum(value: String) {
    _uiState.value = _uiState.value.copy(joinerNum = value)
  }

  fun updateActivityContent(value: String) {
    _uiState.value = _uiState.value.copy(activityContent = value)
  }

  fun updateJoiners(value: String) {
    _uiState.value = _uiState.value.copy(joiners = value)
  }

  fun setPhilosophySocialSciences(enabled: Boolean) {
    _uiState.value = _uiState.value.copy(isPhilosophySocialSciences = enabled)
  }

  fun setOffSchoolJoiner(enabled: Boolean) {
    _uiState.value = _uiState.value.copy(isOffSchoolJoiner = enabled)
  }

  fun canAdvanceToReservationForm(): Boolean = _uiState.value.reservationSummary != null

  fun selectionHint(): String =
      when {
        _uiState.value.selectedSiteId == null -> "请先选择研讨室"
        _uiState.value.selectedDate.isBlank() -> "请先选择预约日期"
        _uiState.value.selections.isEmpty() -> "请至少选择一个可预约时段"
        else -> "已完成选择，可以进入下一步"
      }

  fun submitReservation(onSuccess: (() -> Unit)? = null) {
    val current = _uiState.value
    val siteId = current.selectedSiteId ?: return setActionMessage("请先选择场地")
    val purposeType = current.purposeType ?: return setActionMessage("请选择活动类型")
    val joinerNum = current.joinerNum.toIntOrNull()
    _uiState.value = current.copy(hasTriedSubmitReservation = true, actionMessage = null)
    if (current.selections.isEmpty()) return setActionMessage("请至少选择一个时段")
    if (joinerNum == null || joinerNum <= 0) return setActionMessage("参与人数必须大于 0")
    if (current.phone.isBlank()) return setActionMessage("请填写联系电话")
    if (current.theme.isBlank()) return setActionMessage("请填写活动主题")
    if (current.activityContent.isBlank()) return setActionMessage("请填写活动内容")
    if (current.joiners.isBlank()) return setActionMessage("请填写参与人说明")

    viewModelScope.launch {
      _uiState.value =
          _uiState.value.copy(
              isSubmitting = true,
              actionMessage = null,
              hasTriedSubmitReservation = true,
          )
      val result =
          cgyyApi.submitReservation(
              CgyyReservationSubmitRequest(
                  venueSiteId = siteId,
                  reservationDate = current.selectedDate,
                  selections = current.selections,
                  phone = current.phone,
                  theme = current.theme,
                  purposeType = purposeType,
                  joinerNum = joinerNum,
                  activityContent = current.activityContent,
                  joiners = current.joiners,
                  isPhilosophySocialSciences = current.isPhilosophySocialSciences,
                  isOffSchoolJoiner = current.isOffSchoolJoiner,
              )
          )
      result
          .onSuccess {
            val storedForm =
                StoredCgyyReservationForm(
                    phone = current.phone,
                    theme = current.theme,
                    purposeType = purposeType,
                    joinerNum = current.joinerNum,
                    activityContent = current.activityContent,
                    joiners = current.joiners,
                    isPhilosophySocialSciences = current.isPhilosophySocialSciences,
                    isOffSchoolJoiner = current.isOffSchoolJoiner,
                )
            CgyyReservationFormStore.save(storedForm)
            _uiState.value =
                _uiState.value.copy(
                    isSubmitting = false,
                    selections = emptyList(),
                    reservationSummary = null,
                    phone = storedForm.phone,
                    theme = storedForm.theme,
                    purposeType = storedForm.purposeType,
                    joinerNum = storedForm.joinerNum,
                    activityContent = storedForm.activityContent,
                    joiners = storedForm.joiners,
                    isPhilosophySocialSciences = storedForm.isPhilosophySocialSciences,
                    isOffSchoolJoiner = storedForm.isOffSchoolJoiner,
                    hasTriedSubmitReservation = false,
                    actionMessage = it.message,
                )
            loadDayInfo(siteId, current.selectedDate)
            loadOrders()
            onSuccess?.invoke()
          }
          .onFailure {
            _uiState.value =
                _uiState.value.copy(
                    isSubmitting = false,
                    actionMessage = it.message ?: "预约失败",
                )
          }
    }
  }

  fun loadOrders(page: Int = 0, size: Int = 20) {
    ordersLoadedOnce = true
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isOrdersLoading = true, ordersError = null)
      cgyyApi
          .getMyOrders(page, size)
          .onSuccess {
            _uiState.value =
                _uiState.value.copy(
                    isOrdersLoading = false,
                    orders = it,
                    ordersError = null,
                )
          }
          .onFailure {
            _uiState.value =
                _uiState.value.copy(
                    isOrdersLoading = false,
                    ordersError = it.message ?: "加载预约列表失败",
                )
          }
    }
  }

  fun cancelOrder(orderId: Int) {
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(actionMessage = null)
      cgyyApi
          .cancelOrder(orderId)
          .onSuccess {
            _uiState.value = _uiState.value.copy(actionMessage = it.message)
            loadOrders(_uiState.value.orders.number, _uiState.value.orders.size)
          }
          .onFailure {
            _uiState.value = _uiState.value.copy(actionMessage = it.message ?: "取消预约失败")
          }
    }
  }

  fun loadLockCode() {
    if (_uiState.value.isLockCodeLoading) return
    lockCodeLoadedOnce = true
    _uiState.value = _uiState.value.copy(isLockCodeLoading = true, lockCodeError = null)
    viewModelScope.launch {
      cgyyApi
          .getLockCode()
          .onSuccess {
            _uiState.value =
                _uiState.value.copy(
                    isLockCodeLoading = false,
                    lockCode = it,
                    lockCodeError = null,
                )
          }
          .onFailure {
            _uiState.value =
                _uiState.value.copy(
                    isLockCodeLoading = false,
                    lockCodeError = it.message ?: "加载门锁密码失败",
                )
          }
    }
  }

  fun clearActionMessage() {
    _uiState.value = _uiState.value.copy(actionMessage = null)
  }

  fun refreshReserveData() {
    val current = _uiState.value
    val selectedSiteId = current.selectedSiteId
    if (selectedSiteId == null) {
      loadInitialData()
      return
    }
    loadDayInfo(selectedSiteId, current.selectedDate.ifBlank { currentDateProvider() })
  }

  private fun loadDayInfo(siteId: Int, date: String) {
    viewModelScope.launch {
      _uiState.value = _uiState.value.copy(isDayInfoLoading = true, dayInfoError = null)
      cgyyApi
          .getDayInfo(siteId, date)
          .onSuccess { response ->
            val filteredSelections =
                _uiState.value.selections.filter { selection ->
                  response.spaces.any { space ->
                    space.spaceId == selection.spaceId &&
                        space.slots.any { it.timeId == selection.timeId && it.isReservable }
                  }
                }
            val nextState =
                _uiState.value.copy(
                    isDayInfoLoading = false,
                    dayInfo = response,
                    selectedDate = response.reservationDate,
                    selections = filteredSelections,
                )
            _uiState.value =
                nextState.copy(
                    reservationSummary = buildReservationSummary(nextState),
                )
          }
          .onFailure {
            _uiState.value =
                _uiState.value.copy(
                    isDayInfoLoading = false,
                    dayInfoError = it.message ?: "加载可预约信息失败",
                )
          }
    }
  }

  private fun setActionMessage(message: String) {
    _uiState.value = _uiState.value.copy(actionMessage = message)
  }

  private fun createInitialState(): CgyyUiState {
    val storedForm = CgyyReservationFormStore.get()
    return CgyyUiState(
        phone = storedForm?.phone.orEmpty(),
        theme = storedForm?.theme.orEmpty(),
        purposeType = storedForm?.purposeType,
        joinerNum = storedForm?.joinerNum ?: "1",
        activityContent = storedForm?.activityContent.orEmpty(),
        joiners = storedForm?.joiners.orEmpty(),
        isPhilosophySocialSciences = storedForm?.isPhilosophySocialSciences ?: false,
        isOffSchoolJoiner = storedForm?.isOffSchoolJoiner ?: false,
    )
  }

  private fun areAdjacent(
      firstTimeId: Int,
      secondTimeId: Int,
      orderedTimeIds: Map<Int, Int>?,
  ): Boolean {
    val firstIndex = orderedTimeIds?.get(firstTimeId) ?: return false
    val secondIndex = orderedTimeIds[secondTimeId] ?: return false
    return abs(firstIndex - secondIndex) == 1
  }

  private fun buildReservationSummary(state: CgyyUiState): CgyyReservationSummary? {
    val selectedSiteId = state.selectedSiteId ?: return null
    if (state.selectedDate.isBlank() || state.selections.isEmpty()) return null
    val selectedSpaceId = state.selections.firstOrNull()?.spaceId ?: return null
    if (state.selections.any { it.spaceId != selectedSpaceId }) return null
    val site = state.sites.firstOrNull { it.id == selectedSiteId } ?: return null
    val dayInfo = state.dayInfo ?: return null
    val space = dayInfo.spaces.firstOrNull { it.spaceId == selectedSpaceId } ?: return null
    val orderedTimeIds = dayInfo.timeSlots.mapIndexed { index, slot -> slot.id to index }.toMap()
    val selectedTimeIds = state.selections.map { it.timeId }.toSet()
    val slotLabels =
        space.slots
            .filter { it.timeId in selectedTimeIds }
            .sortedBy { orderedTimeIds[it.timeId] ?: Int.MAX_VALUE }
            .mapNotNull { slot ->
              dayInfo.timeSlots.firstOrNull { it.id == slot.timeId }?.label
                  ?: slot.startDate?.substringAfter(" ")?.let { start ->
                    slot.endDate?.substringAfter(" ")?.let { end -> "$start-$end" }
                  }
            }
    if (slotLabels.isEmpty()) return null
    return CgyyReservationSummary(
        siteLabel =
            listOf(site.venueName, site.siteName).filter { it.isNotBlank() }.joinToString(" "),
        reservationDate = state.selectedDate,
        spaceName = space.spaceName,
        slotLabels = slotLabels,
    )
  }
}
