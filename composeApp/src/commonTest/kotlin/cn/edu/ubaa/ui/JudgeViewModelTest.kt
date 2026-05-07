package cn.edu.ubaa.ui

import cn.edu.ubaa.api.feature.JudgeApi
import cn.edu.ubaa.model.dto.JudgeAssignmentDetailDto
import cn.edu.ubaa.model.dto.JudgeAssignmentDetailKeyDto
import cn.edu.ubaa.model.dto.JudgeAssignmentDetailsResponse
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
    val api = apiWithAssignments()
    val viewModel = createViewModel(api)

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()

    val state = viewModel.uiState.value
    assertNull(state.error)
    assertEquals(3, state.assignmentsResponse?.assignments?.size)
    assertTrue(state.showOnlyUnfinished)
    assertEquals(listOf("101", "102"), state.visibleAssignments.map { it.assignmentId })
    assertEquals(
        listOf(listOf("1:101", "2:102", "3:103")),
        api.batchDetailRequests,
    )
    assertEquals(
        emptyList(),
        api.detailRequests,
    )
    assertEquals(
        listOf("2026-05-03 23:00:00", "2026-05-10 23:00:00"),
        state.visibleAssignments.map { it.dueTime },
    )
  }

  @Test
  fun `assignment detail enrichment requests fixed size batches`() = runTest {
    setMainDispatcher(testScheduler)
    val api = RecordingJudgeApi(assignmentCount = 25)
    val viewModel = createViewModel(api)

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()

    assertEquals(listOf(12, 12, 1), api.batchDetailRequests.map { it.size })
    assertEquals(emptyList(), api.detailRequests)
  }

  @Test
  fun `assignment detail enrichment skips complete summaries`() = runTest {
    setMainDispatcher(testScheduler)
    val api = RecordingJudgeApi(assignments = detailBackedAssignments())
    val viewModel = createViewModel(api)

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()

    assertTrue(!viewModel.uiState.value.isEnrichingAssignments)
    assertEquals(emptyList(), api.batchDetailRequests)
    assertEquals(emptyList(), api.detailRequests)
    assertEquals(
        listOf("101", "102"),
        viewModel.uiState.value.visibleAssignments.map { it.assignmentId },
    )
  }

  @Test
  fun `assignment detail enrichment only requests incomplete summaries`() = runTest {
    setMainDispatcher(testScheduler)
    val api = RecordingJudgeApi(assignments = partiallyBackedAssignments())
    val viewModel = createViewModel(api)

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()

    assertEquals(listOf(listOf("2:102", "3:103")), api.batchDetailRequests)
    assertEquals(emptyList(), api.detailRequests)
  }

  @Test
  fun `assignment detail enrichment falls back to single details when batch fails`() = runTest {
    setMainDispatcher(testScheduler)
    val api = RecordingJudgeApi(shouldFailBatchDetails = true)
    val viewModel = createViewModel(api)

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()

    assertEquals(listOf(listOf("1:101", "2:102", "3:103")), api.batchDetailRequests)
    assertEquals(listOf("1:101", "2:102", "3:103"), api.detailRequests)
    assertEquals(
        listOf("101", "102"),
        viewModel.uiState.value.visibleAssignments.map { it.assignmentId },
    )
  }

  @Test
  fun `show all filters exposes summaries when detail enrichment is unavailable`() = runTest {
    setMainDispatcher(testScheduler)
    val api = RecordingJudgeApi(shouldFailBatchDetails = true, shouldFailSingleDetails = true)
    val viewModel = createViewModel(api)

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.setShowOnlyUnfinished(false)
    viewModel.setShowExpired(true)

    assertEquals(3, viewModel.uiState.value.assignmentsResponse?.assignments?.size)
    assertEquals(
        listOf("103", "102", "101"),
        viewModel.uiState.value.visibleAssignments.map { it.assignmentId },
    )
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
    viewModel.setShowOnlyUnfinished(false)
    viewModel.setShowExpired(true)

    assertEquals(
        listOf("103", "101", "102"),
        viewModel.uiState.value.visibleAssignments.map { it.assignmentId },
    )
  }

  @Test
  fun `show expired disables unfinished filter and exposes submitted expired assignments`() =
      runTest {
        setMainDispatcher(testScheduler)
        val viewModel = createViewModel(apiWithAssignments())

        viewModel.ensureAssignmentsLoaded()
        advanceUntilIdle()
        viewModel.setShowExpired(true)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(!state.showOnlyUnfinished)
        assertEquals(
            listOf("103", "101", "102"),
            state.visibleAssignments.map { it.assignmentId },
        )
      }

  @Test
  fun `unfinished filter cannot be reenabled while expired assignments are shown`() = runTest {
    setMainDispatcher(testScheduler)
    val viewModel = createViewModel(apiWithAssignments())

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.setShowExpired(true)
    viewModel.setShowOnlyUnfinished(true)
    advanceUntilIdle()

    val state = viewModel.uiState.value
    assertTrue(!state.showOnlyUnfinished)
    assertEquals(
        listOf("103", "101", "102"),
        state.visibleAssignments.map { it.assignmentId },
    )
  }

  @Test
  fun `enabling show expired refreshes assignments with expired flag`() = runTest {
    setMainDispatcher(testScheduler)
    val api = RecordingJudgeApi()
    val viewModel = createViewModel(api)

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.setShowExpired(true)
    advanceUntilIdle()

    assertEquals(listOf(false, true), api.assignmentRequests)
  }

  @Test
  fun `load assignment detail success stores detail`() = runTest {
    setMainDispatcher(testScheduler)
    val api = apiWithAssignmentsAndDetail()
    val viewModel = createViewModel(api)

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.loadAssignmentDetail("1", "101")
    advanceUntilIdle()

    val detail = viewModel.uiState.value.assignmentDetail
    assertEquals("101", detail?.assignmentId)
    assertEquals("设计说明", detail?.problems?.firstOrNull()?.name)
    assertNull(viewModel.uiState.value.detailError)
    assertEquals(emptyList(), api.detailRequests)
  }

  @Test
  fun `refresh clears cached assignment details`() = runTest {
    setMainDispatcher(testScheduler)
    val api = apiWithAssignmentsAndDetail()
    val viewModel = createViewModel(api)

    viewModel.ensureAssignmentsLoaded()
    advanceUntilIdle()
    viewModel.loadAssignmentDetail("1", "101")
    advanceUntilIdle()
    assertEquals(emptyList(), api.detailRequests)

    api.shouldReturnBatchDetails = false
    viewModel.loadAssignments(refresh = true)
    advanceUntilIdle()
    val detailRequestsAfterRefresh = api.detailRequests.toList()
    viewModel.loadAssignmentDetail("1", "101")
    advanceUntilIdle()

    assertEquals(listOf("1:101", "2:102", "3:103"), detailRequestsAfterRefresh)
    assertEquals(detailRequestsAfterRefresh, api.detailRequests)
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

  private fun apiWithAssignments(): RecordingJudgeApi = RecordingJudgeApi()

  private inner class RecordingJudgeApi(
      private val assignmentCount: Int = 3,
      private val assignments: List<JudgeAssignmentSummaryDto>? = null,
      var shouldReturnBatchDetails: Boolean = true,
      private val shouldFailBatchDetails: Boolean = false,
      private val shouldFailSingleDetails: Boolean = false,
  ) : JudgeApi() {
    val assignmentRequests = mutableListOf<Boolean>()
    val detailRequests = mutableListOf<String>()
    val batchDetailRequests = mutableListOf<List<String>>()

    override suspend fun getAssignments(
        includeExpired: Boolean,
        userKey: String?,
    ): Result<JudgeAssignmentsResponse> {
      assignmentRequests += includeExpired
      return Result.success(
          JudgeAssignmentsResponse(assignments = assignments ?: testAssignments(assignmentCount))
      )
    }

    override suspend fun getAssignmentDetail(
        courseId: String,
        assignmentId: String,
    ): Result<JudgeAssignmentDetailDto> {
      detailRequests += "$courseId:$assignmentId"
      if (shouldFailSingleDetails) {
        return Result.failure(IllegalStateException("single unavailable"))
      }
      return Result.success(detailFor(courseId, assignmentId))
    }

    override suspend fun getAssignmentDetails(
        keys: List<JudgeAssignmentDetailKeyDto>
    ): Result<JudgeAssignmentDetailsResponse> {
      batchDetailRequests += keys.map { "${it.courseId}:${it.assignmentId}" }
      if (shouldFailBatchDetails) {
        return Result.failure(IllegalStateException("batch unavailable"))
      }
      if (!shouldReturnBatchDetails) {
        return Result.success(JudgeAssignmentDetailsResponse(emptyList()))
      }
      return Result.success(
          JudgeAssignmentDetailsResponse(
              details = keys.distinct().map { detailFor(it.courseId, it.assignmentId) }
          )
      )
    }
  }

  private fun testAssignments(count: Int): List<JudgeAssignmentSummaryDto> {
    val baseAssignments =
        listOf(
            JudgeAssignmentSummaryDto(
                courseId = "1",
                courseName = "软件工程",
                assignmentId = "101",
                title = "设计作业",
                submissionStatus = JudgeSubmissionStatus.UNKNOWN,
                submissionStatusText = "未知状态",
            ),
            JudgeAssignmentSummaryDto(
                courseId = "2",
                courseName = "算法设计",
                assignmentId = "102",
                title = "编程作业",
                submissionStatus = JudgeSubmissionStatus.UNKNOWN,
                submissionStatusText = "未知状态",
            ),
            JudgeAssignmentSummaryDto(
                courseId = "3",
                courseName = "数据库",
                assignmentId = "103",
                title = "已截止作业",
                submissionStatus = JudgeSubmissionStatus.UNKNOWN,
                submissionStatusText = "未知状态",
            ),
        )
    if (count <= baseAssignments.size) return baseAssignments.take(count)
    return baseAssignments +
        (4..count).map { index ->
          JudgeAssignmentSummaryDto(
              courseId = "course-$index",
              courseName = "课程$index",
              assignmentId = "assignment-$index",
              title = "批量作业$index",
              submissionStatus = JudgeSubmissionStatus.UNKNOWN,
              submissionStatusText = "未知状态",
          )
        }
  }

  private fun detailBackedAssignments(): List<JudgeAssignmentSummaryDto> =
      listOf(
          detailBackedAssignment(
              courseId = "1",
              courseName = "软件工程",
              assignmentId = "101",
              title = "设计作业",
              startTime = "2026-04-20 19:00:00",
              dueTime = "2026-05-03 23:00:00",
              submissionStatus = JudgeSubmissionStatus.PARTIAL,
              submissionStatusText = "进行中(1/2)",
          ),
          detailBackedAssignment(
              courseId = "2",
              courseName = "算法设计",
              assignmentId = "102",
              title = "编程作业",
              startTime = "2026-04-15 08:00:00",
              dueTime = "2026-05-10 23:00:00",
              submissionStatus = JudgeSubmissionStatus.UNSUBMITTED,
              submissionStatusText = "未提交",
          ),
      )

  private fun partiallyBackedAssignments(): List<JudgeAssignmentSummaryDto> =
      listOf(
          detailBackedAssignment(
              courseId = "1",
              courseName = "软件工程",
              assignmentId = "101",
              title = "设计作业",
              startTime = "2026-04-20 19:00:00",
              dueTime = "2026-05-03 23:00:00",
              submissionStatus = JudgeSubmissionStatus.PARTIAL,
              submissionStatusText = "进行中(1/2)",
          ),
          detailBackedAssignment(
              courseId = "2",
              courseName = "算法设计",
              assignmentId = "102",
              title = "编程作业",
              startTime = "2026-04-15 08:00:00",
              dueTime = null,
              submissionStatus = JudgeSubmissionStatus.UNSUBMITTED,
              submissionStatusText = "未提交",
          ),
          detailBackedAssignment(
              courseId = "3",
              courseName = "数据库",
              assignmentId = "103",
              title = "状态未知作业",
              startTime = "2026-04-01 08:00:00",
              dueTime = "2026-04-10 23:00:00",
              submissionStatus = JudgeSubmissionStatus.UNKNOWN,
              submissionStatusText = "未知状态",
          ),
      )

  private fun detailBackedAssignment(
      courseId: String,
      courseName: String,
      assignmentId: String,
      title: String,
      startTime: String?,
      dueTime: String?,
      submissionStatus: JudgeSubmissionStatus,
      submissionStatusText: String,
  ): JudgeAssignmentSummaryDto =
      JudgeAssignmentSummaryDto(
          courseId = courseId,
          courseName = courseName,
          assignmentId = assignmentId,
          title = title,
          startTime = startTime,
          dueTime = dueTime,
          maxScore = "100",
          myScore = null,
          totalProblems = 2,
          submittedCount = 1,
          submissionStatus = submissionStatus,
          submissionStatusText = submissionStatusText,
      )

  private fun detailFor(courseId: String, assignmentId: String): JudgeAssignmentDetailDto =
      when (assignmentId) {
        "101" ->
            detail(
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
            )
        "102" ->
            detail(
                courseId = courseId,
                courseName = "算法设计",
                assignmentId = assignmentId,
                title = "编程作业",
                startTime = "2026-04-15 08:00:00",
                dueTime = "2026-05-10 23:00:00",
                maxScore = "20",
                myScore = null,
                totalProblems = 1,
                submittedCount = 0,
                submissionStatus = JudgeSubmissionStatus.UNSUBMITTED,
                submissionStatusText = "未提交",
            )
        else ->
            detail(
                courseId = courseId,
                courseName = "数据库",
                assignmentId = assignmentId,
                title = "已截止作业",
                startTime = "2026-04-01 08:00:00",
                dueTime = "2026-04-10 23:00:00",
                maxScore = "10",
                myScore = "10",
                totalProblems = 1,
                submittedCount = 1,
                submissionStatus = JudgeSubmissionStatus.SUBMITTED,
                submissionStatusText = "已完成 10/10",
            )
      }

  private fun apiWithAssignmentsAndDetail(): RecordingJudgeApi = RecordingJudgeApi()

  private fun detail(
      courseId: String,
      courseName: String,
      assignmentId: String,
      title: String,
      startTime: String,
      dueTime: String,
      maxScore: String,
      myScore: String?,
      totalProblems: Int,
      submittedCount: Int,
      submissionStatus: JudgeSubmissionStatus,
      submissionStatusText: String,
  ): JudgeAssignmentDetailDto =
      JudgeAssignmentDetailDto(
          courseId = courseId,
          courseName = courseName,
          assignmentId = assignmentId,
          title = title,
          startTime = startTime,
          dueTime = dueTime,
          maxScore = maxScore,
          myScore = myScore,
          totalProblems = totalProblems,
          submittedCount = submittedCount,
          submissionStatus = submissionStatus,
          submissionStatusText = submissionStatusText,
          problems =
              listOf(
                  JudgeProblemDto(
                      name = "设计说明",
                      score = myScore,
                      maxScore = maxScore,
                      status = submissionStatus,
                      statusText = submissionStatusText,
                  )
              ),
      )

  companion object {
    private val FIXED_NOW = LocalDateTime.parse("2026-05-01T12:00:00")
  }
}
