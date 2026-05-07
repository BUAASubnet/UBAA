package cn.edu.ubaa.api

import cn.edu.ubaa.api.core.ApiClient
import cn.edu.ubaa.api.feature.SpocApi
import cn.edu.ubaa.api.storage.AuthTokensStore
import cn.edu.ubaa.api.storage.ClientIdStore
import cn.edu.ubaa.model.dto.SpocAssignmentDetailDto
import cn.edu.ubaa.model.dto.SpocAssignmentSummaryDto
import cn.edu.ubaa.model.dto.SpocAssignmentsResponse
import cn.edu.ubaa.model.dto.SpocSubmissionStatus
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
import kotlinx.serialization.json.Json

class SpocApiTest {
  private val json = Json { ignoreUnknownKeys = true }

  @BeforeTest
  fun setup() {
    AuthTokensStore.settings = MapSettings()
    ClientIdStore.settings = MapSettings()
  }

  @Test
  fun shouldReturnAssignmentsWhenGetAssignmentsSuccess() = runTest {
    val mockEngine = MockEngine { request ->
      assertEquals("/api/v1/spoc/assignments", request.url.encodedPath)
      respond(
          content =
              ByteReadChannel(
                  json.encodeToString(
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
                                      title = "作业 1",
                                      startTime = "2026-03-10 00:00:00",
                                      dueTime = "2026-03-16 18:00:00",
                                      score = "100",
                                      submissionStatus = SpocSubmissionStatus.SUBMITTED,
                                      submissionStatusText = "已提交",
                                  )
                              ),
                      )
                  )
              ),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    val api = SpocApi(ApiClient(mockEngine))

    val result = api.getAssignments()

    assertTrue(result.isSuccess)
    val response = result.getOrNull()
    assertEquals("2025-20262", response?.termCode)
    assertEquals(1, response?.assignments?.size)
    assertEquals("作业 1", response?.assignments?.firstOrNull()?.title)
  }

  @Test
  fun shouldReturnAssignmentDetailWhenGetAssignmentDetailSuccess() = runTest {
    val mockEngine = MockEngine { request ->
      assertEquals("/api/v1/spoc/assignments/a1", request.url.encodedPath)
      respond(
          content =
              ByteReadChannel(
                  json.encodeToString(
                      SpocAssignmentDetailDto(
                          assignmentId = "a1",
                          courseId = "c1",
                          courseName = "操作系统",
                          teacherName = "牛虹婷",
                          title = "作业 1",
                          startTime = "2026-03-10 00:00:00",
                          dueTime = "2026-03-16 18:00:00",
                          score = "100",
                          submissionStatus = SpocSubmissionStatus.UNSUBMITTED,
                          submissionStatusText = "未提交",
                          contentPlainText = "请提交 PDF",
                          contentHtml = "<p>请提交 PDF</p>",
                          submittedAt = null,
                      )
                  )
              ),
          status = HttpStatusCode.OK,
          headers = headersOf(HttpHeaders.ContentType, "application/json"),
      )
    }

    val api = SpocApi(ApiClient(mockEngine))

    val result = api.getAssignmentDetail("a1")

    assertTrue(result.isSuccess)
    val response = result.getOrNull()
    assertEquals("a1", response?.assignmentId)
    assertEquals("请提交 PDF", response?.contentPlainText)
    assertEquals(SpocSubmissionStatus.UNSUBMITTED, response?.submissionStatus)
  }
}
