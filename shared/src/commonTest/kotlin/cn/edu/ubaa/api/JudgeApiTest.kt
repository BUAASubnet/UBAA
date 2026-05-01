package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.JudgeAssignmentDetailDto
import cn.edu.ubaa.model.dto.JudgeAssignmentSummaryDto
import cn.edu.ubaa.model.dto.JudgeAssignmentsResponse
import cn.edu.ubaa.model.dto.JudgeProblemDto
import cn.edu.ubaa.model.dto.JudgeSubmissionStatus
import com.russhwolf.settings.MapSettings
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class JudgeApiTest {
  private val json = Json { ignoreUnknownKeys = true }

  @BeforeTest
  fun setup() {
    AuthTokensStore.settings = MapSettings()
    ClientIdStore.settings = MapSettings()
  }

  @Test
  fun shouldReturnAssignmentsWhenGetAssignmentsSuccess() = runTest {
    val mockEngine = MockEngine { request ->
      assertEquals("/api/v1/judge/assignments", request.url.encodedPath)
      respond(
          content =
              ByteReadChannel(
                  json.encodeToString(
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
                                  )
                              )
                      )
                  )
              ),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    val api = JudgeApi(ApiClient(mockEngine))

    val result = api.getAssignments()

    assertTrue(result.isSuccess)
    assertEquals("设计作业", result.getOrNull()?.assignments?.firstOrNull()?.title)
  }

  @Test
  fun shouldReturnAssignmentDetailWhenGetAssignmentDetailSuccess() = runTest {
    val mockEngine = MockEngine { request ->
      assertEquals("/api/v1/judge/courses/1/assignments/101", request.url.encodedPath)
      respond(
          content =
              ByteReadChannel(
                  json.encodeToString(
                      JudgeAssignmentDetailDto(
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
              ),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    val api = JudgeApi(ApiClient(mockEngine))

    val result = api.getAssignmentDetail("1", "101")

    assertTrue(result.isSuccess)
    assertEquals("101", result.getOrNull()?.assignmentId)
    assertEquals("设计说明", result.getOrNull()?.problems?.firstOrNull()?.name)
  }
}
