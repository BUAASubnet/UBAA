package cn.edu.ubaa.ui

import cn.edu.ubaa.api.JudgeApi
import cn.edu.ubaa.model.dto.JudgeAssignmentDetailDto
import cn.edu.ubaa.model.dto.JudgeAssignmentSummaryDto
import cn.edu.ubaa.model.dto.JudgeAssignmentsResponse
import cn.edu.ubaa.model.dto.JudgeProblemDto
import cn.edu.ubaa.model.dto.JudgeSubmissionStatus
import cn.edu.ubaa.ui.screens.judge.JudgeSortField
import cn.edu.ubaa.ui.screens.judge.JudgeViewModel
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
class JudgeViewModelTest {
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
    assertEquals(listOf("101", "102"), state.visibleAssignments.map { it.assignmentId })
  }

  @Test
  fun `show only unfinished keeps unsubmitted and partial assignments`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignments())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.setShowOnlyUnfinished(true)

    assertEquals(
        listOf("101", "102"),
        viewModel.uiState.value.visibleAssignments.map { it.assignmentId },
    )
  }

  @Test
  fun `search query matches course and title`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignments())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.setSearchQuery("算法")

    assertEquals(listOf("102"), viewModel.uiState.value.visibleAssignments.map { it.assignmentId })
  }

  @Test
  fun `sort by start time reorders visible assignments`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignments())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.setSortField(JudgeSortField.START_TIME)

    assertEquals(
        listOf("102", "101"),
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
        listOf("103", "101", "102"),
        viewModel.uiState.value.visibleAssignments.map { it.assignmentId },
    )
  }

  @Test
  fun `load assignment detail success stores detail`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignmentsAndDetail())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.loadAssignmentDetail("1", "101")
    advanceUntilIdle()

    val detail = viewModel.uiState.value.assignmentDetail
    assertEquals("101", detail?.assignmentId)
    assertEquals("设计说明", detail?.problems?.firstOrNull()?.name)
    assertNull(viewModel.uiState.value.detailError)
  }

  @Test
  fun `clear assignment detail resets detail state`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignmentsAndDetail())

    viewModel.loadAssignmentDetail("1", "101")
    advanceUntilIdle()
    viewModel.clearAssignmentDetail()

    val state = viewModel.uiState.value
    assertNull(state.assignmentDetail)
    assertNull(state.detailError)
    assertTrue(!state.isDetailLoading)
  }

  private fun createViewModel(api: JudgeApi): JudgeViewModel {
    return JudgeViewModel(api, nowProvider = { FIXED_NOW })
  }

  private fun setMainDispatcher(testScheduler: TestCoroutineScheduler) {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
  }

  private fun apiWithAssignments(): JudgeApi =
      object : JudgeApi() {
        override suspend fun getAssignments(): Result<JudgeAssignmentsResponse> {
          return Result.success(
              JudgeAssignmentsResponse(
                  assignments =
                      listOf(
                          JudgeAssignmentSummaryDto(
                              courseId = "1",
                              courseName = "软件工程",
                              assignmentId = "101",
                              title = "设计作业",
                              startTime = "2026-04-20 19:00:00",
                              dueTime = "2026-05-03 23:00:00",
                              maxScore = "100",
                              myScore = "60",
                              totalProblems = 2,
                              submittedCount = 1,
                              submissionStatus = JudgeSubmissionStatus.PARTIAL,
                              submissionStatusText = "进行中(1/2)",
                          ),
                          JudgeAssignmentSummaryDto(
                              courseId = "2",
                              courseName = "算法设计",
                              assignmentId = "102",
                              title = "编程作业",
                              startTime = "2026-04-15 08:00:00",
                              dueTime = "2026-05-10 23:00:00",
                              maxScore = "20",
                              myScore = null,
                              totalProblems = 1,
                              submittedCount = 0,
                              submissionStatus = JudgeSubmissionStatus.UNSUBMITTED,
                              submissionStatusText = "未提交",
                          ),
                          JudgeAssignmentSummaryDto(
                              courseId = "3",
                              courseName = "数据库",
                              assignmentId = "103",
                              title = "已截止作业",
                              startTime = "2026-04-01 08:00:00",
                              dueTime = "2026-04-10 23:00:00",
                              maxScore = "10",
                              myScore = "10",
                              totalProblems = 1,
                              submittedCount = 1,
                              submissionStatus = JudgeSubmissionStatus.SUBMITTED,
                              submissionStatusText = "已完成 10/10",
                          ),
                      )
              )
          )
        }
      }

  private fun apiWithAssignmentsAndDetail(): JudgeApi =
      object : JudgeApi() {
        override suspend fun getAssignments(): Result<JudgeAssignmentsResponse> =
            apiWithAssignments().getAssignments()

        override suspend fun getAssignmentDetail(
            courseId: String,
            assignmentId: String,
        ): Result<JudgeAssignmentDetailDto> {
          return Result.success(
              JudgeAssignmentDetailDto(
                  courseId = courseId,
                  courseName = "软件工程",
                  assignmentId = assignmentId,
                  title = "设计作业",
                  startTime = "2026-04-20 19:00:00",
                  dueTime = "2026-05-03 23:00:00",
                  maxScore = "100",
                  myScore = "60",
                  totalProblems = 2,
                  submittedCount = 1,
                  submissionStatus = JudgeSubmissionStatus.PARTIAL,
                  submissionStatusText = "进行中(1/2)",
                  problems =
                      listOf(
                          JudgeProblemDto(
                              name = "设计说明",
                              score = "60",
                              maxScore = "60",
                              status = JudgeSubmissionStatus.SUBMITTED,
                              statusText = "已提交",
                          )
                      ),
              )
          )
        }
      }

  companion object {
    private val FIXED_NOW = LocalDateTime.parse("2026-05-01T12:00:00")
  }
}
