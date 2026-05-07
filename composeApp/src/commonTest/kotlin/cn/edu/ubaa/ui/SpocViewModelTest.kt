package cn.edu.ubaa.ui

import cn.edu.ubaa.api.feature.SpocApi
import cn.edu.ubaa.model.dto.SpocAssignmentDetailDto
import cn.edu.ubaa.model.dto.SpocAssignmentSummaryDto
import cn.edu.ubaa.model.dto.SpocAssignmentsResponse
import cn.edu.ubaa.model.dto.SpocSubmissionStatus
import cn.edu.ubaa.ui.screens.spoc.SpocSortField
import cn.edu.ubaa.ui.screens.spoc.SpocViewModel
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
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
import kotlinx.datetime.LocalDateTime

@OptIn(ExperimentalCoroutinesApi::class)
class SpocViewModelTest {
  @AfterTest
  fun tearDown() {
    Dispatchers.resetMain()
  }

  @Test
  fun `load assignments success updates ui state`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignments())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()

    val state = viewModel.uiState.value
    assertNull(state.error)
    assertEquals(3, state.assignmentsResponse?.assignments?.size)
    assertEquals(listOf("a1", "a2"), state.visibleAssignments.map { it.assignmentId })
  }

  @Test
  fun `load assignments failure exposes error`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel =
        createViewModel(
            object : SpocApi() {
              override suspend fun getAssignments(): Result<SpocAssignmentsResponse> {
                return Result.failure(IllegalStateException("network failed"))
              }
            }
        )

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()

    assertEquals("network failed", viewModel.uiState.value.error)
  }

  @Test
  fun `default state hides expired assignments`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignments())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()

    assertEquals(
        listOf("a1", "a2"),
        viewModel.uiState.value.visibleAssignments.map { it.assignmentId },
    )
  }

  @Test
  fun `show expired exposes expired assignments`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignments())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.setShowExpired(true)

    assertEquals(
        listOf("a3", "a1", "a2"),
        viewModel.uiState.value.visibleAssignments.map { it.assignmentId },
    )
  }

  @Test
  fun `show only unsubmitted keeps unsubmitted assignments`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignments())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.setShowOnlyUnsubmitted(true)

    assertEquals(listOf("a1"), viewModel.uiState.value.visibleAssignments.map { it.assignmentId })
  }

  @Test
  fun `search query matches course name`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignments())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.setSearchQuery("数据")

    assertEquals(listOf("a2"), viewModel.uiState.value.visibleAssignments.map { it.assignmentId })
  }

  @Test
  fun `search query matches assignment title`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignments())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.setSearchQuery("实验")

    assertEquals(listOf("a2"), viewModel.uiState.value.visibleAssignments.map { it.assignmentId })
  }

  @Test
  fun `sort by start time reorders visible assignments`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignments())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.setSortField(SpocSortField.START_TIME)

    assertEquals(
        listOf("a2", "a1"),
        viewModel.uiState.value.visibleAssignments.map { it.assignmentId },
    )
  }

  @Test
  fun `toggle sort direction reverses order`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignments())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.toggleSortDirection()

    assertEquals(
        listOf("a2", "a1"),
        viewModel.uiState.value.visibleAssignments.map { it.assignmentId },
    )
  }

  @Test
  fun `load assignment detail success stores detail`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignmentsAndDetail())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.loadAssignmentDetail("a1")
    advanceUntilIdle()

    val detail = viewModel.uiState.value.assignmentDetail
    assertEquals("a1", detail?.assignmentId)
    assertEquals("请提交 PDF", detail?.contentPlainText)
    assertNull(viewModel.uiState.value.detailError)
  }

  @Test
  fun `clear assignment detail resets detail state`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignmentsAndDetail())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.loadAssignmentDetail("a1")
    advanceUntilIdle()
    viewModel.clearAssignmentDetail()

    val state = viewModel.uiState.value
    assertNull(state.assignmentDetail)
    assertNull(state.detailError)
    assertTrue(!state.isDetailLoading)
  }

  @Test
  fun `does not fetch assignments before ensureAssignmentsLoaded`() = runTest {
    setMainDispatcher(testScheduler)
    val api = CountingSpocApi(apiWithAssignments())
    createViewModel(api)

    advanceUntilIdle()

    assertEquals(0, api.assignmentCalls)
  }

  private fun createViewModel(api: SpocApi): SpocViewModel {
    return SpocViewModel(api, nowProvider = { FIXED_NOW })
  }

  private fun setMainDispatcher(testScheduler: TestCoroutineScheduler) {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
  }

  private fun apiWithAssignments(): SpocApi {
    return object : SpocApi() {
      override suspend fun getAssignments(): Result<SpocAssignmentsResponse> {
        return Result.success(
            SpocAssignmentsResponse(
                termCode = "2025-20262",
                termName = "2026年春季学期",
                assignments =
                    listOf(
                        SpocAssignmentSummaryDto(
                            assignmentId = "a1",
                            courseId = "c1",
                            courseName = "操作系统",
                            teacherName = "牛虹婷",
                            title = "第一次大作业",
                            startTime = "2026-03-15 08:00:00",
                            dueTime = "2026-03-18 18:00:00",
                            score = "100",
                            submissionStatus = SpocSubmissionStatus.UNSUBMITTED,
                            submissionStatusText = "未提交",
                        ),
                        SpocAssignmentSummaryDto(
                            assignmentId = "a2",
                            courseId = "c2",
                            courseName = "数据结构",
                            teacherName = "张老师",
                            title = "实验报告",
                            startTime = "2026-03-14 09:00:00",
                            dueTime = "2026-03-20 20:00:00",
                            score = "80",
                            submissionStatus = SpocSubmissionStatus.SUBMITTED,
                            submissionStatusText = "已提交",
                        ),
                        SpocAssignmentSummaryDto(
                            assignmentId = "a3",
                            courseId = "c3",
                            courseName = "编译原理",
                            teacherName = "李老师",
                            title = "过期作业",
                            startTime = "2026-03-10 08:00:00",
                            dueTime = "2026-03-16 12:00:00",
                            score = "60",
                            submissionStatus = SpocSubmissionStatus.UNSUBMITTED,
                            submissionStatusText = "未提交",
                        ),
                    ),
            )
        )
      }
    }
  }

  private fun apiWithAssignmentsAndDetail(): SpocApi {
    return object : SpocApi() {
      override suspend fun getAssignments(): Result<SpocAssignmentsResponse> =
          apiWithAssignments().getAssignments()

      override suspend fun getAssignmentDetail(
          assignmentId: String
      ): Result<SpocAssignmentDetailDto> {
        return Result.success(
            SpocAssignmentDetailDto(
                assignmentId = assignmentId,
                courseId = "c1",
                courseName = "操作系统",
                teacherName = "牛虹婷",
                title = "第一次大作业",
                startTime = "2026-03-15 08:00:00",
                dueTime = "2026-03-18 18:00:00",
                score = "100",
                submissionStatus = SpocSubmissionStatus.UNSUBMITTED,
                submissionStatusText = "未提交",
                contentPlainText = "请提交 PDF",
                contentHtml = "<p>请提交 PDF</p>",
                submittedAt = null,
            )
        )
      }
    }
  }

  companion object {
    private val FIXED_NOW = LocalDateTime.parse("2026-03-17T12:00:00")
  }

  private class CountingSpocApi(private val delegate: SpocApi) : SpocApi() {
    var assignmentCalls = 0
      private set

    override suspend fun getAssignments(): Result<SpocAssignmentsResponse> {
      assignmentCalls++
      return delegate.getAssignments()
    }

    override suspend fun getAssignmentDetail(
        assignmentId: String
    ): Result<SpocAssignmentDetailDto> {
      return delegate.getAssignmentDetail(assignmentId)
    }
  }
}
