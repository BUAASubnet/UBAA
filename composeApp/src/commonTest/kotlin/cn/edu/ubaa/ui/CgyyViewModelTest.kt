package cn.edu.ubaa.ui

import cn.edu.ubaa.api.CgyyReservationFormStore
import cn.edu.ubaa.api.CgyyApi
import cn.edu.ubaa.model.dto.CgyyDayInfoResponse
import cn.edu.ubaa.model.dto.CgyyLockCodeResponse
import cn.edu.ubaa.model.dto.CgyyOrderDto
import cn.edu.ubaa.model.dto.CgyyOrdersPageResponse
import cn.edu.ubaa.model.dto.CgyyPurposeTypeDto
import cn.edu.ubaa.model.dto.CgyyReservationSubmitRequest
import cn.edu.ubaa.model.dto.CgyyReservationSubmitResponse
import cn.edu.ubaa.model.dto.CgyySlotStatusDto
import cn.edu.ubaa.model.dto.CgyySpaceAvailabilityDto
import cn.edu.ubaa.model.dto.CgyyTimeSlotDto
import cn.edu.ubaa.model.dto.CgyyVenueSiteDto
import cn.edu.ubaa.ui.screens.cgyy.CgyyViewModel
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@OptIn(ExperimentalCoroutinesApi::class)
class CgyyViewModelTest {
  @AfterTest
  fun tearDown() {
    Dispatchers.resetMain()
    CgyyReservationFormStore.clear()
  }

  @Test
  fun `init loads sites and day info`() = runTest {
    setMainDispatcher(testScheduler)
    val api = FakeCgyyApi()
    val viewModel = CgyyViewModel(api, currentDateProvider = { "2026-03-29" })

    advanceUntilIdle()

    assertEquals(1, viewModel.uiState.value.sites.size)
    assertEquals(4, viewModel.uiState.value.selectedSiteId)
    assertEquals("2026-03-29", viewModel.uiState.value.selectedDate)
    assertEquals(1, api.dayInfoCalls)
    assertEquals(0, api.ordersCalls)
  }

  @Test
  fun `toggle slot allows at most two consecutive selections and builds summary`() = runTest {
    setMainDispatcher(testScheduler)
    CgyyReservationFormStore.clear()
    val viewModel = CgyyViewModel(FakeCgyyApi(), currentDateProvider = { "2026-03-29" })

    advanceUntilIdle()
    viewModel.toggleSlot(6, 241, null)
    viewModel.toggleSlot(6, 242, null)

    assertEquals(2, viewModel.uiState.value.selections.size)
    assertEquals(listOf(241, 242), viewModel.uiState.value.selections.map { it.timeId })
    assertNotNull(viewModel.uiState.value.reservationSummary)
    assertEquals("主204", viewModel.uiState.value.reservationSummary?.spaceName)
    assertEquals(
        listOf("12:30-14:00", "14:00-15:35"),
        viewModel.uiState.value.reservationSummary?.slotLabels,
    )
  }

  @Test
  fun `tapping same slot twice clears selection`() = runTest {
    setMainDispatcher(testScheduler)
    CgyyReservationFormStore.clear()
    val viewModel = CgyyViewModel(FakeCgyyApi(), currentDateProvider = { "2026-03-29" })

    advanceUntilIdle()
    viewModel.toggleSlot(6, 242, null)
    viewModel.toggleSlot(6, 242, null)

    assertTrue(viewModel.uiState.value.selections.isEmpty())
    assertEquals(null, viewModel.uiState.value.reservationSummary)
  }

  @Test
  fun `non consecutive or third slot resets to latest single selection`() = runTest {
    setMainDispatcher(testScheduler)
    CgyyReservationFormStore.clear()
    val viewModel = CgyyViewModel(FakeCgyyApi(), currentDateProvider = { "2026-03-29" })

    advanceUntilIdle()
    viewModel.toggleSlot(6, 241, null)
    viewModel.toggleSlot(6, 243, null)
    assertEquals(listOf(243), viewModel.uiState.value.selections.map { it.timeId })

    viewModel.toggleSlot(6, 242, null)
    assertEquals(listOf(242, 243), viewModel.uiState.value.selections.map { it.timeId })

    viewModel.toggleSlot(6, 241, null)
    assertEquals(listOf(241), viewModel.uiState.value.selections.map { it.timeId })
  }

  @Test
  fun `submit reservation refreshes orders`() = runTest {
    setMainDispatcher(testScheduler)
    CgyyReservationFormStore.clear()
    val api = FakeCgyyApi()
    val viewModel = CgyyViewModel(api, currentDateProvider = { "2026-03-29" })

    advanceUntilIdle()
    viewModel.updatePhone("18800000000")
    viewModel.updateTheme("讨论")
    viewModel.updateJoinerNum("3")
    viewModel.updateActivityContent("活动内容")
    viewModel.updateJoiners("张三等三人")
    viewModel.toggleSlot(6, 242, null)
    viewModel.submitReservation()
    advanceUntilIdle()

    assertEquals(1, api.submitCalls)
    assertEquals(1, api.ordersCalls)
    assertEquals("预约成功", viewModel.uiState.value.actionMessage)
    assertTrue(viewModel.uiState.value.selections.isEmpty())
    assertEquals("讨论", viewModel.uiState.value.theme)
  }

  @Test
  fun `ensure orders loaded fetches orders lazily`() = runTest {
    setMainDispatcher(testScheduler)
    CgyyReservationFormStore.clear()
    val api = FakeCgyyApi()
    val viewModel = CgyyViewModel(api, currentDateProvider = { "2026-03-29" })

    advanceUntilIdle()
    viewModel.ensureOrdersLoaded()
    advanceUntilIdle()

    assertEquals(1, api.ordersCalls)
    assertEquals(1, viewModel.uiState.value.orders.content.size)
  }

  @Test
  fun `load lock code stores raw value`() = runTest {
    setMainDispatcher(testScheduler)
    CgyyReservationFormStore.clear()
    val viewModel = CgyyViewModel(FakeCgyyApi(), currentDateProvider = { "2026-03-29" })

    advanceUntilIdle()
    viewModel.loadLockCode()
    advanceUntilIdle()

    assertTrue(viewModel.uiState.value.lockCode?.rawData.toString().contains("123456"))
  }

  @Test
  fun `successful reservation saves form for next time`() = runTest {
    setMainDispatcher(testScheduler)
    CgyyReservationFormStore.clear()
    val api = FakeCgyyApi()
    val firstViewModel = CgyyViewModel(api, currentDateProvider = { "2026-03-29" })

    advanceUntilIdle()
    firstViewModel.updatePhone("18800000000")
    firstViewModel.updateTheme("课题讨论")
    firstViewModel.updateJoinerNum("5")
    firstViewModel.updateActivityContent("研讨内容")
    firstViewModel.updateJoiners("张三、李四")
    firstViewModel.setPhilosophySocialSciences(true)
    firstViewModel.setOffSchoolJoiner(true)
    firstViewModel.toggleSlot(6, 241, null)
    firstViewModel.submitReservation()
    advanceUntilIdle()

    val secondViewModel = CgyyViewModel(api, currentDateProvider = { "2026-03-29" })
    advanceUntilIdle()

    assertEquals("18800000000", secondViewModel.uiState.value.phone)
    assertEquals("课题讨论", secondViewModel.uiState.value.theme)
    assertEquals("5", secondViewModel.uiState.value.joinerNum)
    assertEquals("研讨内容", secondViewModel.uiState.value.activityContent)
    assertEquals("张三、李四", secondViewModel.uiState.value.joiners)
    assertTrue(secondViewModel.uiState.value.isPhilosophySocialSciences)
    assertTrue(secondViewModel.uiState.value.isOffSchoolJoiner)
  }

  private fun setMainDispatcher(testScheduler: TestCoroutineScheduler) {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
  }

  private class FakeCgyyApi : CgyyApi() {
    var dayInfoCalls = 0
    var submitCalls = 0
    var ordersCalls = 0

    override suspend fun getVenueSites(): Result<List<CgyyVenueSiteDto>> {
      return Result.success(
          listOf(
              CgyyVenueSiteDto(id = 4, siteName = "二层", venueName = "老主楼研讨室", campusName = "学院路校区")
          )
      )
    }

    override suspend fun getPurposeTypes(): Result<List<CgyyPurposeTypeDto>> {
      return Result.success(listOf(CgyyPurposeTypeDto(3, "学术研讨类")))
    }

    override suspend fun getDayInfo(venueSiteId: Int, date: String): Result<CgyyDayInfoResponse> {
      dayInfoCalls++
      return Result.success(
          CgyyDayInfoResponse(
              venueSiteId = venueSiteId,
              reservationDate = date,
              availableDates = listOf(date),
              timeSlots =
                  listOf(
                      CgyyTimeSlotDto(241, "12:30", "14:00", "12:30-14:00"),
                      CgyyTimeSlotDto(242, "14:00", "15:35", "14:00-15:35"),
                      CgyyTimeSlotDto(243, "15:35", "17:10", "15:35-17:10"),
                  ),
              spaces =
                  listOf(
                      CgyySpaceAvailabilityDto(
                          spaceId = 6,
                          spaceName = "主204",
                          venueSiteId = venueSiteId,
                          slots =
                              listOf(
                                  CgyySlotStatusDto(
                                      timeId = 241,
                                      reservationStatus = 1,
                                      isReservable = true,
                                  ),
                                  CgyySlotStatusDto(
                                      timeId = 242,
                                      reservationStatus = 1,
                                      isReservable = true,
                                  ),
                                  CgyySlotStatusDto(
                                      timeId = 243,
                                      reservationStatus = 1,
                                      isReservable = true,
                                  )
                              ),
                      ),
                      CgyySpaceAvailabilityDto(
                          spaceId = 7,
                          spaceName = "主205",
                          venueSiteId = venueSiteId,
                          slots =
                              listOf(
                                  CgyySlotStatusDto(
                                      timeId = 241,
                                      reservationStatus = 1,
                                      isReservable = true,
                                  ),
                                  CgyySlotStatusDto(
                                      timeId = 242,
                                      reservationStatus = 1,
                                      isReservable = true,
                                  ),
                                  CgyySlotStatusDto(
                                      timeId = 243,
                                      reservationStatus = 1,
                                      isReservable = true,
                                  )
                              ),
                      ),
                  ),
          )
      )
    }

    override suspend fun submitReservation(
        request: CgyyReservationSubmitRequest
    ): Result<CgyyReservationSubmitResponse> {
      submitCalls++
      return Result.success(
          CgyyReservationSubmitResponse(
              success = true,
              message = "预约成功",
              order = CgyyOrderDto(id = 1, theme = request.theme),
          )
      )
    }

    override suspend fun getMyOrders(page: Int, size: Int): Result<CgyyOrdersPageResponse> {
      ordersCalls++
      return Result.success(
          CgyyOrdersPageResponse(
              content = listOf(CgyyOrderDto(id = 1, theme = "讨论")),
              totalElements = 1,
              totalPages = 1,
              size = size,
              number = page,
          )
      )
    }

    override suspend fun getLockCode(): Result<CgyyLockCodeResponse> {
      return Result.success(CgyyLockCodeResponse(buildJsonObject { put("password", "123456") }))
    }
  }
}
