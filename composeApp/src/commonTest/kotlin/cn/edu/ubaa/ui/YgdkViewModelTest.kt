package cn.edu.ubaa.ui

import cn.edu.ubaa.api.feature.YgdkApi
import cn.edu.ubaa.api.storage.YgdkReminderStore
import cn.edu.ubaa.model.dto.YgdkClockinSubmitRequest
import cn.edu.ubaa.model.dto.YgdkClockinSubmitResponse
import cn.edu.ubaa.model.dto.YgdkItemDto
import cn.edu.ubaa.model.dto.YgdkOverviewResponse
import cn.edu.ubaa.model.dto.YgdkRecordDto
import cn.edu.ubaa.model.dto.YgdkRecordsPageResponse
import cn.edu.ubaa.model.dto.YgdkTermSummaryDto
import cn.edu.ubaa.ui.common.util.PickedImage
import cn.edu.ubaa.ui.screens.ygdk.YgdkViewModel
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain

@OptIn(ExperimentalCoroutinesApi::class)
class YgdkViewModelTest {
  @AfterTest
  fun tearDown() {
    Dispatchers.resetMain()
    YgdkReminderStore.clear("ygdk-viewmodel-test-user")
    YgdkReminderStore.clear("ygdk-viewmodel-test-other")
  }

  @Test
  fun `initial refresh loads overview and records`() = runTest {
    setMainDispatcher(testScheduler)
    val api =
        FakeYgdkApi(
            overviewResults = mutableListOf(Result.success(sampleOverview())),
            recordsResults =
                mutableMapOf(1 to mutableListOf(Result.success(sampleRecordsPage(hasMore = true)))),
        )

    val viewModel = YgdkViewModel(api)
    viewModel.ensureLoaded()
    advanceUntilIdle()

    val state = viewModel.uiState.value
    assertNull(state.loadError)
    assertEquals("阳光体育", state.overview?.classifyName)
    assertEquals(1, state.records.size)
    assertTrue(state.hasMore)
  }

  @Test
  fun `loadMoreRecords appends next page`() = runTest {
    setMainDispatcher(testScheduler)
    val api =
        FakeYgdkApi(
            overviewResults = mutableListOf(Result.success(sampleOverview())),
            recordsResults =
                mutableMapOf(
                    1 to mutableListOf(Result.success(sampleRecordsPage(hasMore = true))),
                    2 to
                        mutableListOf(
                            Result.success(
                                YgdkRecordsPageResponse(
                                    content =
                                        listOf(
                                            YgdkRecordDto(
                                                recordId = 2,
                                                itemName = "健走",
                                                place = "体育馆",
                                            )
                                        ),
                                    total = 2,
                                    page = 2,
                                    size = 20,
                                    hasMore = false,
                                )
                            )
                        ),
                ),
        )
    val viewModel = YgdkViewModel(api)
    viewModel.ensureLoaded()
    advanceUntilIdle()

    viewModel.loadMoreRecords()
    advanceUntilIdle()

    assertEquals(listOf(1, 2), viewModel.uiState.value.records.map { it.recordId })
    assertEquals(2, viewModel.uiState.value.page)
    assertFalse(viewModel.uiState.value.hasMore)
    assertEquals(listOf(1, 2), api.recordCallPages)
  }

  @Test
  fun `submitClockin with partial time shows validation error without api call`() = runTest {
    setMainDispatcher(testScheduler)
    val api =
        FakeYgdkApi(
            overviewResults = mutableListOf(Result.success(sampleOverview())),
            recordsResults =
                mutableMapOf(
                    1 to mutableListOf(Result.success(sampleRecordsPage(hasMore = false)))
                ),
        )
    val viewModel = YgdkViewModel(api)
    viewModel.ensureLoaded()
    advanceUntilIdle()

    viewModel.updateStartTime("2026-04-01 08:00")
    viewModel.submitClockin()

    assertEquals("开始时间和结束时间需要同时填写", viewModel.uiState.value.submitMessage)
    assertEquals(0, api.submitCalls)
  }

  @Test
  fun `submitClockin success resets form and refreshes data`() = runTest {
    setMainDispatcher(testScheduler)
    val api =
        FakeYgdkApi(
            overviewResults =
                mutableListOf(
                    Result.success(sampleOverview(termCount = 5)),
                    Result.success(sampleOverview(termCount = 6)),
                ),
            recordsResults =
                mutableMapOf(
                    1 to
                        mutableListOf(
                            Result.success(sampleRecordsPage(recordId = 1, hasMore = false)),
                            Result.success(sampleRecordsPage(recordId = 2, hasMore = false)),
                        )
                ),
            submitResult =
                Result.success(
                    YgdkClockinSubmitResponse(
                        success = true,
                        message = "打卡成功",
                        recordId = 1001,
                        summary = YgdkTermSummaryDto(termCount = 6, termTarget = 16),
                    )
                ),
        )
    val viewModel = YgdkViewModel(api)
    viewModel.ensureLoaded()
    advanceUntilIdle()

    viewModel.updateItemId(2)
    viewModel.updateStartTime("2026-04-01 10:00")
    viewModel.updateEndTime("2026-04-01 11:00")
    viewModel.updatePlace("足球场")
    viewModel.setShareToSquare(true)
    viewModel.setPhoto(
        PickedImage(
            bytes = byteArrayOf(1, 2, 3),
            fileName = "proof.png",
            mimeType = "image/png",
        )
    )

    var successCalled = false
    viewModel.submitClockin { successCalled = true }
    advanceUntilIdle()

    val request = api.lastSubmitRequest
    assertNotNull(request)
    assertEquals(2, request.itemId)
    assertEquals("2026-04-01 10:00", request.startTime)
    assertEquals("2026-04-01 11:00", request.endTime)
    assertEquals("足球场", request.place)
    assertEquals(true, request.shareToSquare)
    assertContentEquals(byteArrayOf(1, 2, 3), request.photo?.bytes)
    assertEquals("proof.png", request.photo?.fileName)
    assertTrue(successCalled)

    val state = viewModel.uiState.value
    assertEquals("打卡成功", state.submitMessage)
    assertEquals(2, state.records.single().recordId)
    assertEquals(6, state.overview?.summary?.termCount)
    assertNull(state.form.photo)
    assertEquals("", state.form.startTime)
    assertEquals("", state.form.endTime)
    assertEquals("", state.form.place)
    assertEquals(1, api.submitCalls)
    assertEquals(listOf(1, 1), api.recordCallPages)
  }

  @Test
  fun `submitClockin success updates overview before navigation callback`() = runTest {
    setMainDispatcher(testScheduler)
    val api =
        FakeYgdkApi(
            overviewResults =
                mutableListOf(
                    Result.success(sampleOverview(termCount = 15, weekCount = 3)),
                    Result.success(sampleOverview(termCount = 16, weekCount = 4)),
                ),
            recordsResults =
                mutableMapOf(
                    1 to
                        mutableListOf(
                            Result.success(sampleRecordsPage(recordId = 1, hasMore = false)),
                            Result.success(sampleRecordsPage(recordId = 2, hasMore = false)),
                        )
                ),
            submitResult =
                Result.success(
                    YgdkClockinSubmitResponse(
                        success = true,
                        message = "打卡成功",
                        recordId = 1001,
                        summary =
                            YgdkTermSummaryDto(
                                termCount = 16,
                                termTarget = 16,
                                weekCount = 4,
                                weekTarget = 4,
                            ),
                    )
                ),
        )
    val viewModel = YgdkViewModel(api)
    viewModel.ensureLoaded()
    advanceUntilIdle()

    var callbackTermCount: Int? = null
    var callbackWeekCount: Int? = null
    viewModel.submitClockin {
      callbackTermCount = viewModel.uiState.value.overview?.summary?.termCount
      callbackWeekCount = viewModel.uiState.value.overview?.summary?.weekCount
    }
    advanceUntilIdle()

    assertEquals(16, callbackTermCount)
    assertEquals(4, callbackWeekCount)
    assertEquals(16, viewModel.uiState.value.overview?.summary?.termCount)
    assertEquals(4, viewModel.uiState.value.overview?.summary?.weekCount)
  }

  @Test
  fun `home reminder preference defaults enabled and can be toggled per user`() = runTest {
    YgdkReminderStore.clear("ygdk-viewmodel-test-user")
    YgdkReminderStore.clear("ygdk-viewmodel-test-other")
    val api =
        FakeYgdkApi(
            overviewResults = mutableListOf(Result.success(sampleOverview())),
            recordsResults =
                mutableMapOf(
                    1 to mutableListOf(Result.success(sampleRecordsPage(hasMore = false)))
                ),
        )

    val first = YgdkViewModel(api, userKey = "ygdk-viewmodel-test-user")
    val other = YgdkViewModel(api, userKey = "ygdk-viewmodel-test-other")

    assertTrue(first.uiState.value.homeReminderEnabled)
    first.setHomeReminderEnabled(false)

    assertFalse(first.uiState.value.homeReminderEnabled)
    assertTrue(other.uiState.value.homeReminderEnabled)
    assertFalse(
        YgdkViewModel(api, userKey = "ygdk-viewmodel-test-user").uiState.value.homeReminderEnabled
    )
  }

  @Test
  fun `clearPhoto removes selected image from form`() = runTest {
    setMainDispatcher(testScheduler)
    val api =
        FakeYgdkApi(
            overviewResults = mutableListOf(Result.success(sampleOverview())),
            recordsResults =
                mutableMapOf(
                    1 to mutableListOf(Result.success(sampleRecordsPage(hasMore = false)))
                ),
        )
    val viewModel = YgdkViewModel(api)
    viewModel.ensureLoaded()
    advanceUntilIdle()

    viewModel.setPhoto(PickedImage(byteArrayOf(4, 5), "sample.jpg", "image/jpeg"))
    assertNotNull(viewModel.uiState.value.form.photo)

    viewModel.clearPhoto()

    assertNull(viewModel.uiState.value.form.photo)
  }

  @Test
  fun `does not load before ensureLoaded is called`() = runTest {
    setMainDispatcher(testScheduler)
    val api =
        FakeYgdkApi(
            overviewResults = mutableListOf(Result.success(sampleOverview())),
            recordsResults =
                mutableMapOf(
                    1 to mutableListOf(Result.success(sampleRecordsPage(hasMore = false)))
                ),
        )

    YgdkViewModel(api)
    advanceUntilIdle()

    assertEquals(0, api.overviewCalls)
    assertTrue(api.recordCallPages.isEmpty())
  }

  private fun setMainDispatcher(testScheduler: TestCoroutineScheduler) {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
  }

  private fun sampleOverview(
      termCount: Int = 5,
      weekCount: Int? = null,
  ): YgdkOverviewResponse {
    return YgdkOverviewResponse(
        summary = YgdkTermSummaryDto(termCount = termCount, termTarget = 16, weekCount = weekCount),
        classifyId = 3,
        classifyName = "阳光体育",
        defaultItemId = 1,
        defaultItemName = "跑步",
        items =
            listOf(
                YgdkItemDto(itemId = 1, name = "跑步"),
                YgdkItemDto(itemId = 2, name = "健走"),
            ),
    )
  }

  private fun sampleRecordsPage(recordId: Int = 1, hasMore: Boolean): YgdkRecordsPageResponse {
    return YgdkRecordsPageResponse(
        content = listOf(YgdkRecordDto(recordId = recordId, itemName = "跑步", place = "操场")),
        total = if (hasMore) 2 else 1,
        page = 1,
        size = 20,
        hasMore = hasMore,
    )
  }

  private class FakeYgdkApi(
      private val overviewResults: MutableList<Result<YgdkOverviewResponse>>,
      private val recordsResults: MutableMap<Int, MutableList<Result<YgdkRecordsPageResponse>>>,
      private val submitResult: Result<YgdkClockinSubmitResponse> =
          Result.success(YgdkClockinSubmitResponse(success = true, message = "打卡成功", recordId = 1)),
  ) : YgdkApi() {
    var overviewCalls = 0
      private set

    var submitCalls = 0
      private set

    var lastSubmitRequest: YgdkClockinSubmitRequest? = null
      private set

    val recordCallPages = mutableListOf<Int>()

    override suspend fun getOverview(): Result<YgdkOverviewResponse> {
      overviewCalls++
      return overviewResults.removeFirstOrNull() ?: Result.success(sampleFallbackOverview())
    }

    override suspend fun getRecords(page: Int, size: Int): Result<YgdkRecordsPageResponse> {
      recordCallPages += page
      return recordsResults[page]?.removeFirstOrNull()
          ?: Result.success(YgdkRecordsPageResponse(page = page, size = size))
    }

    override suspend fun submitClockin(
        request: YgdkClockinSubmitRequest
    ): Result<YgdkClockinSubmitResponse> {
      submitCalls++
      val copiedPhoto = request.photo?.let { photo -> photo.copy(bytes = photo.bytes.copyOf()) }
      lastSubmitRequest = request.copy(photo = copiedPhoto)
      return submitResult
    }

    private fun sampleFallbackOverview(): YgdkOverviewResponse {
      return YgdkOverviewResponse(
          summary = YgdkTermSummaryDto(termCount = 0),
          classifyId = 3,
          classifyName = "阳光体育",
      )
    }
  }
}
